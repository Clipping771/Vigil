-- Scenario tests for 009_public_holidays.sql. Run after rls_tests.sql, which
-- creates the Acme and Beta organizations and their users.
\set ON_ERROR_STOP 1
SET client_min_messages = notice;

CREATE OR REPLACE FUNCTION pg_temp.as_user(uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', uid::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
END $$;

-- The tests need a linked manager and staff member; earlier suites may change them.
UPDATE public.employees SET role = 'manager' WHERE email = 'mgr.a@acme.test';
UPDATE public.employees SET role = 'staff' WHERE email = 'staff.a@acme.test';

DELETE FROM public.public_holidays;
INSERT INTO public.public_holidays (organization_id, holiday_date, name)
SELECT organization_id, DATE '2026-12-25', 'Christmas Day'
FROM public.employees WHERE email = 'owner.a@acme.test';
INSERT INTO public.public_holidays (organization_id, holiday_date, name)
SELECT organization_id, DATE '2026-12-26', 'Boxing Day'
FROM public.employees WHERE email = 'owner.b@beta.test';

-- 1. Re-running the migration works and keeps the rows
\ir ../migrations/009_public_holidays.sql
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.public_holidays;
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL 1: expected 2 rows after re-running, got %', n; END IF;
  RAISE NOTICE 'PASS 1: the migration can be re-run and keeps existing holidays';
END $$;

-- 2. Row level security is on
DO $$ BEGIN
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.public_holidays'::regclass) THEN
    RAISE EXCEPTION 'FAIL 2: row level security is off';
  END IF;
  RAISE NOTICE 'PASS 2: row level security is on';
END $$;

-- 3. Signed-out users have no access, and no policy applies even if granted
BEGIN;
SET LOCAL ROLE anon;
DO $$ DECLARE blocked boolean := false; BEGIN
  BEGIN
    PERFORM 1 FROM public.public_holidays;
  EXCEPTION WHEN insufficient_privilege THEN blocked := true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL 3a: anon could read the table'; END IF;
END $$;
RESET ROLE;
GRANT ALL ON public.public_holidays TO anon;
SET LOCAL ROLE anon;
DO $$ DECLARE n int; blocked boolean := false; BEGIN
  SELECT count(*) INTO n FROM public.public_holidays;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 3b: anon read % rows through the policies', n; END IF;
  BEGIN
    INSERT INTO public.public_holidays (organization_id, holiday_date, name)
    VALUES (gen_random_uuid(), DATE '2027-01-01', 'Sneaky');
  EXCEPTION WHEN insufficient_privilege THEN blocked := true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL 3c: anon wrote through the policies'; END IF;
  RAISE NOTICE 'PASS 3: signed-out users cannot read or write holidays';
END $$;
ROLLBACK;

-- 4. Staff read only their own organization's holidays
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE n int; other int; BEGIN
  SELECT count(*) INTO n FROM public.public_holidays;
  SELECT count(*) INTO other FROM public.public_holidays WHERE name = 'Boxing Day';
  IF n <> 1 OR other <> 0 THEN RAISE EXCEPTION 'FAIL 4: staff saw % rows, % from another organization', n, other; END IF;
  RAISE NOTICE 'PASS 4: staff read only their own organization''s holidays';
END $$;
ROLLBACK;

-- 5. Staff cannot change the list, even for their own organization
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE blocked boolean := false; n int; BEGIN
  BEGIN
    INSERT INTO public.public_holidays (organization_id, holiday_date, name)
    VALUES (public.get_user_org_id(), DATE '2027-01-01', 'New Year''s Day');
  EXCEPTION WHEN insufficient_privilege THEN blocked := true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL 5a: staff added a holiday'; END IF;

  UPDATE public.public_holidays SET name = 'Changed';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 5b: staff changed % holidays', n; END IF;

  DELETE FROM public.public_holidays;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 5c: staff deleted % holidays', n; END IF;
  RAISE NOTICE 'PASS 5: staff cannot change holidays';
END $$;
ROLLBACK;

-- 6. Managers can add, change and remove their own organization's holidays
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000003');
DO $$ DECLARE h public.public_holidays; n int; BEGIN
  INSERT INTO public.public_holidays (organization_id, holiday_date, name)
  VALUES (public.get_user_org_id(), DATE '2027-01-26', 'Australia Day') RETURNING * INTO h;
  IF h.id IS NULL THEN RAISE EXCEPTION 'FAIL 6a: manager could not add a holiday'; END IF;

  UPDATE public.public_holidays SET name = 'Australia Day (observed)' WHERE id = h.id;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 6b: manager could not change a holiday'; END IF;

  DELETE FROM public.public_holidays WHERE id = h.id;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 6c: manager could not remove a holiday'; END IF;
  RAISE NOTICE 'PASS 6: managers manage their own organization''s holidays';
END $$;
ROLLBACK;

-- 7. Managers cannot touch another organization's holidays or move theirs there.
-- RLS hides Beta's employees from Acme's manager, so look up the id first.
SELECT set_config('vigil.beta_org', organization_id::text, false)
FROM public.employees WHERE email = 'owner.b@beta.test';

BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000003');
DO $$
DECLARE
  beta uuid := current_setting('vigil.beta_org')::uuid;
  blocked int := 0;
  n int;
BEGIN
  BEGIN
    INSERT INTO public.public_holidays (organization_id, holiday_date, name)
    VALUES (beta, DATE '2027-01-01', 'New Year''s Day');
  EXCEPTION WHEN insufficient_privilege THEN blocked := blocked + 1; END;
  BEGIN
    UPDATE public.public_holidays SET organization_id = beta;
  EXCEPTION WHEN insufficient_privilege THEN blocked := blocked + 1; END;
  IF blocked <> 2 THEN RAISE EXCEPTION 'FAIL 7a: only % of 2 cross-organization writes were blocked', blocked; END IF;

  UPDATE public.public_holidays SET name = 'Changed' WHERE organization_id = beta;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 7b: manager changed % of another organization''s holidays', n; END IF;

  DELETE FROM public.public_holidays WHERE organization_id = beta;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 7c: manager deleted % of another organization''s holidays', n; END IF;
  RAISE NOTICE 'PASS 7: managers cannot touch another organization''s holidays';
END $$;
ROLLBACK;

-- 8. A system admin can manage holidays in any organization
BEGIN;
UPDATE public.employees SET role = 'system_admin' WHERE email = 'owner.a@acme.test';
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000001');
DO $$ DECLARE beta uuid := current_setting('vigil.beta_org')::uuid; n int; BEGIN
  SELECT count(*) INTO n FROM public.public_holidays WHERE organization_id = beta;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 8a: system admin saw % rows', n; END IF;
  INSERT INTO public.public_holidays (organization_id, holiday_date, name)
  VALUES (beta, DATE '2027-01-01', 'New Year''s Day');
  RAISE NOTICE 'PASS 8: system admins can manage any organization''s holidays';
END $$;
ROLLBACK;

-- 9. A date can be listed once per organization, and needs a name
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000001');
DO $$ DECLARE blocked int := 0; BEGIN
  BEGIN
    INSERT INTO public.public_holidays (organization_id, holiday_date, name)
    VALUES (public.get_user_org_id(), DATE '2026-12-25', 'Christmas again');
  EXCEPTION WHEN unique_violation THEN blocked := blocked + 1; END;
  BEGIN
    INSERT INTO public.public_holidays (organization_id, holiday_date, name)
    VALUES (public.get_user_org_id(), DATE '2027-04-25', '   ');
  EXCEPTION WHEN check_violation THEN blocked := blocked + 1; END;
  IF blocked <> 2 THEN RAISE EXCEPTION 'FAIL 9: only % of 2 bad rows were rejected', blocked; END IF;
  RAISE NOTICE 'PASS 9: duplicate dates and blank names are rejected';
END $$;
ROLLBACK;

-- 10. Two organizations can list the same date
BEGIN;
SELECT pg_temp.as_user('b0000000-0000-0000-0000-000000000001');
DO $$ BEGIN
  INSERT INTO public.public_holidays (organization_id, holiday_date, name)
  VALUES (public.get_user_org_id(), DATE '2026-12-25', 'Christmas Day');
  RAISE NOTICE 'PASS 10: each organization keeps its own list';
END $$;
ROLLBACK;

DELETE FROM public.public_holidays;
