-- Add the staff/admin user who recorded the advance payment.
alter table public.advance_payments
  add column if not exists added_by uuid references public.users(id) on delete set null;

create index if not exists idx_advance_payments_added_by
  on public.advance_payments (added_by);

comment on column public.advance_payments.added_by is 'The user account that created this advance payment record.';
