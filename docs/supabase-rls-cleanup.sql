begin;

-- Reviewed from the exported policy list provided on 2026-03-10.
-- Apply in staging first. This file removes clearly over-broad policies and
-- adds a small number of safer replacements where the schema intent is clear.

-- announcements
drop policy if exists ann_select_readable on public.announcements;

-- beneficiaries
drop policy if exists "Allow all select" on public.beneficiaries;

-- claims
drop policy if exists "Allow update for authenticated" on public.claims;

-- dayung_collectors
drop policy if exists "Allow all select" on public.dayung_collectors;

-- payments
drop policy if exists "Allow public select" on public.payments;
drop policy if exists "Allow update on unpaid payments" on public.payments;
drop policy if exists "Allow user to update own payments" on public.payments;

drop policy if exists "Allow treasurer insert payments" on public.payments;
create policy treasurer_insert_own_unit_payments
on public.payments
for insert
to authenticated
with check (
  exists (
    select 1
    from public.dayung_units d
    where d.id = payments.dayung_unit_id
      and d.treasurer_id = auth.uid()
  )
);

-- service_checklist
drop policy if exists "Allow delete for authenticated users" on public.service_checklist;
drop policy if exists "Allow insert for authenticated users" on public.service_checklist;
drop policy if exists "Allow select for authenticated users" on public.service_checklist;
drop policy if exists "Allow update for authenticated users" on public.service_checklist;

-- set_amount
drop policy if exists "Authenticated users can select" on public.set_amount;
drop policy if exists "Allow insert for secretary" on public.set_amount;
drop policy if exists "Allow insert for authenticated" on public.set_amount;

-- users
drop policy if exists "Allow all inserts (dev only)" on public.users;
drop policy if exists "Allow read id and name for all authenticated" on public.users;
drop policy if exists "Allow select for authenticated" on public.users;

-- If the application needs a directory of members, create a dedicated view with
-- only the safe columns instead of exposing the full users table.

-- audit_logs
drop policy if exists "Enable read access for all users" on public.audit_logs;
drop policy if exists "public insert" on public.audit_logs;
drop policy if exists "Enable insert for authenticated users only" on public.audit_logs;

create policy audit_logs_insert_service_role
on public.audit_logs
for insert
to service_role
with check (true);

-- If audit logs must be viewed in-app, replace this with a narrower admin-only
-- policy or expose a filtered RPC/view instead of raw table reads.

-- gcash_qr_uploads
drop policy if exists "Allow read for all" on public.gcash_qr_uploads;

-- storage.objects
drop policy if exists "Public Read" on storage.objects;
drop policy if exists "allow upload valid ID 1yzldcd_1" on storage.objects;
drop policy if exists "allow users to upload and read QR images 11ps9kh_0" on storage.objects;
drop policy if exists "allow users to upload and read QR images 11ps9kh_1" on storage.objects;
drop policy if exists "allow users to upload and read QR images 11ps9kh_2" on storage.objects;
drop policy if exists "Allow users to upload and read QR images 11ps9kh_1" on storage.objects;

-- Keep owner-only storage access unless a bucket is intentionally public.
-- This means the following generic policies remain useful:
--   Allow authenticated insert   => auth.uid() = owner
--   Allow authenticated select   => auth.uid() = owner
--   Allow authenticated update   => auth.uid() = owner
--   Allow authenticated delete   => auth.uid() = owner

-- Optional follow-up: tighten dayung_units if officer assignment columns or
-- internal operational fields should not be visible to all authenticated users.
-- drop policy if exists public_can_read_all_units on public.dayung_units;
-- drop policy if exists dayung_units_select_auth on public.dayung_units;

commit;