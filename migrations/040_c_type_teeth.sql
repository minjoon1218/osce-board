-- 오스키실 예약판 · 업데이트 040 (데이터)
-- C형 관련 케이스에 치식이 빠진 줄 채우기 (두근두근 앱 케이스 내용 기준) — 공유 텍스트에 '술기 + 치식'으로 나옴
update public.prac_problems set related = replace(related, '두근두근 36 급성 치주농양(치수 생활력 정상)', '두근두근 36 급성 치주농양(#36, 치수 생활력 정상)') where unit='3A' and type='C' and no=2 and related like '%두근두근 36 급성 치주농양(치수 생활력 정상)%';
update public.prac_problems set related = replace(replace(related, '두근두근 10 사랑니 주위염(하악 지치 부분 맹출)', '두근두근 10 사랑니 주위염(#38, 하악 지치 부분 맹출)'), '두근두근 30 급성 지치주위염(개구장애·안모부종 동반)', '두근두근 30 급성 지치주위염(#38, 개구장애·안모부종 동반)') where unit='3A' and type='C' and no=7 and related like '%두근두근 10 사랑니 주위염(하악 지치 부분 맹출)%';
