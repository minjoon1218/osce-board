-- 오스키실 예약판 · 업데이트 009
-- 관리자 지정 '고정 시간대' (조·방·요일·시간·기간 → 해당 날짜마다 신청 자동 생성)
-- + 관리자 재료 지정/추가 (고정 시간대 전체 또는 신청 한 건)

-- 1) 고정 시간대 정의 ------------------------------------------------------
create table if not exists public.fixed_slots (
  id         uuid primary key default gen_random_uuid(),
  team       text not null references public.leaders(team) on update cascade,
  room       int  not null check (room between 1 and 6),
  weekdays   int[] not null,                      -- 0=일 … 6=토
  start_min  int  not null check (start_min >= 480),
  end_min    int  not null check (end_min <= 1320 and end_min > start_min),
  date_from  date not null,
  date_to    date not null check (date_to >= date_from),
  kit_types  text[] not null default '{}',        -- 예: {anes,ext}
  content    text not null default '',
  created_at timestamptz not null default now()
);
alter table public.fixed_slots enable row level security;
drop policy if exists "read fixed_slots" on public.fixed_slots;
create policy "read fixed_slots" on public.fixed_slots for select using (true);

-- 고정 시간대 신청은 3시간 제한 예외
do $$ declare c record; begin
  for c in select conname from pg_constraint
           where conrelid = 'public.bookings'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) like '%end_min%'
  loop execute format('alter table public.bookings drop constraint %I', c.conname); end loop;
end $$;
alter table public.bookings add constraint bookings_time_check
  check (end_min <= 1320 and end_min > start_min and (end_min - start_min <= 180 or fixed_id is not null));

-- 2) 재료 세트 자동 배정: 종류 목록 → 그 시간에 비어 있는 세트(1/2) ----------------
create or replace function public.pick_kits(p_date date, p_start int, p_end int, p_types text[], p_exclude uuid)
returns text[] language plpgsql stable security definer set search_path = public as $$
declare t text; s int; out text[] := '{}';
begin
  foreach t in array coalesce(p_types,'{}') loop
    for s in 1..2 loop
      if not exists (select 1 from public.bookings b
                     where b.date = p_date and b.id is distinct from p_exclude
                       and (t||'-'||s) = any(b.kits)
                       and int4range(b.start_min,b.end_min) && int4range(p_start,p_end)) then
        out := out || (t||'-'||s); exit;
      end if;
    end loop;
  end loop;
  return out;
end $$;

-- 3) 관리자: 고정 시간대 추가 → 날짜별 신청 생성 ------------------------------
create or replace function public.admin_add_fixed(
  p_code text, p_team text, p_room int, p_weekdays int[], p_start int, p_end int,
  p_from date, p_to date, p_kit_types text[], p_content text
) returns json
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid; v_team text := upper(trim(p_team)); d date; v_kits text[];
  n_ok int := 0; skipped json[] := '{}'; v_who text; missing text[];
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  if not exists (select 1 from public.leaders where team = v_team) then raise exception 'BAD_TEAM'; end if;
  if p_start < 480 or p_end > 1320 or p_end <= p_start then raise exception 'BAD_RANGE'; end if;
  if p_to < p_from or p_to - p_from > 180 then raise exception 'BAD_PERIOD'; end if;
  if coalesce(array_length(p_weekdays,1),0) = 0 then raise exception 'NO_DAYS'; end if;

  insert into public.fixed_slots (team, room, weekdays, start_min, end_min, date_from, date_to, kit_types, content)
  values (v_team, p_room, p_weekdays, p_start, p_end, p_from, p_to, coalesce(p_kit_types,'{}'), coalesce(p_content,''))
  returning id into v_id;

  d := greatest(p_from, (now() at time zone 'Asia/Seoul')::date);
  while d <= p_to loop
    if extract(dow from d)::int = any(p_weekdays) then
      select team into v_who from public.bookings b
       where b.date = d and b.room = p_room and int4range(b.start_min,b.end_min) && int4range(p_start,p_end) limit 1;
      if v_who is not null then
        skipped := skipped || json_build_object('date', d, 'reason', v_who||'조 신청과 겹침');
      elsif exists (select 1 from public.bookings b where b.date = d and b.team = v_team
                    and int4range(b.start_min,b.end_min) && int4range(p_start,p_end)) then
        skipped := skipped || json_build_object('date', d, 'reason', '같은 조가 다른 방 사용 중');
      else
        v_kits := public.pick_kits(d, p_start, p_end, p_kit_types, null);
        select array_agg(t) into missing from unnest(coalesce(p_kit_types,'{}')) t
         where not exists (select 1 from unnest(v_kits) k where split_part(k,'-',1) = t);
        insert into public.bookings (date, room, start_min, end_min, day_label, team, content, kits, fixed_id)
        values (d, p_room, p_start, p_end, '', v_team, coalesce(p_content,''), v_kits, v_id);
        n_ok := n_ok + 1;
        if missing is not null then
          skipped := skipped || json_build_object('date', d, 'reason', '재료 부족: '||array_to_string(missing, ','), 'created', true);
        end if;
      end if;
    end if;
    d := d + 1;
  end loop;
  return json_build_object('id', v_id, 'created', n_ok, 'notes', to_json(skipped));
end $$;

-- 4) 관리자: 고정 시간대 삭제 (지난 기록은 남기고 오늘 이후 신청만 삭제) ---------------
create or replace function public.admin_delete_fixed(p_code text, p_id uuid)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not exists (select 1 from public.admins where code = upper(trim(p_code))) then raise exception 'NOT_ADMIN'; end if;
  delete from public.bookings where fixed_id = p_id and date >= (now() at time zone 'Asia/Seoul')::date;
  get diagnostics n = row_count;
  delete from public.fixed_slots where id = p_id;
  return n;
end $$;

-- 5) 관리자: 재료 지정/추가 (신청 한 건 또는 고정 시간대의 오늘 이후 전체) -------------
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
    -- 이미 가진 세트 중 계속 쓰는 종류는 그대로, 새 종류만 빈 세트 배정
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
    update public.bookings set kits = v_kits where id = r.id;
    n := n + 1;
  end loop;
  return json_build_object('updated', n, 'short', to_json(short));
end $$;

-- 6) 권한 ---------------------------------------------------------------
revoke all on function public.pick_kits(date,int,int,text[],uuid) from public;
revoke all on function public.admin_add_fixed(text,text,int,int[],int,int,date,date,text[],text) from public;
revoke all on function public.admin_delete_fixed(text,uuid) from public;
revoke all on function public.admin_set_kits(text,uuid,text[],boolean) from public;
grant execute on function public.admin_add_fixed(text,text,int,int[],int,int,date,date,text[],text) to anon, authenticated;
grant execute on function public.admin_delete_fixed(text,uuid) to anon, authenticated;
grant execute on function public.admin_set_kits(text,uuid,text[],boolean) to anon, authenticated;

do $$ begin
  alter publication supabase_realtime add table public.fixed_slots;
exception when duplicate_object then null; end $$;
