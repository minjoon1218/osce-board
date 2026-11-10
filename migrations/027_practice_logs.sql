-- 오스키실 예약판 · 업데이트 027
-- 기록 탭에서 바로 추가: 조 짜기 없이 한 연습도 (사람·질환·날짜·피드백·같이 본 사람) → 직접 1회 / 같이 본 사람은 피드백 1회
-- 조원 코드로도 추가·수정·삭제 가능. 조 짜기 저장(prac_save_day)과는 따로 저장돼서 서로 안 지워짐

create table if not exists public.prac_logs (
  id         uuid primary key default gen_random_uuid(),
  unit       text not null,
  date       date not null,
  member_id  uuid not null references public.prac_members(id),
  problem_id uuid not null references public.prac_problems(id),
  feedback   text not null default '' check (length(feedback) <= 2000),
  observers  uuid[] not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists prac_logs_unit on public.prac_logs(unit);
alter table public.prac_logs enable row level security;
revoke all on public.prac_logs from anon, authenticated;

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
              ) order by d.date), '[]') from public.prac_days d where d.unit = u),
    'logs', (select coalesce(json_agg(g order by g.date, g.created_at), '[]') from public.prac_logs g where g.unit = u)
  );
end $$;

create or replace function public.prac_save_members(p_code text, p_unit text, p_items json) returns json
language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit(p_code, p_unit); x json; keep uuid[] := '{}'; v_id uuid;
begin
  for x in select * from json_array_elements(coalesce(p_items, '[]')) loop
    v_id := nullif(x->>'id', '')::uuid;
    if v_id is not null and exists (select 1 from public.prac_members where id = v_id and unit = u) then
      update public.prac_members set name = trim(x->>'name'), active = coalesce((x->>'active')::boolean, true), sort = coalesce((x->>'sort')::int, 0) where id = v_id;
    else
      insert into public.prac_members (unit, name, active, sort)
      values (u, trim(x->>'name'), coalesce((x->>'active')::boolean, true), coalesce((x->>'sort')::int, 0)) returning id into v_id;
    end if;
    keep := keep || v_id;
  end loop;
  update public.prac_members m set active = false
   where m.unit = u and not (m.id = any(keep)) and (exists (select 1 from public.prac_assign a where a.member_id = m.id) or exists (select 1 from public.prac_logs g where g.member_id = m.id));
  delete from public.prac_members m
   where m.unit = u and not (m.id = any(keep)) and not (exists (select 1 from public.prac_assign a where a.member_id = m.id) or exists (select 1 from public.prac_logs g where g.member_id = m.id));
  return public.prac_load(p_code, p_unit);
end $$;

create or replace function public.prac_save_problems(p_code text, p_unit text, p_items json) returns json
language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit(p_code, p_unit); x json; keep uuid[] := '{}'; v_id uuid; v_type text; v_no int;
begin
  -- 번호 바꾸기(맞바꾸기 포함) 충돌을 피하려고 일단 큰 번호로 비켜 둠
  update public.prac_problems set no = no + 50 where unit = u and no <= 49;
  for x in select * from json_array_elements(coalesce(p_items, '[]')) loop
    v_id := nullif(x->>'id', '')::uuid; v_type := upper(trim(x->>'type')); v_no := (x->>'no')::int;
    if v_id is not null and exists (select 1 from public.prac_problems where id = v_id and unit = u) then
      update public.prac_problems set type = v_type, no = v_no, name = coalesce(trim(x->>'name'), ''), active = coalesce((x->>'active')::boolean, true) where id = v_id;
    else
      insert into public.prac_problems (unit, type, no, name, active)
      values (u, v_type, v_no, coalesce(trim(x->>'name'), ''), coalesce((x->>'active')::boolean, true)) returning id into v_id;
    end if;
    keep := keep || v_id;
  end loop;
  delete from public.prac_problems p
   where p.unit = u and not (p.id = any(keep)) and not exists (select 1 from public.prac_assign a where a.problem_id = p.id) and not exists (select 1 from public.prac_logs g where g.problem_id = p.id);
  -- 기록 때문에 남겨 둔 질환은 비활성 + 겹치지 않는 번호
  update public.prac_problems p set active = false
   where p.unit = u and not (p.id = any(keep));
  return public.prac_load(p_code, p_unit);
end $$;

create or replace function public.prac_add_log(p_code text, p_unit text, p_date date, p_member uuid, p_problem uuid, p_feedback text, p_observers uuid[])
returns json language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit_ro(p_code, p_unit);
begin
  if not exists (select 1 from public.prac_members where id = p_member and unit = u)
     or not exists (select 1 from public.prac_problems where id = p_problem and unit = u)
     or exists (select 1 from unnest(coalesce(p_observers, '{}')) o where not exists (select 1 from public.prac_members where id = o and unit = u)) then
    raise exception 'BAD_ITEM';
  end if;
  insert into public.prac_logs (unit, date, member_id, problem_id, feedback, observers)
  values (u, p_date, p_member, p_problem, left(coalesce(p_feedback, ''), 2000), array_remove(coalesce(p_observers, '{}'), p_member));
  return public.prac_load(p_code, p_unit);
end $$;

create or replace function public.prac_edit_log(p_code text, p_unit text, p_id uuid, p_feedback text) returns boolean
language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit_ro(p_code, p_unit);
begin
  update public.prac_logs set feedback = left(coalesce(p_feedback, ''), 2000) where id = p_id and unit = u;
  return found;
end $$;

create or replace function public.prac_delete_log(p_code text, p_unit text, p_id uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit_ro(p_code, p_unit);
begin
  delete from public.prac_logs where id = p_id and unit = u;
  return found;
end $$;

do $$ declare f text; begin
  foreach f in array array['prac_load(text,text)','prac_save_members(text,text,json)','prac_save_problems(text,text,json)',
    'prac_add_log(text,text,date,uuid,uuid,text,uuid[])','prac_edit_log(text,text,uuid,text)','prac_delete_log(text,text,uuid)'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;
