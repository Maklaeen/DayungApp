begin;

-- Allow unit presidents and secretaries to create signed URLs for documents
-- belonging to applicants in their own unit. Keep the buckets private.
drop policy if exists staff_read_unit_documents on storage.objects;

create policy staff_read_unit_documents
on storage.objects
for select
to authenticated
using (
  bucket_id in (
    'birth_certificates',
    'death_certificates',
    'marriage_certificates',
    'proof_of_residency',
    'valid_ids'
  )
  and exists (
    select 1
    from public.applications a
    join public.dayung_units d on d.id = a.dayung_unit_id
    where storage.objects.name like a.user_id::text || '-%'
      and (d.president_id = auth.uid() or d.secretary_id = auth.uid())
  )
);

commit;
