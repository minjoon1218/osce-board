-- 오스키실 예약판 · 업데이트 026
-- 연습 플랜 전용 '조원 코드' (묶음마다 1개): 조 편성 보기·피드백 쓰기·기록 보기만. 예약판에선 안 먹힘
-- 조원·질환 수정, 조 짜기·저장, 안 함 표시, 기록 지우기는 조장/관리자 코드로만

create table if not exists public.prac_codes (
  unit text primary key,
  code text not null unique
);
alter table public.prac_codes enable row level security;
revoke all on public.prac_codes from anon, authenticated;

create or replace function public.prac_gen_code() returns text
language plpgsql volatile security definer set search_path = public as $$
declare a text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; c text;
begin
  loop
    c := '';
    for i in 1..6 loop c := c || substr(a, 1 + floor(random() * length(a))::int, 1); end loop;
    exit when not exists (select 1 from public.leaders where code = c)
          and not exists (select 1 from public.admins where code = c)
          and not exists (select 1 from public.prac_codes where code = c);
  end loop;
  return c;
end $$;

insert into public.prac_codes (unit, code)
select u, public.prac_gen_code() from (
  select distinct coalesce(unit, team) u from public.leaders
   where exam_day between 1 and coalesce((select val from public.rule_cfg where key = 'prac_max_day'), 4)) s
on conflict do nothing;

-- 읽기·피드백용: 조원 코드도 통과
create or replace function public.prac_unit_ro(p_code text, p_unit text) returns text
language plpgsql stable security definer set search_path = public as $$
declare v_unit text;
begin
  select unit into v_unit from public.prac_codes where code = upper(trim(p_code));
  if v_unit is not null then
    if not exists (select 1 from public.leaders where coalesce(unit, team) = v_unit
                    and exam_day between 1 and coalesce((select val from public.rule_cfg where key = 'prac_max_day'), 4)) then
      raise exception 'PRAC_CLOSED';
    end if;
    return v_unit;
  end if;
  return public.prac_unit(p_code, p_unit);
end $$;

create or replace function public.prac_auth(p_code text) returns json
language plpgsql security definer set search_path = public as $$
declare v_unit text;
begin
  select unit into v_unit from public.prac_codes where code = upper(trim(p_code));
  if v_unit is not null then
    perform public._login_guard('prac_auth', true);
    return json_build_object('role', 'member', 'team', null, 'unit', v_unit);
  end if;
  return public.auth_code(p_code);
end $$;

create or replace function public.prac_load(p_code text, p_unit text default null) returns json
language plpgsql stable security definer set search_path = public as $$
declare u text := public.prac_unit_ro(p_code, p_unit);
        v_member boolean := exists (select 1 from public.prac_codes where code = upper(trim(p_code)));
begin
  return json_build_object(
    'unit', u,
    'role', case when v_member then 'member' else 'leader' end,
    'member_code', case when v_member then null else (select code from public.prac_codes where unit = u) end,
    'teams', (select coalesce(json_agg(team order by team), '[]') from public.leaders where coalesce(unit, team) = u),
    'members', (select coalesce(json_agg(m order by m.sort, m.created_at), '[]') from public.prac_members m where m.unit = u),
    'problems', (select coalesce(json_agg(p order by p.type, p.no), '[]') from public.prac_problems p where p.unit = u),
    'days', (select coalesce(json_agg(json_build_object(
                'id', d.id, 'date', d.date, 'slots', d.slots, 'problem_set', d.problem_set, 'skipped', d.skipped,
                'assigns', (select coalesce(json_agg(a order by a.slot, a.grp, a.ord), '[]') from public.prac_assign a where a.day_id = d.id)
              ) order by d.date), '[]') from public.prac_days d where d.unit = u)
  );
end $$;

create or replace function public.prac_feedback(p_code text, p_unit text, p_id uuid, p_text text) returns boolean
language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit_ro(p_code, p_unit);
begin
  update public.prac_assign a set feedback = left(coalesce(p_text, ''), 2000), updated_at = now()
    from public.prac_days d where a.id = p_id and d.id = a.day_id and d.unit = u;
  return found;
end $$;

-- 조장/관리자: 조원 코드 새로 뽑기 (예전 코드는 바로 막힘)
create or replace function public.prac_reset_code(p_code text, p_unit text default null) returns text
language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit(p_code, p_unit); c text := public.prac_gen_code();
begin
  insert into public.prac_codes (unit, code) values (u, c) on conflict (unit) do update set code = excluded.code;
  return c;
end $$;

revoke all on function public.prac_gen_code() from public, anon, authenticated;
revoke all on function public.prac_unit_ro(text,text) from public, anon, authenticated;
do $$ declare f text; begin
  foreach f in array array['prac_auth(text)','prac_load(text,text)','prac_feedback(text,text,uuid,text)','prac_reset_code(text,text)'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;
