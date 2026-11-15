-- 오스키실 예약판 · 업데이트 056
-- 매일 20:55(KST) pg_cron으로 신청 오픈 순서를 하루씩 밀기 (055의 11/16 1회 작업은 이걸로 대체)
-- 그날 기준 first = 3 + (날짜 - 11/15). 열린 일차 = first .. first+5 (12일차까지), 21:10부터 10분 간격
-- first보다 앞 일차와 창 밖 일차는 신청 막기. 1·2일차는 건드리지 않음. 12일차까지 다 지나면 작업 스스로 해제
create or replace function public.osce_roll_day(p_date date default (now() at time zone 'Asia/Seoul')::date)
returns text language plpgsql security definer set search_path = public as $$
declare f int := 3 + (p_date - date '2026-11-15'); l int := least(f + 5, 12); d int; v_open boolean;
begin
  for d in 3..12 loop
    v_open := d between f and l;
    if not exists (select 1 from public.day_tiers where from_day = d and to_day = d) then
      insert into public.day_tiers (id, from_day, to_day, label, team_min, closed)
      values ((select coalesce(max(id), 0) + 1 from public.day_tiers), d, d, d || '일차', 960, not v_open);
    else
      update public.day_tiers set closed = not v_open, team_min = case when v_open then 960 else team_min end where from_day = d and to_day = d;
    end if;
    if v_open then
      insert into public.open_offsets (exam_day, offset_min) values (d, 10 * (d - f + 1))
      on conflict (exam_day) do update set offset_min = excluded.offset_min;
    end if;
  end loop;
  if f > 12 then
    perform cron.unschedule(jobid) from cron.job where jobname = 'osce-roll-daily';
    return 'done';
  end if;
  return format('open %s..%s', f, l);
end $$;
revoke all on function public.osce_roll_day(date) from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'osce-shift-order-1116';
select cron.schedule('osce-roll-daily', '55 11 * * *', 'select public.osce_roll_day()');
