begin;

-- Apply only after verifying the Flutter app no longer depends on public URLs
-- for sensitive uploads. Buckets that store identity or civil-status documents
-- should be private and accessed through signed URLs or tightly scoped reads.

-- Keep avatars public only if profile images are intentionally public.
update storage.buckets
set public = true
where id = 'avatars';

-- Sensitive document buckets should be private.
update storage.buckets
set public = false
where id in (
  'birth_certificates',
  'death_certificates',
  'marriage_certificates',
  'proof_of_residency',
  'valid_ids',
  'gcash_qr_images'
);

-- Optional hardening: apply sane limits and MIME restrictions.
-- Adjust limits to match the actual business requirement before applying.

update storage.buckets
set
  file_size_limit = 10485760,
  allowed_mime_types = array[
    'image/jpeg',
    'image/png',
    'application/pdf'
  ]
where id in (
  'birth_certificates',
  'death_certificates',
  'marriage_certificates',
  'proof_of_residency',
  'valid_ids'
);

update storage.buckets
set
  file_size_limit = 5242880,
  allowed_mime_types = array[
    'image/jpeg',
    'image/png'
  ]
where id in ('avatars', 'gcash_qr_images');

commit;