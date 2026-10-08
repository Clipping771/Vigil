-- ==============================================================================
-- ENABLE SUPABASE REALTIME REPLICATION FOR LIVE COLLABORATION
-- Run in Supabase SQL Editor to stream updates directly to Flutter clients
-- ==============================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE public.exception_records;
ALTER PUBLICATION supabase_realtime ADD TABLE public.clock_events;
ALTER PUBLICATION supabase_realtime ADD TABLE public.breaks;
ALTER PUBLICATION supabase_realtime ADD TABLE public.shifts;
ALTER PUBLICATION supabase_realtime ADD TABLE public.leave_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE public.geofence_zones;
ALTER PUBLICATION supabase_realtime ADD TABLE public.organization_settings;
