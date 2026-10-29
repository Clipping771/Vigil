-- Tests for 003_exception_review.sql. Run after exception_rules_tests.sql.
\set ON_ERROR_STOP 1

-- Relationship names the app relies on for PostgREST embedding.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'exception_records_employee_id_fkey')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'exception_records_reviewed_by_fkey') THEN
    RAISE EXCEPTION 'FAIL R0: expected foreign key names are missing';
  END IF;
  RAISE NOTICE 'PASS R0: foreign key names match the app queries';
END $$;

-- Seed: one issue for staff, one for the manager.
INSERT INTO public.exception_records (organization_id, employee_id, exception_type, severity, description)
SELECT organization_id, id, 'late_clock_in', 'high', 'review-test staff' FROM public.employees WHERE email = 'staff.a@acme.test';
INSERT INTO public.exception_records (organization_id, employee_id, exception_type, severity, description)
SELECT organization_id, id, 'early_departure', 'medium', 'review-test manager' FROM public.employees WHERE email = 'mgr.a@acme.test';

-- 1. Staff only see their own issues.
BEGIN;
SELECT set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.exception_records WHERE description = 'review-test manager';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL R1: staff can see a colleague''s issue'; END IF;
  SELECT count(*) INTO n FROM public.exception_records WHERE description = 'review-test staff';
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL R1: staff cannot see their own issue'; END IF;
  RAISE NOTICE 'PASS R1: staff see only their own issues';
END $$;
ROLLBACK;

-- 2. Owner resolves: reviewer and time are stamped by the database, and audited.
BEGIN;
SELECT set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);
SET LOCAL ROLE authenticated;
UPDATE public.exception_records
SET status = 'resolved', resolution_note = 'Approved late start',
    reviewed_by = (SELECT id FROM public.employees WHERE email = 'mgr.a@acme.test')  -- spoof attempt
WHERE description = 'review-test staff';
DO $$ DECLARE r record; BEGIN
  SELECT x.reviewed_by, x.reviewed_at, x.resolved_at, e.email INTO r
  FROM public.exception_records x LEFT JOIN public.employees e ON e.id = x.reviewed_by
  WHERE x.description = 'review-test staff';
  IF r.email IS DISTINCT FROM 'owner.a@acme.test' THEN RAISE EXCEPTION 'FAIL R2: reviewer is % (spoofable?)', r.email; END IF;
  IF r.reviewed_at IS NULL OR r.resolved_at IS NULL THEN RAISE EXCEPTION 'FAIL R2: timestamps not set'; END IF;
  RAISE NOTICE 'PASS R2: reviewer is the signed-in owner (spoof ignored) and timestamps are set';
END $$;
COMMIT;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.audit_logs WHERE action = 'exception_resolved' AND details ->> 'note' = 'Approved late start') THEN
    RAISE EXCEPTION 'FAIL R3: no audit log entry';
  END IF;
  RAISE NOTICE 'PASS R3: the review is recorded in audit_logs';
END $$;

-- 4. Staff can read who resolved their issue.
BEGIN;
SELECT set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE who text; BEGIN
  SELECT e.full_name INTO who FROM public.exception_records x JOIN public.employees e ON e.id = x.reviewed_by
  WHERE x.description = 'review-test staff';
  IF who IS NULL THEN RAISE EXCEPTION 'FAIL R4: staff cannot see who resolved it'; END IF;
  RAISE NOTICE 'PASS R4: staff can see it was resolved by %', who;
END $$;
ROLLBACK;

-- 5. Editing other fields keeps the reviewer; reopening clears it.
BEGIN;
SELECT set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);
SET LOCAL ROLE authenticated;
UPDATE public.exception_records SET resolution_note = 'edited', reviewed_by = NULL WHERE description = 'review-test staff';
DO $$ BEGIN
  IF (SELECT reviewed_by FROM public.exception_records WHERE description = 'review-test staff') IS NULL THEN
    RAISE EXCEPTION 'FAIL R5a: reviewer was cleared by a direct edit';
  END IF;
END $$;
UPDATE public.exception_records SET status = 'pending' WHERE description = 'review-test staff';
DO $$ BEGIN
  IF (SELECT reviewed_by FROM public.exception_records WHERE description = 'review-test staff') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL R5b: reopening did not clear the reviewer';
  END IF;
  RAISE NOTICE 'PASS R5: reviewer cannot be edited directly; reopening clears it';
END $$;
ROLLBACK;
