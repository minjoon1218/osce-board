-- 오스키실 예약판 · 업데이트 006
-- 사용 중 조기 퇴실(30분/1시간)·연장(30분/1시간)
-- 005_block_rooms.sql 실행 후, SQL Editor에 붙여넣고 Run (여러 번 실행해도 안전)

-- 1) 사용 시간 제약 완화: 1·2시간 고정 → 끝>시작, 최대 3시간 (신청 자체는 여전히 1·2시간만)
do $$ declare c record; begin
  for c in select conname from pg_constraint
           where conrelid = 'public.bookings'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) like '%end_min%'
  loop
    execute format('alter table public.bookings drop constraint %I', c.conname);
  end loop;
end $$;
alter table public.bookings add constraint bookings_time_check
  check (end_min <= 1320 and end_min > start_min and end_min - start_min <= 180);

-- 2) 조기 퇴실 / 연장
--    조장: 우리 조 신청이 '지금 사용 중'일 때만 / 관리자: 언제든
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
    if v_end - b.start_min > 180 then raise exception 'TOO_LONG'; end if;
    if exists (select 1 from public.bookings o
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

revoke all on function public.adjust_booking(text, uuid, int) from public;
grant execute on function public.adjust_booking(text, uuid, int) to anon, authenticated;
