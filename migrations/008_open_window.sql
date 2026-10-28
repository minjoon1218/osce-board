-- 오스키실 예약판 · 업데이트 008
-- 예약 오픈 규칙 변경: 매일 21:00에 다음 날 오픈 (평소엔 오늘까지만)
-- + 관리자가 특정 날짜를 특정 시각에 따로 열 수 있음 (open_dates)

create table if not exists public.open_dates (
  date      date primary key,
  opens_at  timestamptz not null,
  memo      text not null default ''
);
alter table public.open_dates enable row level security;
drop policy if exists "read open_dates" on public.open_dates;
create policy "read open_dates" on public.open_dates for select using (true);

-- 고정 시간대 신청 구분용 (업데이트 009에서 사용, 하루 2회 제한에서 제외)
alter table public.bookings add column if not exists fixed_id uuid;

-- 지금 조장이 신청할 수 있는 마지막 날짜
create or replace function public.last_bookable()
returns date language sql stable security definer set search_path = public as $$
  select greatest(
    (now() at time zone 'Asia/Seoul')::date
      + case when (now() at time zone 'Asia/Seoul')::time >= time '21:00' then 1 else 0 end,
    coalesce((select max(date) from public.open_dates where opens_at <= now()), date '1900-01-01'));
$$;
grant execute on function public.last_bookable() to anon, authenticated;

-- 전환용: 이미 열려 있던 금요일(10/30)은 그대로, 토요일(10/31)은 10/29 11:00에 오픈
insert into public.open_dates (date, opens_at, memo) values
  ('2026-10-30', now(), '규칙 변경 전 이미 열려 있던 날'),
  ('2026-10-31', '2026-10-29 11:00:00+09', '토요일 특별 오픈')
on conflict (date) do update set opens_at = excluded.opens_at, memo = excluded.memo;

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
  if p_dur not in (60,120) then raise exception 'BAD_DURATION'; end if;
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

do $$ begin
  alter publication supabase_realtime add table public.open_dates;
exception when duplicate_object then null; end $$;
