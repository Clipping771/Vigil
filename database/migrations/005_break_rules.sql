-- ==============================================================================
-- VIGIL — BREAK RULES MIGRATION (005)
-- ------------------------------------------------------------------------------
-- Run in the Supabase SQL Editor after 004. Idempotent and safe to re-run.
--
-- Allows the 'excessive_breaks' exception type, raised by the app when an
-- employee takes more than 3 breaks or more than 60 minutes of breaks in one
-- clock-in.
-- ==============================================================================

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
    'statistical_anomaly', 'fraud_risk', 'excessive_breaks'
  ));
