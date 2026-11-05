-- Scenario tests for 007_leave_entitlements.sql. Run after rls_tests.sql, which
-- creates the Acme organization and its users.
\set ON_ERROR_STOP 1
SET client_min_messages = notice;

GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;

CREATE OR REPLACE FUNCTION pg_temp.as_user(uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', uid::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
END $$;

-- The tests need a linked manager; earlier suites may not leave one behind.
UPDATE public.employees SET role = 'manager' WHERE email = 'mgr.a@acme.test';

-- 1. Existing employees start as full-time on 20 and 10 days
DO $$ DECLARE e public.employees; BEGIN
  SELECT * INTO e FROM public.employees WHERE email = 'staff.a@acme.test';
  IF e.employment_type <> 'full_time' OR e.annual_leave_days <> 20 OR e.sick_leave_days <> 10 THEN
    RAISE EXCEPTION 'FAIL 1: got % % %', e.employment_type, e.annual_leave_days, e.sick_leave_days;
  END IF;
  RAISE NOTICE 'PASS 1: existing employees default to full-time on 20 and 10 days';
END $$;

-- 2. Staff can still edit their own row, but not their entitlements
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE blocked int := 0; BEGIN
  UPDATE public.employees SET site_location = 'Depot' WHERE id = public.current_employee_id();
  IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 2a: staff could not edit their own row'; END IF;

  BEGIN
    UPDATE public.employees SET annual_leave_days = 99 WHERE id = public.current_employee_id();
  EXCEPTION WHEN raise_exception THEN blocked := blocked + 1; END;
  BEGIN
    UPDATE public.employees SET sick_leave_days = 99 WHERE id = public.current_employee_id();
  EXCEPTION WHEN raise_exception THEN blocked := blocked + 1; END;
  BEGIN
    UPDATE public.employees SET employment_type = 'casual' WHERE id = public.current_employee_id();
  EXCEPTION WHEN raise_exception THEN blocked := blocked + 1; END;
  IF blocked <> 3 THEN RAISE EXCEPTION 'FAIL 2b: only % of 3 changes were blocked', blocked; END IF;
  RAISE NOTICE 'PASS 2: staff cannot change their own entitlements';
END $$;
ROLLBACK;

-- 3. A manager can change a team member's entitlements but not their own
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000003');
DO $$ DECLARE e public.employees; blocked boolean := false; BEGIN
  UPDATE public.employees SET employment_type = 'part_time', annual_leave_days = 12, sick_leave_days = 6
  WHERE email = 'staff.a@acme.test' RETURNING * INTO e;
  IF e.annual_leave_days IS DISTINCT FROM 12 THEN RAISE EXCEPTION 'FAIL 3a: manager update did not apply'; END IF;

  BEGIN
    UPDATE public.employees SET annual_leave_days = 99 WHERE id = public.current_employee_id();
  EXCEPTION WHEN raise_exception THEN blocked := true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL 3b: manager changed their own entitlement'; END IF;
  RAISE NOTICE 'PASS 3: managers change entitlements for others only';
END $$;
ROLLBACK;

-- 4. An org admin can change their own entitlements
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000001');
DO $$ DECLARE e public.employees; BEGIN
  UPDATE public.employees SET annual_leave_days = 25
  WHERE id = public.current_employee_id() RETURNING * INTO e;
  IF e.annual_leave_days IS DISTINCT FROM 25 THEN RAISE EXCEPTION 'FAIL 4: admin update did not apply'; END IF;
  RAISE NOTICE 'PASS 4: org admins can change their own entitlements';
END $$;
ROLLBACK;

-- 5. Out-of-range values and unknown employment types are rejected
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000001');
DO $$ DECLARE blocked int := 0; BEGIN
  BEGIN
    UPDATE public.employees SET annual_leave_days = -1 WHERE email = 'staff.a@acme.test';
  EXCEPTION WHEN check_violation THEN blocked := blocked + 1; END;
  BEGIN
    UPDATE public.employees SET employment_type = 'contractor' WHERE email = 'staff.a@acme.test';
  EXCEPTION WHEN check_violation THEN blocked := blocked + 1; END;
  IF blocked <> 2 THEN RAISE EXCEPTION 'FAIL 5: only % of 2 bad values were rejected', blocked; END IF;
  RAISE NOTICE 'PASS 5: invalid entitlement values are rejected';
END $$;
ROLLBACK;
