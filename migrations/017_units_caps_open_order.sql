-- 오스키실 예약판 · 업데이트 017
-- 1) 연습 단위(같이 연습하는 조 묶음)·시험 일차
-- 2) 단위별 하루 상한(방·분), 동시 방 수 상한, 연속 사용 3시간
--    · '하루 2회' 제한 대신 '하루 방·시간 상한' (수업 등으로 막힌 시간만큼 자동 축소)
-- 3) 일차별 신청 오픈 시각: 21:00 1·2일차 → 21:10 3일차 → 21:20 4일차 → 21:30 5일차 → 21:40 나머지
-- 관리자 신청은 모든 상한 예외 (단, 관리자가 넣은 시간도 그 단위 사용량에 포함)

-- ── 1) 조별 일차·연습 단위 ─────────────────────────────────────────────
alter table public.leaders add column if not exists unit text;
alter table public.leaders add column if not exists exam_day int;
update public.leaders set exam_day = nullif(regexp_replace(team, '\D', '', 'g'), '')::int where exam_day is null;
update public.leaders set unit = team where unit is null;
update public.leaders set unit = '1A+1B' where team in ('1A','1B');
update public.leaders set unit = '3A'    where team in ('3A','3B','3C');

-- ── 2) 연습 단위별 상한 ───────────────────────────────────────────────
create table if not exists public.units (
  unit       text primary key,
  people     int,
  max_rooms  int not null default 1 check (max_rooms between 1 and 6),
  daily_min  int not null default 120 check (daily_min between 0 and 5760)   -- 하루 상한 (방·분)
);
alter table public.units enable row level security;
drop policy if exists "read units" on public.units;
create policy "read units" on public.units for select using (true);

insert into public.units (unit, people, max_rooms, daily_min) values
  ('1A+1B', 7, 2, 840), ('2A', 4, 1, 420), ('2B', 3, 1, 300), ('3A', 10, 2, 960),
  ('4A', 3, 1, 240), ('4B', 4, 1, 300), ('5A', 4, 1, 240), ('5B', 4, 1, 240),
  ('6A', null, 1, 240), ('6B', null, 1, 240), ('7', null, 1, 240)
on conflict (unit) do nothing;
insert into public.units (unit, daily_min)
select distinct l.unit, 120 from public.leaders l on conflict (unit) do nothing;

-- ── 3) 일차별 오픈 시각 (21:00 기준 몇 분 뒤) ──────────────────────────────
create table if not exists public.open_offsets (
  exam_day   int primary key,      -- 0 = 나머지 모든 일차
  offset_min int not null check (offset_min between 0 and 180)
);
alter table public.open_offsets enable row level security;
drop policy if exists "read open_offsets" on public.open_offsets;
create policy "read open_offsets" on public.open_offsets for select using (true);
insert into public.open_offsets values (1,0),(2,0),(3,10),(4,20),(5,30),(0,40) on conflict do nothing;

-- ── 계산 함수 ─────────────────────────────────────────────────────────
create or replace function public.unit_of(p_team text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select unit from public.leaders where team = p_team), p_team);
$$;

create or replace function public.open_offset_of(p_team text) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select o.offset_min from public.open_offsets o join public.leaders l on l.exam_day = o.exam_day where l.team = p_team),
    (select offset_min from public.open_offsets where exam_day = 0), 0);
$$;

-- 이 조가 지금 신청할 수 있는 마지막 날짜 (21:00 + 일차별 지연에 다음 날 오픈)
create or replace function public.last_bookable_for(p_team text) returns date
language sql stable security definer set search_path = public as $$
  select greatest(
    (now() at time zone 'Asia/Seoul')::date
      + case when (now() at time zone 'Asia/Seoul')::time >= time '21:00' + make_interval(mins => public.open_offset_of(p_team)) then 1 else 0 end,
    coalesce((select max(date) from public.open_dates where opens_at <= now()), date '1900-01-01'));
$$;

-- 그날 단위의 하루 상한 (방·분): 막힌 시간 비율만큼 줄이고 30분 단위로 내림, 최소 50%
create or replace function public.unit_cap(p_unit text, p_date date) returns int
language sql stable security definer set search_path = public as $$
  with base as (select coalesce((select daily_min from public.units where unit = p_unit), 120) m),
       blk as (select coalesce(sum((least(end_min,1380) - greatest(start_min,420)) * cardinality(rooms)), 0) b
                 from public.blocks where date = p_date)
  select (floor(base.m * greatest(0.5, 1 - blk.b::numeric / (6 * 960)) / 30) * 30)::int from base, blk;
$$;

create or replace function public.unit_used(p_unit text, p_date date, p_exclude uuid) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(sum(b.end_min - b.start_min), 0)::int from public.bookings b
   where b.date = p_date and b.id is distinct from p_exclude and public.unit_of(b.team) = p_unit;
$$;

-- 같은 단위가 같은 방에서 이어서 쓰는 시간 (앞뒤로 딱 붙은 신청까지 합침)
create or replace function public.unit_run(p_unit text, p_date date, p_room int, p_start int, p_end int, p_exclude uuid) returns int
language plpgsql stable security definer set search_path = public as $$
declare s int := p_start; e int := p_end; v int;
begin
  loop
    select b.start_min into v from public.bookings b
     where b.date = p_date and b.room = p_room and b.end_min = s and b.id is distinct from p_exclude and public.unit_of(b.team) = p_unit limit 1;
    exit when v is null; s := v;
  end loop;
  loop
    select b.end_min into v from public.bookings b
     where b.date = p_date and b.room = p_room and b.start_min = e and b.id is distinct from p_exclude and public.unit_of(b.team) = p_unit limit 1;
    exit when v is null; e := v;
  end loop;
  return e - s;
end $$;

-- 조장 신청 공통 검사: 하루 상한·동시 방·연속 3시간
create or replace function public.check_unit_limits(p_team text, p_date date, p_room int, p_start int, p_end int, p_exclude uuid) returns void
language plpgsql stable security definer set search_path = public as $$
declare u text := public.unit_of(p_team); mr int;
begin
  if public.unit_used(u, p_date, p_exclude) + (p_end - p_start) > public.unit_cap(u, p_date) then
    raise exception 'DAILY_CAP';
  end if;
  mr := coalesce((select max_rooms from public.units where unit = u), 1);
  if (select count(*) from public.bookings b
       where b.date = p_date and b.id is distinct from p_exclude and public.unit_of(b.team) = u
         and int4range(b.start_min,b.end_min) && int4range(p_start,p_end)) >= mr then
    raise exception 'TEAM_BUSY';
  end if;
  if public.unit_run(u, p_date, p_room, p_start, p_end, p_exclude) > 180 then
    raise exception 'RUN_LIMIT';
  end if;
end $$;

-- 화면용: 조별 일차·단위·오픈 지연 (코드는 노출 안 함)
create or replace function public.list_team_rules()
returns table(team text, unit text, exam_day int, open_offset int)
language sql stable security definer set search_path = public as $$
  select l.team, coalesce(l.unit, l.team), l.exam_day, public.open_offset_of(l.team) from public.leaders l order by l.team;
$$;

-- ── 신청 ─────────────────────────────────────────────────────────────
create or replace function public.create_booking(
  p_code text, p_date date, p_room int, p_start int, p_dur int,
  p_day text, p_content text, p_kits text[], p_team text default null
) returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_team text; v_admin boolean; v_row public.bookings;
  v_now timestamp := now() at time zone 'Asia/Seoul';
begin
  v_admin := exists (select 1 from public.admins where code = upper(trim(p_code)));
  if v_admin then
    v_team := upper(trim(p_team));
    if v_team is null or not exists (select 1 from public.leaders where team = v_team) then
      raise exception 'BAD_TEAM';
    end if;
  else
    select team into v_team from public.leaders where code = upper(trim(p_code));
    if v_team is null then raise exception 'NOT_LEADER'; end if;
    if p_date < v_now::date
       or (p_date = v_now::date and p_start + p_dur <= extract(hour from v_now)::int*60 + extract(minute from v_now)::int) then
      raise exception 'PAST';
    end if;
    if p_date > public.last_bookable_for(v_team) then raise exception 'TOO_FAR'; end if;
  end if;

  if p_dur is null or p_dur < 30 or p_dur % 30 <> 0 then raise exception 'BAD_DURATION'; end if;
  if not v_admin and p_dur not in (60,120) then raise exception 'BAD_DURATION'; end if;
  if p_start < 420 or p_start + p_dur > 1380 then raise exception 'BAD_RANGE'; end if;
  if not v_admin and exists (select 1 from public.blocks k
             where k.date = p_date and p_room = any(k.rooms) and int4range(k.start_min,k.end_min) && int4range(p_start,p_start+p_dur)) then
    raise exception 'BLOCKED';
  end if;
  if exists (select 1 from public.rooms where room = p_room and not open) then raise exception 'ROOM_CLOSED'; end if;
  if not v_admin then
    perform public.check_unit_limits(v_team, p_date, p_room, p_start, p_start + p_dur, null);
  end if;
  if coalesce(array_length(p_kits,1),0) > 0 and exists (
     select 1 from public.bookings b
      where b.date = p_date and b.kits && p_kits
        and int4range(b.start_min,b.end_min) && int4range(p_start,p_start+p_dur)) then
    raise exception 'KIT_TAKEN';
  end if;
  insert into public.bookings(date,room,start_min,end_min,day_label,team,content,kits)
  values (p_date,p_room,p_start,p_start+p_dur,coalesce(p_day,''),v_team,coalesce(p_content,''),coalesce(p_kits,'{}'))
  returning * into v_row;
  return v_row;
end $$;

-- ── 신청 변경 ─────────────────────────────────────────────────────────
create or replace function public.update_booking(
  p_code text, p_id uuid, p_date date, p_room int, p_start int, p_dur int,
  p_day text, p_content text, p_kits text[], p_team text default null
) returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_team text; v_admin boolean; b public.bookings; v_row public.bookings;
  v_now timestamp := now() at time zone 'Asia/Seoul';
  v_nowmin int := extract(hour from v_now)::int * 60 + extract(minute from v_now)::int;
  v_locked boolean := false; v_moved boolean;
begin
  v_admin := exists (select 1 from public.admins where code = upper(trim(p_code)));
  if not v_admin then
    select team into v_team from public.leaders where code = upper(trim(p_code));
    if v_team is null then raise exception 'NOT_LEADER'; end if;
  end if;

  select * into b from public.bookings where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  v_moved := p_date <> b.date or p_room <> b.room or p_start <> b.start_min or p_start + p_dur <> b.end_min;

  if v_admin then
    v_team := coalesce(nullif(upper(trim(p_team)), ''), b.team);
    if not exists (select 1 from public.leaders where team = v_team) then raise exception 'BAD_TEAM'; end if;
  else
    if b.team <> v_team then raise exception 'NOT_YOURS'; end if;
    if b.date < v_now::date or (b.date = v_now::date and b.end_min <= v_nowmin) then raise exception 'ENDED'; end if;
    v_locked := b.fixed_id is not null or (b.date = v_now::date and b.start_min <= v_nowmin);
    if v_locked and v_moved then
      if b.fixed_id is not null then raise exception 'FIXED_TIME'; else raise exception 'STARTED'; end if;
    end if;
    if not v_locked then
      if p_date < v_now::date or (p_date = v_now::date and p_start <= v_nowmin) then raise exception 'PAST'; end if;
      if p_date > public.last_bookable_for(v_team) and p_date <> b.date then raise exception 'TOO_FAR'; end if;
    end if;
  end if;

  if p_dur is null or p_dur < 30 or p_dur % 30 <> 0 then raise exception 'BAD_DURATION'; end if;
  if not v_admin and not v_locked and p_dur not in (60,120) and p_dur <> b.end_min - b.start_min then raise exception 'BAD_DURATION'; end if;
  if p_start < 420 or p_start + p_dur > 1380 then raise exception 'BAD_RANGE'; end if;

  if not v_admin and not v_locked and v_moved then
    if exists (select 1 from public.blocks k
               where k.date = p_date and p_room = any(k.rooms)
                 and int4range(k.start_min,k.end_min) && int4range(p_start,p_start+p_dur)) then
      raise exception 'BLOCKED';
    end if;
    perform public.check_unit_limits(v_team, p_date, p_room, p_start, p_start + p_dur, b.id);
  end if;
  if p_room <> b.room and exists (select 1 from public.rooms where room = p_room and not open) then
    raise exception 'ROOM_CLOSED';
  end if;
  if coalesce(array_length(p_kits,1),0) > 0 and exists (
     select 1 from public.bookings o
      where o.id <> b.id and o.date = p_date and o.kits && p_kits
        and int4range(o.start_min,o.end_min) && int4range(p_start,p_start+p_dur)) then
    raise exception 'KIT_TAKEN';
  end if;

  update public.bookings
     set date = p_date, room = p_room, start_min = p_start, end_min = p_start + p_dur,
         day_label = coalesce(p_day,''), team = v_team, content = coalesce(p_content,''),
         kits = coalesce(p_kits,'{}')
   where id = b.id
  returning * into v_row;
  return v_row;
end $$;

-- ── 연장·조기 퇴실 ────────────────────────────────────────────────────
create or replace function public.adjust_booking(p_code text, p_id uuid, p_delta int)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_admin boolean; v_team text; b public.bookings; v_row public.bookings;
  v_now timestamp := now() at time zone 'Asia/Seoul';
  v_nowmin int := extract(hour from v_now)::int * 60 + extract(minute from v_now)::int;
  v_end int;
begin
  if p_delta not in (-60, -30, 30, 60) then raise exception 'BAD_DELTA'; end if;
  v_admin := exists (select 1 from public.admins where code = upper(trim(p_code)));
  if not v_admin then
    select team into v_team from public.leaders where code = upper(trim(p_code));
    if v_team is null then raise exception 'NOT_LEADER'; end if;
  end if;

  select * into b from public.bookings where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if not v_admin then
    if b.team <> v_team then raise exception 'NOT_YOURS'; end if;
    if b.date <> v_now::date or v_nowmin < b.start_min or v_nowmin >= b.end_min then
      raise exception 'NOT_IN_USE';
    end if;
  end if;

  v_end := b.end_min + p_delta;
  if p_delta < 0 then
    if v_end <= b.start_min or (not v_admin and v_end <= v_nowmin) then raise exception 'TOO_SHORT'; end if;
  else
    if v_end > 1380 then raise exception 'CLOSE_TIME'; end if;
    if not v_admin and v_end - b.start_min > 180 then raise exception 'TOO_LONG'; end if;
    if coalesce(array_length(b.kits, 1), 0) > 0 and exists (
       select 1 from public.bookings o
        where o.id <> b.id and o.date = b.date and o.kits && b.kits
          and int4range(o.start_min, o.end_min) && int4range(b.end_min, v_end)) then
      raise exception 'KIT_TAKEN';
    end if;
    if not v_admin then
      if exists (select 1 from public.blocks k
                 where k.date = b.date and b.room = any(k.rooms)
                   and int4range(k.start_min, k.end_min) && int4range(b.end_min, v_end)) then
        raise exception 'BLOCKED';
      end if;
      if exists (select 1 from public.rooms where room = b.room and not open) then raise exception 'ROOM_CLOSED'; end if;
      perform public.check_unit_limits(b.team, b.date, b.room, b.start_min, v_end, b.id);
    end if;
  end if;

  update public.bookings set end_min = v_end where id = b.id returning * into v_row;
  return v_row;
end $$;

-- ── 관리자: 조별 일차·단위, 단위 상한, 일차별 오픈 지연 ─────────────────────
create or replace function public.admin_set_team_rule(p_code text, p_team text, p_unit text, p_exam_day int)
returns boolean language plpgsql security definer set search_path = public as $$
declare u text := upper(trim(coalesce(nullif(p_unit,''), p_team)));
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  update public.leaders set unit = u, exam_day = p_exam_day where team = upper(trim(p_team));
  insert into public.units (unit) values (u) on conflict do nothing;
  return found;
end $$;

create or replace function public.admin_set_unit(p_code text, p_unit text, p_people int, p_max_rooms int, p_daily_min int)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  insert into public.units (unit, people, max_rooms, daily_min) values (upper(trim(p_unit)), p_people, p_max_rooms, p_daily_min)
  on conflict (unit) do update set people = excluded.people, max_rooms = excluded.max_rooms, daily_min = excluded.daily_min;
  return true;
end $$;

create or replace function public.admin_set_offset(p_code text, p_exam_day int, p_offset int)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  insert into public.open_offsets values (p_exam_day, p_offset)
  on conflict (exam_day) do update set offset_min = excluded.offset_min;
  return true;
end $$;

-- ── 권한 ─────────────────────────────────────────────────────────────
do $$ declare f text; begin
  foreach f in array array[
    'unit_of(text)','open_offset_of(text)','unit_cap(text,date)','unit_used(text,date,uuid)',
    'unit_run(text,date,int,int,int,uuid)','check_unit_limits(text,date,int,int,int,uuid)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
  foreach f in array array[
    'last_bookable_for(text)','list_team_rules()','create_booking(text,date,int,int,int,text,text,text[],text)',
    'update_booking(text,uuid,date,int,int,int,text,text,text[],text)','adjust_booking(text,uuid,int)',
    'admin_set_team_rule(text,text,text,int)','admin_set_unit(text,text,int,int,int)','admin_set_offset(text,int,int)'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;

do $$ begin alter publication supabase_realtime add table public.units; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.open_offsets; exception when duplicate_object then null; end $$;
