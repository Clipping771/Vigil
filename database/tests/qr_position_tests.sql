-- Scenario tests for 008_qr_requires_position.sql. Run after rls_tests.sql and
-- punch_integrity_tests.sql, which create the organizations, users and Depot
-- site (-33.87, 151.21, 100 m radius) with a shift for staff.
\set ON_ERROR_STOP 1
SET client_min_messages = notice;

GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;

CREATE OR REPLACE FUNCTION pg_temp.as_user(uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', uid::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
END $$;

-- A second Acme site about 13 km from Depot.
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000001');
INSERT INTO public.geofence_zones (organization_id, name, latitude, longitude, radius_meters)
VALUES (public.get_user_org_id(), 'Yard', -33.90, 151.35, 100);
COMMIT;

-- Tests run as staff, who cannot read the secrets, so the codes are read first.
CREATE TEMP TABLE codes AS
  SELECT z.name, 'vigil:site:' || c.zone_id || ':' || c.qr_token AS code
  FROM public.site_qr_codes c JOIN public.geofence_zones z ON z.id = c.zone_id
  WHERE z.name IN ('Depot', 'Yard');
GRANT SELECT ON codes TO authenticated;

-- Makes a QR punch as the signed-in person.
CREATE OR REPLACE FUNCTION pg_temp.scan(site text, lat double precision, lng double precision, kind text DEFAULT 'clock_in')
RETURNS public.clock_events LANGUAGE plpgsql AS $$
DECLARE e public.clock_events; BEGIN
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time, latitude, longitude, is_geofenced, site_code)
  VALUES (public.get_user_org_id(), public.current_employee_id(), kind, now(), lat, lng, true, (SELECT code FROM codes WHERE name = site))
  RETURNING * INTO e;
  RETURN e;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.geofence_issues() RETURNS SETOF public.exception_records LANGUAGE sql AS $$
  SELECT * FROM public.exception_records WHERE exception_type = 'geofence_violation' ORDER BY created_at;
$$;

-- 1. Code and a position inside the scanned site: on site, nothing to review
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE e public.clock_events; n int; BEGIN
  e := pg_temp.scan('Depot', -33.8702, 151.2101);
  IF NOT e.is_geofenced THEN RAISE EXCEPTION 'FAIL 1a: scan inside the site was not verified'; END IF;
  IF e.site_code IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1b: the code was stored'; END IF;
  IF e.latitude IS NULL OR e.longitude IS NULL THEN RAISE EXCEPTION 'FAIL 1c: the position was not kept'; END IF;
  SELECT count(*) INTO n FROM pg_temp.geofence_issues();
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 1d: issue raised for a punch on site'; END IF;
  RAISE NOTICE 'PASS 1: code plus a position inside the site is on site';
END $$;
ROLLBACK;

-- 2. The photo attack: real code, position far away, even claiming to be on site
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE e public.clock_events; x public.exception_records; n int; BEGIN
  e := pg_temp.scan('Depot', -34.50, 150.50);
  IF e.is_geofenced THEN RAISE EXCEPTION 'FAIL 2a: real code from far away was marked on site'; END IF;
  SELECT count(*) INTO n FROM pg_temp.geofence_issues();
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 2b: expected 1 issue, got %', n; END IF;
  SELECT * INTO x FROM pg_temp.geofence_issues();
  IF x.description NOT LIKE 'Clocked in outside%' THEN RAISE EXCEPTION 'FAIL 2c: wrong description: %', x.description; END IF;
  IF x.status <> 'pending' THEN RAISE EXCEPTION 'FAIL 2d: issue is not awaiting review'; END IF;
  RAISE NOTICE 'PASS 2: a real code from far away is recorded off site and raised for review';
END $$;
ROLLBACK;

-- 3. No position at all: recorded, not on site, and raised for review
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE e public.clock_events; x public.exception_records; n int; BEGIN
  e := pg_temp.scan('Depot', NULL, NULL);
  IF e.is_geofenced IS DISTINCT FROM false THEN RAISE EXCEPTION 'FAIL 3a: on-site flag is %', e.is_geofenced; END IF;
  SELECT count(*) INTO n FROM pg_temp.geofence_issues();
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 3b: expected 1 issue, got %', n; END IF;
  SELECT * INTO x FROM pg_temp.geofence_issues();
  IF x.description NOT LIKE 'Clocked in with no location%' THEN RAISE EXCEPTION 'FAIL 3c: wrong description: %', x.description; END IF;
  RAISE NOTICE 'PASS 3: a scan with no position is recorded off site and raised for review';
END $$;
ROLLBACK;

-- 4. Half a position counts as none
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE e public.clock_events; n int; BEGIN
  e := pg_temp.scan('Depot', -33.87, NULL);
  IF e.is_geofenced IS DISTINCT FROM false THEN RAISE EXCEPTION 'FAIL 4a: on-site flag is %', e.is_geofenced; END IF;
  SELECT count(*) INTO n FROM pg_temp.geofence_issues();
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 4b: expected 1 issue, got %', n; END IF;
  RAISE NOTICE 'PASS 4: half a position is treated as no position';
END $$;
ROLLBACK;

-- 5. Standing in another of the organization's sites does not verify this code
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE e public.clock_events; n int; BEGIN
  e := pg_temp.scan('Depot', -33.90, 151.35);
  IF e.is_geofenced THEN RAISE EXCEPTION 'FAIL 5a: code for one site verified at another'; END IF;
  SELECT count(*) INTO n FROM pg_temp.geofence_issues();
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 5b: expected 1 issue, got %', n; END IF;
  RAISE NOTICE 'PASS 5: only the scanned site counts';
END $$;
ROLLBACK;

-- 6. The radius applies from the site's centre, on both sides of its edge
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE e public.clock_events; BEGIN
  e := pg_temp.scan('Depot', -33.87 - 0.0008, 151.21);  -- about 89 m
  IF NOT e.is_geofenced THEN RAISE EXCEPTION 'FAIL 6a: 89 m from a 100 m site was not verified'; END IF;
  e := pg_temp.scan('Depot', -33.87 - 0.0010, 151.21);  -- about 111 m
  IF e.is_geofenced THEN RAISE EXCEPTION 'FAIL 6b: 111 m from a 100 m site was verified'; END IF;
  RAISE NOTICE 'PASS 6: the site radius is respected';
END $$;
ROLLBACK;

-- 7. Repeat off-site scans raise one issue per shift
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE e public.clock_events; n int; BEGIN
  e := pg_temp.scan('Depot', NULL, NULL);
  e := pg_temp.scan('Depot', -34.50, 150.50);
  SELECT count(*) INTO n FROM pg_temp.geofence_issues();
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 7: expected 1 issue, got %', n; END IF;
  RAISE NOTICE 'PASS 7: one issue per shift';
END $$;
ROLLBACK;

-- 8. A wrong code is still rejected, even with a good position
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ BEGIN
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time, latitude, longitude, site_code)
  VALUES (public.get_user_org_id(), public.current_employee_id(), 'clock_in', now(), -33.87, 151.21, 'vigil:site:nope:nope');
  RAISE EXCEPTION 'FAIL 8: a wrong code was accepted';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 8: a wrong code is rejected';
END $$;
ROLLBACK;

-- 9. Another organization's code fails even when standing at that site
BEGIN;
SELECT pg_temp.as_user('b0000000-0000-0000-0000-000000000001');
DO $$ BEGIN
  PERFORM pg_temp.scan('Depot', -33.87, 151.21);
  RAISE EXCEPTION 'FAIL 9: Beta punched with an Acme code';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 9: site codes work only in their own organization';
END $$;
ROLLBACK;

-- 10. No shift: still not on site. The app raises the no-shift issue for this.
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000001');
DO $$ DECLARE e public.clock_events; n int; BEGIN
  e := pg_temp.scan('Depot', NULL, NULL);
  IF e.is_geofenced IS DISTINCT FROM false THEN RAISE EXCEPTION 'FAIL 10a: on-site flag is %', e.is_geofenced; END IF;
  SELECT count(*) INTO n FROM pg_temp.geofence_issues();
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 10b: expected no geofence issue without a shift, got %', n; END IF;
  RAISE NOTICE 'PASS 10: a scan with no shift and no position is not on site';
END $$;
ROLLBACK;

-- 11. GPS punches, clock-outs and managers' entries are not affected
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE e public.clock_events; n int; BEGIN
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time, latitude, longitude)
  VALUES (public.get_user_org_id(), public.current_employee_id(), 'clock_in', now(), -33.87, 151.21)
  RETURNING * INTO e;
  IF NOT e.is_geofenced THEN RAISE EXCEPTION 'FAIL 11a: GPS inside a site was not verified'; END IF;
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time)
  VALUES (public.get_user_org_id(), public.current_employee_id(), 'clock_out', now())
  RETURNING * INTO e;
  IF e.is_geofenced THEN RAISE EXCEPTION 'FAIL 11b: clock-out with no position was verified'; END IF;
  SELECT count(*) INTO n FROM pg_temp.geofence_issues();
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 11c: clock-out with no position raised an issue'; END IF;
END $$;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000003');
DO $$ DECLARE n int; BEGIN
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time)
  SELECT organization_id, id, 'clock_in', now() - interval '1 hour' FROM public.employees WHERE email = 'staff.a@acme.test';
  SELECT count(*) INTO n FROM pg_temp.geofence_issues();
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 11d: manager entry with no position raised an issue'; END IF;
  RAISE NOTICE 'PASS 11: GPS punches, clock-outs and manager entries behave as before';
END $$;
ROLLBACK;

-- 12. A direct clock-in that leaves out both code and position is also reviewed
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE n int; BEGIN
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time)
  VALUES (public.get_user_org_id(), public.current_employee_id(), 'clock_in', now());
  SELECT count(*) INTO n FROM pg_temp.geofence_issues();
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 12: expected 1 issue, got %', n; END IF;
  RAISE NOTICE 'PASS 12: leaving out the code does not avoid review';
END $$;
ROLLBACK;

-- 13. Trusted server work is left unchanged
BEGIN;
DO $$ DECLARE e public.clock_events; emp public.employees; BEGIN
  SELECT * INTO emp FROM public.employees WHERE email = 'staff.a@acme.test';
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time, is_geofenced, site_code)
  VALUES (emp.organization_id, emp.id, 'clock_in', now() - interval '1 day', true, 'anything')
  RETURNING * INTO e;
  IF NOT e.is_geofenced OR e.site_code IS NOT NULL THEN RAISE EXCEPTION 'FAIL 13: server insert was changed'; END IF;
  RAISE NOTICE 'PASS 13: requests without a signed-in user are left unchanged';
END $$;
ROLLBACK;

-- Clean up the extra site so these tests can run again.
DELETE FROM public.geofence_zones WHERE name = 'Yard';
