-- 오스키실 예약판 · 업데이트 045
-- 1) 타임마다 문제 세트·진행 순서를 따로: prac_days.cfg = {"1":{"rounds":["A","B","C"],"set":[uuid…]}, "2":{…}}
--    진행 순서는 자유 (예: B→B→C). problem_set은 모든 타임 세트를 합친 것(예전 화면 호환)
-- 2) 타임 6개까지 (타임 추가)
-- 3) 조원(링크)도 질환별 관련 케이스 번호를 고칠 수 있게: prac_save_related

alter table public.prac_days add column if not exists cfg jsonb not null default '{}';
alter table public.prac_days drop constraint if exists prac_days_slots_check;
alter table public.prac_days add constraint prac_days_slots_check check (slots between 1 and 6);
alter table public.prac_assign drop constraint if exists prac_assign_slot_check;
alter table public.prac_assign add constraint prac_assign_slot_check check (slot between 1 and 6);

drop function if exists public.prac_save_day(text, text, date, int, uuid[], json);
create or replace function public.prac_save_day(p_code text, p_unit text, p_date date, p_slots int, p_set uuid[], p_assigns json, p_cfg jsonb default null)
returns json language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit(p_code, p_unit); v_day uuid; x json;
begin
  insert into public.prac_days (unit, date, slots, problem_set, cfg) values (u, p_date, p_slots, coalesce(p_set, '{}'), coalesce(p_cfg, '{}'))
  on conflict (unit, date) do update set slots = excluded.slots, problem_set = excluded.problem_set,
     cfg = case when p_cfg is null then public.prac_days.cfg else excluded.cfg end, updated_at = now()
  returning id into v_day;
  delete from public.prac_assign where day_id = v_day;
  for x in select * from json_array_elements(coalesce(p_assigns, '[]')) loop
    if not exists (select 1 from public.prac_members where id = (x->>'member_id')::uuid and unit = u)
       or not exists (select 1 from public.prac_problems where id = (x->>'problem_id')::uuid and unit = u) then
      raise exception 'BAD_ITEM';
    end if;
    insert into public.prac_assign (day_id, slot, grp, ord, member_id, problem_id)
    values (v_day, (x->>'slot')::int, (x->>'grp')::int, coalesce((x->>'ord')::int, 1), (x->>'member_id')::uuid, (x->>'problem_id')::uuid);
  end loop;
  return public.prac_load(p_code, p_unit);
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
                'id', d.id, 'date', d.date, 'slots', d.slots, 'problem_set', d.problem_set, 'skipped', d.skipped, 'cfg', d.cfg,
                'assigns', (select coalesce(json_agg(a order by a.slot, a.grp, a.ord), '[]') from public.prac_assign a where a.day_id = d.id)
              ) order by d.date), '[]') from public.prac_days d where d.unit = u),
    'logs', (select coalesce(json_agg(g order by g.date, g.created_at), '[]') from public.prac_logs g where g.unit = u),
    'fbs', (select coalesce(json_agg(f order by f.created_at), '[]') from public.prac_fb f where f.unit = u)
  );
end $$;

create or replace function public.prac_save_related(p_code text, p_unit text, p_items json) returns json
language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit_ro(p_code, p_unit); x json;
begin
  for x in select * from json_array_elements(coalesce(p_items, '[]')) loop
    update public.prac_problems set related = left(trim(coalesce(x->>'related', '')), 4000)
     where id = (x->>'id')::uuid and unit = u;
  end loop;
  return public.prac_load(p_code, p_unit);
end $$;

do $$ declare f text; begin
  foreach f in array array['prac_save_day(text,text,date,int,uuid[],json,jsonb)','prac_load(text,text)','prac_save_related(text,text,json)'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;
