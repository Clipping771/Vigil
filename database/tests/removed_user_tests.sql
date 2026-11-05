-- Scenario tests for 010_removed_users_stay_removed.sql. Run after rls_tests.sql.
\set ON_ERROR_STOP 1
SET client_min_messages = notice;

CREATE OR REPLACE FUNCTION pg_temp.as_user(uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', uid::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
END $$;

INSERT INTO auth.users (id, email, email_confirmed_at, raw_user_meta_data) VALUES
  ('e0000000-0000-0000-0000-000000000001', 'removed.admin@gamma.test', now(), '{"company_name":"Gamma","full_name":"Rae Removed"}');

-- 1. Signing up still creates the workspace, once.
BEGIN;
SELECT pg_temp.as_user('e0000000-0000-0000-0000-000000000001');
DO $$ DECLARE e public.employees; BEGIN
  e := public.link_current_user();
  IF e.role <> 'admin' THEN RAISE EXCEPTION 'FAIL R1: got role %', e.role; END IF;
  RAISE NOTICE 'PASS R1: sign-up creates a workspace with an admin';
END $$;
COMMIT;

-- 2. Removed from the database: the saved session must not bring them back.
DELETE FROM public.employees WHERE auth_user_id = 'e0000000-0000-0000-0000-000000000001';
CREATE TEMP TABLE before_orgs AS SELECT count(*) AS n FROM public.organizations;
GRANT SELECT ON before_orgs TO authenticated;

BEGIN;
SELECT pg_temp.as_user('e0000000-0000-0000-0000-000000000001');
DO $$ BEGIN
  PERFORM public.link_current_user();
  RAISE EXCEPTION 'FAIL R2: removed user was recreated as an admin';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS R2: removed user is refused (%)', SQLERRM;
END $$;
COMMIT;

DO $$ DECLARE orgs bigint; emps bigint; BEGIN
  SELECT count(*) INTO orgs FROM public.organizations;
  SELECT count(*) INTO emps FROM public.employees WHERE auth_user_id = 'e0000000-0000-0000-0000-000000000001';
  IF orgs <> (SELECT n FROM before_orgs) OR emps <> 0 THEN
    RAISE EXCEPTION 'FAIL R3: % organizations, % employee rows', orgs, emps;
  END IF;
  RAISE NOTICE 'PASS R3: no organization or employee row was created';
END $$;

-- 3. Invited back: they join the inviting organization with the invited role.
INSERT INTO public.employees (organization_id, email, full_name, role)
SELECT id, 'Removed.Admin@gamma.test', 'Rae Removed', 'staff' FROM public.organizations WHERE name = 'Acme' LIMIT 1;

BEGIN;
SELECT pg_temp.as_user('e0000000-0000-0000-0000-000000000001');
DO $$ DECLARE e public.employees; BEGIN
  e := public.link_current_user();
  IF e.role <> 'staff' THEN RAISE EXCEPTION 'FAIL R4: got role %', e.role; END IF;
  RAISE NOTICE 'PASS R4: a removed user can be invited back';
END $$;
COMMIT;

-- 4. People removed before this migration: re-running it covers them too.
INSERT INTO auth.users (id, email, email_confirmed_at, last_sign_in_at, raw_user_meta_data) VALUES
  ('e0000000-0000-0000-0000-000000000002', 'old.removed@delta.test', now(), now(), '{"company_name":"Delta"}'),
  ('e0000000-0000-0000-0000-000000000003', 'new.signup@epsilon.test', now(), NULL, '{"company_name":"Epsilon"}');
\ir ../migrations/010_removed_users_stay_removed.sql

BEGIN;
SELECT pg_temp.as_user('e0000000-0000-0000-0000-000000000002');
DO $$ BEGIN
  PERFORM public.link_current_user();
  RAISE EXCEPTION 'FAIL R5: earlier removed user was recreated';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS R5: someone removed before the migration is refused';
END $$;
COMMIT;

-- 5. Someone who confirmed their email but has not signed in yet is unaffected.
BEGIN;
SELECT pg_temp.as_user('e0000000-0000-0000-0000-000000000003');
DO $$ DECLARE e public.employees; BEGIN
  e := public.link_current_user();
  IF e.role <> 'admin' THEN RAISE EXCEPTION 'FAIL R6: got role %', e.role; END IF;
  RAISE NOTICE 'PASS R6: a new sign-up still gets a workspace';
END $$;
COMMIT;

-- 6. Users cannot read or clear the record.
BEGIN;
SELECT pg_temp.as_user('e0000000-0000-0000-0000-000000000001');
DO $$ BEGIN
  DELETE FROM public.workspace_signups;
  RAISE EXCEPTION 'FAIL R7: a user could change workspace_signups';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS R7: users cannot change workspace_signups';
END $$;
COMMIT;

DO $$ BEGIN RAISE NOTICE 'removed_user_tests: ALL PASSED'; END $$;
