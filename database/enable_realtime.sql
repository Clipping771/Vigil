-- Enable Realtime for the Live Dashboard tables
ALTER PUBLICATION supabase_realtime ADD TABLE exception_records;
ALTER PUBLICATION supabase_realtime ADD TABLE clock_events;
