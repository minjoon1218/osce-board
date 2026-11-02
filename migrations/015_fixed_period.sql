-- 오스키실 예약판 · 업데이트 015
-- 고정 시간대 기간 변경: 늘리면 새 날짜에 신청 추가, 줄이면 기간 밖 '오늘 이후' 신청 삭제 (지난 기록은 유지)

create or replace function public.admin_set_fixed_period(p_code text, p_id uuid, p_from date, p_to date)
returns json language plpgsql security definer set search_path = public as $$
declare
  f public.fixed_slots; d date; v_today date := (now() at time zone 'Asia/Seoul')::date;
  n_add int := 0; n_del int := 0; notes json[] := '{}'; v_who text; v_kits text[]; missing text[];
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  select * into f from public.fixed_slots where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if p_to < p_from or p_to - p_from > 180 then raise exception 'BAD_PERIOD'; end if;

  -- 기간 밖으로 빠진 오늘 이후 신청 삭제
  delete from public.bookings
   where fixed_id = p_id and date >= v_today and (date < p_from or date > p_to);
  get diagnostics n_del = row_count;

  update public.fixed_slots set date_from = p_from, date_to = p_to where id = p_id;

  -- 기간 안에서 아직 신청이 없는 날짜 채우기
  d := greatest(p_from, v_today);
  while d <= p_to loop
    if extract(dow from d)::int = any(f.weekdays)
       and not exists (select 1 from public.bookings where fixed_id = p_id and date = d) then
      v_who := null;
      select team into v_who from public.bookings b
       where b.date = d and b.room = f.room and int4range(b.start_min,b.end_min) && int4range(f.start_min,f.end_min) limit 1;
      if v_who is not null then
        notes := notes || json_build_object('date', d, 'reason', v_who||'조 신청과 겹침');
      elsif exists (select 1 from public.bookings b where b.date = d and b.team = f.team
                    and int4range(b.start_min,b.end_min) && int4range(f.start_min,f.end_min)) then
        notes := notes || json_build_object('date', d, 'reason', '같은 조가 다른 방 사용 중');
      else
        v_kits := public.pick_kits(d, f.start_min, f.end_min, f.kit_types, null);
        missing := null;
        select array_agg(t) into missing from unnest(f.kit_types) t
         where not exists (select 1 from unnest(v_kits) k where split_part(k,'-',1) = t);
        insert into public.bookings (date, room, start_min, end_min, day_label, team, content, kits, fixed_id)
        values (d, f.room, f.start_min, f.end_min, '', f.team, f.content, v_kits, p_id);
        n_add := n_add + 1;
        if missing is not null then
          notes := notes || json_build_object('date', d, 'reason', '재료 부족: '||array_to_string(missing, ','), 'created', true);
        end if;
      end if;
    end if;
    d := d + 1;
  end loop;
  return json_build_object('added', n_add, 'removed', n_del, 'notes', to_json(notes));
end $$;

revoke all on function public.admin_set_fixed_period(text,uuid,date,date) from public;
grant execute on function public.admin_set_fixed_period(text,uuid,date,date) to anon, authenticated;
