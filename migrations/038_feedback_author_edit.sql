-- 오스키실 예약판 · 업데이트 038
-- 피드백 고칠 때 쓴 사람(이름)도 바꿀 수 있게 (예전에 익명으로 남은 것에 이름 붙이기)
drop function if exists public.prac_fb_edit(text, text, uuid, text);
create or replace function public.prac_fb_edit(p_code text, p_unit text, p_id uuid, p_text text, p_author uuid default null) returns boolean
language plpgsql security definer set search_path = public as $$
declare u text := public.prac_unit_ro(p_code, p_unit);
begin
  if length(trim(coalesce(p_text, ''))) = 0 then raise exception 'EMPTY'; end if;
  if p_author is not null and not exists (select 1 from public.prac_members where id = p_author and unit = u) then raise exception 'BAD_ITEM'; end if;
  update public.prac_fb set text = left(trim(p_text), 2000), author_id = coalesce(p_author, author_id), updated_at = now() where id = p_id and unit = u;
  return found;
end $$;
revoke all on function public.prac_fb_edit(text, text, uuid, text, uuid) from public;
grant execute on function public.prac_fb_edit(text, text, uuid, text, uuid) to anon, authenticated;
