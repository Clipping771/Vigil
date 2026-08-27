-- PROTOTYPE BYPASS: Disable RLS and Foreign Keys so Mock Auth works!

-- 1. Disable Row Level Security since Mock Auth doesn't have a real auth.uid()
ALTER TABLE public.organizations DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.employees DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.shifts DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.clock_events DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.exception_records DISABLE ROW LEVEL SECURITY;

-- 2. Drop the Auth Foreign Key constraint so we can insert fake employee IDs 
ALTER TABLE public.employees DROP CONSTRAINT IF EXISTS employees_id_fkey;
