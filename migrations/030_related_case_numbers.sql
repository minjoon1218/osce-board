-- 오스키실 예약판 · 업데이트 030 (데이터)
-- 관련 초진 케이스를 '#두근두근 케이스번호 제목' 한 줄씩으로 (화면엔 번호만, 설정 탭엔 전체). 사용자가 고친 줄은 건드리지 않음
update public.prac_problems set related = '#114 재발성 구순 단순포진(HSV-1)
#202 재발성 구순 단순포진(HSV-1, 수포기)
#220 재발성 구순 단순포진(하순 좌측 입가 쪽)
#229 재발성 구강 내 단순포진(우측 경구개, 치과 구개 마취 후)' where unit = '3A' and type = 'A' and no = 1 and related in ('재발성 구순 단순포진(HSV-1) · 구순 단순포진 수포기 · 하순 입가 단순포진 · 구강 내 단순포진(경구개, 구개 마취 후)', '');
update public.prac_problems set related = '#22 재발성 아프타성 구내염(경도, minor RAS)
#207 재발성 아프타성 구내염(경도, 하순 점막)
#224 재발성 아프타성 구내염(경도, 혀 좌측)
#233 재발성 아프타성 구내염, 주요형(major RAS, 연구개)' where unit = '3A' and type = 'A' and no = 2 and related in ('재발성 아프타성 구내염 경도(하순 점막·혀 좌측) · minor RAS · 주요형 major RAS(연구개)', '');
update public.prac_problems set related = '#201 약물관련 악골괴사증(MRONJ, 발치 후 누공·배농)' where unit = '3A' and type = 'A' and no = 3 and related in ('약물관련 악골괴사증 MRONJ(발치 후 누공·배농)', '');
update public.prac_problems set related = '#44 정중과잉치로 인한 정중이개(SLOB 규칙)
#204 역위 정중과잉치와 #61 만기잔존(SLOB 규칙)
#228 역위 정중과잉치 2개에 의한 정중이개(SLOB 3장)
#239 맹출된 정중과잉치(#21 회전·구개측 전위, 단순 발치)
#40 정중이개(상순소대 고위 부착) — 감별' where unit = '3A' and type = 'A' and no = 4 and related in ('정중과잉치로 인한 정중이개(SLOB) · 역위 정중과잉치 2개에 의한 정중이개 · 역위 정중과잉치 + #61 만기잔존 · 맹출된 정중과잉치(#21 회전·구개측 전위) · 감별: 상순소대 고위 부착', '');
update public.prac_problems set related = '#203 유구치(#54) 증상성 비가역성 치수염
#205 레진 하방 이차우식에 의한 비가역성 치수염(#16)
#31 이차우식으로 인한 비가역적 치수염
#210 균열치로 인한 비가역성 치수염(#16)' where unit = '3A' and type = 'A' and no = 5 and related in ('유구치 #54 증상성 비가역성 치수염 · 레진 하방 이차우식에 의한 비가역성 치수염(#16) · 균열치로 인한 비가역성 치수염(#16)', '');
update public.prac_problems set related = '#12 치아 외상(전치부 치관파절 — 법랑질·상아질)
#37 영구전치 치관파절(치근 미완성)
#211 외상 후 치수괴사에 의한 만성 치근단 농양(#21, 누공)' where unit = '3A' and type = 'A' and no = 6 and related in ('전치부 치관파절(법랑질·상아질) · 영구전치 치관파절(치근 미완성) · 외상 후 치수괴사 만성 치근단 농양(#21, 누공)', '');
update public.prac_problems set related = '#33 균열치아증후군(Cracked Tooth Syndrome)
#219 균열치아증후군(#17, 치수 생활력 정상)
#226 균열치아증후군(#36 MOD 아말감, 근심설측 교두)
#210 균열치로 인한 비가역성 치수염(#16)
#110 수직 치근 파절(근관치료·포스트 치아) — 감별' where unit = '3A' and type = 'A' and no = 7 and related in ('균열치아증후군(#17 생활력 정상) · 균열치아증후군(#36 MOD 아말감) · 균열치로 인한 비가역성 치수염(#16) · 감별: 수직 치근 파절', '');
update public.prac_problems set related = '#111 치아 과민증(치은퇴축·치경부 마모) — 치은퇴축으로 인한 지각과민' where unit = '3A' and type = 'C' and no = 1 and related in ('치은퇴축으로 인한 지각과민 (두근두근: 치아 과민증 — 치은퇴축·치경부 마모)', '');
update public.prac_problems set related = '#208 급성 치주농양(#46, 페니실린 알레르기)
#218 스케일링 후 급성 치주농양(#37, 발열 동반)
#36 급성 치주농양(치수 생활력 정상)' where unit = '3A' and type = 'C' and no = 2 and related in ('급성 치주농양 (두근두근: #46 페니실린 알레르기 · 스케일링 후 #37 발열 동반 · 치수 생활력 정상)', '');
update public.prac_problems set related = '진탕 외상 (두근두근에 같은 케이스 없음)' where unit = '3A' and type = 'C' and no = 3 and related in ('진탕 외상', '');
update public.prac_problems set related = '#20 교정 환자 구강위생교육(브라켓 주변 치은염)
#212 교정 장치 주변 치태성 치은염(성인 교정, TBI)' where unit = '3A' and type = 'C' and no = 4 and related in ('교정 환자 (두근두근: 브라켓 주변 치은염 · 성인 교정 장치 주변 치태성 치은염)', '');
update public.prac_problems set related = '#213 만성 재발성 지치주위염(#38, 아스피린 복용 고혈압, 협진의뢰서) — 사랑니 발치' where unit = '3A' and type = 'C' and no = 5 and related in ('사랑니 발치 (두근두근: 만성 재발성 지치주위염 #38, 아스피린 복용 고혈압)', '');
update public.prac_problems set related = '#230 긴장형 두통(당뇨 환자, 진통제 잦은 복용 — 치과적 원인 배제)' where unit = '3A' and type = 'C' and no = 6 and related in ('긴장성 두통 (두근두근: 긴장형 두통, 당뇨 환자·진통제 잦은 복용)', '');
update public.prac_problems set related = '#113 급성 지치주위염(개구장애 동반)
#213 만성 재발성 지치주위염(#38, 협진의뢰서)' where unit = '3A' and type = 'C' and no = 7 and related in ('지치주위염 (두근두근: 급성 지치주위염 개구장애 · 만성 재발성 지치주위염 #38)', '');
