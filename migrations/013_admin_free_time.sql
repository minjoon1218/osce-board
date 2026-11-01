-- 오스키실 예약판 · 업데이트 013
-- 관리자 신청·변경·연장은 사용 시간을 30분 단위로 자유롭게 (08:00–22:00 안, 3시간 넘어도 됨)
-- 조장은 그대로: 신청 1·2시간, 연장 포함 최대 3시간
-- Supabase → SQL Editor에 통째로 붙여넣고 Run (여러 번 실행해도 안전)

alter table public.bookings drop constraint if exists bookings_time_check;
alter table public.bookings add constraint bookings_time_check
  check (end_min <= 1320 and end_min > start_min);

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
    if p_date > public.last_bookable() then raise exception 'TOO_FAR'; end if;
  end if;

  -- 조장은 조당 하루 2회까지 (관리자 대리 신청·고정 시간대는 예외)
  if not v_admin and (select count(*) from public.bookings where date = p_date and team = v_team and fixed_id is null) >= 2 then
    raise exception 'DAILY_LIMIT';
  end if;
  -- 사용 시간: 조장은 1·2시간, 관리자는 30분 단위로 자유롭게 (08:00–22:00 안)
  if p_dur is null or p_dur < 30 or p_dur % 30 <> 0 then raise exception 'BAD_DURATION'; end if;
  if not v_admin and p_dur not in (60,120) then raise exception 'BAD_DURATION'; end if;
  if p_start < 480 or p_start + p_dur > 1320 then raise exception 'BAD_RANGE'; end if;
  if not v_admin and exists (select 1 from public.blocks k
             where k.date = p_date and p_room = any(k.rooms) and int4range(k.start_min,k.end_min) && int4range(p_start,p_start+p_dur)) then
    raise exception 'BLOCKED';
  end if;
  if exists (select 1 from public.rooms where room = p_room and not open) then raise exception 'ROOM_CLOSED'; end if;
  -- 같은 조가 같은 시간에 방 두 개: 조장은 불가, 관리자 대리 신청은 허용
  if not v_admin and exists (select 1 from public.bookings b
             where b.date = p_date and b.team = v_team
               and int4range(b.start_min,b.end_min) && int4range(p_start,p_start+p_dur)) then
    raise exception 'TEAM_BUSY';
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

create or replace function public.update_booking(
  p_code text, p_id uuid, p_date date, p_room int, p_start int, p_dur int,
  p_day text, p_content text, p_kits text[], p_team text default null
) returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_team text; v_admin boolean; b public.bookings; v_row public.bookings;
  v_now timestamp := now() at time zone 'Asia/Seoul';
  v_nowmin int := extract(hour from v_now)::int * 60 + extract(minute from v_now)::int;
begin
  v_admin := exists (select 1 from public.admins where code = upper(trim(p_code)));
  if not v_admin then
    select team into v_team from public.leaders where code = upper(trim(p_code));
    if v_team is null then raise exception 'NOT_LEADER'; end if;
  end if;

  select * into b from public.bookings where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;

  if v_admin then
    v_team := coalesce(nullif(upper(trim(p_team)), ''), b.team);
    if not exists (select 1 from public.leaders where team = v_team) then raise exception 'BAD_TEAM'; end if;
  else
    if b.team <> v_team then raise exception 'NOT_YOURS'; end if;
    if b.fixed_id is not null then raise exception 'FIXED_ONLY_ADMIN'; end if;
    if b.date < v_now::date or (b.date = v_now::date and b.start_min <= v_nowmin) then
      raise exception 'STARTED';
    end if;
    if p_date < v_now::date or (p_date = v_now::date and p_start <= v_nowmin) then raise exception 'PAST'; end if;
    if p_date > public.last_bookable() then raise exception 'TOO_FAR'; end if;
  end if;

  -- 사용 시간: 조장은 1·2시간, 관리자는 30분 단위로 자유롭게 (08:00–22:00 안)
  if p_dur is null or p_dur < 30 or p_dur % 30 <> 0 then raise exception 'BAD_DURATION'; end if;
  if not v_admin and p_dur not in (60,120) and p_dur <> b.end_min - b.start_min then raise exception 'BAD_DURATION'; end if;
  if p_start < 480 or p_start + p_dur > 1320 then raise exception 'BAD_RANGE'; end if;

  if not v_admin and b.fixed_id is null and (select count(*) from public.bookings
      where date = p_date and team = v_team and fixed_id is null and id <> b.id) >= 2 then
    raise exception 'DAILY_LIMIT';
  end if;
  if not v_admin and exists (select 1 from public.blocks k
             where k.date = p_date and p_room = any(k.rooms)
               and int4range(k.start_min,k.end_min) && int4range(p_start,p_start+p_dur)) then
    raise exception 'BLOCKED';
  end if;
  if p_room <> b.room and exists (select 1 from public.rooms where room = p_room and not open) then
    raise exception 'ROOM_CLOSED';
  end if;
  if not v_admin and exists (select 1 from public.bookings o
             where o.id <> b.id and o.date = p_date and o.team = v_team
               and int4range(o.start_min,o.end_min) && int4range(p_start,p_start+p_dur)) then
    raise exception 'TEAM_BUSY';
  end if;
  if coalesce(array_length(p_kits,1),0) > 0 and exists (
     select 1 from public.bookings o
      where o.id <> b.id and o.date = p_date and o.kits && p_kits
        and int4range(o.start_min,o.end_min) && int4range(p_start,p_start+p_dur)) then
    raise exception 'KIT_TAKEN';
  end if;

  -- 같은 방·시간 다른 신청과 겹치면 no_overlap 제약이 23P01로 막음
  update public.bookings
     set date = p_date, room = p_room, start_min = p_start, end_min = p_start + p_dur,
         day_label = coalesce(p_day,''), team = v_team, content = coalesce(p_content,''),
         kits = coalesce(p_kits,'{}')
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
    if v_end > 1320 then raise exception 'CLOSE_TIME'; end if;
    if not v_admin and v_end - b.start_min > 180 then raise exception 'TOO_LONG'; end if;
    if not v_admin and exists (select 1 from public.bookings o
               where o.id <> b.id and o.date = b.date and o.team = b.team
                 and int4range(o.start_min, o.end_min) && int4range(b.end_min, v_end)) then
      raise exception 'TEAM_BUSY';
    end if;
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
    end if;
  end if;

  -- 같은 방 다음 신청과 겹치면 no_overlap 제약이 23P01로 막음
  update public.bookings set end_min = v_end where id = b.id returning * into v_row;
  return v_row;
end $$;
