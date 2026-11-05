-- Scenario tests for 006_punch_integrity.sql. Run after rls_tests.sql, which
-- creates the Acme and Beta organizations and their users.
\set ON_ERROR_STOP 1
SET client_min_messages = notice;

GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;

CREATE OR REPLACE FUNCTION pg_temp.as_user(uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', uid::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
END $$;

-- Acme site at (-33.87, 151.21) with a 100 m radius, and a shift for staff now.
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000001');
INSERT INTO public.geofence_zones (organization_id, name, latitude, longitude, radius_meters)
VALUES (public.get_user_org_id(), 'Depot', -33.87, 151.21, 100);
INSERT INTO public.shifts (organization_id, employee_id, site_location, start_time, end_time)
SELECT organization_id, id, 'Depot', now() - interval '1 hour', now() + interval '7 hours'
FROM public.employees WHERE email = 'staff.a@acme.test';
COMMIT;

-- 1. A backdated punch that claims to be on site gets the server's time and flag
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE e public.clock_events; BEGIN
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time, is_geofenced, created_at)
  VALUES (public.get_user_org_id(), public.current_employee_id(), 'clock_in', now() - interval '3 hours', true, now() - interval '3 hours')
  RETURNING * INTO e;
  IF e.event_time <> now() OR e.created_at <> now() THEN RAISE EXCEPTION 'FAIL 1a: kept client time %', e.event_time; END IF;
  IF e.is_geofenced THEN RAISE EXCEPTION 'FAIL 1b: client claim of being on site was kept'; END IF;
  RAISE NOTICE 'PASS 1: staff cannot choose the time or claim to be on site';
END $$;
ROLLBACK;

-- 2. GPS inside the zone is verified; outside raises one geofence issue per shift
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE e public.clock_events; n int; BEGIN
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time, latitude, longitude)
  VALUES (public.get_user_org_id(), public.current_employee_id(), 'clock_in', now(), -33.8702, 151.2101)
  RETURNING * INTO e;
  IF NOT e.is_geofenced THEN RAISE EXCEPTION 'FAIL 2a: GPS inside the zone was not verified'; END IF;
  SELECT count(*) INTO n FROM public.exception_records WHERE exception_type = 'geofence_violation';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 2b: issue raised for a punch on site'; END IF;

  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time, latitude, longitude, is_geofenced)
  VALUES (public.get_user_org_id(), public.current_employee_id(), 'clock_out', now(), -33.90, 151.30, true)
  RETURNING * INTO e;
  IF e.is_geofenced THEN RAISE EXCEPTION 'FAIL 2c: GPS outside the zone was verified'; END IF;
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time, latitude, longitude)
  VALUES (public.get_user_org_id(), public.current_employee_id(), 'clock_in', now(), -33.90, 151.30);
  SELECT count(*) INTO n FROM public.exception_records WHERE exception_type = 'geofence_violation';
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 2d: expected 1 geofence issue, got %', n; END IF;
  RAISE NOTICE 'PASS 2: location is checked by the database and raises one issue per shift';
END $$;
ROLLBACK;

-- 3. QR: staff cannot read the secret; only the real code verifies, and it is not stored
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE n int; zone uuid; BEGIN
  SELECT count(*) INTO n FROM public.site_qr_codes;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 3a: staff can read site secrets'; END IF;
  SELECT id INTO zone FROM public.geofence_zones WHERE name = 'Depot';
  BEGIN
    INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time, site_code)
    VALUES (public.get_user_org_id(), public.current_employee_id(), 'clock_in', now(), 'vigil:site:' || zone);
    RAISE EXCEPTION 'FAIL 3b: an old code without the secret was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'PASS 3a: staff cannot read the secret or punch with only the zone ID';
END $$;
RESET ROLE;
CREATE TEMP TABLE real_code ON COMMIT DROP AS
  SELECT 'vigil:site:' || zone_id || ':' || qr_token AS code FROM public.site_qr_codes;
GRANT SELECT ON real_code TO authenticated;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE e public.clock_events; BEGIN
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time, latitude, longitude, site_code)
  VALUES (public.get_user_org_id(), public.current_employee_id(), 'clock_in', now(), -33.87, 151.21, (SELECT code FROM real_code))
  RETURNING * INTO e;
  IF NOT e.is_geofenced THEN RAISE EXCEPTION 'FAIL 3c: the real code was not verified'; END IF;
  IF e.site_code IS NOT NULL THEN RAISE EXCEPTION 'FAIL 3d: the code was stored'; END IF;
  RAISE NOTICE 'PASS 3b: the real site code verifies and is not stored';
END $$;
ROLLBACK;

-- 4. Another organization's code does not work
BEGIN;
SELECT pg_temp.as_user('b0000000-0000-0000-0000-000000000001');
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.site_qr_codes;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 4a: Beta admin reads Acme secrets'; END IF;
END $$;
RESET ROLE;
CREATE TEMP TABLE real_code ON COMMIT DROP AS
  SELECT 'vigil:site:' || zone_id || ':' || qr_token AS code FROM public.site_qr_codes;
GRANT SELECT ON real_code TO authenticated;
SELECT pg_temp.as_user('b0000000-0000-0000-0000-000000000001');
DO $$ BEGIN
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time, site_code)
  VALUES (public.get_user_org_id(), public.current_employee_id(), 'clock_in', now(), (SELECT code FROM real_code));
  RAISE EXCEPTION 'FAIL 4b: Beta punched with an Acme code';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 4: site codes work only in their own organization';
END $$;
ROLLBACK;

-- 5. A manager's own punch uses server time; one entered for staff keeps its time and is audited
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000003');
DO $$ DECLARE e public.clock_events; n int; BEGIN
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time)
  VALUES (public.get_user_org_id(), public.current_employee_id(), 'clock_in', now() - interval '3 hours')
  RETURNING * INTO e;
  IF e.event_time <> now() THEN RAISE EXCEPTION 'FAIL 5a: manager backdated their own punch'; END IF;
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time)
  SELECT organization_id, id, 'clock_in', now() - interval '3 hours' FROM public.employees WHERE email = 'staff.a@acme.test'
  RETURNING * INTO e;
  IF e.event_time <> now() - interval '3 hours' THEN RAISE EXCEPTION 'FAIL 5b: correction lost its time'; END IF;
  SELECT count(*) INTO n FROM public.audit_logs WHERE action = 'clock_event_entered_for_employee' AND entity_id = e.id;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 5c: correction was not audited'; END IF;
  RAISE NOTICE 'PASS 5: managers cannot backdate their own punch; corrections are audited';
END $$;
ROLLBACK;

-- 6. Punches cannot be changed or deleted
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time)
VALUES (public.get_user_org_id(), public.current_employee_id(), 'clock_in', now());
DO $$ DECLARE n int; BEGIN
  UPDATE public.clock_events SET event_time = now() - interval '3 hours';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 6a: staff edited a punch'; END IF;
  DELETE FROM public.clock_events;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 6b: staff deleted a punch'; END IF;
  RAISE NOTICE 'PASS 6: punches cannot be changed or deleted';
END $$;
ROLLBACK;

-- 7. Own breaks: times come from the server and a finished break is locked
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
DO $$ DECLARE b public.breaks; n int; BEGIN
  INSERT INTO public.breaks (organization_id, employee_id, start_time, end_time, duration_minutes)
  VALUES (public.get_user_org_id(), public.current_employee_id(), now() - interval '2 hours', now() - interval '110 minutes', 10)
  RETURNING * INTO b;
  IF b.start_time <> now() OR b.end_time IS NOT NULL OR b.duration_minutes IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL 7a: staff logged a break with their own times';
  END IF;

  UPDATE public.breaks SET start_time = now() - interval '1 hour', break_type = 'rest' WHERE id = b.id RETURNING * INTO b;
  IF b.start_time <> now() OR b.break_type <> 'meal' THEN RAISE EXCEPTION 'FAIL 7b: staff edited an open break'; END IF;

  UPDATE public.breaks SET end_time = now() - interval '1 day', duration_minutes = 1 WHERE id = b.id RETURNING * INTO b;
  IF b.end_time <> now() OR b.duration_minutes <> 0 THEN RAISE EXCEPTION 'FAIL 7c: staff chose the end of their break'; END IF;

  BEGIN
    UPDATE public.breaks SET end_time = now() - interval '1 day' WHERE id = b.id;
    RAISE EXCEPTION 'FAIL 7d: staff changed a finished break';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  END;

  DELETE FROM public.breaks WHERE id = b.id;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 7e: staff deleted a break'; END IF;
  RAISE NOTICE 'PASS 7: staff can only start and end their own break, at server time';
END $$;
ROLLBACK;

-- 8. Managers can correct someone else's break (audited) but not delete their own
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
INSERT INTO public.breaks (organization_id, employee_id, start_time)
VALUES (public.get_user_org_id(), public.current_employee_id(), now());
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000003');
DO $$ DECLARE n int; BEGIN
  UPDATE public.breaks SET end_time = now() + interval '30 minutes', duration_minutes = 30;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 8a: manager could not correct a break'; END IF;
  DELETE FROM public.breaks;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 8b: manager could not delete a break'; END IF;
  SELECT count(*) INTO n FROM public.audit_logs WHERE action IN ('break_update_for_employee', 'break_delete_for_employee');
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL 8c: expected 2 audit rows, got %', n; END IF;

  INSERT INTO public.breaks (organization_id, employee_id, start_time)
  VALUES (public.get_user_org_id(), public.current_employee_id(), now());
  DELETE FROM public.breaks WHERE employee_id = public.current_employee_id();
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 8d: manager deleted their own break'; END IF;
  RAISE NOTICE 'PASS 8: managers correct others'' breaks with an audit trail, not their own';
END $$;
ROLLBACK;

-- 9. Staff read only their own punches and breaks; managers read the organization's
BEGIN;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000003');
INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time, latitude, longitude)
VALUES (public.get_user_org_id(), public.current_employee_id(), 'clock_in', now(), -33.87, 151.21);
INSERT INTO public.breaks (organization_id, employee_id, start_time)
VALUES (public.get_user_org_id(), public.current_employee_id(), now());
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time)
VALUES (public.get_user_org_id(), public.current_employee_id(), 'clock_in', now());
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.clock_events WHERE event_time = now();
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 9a: staff see % punches', n; END IF;
  SELECT count(*) INTO n FROM public.breaks;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 9b: staff see % colleague breaks', n; END IF;
END $$;
SELECT pg_temp.as_user('a0000000-0000-0000-0000-000000000001');
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.clock_events WHERE event_time = now();
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL 9c: admin sees % punches', n; END IF;
  RAISE NOTICE 'PASS 9: staff cannot read colleagues'' punches or breaks';
END $$;
ROLLBACK;

-- 10. Trusted server work (SQL editor, cron) is left unchanged
BEGIN;
DO $$ DECLARE e public.clock_events; emp public.employees; BEGIN
  SELECT * INTO emp FROM public.employees WHERE email = 'staff.a@acme.test';
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time, is_geofenced)
  VALUES (emp.organization_id, emp.id, 'clock_in', now() - interval '1 day', true)
  RETURNING * INTO e;
  IF e.event_time <> now() - interval '1 day' OR NOT e.is_geofenced THEN RAISE EXCEPTION 'FAIL 10: server insert was changed'; END IF;
  RAISE NOTICE 'PASS 10: requests without a signed-in user are left unchanged';
END $$;
ROLLBACK;
