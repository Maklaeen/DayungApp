begin;

create or replace function public.remove_member_application(p_application_id bigint)
returns public.applications
language plpgsql
security definer
set search_path = public
as $$
declare
  current_uid uuid := auth.uid();
  updated_row public.applications;
begin
  if current_uid is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1
    from public.applications a
    join public.dayung_units d on d.id = a.dayung_unit_id
    where a.id = p_application_id
      and a.status = 'approved'
      and (
        d.president_id = current_uid
        or d.secretary_id = current_uid
      )
  ) then
    raise exception 'Not allowed to remove this member';
  end if;

  update public.applications a
  set
    status = 'removed',
    updated_at = now()
  where a.id = p_application_id
    and a.status = 'approved'
  returning a.* into updated_row;

  if updated_row.id is null then
    raise exception 'Application status was not updated';
  end if;

  return updated_row;
end;
$$;

revoke all on function public.remove_member_application(bigint) from public;
grant execute on function public.remove_member_application(bigint) to authenticated;

commit;