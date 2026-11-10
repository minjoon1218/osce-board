-- 오스키실 예약판 · 업데이트 028
-- 연습 플랜은 3일차만 (rule_cfg prac_min_day ~ prac_max_day = 3~3). 조원은 링크(plan.html?k=조원코드)로 바로 들어옴
insert into public.rule_cfg values ('prac_min_day', 3) on conflict (key) do update set val = excluded.val;
insert into public.rule_cfg values ('prac_max_day', 3) on conflict (key) do update set val = excluded.val;

create or replace function public.prac_day_ok(p_day int) returns boolean
language sql stable security definer set search_path = public as $$
  select p_day is not null
     and p_day >= coalesce((select val from public.rule_cfg where key = 'prac_min_day'), 1)
     and p_day <= coalesce((select val from public.rule_cfg where key = 'prac_max_day'), 4);
$$;

create or replace function public.prac_unit(p_code text, p_unit text) returns text
language plpgsql stable security definer set search_path = public as $$
declare v_team text; v_day int; v_unit text;
begin
  if exists (select 1 from public.admins where code = upper(trim(p_code))) then
    v_unit := upper(trim(coalesce(p_unit, '')));
    if not exists (select 1 from public.leaders where coalesce(unit, team) = v_unit) then raise exception 'BAD_TEAM'; end if;
    return v_unit;
  end if;
  select team, exam_day, coalesce(unit, team) into v_team, v_day, v_unit from public.leaders where code = upper(trim(p_code));
  if v_team is null then raise exception 'NOT_LEADER'; end if;
  if not public.prac_day_ok(v_day) then raise exception 'PRAC_CLOSED'; end if;
  return v_unit;
end $$;

create or replace function public.prac_unit_ro(p_code text, p_unit text) returns text
language plpgsql stable security definer set search_path = public as $$
declare v_unit text;
begin
  select unit into v_unit from public.prac_codes where code = upper(trim(p_code));
  if v_unit is not null then
    if not exists (select 1 from public.leaders where coalesce(unit, team) = v_unit and public.prac_day_ok(exam_day)) then
      raise exception 'PRAC_CLOSED';
    end if;
    return v_unit;
  end if;
  return public.prac_unit(p_code, p_unit);
end $$;

-- 3일차 말고는 조원 코드(링크) 없앰
delete from public.prac_codes where unit <> '3A';

create or replace function public.admin_set_cfg(p_code text, p_key text, p_val int)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  if p_key not in ('walkin_min', 'prac_min_day', 'prac_max_day') or p_val < 0 or p_val > 960 then raise exception 'BAD_CFG'; end if;
  insert into public.rule_cfg values (p_key, p_val) on conflict (key) do update set val = excluded.val;
  return true;
end $$;

revoke all on function public.prac_day_ok(int) from public, anon, authenticated;
revoke all on function public.admin_set_cfg(text,text,int) from public;
grant execute on function public.admin_set_cfg(text,text,int) to anon, authenticated;
