-- 오스키실 예약판 · 업데이트 005
-- 사용 금지를 방 일부만 골라서도 설정 (기본은 1–6번 전체)
-- 004_blocks.sql 실행 후, SQL Editor에 붙여넣고 Run (여러 번 실행해도 안전)

alter table public.blocks add column if not exists rooms int[] not null default '{1,2,3,4,5,6}';

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
  -- 관리자가 정한 사용 금지 시간 (해당 방만, 조장만 막힘)
  if not v_admin and exists (select 1 from public.blocks k
             where k.date = p_date and p_room = any(k.rooms) and int4range(k.start_min,k.end_min) && int4range(p_start,p_start+p_dur)) then
    raise exception 'BLOCKED';
  end if;
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

drop function if exists public.admin_add_block(text,date,int,int,text,boolean);
create or replace function public.admin_add_block(
  p_code text, p_date date, p_start int, p_end int, p_reason text,
  p_cancel boolean default false, p_rooms int[] default '{1,2,3,4,5,6}'
) returns int
language plpgsql security definer set search_path = public as $$
declare n int := 0; v_rooms int[];
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  if p_start < 480 or p_end > 1320 or p_end <= p_start then raise exception 'BAD_RANGE'; end if;
  select array_agg(distinct r order by r) into v_rooms from unnest(coalesce(p_rooms,'{}')) r where r between 1 and 6;
  if v_rooms is null then raise exception 'NO_ROOMS'; end if;
  insert into public.blocks (date, start_min, end_min, reason, rooms) values (p_date, p_start, p_end, coalesce(p_reason,''), v_rooms);
  if p_cancel then
    delete from public.bookings b
     where b.date = p_date and b.room = any(v_rooms) and int4range(b.start_min,b.end_min) && int4range(p_start,p_end);
    get diagnostics n = row_count;
  end if;
  return n;
end $$;
revoke all on function public.admin_add_block(text,date,int,int,text,boolean,int[]) from public;
grant execute on function public.admin_add_block(text,date,int,int,text,boolean,int[]) to anon, authenticated;
