# Supabase Edge Functions

DayungApp now uses a Supabase-native function for privileged SuperAdmin actions that cannot run safely from the client.

## Function Included

- `superadmin-admin`
- `audit-ingest`

This function handles:

- SuperAdmin user listing with accurate disabled status
- Create Auth user + matching `public.users` row
- Reset another user's password
- Disable or reactivate Auth users
- Reports and system snapshot with disabled-user counts
- In-app broadcast delivery, including inactive-account targeting

The audit ingest function handles:

- failed login attempts before a user session exists
- server-side audit inserts for login, access, system error, and user activity events

SMS is still intentionally excluded.

## Deploy

Install and link the Supabase CLI to your project, then deploy:

```bash
supabase login
supabase link
supabase functions deploy audit-ingest
supabase functions deploy superadmin-admin
```

If you are testing locally:

```bash
supabase start
supabase functions serve audit-ingest --no-verify-jwt
supabase functions serve superadmin-admin --no-verify-jwt
```

## Required Secrets

The function expects these environment variables in Supabase:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

Supabase-hosted functions already expose these for the project environment. If you run the function outside that environment, provide them manually.

## Flutter Behavior

When `SUPERADMIN_BACKEND_URL` is empty, the Flutter app now:

- uses direct table access for safe client-side SuperAdmin flows
- invokes `superadmin-admin` for privileged Auth admin flows
- invokes `audit-ingest` for server-side audit writes, including pre-auth login failures
- falls back to direct table mode for read-only pages if the function is not deployed yet

## Database Setup

Apply these SQL assets before using the full SuperAdmin panel:

- `docs/supabase-system-settings.sql`
- your current RLS hardening scripts under `docs/`

The function assumes `audit_logs`, `notifications`, `users`, `applications`, `dayung_units`, `dayung_collectors`, and `payments` already exist.