-- ==============================================================================
-- VIGIL — PUNCH INTEGRITY MIGRATION (006)
-- ------------------------------------------------------------------------------
-- Run in the Supabase SQL Editor after 005. Idempotent and safe to re-run.
--
-- The database, not the app, now decides what a punch or break records:
--   1. A person's own punch always gets the server's time, and "inside a work
--      site" is worked out here from the GPS position or a secret site QR code.
--   2. Punching outside a work site raises the geofence issue here.
--   3. Staff can start and end their own break, but its times are set here and a
--      finished break cannot be changed. Only managers can edit or delete
--      someone else's break, and that is written to audit_logs.
--   4. Staff can read only their own punches and breaks (which include GPS).
--
-- Site QR codes now carry a secret, so codes printed before this migration stop
-- working: print them again from Work sites. Requests without a signed-in user
-- (SQL editor, cron, service role) are trusted and left unchanged.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. SECRET SITE QR CODES (zone IDs are readable by all staff, these are not)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.site_qr_codes (
  zone_id UUID PRIMARY KEY REFERENCES public.geofence_zones(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  qr_token UUID NOT NULL DEFAULT gen_random_uuid()
);

ALTER TABLE public.site_qr_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS site_qr_codes_select ON public.site_qr_codes;
CREATE POLICY site_qr_codes_select ON public.site_qr_codes FOR SELECT TO authenticated
  USING ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin())
         OR public.is_system_admin());

INSERT INTO public.site_qr_codes (zone_id, organization_id)
SELECT id, organization_id FROM public.geofence_zones
ON CONFLICT (zone_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.create_site_qr_code()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.site_qr_codes (zone_id, organization_id) VALUES (NEW.id, NEW.organization_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_create_site_qr_code ON public.geofence_zones;
CREATE TRIGGER trg_create_site_qr_code
  AFTER INSERT ON public.geofence_zones
  FOR EACH ROW EXECUTE FUNCTION public.create_site_qr_code();

-- ------------------------------------------------------------------------------
-- 2. PUNCHES
-- ------------------------------------------------------------------------------
-- The scanned code on its way in; the trigger checks it and never stores it.
ALTER TABLE public.clock_events ADD COLUMN IF NOT EXISTS site_code TEXT;

CREATE OR REPLACE FUNCTION public.distance_meters(lat1 double precision, lon1 double precision,
                                                  lat2 double precision, lon2 double precision)
RETURNS double precision LANGUAGE sql IMMUTABLE AS $$
  SELECT 2 * 6371000 * asin(least(1, sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1) / 2), 2)
  )));
$$;

CREATE OR REPLACE FUNCTION public.stamp_clock_event()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  code TEXT := NEW.site_code;
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
    IF NOT EXISTS (
      SELECT 1 FROM public.site_qr_codes c
      WHERE c.organization_id = NEW.organization_id
        AND code = 'vigil:site:' || c.zone_id || ':' || c.qr_token
    ) THEN
      RAISE EXCEPTION 'invalid site code';
    END IF;
    NEW.is_geofenced := true;
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

DROP TRIGGER IF EXISTS trg_stamp_clock_event ON public.clock_events;
CREATE TRIGGER trg_stamp_clock_event
  BEFORE INSERT ON public.clock_events
  FOR EACH ROW EXECUTE FUNCTION public.stamp_clock_event();

CREATE OR REPLACE FUNCTION public.review_clock_event()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  me UUID := public.current_employee_id();
  shift public.shifts;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;

  IF NEW.employee_id <> me THEN
    INSERT INTO public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, details)
    VALUES (NEW.organization_id, me, 'clock_event_entered_for_employee', 'clock_event', NEW.id,
            jsonb_build_object('employee_id', NEW.employee_id, 'event_type', NEW.event_type, 'event_time', NEW.event_time));
  END IF;

  IF NOT NEW.is_geofenced AND NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
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
              CASE NEW.event_type WHEN 'clock_in' THEN 'Clocked in' ELSE 'Clocked out' END
              || ' outside the ' || shift.site_location || ' work site.');
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_review_clock_event ON public.clock_events;
CREATE TRIGGER trg_review_clock_event
  AFTER INSERT ON public.clock_events
  FOR EACH ROW EXECUTE FUNCTION public.review_clock_event();

-- ------------------------------------------------------------------------------
-- 3. BREAKS
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_break()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  me UUID := public.current_employee_id();
  ending BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' AND NEW.employee_id = me THEN
    NEW.start_time := now();
    NEW.end_time := NULL;
    NEW.duration_minutes := NULL;
    NEW.created_at := now();
    IF NOT EXISTS (SELECT 1 FROM public.shifts s WHERE s.id = NEW.shift_id AND s.employee_id = me) THEN
      NEW.shift_id := NULL;
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.employee_id = me THEN
    IF OLD.end_time IS NOT NULL THEN
      RAISE EXCEPTION 'a finished break cannot be changed';
    END IF;
    -- Ending the break is the only change a person can make to their own.
    ending := NEW.end_time IS NOT NULL;
    NEW := OLD;
    IF ending THEN
      NEW.end_time := now();
      NEW.duration_minutes := round(extract(epoch FROM now() - OLD.start_time) / 60);
    END IF;
    RETURN NEW;
  END IF;

  INSERT INTO public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, details)
  VALUES (
    COALESCE(NEW.organization_id, OLD.organization_id), me, 'break_' || lower(TG_OP) || '_for_employee', 'break',
    COALESCE(NEW.id, OLD.id),
    jsonb_build_object('employee_id', COALESCE(NEW.employee_id, OLD.employee_id),
                       'before', to_jsonb(OLD), 'after', to_jsonb(NEW))
  );
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_break ON public.breaks;
CREATE TRIGGER trg_guard_break
  BEFORE INSERT OR UPDATE OR DELETE ON public.breaks
  FOR EACH ROW EXECUTE FUNCTION public.guard_break();

DROP POLICY IF EXISTS breaks_write ON public.breaks;
DROP POLICY IF EXISTS breaks_insert ON public.breaks;
DROP POLICY IF EXISTS breaks_update ON public.breaks;
DROP POLICY IF EXISTS breaks_delete ON public.breaks;
CREATE POLICY breaks_insert ON public.breaks FOR INSERT TO authenticated
  WITH CHECK (organization_id = public.get_user_org_id()
              AND (employee_id = public.current_employee_id() OR public.is_manager_or_admin()));
CREATE POLICY breaks_update ON public.breaks FOR UPDATE TO authenticated
  USING (organization_id = public.get_user_org_id()
         AND (employee_id = public.current_employee_id() OR public.is_manager_or_admin()))
  WITH CHECK (organization_id = public.get_user_org_id()
              AND (employee_id = public.current_employee_id() OR public.is_manager_or_admin()));
-- Nobody deletes their own break, managers included.
CREATE POLICY breaks_delete ON public.breaks FOR DELETE TO authenticated
  USING (organization_id = public.get_user_org_id()
         AND public.is_manager_or_admin()
         AND employee_id IS DISTINCT FROM public.current_employee_id());

-- ------------------------------------------------------------------------------
-- 4. WHO CAN READ PUNCHES AND BREAKS
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS clock_select ON public.clock_events;
CREATE POLICY clock_select ON public.clock_events FOR SELECT TO authenticated
  USING ((organization_id = public.get_user_org_id()
          AND (public.is_manager_or_admin() OR employee_id = public.current_employee_id()))
         OR public.is_system_admin());

DROP POLICY IF EXISTS breaks_select ON public.breaks;
CREATE POLICY breaks_select ON public.breaks FOR SELECT TO authenticated
  USING ((organization_id = public.get_user_org_id()
          AND (public.is_manager_or_admin() OR employee_id = public.current_employee_id()))
         OR public.is_system_admin());
