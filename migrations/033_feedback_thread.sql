-- 오스키실 예약판 · 업데이트 033
-- 피드백을 댓글처럼 한 건씩 저장 (여러 명이 써도 덮어쓰지 않음): prac_fb
--   - 조 짜기 기록: (day_id, slot, member_id=푼 사람, problem_id)로 연결 → 조를 다시 저장해도 피드백 유지
--   - 직접 추가 기록: log_id로 연결
--   - author_id: 쓴 사람(선택). 기존 prac_assign.feedback / prac_logs.feedback 내용은 첫 댓글로 옮김

create table if not exists public.prac_fb (
  id         uuid primary key default gen_random_uuid(),
  unit       text not null,
  day_id     uuid references public.prac_days(id) on delete cascade,
  slot       int,
  log_id     uuid references public.prac_logs(id) on delete cascade,
  member_id  uuid not null references public.prac_members(id) on delete cascade,
  problem_id uuid not null references public.prac_problems(id) on delete cascade,
  author_id  uuid references public.prac_members(id) on delete set null,
  text       text not null check (length(text) between 1 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((day_id is not null and slot is not null) or log_id is not null)
);
create index if not exists prac_fb_unit on public.prac_fb(unit);
alter table public.prac_fb enable row level security;
revoke all on public.prac_fb from anon, authenticated;

-- 기존 피드백 옮기기 (한 번만)
insert into public.prac_fb (unit, day_id, slot, member_id, problem_id, text, created_at, updated_at)
select d.unit, d.id, a.slot, a.member_id, a.problem_id, a.feedback, a.updated_at, a.updated_at
  from public.prac_assign a join public.prac_days d on d.id = a.day_id
 where a.feedback <> '' and not exists (select 1 from public.prac_fb f where f.day_id = d.id and f.slot = a.slot and f.member_id = a.member_id and f.problem_id = a.problem_id);
update public.prac_assign set feedback = '' where feedback <> '';
insert into public.prac_fb (unit, log_id, member_id, problem_id, text, created_at, updated_at)
select g.unit, g.id, g.member_id, g.problem_id, g.feedback, g.created_at, g.created_at
  from public.prac_logs g where g.feedback <> '' and not exists (select 1 from public.prac_fb f where f.log_id = g.id);
update public.prac_logs set feedback = '' where feedback <> '';

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
    'logs', (select coalesce(json_agg(g order by g.date, g.created_at), '[]') from public.prac_logs g where g.unit = u),
    'fbs', (select coalesce(json_agg(f order by f.created_at), '[]') from public.prac_fb f where f.unit = u)
  );
end $$;

create or replace function public.prac_add_log(p_code text, p_unit text, p_date date, p_member uuid, p_problem uuid, p_feedback text, p_observers uuid[])
returns json language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit_ro(p_code, p_unit); v_id uuid;
begin
  if not exists (select 1 from public.prac_members where id = p_member and unit = u)
     or not exists (select 1 from public.prac_problems where id = p_problem and unit = u)
     or exists (select 1 from unnest(coalesce(p_observers, '{}')) o where not exists (select 1 from public.prac_members where id = o and unit = u)) then
    raise exception 'BAD_ITEM';
  end if;
  insert into public.prac_logs (unit, date, member_id, problem_id, feedback, observers)
  values (u, p_date, p_member, p_problem, '', array_remove(coalesce(p_observers, '{}'), p_member)) returning id into v_id;
  if length(trim(coalesce(p_feedback, ''))) > 0 then
    insert into public.prac_fb (unit, log_id, member_id, problem_id, text) values (u, v_id, p_member, p_problem, left(trim(p_feedback), 2000));
  end if;
  return public.prac_load(p_code, p_unit);
end $$;

create or replace function public.prac_fb_add(p_code text, p_unit text, p_day uuid, p_slot int, p_log uuid,
                                              p_member uuid, p_problem uuid, p_author uuid, p_text text)
returns json language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit_ro(p_code, p_unit); v public.prac_fb;
begin
  if length(trim(coalesce(p_text, ''))) = 0 then raise exception 'EMPTY'; end if;
  if not exists (select 1 from public.prac_members where id = p_member and unit = u)
     or not exists (select 1 from public.prac_problems where id = p_problem and unit = u)
     or (p_author is not null and not exists (select 1 from public.prac_members where id = p_author and unit = u))
     or (p_day is not null and not exists (select 1 from public.prac_days where id = p_day and unit = u))
     or (p_log is not null and not exists (select 1 from public.prac_logs where id = p_log and unit = u))
     or (p_day is null and p_log is null) then
    raise exception 'BAD_ITEM';
  end if;
  insert into public.prac_fb (unit, day_id, slot, log_id, member_id, problem_id, author_id, text)
  values (u, p_day, case when p_day is null then null else p_slot end, p_log, p_member, p_problem, p_author, left(trim(p_text), 2000))
  returning * into v;
  return row_to_json(v);
end $$;

create or replace function public.prac_fb_edit(p_code text, p_unit text, p_id uuid, p_text text) returns boolean
language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit_ro(p_code, p_unit);
begin
  if length(trim(coalesce(p_text, ''))) = 0 then raise exception 'EMPTY'; end if;
  update public.prac_fb set text = left(trim(p_text), 2000), updated_at = now() where id = p_id and unit = u;
  return found;
end $$;

create or replace function public.prac_fb_del(p_code text, p_unit text, p_id uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit_ro(p_code, p_unit);
begin
  delete from public.prac_fb where id = p_id and unit = u;
  return found;
end $$;

do $$ declare f text; begin
  foreach f in array array['prac_load(text,text)','prac_add_log(text,text,date,uuid,uuid,text,uuid[])',
    'prac_fb_add(text,text,uuid,int,uuid,uuid,uuid,uuid,text)','prac_fb_edit(text,text,uuid,text)','prac_fb_del(text,text,uuid)'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;
