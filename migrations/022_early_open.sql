-- 오스키실 예약판 · 업데이트 022
-- 1·2일차는 21:00 전에도 다음 날 신청 가능: 오픈 시차를 음수까지 허용 (-1260 = 그날 00:00 → 하루 종일 다음 날 열림)
alter table public.open_offsets drop constraint if exists open_offsets_offset_min_check;
alter table public.open_offsets add constraint open_offsets_offset_min_check check (offset_min between -1260 and 180);
update public.open_offsets set offset_min = -1260 where exam_day in (1, 2);
