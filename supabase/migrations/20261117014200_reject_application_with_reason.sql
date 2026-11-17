create or replace function public.reject_application_with_reason(
  p_application_id bigint,
  p_rejection_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  reason text := nullif(btrim(p_rejection_reason), '');
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if reason is null then
    raise exception 'A rejection reason is required';
  end if;

  if char_length(reason) > 500 then
    raise exception 'Rejection reason must be 500 characters or fewer';
  end if;

  perform public.reject_application(p_application_id);

  update public.applications
  set
    rejection_reason = reason,
    rejection_date = now()
  where id = p_application_id
    and status = 'rejected';

  if not found then
    raise exception 'Application rejection details were not saved';
  end if;
end;
$$;

revoke all on function public.reject_application_with_reason(bigint, text)
  from public;
grant execute on function public.reject_application_with_reason(bigint, text)
  to authenticated;

notify pgrst, 'reload schema';
