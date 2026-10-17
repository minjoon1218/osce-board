-- 오스키실 예약판 · 업데이트 007
-- 조 이름 목록 공개(코드는 비공개) → 조별 고정 색상·연습 기록에 사용

create or replace function public.list_teams()
returns setof text
language sql security definer set search_path = public stable as $$
  select team from public.leaders order by team;
$$;
revoke all on function public.list_teams() from public;
grant execute on function public.list_teams() to anon, authenticated;
