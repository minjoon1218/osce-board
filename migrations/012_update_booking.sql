-- 오스키실 예약판 · 업데이트 012
-- 신청 변경: 날짜·시간·방·사용 시간·일차·연습내용·재료(관리자는 조도) 를 한 번에 바꿈
-- 조장: 우리 조 신청, 시작 전, 고정 시간대 아닌 것만 / 신청 규칙(오픈·하루 2회·금지 시간·조 겹침) 그대로 적용
-- 관리자: 모든 신청, 규칙 예외는 대리 신청과 같음
-- 자기 자신은 겹침·하루 2회 계산에서 빠짐

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

  if p_dur not in (60,120) and p_dur <> b.end_min - b.start_min then raise exception 'BAD_DURATION'; end if;
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

revoke all on function public.update_booking(text,uuid,date,int,int,int,text,text,text[],text) from public;
grant execute on function public.update_booking(text,uuid,date,int,int,int,text,text,text[],text) to anon, authenticated;
