-- 오스키실 예약판 · 업데이트 016
-- 운영 시간 08:00–22:00 → 07:00–23:00
-- 시작 하한 480분(08:00) → 420분(07:00), 끝 상한 1320분(22:00) → 1380분(23:00)
-- 함수·제약에 들어 있는 숫자만 바꿔서 다시 만들어요 (여러 번 실행해도 안전)

do $$
declare c record; def text;
begin
  -- 1) 표 제약
  for c in select conrelid::regclass as tbl, conname, pg_get_constraintdef(oid) as d
             from pg_constraint
            where connamespace = 'public'::regnamespace and contype = 'c'
              and (pg_get_constraintdef(oid) like '%480%' or pg_get_constraintdef(oid) like '%1320%')
  loop
    def := replace(replace(c.d, '480', '420'), '1320', '1380');
    execute format('alter table %s drop constraint %I', c.tbl, c.conname);
    execute format('alter table %s add constraint %I %s', c.tbl, c.conname, def);
  end loop;

  -- 2) 함수 (신청·변경·연장·사용 금지·고정 시간대)
  for c in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public'
              and p.proname in ('create_booking','update_booking','adjust_booking','admin_add_block','admin_add_fixed')
              and (p.prosrc like '%480%' or p.prosrc like '%1320%')
  loop
    def := pg_get_functiondef(c.oid);
    def := replace(replace(def, '480', '420'), '1320', '1380');
    execute def;
  end loop;
end $$;
