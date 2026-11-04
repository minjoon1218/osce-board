-- 오스키실 예약판 · 업데이트 023
-- 1) 같은 방에서 같은 조(묶음) 신청 사이 틈은 붙이거나 2시간 이상 (1시간 틈 금지) → GAP_SHORT
--    다른 방으로 옮기는 건 제한 없음. 관리자 신청은 예외 (조장 신청·변경·연장에만 적용)
-- 2) 조장 한 번 신청 최대 3시간 (1·2·3시간 선택)

create or replace function public.check_unit_limits(p_team text, p_date date, p_room int, p_start int, p_end int, p_exclude uuid, p_walkin boolean)
returns void language plpgsql stable security definer set search_path = public as $$
declare u text := public.unit_of(p_team); mr int; v_free boolean := p_walkin;
begin
  if public.team_closed(p_team) then raise exception 'TEAM_CLOSED'; end if;
  if not v_free and p_exclude is not null then
    v_free := exists (select 1 from public.bookings where id = p_exclude and (bonus or fixed_id is not null));
  end if;
  if not v_free and public.unit_used(u, p_date, p_exclude) + public.charge_min(p_start, p_end) > public.unit_cap(u, p_date) then
    raise exception 'DAILY_CAP';
  end if;
  mr := coalesce((select max_rooms from public.units where unit = u), 1);
  if (select count(*) from public.bookings b
       where b.date = p_date and b.id is distinct from p_exclude and public.unit_of(b.team) = u
         and int4range(b.start_min,b.end_min) && int4range(p_start,p_end)) >= mr then
    raise exception 'TEAM_BUSY';
  end if;
  -- 같은 방·같은 묶음 신청 사이 틈은 0(붙이기) 또는 2시간 이상
  if exists (select 1 from public.bookings b
              where b.date = p_date and b.room = p_room and b.id is distinct from p_exclude and public.unit_of(b.team) = u
                and ((b.end_min < p_start and p_start - b.end_min < 120)
                  or (b.start_min > p_end and b.start_min - p_end < 120))) then
    raise exception 'GAP_SHORT';
  end if;
  if public.unit_run(u, p_date, p_room, p_start, p_end, p_exclude) > 180 then
    raise exception 'RUN_LIMIT';
  end if;
end $$;

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
  if not v_admin and p_dur not in (60,120,180) then raise exception 'BAD_DURATION'; end if;
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
  insert into public.bookings(date,room,start_min,end_min,day_label,team,content,kits,walkin,bonus)
  values (p_date,p_room,p_start,p_start+p_dur,coalesce(p_day,''),v_team,coalesce(p_content,''),coalesce(p_kits,'{}'),v_walk,v_admin)
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
  if not v_admin and not v_locked and p_dur not in (60,120,180) and p_dur <> b.end_min - b.start_min then raise exception 'BAD_DURATION'; end if;
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

revoke all on function public.check_unit_limits(text,date,int,int,int,uuid,boolean) from public, anon, authenticated;
revoke all on function public.create_booking(text,date,int,int,int,text,text,text[],text) from public;
grant execute on function public.create_booking(text,date,int,int,int,text,text,text[],text) to anon, authenticated;
revoke all on function public.update_booking(text,uuid,date,int,int,int,text,text,text[],text) from public;
grant execute on function public.update_booking(text,uuid,date,int,int,int,text,text,text[],text) to anon, authenticated;
