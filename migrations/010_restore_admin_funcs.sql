-- 오스키실 예약판 · 업데이트 010 (Supabase 적용 완료)
-- schema.sql을 다시 실행하면 cancel_booking·set_kit이 관리자 코드를 모르는 옛 버전으로 덮어써져요.
-- 그 경우 이 파일을 다시 실행하면 복구돼요.

create or replace function public.cancel_booking(p_code text, p_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_team text; v_admin boolean; n int;
begin
  v_admin := exists (select 1 from public.admins where code = upper(trim(p_code)));
  if v_admin then
    delete from public.bookings where id = p_id;
  else
    select team into v_team from public.leaders where code = upper(trim(p_code));
    if v_team is null then raise exception 'NOT_LEADER'; end if;
    delete from public.bookings where id = p_id and team = v_team;
  end if;
  get diagnostics n = row_count;
  return n > 0;
end $$;

create or replace function public.set_kit(p_code text, p_id text, p_status text, p_who text)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_team text; v_admin boolean;
begin
  v_admin := exists (select 1 from public.admins where code = upper(trim(p_code)));
  select team into v_team from public.leaders where code = upper(trim(p_code));
  if v_team is null and not v_admin then raise exception 'NOT_LEADER'; end if;
  if p_status not in ('in','out') then raise exception 'BAD_STATUS'; end if;
  update public.kits
     set status = p_status,
         who = case when p_status = 'out'
                    then coalesce(nullif(trim(p_who),''), case when v_admin then '관리자' else v_team || '조' end)
                    else '' end,
         at = now()
   where id = p_id;
  return found;
end $$;

drop function if exists public.create_booking(text,date,int,int,int,text,text,text[]);

revoke all on function public.cancel_booking(text,uuid) from public;
revoke all on function public.set_kit(text,text,text,text) from public;
grant execute on function public.cancel_booking(text,uuid) to anon, authenticated;
grant execute on function public.set_kit(text,text,text,text) to anon, authenticated;
