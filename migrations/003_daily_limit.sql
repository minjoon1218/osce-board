-- 오스키실 예약판 · 업데이트 003
-- 조당 하루 2회까지 신청 가능 (관리자 대리 신청은 제한 없음)
-- 002_admin.sql 실행 후, SQL Editor에 붙여넣고 Run (여러 번 실행해도 안전)

create or replace function public.create_booking(
  p_code text, p_date date, p_room int, p_start int, p_dur int,
  p_day text, p_content text, p_kits text[], p_team text default null
) returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_team text; v_admin boolean; v_row public.bookings;
  v_now timestamp := now() at time zone 'Asia/Seoul';
  v_last date;
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
    -- 2일 후까지, 매일 밤 10시에 다음 날짜 오픈
    v_last := v_now::date + case when v_now::time >= time '22:00' then 3 else 2 end;
    if p_date < v_now::date
       or (p_date = v_now::date and p_start + p_dur <= extract(hour from v_now)::int*60 + extract(minute from v_now)::int) then
      raise exception 'PAST';
    end if;
    if p_date > v_last then raise exception 'TOO_FAR'; end if;
  end if;

  -- 조장은 조당 하루 2회까지 (관리자 대리 신청은 예외)
  if not v_admin and (select count(*) from public.bookings where date = p_date and team = v_team) >= 2 then
    raise exception 'DAILY_LIMIT';
  end if;
  if p_dur not in (60,120) then raise exception 'BAD_DURATION'; end if;
  if exists (select 1 from public.rooms where room = p_room and not open) then raise exception 'ROOM_CLOSED'; end if;
  if exists (select 1 from public.bookings b
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

grant execute on function public.create_booking(text,date,int,int,int,text,text,text[],text) to anon, authenticated;
