-- ==============================================================================
-- VIGIL — QR PUNCHES REQUIRE A POSITION (008)
-- ------------------------------------------------------------------------------
-- Run in the Supabase SQL Editor after 007. Idempotent and safe to re-run.
--
-- A site QR code never changes, so a photo of one must not prove someone is at
-- the site. A scanned punch now counts as on site only if the position sent with
-- it is within the radius of the site on the code:
--   1. Valid code, position inside that site: on site.
--   2. Valid code, position elsewhere or missing: still recorded, but not on site
--      and raised as a geofence issue for a manager, once per shift.
--   3. Invalid code: rejected, as before.
--
-- Printed codes keep working. Requests without a signed-in user (SQL editor,
-- cron, service role) are trusted and left unchanged. Run this before deploying
-- the app version that sends the position: until then, app versions that send
-- only the code get punches flagged for review.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.stamp_clock_event()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  code TEXT := NEW.site_code;
  site public.geofence_zones;
BEGIN
  NEW.site_code := NULL;
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  NEW.created_at := now();
  -- Managers may enter a past punch for someone else (see the audit below), but
  -- nobody chooses the time of their own.
  IF NEW.employee_id = public.current_employee_id() THEN
    NEW.event_time := now();
  END IF;

  IF code IS NOT NULL THEN
    SELECT z.* INTO site
    FROM public.site_qr_codes c
    JOIN public.geofence_zones z ON z.id = c.zone_id
    WHERE c.organization_id = NEW.organization_id
      AND code = 'vigil:site:' || c.zone_id || ':' || c.qr_token;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'invalid site code';
    END IF;
    -- Only the scanned site counts. A missing position gives NULL, which is "no".
    NEW.is_geofenced := COALESCE(
      public.distance_meters(NEW.latitude, NEW.longitude, site.latitude, site.longitude) <= site.radius_meters,
      false
    );
  ELSE
    NEW.is_geofenced := EXISTS (
      SELECT 1 FROM public.geofence_zones z
      WHERE z.organization_id = NEW.organization_id
        AND public.distance_meters(NEW.latitude, NEW.longitude, z.latitude, z.longitude) <= z.radius_meters
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_clock_event()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  me UUID := public.current_employee_id();
  shift public.shifts;
  located BOOLEAN := NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;

  IF NEW.employee_id <> me THEN
    INSERT INTO public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, details)
    VALUES (NEW.organization_id, me, 'clock_event_entered_for_employee', 'clock_event', NEW.id,
            jsonb_build_object('employee_id', NEW.employee_id, 'event_type', NEW.event_type, 'event_time', NEW.event_time));
  END IF;

  -- Off site, or a person's own clock-in with no position to check. A clock-out
  -- may go without a fix, and a manager entering a punch for someone else need
  -- not have one.
  IF NOT NEW.is_geofenced AND (located OR (NEW.event_type = 'clock_in' AND NEW.employee_id = me)) THEN
    -- The rostered shift closest to the punch within 12 hours, once per shift.
    SELECT * INTO shift FROM public.shifts s
    WHERE s.employee_id = NEW.employee_id
      AND s.end_time >= NEW.event_time - interval '12 hours'
      AND s.start_time <= NEW.event_time + interval '12 hours'
    ORDER BY greatest(s.start_time - NEW.event_time, NEW.event_time - s.end_time, interval '0') LIMIT 1;

    IF FOUND AND NOT EXISTS (
      SELECT 1 FROM public.exception_records x
      WHERE x.employee_id = NEW.employee_id AND x.exception_type = 'geofence_violation' AND x.shift_id = shift.id
    ) THEN
      INSERT INTO public.exception_records (organization_id, employee_id, exception_type, severity, shift_id, status, description)
      VALUES (NEW.organization_id, NEW.employee_id, 'geofence_violation', 'high', shift.id, 'pending',
              CASE
                WHEN NOT located THEN 'Clocked in with no location, so being at the ' || shift.site_location || ' work site could not be confirmed.'
                WHEN NEW.event_type = 'clock_in' THEN 'Clocked in outside the ' || shift.site_location || ' work site.'
                ELSE 'Clocked out outside the ' || shift.site_location || ' work site.'
              END);
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
