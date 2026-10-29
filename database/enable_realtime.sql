-- ==============================================================================
-- ENABLE SUPABASE REALTIME FOR LIVE UPDATES
-- Run in the Supabase SQL Editor. Safe to re-run.
--
-- Adds every table the app listens to to the `supabase_realtime` publication
-- and sets REPLICA IDENTITY FULL so DELETE events carry organization_id (the
-- app filters realtime events by organization). Row Level Security still
-- applies: users only receive changes to rows they are allowed to read.
-- ==============================================================================
DO $$
DECLARE
  t TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;

  FOREACH t IN ARRAY ARRAY[
    'employees', 'shifts', 'clock_events', 'breaks', 'exception_records',
    'leave_requests', 'geofence_zones', 'organization_settings'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', t);
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END $$;

-- Check: should list all eight tables.
SELECT tablename FROM pg_publication_tables WHERE pubname = 'supabase_realtime' ORDER BY tablename;
