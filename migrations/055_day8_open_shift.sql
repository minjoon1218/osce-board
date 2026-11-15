-- 오스키실 예약판 · 업데이트 055 (데이터)
-- 8일차 신청 열기(제한 없음), 상한 구간 3·4일차 → 3일차 / 4일차로 나눔
-- 11/15 밤: 8일차는 22:00 오픈 (기존 '나머지' 자리)
-- 11/16 20:55(KST)에 pg_cron 1회 작업으로: 3일차 신청 막기 + 오픈 순서 한 칸씩 당김 (4일차 21:10 … 8일차 21:50)
update public.day_tiers set to_day = 3, label = '3일차' where label = '3·4일차';
insert into public.day_tiers (id, from_day, to_day, label, team_min, closed) values (7, 4, 4, '4일차', 960, false), (8, 8, 8, '8일차', 960, false) on conflict (id) do nothing;
insert into public.open_offsets (exam_day, offset_min) values (8, 60) on conflict (exam_day) do update set offset_min = excluded.offset_min;
select cron.schedule('osce-shift-order-1116', '55 11 16 11 *', $job$
  update public.open_offsets set offset_min = case exam_day when 4 then 10 when 5 then 20 when 6 then 30 when 7 then 40 when 8 then 50 else offset_min end where exam_day between 4 and 8;
  update public.day_tiers set closed = true where label = '3일차';
  select cron.unschedule('osce-shift-order-1116');
$job$);
