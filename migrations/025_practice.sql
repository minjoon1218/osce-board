-- 오스키실 예약판 · 업데이트 025
-- 연습 플랜 개정: 조원·질환 확정 → 날마다 랜덤 조(인원 자유) + 그날 문제 세트 → 1인 1문제 + 나머지 피드백 → 질환별 기록
--   - 데이터는 '묶음(unit)' 단위로 공유 (1A+1B, 3A·3B·3C …). 테이블은 직접 못 읽고, 조장 코드/관리자 코드로 RPC만
--   - 1–N일차 조장만 사용 (rule_cfg.prac_max_day, 기본 4)

create table if not exists public.prac_members (
  id         uuid primary key default gen_random_uuid(),
  unit       text not null,
  name       text not null check (length(trim(name)) between 1 and 20),
  active     boolean not null default true,
  sort       int not null default 0,
  created_at timestamptz not null default now()
);
create table if not exists public.prac_problems (
  id         uuid primary key default gen_random_uuid(),
  unit       text not null,
  type       text not null check (type ~ '^[A-Z]$'),
  no         int  not null check (no between 1 and 99),
  name       text not null default '',
  active     boolean not null default true,
  unique (unit, type, no)
);
create table if not exists public.prac_days (
  id          uuid primary key default gen_random_uuid(),
  unit        text not null,
  date        date not null,
  slots       int  not null default 2 check (slots between 1 and 4),
  problem_set uuid[] not null default '{}',
  skipped     int[]  not null default '{}',
  updated_at  timestamptz not null default now(),
  unique (unit, date)
);
create table if not exists public.prac_assign (
  id         uuid primary key default gen_random_uuid(),
  day_id     uuid not null references public.prac_days(id) on delete cascade,
  slot       int  not null check (slot between 1 and 4),
  grp        int  not null check (grp between 1 and 10),
  ord        int  not null default 1,
  member_id  uuid not null references public.prac_members(id),
  problem_id uuid not null references public.prac_problems(id),
  feedback   text not null default '' check (length(feedback) <= 2000),
  updated_at timestamptz not null default now()
);
create index if not exists prac_assign_day on public.prac_assign(day_id);
create index if not exists prac_members_unit on public.prac_members(unit);

alter table public.prac_members  enable row level security;
alter table public.prac_problems enable row level security;
alter table public.prac_days     enable row level security;
alter table public.prac_assign   enable row level security;
revoke all on public.prac_members, public.prac_problems, public.prac_days, public.prac_assign from anon, authenticated;

insert into public.rule_cfg values ('prac_max_day', 4) on conflict do nothing;

-- 코드 → 묶음 (관리자는 p_unit 지정)
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
  if v_day is null or v_day < 1 or v_day > coalesce((select val from public.rule_cfg where key = 'prac_max_day'), 4) then
    raise exception 'PRAC_CLOSED';
  end if;
  return v_unit;
end $$;

create or replace function public.prac_load(p_code text, p_unit text default null) returns json
language plpgsql stable security definer set search_path = public as $$
declare u text := public.prac_unit(p_code, p_unit);
begin
  return json_build_object(
    'unit', u,
    'teams', (select coalesce(json_agg(team order by team), '[]') from public.leaders where coalesce(unit, team) = u),
    'members', (select coalesce(json_agg(m order by m.sort, m.created_at), '[]') from public.prac_members m where m.unit = u),
    'problems', (select coalesce(json_agg(p order by p.type, p.no), '[]') from public.prac_problems p where p.unit = u),
    'days', (select coalesce(json_agg(json_build_object(
                'id', d.id, 'date', d.date, 'slots', d.slots, 'problem_set', d.problem_set, 'skipped', d.skipped,
                'assigns', (select coalesce(json_agg(a order by a.slot, a.grp, a.ord), '[]') from public.prac_assign a where a.day_id = d.id)
              ) order by d.date), '[]') from public.prac_days d where d.unit = u)
  );
end $$;

-- 조원: [{id?, name, active, sort}] 목록 그대로 저장. 목록에서 빠진 사람은 기록이 있으면 '쉬는 중', 없으면 삭제
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
   where m.unit = u and not (m.id = any(keep)) and exists (select 1 from public.prac_assign a where a.member_id = m.id);
  delete from public.prac_members m
   where m.unit = u and not (m.id = any(keep)) and not exists (select 1 from public.prac_assign a where a.member_id = m.id);
  return public.prac_load(p_code, p_unit);
end $$;

-- 질환: [{id?, type, no, name, active}]. 빠진 질환은 기록이 있으면 비활성, 없으면 삭제
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
   where p.unit = u and not (p.id = any(keep)) and not exists (select 1 from public.prac_assign a where a.problem_id = p.id);
  -- 기록 때문에 남겨 둔 질환은 비활성 + 겹치지 않는 번호
  update public.prac_problems p set active = false
   where p.unit = u and not (p.id = any(keep));
  return public.prac_load(p_code, p_unit);
end $$;

-- 하루 저장: 조·문제 배정 통째로 교체. 같은 (타임, 사람, 문제) 줄의 피드백은 이어서 보존
create or replace function public.prac_save_day(p_code text, p_unit text, p_date date, p_slots int, p_set uuid[], p_assigns json)
returns json language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit(p_code, p_unit); v_day uuid; x json;
begin
  insert into public.prac_days (unit, date, slots, problem_set) values (u, p_date, p_slots, coalesce(p_set, '{}'))
  on conflict (unit, date) do update set slots = excluded.slots, problem_set = excluded.problem_set, updated_at = now()
  returning id into v_day;
  create temp table if not exists _prac_old (slot int, member_id uuid, problem_id uuid, feedback text) on commit drop;
  delete from _prac_old;
  insert into _prac_old select slot, member_id, problem_id, feedback from public.prac_assign where day_id = v_day and feedback <> '';
  delete from public.prac_assign where day_id = v_day;
  for x in select * from json_array_elements(coalesce(p_assigns, '[]')) loop
    if not exists (select 1 from public.prac_members where id = (x->>'member_id')::uuid and unit = u)
       or not exists (select 1 from public.prac_problems where id = (x->>'problem_id')::uuid and unit = u) then
      raise exception 'BAD_ITEM';
    end if;
    insert into public.prac_assign (day_id, slot, grp, ord, member_id, problem_id, feedback)
    values (v_day, (x->>'slot')::int, (x->>'grp')::int, coalesce((x->>'ord')::int, 1), (x->>'member_id')::uuid, (x->>'problem_id')::uuid,
            coalesce((select o.feedback from _prac_old o where o.slot = (x->>'slot')::int and o.member_id = (x->>'member_id')::uuid
                        and o.problem_id = (x->>'problem_id')::uuid limit 1), ''));
  end loop;
  return public.prac_load(p_code, p_unit);
end $$;

create or replace function public.prac_feedback(p_code text, p_unit text, p_id uuid, p_text text) returns boolean
language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit(p_code, p_unit);
begin
  update public.prac_assign a set feedback = left(coalesce(p_text, ''), 2000), updated_at = now()
    from public.prac_days d where a.id = p_id and d.id = a.day_id and d.unit = u;
  return found;
end $$;

create or replace function public.prac_skip(p_code text, p_unit text, p_day uuid, p_slot int, p_skip boolean) returns boolean
language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit(p_code, p_unit);
begin
  update public.prac_days set skipped = case when p_skip then array(select distinct unnest(skipped || p_slot) order by 1)
                                             else array_remove(skipped, p_slot) end
   where id = p_day and unit = u;
  return found;
end $$;

create or replace function public.prac_delete_day(p_code text, p_unit text, p_day uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit(p_code, p_unit);
begin
  delete from public.prac_days where id = p_day and unit = u;
  return found;
end $$;

-- 관리자: 연습 플랜을 쓸 수 있는 일차 (1–N일차)
create or replace function public.admin_set_cfg(p_code text, p_key text, p_val int)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  if p_key not in ('walkin_min', 'prac_max_day') or p_val < 0 or p_val > 960 then raise exception 'BAD_CFG'; end if;
  insert into public.rule_cfg values (p_key, p_val) on conflict (key) do update set val = excluded.val;
  return true;
end $$;

revoke all on function public.prac_unit(text,text) from public, anon, authenticated;
do $$ declare f text; begin
  foreach f in array array[
    'prac_load(text,text)','prac_save_members(text,text,json)','prac_save_problems(text,text,json)',
    'prac_save_day(text,text,date,int,uuid[],json)','prac_feedback(text,text,uuid,text)',
    'prac_skip(text,text,uuid,int,boolean)','prac_delete_day(text,text,uuid)','admin_set_cfg(text,text,int)'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;
