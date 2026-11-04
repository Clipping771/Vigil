# Vigil

Workforce attendance, rostering and compliance platform — Flutter (web, mobile, desktop) on Supabase, with an optional Python AI engine.

## Features

- Geofenced GPS punch clock and per-site QR codes
- Live workforce board (who is on shift / on break)
- Rosters with overnight shifts and overlap checks
- Leave requests and approvals
- Compliance exceptions: late starts, overtime, excessive breaks, 10-hour rest breaches, geofence breaches, leave conflicts
- CSV / PDF compliance exports
- Multi-tenant with row-level security and role-based access (admin, HR, manager, staff, system admin)
- Light and dark mode (follows the device on first launch)
- Optional AI assistant (bring your own Gemini / OpenAI / Claude key)

## Setup

### 1. Database (Supabase SQL editor)

Fresh project:

1. `database/schema.sql`
2. `database/migrations/001_production_security.sql` — RLS, roles, sign-up
3. `database/migrations/002_exception_rules.sql` — exception types, server-side no-show detection (enable `pg_cron` first)
4. `database/migrations/003_exception_review.sql` — who reviewed each issue, audit log, staff see only their own issues
5. `database/migrations/004_admin_founder.sql` — converts legacy owners to admins; other admins cannot demote or remove the workspace founder
6. `database/migrations/005_break_rules.sql` — allows the excessive-breaks issue type
7. `database/migrations/006_punch_integrity.sql` — the database sets punch and break times and checks location; staff see only their own punches. Site QR codes printed earlier stop working, so print them again from **Work sites**
8. `database/enable_realtime.sql`

Existing database: run the migrations in order (each is idempotent and safe to re-run), then `enable_realtime.sql`. Run them before deploying the app.

In **Auth → URL configuration**, set the Site URL to your deployed web origin so confirmation and password-reset links return to the app.

### 2. Flutter app

```bash
cp .env.example .env   # fill in SUPABASE_URL and SUPABASE_ANON_KEY
flutter pub get
flutter run --dart-define-from-file=.env
```

### 3. Accounts

- **New organization:** "Create a workspace" on the landing page. The person who signs up becomes an admin and the workspace founder; other admins cannot demote or remove them.
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
flutter test        # unit tests + layout tests (every page, phone & desktop, light & dark)
```

Database security tests (needs a local PostgreSQL; never run against production):

```bash
psql -d vigil_test -f database/tests/supabase_stub.sql
psql -d vigil_test -f database/schema.sql
psql -d vigil_test -f database/migrations/001_production_security.sql
psql -d vigil_test -f database/migrations/002_exception_rules.sql
psql -d vigil_test -f database/migrations/003_exception_review.sql
psql -d vigil_test -f database/migrations/004_admin_founder.sql
psql -d vigil_test -f database/migrations/005_break_rules.sql
psql -d vigil_test -f database/migrations/006_punch_integrity.sql
psql -d vigil_test -f database/tests/rls_tests.sql   # prints PASS/FAIL per scenario
psql -d vigil_test -f database/tests/exception_rules_tests.sql
psql -d vigil_test -f database/tests/exception_review_tests.sql
psql -d vigil_test -f database/tests/punch_integrity_tests.sql
```

Preview the signed-in app with sample data (no backend):

```bash
flutter run -d chrome -t test/preview/main_preview.dart
```
