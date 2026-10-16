-- 오스키실 예약판 · 업데이트 004
-- 관리자: 일정 시간 동안 오스키실 전체 사용 금지
-- 003_daily_limit.sql 실행 후, SQL Editor에 붙여넣고 Run (여러 번 실행해도 안전)

-- 1) 사용 금지 시간 ------------------------------------------------------
create table if not exists public.blocks (
  id         uuid primary key default gen_random_uuid(),
  date       date not null,
  start_min  int  not null check (start_min >= 480),
  end_min    int  not null check (end_min <= 1320 and end_min > start_min),
  reason     text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists blocks_date_idx on public.blocks (date);
alter table public.blocks enable row level security;
drop policy if exists "read blocks" on public.blocks;
create policy "read blocks" on public.blocks for select using (true);

-- 2) 신청: 사용 금지 시간 검사 추가 -----------------------------------------
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
  -- 관리자가 정한 전체 사용 금지 시간 (조장만 막힘)
  if not v_admin and exists (select 1 from public.blocks k
             where k.date = p_date and int4range(k.start_min,k.end_min) && int4range(p_start,p_start+p_dur)) then
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

-- 3) 관리자: 사용 금지 추가 / 삭제 ------------------------------------------
create or replace function public.admin_add_block(
  p_code text, p_date date, p_start int, p_end int, p_reason text, p_cancel boolean default false
) returns int
language plpgsql security definer set search_path = public as $$
declare n int := 0;
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  if p_start < 480 or p_end > 1320 or p_end <= p_start then raise exception 'BAD_RANGE'; end if;
  insert into public.blocks (date, start_min, end_min, reason) values (p_date, p_start, p_end, coalesce(p_reason,''));
  if p_cancel then
    delete from public.bookings b
     where b.date = p_date and int4range(b.start_min,b.end_min) && int4range(p_start,p_end);
    get diagnostics n = row_count;
  end if;
  return n;   -- 같이 취소된 신청 수
end $$;

create or replace function public.admin_delete_block(p_code text, p_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  delete from public.blocks where id = p_id;
  return found;
end $$;

revoke all on function public.admin_add_block(text,date,int,int,text,boolean) from public;
revoke all on function public.admin_delete_block(text,uuid) from public;
grant execute on function public.admin_add_block(text,date,int,int,text,boolean) to anon, authenticated;
grant execute on function public.admin_delete_block(text,uuid) to anon, authenticated;

-- 4) 실시간 반영 ---------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.blocks;
exception when duplicate_object then null; end $$;
