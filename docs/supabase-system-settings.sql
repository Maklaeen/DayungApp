create table if not exists public.system_settings (
  id text primary key,
  maintenance_mode boolean not null default false,
  maintenance_message text not null default 'Dayung is temporarily unavailable for maintenance. Please try again later.',
  allow_sms_broadcast boolean not null default false,
  force_password_change_on_create boolean not null default true,
  force_password_change_on_reset boolean not null default true,
  updated_at timestamptz,
  updated_by text
);

insert into public.system_settings (
  id,
  maintenance_mode,
  maintenance_message,
  allow_sms_broadcast,
  force_password_change_on_create,
  force_password_change_on_reset
)
values (
  'global',
  false,
  'Dayung is temporarily unavailable for maintenance. Please try again later.',
  false,
  true,
  true
)
on conflict (id) do nothing;

alter table public.system_settings enable row level security;

drop policy if exists system_settings_superadmin_read on public.system_settings;
create policy system_settings_superadmin_read
on public.system_settings
for select
using (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'superadmin'
  )
);

drop policy if exists system_settings_superadmin_write on public.system_settings;
create policy system_settings_superadmin_write
on public.system_settings
for all
using (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'superadmin'
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'superadmin'
  )
);
