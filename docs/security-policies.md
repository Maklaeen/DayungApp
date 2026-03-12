# Security Policies

## Password Policy

- User passwords must be at least 8 characters long.
- Passwords must include uppercase, lowercase, numeric, and special characters.
- Password verification is handled by Supabase Auth.
- Legacy custom SHA-256 password helpers must not be used.

## Access Policy

- All users authenticate through Supabase Auth.
- Roles currently used in the application are `superadmin`, `president`, `secretary`, `treasurer`, `collector`, and `member`.
- Privileged backend actions must require an authenticated bearer token and verify role ownership for the requested Dayung unit.
- Client-side visibility checks are not a substitute for database or backend authorization rules.

## Logging Policy

- Successful sign-in and key profile events should be written to the `audit_logs` table.
- Backend services must log technical errors server-side without exposing internals to end users.
- Production code should avoid ad hoc `print` debugging for sensitive operations.

## Backup Strategy

- Backups for Supabase database content and storage buckets must be managed outside the mobile app codebase.
- Backup frequency, retention, and restore procedures should be defined in deployment operations.
- Local `.env` files and service-role credentials must not be used as backups.

## Incident Response Plan

- If keys or tokens are exposed, rotate them immediately.
- Review audit logs and provider dashboards for misuse.
- Disable affected backend endpoints or credentials until rotation is complete.
- Document the incident, impact, remediation, and follow-up hardening actions.

## Audit Tooling

- Run `flutter analyze` and `flutter test` for client checks.
- Run `npm run lint` and `npm run audit:deps` in `backend/` for backend checks.
- Database RLS and ownership policies should be version-controlled separately when available.