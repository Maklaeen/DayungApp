# DayungApp

DayungApp is a Flutter client with a small Node.js backend for announcement SMS delivery.

## Workspace Structure

- `lib/`: Flutter mobile and desktop client code
- `backend/`: Express backend used for protected SMS announcement delivery
- `assets/`: Images, fonts, and animations
- `docs/`: Security and operational policy documents

## Setup

### Flutter client

Create a local `.env` file in the project root with values for:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `OPENROUTESERVICE_API_KEY`

For iOS, create `ios/Flutter/Secrets.xcconfig` from `ios/Flutter/Secrets.xcconfig.example` and set:

- `GOOGLE_MAPS_API_KEY`

Then run the Flutter app normally.

### Backend

Create `backend/.env` using `backend/.env.example` and set:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- `TWILIO_FROM`
- `PORT`

Install backend dependencies and start the server:

```bash
cd backend
npm install
npm start
```

### Render deployment

You can deploy the backend folder as a Render Web Service.

- Root Directory: `backend`
- Build Command: `npm install`
- Start Command: `npm start`

Set these environment variables in Render:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- `TWILIO_FROM`

After deployment, verify this endpoint:

- `GET /health`

## Security Notes

- Do not commit real `.env` files.
- Do not commit `ios/Flutter/Secrets.xcconfig`.
- The backend route `/send-announcement-sms` is intended to be authenticated and president-scoped.
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
