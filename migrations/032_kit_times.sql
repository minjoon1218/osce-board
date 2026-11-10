-- 오스키실 예약판 · 업데이트 032
-- 재료를 시간대별로 신청: bookings.kit_times = [{"k":"anes-1","s":600,"e":660}, ...]
--   - kits에 있는데 kit_times에 없는 재료 = 신청 시간 전체
--   - 같은 재료 세트가 겹치는지는 '실제 쓰는 시간'끼리 비교 (kit_conflict / pick_kits)
--   - create_booking / update_booking 에 p_kit_times(선택) 추가, 연장·조기 퇴실 때 시간 자동 정리

alter table public.bookings add column if not exists kit_times jsonb not null default '[]';

-- 재료별 실제 사용 구간
create or replace function public.kit_eff(p_kits text[], p_times jsonb, p_s int, p_e int)
returns table(k text, s int, e int) language sql immutable as $$
  select kk, coalesce(t.s, p_s), coalesce(t.e, p_e)
    from unnest(coalesce(p_kits, '{}')) kk
    left join lateral (select (j->>'s')::int s, (j->>'e')::int e
                         from jsonb_array_elements(coalesce(p_times, '[]'::jsonb)) j where j->>'k' = kk) t on true;
$$;

-- 시간 지정이 올바른지: 신청 시간 안, 30분 단위, 시작<끝, kits에 있는 재료만
create or replace function public.kit_times_ok(p_kits text[], p_times jsonb, p_s int, p_e int)
returns boolean language sql immutable as $$
  select not exists (
    select 1 from jsonb_array_elements(coalesce(p_times, '[]'::jsonb)) j
     where not ((j->>'k') = any(coalesce(p_kits, '{}')))
        or (j->>'s')::int is null or (j->>'e')::int is null
        or (j->>'s')::int < p_s or (j->>'e')::int > p_e or (j->>'s')::int >= (j->>'e')::int
        or (j->>'s')::int % 30 <> 0 or (j->>'e')::int % 30 <> 0);
$$;

-- 저장용 정리: kits에 없는 재료 빼고, 신청 시간 밖은 잘라내고, 시간 전체와 같으면 지움
create or replace function public.kit_times_norm(p_kits text[], p_times jsonb, p_s int, p_e int)
returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(jsonb_build_object('k', k, 's', s2, 'e', e2) order by k, s2), '[]'::jsonb)
    from (select j->>'k' k, greatest((j->>'s')::int, p_s) s2, least((j->>'e')::int, p_e) e2
            from jsonb_array_elements(coalesce(p_times, '[]'::jsonb)) j
           where (j->>'k') = any(coalesce(p_kits, '{}'))) x
   where s2 < e2 and not (s2 = p_s and e2 = p_e);
$$;

create or replace function public.kit_conflict(p_date date, p_kits text[], p_times jsonb, p_s int, p_e int, p_exclude uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.kit_eff(p_kits, p_times, p_s, p_e) m
      join public.bookings o on o.date = p_date and o.id is distinct from p_exclude and m.k = any(o.kits)
      join lateral public.kit_eff(o.kits, o.kit_times, o.start_min, o.end_min) x on x.k = m.k
     where int4range(m.s, m.e) && int4range(x.s, x.e));
$$;

create or replace function public.pick_kits(p_date date, p_start int, p_end int, p_types text[], p_exclude uuid)
returns text[] language plpgsql stable security definer set search_path = public as $$
declare t text; s int; out text[] := '{}';
begin
  foreach t in array coalesce(p_types,'{}') loop
    for s in 1..2 loop
      if not public.kit_conflict(p_date, array[t||'-'||s], '[]'::jsonb, p_start, p_end, p_exclude) then
        out := out || (t||'-'||s); exit;
      end if;
    end loop;
  end loop;
  return out;
end $$;

drop function if exists public.create_booking(text,date,int,int,int,text,text,text[],text);
drop function if exists public.update_booking(text,uuid,date,int,int,int,text,text,text[],text);

create or replace function public.create_booking(
  p_code text, p_date date, p_room int, p_start int, p_dur int,
  p_day text, p_content text, p_kits text[], p_team text default null, p_kit_times jsonb default null
) returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_team text; v_admin boolean; v_row public.bookings; v_walk boolean := false;
  v_now timestamp := now() at time zone 'Asia/Seoul';
begin
  v_admin := exists (select 1 from public.admins where code = upper(trim(p_code)));
  if v_admin then
    v_team := upper(trim(p_team));
    if v_team is null or not exists (select 1 from public.leaders where team = v_team) then
      raise exception 'BAD_TEAM';
    end if;
  else
    select team into v_team from public.leaders where code = upper(trim(p_code));
    if v_team is null then raise exception 'NOT_LEADER'; end if;
    if p_date < v_now::date
       or (p_date = v_now::date and p_start + p_dur <= extract(hour from v_now)::int*60 + extract(minute from v_now)::int) then
      raise exception 'PAST';
    end if;
    if p_date > public.last_bookable_for(v_team) then raise exception 'TOO_FAR'; end if;
    v_walk := public.is_walkin(p_date, p_start);
  end if;

  if p_dur is null or p_dur < 30 or p_dur % 30 <> 0 then raise exception 'BAD_DURATION'; end if;
  if not v_admin and p_dur not in (60,120,180) then raise exception 'BAD_DURATION'; end if;
  if p_start < 420 or p_start + p_dur > 1380 then raise exception 'BAD_RANGE'; end if;
  if not v_admin and exists (select 1 from public.blocks k
             where k.date = p_date and p_room = any(k.rooms) and int4range(k.start_min,k.end_min) && int4range(p_start,p_start+p_dur)) then
    raise exception 'BLOCKED';
  end if;
  if exists (select 1 from public.rooms where room = p_room and not open) then raise exception 'ROOM_CLOSED'; end if;
  if not v_admin then
    perform public.check_unit_limits(v_team, p_date, p_room, p_start, p_start + p_dur, null, v_walk);
  end if;
  if not public.kit_times_ok(p_kits, p_kit_times, p_start, p_start + p_dur) then raise exception 'BAD_KIT_TIME'; end if;
  if public.kit_conflict(p_date, p_kits, p_kit_times, p_start, p_start + p_dur, null) then raise exception 'KIT_TAKEN'; end if;
  insert into public.bookings(date,room,start_min,end_min,day_label,team,content,kits,walkin,bonus,kit_times)
  values (p_date,p_room,p_start,p_start+p_dur,coalesce(p_day,''),v_team,coalesce(p_content,''),coalesce(p_kits,'{}'),v_walk,v_admin,public.kit_times_norm(p_kits, p_kit_times, p_start, p_start + p_dur))
  returning * into v_row;
  return v_row;
end $$;

create or replace function public.update_booking(
  p_code text, p_id uuid, p_date date, p_room int, p_start int, p_dur int,
  p_day text, p_content text, p_kits text[], p_team text default null, p_kit_times jsonb default null
) returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_team text; v_admin boolean; b public.bookings; v_row public.bookings;
  v_now timestamp := now() at time zone 'Asia/Seoul';
  v_nowmin int := extract(hour from v_now)::int * 60 + extract(minute from v_now)::int;
  v_locked boolean := false; v_moved boolean; v_walk boolean := false;
begin
  v_admin := exists (select 1 from public.admins where code = upper(trim(p_code)));
  if not v_admin then
    select team into v_team from public.leaders where code = upper(trim(p_code));
    if v_team is null then raise exception 'NOT_LEADER'; end if;
  end if;

  select * into b from public.bookings where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  v_moved := p_date <> b.date or p_room <> b.room or p_start <> b.start_min or p_start + p_dur <> b.end_min;

  if v_admin then
    v_team := coalesce(nullif(upper(trim(p_team)), ''), b.team);
    if not exists (select 1 from public.leaders where team = v_team) then raise exception 'BAD_TEAM'; end if;
  else
    if b.team <> v_team then raise exception 'NOT_YOURS'; end if;
    if b.date < v_now::date or (b.date = v_now::date and b.end_min <= v_nowmin) then raise exception 'ENDED'; end if;
    v_locked := b.fixed_id is not null or (b.date = v_now::date and b.start_min <= v_nowmin);
    if v_locked and v_moved then
      if b.fixed_id is not null then raise exception 'FIXED_TIME'; else raise exception 'STARTED'; end if;
    end if;
    if not v_locked then
      if p_date < v_now::date or (p_date = v_now::date and p_start <= v_nowmin) then raise exception 'PAST'; end if;
      if p_date > public.last_bookable_for(v_team) and p_date <> b.date then raise exception 'TOO_FAR'; end if;
    end if;
    v_walk := public.is_walkin(p_date, p_start);
  end if;

  if p_dur is null or p_dur < 30 or p_dur % 30 <> 0 then raise exception 'BAD_DURATION'; end if;
  if not v_admin and not v_locked and p_dur not in (60,120,180) and p_dur <> b.end_min - b.start_min then raise exception 'BAD_DURATION'; end if;
  if p_start < 420 or p_start + p_dur > 1380 then raise exception 'BAD_RANGE'; end if;

  if not v_admin and not v_locked and v_moved then
    if exists (select 1 from public.blocks k
               where k.date = p_date and p_room = any(k.rooms)
                 and int4range(k.start_min,k.end_min) && int4range(p_start,p_start+p_dur)) then
      raise exception 'BLOCKED';
    end if;
    perform public.check_unit_limits(v_team, p_date, p_room, p_start, p_start + p_dur, b.id, v_walk);
  end if;
  if p_room <> b.room and exists (select 1 from public.rooms where room = p_room and not open) then
    raise exception 'ROOM_CLOSED';
  end if;
  if not public.kit_times_ok(p_kits, p_kit_times, p_start, p_start + p_dur) then raise exception 'BAD_KIT_TIME'; end if;
  if public.kit_conflict(p_date, p_kits, p_kit_times, p_start, p_start + p_dur, b.id) then raise exception 'KIT_TAKEN'; end if;

  update public.bookings
     set date = p_date, room = p_room, start_min = p_start, end_min = p_start + p_dur,
         day_label = coalesce(p_day,''), team = v_team, content = coalesce(p_content,''),
         kits = coalesce(p_kits,'{}'), kit_times = public.kit_times_norm(p_kits, p_kit_times, p_start, p_start + p_dur),
         walkin = case when v_moved then (v_walk and not v_admin) else b.walkin end
   where id = b.id
  returning * into v_row;
  return v_row;
end $$;

create or replace function public.adjust_booking(p_code text, p_id uuid, p_delta int)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_admin boolean; v_team text; b public.bookings; v_row public.bookings;
  v_now timestamp := now() at time zone 'Asia/Seoul';
  v_nowmin int := extract(hour from v_now)::int * 60 + extract(minute from v_now)::int;
  v_end int;
begin
  if p_delta not in (-60, -30, 30, 60) then raise exception 'BAD_DELTA'; end if;
  v_admin := exists (select 1 from public.admins where code = upper(trim(p_code)));
  if not v_admin then
    select team into v_team from public.leaders where code = upper(trim(p_code));
    if v_team is null then raise exception 'NOT_LEADER'; end if;
  end if;

  select * into b from public.bookings where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if not v_admin then
    if b.team <> v_team then raise exception 'NOT_YOURS'; end if;
    if b.date <> v_now::date or v_nowmin < b.start_min or v_nowmin >= b.end_min then
      raise exception 'NOT_IN_USE';
    end if;
  end if;

  v_end := b.end_min + p_delta;
  if p_delta < 0 then
    if v_end <= b.start_min or (not v_admin and v_end <= v_nowmin) then raise exception 'TOO_SHORT'; end if;
  else
    if v_end > 1380 then raise exception 'CLOSE_TIME'; end if;
    if not v_admin and v_end - b.start_min > 180 then raise exception 'TOO_LONG'; end if;
    -- 시간을 따로 정한 재료는 그대로, 통째로 빌린 재료만 같이 늘어남
    if public.kit_conflict(b.date, b.kits, b.kit_times, b.start_min, v_end, b.id) then raise exception 'KIT_TAKEN'; end if;
    if not v_admin then
      if exists (select 1 from public.blocks k
                 where k.date = b.date and b.room = any(k.rooms)
                   and int4range(k.start_min, k.end_min) && int4range(b.end_min, v_end)) then
        raise exception 'BLOCKED';
      end if;
      if exists (select 1 from public.rooms where room = b.room and not open) then raise exception 'ROOM_CLOSED'; end if;
      -- 사용 중 연장 = 당일 빈자리와 같음: 하루 상한은 안 봄, 동시 방·연속 3시간만
      perform public.check_unit_limits(b.team, b.date, b.room, b.start_min, v_end, b.id,
                                       b.walkin or public.is_walkin(b.date, b.end_min));
    end if;
  end if;

  update public.bookings set end_min = v_end, kit_times = public.kit_times_norm(b.kits, b.kit_times, b.start_min, v_end)
   where id = b.id returning * into v_row;
  return v_row;
end $$;

-- 관리자 재료 지정: 빠진 재료의 시간 지정도 정리
create or replace function public.admin_set_kits(p_code text, p_id uuid, p_kit_types text[], p_series boolean default false)
returns json language plpgsql security definer set search_path = public as $$
declare b public.bookings; r record; v_kits text[]; keep text[]; t text; n int := 0; short json[] := '{}';
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  select * into b from public.bookings where id = p_id;
  if not found then raise exception 'NOT_FOUND'; end if;
  if p_series and b.fixed_id is not null then
    update public.fixed_slots set kit_types = coalesce(p_kit_types,'{}') where id = b.fixed_id;
  end if;
  for r in select * from public.bookings
            where (p_series and b.fixed_id is not null and fixed_id = b.fixed_id and date >= (now() at time zone 'Asia/Seoul')::date)
               or id = p_id
            order by date
  loop
    select coalesce(array_agg(k),'{}') into keep from unnest(r.kits) k where split_part(k,'-',1) = any(coalesce(p_kit_types,'{}'));
    v_kits := keep;
    foreach t in array coalesce(p_kit_types,'{}') loop
      if not exists (select 1 from unnest(keep) k where split_part(k,'-',1) = t) then
        v_kits := v_kits || public.pick_kits(r.date, r.start_min, r.end_min, array[t], r.id);
        if not exists (select 1 from unnest(v_kits) k where split_part(k,'-',1) = t) then
          short := short || json_build_object('date', r.date, 'kit', t);
        end if;
      end if;
    end loop;
    update public.bookings set kits = v_kits, kit_times = public.kit_times_norm(v_kits, r.kit_times, r.start_min, r.end_min) where id = r.id;
    n := n + 1;
  end loop;
  return json_build_object('updated', n, 'short', to_json(short));
end $$;

revoke all on function public.kit_conflict(date,text[],jsonb,int,int,uuid) from public, anon, authenticated;
revoke all on function public.pick_kits(date,int,int,text[],uuid) from public, anon, authenticated;
do $$ declare f text; begin
  foreach f in array array[
    'create_booking(text,date,int,int,int,text,text,text[],text,jsonb)',
    'update_booking(text,uuid,date,int,int,int,text,text,text[],text,jsonb)',
    'adjust_booking(text,uuid,int)','admin_set_kits(text,uuid,text[],boolean)'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;
