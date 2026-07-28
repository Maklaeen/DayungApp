-- Add boolean columns for dayung service tags to dayung_rules
alter table public.dayung_rules
  add column if not exists transportation_assistance boolean default false,
  add column if not exists chapel_assistance boolean default false,
  add column if not exists before_burial_claim_release boolean default false,
  add column if not exists claims_assistance_at_funeral_home boolean default false,
  add column if not exists open_membership boolean default false,
  add column if not exists age_restriction boolean default false,
  add column if not exists barangay_residents_only boolean default false,
  add column if not exists wake_preparation_assistance boolean default false,
  add column if not exists prayer_support boolean default false;

-- Add boolean columns for user-selected service tags to user_preferences
alter table public.user_preferences
  add column if not exists transportation_assistance boolean default false,
  add column if not exists chapel_assistance boolean default false,
  add column if not exists before_burial_claim_release boolean default false,
  add column if not exists claims_assistance_at_funeral_home boolean default false,
  add column if not exists open_membership boolean default false,
  add column if not exists age_restriction boolean default false,
  add column if not exists barangay_residents_only boolean default false,
  add column if not exists wake_preparation_assistance boolean default false,
  add column if not exists prayer_support boolean default false;
