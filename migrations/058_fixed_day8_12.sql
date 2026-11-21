-- 오스키실 예약판 · 업데이트 058 (데이터)
-- 매일 밀기(056) 중단. 이제 8~12일차만 신청, 오픈 시간 고정
-- 11/21 밤: 8일차는 바로 열림(오프셋 0), 9~12일차는 그날 순서 그대로(21:10~21:40)
-- 11/21 22:05(KST) 1회 작업 후 고정: 21:10 8일차 · 21:20 9일차 · 21:30 10일차 · 21:40 11일차 · 21:50 12일차
select cron.unschedule(jobid) from cron.job where jobname = 'osce-roll-daily';
update public.day_tiers set closed = (from_day not between 8 and 12), team_min = case when from_day between 8 and 12 then 960 else team_min end
 where from_day = to_day and from_day between 3 and 12;
update public.day_tiers set closed = true where from_day = 1 and to_day = 2;
update public.open_offsets set offset_min = 0 where exam_day = 8;
select cron.schedule('osce-fix-order-1121', '5 13 21 11 *', $job$
  update public.open_offsets set offset_min = case exam_day when 8 then 10 when 9 then 20 when 10 then 30 when 11 then 40 when 12 then 50 end where exam_day between 8 and 12;
  select cron.unschedule('osce-fix-order-1121');
$job$);
