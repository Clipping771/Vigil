# Vigil

Workforce attendance, rostering and compliance platform — Flutter (web, mobile, desktop) on Supabase, with an optional Python AI engine.

## Features

- Geofenced GPS punch clock and per-site QR codes
- Live workforce board (who is on shift / on break)
- Rosters with overnight shifts and overlap checks
- Leave requests and approvals
- Compliance exceptions: late starts, overtime, 10-hour rest breaches, geofence breaches, leave conflicts
- CSV / PDF compliance exports
- Multi-tenant with row-level security and role-based access (owner, admin, HR, manager, staff, system admin)
- Optional AI assistant (bring your own Gemini / OpenAI / Claude key)

## Setup

### 1. Database (Supabase SQL editor)

Fresh project:

1. `database/schema.sql`
2. `database/migrations/001_production_security.sql`
3. `database/enable_realtime.sql`

Existing prototype database: run **only** `database/migrations/001_production_security.sql`. It re-enables RLS, replaces all prototype policies and is safe to re-run.

In **Auth → URL configuration**, set the Site URL to your deployed web origin so confirmation and password-reset links return to the app.

### 2. Flutter app

```bash
cp .env.example .env   # fill in SUPABASE_URL and SUPABASE_ANON_KEY
flutter pub get
flutter run --dart-define-from-file=.env
```

### 3. Accounts

- **New organization:** "Create a workspace" on the landing page. The person who signs up becomes the owner.
- **Employees:** a manager invites them from **Staff**. They then choose "Activate your account" on the sign-in page using the same email.
- **System admin (platform-wide):** run `database/promote_admin.sql` in the SQL editor.

### 4. Deploy (Vercel)

Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` in the project's environment variables. `build.sh` builds the web bundle with them.

### 5. AI engine (optional)

```bash
cd backend
cp .env.example .env   # service-role key stays server-side only
pip install -r requirements.txt
python main.py
```

Every endpoint requires the user's Supabase access token as `Authorization: Bearer <token>`.

## Tests

```bash
flutter analyze
flutter test
```
