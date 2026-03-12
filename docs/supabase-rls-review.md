# Supabase RLS Review

Reviewed from the exported policy list provided on 2026-03-10.

Latest verification on 2026-03-10 from the follow-up export and bucket metadata:

- The risky permissive policies are still present in the export.
- This means the cleanup in `docs/supabase-rls-cleanup.sql` has not been applied yet, or it was not applied to the project that produced the latest export.
- All current storage buckets are marked `public = true`.
- The current public buckets are `avatars`, `birth_certificates`, `death_certificates`, `gcash_qr_images`, `marriage_certificates`, `proof_of_residency`, and `valid_ids`.
- As exported, `birth_certificates`, `death_certificates`, `marriage_certificates`, `proof_of_residency`, and `valid_ids` should be treated as exposed sensitive-document buckets.

## Overall Verdict

RLS is present across many DayungApp tables and storage objects, so the database is not missing policy coverage.
However, several permissive policies use `USING (true)` or `WITH CHECK (true)` in ways that defeat the stricter role-aware rules on the same table.

In PostgreSQL RLS, permissive policies are effectively combined with `OR` for the same command. A single broad policy can therefore reopen access that narrower policies attempted to restrict.

## Immediate Failures

These policies should be treated as security bugs until removed or replaced:

- `public.users`
  - `Allow select for authenticated`
  - `Allow read id and name for all authenticated`
  - `Allow all inserts (dev only)`
  - Impact: broad user-row exposure and dev-only insert behavior left active.

- `public.payments`
  - `Allow public select`
  - `Allow update on unpaid payments`
  - `Allow user to update own payments`
  - Impact: weakens the more specific member, collector, and secretary payment controls.

- `public.claims`
  - `Allow update for authenticated`
  - Impact: any authenticated user can update claims, overriding the secretary/member-specific update policies.

- `public.beneficiaries`
  - `Allow all select`
  - Impact: weakens owner-only and secretary same-unit read policies.

- `public.announcements`
  - `ann_select_readable`
  - Impact: makes all announcements readable regardless of unit membership.

- `public.dayung_collectors`
  - `Allow all select`
  - Impact: exposes collector assignments beyond self or same-unit staff.

- `public.audit_logs`
  - `Enable read access for all users`
  - `public insert`
  - Impact: destroys audit confidentiality and integrity.

- `public.gcash_qr_uploads`
  - `Allow read for all`
  - Impact: uploaded payment-related assets are broadly readable.

- `public.service_checklist`
  - `Allow select for authenticated users`
  - `Allow insert for authenticated users`
  - `Allow update for authenticated users`
  - `Allow delete for authenticated users`
  - Impact: table is effectively wide open to any authenticated account.

- `public.set_amount`
  - `Authenticated users can select`
  - `Allow insert for secretary`
  - `Allow insert for authenticated`
  - Impact: broad authenticated access with unclear business restrictions.

- `storage.objects`
  - `Public Read`
  - `allow upload valid ID 1yzldcd_1`
  - `allow users to upload and read QR images 11ps9kh_0`
  - `allow users to upload and read QR images 11ps9kh_1`
  - `allow users to upload and read QR images 11ps9kh_2`
  - `Allow users to upload and read QR images 11ps9kh_1`
  - Impact: sensitive storage buckets are opened beyond owner-only access.

## Policies That Look Directionally Correct

These are closer to least-privilege, though they still depend on broad policies above being removed:

- `public.announcement_reads`: owner-only insert/select/update by `user_id = auth.uid()`.
- `public.notifications`: recipient-only select/update plus staff-scoped inserts.
- `public.user_preferences`: owner-only insert/select/update.
- `public.applications`: self-read and unit-leader read policies exist.
- `public.announcements`: president write and unit-member read policies exist.
- `public.dayung_rules`: president write and unit-member read policies exist.
- `public.dayung_collectors`: president write/delete and self or staff-scoped read policies exist.
- `public.users`: self-read and same-unit staff-scoped policies exist.
- `public.payments`: member-own, collector-own-unit, and secretary-own-unit policies exist.
- `public.claims`: member-own and secretary same-unit policies exist.

## Storage Assessment

The export shows a mix of good owner-only storage policies and dangerous broad read policies.

The bucket metadata confirms that all current buckets are public. That is incompatible with least-privilege for identity documents, civil records, and payment-related uploads.

Safer direction:

- `avatars` can remain public only if it contains intentionally public profile images.
- `proof_of_residency`, `valid_ids`, `death_certificates`, `birth_certificates`, and `marriage_certificates` should not be globally readable.
- QR-related buckets should be owner-only or staff-scoped unless there is a verified business reason for wider access.
- `gcash_qr_images` should be private unless every authenticated user is intentionally allowed to inspect payment QR assets.

## Revised Rubric Direction

Based on the policy export alone:

- `3` Access control and authorization: partially implemented.
- `4` Sensitive data protection: partially implemented.
- `5` Role segregation and least privilege: partially implemented.
- `7` Auditability and traceability: partially implemented at best, because `audit_logs` is too open.

These items should not be marked complete until the permissive exceptions are removed.

## What To Do Next

1. Apply the cleanup script in `docs/supabase-rls-cleanup.sql` in a staging Supabase project first.
2. Apply the bucket hardening plan in `docs/supabase-storage-hardening.sql` after confirming the app uses signed URLs or owner-scoped reads for sensitive files.
3. Re-export the policies after cleanup.
4. Confirm that RLS is enabled on each sensitive table, not only that policies exist.
5. Replace any app flows that rely on broad table reads or public file URLs with narrower policies, signed URLs, or dedicated RPC/views.