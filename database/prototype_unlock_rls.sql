-- ==========================================
-- PROTOTYPE COMMAND CENTER RLS UNLOCK
-- Run this in Supabase SQL Editor to allow 
-- the frontend Admin Dashboard to function.
-- ==========================================

-- 1. Employees Table
DROP POLICY IF EXISTS "Prototype Admin Insert Employees" ON public.employees;
DROP POLICY IF EXISTS "Prototype Admin Update Employees" ON public.employees;
DROP POLICY IF EXISTS "Prototype Admin Delete Employees" ON public.employees;
DROP POLICY IF EXISTS "Prototype Admin View All Employees" ON public.employees;
DROP POLICY IF EXISTS "Users view own org employees" ON public.employees;

CREATE POLICY "Prototype Admin Insert Employees" ON public.employees FOR INSERT WITH CHECK (true);
CREATE POLICY "Prototype Admin Update Employees" ON public.employees FOR UPDATE USING (true);
CREATE POLICY "Prototype Admin Delete Employees" ON public.employees FOR DELETE USING (true);
CREATE POLICY "Prototype Admin View All Employees" ON public.employees FOR SELECT USING (true);

-- 2. Organizations Table (in case you missed any)
DROP POLICY IF EXISTS "Prototype Admin Insert" ON public.organizations;
DROP POLICY IF EXISTS "Prototype Admin Update" ON public.organizations;
DROP POLICY IF EXISTS "Prototype Admin Delete" ON public.organizations;
DROP POLICY IF EXISTS "Prototype Admin View All" ON public.organizations;
DROP POLICY IF EXISTS "Users view own organization" ON public.organizations;

CREATE POLICY "Prototype Admin Insert" ON public.organizations FOR INSERT WITH CHECK (true);
CREATE POLICY "Prototype Admin Update" ON public.organizations FOR UPDATE USING (true);
CREATE POLICY "Prototype Admin Delete" ON public.organizations FOR DELETE USING (true);
CREATE POLICY "Prototype Admin View All" ON public.organizations FOR SELECT USING (true);

-- 3. (Optional but recommended for full prototype control) Unlocking the rest
-- Shifts
DROP POLICY IF EXISTS "Users view own org shifts" ON public.shifts;
CREATE POLICY "Prototype View All Shifts" ON public.shifts FOR SELECT USING (true);
CREATE POLICY "Prototype Modify Shifts" ON public.shifts FOR ALL USING (true) WITH CHECK (true);

-- Clock Events
DROP POLICY IF EXISTS "Users view own org clock events" ON public.clock_events;
CREATE POLICY "Prototype View All Clock Events" ON public.clock_events FOR SELECT USING (true);
CREATE POLICY "Prototype Modify Clock Events" ON public.clock_events FOR ALL USING (true) WITH CHECK (true);

-- Exception Records
DROP POLICY IF EXISTS "Users view own org exceptions" ON public.exception_records;
DROP POLICY IF EXISTS "Users update own org exceptions" ON public.exception_records;
CREATE POLICY "Prototype View All Exceptions" ON public.exception_records FOR SELECT USING (true);
CREATE POLICY "Prototype Modify Exceptions" ON public.exception_records FOR ALL USING (true) WITH CHECK (true);

-- Leave Requests
DROP POLICY IF EXISTS "Users view own org leave requests" ON public.leave_requests;
DROP POLICY IF EXISTS "Users update own org leave requests" ON public.leave_requests;
DROP POLICY IF EXISTS "Users insert own org leave requests" ON public.leave_requests;
CREATE POLICY "Prototype View All Leave" ON public.leave_requests FOR SELECT USING (true);
CREATE POLICY "Prototype Modify Leave" ON public.leave_requests FOR ALL USING (true) WITH CHECK (true);

-- Geofence Zones
DROP POLICY IF EXISTS "Users view own org geofence zones" ON public.geofence_zones;
CREATE POLICY "Prototype View All Geofences" ON public.geofence_zones FOR SELECT USING (true);
CREATE POLICY "Prototype Modify Geofences" ON public.geofence_zones FOR ALL USING (true) WITH CHECK (true);
