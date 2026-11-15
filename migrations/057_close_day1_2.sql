-- 오스키실 예약판 · 업데이트 057 (데이터)
-- 1·2일차 신청 막기 (매일 오픈 순서 밀기 작업은 1·2일차를 건드리지 않으므로 계속 막힌 상태)
update public.day_tiers set closed = true where from_day = 1 and to_day = 2;
