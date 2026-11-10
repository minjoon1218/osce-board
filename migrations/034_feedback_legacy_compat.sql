-- 오스키실 예약판 · 업데이트 034
-- 예전 화면(캐시)에서 피드백을 저장해도 새 말풍선(prac_fb)으로 들어가게: 같은 칸에 30분 안에 쓴 익명 말풍선이 있으면 그걸 고치고, 없으면 새로 추가
create or replace function public.prac_feedback(p_code text, p_unit text, p_id uuid, p_text text) returns boolean
language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit_ro(p_code, p_unit); a record; t text := left(trim(coalesce(p_text, '')), 2000); v uuid;
begin
  select x.slot, x.member_id, x.problem_id, d.id day_id into a
    from public.prac_assign x join public.prac_days d on d.id = x.day_id where x.id = p_id and d.unit = u;
  if not found then return false; end if;
  select id into v from public.prac_fb
   where day_id = a.day_id and slot = a.slot and member_id = a.member_id and problem_id = a.problem_id
     and author_id is null and created_at > now() - interval '30 minutes' order by created_at desc limit 1;
  if t = '' then
    if v is not null then delete from public.prac_fb where id = v; end if;
  elsif v is not null then
    update public.prac_fb set text = t, updated_at = now() where id = v;
  else
    insert into public.prac_fb (unit, day_id, slot, member_id, problem_id, text) values (u, a.day_id, a.slot, a.member_id, a.problem_id, t);
  end if;
  return true;
end $$;

create or replace function public.prac_edit_log(p_code text, p_unit text, p_id uuid, p_feedback text) returns boolean
language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit_ro(p_code, p_unit); g record; t text := left(trim(coalesce(p_feedback, '')), 2000); v uuid;
begin
  select id, member_id, problem_id into g from public.prac_logs where id = p_id and unit = u;
  if not found then return false; end if;
  select id into v from public.prac_fb where log_id = g.id and author_id is null and created_at > now() - interval '30 minutes' order by created_at desc limit 1;
  if t = '' then
    if v is not null then delete from public.prac_fb where id = v; end if;
  elsif v is not null then
    update public.prac_fb set text = t, updated_at = now() where id = v;
  else
    insert into public.prac_fb (unit, log_id, member_id, problem_id, text) values (u, g.id, g.member_id, g.problem_id, t);
  end if;
  return true;
end $$;
