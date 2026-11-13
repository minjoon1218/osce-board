-- 오스키실 예약판 · 업데이트 054 (데이터, 3A)
-- a5 비치수염 → 가역성 치수염(대표 ★ 두근두근 39), a6 외상 → 치관파절(치수 노출 없음: 두근두근 12·37)
update public.prac_problems set name = '가역성 치수염', related = '★ 두근두근 39 소치 가역적 치수염(#85 유구치 깊은 우식, 6세)
두근두근 55 미성숙 영구치 가역성 치수염(#11, 다발성 우식, 7세)' where unit = '3A' and type = 'A' and no = 5;
update public.prac_problems set name = '치관파절(노출X)', related = '두근두근 12 치관파절 Ellis II(#11, 법랑질·상아질, 치수 노출 없음)
두근두근 37 영구전치 치관파절 Ellis II(#11, 치근 미완성)
두근두근 18 치아 진탕/불완전 파절(#11) — 감별' where unit = '3A' and type = 'A' and no = 6;
