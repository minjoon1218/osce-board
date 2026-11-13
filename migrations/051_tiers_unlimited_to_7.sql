-- 오스키실 예약판 · 업데이트 051 (데이터)
-- 5일차, 6·7일차도 하루 상한 없이 (960분 이상 = 무제한). 8일차 이후('나머지')는 그대로 신청 불가
update public.day_tiers set team_min = 960 where label in ('5일차', '6·7일차');
