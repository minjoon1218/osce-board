-- 오스키실 예약판 · 업데이트 029
-- 1) 조 편성 저장 오류 수정: 'DELETE requires a WHERE clause' (prac_save_day 임시 테이블 비우기)
-- 2) 질환별 '관련 초진 케이스'(prac_problems.related) — 3일차 A·C형은 두근두근 초진 케이스로 미리 채움

alter table public.prac_problems add column if not exists related text not null default '';

create or replace function public.prac_save_day(p_code text, p_unit text, p_date date, p_slots int, p_set uuid[], p_assigns json)
returns json language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit(p_code, p_unit); v_day uuid; x json;
begin
  insert into public.prac_days (unit, date, slots, problem_set) values (u, p_date, p_slots, coalesce(p_set, '{}'))
  on conflict (unit, date) do update set slots = excluded.slots, problem_set = excluded.problem_set, updated_at = now()
  returning id into v_day;
  create temp table if not exists _prac_old (slot int, member_id uuid, problem_id uuid, feedback text) on commit drop;
  delete from _prac_old where true;
  insert into _prac_old select slot, member_id, problem_id, feedback from public.prac_assign where day_id = v_day and feedback <> '';
  delete from public.prac_assign where day_id = v_day;
  for x in select * from json_array_elements(coalesce(p_assigns, '[]')) loop
    if not exists (select 1 from public.prac_members where id = (x->>'member_id')::uuid and unit = u)
       or not exists (select 1 from public.prac_problems where id = (x->>'problem_id')::uuid and unit = u) then
      raise exception 'BAD_ITEM';
    end if;
    insert into public.prac_assign (day_id, slot, grp, ord, member_id, problem_id, feedback)
    values (v_day, (x->>'slot')::int, (x->>'grp')::int, coalesce((x->>'ord')::int, 1), (x->>'member_id')::uuid, (x->>'problem_id')::uuid,
            coalesce((select o.feedback from _prac_old o where o.slot = (x->>'slot')::int and o.member_id = (x->>'member_id')::uuid
                        and o.problem_id = (x->>'problem_id')::uuid limit 1), ''));
  end loop;
  return public.prac_load(p_code, p_unit);
end $$;

create or replace function public.prac_save_problems(p_code text, p_unit text, p_items json) returns json
language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit(p_code, p_unit); x json; keep uuid[] := '{}'; v_id uuid; v_type text; v_no int;
begin
  -- 번호 바꾸기(맞바꾸기 포함) 충돌을 피하려고 일단 큰 번호로 비켜 둠
  update public.prac_problems set no = no + 50 where unit = u and no <= 49;
  for x in select * from json_array_elements(coalesce(p_items, '[]')) loop
    v_id := nullif(x->>'id', '')::uuid; v_type := upper(trim(x->>'type')); v_no := (x->>'no')::int;
    if v_id is not null and exists (select 1 from public.prac_problems where id = v_id and unit = u) then
      update public.prac_problems set type = v_type, no = v_no, name = coalesce(trim(x->>'name'), ''), related = coalesce(trim(x->>'related'), related), active = coalesce((x->>'active')::boolean, true) where id = v_id;
    else
      insert into public.prac_problems (unit, type, no, name, related, active)
      values (u, v_type, v_no, coalesce(trim(x->>'name'), ''), coalesce(trim(x->>'related'), ''), coalesce((x->>'active')::boolean, true)) returning id into v_id;
    end if;
    keep := keep || v_id;
  end loop;
  delete from public.prac_problems p
   where p.unit = u and not (p.id = any(keep)) and not exists (select 1 from public.prac_assign a where a.problem_id = p.id) and not exists (select 1 from public.prac_logs g where g.problem_id = p.id);
  -- 기록 때문에 남겨 둔 질환은 비활성 + 겹치지 않는 번호
  update public.prac_problems p set active = false
   where p.unit = u and not (p.id = any(keep));
  return public.prac_load(p_code, p_unit);
end $$;

update public.prac_problems set related = '재발성 구순 단순포진(HSV-1) · 구순 단순포진 수포기 · 하순 입가 단순포진 · 구강 내 단순포진(경구개, 구개 마취 후)' where unit = '3A' and type = 'A' and no = 1 and related = '';
update public.prac_problems set related = '재발성 아프타성 구내염 경도(하순 점막·혀 좌측) · minor RAS · 주요형 major RAS(연구개)' where unit = '3A' and type = 'A' and no = 2 and related = '';
update public.prac_problems set related = '약물관련 악골괴사증 MRONJ(발치 후 누공·배농)' where unit = '3A' and type = 'A' and no = 3 and related = '';
update public.prac_problems set related = '정중과잉치로 인한 정중이개(SLOB) · 역위 정중과잉치 2개에 의한 정중이개 · 역위 정중과잉치 + #61 만기잔존 · 맹출된 정중과잉치(#21 회전·구개측 전위) · 감별: 상순소대 고위 부착' where unit = '3A' and type = 'A' and no = 4 and related = '';
update public.prac_problems set related = '유구치 #54 증상성 비가역성 치수염 · 레진 하방 이차우식에 의한 비가역성 치수염(#16) · 균열치로 인한 비가역성 치수염(#16)' where unit = '3A' and type = 'A' and no = 5 and related = '';
update public.prac_problems set related = '전치부 치관파절(법랑질·상아질) · 영구전치 치관파절(치근 미완성) · 외상 후 치수괴사 만성 치근단 농양(#21, 누공)' where unit = '3A' and type = 'A' and no = 6 and related = '';
update public.prac_problems set related = '균열치아증후군(#17 생활력 정상) · 균열치아증후군(#36 MOD 아말감) · 균열치로 인한 비가역성 치수염(#16) · 감별: 수직 치근 파절' where unit = '3A' and type = 'A' and no = 7 and related = '';
update public.prac_problems set related = '치은퇴축으로 인한 지각과민 (두근두근: 치아 과민증 — 치은퇴축·치경부 마모)' where unit = '3A' and type = 'C' and no = 1 and related = '';
update public.prac_problems set related = '급성 치주농양 (두근두근: #46 페니실린 알레르기 · 스케일링 후 #37 발열 동반 · 치수 생활력 정상)' where unit = '3A' and type = 'C' and no = 2 and related = '';
update public.prac_problems set related = '진탕 외상' where unit = '3A' and type = 'C' and no = 3 and related = '';
update public.prac_problems set related = '교정 환자 (두근두근: 브라켓 주변 치은염 · 성인 교정 장치 주변 치태성 치은염)' where unit = '3A' and type = 'C' and no = 4 and related = '';
update public.prac_problems set related = '사랑니 발치 (두근두근: 만성 재발성 지치주위염 #38, 아스피린 복용 고혈압)' where unit = '3A' and type = 'C' and no = 5 and related = '';
update public.prac_problems set related = '긴장성 두통 (두근두근: 긴장형 두통, 당뇨 환자·진통제 잦은 복용)' where unit = '3A' and type = 'C' and no = 6 and related = '';
update public.prac_problems set related = '지치주위염 (두근두근: 급성 지치주위염 개구장애 · 만성 재발성 지치주위염 #38)' where unit = '3A' and type = 'C' and no = 7 and related = '';

do $$ declare f text; begin
  foreach f in array array['prac_save_day(text,text,date,int,uuid[],json)','prac_save_problems(text,text,json)'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;
