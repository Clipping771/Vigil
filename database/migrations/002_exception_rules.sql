-- ==============================================================================
-- VIGIL — EXCEPTION RULES MIGRATION (002)
-- ------------------------------------------------------------------------------
-- Run in the Supabase SQL Editor after 001. Idempotent and safe to re-run.
--
-- 1. Allows the new exception types raised by the app:
--      late_clock_in, early_departure, missed_clock_out
-- 2. Adds detect_missed_punches(): server-side detection of no-shows and
--    forgotten clock-outs, so they are caught even if nobody opens the app.
-- 3. Schedules it every 5 minutes with pg_cron (when the extension is available).
-- ==============================================================================

-- 1. Exception types ------------------------------------------------------------
DO $$
DECLARE c record;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.exception_records'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%exception_type%'
  LOOP
    EXECUTE format('ALTER TABLE public.exception_records DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE public.exception_records
  ADD CONSTRAINT exception_records_exception_type_check CHECK (exception_type IN (
    'missed_clock_in', 'late_clock_in', 'early_departure', 'missed_clock_out',
    'excessive_overtime', 'roster_breach', 'geofence_violation',
    'fair_work_compliance_breach', 'leave_roster_conflict',
    'statistical_anomaly', 'fraud_risk'
  ));

CREATE INDEX IF NOT EXISTS idx_exception_records_shift_type
  ON public.exception_records (shift_id, exception_type);

-- 2. Server-side missed-punch detection -----------------------------------------
CREATE OR REPLACE FUNCTION public.detect_missed_punches()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  inserted integer := 0;
  n integer;
BEGIN
  -- No-shows / not clocked in after the grace period.
  INSERT INTO public.exception_records (organization_id, employee_id, shift_id, exception_type, severity, status, description)
  SELECT s.organization_id, s.employee_id, s.id, 'missed_clock_in', 'high', 'pending',
         CASE WHEN now() > s.end_time
              THEN 'No-show: did not clock in for the shift at ' || s.site_location || '.'
              ELSE 'Not clocked in ' || floor(extract(epoch FROM now() - s.start_time) / 60)::int
                   || ' min after the shift started.'
         END
  FROM public.shifts s
  LEFT JOIN public.organization_settings os ON os.organization_id = s.organization_id
  WHERE s.start_time > now() - interval '36 hours'
    AND s.start_time < now() - make_interval(mins => COALESCE(os.allowed_late_minutes, 15))
    AND NOT EXISTS (
      SELECT 1 FROM public.clock_events e
      WHERE e.employee_id = s.employee_id AND e.event_type = 'clock_in'
        AND e.event_time >= s.start_time - interval '2 hours' AND e.event_time < s.end_time)
    AND NOT EXISTS (
      SELECT 1 FROM public.exception_records x
      WHERE x.shift_id = s.id AND x.exception_type = 'missed_clock_in');
  GET DIAGNOSTICS n = ROW_COUNT;
  inserted := inserted + n;

  -- Still clocked in well after the shift ended (forgot to clock out).
  INSERT INTO public.exception_records (organization_id, employee_id, shift_id, exception_type, severity, status, description)
  SELECT s.organization_id, s.employee_id, s.id, 'missed_clock_out', 'medium', 'pending',
         'Still clocked in ' || floor(extract(epoch FROM now() - s.end_time) / 60)::int
         || ' min after the shift ended — likely forgot to clock out.'
  FROM public.shifts s
  LEFT JOIN public.organization_settings os ON os.organization_id = s.organization_id
  WHERE s.end_time > now() - interval '36 hours'
    AND s.end_time < now() - make_interval(mins => COALESCE(os.allowed_overtime_minutes, 30) + 60)
    AND (
      SELECT e.event_type FROM public.clock_events e
      WHERE e.employee_id = s.employee_id AND e.event_time >= s.start_time - interval '2 hours'
      ORDER BY e.event_time DESC LIMIT 1
    ) = 'clock_in'
    AND NOT EXISTS (
      SELECT 1 FROM public.exception_records x
      WHERE x.shift_id = s.id AND x.exception_type = 'missed_clock_out');
  GET DIAGNOSTICS n = ROW_COUNT;
  inserted := inserted + n;

  RETURN inserted;
END;
$$;

-- Runs across every organization: keep it server-only.
REVOKE ALL ON FUNCTION public.detect_missed_punches() FROM PUBLIC, anon, authenticated;

-- 3. Schedule every 5 minutes ------------------------------------------------------
DO $$
BEGIN
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron is not available (%). Enable it under Database → Extensions, then re-run this file.', SQLERRM;
    RETURN;
  END;

  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'vigil-missed-punches';
  PERFORM cron.schedule('vigil-missed-punches', '*/5 * * * *', 'SELECT public.detect_missed_punches()');
  RAISE NOTICE 'Scheduled vigil-missed-punches every 5 minutes.';
END $$;
