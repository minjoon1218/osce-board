-- 오스키실 예약판 · 업데이트 018
-- 식사 시간 비는 걸 줄이기:
--   1) 식사 시간 할인: meal_windows 시간대(기본 12:00–13:00, 17:00–19:00)에 쓴 시간은 하루 상한에 factor(기본 0.5)만 차감
--   2) 당일 빈자리 개방: 오늘, 지금부터 walkin_min(기본 120분) 안에 시작하는 조장 신청은 하루 상한에 안 들어감 (bookings.walkin)
--      동시 방 수·같은 방 연속 3시간은 그대로 적용
-- 017 다음에 실행

-- 1) 설정 ------------------------------------------------------------------
create table if not exists public.meal_windows (
  id        serial primary key,
  start_min int not null check (start_min between 420 and 1380),
  end_min   int not null check (end_min between 420 and 1380 and end_min > start_min),
  factor    numeric not null default 0.5 check (factor between 0 and 1)
);
alter table public.meal_windows enable row level security;
drop policy if exists "read meal_windows" on public.meal_windows;
create policy "read meal_windows" on public.meal_windows for select using (true);
insert into public.meal_windows (start_min, end_min, factor)
select * from (values (720, 780, 0.5), (1020, 1140, 0.5)) v
where not exists (select 1 from public.meal_windows);

create table if not exists public.rule_cfg (key text primary key, val int not null);
alter table public.rule_cfg enable row level security;
drop policy if exists "read rule_cfg" on public.rule_cfg;
create policy "read rule_cfg" on public.rule_cfg for select using (true);
insert into public.rule_cfg values ('walkin_min', 120) on conflict do nothing;

alter table public.bookings add column if not exists walkin boolean not null default false;

-- 2) 계산 함수 -------------------------------------------------------------
-- 상한에 차감되는 분: 식사 시간과 겹치는 부분은 factor만
create or replace function public.charge_min(p_start int, p_end int) returns numeric
language sql stable security definer set search_path = public as $$
  select (p_end - p_start) - coalesce(sum(greatest(0, least(p_end, w.end_min) - greatest(p_start, w.start_min)) * (1 - w.factor)), 0)
    from public.meal_windows w;
$$;

-- 오늘, 지금부터 walkin_min 안에 시작하면 당일 빈자리
create or replace function public.is_walkin(p_date date, p_start int) returns boolean
language sql stable security definer set search_path = public as $$
  select p_date = (now() at time zone 'Asia/Seoul')::date
     and p_start <= extract(hour from now() at time zone 'Asia/Seoul')::int * 60
                  + extract(minute from now() at time zone 'Asia/Seoul')::int
                  + coalesce((select val from public.rule_cfg where key = 'walkin_min'), 120);
$$;

drop function if exists public.unit_used(text, date, uuid);
create function public.unit_used(p_unit text, p_date date, p_exclude uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(public.charge_min(b.start_min, b.end_min)), 0) from public.bookings b
   where b.date = p_date and b.id is distinct from p_exclude and not b.walkin and public.unit_of(b.team) = p_unit;
$$;

drop function if exists public.check_unit_limits(text, date, int, int, int, uuid);
create or replace function public.check_unit_limits(p_team text, p_date date, p_room int, p_start int, p_end int, p_exclude uuid, p_walkin boolean)
returns void language plpgsql stable security definer set search_path = public as $$
declare u text := public.unit_of(p_team); mr int;
begin
  if not p_walkin and public.unit_used(u, p_date, p_exclude) + public.charge_min(p_start, p_end) > public.unit_cap(u, p_date) then
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

-- 3) 신청 / 변경 / 연장 ------------------------------------------------------
create or replace function public.create_booking(
  p_code text, p_date date, p_room int, p_start int, p_dur int,
  p_day text, p_content text, p_kits text[], p_team text default null
) returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_team text; v_admin boolean; v_row public.bookings; v_walk boolean := false;
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
    v_walk := public.is_walkin(p_date, p_start);
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
    perform public.check_unit_limits(v_team, p_date, p_room, p_start, p_start + p_dur, null, v_walk);
  end if;
  if coalesce(array_length(p_kits,1),0) > 0 and exists (
     select 1 from public.bookings b
      where b.date = p_date and b.kits && p_kits
        and int4range(b.start_min,b.end_min) && int4range(p_start,p_start+p_dur)) then
    raise exception 'KIT_TAKEN';
  end if;
  insert into public.bookings(date,room,start_min,end_min,day_label,team,content,kits,walkin)
  values (p_date,p_room,p_start,p_start+p_dur,coalesce(p_day,''),v_team,coalesce(p_content,''),coalesce(p_kits,'{}'),v_walk)
  returning * into v_row;
  return v_row;
end $$;

create or replace function public.update_booking(
  p_code text, p_id uuid, p_date date, p_room int, p_start int, p_dur int,
  p_day text, p_content text, p_kits text[], p_team text default null
) returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_team text; v_admin boolean; b public.bookings; v_row public.bookings;
  v_now timestamp := now() at time zone 'Asia/Seoul';
  v_nowmin int := extract(hour from v_now)::int * 60 + extract(minute from v_now)::int;
  v_locked boolean := false; v_moved boolean; v_walk boolean := false;
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
    v_walk := public.is_walkin(p_date, p_start);
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
    perform public.check_unit_limits(v_team, p_date, p_room, p_start, p_start + p_dur, b.id, v_walk);
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
         kits = coalesce(p_kits,'{}'),
         walkin = case when v_moved then (v_walk and not v_admin) else b.walkin end
   where id = b.id
  returning * into v_row;
  return v_row;
end $$;

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
      -- 사용 중 연장 = 당일 빈자리와 같음: 하루 상한은 안 봄, 동시 방·연속 3시간만
      perform public.check_unit_limits(b.team, b.date, b.room, b.start_min, v_end, b.id,
                                       b.walkin or public.is_walkin(b.date, b.end_min));
    end if;
  end if;

  update public.bookings set end_min = v_end where id = b.id returning * into v_row;
  return v_row;
end $$;

-- 4) 관리자 설정 -----------------------------------------------------------
create or replace function public.admin_set_meal(p_code text, p_starts int[], p_ends int[], p_factor numeric)
returns boolean language plpgsql security definer set search_path = public as $$
declare i int;
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  if coalesce(array_length(p_starts,1),0) <> coalesce(array_length(p_ends,1),0) then raise exception 'BAD_RANGE'; end if;
  delete from public.meal_windows where true;
  for i in 1..coalesce(array_length(p_starts,1),0) loop
    insert into public.meal_windows (start_min, end_min, factor) values (p_starts[i], p_ends[i], p_factor);
  end loop;
  return true;
end $$;

create or replace function public.admin_set_cfg(p_code text, p_key text, p_val int)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  if p_key not in ('walkin_min') or p_val < 0 or p_val > 960 then raise exception 'BAD_CFG'; end if;
  insert into public.rule_cfg values (p_key, p_val) on conflict (key) do update set val = excluded.val;
  return true;
end $$;

-- 5) 권한 ---------------------------------------------------------------
do $$ declare f text; begin
  foreach f in array array[
    'charge_min(int,int)','is_walkin(date,int)','unit_used(text,date,uuid)',
    'check_unit_limits(text,date,int,int,int,uuid,boolean)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
  foreach f in array array[
    'create_booking(text,date,int,int,int,text,text,text[],text)',
    'update_booking(text,uuid,date,int,int,int,text,text,text[],text)','adjust_booking(text,uuid,int)',
    'admin_set_meal(text,int[],int[],numeric)','admin_set_cfg(text,text,int)'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;

do $$ begin alter publication supabase_realtime add table public.meal_windows; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.rule_cfg; exception when duplicate_object then null; end $$;
