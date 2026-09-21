begin;

create or replace function public.approve_application(
  p_application_id bigint,
  p_approved_by uuid
)
returns public.applications
language plpgsql
security definer
set search_path = public
as $$
declare
  current_uid uuid := auth.uid();
  applicant_user_id uuid;
  updated_row public.applications;
begin
  if current_uid is null then
    raise exception 'Not authenticated';
  end if;

  if p_approved_by is null then
    raise exception 'Approved user ID is required';
  end if;

  select a.user_id
  into applicant_user_id
  from public.applications a
  where a.id = p_application_id
    and a.status = 'pending';

  if applicant_user_id is null then
    raise exception 'Application status was not updated';
  end if;

  if not exists (
    select 1
    from public.beneficiaries b
    where b.user_id = applicant_user_id
  ) then
    raise exception 'Application requires at least one beneficiary before approval';
  end if;

  update public.applications a
  set
    status = 'approved',
    approved_at = now(),
    approved_by = p_approved_by,
    updated_at = now()
  where a.id = p_application_id
    and a.status = 'pending'
  returning a.* into updated_row;

  if updated_row.id is null then
    raise exception 'Application status was not updated';
  end if;

  return updated_row;
end;
$$;

revoke all on function public.approve_application(bigint, uuid) from public;
grant execute on function public.approve_application(bigint, uuid) to authenticated;

commit;
