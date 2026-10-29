-- ⚠️ 처음 한 번만 실행하는 파일이에요. 이미 쓰고 있는 DB에서 다시 실행하면 관리자 기능 함수가 옛 버전으로 덮어써져요.
--    다시 실행했다면 migrations/002~010을 순서대로 다시 실행하세요. (조 추가·코드 재발급은 README의 '자주 쓰는 SQL' 사용)

-- 오스키실 예약판 · Supabase 스키마 (조장 코드 버전)
-- Supabase 대시보드 → SQL Editor → 전체 붙여넣고 Run
-- 실행 후 맨 아래 쿼리 결과(팀별 조장 코드)를 각 조장에게 개인톡으로 전달

-- (이전 버전 schema.sql을 이미 실행했다면 아래 3줄 주석을 풀고 먼저 실행)
-- drop function if exists public.cancel_booking(uuid, text);
-- drop table if exists public.bookings;
-- drop table if exists public.kits;

create extension if not exists btree_gist;

-- 1) 조장 코드 ----------------------------------------------------------
create table if not exists public.leaders (
  team  text primary key,                 -- 'A', 'B', ...
  code  text not null unique,             -- 조장 로그인 코드
  name  text default ''
);
alter table public.leaders enable row level security;   -- 정책 없음 = 아무도 직접 못 읽음

-- 2) 예약 ---------------------------------------------------------------
create table if not exists public.bookings (
  id          uuid primary key default gen_random_uuid(),
  date        date not null,
  room        int  not null check (room between 1 and 6),
  start_min   int  not null check (start_min >= 480),
  end_min     int  not null check (end_min <= 1320 and end_min - start_min in (60,120)),
  day_label   text default '',
  team        text not null references public.leaders(team) on update cascade,
  content     text default '',
  kits        text[] not null default '{}',
  created_at  timestamptz not null default now(),
  constraint no_overlap exclude using gist (
    room with =, date with =, int4range(start_min, end_min) with &&
  )
);
create index if not exists bookings_date_idx on public.bookings (date);

-- 3) 재료 세트 (10종 × 2세트) --------------------------------------------
create table if not exists public.kits (
  id      text primary key,
  status  text not null default 'in' check (status in ('in','out')),
  who     text default '',
  at      timestamptz default now()
);
insert into public.kits (id)
select k || '-' || s
from unnest(array['anes','ext','sut','tbi','fl','seal','rd','srp','ept','probe']) k,
     generate_series(1,2) s
on conflict do nothing;

-- 4) 권한: 누구나 보기만, 쓰기는 조장 코드가 맞는 함수로만 ----------------
alter table public.bookings enable row level security;
alter table public.kits     enable row level security;
drop policy if exists "read bookings" on public.bookings;
drop policy if exists "read kits"     on public.kits;
create policy "read bookings" on public.bookings for select using (true);
create policy "read kits"     on public.kits     for select using (true);

-- 조장 확인
create or replace function public.leader_login(p_code text)
returns text language sql security definer set search_path = public stable as $$
  select team from public.leaders where code = upper(trim(p_code));
$$;

-- 신청
create or replace function public.create_booking(
  p_code text, p_date date, p_room int, p_start int, p_dur int,
  p_day text, p_content text, p_kits text[]
) returns public.bookings
language plpgsql security definer set search_path = public as $$
declare v_team text; v_row public.bookings;
begin
  select team into v_team from public.leaders where code = upper(trim(p_code));
  if v_team is null then raise exception 'NOT_LEADER'; end if;
  if p_dur not in (60,120) then raise exception 'BAD_DURATION'; end if;
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

-- 취소 (자기 조 신청만)
create or replace function public.cancel_booking(p_code text, p_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_team text; n int;
begin
  select team into v_team from public.leaders where code = upper(trim(p_code));
  if v_team is null then raise exception 'NOT_LEADER'; end if;
  delete from public.bookings where id = p_id and team = v_team;
  get diagnostics n = row_count;
  return n > 0;
end $$;

-- 재료 대여·반납
create or replace function public.set_kit(p_code text, p_id text, p_status text, p_who text)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_team text;
begin
  select team into v_team from public.leaders where code = upper(trim(p_code));
  if v_team is null then raise exception 'NOT_LEADER'; end if;
  if p_status not in ('in','out') then raise exception 'BAD_STATUS'; end if;
  update public.kits
     set status = p_status,
         who = case when p_status = 'out' then coalesce(nullif(trim(p_who),''), v_team || '조') else '' end,
         at = now()
   where id = p_id;
  return found;
end $$;

revoke all on function public.leader_login(text) from public;
revoke all on function public.create_booking(text,date,int,int,int,text,text,text[]) from public;
revoke all on function public.cancel_booking(text,uuid) from public;
revoke all on function public.set_kit(text,text,text,text) from public;
grant execute on function public.leader_login(text) to anon, authenticated;
grant execute on function public.create_booking(text,date,int,int,int,text,text,text[]) to anon, authenticated;
grant execute on function public.cancel_booking(text,uuid) to anon, authenticated;
grant execute on function public.set_kit(text,text,text,text) to anon, authenticated;

-- 5) 실시간 반영 ---------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.bookings, public.kits;
exception when duplicate_object then null; end $$;

-- 6) 조장 코드 만들기: 팀 목록을 실제 조에 맞게 고친 뒤 실행 ----------------
insert into public.leaders (team, code)
select t, upper(substr(md5(random()::text || t), 1, 6))
from unnest(array['A','B','C','D','E','F','G','H']) t
on conflict (team) do nothing;

select team as "조", code as "조장 코드" from public.leaders order by team;

-- 참고
-- 코드 새로 발급:   update public.leaders set code = upper(substr(md5(random()::text),1,6)) where team = 'C';
-- 조 추가:          insert into public.leaders (team, code) values ('I', 'ABC123');
-- 지난 예약 정리:   delete from public.bookings where date < current_date - 30;
