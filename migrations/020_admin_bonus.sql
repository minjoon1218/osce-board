-- 오스키실 예약판 · 업데이트 020
-- 관리자가 넣은 시간은 '보너스': 조 하루 상한에 안 들어감
--   - 관리자 대리 신청(create_booking 관리자 경로) → bookings.bonus = true
--   - 고정 시간대 신청(fixed_id 있음)도 상한에 안 들어감
--   - 조장이 보너스·고정 신청을 옮기거나 연장해도 하루 상한은 안 봄 (동시 방·연속 3시간은 그대로)

alter table public.bookings add column if not exists bonus boolean not null default false;

create or replace function public.unit_used(p_unit text, p_date date, p_exclude uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(public.charge_min(b.start_min, b.end_min)), 0) from public.bookings b
   where b.date = p_date and b.id is distinct from p_exclude
     and not b.walkin and not b.bonus and b.fixed_id is null
     and public.unit_of(b.team) = p_unit;
$$;

create or replace function public.check_unit_limits(p_team text, p_date date, p_room int, p_start int, p_end int, p_exclude uuid, p_walkin boolean)
returns void language plpgsql stable security definer set search_path = public as $$
declare u text := public.unit_of(p_team); mr int; v_free boolean := p_walkin;
begin
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
  insert into public.bookings(date,room,start_min,end_min,day_label,team,content,kits,walkin,bonus)
  values (p_date,p_room,p_start,p_start+p_dur,coalesce(p_day,''),v_team,coalesce(p_content,''),coalesce(p_kits,'{}'),v_walk,v_admin)
  returning * into v_row;
  return v_row;
end $$;

revoke all on function public.unit_used(text,date,uuid) from public, anon, authenticated;
revoke all on function public.check_unit_limits(text,date,int,int,int,uuid,boolean) from public, anon, authenticated;
revoke all on function public.create_booking(text,date,int,int,int,text,text,text[],text) from public;
grant execute on function public.create_booking(text,date,int,int,int,text,text,text[],text) to anon, authenticated;
