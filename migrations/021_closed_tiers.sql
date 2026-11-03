-- 오스키실 예약판 · 업데이트 021
-- 일차 구간별 '신청 막기': day_tiers.closed = true 인 구간의 조장은 신청·변경(시간 이동)·연장 불가 (당일 빈자리 포함)
-- 기본: '나머지'(8일차 이후) 막음. 관리자 신청은 그대로 가능

alter table public.day_tiers add column if not exists closed boolean not null default false;
update public.day_tiers set closed = true where from_day = 0;

create or replace function public.team_closed(p_team text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select t.closed from public.day_tiers t join public.leaders l on l.team = p_team
      where t.from_day > 0 and l.exam_day between t.from_day and t.to_day order by t.from_day limit 1),
    (select closed from public.day_tiers where from_day = 0 limit 1), false);
$$;

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
  if public.unit_run(u, p_date, p_room, p_start, p_end, p_exclude) > 180 then
    raise exception 'RUN_LIMIT';
  end if;
end $$;

create or replace function public.admin_set_tier_closed(p_code text, p_id int, p_closed boolean)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  update public.day_tiers set closed = p_closed where id = p_id;
  return found;
end $$;

revoke all on function public.team_closed(text) from public, anon, authenticated;
revoke all on function public.check_unit_limits(text,date,int,int,int,uuid,boolean) from public, anon, authenticated;
revoke all on function public.admin_set_tier_closed(text,int,boolean) from public;
grant execute on function public.admin_set_tier_closed(text,int,boolean) to anon, authenticated;
