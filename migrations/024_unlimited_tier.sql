-- 오스키실 예약판 · 업데이트 024
-- 구간 상한 16시간(960분) = 제한 없음 (사용 금지 날 자동 축소도 안 함). 1·2일차를 제한 없음으로
create or replace function public.unit_cap(p_unit text, p_date date) returns int
language sql stable security definer set search_path = public as $$
  with tm as (select public.tier_min(l.exam_day) m from public.leaders l where coalesce(l.unit, l.team) = p_unit),
       base as (select coalesce((select sum(m) from tm), 120) m, coalesce((select max(m) from tm), 0) >= 960 unlimited),
       blk as (select coalesce(sum((least(end_min,1380) - greatest(start_min,420)) * cardinality(rooms)), 0) b
                 from public.blocks where date = p_date)
  select case when base.unlimited then 99999
              else (floor(base.m * greatest(0.5, 1 - blk.b::numeric / (6 * 960)) / 30) * 30)::int end
    from base, blk;
$$;
update public.day_tiers set team_min = 960 where from_day = 1 and to_day = 2;
