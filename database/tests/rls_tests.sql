-- Security scenario tests for 001_production_security.sql.
-- Each block raises if behaviour is wrong; success prints PASS lines.
\set ON_ERROR_STOP 1
SET client_min_messages = notice;

GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;

-- Test helpers -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.as_user(uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', uid::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
END $$;

-- Auth users
INSERT INTO auth.users (id, email, email_confirmed_at, raw_user_meta_data) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'owner.a@acme.test', now(), '{"company_name":"Acme","full_name":"Olivia Owner"}'),
  ('a0000000-0000-0000-0000-000000000002', 'staff.a@acme.test', now(), '{}'),
  ('a0000000-0000-0000-0000-000000000003', 'mgr.a@acme.test',   now(), '{}'),
  ('b0000000-0000-0000-0000-000000000001', 'owner.b@beta.test', now(), '{"company_name":"Beta"}'),
  ('c0000000-0000-0000-0000-000000000001', 'nobody@x.test',     now(), '{}'),
  ('d0000000-0000-0000-0000-000000000001', 'unverified@x.test', NULL,  '{"company_name":"Sneaky"}');

-- 1. Self-service sign-up creates org + owner
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000001');
DO $$ DECLARE e public.employees; BEGIN
  e := public.link_current_user();
  IF e.role <> 'owner' OR e.auth_user_id IS NULL THEN RAISE EXCEPTION 'FAIL 1: got role % link %', e.role, e.auth_user_id; END IF;
  RAISE NOTICE 'PASS 1: sign-up creates organization with an owner';
END $$;
COMMIT;

BEGIN;
SELECT pg_temp.as_user('b0000000-0000-0000-0000-000000000001');
SELECT public.link_current_user();
COMMIT;

-- 2. Unverified email cannot bootstrap
BEGIN;
SELECT pg_temp.as_user('d0000000-0000-0000-0000-000000000001');
DO $$ BEGIN
  PERFORM public.link_current_user();
  RAISE EXCEPTION 'FAIL 2: unverified user was linked';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 2: unverified email is rejected (%)', SQLERRM;
END $$;
ROLLBACK;

-- 3. Uninvited user with no company gets a clear error
BEGIN;
SELECT pg_temp.as_user('c0000000-0000-0000-0000-000000000001');
DO $$ BEGIN
  PERFORM public.link_current_user();
  RAISE EXCEPTION 'FAIL 3: uninvited user was linked';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 3: uninvited user is rejected';
END $$;
ROLLBACK;

-- 4. Owner invites staff + manager; client-supplied auth_user_id is ignored
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000001');
INSERT INTO public.employees (organization_id, email, full_name, role, auth_user_id)
VALUES (public.get_user_org_id(), 'staff.a@acme.test', 'Sam Staff', 'staff', 'c0000000-0000-0000-0000-000000000001');
INSERT INTO public.employees (organization_id, email, full_name, role)
VALUES (public.get_user_org_id(), 'mgr.a@acme.test', 'Max Manager', 'manager');
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.employees WHERE email = 'staff.a@acme.test' AND auth_user_id IS NOT NULL) THEN
    RAISE EXCEPTION 'FAIL 4: client set auth_user_id on insert';
  END IF;
  RAISE NOTICE 'PASS 4: invites work and auth_user_id cannot be injected';
END $$;
COMMIT;

-- 5. Invited staff activates and is linked by verified email
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE e public.employees; BEGIN
  e := public.link_current_user();
  IF e.role <> 'staff' OR e.email <> 'staff.a@acme.test' THEN RAISE EXCEPTION 'FAIL 5'; END IF;
  RAISE NOTICE 'PASS 5: invited staff is linked on first sign-in';
END $$;
COMMIT;
BEGIN; SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000003'); SELECT public.link_current_user(); COMMIT;

-- 6. Staff cannot escalate their own role
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ BEGIN
  UPDATE public.employees SET role = 'system_admin' WHERE auth_user_id = auth.uid();
  RAISE EXCEPTION 'FAIL 6a: staff became system_admin';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 6a: staff cannot make themselves system_admin';
END $$;
DO $$ BEGIN
  UPDATE public.employees SET role = 'manager' WHERE auth_user_id = auth.uid();
  RAISE EXCEPTION 'FAIL 6b: staff promoted self to manager';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 6b: staff cannot promote themselves';
END $$;
DO $$ DECLARE n int; BEGIN
  UPDATE public.employees SET full_name = 'Samuel Staff' WHERE auth_user_id = auth.uid();
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 6c: staff could not edit own name'; END IF;
  RAISE NOTICE 'PASS 6c: staff can still edit their own name';
END $$;
ROLLBACK;

-- 7. Manager cannot grant admin, owner can promote staff
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000003');
DO $$ BEGIN
  UPDATE public.employees SET role = 'admin' WHERE email = 'staff.a@acme.test';
  RAISE EXCEPTION 'FAIL 7a: manager granted admin';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 7a: managers cannot grant admin';
END $$;
ROLLBACK;
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000001');
DO $$ DECLARE n int; BEGIN
  UPDATE public.employees SET role = 'hr' WHERE email = 'staff.a@acme.test';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 7b'; END IF;
  RAISE NOTICE 'PASS 7b: owner can change a staff role';
END $$;
ROLLBACK;

-- 8. Tenant isolation: Beta owner sees nothing from Acme
BEGIN;
SELECT pg_temp.as_user('b0000000-0000-0000-0000-000000000001');
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.employees WHERE email LIKE '%@acme.test';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 8a: Beta sees % Acme employees', n; END IF;
  UPDATE public.employees SET full_name = 'hacked' WHERE email = 'staff.a@acme.test';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 8b: Beta edited Acme employee'; END IF;
  RAISE NOTICE 'PASS 8: organizations are isolated from each other';
END $$;
ROLLBACK;

-- 9. Anonymous users see nothing
BEGIN;
SET LOCAL ROLE anon;
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.employees;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 9: anon sees % employees', n; END IF;
  RAISE NOTICE 'PASS 9: anonymous requests see no data';
END $$;
ROLLBACK;

-- 10. Punches: staff can only punch for themselves
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time)
VALUES (public.get_user_org_id(), public.current_employee_id(), 'clock_in', now());
DO $$ BEGIN
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time)
  SELECT organization_id, id, 'clock_in', now() FROM public.employees WHERE email = 'mgr.a@acme.test';
  RAISE EXCEPTION 'FAIL 10: staff punched for someone else';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS 10: staff can punch only for themselves';
END $$;
ROLLBACK;

-- 11. Staff cannot create organizations or delete colleagues
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE n int; BEGIN
  BEGIN
    INSERT INTO public.organizations (name) VALUES ('Rogue Org');
    RAISE EXCEPTION 'FAIL 11a: staff created an organization';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  DELETE FROM public.employees WHERE email = 'mgr.a@acme.test';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 11b: staff deleted a colleague'; END IF;
  RAISE NOTICE 'PASS 11: staff cannot create orgs or delete colleagues';
END $$;
ROLLBACK;

-- 12. Leave: manager cannot approve own leave; owner can approve staff leave
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000003');
INSERT INTO public.leave_requests (organization_id, employee_id, start_date, end_date, leave_type)
VALUES (public.get_user_org_id(), public.current_employee_id(), current_date + 7, current_date + 8, 'annual');
DO $$ DECLARE n int; BEGIN
  UPDATE public.leave_requests SET status = 'approved' WHERE employee_id = public.current_employee_id();
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 12a: manager approved own leave'; END IF;
  RAISE NOTICE 'PASS 12a: managers cannot approve their own leave';
END $$;
COMMIT;
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000001');
DO $$ DECLARE n int; BEGIN
  UPDATE public.leave_requests SET status = 'approved' WHERE status = 'pending';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 12b: owner could not approve (rows=%)', n; END IF;
  RAISE NOTICE 'PASS 12b: owner can approve a manager''s leave';
END $$;
ROLLBACK;

-- 13. Org settings row exists for new orgs and staff cannot change it
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.organization_settings;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 13a: settings rows visible = %', n; END IF;
  UPDATE public.organization_settings SET allowed_late_minutes = 999;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 13b: staff changed org settings'; END IF;
  RAISE NOTICE 'PASS 13: settings row exists and staff cannot change it';
END $$;
ROLLBACK;

-- 14. Owner cannot delete themselves; exceptions keep the original description
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000001');
DO $$ DECLARE n int; BEGIN
  DELETE FROM public.employees WHERE auth_user_id = auth.uid();
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 14: owner deleted own account'; END IF;
  RAISE NOTICE 'PASS 14: you cannot delete your own account';
END $$;
ROLLBACK;
