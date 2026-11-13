-- 오스키실 예약판 · 업데이트 052 (데이터)
-- 상한 구간 '6·7일차'를 6일차 / 7일차로 나눠서 표시 (둘 다 제한 없음). 오픈 시간은 원래부터 6일차 21:40, 7일차 21:50
update public.day_tiers set to_day = 6, label = '6일차' where label = '6·7일차';
insert into public.day_tiers (id, from_day, to_day, label, team_min, closed)
select 6, 7, 7, '7일차', 960, false where not exists (select 1 from public.day_tiers where from_day = 7);
