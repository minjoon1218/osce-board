-- 오스키실 예약판 · 업데이트 031 (데이터)
-- 관련 케이스 번호를 실제 앱 표시 번호로: '초진 n'(= case(200+n), 1–40) / '두근두근 n'(= case n, 1–55). 사용자가 고친 줄은 그대로
update public.prac_problems set related = '초진 2 재발성 구순 단순포진(HSV-1, 수포기)
초진 20 재발성 구순 단순포진(하순 좌측 입가 쪽)
초진 29 재발성 구강 내 단순포진(우측 경구개, 치과 구개 마취 후)
두근두근 13 구순 단순포진(HSV-1 재발성 구순염)
두근두근 23 재발성 구강 내 단순포진(HSV-1 구내염, 경구개)' where unit = '3A' and type = 'A' and no = 1 and related in ('#114 재발성 구순 단순포진(HSV-1)
#202 재발성 구순 단순포진(HSV-1, 수포기)
#220 재발성 구순 단순포진(하순 좌측 입가 쪽)
#229 재발성 구강 내 단순포진(우측 경구개, 치과 구개 마취 후)', '');
update public.prac_problems set related = '초진 7 재발성 아프타성 구내염(경도, 하순 점막)
초진 24 재발성 아프타성 구내염(경도, 혀 좌측)
초진 33 재발성 아프타성 구내염, 주요형(major RAS, 연구개)
두근두근 22 재발성 아프타성 구내염(경도, minor RAS)' where unit = '3A' and type = 'A' and no = 2 and related in ('#22 재발성 아프타성 구내염(경도, minor RAS)
#207 재발성 아프타성 구내염(경도, 하순 점막)
#224 재발성 아프타성 구내염(경도, 혀 좌측)
#233 재발성 아프타성 구내염, 주요형(major RAS, 연구개)', '');
update public.prac_problems set related = '초진 1 약물관련 악골괴사증(MRONJ, 발치 후 누공·배농)
두근두근 29 약물관련 악골괴사증(MRONJ)' where unit = '3A' and type = 'A' and no = 3 and related in ('#201 약물관련 악골괴사증(MRONJ, 발치 후 누공·배농)', '');
update public.prac_problems set related = '초진 4 역위 정중과잉치와 #61 만기잔존(SLOB 규칙)
초진 28 역위 정중과잉치 2개에 의한 정중이개(SLOB 3장)
초진 39 맹출된 정중과잉치(#21 회전·구개측 전위, 단순 발치)
두근두근 44 정중과잉치로 인한 정중이개(SLOB 규칙)
두근두근 52 정중과잉치로 매복된 중절치(교정적 견인)
두근두근 40 정중이개(상순소대 고위 부착) — 감별' where unit = '3A' and type = 'A' and no = 4 and related in ('#44 정중과잉치로 인한 정중이개(SLOB 규칙)
#204 역위 정중과잉치와 #61 만기잔존(SLOB 규칙)
#228 역위 정중과잉치 2개에 의한 정중이개(SLOB 3장)
#239 맹출된 정중과잉치(#21 회전·구개측 전위, 단순 발치)
#40 정중이개(상순소대 고위 부착) — 감별', '');
update public.prac_problems set related = '초진 3 유구치(#54) 증상성 비가역성 치수염
초진 5 레진 하방 이차우식에 의한 비가역성 치수염(#16)
초진 10 균열치로 인한 비가역성 치수염(#16)
두근두근 8 비가역적 치수염(치수괴사 진행)
두근두근 15 비가역적 치수염(방사통, 원인 치아 특정 곤란)
두근두근 31 이차우식으로 인한 비가역적 치수염' where unit = '3A' and type = 'A' and no = 5 and related in ('#203 유구치(#54) 증상성 비가역성 치수염
#205 레진 하방 이차우식에 의한 비가역성 치수염(#16)
#31 이차우식으로 인한 비가역적 치수염
#210 균열치로 인한 비가역성 치수염(#16)', '');
update public.prac_problems set related = '초진 11 외상 후 치수괴사에 의한 만성 치근단 농양(#21, 누공)
두근두근 12 치아 외상(전치부 치관파절 — 법랑질·상아질)
두근두근 18 치아 진탕/불완전 파절(이물 교합, #11)
두근두근 37 영구전치 치관파절(치근 미완성)
두근두근 34 외상 후 치아변색(치수괴사 의심)' where unit = '3A' and type = 'A' and no = 6 and related in ('#12 치아 외상(전치부 치관파절 — 법랑질·상아질)
#37 영구전치 치관파절(치근 미완성)
#211 외상 후 치수괴사에 의한 만성 치근단 농양(#21, 누공)', '');
update public.prac_problems set related = '초진 19 균열치아증후군(#17, 치수 생활력 정상)
초진 26 균열치아증후군(#36 MOD 아말감, 근심설측 교두)
초진 10 균열치로 인한 비가역성 치수염(#16)
두근두근 33 균열치아증후군(Cracked Tooth Syndrome)
초진 40 #36 수직 치근 파절(협심증 스텐트·이중 항혈소판제) — 감별' where unit = '3A' and type = 'A' and no = 7 and related in ('#33 균열치아증후군(Cracked Tooth Syndrome)
#219 균열치아증후군(#17, 치수 생활력 정상)
#226 균열치아증후군(#36 MOD 아말감, 근심설측 교두)
#210 균열치로 인한 비가역성 치수염(#16)
#110 수직 치근 파절(근관치료·포스트 치아) — 감별', '');
update public.prac_problems set related = '두근두근 21 치아 과민증(#43 치은퇴축, 부적절한 잇솔질) — 치은퇴축으로 인한 지각과민' where unit = '3A' and type = 'C' and no = 1 and related in ('#111 치아 과민증(치은퇴축·치경부 마모) — 치은퇴축으로 인한 지각과민', '');
update public.prac_problems set related = '초진 8 급성 치주농양(#46, 페니실린 알레르기)
초진 18 스케일링 후 급성 치주농양(#37, 발열 동반)
두근두근 36 급성 치주농양(치수 생활력 정상)' where unit = '3A' and type = 'C' and no = 2 and related in ('#208 급성 치주농양(#46, 페니실린 알레르기)
#218 스케일링 후 급성 치주농양(#37, 발열 동반)
#36 급성 치주농양(치수 생활력 정상)', '');
update public.prac_problems set related = '두근두근 18 치아 진탕/불완전 파절(이물 교합, #11) — 진탕 외상' where unit = '3A' and type = 'C' and no = 3 and related in ('진탕 외상 (두근두근에 같은 케이스 없음)', '');
update public.prac_problems set related = '초진 12 교정 장치 주변 치태성 치은염(성인 교정, TBI)
두근두근 20 교정 환자 구강위생교육(브라켓 주변 치은염)' where unit = '3A' and type = 'C' and no = 4 and related in ('#20 교정 환자 구강위생교육(브라켓 주변 치은염)
#212 교정 장치 주변 치태성 치은염(성인 교정, TBI)', '');
update public.prac_problems set related = '초진 13 만성 재발성 지치주위염(#38, 아스피린 복용 고혈압, 협진의뢰서) — 사랑니 발치' where unit = '3A' and type = 'C' and no = 5 and related in ('#213 만성 재발성 지치주위염(#38, 아스피린 복용 고혈압, 협진의뢰서) — 사랑니 발치', '');
update public.prac_problems set related = '초진 30 긴장형 두통(당뇨 환자, 진통제 잦은 복용 — 치과적 원인 배제)
두근두근 28 긴장성 두통(측두근 연관, 치과적 원인 배제)' where unit = '3A' and type = 'C' and no = 6 and related in ('#230 긴장형 두통(당뇨 환자, 진통제 잦은 복용 — 치과적 원인 배제)', '');
update public.prac_problems set related = '초진 13 만성 재발성 지치주위염(#38, 협진의뢰서)
두근두근 10 사랑니 주위염(하악 지치 부분 맹출)
두근두근 30 급성 지치주위염(개구장애·안모부종 동반)' where unit = '3A' and type = 'C' and no = 7 and related in ('#113 급성 지치주위염(개구장애 동반)
#213 만성 재발성 지치주위염(#38, 협진의뢰서)', '');
