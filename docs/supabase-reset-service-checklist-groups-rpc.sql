begin;

create or replace function public.reset_service_checklist_groups(
  p_service_checklist_id bigint
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  current_uid uuid := auth.uid();
  updated_count integer;
begin
  if current_uid is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1
    from public.service_checklist sc
    join public.dayung_units d on d.id = sc.dayung_unit_id
    where sc.id = p_service_checklist_id
      and (
        d.president_id = current_uid
        or d.secretary_id = current_uid
        or d.treasurer_id = current_uid
      )
  ) then
    raise exception 'Not allowed to reset this service checklist';
  end if;

  update public.service_checklist_participants p
  set "group" = 'no_groups'
  where p.service_checklist_id = p_service_checklist_id;

  get diagnostics updated_count = row_count;
  return updated_count;
end;
$$;

revoke all on function public.reset_service_checklist_groups(bigint) from public;
grant execute on function public.reset_service_checklist_groups(bigint) to authenticated;

create or replace function public.save_service_checklist_participants(
  p_service_checklist_id bigint,
  p_participant_rows jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  current_uid uuid := auth.uid();
  updated_count integer;
begin
  if current_uid is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1
    from public.service_checklist sc
    join public.dayung_units d on d.id = sc.dayung_unit_id
    where sc.id = p_service_checklist_id
      and (
        d.president_id = current_uid
        or d.secretary_id = current_uid
        or d.treasurer_id = current_uid
      )
  ) then
    raise exception 'Not allowed to save this service checklist';
  end if;

  if p_participant_rows is null or jsonb_typeof(p_participant_rows) <> 'array' then
    raise exception 'Participant rows must be a JSON array';
  end if;

  insert into public.service_checklist_participants (
    service_checklist_id,
    user_id,
    "group",
    dayung_unit_id,
    created_at
  )
  select
    p_service_checklist_id,
    row_data.user_id,
    row_data.group_name,
    row_data.dayung_unit_id,
    coalesce(row_data.created_at, now())
  from jsonb_to_recordset(p_participant_rows) as row_data(
    user_id uuid,
    group_name text,
    dayung_unit_id bigint,
    created_at timestamptz
  )
  on conflict (service_checklist_id, user_id)
  do update set
    "group" = excluded."group",
    dayung_unit_id = excluded.dayung_unit_id;

  get diagnostics updated_count = row_count;
  return updated_count;
end;
$$;

revoke all on function public.save_service_checklist_participants(bigint, jsonb) from public;
grant execute on function public.save_service_checklist_participants(bigint, jsonb) to authenticated;

commit;