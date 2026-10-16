-- 오스키실 예약판 · 업데이트 002
-- 관리자 코드, 공지사항, 방 관리(토마스·사용 가능 여부·메모), 예약 가능 기간(2일 후까지, 밤 10시 기준)
-- schema.sql을 이미 실행한 프로젝트에서 SQL Editor에 통째로 붙여넣고 Run (여러 번 실행해도 안전)

-- 1) 관리자 코드 ---------------------------------------------------------
create table if not exists public.admins (
  code text primary key,
  name text default '관리자'
);
alter table public.admins enable row level security;   -- 정책 없음 = 아무도 직접 못 읽음

-- 2) 방 상태 -------------------------------------------------------------
create table if not exists public.rooms (
  room       int primary key check (room between 1 and 6),
  thomas     boolean not null default true,     -- 토마스(마네킹)가 방에 있는지
  open       boolean not null default true,     -- false면 신청 불가 (점검 등)
  memo       text not null default '',
  updated_at timestamptz default now()
);
insert into public.rooms (room) select generate_series(1,6) on conflict do nothing;
alter table public.rooms enable row level security;
drop policy if exists "read rooms" on public.rooms;
create policy "read rooms" on public.rooms for select using (true);

-- 3) 공지사항 ------------------------------------------------------------
create table if not exists public.settings (
  key        text primary key,
  value      text not null default '',
  updated_at timestamptz default now()
);
insert into public.settings (key, value) values ('notice', '') on conflict do nothing;
alter table public.settings enable row level security;
drop policy if exists "read settings" on public.settings;
create policy "read settings" on public.settings for select using (true);

-- 4) 코드 확인: 조장/관리자 구분 --------------------------------------------
create or replace function public.auth_code(p_code text)
returns json language sql security definer set search_path = public stable as $$
  select case
    when exists (select 1 from public.admins where code = upper(trim(p_code)))
      then json_build_object('role','admin','team',null)
    when exists (select 1 from public.leaders where code = upper(trim(p_code)))
      then json_build_object('role','leader','team',(select team from public.leaders where code = upper(trim(p_code))))
    else null end;
$$;

-- 5) 신청: 예약 가능 기간 + 방 사용 불가 + 관리자 대리 신청 --------------------
drop function if exists public.create_booking(text,date,int,int,int,text,text,text[]);
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

-- 6) 취소: 조장은 자기 조만, 관리자는 전부 ----------------------------------
create or replace function public.cancel_booking(p_code text, p_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_team text; v_admin boolean; n int;
begin
  v_admin := exists (select 1 from public.admins where code = upper(trim(p_code)));
  if v_admin then
    delete from public.bookings where id = p_id;
  else
    select team into v_team from public.leaders where code = upper(trim(p_code));
    if v_team is null then raise exception 'NOT_LEADER'; end if;
    delete from public.bookings where id = p_id and team = v_team;
  end if;
  get diagnostics n = row_count;
  return n > 0;
end $$;

-- 7) 재료 대여·반납: 관리자도 가능 -----------------------------------------
create or replace function public.set_kit(p_code text, p_id text, p_status text, p_who text)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_team text; v_admin boolean;
begin
  v_admin := exists (select 1 from public.admins where code = upper(trim(p_code)));
  select team into v_team from public.leaders where code = upper(trim(p_code));
  if v_team is null and not v_admin then raise exception 'NOT_LEADER'; end if;
  if p_status not in ('in','out') then raise exception 'BAD_STATUS'; end if;
  update public.kits
     set status = p_status,
         who = case when p_status = 'out'
                    then coalesce(nullif(trim(p_who),''), case when v_admin then '관리자' else v_team || '조' end)
                    else '' end,
         at = now()
   where id = p_id;
  return found;
end $$;

-- 8) 관리자 전용: 공지, 방 상태 ------------------------------------------
create or replace function public.admin_set_notice(p_code text, p_text text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  insert into public.settings (key, value, updated_at) values ('notice', coalesce(p_text,''), now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
  return true;
end $$;

create or replace function public.admin_set_room(p_code text, p_room int, p_thomas boolean, p_open boolean, p_memo text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  update public.rooms set thomas = p_thomas, open = p_open, memo = coalesce(p_memo,''), updated_at = now()
   where room = p_room;
  return found;
end $$;

-- 9) 권한 ---------------------------------------------------------------
revoke all on function public.auth_code(text) from public;
revoke all on function public.create_booking(text,date,int,int,int,text,text,text[],text) from public;
revoke all on function public.cancel_booking(text,uuid) from public;
revoke all on function public.set_kit(text,text,text,text) from public;
revoke all on function public.admin_set_notice(text,text) from public;
revoke all on function public.admin_set_room(text,int,boolean,boolean,text) from public;
grant execute on function public.auth_code(text) to anon, authenticated;
grant execute on function public.create_booking(text,date,int,int,int,text,text,text[],text) to anon, authenticated;
grant execute on function public.cancel_booking(text,uuid) to anon, authenticated;
grant execute on function public.set_kit(text,text,text,text) to anon, authenticated;
grant execute on function public.admin_set_notice(text,text) to anon, authenticated;
grant execute on function public.admin_set_room(text,int,boolean,boolean,text) to anon, authenticated;

-- 10) 실시간 반영 --------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.rooms;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.settings;
exception when duplicate_object then null; end $$;

-- 11) 관리자 코드 만들기 (없을 때만) → 결과를 캡처해 두세요 -------------------
insert into public.admins (code)
select 'ADM' || upper(substr(md5(random()::text), 1, 5))
where not exists (select 1 from public.admins);

select code as "관리자 코드" from public.admins;

-- 참고: 관리자 코드 재발급
-- delete from public.admins; insert into public.admins (code) values ('ADM' || upper(substr(md5(random()::text),1,5))); select code from public.admins;
