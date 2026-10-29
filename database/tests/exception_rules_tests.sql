-- Tests for 002_exception_rules.sql. Run after rls_tests.sql on a throwaway DB.
\set ON_ERROR_STOP 1

DO $$
DECLARE
  org uuid := (SELECT id FROM public.organizations WHERE name = 'Acme');
  staff uuid := (SELECT id FROM public.employees WHERE email = 'staff.a@acme.test');
  mgr uuid := (SELECT id FROM public.employees WHERE email = 'mgr.a@acme.test');
  n int;
BEGIN
  -- New types are accepted.
  INSERT INTO public.exception_records (organization_id, employee_id, exception_type, severity, description)
  VALUES (org, staff, 'late_clock_in', 'high', 'test'), (org, staff, 'early_departure', 'high', 'test');
  RAISE NOTICE 'PASS E1: late_clock_in and early_departure are valid exception types';

  -- Shift that started 2h ago with no clock-in (no-show in progress).
  INSERT INTO public.shifts (organization_id, employee_id, site_location, start_time, end_time)
  VALUES (org, staff, 'CBD', now() - interval '2 hours', now() + interval '6 hours');

  -- Shift that ended 3h ago; manager clocked in but never out.
  INSERT INTO public.shifts (organization_id, employee_id, site_location, start_time, end_time)
  VALUES (org, mgr, 'CBD', now() - interval '11 hours', now() - interval '3 hours');
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time)
  VALUES (org, mgr, 'clock_in', now() - interval '11 hours');

  n := public.detect_missed_punches();
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL E2: expected 2 new exceptions, got %', n; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.exception_records WHERE employee_id = staff AND exception_type = 'missed_clock_in') THEN
    RAISE EXCEPTION 'FAIL E2: missed_clock_in not raised';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.exception_records WHERE employee_id = mgr AND exception_type = 'missed_clock_out') THEN
    RAISE EXCEPTION 'FAIL E2: missed_clock_out not raised';
  END IF;
  RAISE NOTICE 'PASS E2: detects a no-show and a forgotten clock-out';

  n := public.detect_missed_punches();
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL E3: re-run inserted % duplicates', n; END IF;
  RAISE NOTICE 'PASS E3: re-running does not create duplicates';
END $$;

-- Regular users cannot run the cross-organization detector.
BEGIN;
SELECT set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  PERFORM public.detect_missed_punches();
  RAISE EXCEPTION 'FAIL E4: staff could run detect_missed_punches';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS E4: only the server can run the detector';
END $$;
ROLLBACK;
