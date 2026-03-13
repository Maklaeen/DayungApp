# DayungApp

DayungApp is a Flutter client backed by Supabase. Privileged SuperAdmin actions now run through a Supabase Edge Function instead of Render.

## Workspace Structure

- `lib/`: Flutter mobile and desktop client code
- `backend/`: legacy Express backend kept only as a reference for SMS-related work
- `assets/`: Images, fonts, and animations
- `docs/`: Security and operational policy documents
- `supabase/functions/`: Supabase Edge Functions for privileged server-side actions

## Setup

### Flutter client

Create a local `.env` file in the project root with values for:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `OPENROUTESERVICE_API_KEY`

For iOS, create `ios/Flutter/Secrets.xcconfig` from `ios/Flutter/Secrets.xcconfig.example` and set:

- `GOOGLE_MAPS_API_KEY`

Then run the Flutter app normally.

### Supabase Edge Function

Deploy the bundled Supabase function for privileged SuperAdmin actions:

```bash
supabase login
supabase link
supabase functions deploy superadmin-admin
```

More detail is in `docs/supabase-edge-functions.md`.

### Legacy SMS backend

The `backend/` folder remains available only if you later restore SMS delivery.

Create `backend/.env` using `backend/.env.example` and set:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- `TWILIO_FROM`
- `PORT`

## Security Notes

- Do not commit real `.env` files.
- Do not commit `ios/Flutter/Secrets.xcconfig`.
- The Edge Function `superadmin-admin` is intended to be authenticated and superadmin-scoped.
- The backend route `/send-announcement-sms` remains intended to be authenticated and president-scoped if SMS is restored later.
- Sensitive document buckets should use private access policies and signed URLs at the infrastructure level.

## Audit and Quality Checks

Flutter:

```bash
flutter analyze
flutter test
```

Backend:

```bash
cd backend
npm run lint
npm run audit:deps
```

## Security Documentation

See [docs/security-policies.md](docs/security-policies.md) for:

- password policy
- access policy
- logging policy
- backup strategy
- incident response plan
