-- 오스키실 예약판 · 업데이트 049
-- 같은 방 앞 신청과의 '2시간 틈' 규칙(GAP_SHORT) 없앰. 나머지(조 마감·하루 상한·동시 방 수·한 번에 3시간)는 그대로
create or replace function public.check_unit_limits(p_team text, p_date date, p_room integer, p_start integer, p_end integer, p_exclude uuid, p_walkin boolean)
returns void language plpgsql stable security definer set search_path to 'public' as $function$
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
  if public.unit_run(u, p_date, p_room, p_start, p_end, p_exclude) > 180 then
    raise exception 'RUN_LIMIT';
  end if;
end $function$;
