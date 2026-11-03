-- 오스키실 예약판 · 업데이트 019
-- 하루 상한 단순화: 일차 구간별 '조당' 상한 (같이 연습하는 묶음은 조 수만큼 합산)
--   1·2일차 6시간 / 3–5일차 4시간 / 6·7일차 3시간 / 나머지 2시간
-- 식사 시간 할인은 끔 (meal_windows 비움 → charge_min = 실제 사용 시간)
-- 당일 빈자리(2시간 안 시작은 상한 미포함)·동시 방 수·연속 3시간은 그대로

create table if not exists public.day_tiers (
  id        serial primary key,
  from_day  int not null,          -- 0 = 나머지(기본값)
  to_day    int not null,
  label     text not null,
  team_min  int not null check (team_min between 0 and 960)
);
alter table public.day_tiers enable row level security;
drop policy if exists "read day_tiers" on public.day_tiers;
create policy "read day_tiers" on public.day_tiers for select using (true);
insert into public.day_tiers (from_day, to_day, label, team_min)
select * from (values (1,2,'1·2일차',360),(3,5,'3–5일차',240),(6,7,'6·7일차',180),(0,0,'나머지',120)) v(a,b,c,d)
where not exists (select 1 from public.day_tiers);

create or replace function public.tier_min(p_day int) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select team_min from public.day_tiers where from_day > 0 and p_day between from_day and to_day order by from_day limit 1),
    (select team_min from public.day_tiers where from_day = 0 limit 1), 120);
$$;

create or replace function public.unit_cap(p_unit text, p_date date) returns int
language sql stable security definer set search_path = public as $$
  with base as (select coalesce((select sum(public.tier_min(l.exam_day)) from public.leaders l where coalesce(l.unit, l.team) = p_unit), 120) m),
       blk as (select coalesce(sum((least(end_min,1380) - greatest(start_min,420)) * cardinality(rooms)), 0) b
                 from public.blocks where date = p_date)
  select (floor(base.m * greatest(0.5, 1 - blk.b::numeric / (6 * 960)) / 30) * 30)::int from base, blk;
$$;

delete from public.meal_windows where true;

create or replace function public.admin_set_tier(p_code text, p_id int, p_team_min int)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  if p_team_min < 0 or p_team_min > 960 then raise exception 'BAD_CFG'; end if;
  update public.day_tiers set team_min = p_team_min where id = p_id;
  return found;
end $$;

revoke all on function public.tier_min(int) from public, anon, authenticated;
revoke all on function public.admin_set_tier(text,int,int) from public;
grant execute on function public.admin_set_tier(text,int,int) to anon, authenticated;
do $$ begin alter publication supabase_realtime add table public.day_tiers; exception when duplicate_object then null; end $$;
