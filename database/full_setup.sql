-- ==============================================================================
-- VIGIL COMPLETE ALL-IN-ONE SUPABASE SETUP SCRIPT
-- ==============================================================================
-- This script contains:
-- 1. Full Database Schema (All 10 Tables, Foreign Keys, Constraints)
-- 2. Performance Indexes
-- 3. Automatic Timestamp Triggers
-- 4. Multi-Tenant RLS Helper Functions & Security Policies
-- 5. Prototype RLS Unlock (Enables seamless Flutter frontend & demo testing)
-- 6. Supabase Realtime Stream Subscriptions
-- 7. Multi-Tenant Dummy / Seed Data (Organizations, Staff, Shifts, Clock-ins, etc.)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- STEP 1: CLEAN UP EXISTING TABLES (Clean Slate)
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS public.audit_logs CASCADE;
DROP TABLE IF EXISTS public.organization_settings CASCADE;
DROP TABLE IF EXISTS public.breaks CASCADE;
DROP TABLE IF EXISTS public.leave_requests CASCADE;
DROP TABLE IF EXISTS public.geofence_zones CASCADE;
DROP TABLE IF EXISTS public.exception_records CASCADE;
DROP TABLE IF EXISTS public.clock_events CASCADE;
DROP TABLE IF EXISTS public.shifts CASCADE;
DROP TABLE IF EXISTS public.employees CASCADE;
DROP TABLE IF EXISTS public.organizations CASCADE;

-- ------------------------------------------------------------------------------
-- STEP 2: CREATE CORE TABLES
-- ------------------------------------------------------------------------------

-- 1. Organizations Table
CREATE TABLE public.organizations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    subscription_plan TEXT DEFAULT 'freemium' CHECK (subscription_plan IN ('freemium', 'pro', 'enterprise')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Organization Settings Table
CREATE TABLE public.organization_settings (
    organization_id UUID PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
    allowed_late_minutes INTEGER DEFAULT 15,
    allowed_overtime_minutes INTEGER DEFAULT 30,
    auto_reporting_enabled BOOLEAN DEFAULT false,
    report_frequency TEXT DEFAULT 'Weekly' CHECK (report_frequency IN ('Daily', 'Weekly', 'Monthly')),
    delivery_email TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Employees Table
CREATE TABLE public.employees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'system_admin', 'hr', 'manager', 'staff')),
    site_location TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(organization_id, email)
);

-- 4. Shifts Table
CREATE TABLE public.shifts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    site_location TEXT NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Clock Events Table
CREATE TABLE public.clock_events (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN ('clock_in', 'clock_out')),
    event_time TIMESTAMPTZ NOT NULL,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    is_geofenced BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Breaks Table (Fair Work Compliance: meal & rest breaks tracking)
CREATE TABLE public.breaks (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    shift_id UUID REFERENCES public.shifts(id) ON DELETE SET NULL,
    employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    duration_minutes INTEGER,
    break_type TEXT DEFAULT 'meal' CHECK (break_type IN ('meal', 'rest', 'other')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Exception Records Table
CREATE TABLE public.exception_records (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    exception_type TEXT NOT NULL CHECK (exception_type IN (
        'missed_clock_in', 
        'excessive_overtime', 
        'roster_breach', 
        'geofence_violation', 
        'fair_work_compliance_breach',
        'leave_roster_conflict',
        'statistical_anomaly',
        'fraud_risk'
    )),
    severity TEXT NOT NULL CHECK (severity IN ('critical', 'high', 'medium', 'low')),
    shift_id UUID REFERENCES public.shifts(id) ON DELETE SET NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'resolved', 'ignored', 'acknowledged')),
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

-- 8. Leave Requests Table
CREATE TABLE public.leave_requests (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    leave_type TEXT NOT NULL CHECK (leave_type IN ('sick', 'annual', 'unpaid', 'maternity', 'paternity', 'compassionate', 'other')),
    reason TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'declined')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Geofence Zones Table
CREATE TABLE public.geofence_zones (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    radius_meters DOUBLE PRECISION DEFAULT 100.0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. Audit Logs Table (Enterprise Compliance & Security Tracking)
CREATE TABLE public.audit_logs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID,
    details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- STEP 3: DATABASE INDEXES (Performance Optimization)
-- ------------------------------------------------------------------------------
CREATE INDEX idx_employees_org ON public.employees(organization_id);
CREATE INDEX idx_employees_email ON public.employees(email);
CREATE INDEX idx_shifts_org_emp ON public.shifts(organization_id, employee_id);
CREATE INDEX idx_shifts_time ON public.shifts(start_time, end_time);
CREATE INDEX idx_clock_events_emp_time ON public.clock_events(employee_id, event_time);
CREATE INDEX idx_clock_events_org ON public.clock_events(organization_id);
CREATE INDEX idx_breaks_shift_emp ON public.breaks(shift_id, employee_id);
CREATE INDEX idx_exception_records_org_status ON public.exception_records(organization_id, status);
CREATE INDEX idx_leave_requests_org_emp ON public.leave_requests(organization_id, employee_id, status);
CREATE INDEX idx_geofence_zones_org ON public.geofence_zones(organization_id);
CREATE INDEX idx_audit_logs_org_time ON public.audit_logs(organization_id, created_at DESC);

-- ------------------------------------------------------------------------------
-- STEP 4: AUTOMATIC TIMESTAMPS TRIGGER FUNCTION
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_organizations_updated_at BEFORE UPDATE ON public.organizations FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_org_settings_updated_at BEFORE UPDATE ON public.organization_settings FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_employees_updated_at BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_shifts_updated_at BEFORE UPDATE ON public.shifts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_leave_requests_updated_at BEFORE UPDATE ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_geofence_zones_updated_at BEFORE UPDATE ON public.geofence_zones FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ------------------------------------------------------------------------------
-- STEP 5: ROW LEVEL SECURITY (RLS) HELPER FUNCTIONS
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_user_org_id()
RETURNS UUID
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
  SELECT organization_id FROM public.employees WHERE id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS TEXT
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
  SELECT role FROM public.employees WHERE id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.is_manager_or_admin()
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
  SELECT COALESCE(
    (SELECT role IN ('owner', 'admin', 'system_admin', 'manager', 'hr') 
     FROM public.employees 
     WHERE id = auth.uid() LIMIT 1), 
    false
  );
$$;

CREATE OR REPLACE FUNCTION public.is_system_admin()
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
  SELECT COALESCE(
    (SELECT role = 'system_admin' 
     FROM public.employees 
     WHERE id = auth.uid() LIMIT 1), 
    false
  );
$$;

-- ------------------------------------------------------------------------------
-- STEP 6: ENABLE ROW LEVEL SECURITY
-- ------------------------------------------------------------------------------
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clock_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.breaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exception_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.geofence_zones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------------------------
-- STEP 7: RLS POLICIES (Configured for Prototype & Frontend Compatibility)
-- ------------------------------------------------------------------------------

-- 1. Organizations Policies
CREATE POLICY "Users view own organization or system admin view all"
ON public.organizations FOR SELECT
USING (id = public.get_user_org_id() OR public.is_system_admin() OR true);

CREATE POLICY "Allow authenticated user to insert organization on registration"
ON public.organizations FOR INSERT
TO authenticated, anon
WITH CHECK (true);

CREATE POLICY "Admins or System Admin update organization"
ON public.organizations FOR UPDATE
USING (true);

CREATE POLICY "System Admin delete organization"
ON public.organizations FOR DELETE
USING (true);

-- 2. Organization Settings Policies
CREATE POLICY "Users view own org settings"
ON public.organization_settings FOR SELECT
USING (true);

CREATE POLICY "Managers and Admins manage org settings"
ON public.organization_settings FOR ALL
USING (true)
WITH CHECK (true);

-- 3. Employees Policies
CREATE POLICY "Users view employees"
ON public.employees FOR SELECT
USING (true);

CREATE POLICY "Allow insert employees"
ON public.employees FOR INSERT
TO authenticated, anon
WITH CHECK (true);

CREATE POLICY "Allow employee update profile"
ON public.employees FOR UPDATE
USING (true);

CREATE POLICY "Managers delete employee"
ON public.employees FOR DELETE
USING (true);

-- 4. Shifts Policies
CREATE POLICY "View shifts"
ON public.shifts FOR SELECT
USING (true);

CREATE POLICY "Manage shifts"
ON public.shifts FOR ALL
USING (true)
WITH CHECK (true);

-- 5. Clock Events Policies
CREATE POLICY "View clock events"
ON public.clock_events FOR SELECT
USING (true);

CREATE POLICY "Insert clock events"
ON public.clock_events FOR INSERT
WITH CHECK (true);

CREATE POLICY "Modify clock events"
ON public.clock_events FOR ALL
USING (true)
WITH CHECK (true);

-- 6. Breaks Policies
CREATE POLICY "View breaks"
ON public.breaks FOR SELECT
USING (true);

CREATE POLICY "Manage breaks"
ON public.breaks FOR ALL
USING (true)
WITH CHECK (true);

-- 7. Exception Records Policies
CREATE POLICY "View exceptions"
ON public.exception_records FOR SELECT
USING (true);

CREATE POLICY "Insert exceptions"
ON public.exception_records FOR INSERT
WITH CHECK (true);

CREATE POLICY "Update exceptions"
ON public.exception_records FOR UPDATE
USING (true);

CREATE POLICY "Manage exceptions"
ON public.exception_records FOR ALL
USING (true)
WITH CHECK (true);

-- 8. Leave Requests Policies
CREATE POLICY "View leave requests"
ON public.leave_requests FOR SELECT
USING (true);

CREATE POLICY "Insert leave requests"
ON public.leave_requests FOR INSERT
WITH CHECK (true);

CREATE POLICY "Update leave requests"
ON public.leave_requests FOR UPDATE
USING (true);

CREATE POLICY "Delete leave requests"
ON public.leave_requests FOR DELETE
USING (true);

-- 9. Geofence Zones Policies
CREATE POLICY "View geofences"
ON public.geofence_zones FOR SELECT
USING (true);

CREATE POLICY "Manage geofences"
ON public.geofence_zones FOR ALL
USING (true)
WITH CHECK (true);

-- 10. Audit Logs Policies
CREATE POLICY "View audit logs"
ON public.audit_logs FOR SELECT
USING (true);

CREATE POLICY "Insert audit logs"
ON public.audit_logs FOR INSERT
WITH CHECK (true);

-- ------------------------------------------------------------------------------
-- STEP 8: ENABLE SUPABASE REALTIME REPLICATION
-- ------------------------------------------------------------------------------
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.exception_records;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.clock_events;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.breaks;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.shifts;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.leave_requests;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.geofence_zones;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.organization_settings;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

-- ------------------------------------------------------------------------------
-- STEP 9: SEED INITIAL MULTI-TENANT DUMMY DATA
-- ------------------------------------------------------------------------------
DO $$ 
DECLARE
  org1_id UUID := gen_random_uuid();
  org2_id UUID := gen_random_uuid();
  uid1 UUID := gen_random_uuid();
  uid2 UUID := gen_random_uuid();
  uid3 UUID := gen_random_uuid();
  uid4 UUID := gen_random_uuid();
  uid5 UUID := gen_random_uuid();
  shift1_id UUID := gen_random_uuid();
  shift2_id UUID := gen_random_uuid();
BEGIN
  -- 1. Insert Organizations
  INSERT INTO public.organizations (id, name, subscription_plan)
  VALUES 
  (org1_id, 'SecureLock Global', 'enterprise'),
  (org2_id, 'Acme Corp', 'pro');

  -- 2. Insert Organization Settings
  INSERT INTO public.organization_settings (organization_id, allowed_late_minutes, allowed_overtime_minutes, auto_reporting_enabled, report_frequency, delivery_email)
  VALUES
  (org1_id, 15, 30, true, 'Daily', 'hr@securelock.com'),
  (org2_id, 10, 20, false, 'Weekly', 'admin@acme.com');

  -- 3. Insert into auth.users (wrapped safely for local / hosted Supabase)
  BEGIN
    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES 
    ('00000000-0000-0000-0000-000000000000', uid1, 'authenticated', 'authenticated', 'alice.smith@securelock.com', 'dummy', now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now()),
    ('00000000-0000-0000-0000-000000000000', uid2, 'authenticated', 'authenticated', 'bob.jones@securelock.com', 'dummy', now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now()),
    ('00000000-0000-0000-0000-000000000000', uid3, 'authenticated', 'authenticated', 'carol.white@securelock.com', 'dummy', now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now()),
    ('00000000-0000-0000-0000-000000000000', uid4, 'authenticated', 'authenticated', 'david.brown@acme.com', 'dummy', now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now()),
    ('00000000-0000-0000-0000-000000000000', uid5, 'authenticated', 'authenticated', 'admin@admin.com', 'dummy', now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now())
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Skipping auth.users insert: %', SQLERRM;
  END;

  -- 4. Insert into public.employees
  INSERT INTO public.employees (id, organization_id, email, full_name, role, site_location)
  VALUES
  (uid1, org1_id, 'alice.smith@securelock.com', 'Alice Smith', 'owner', 'Oakleigh HQ'),
  (uid2, org1_id, 'bob.jones@securelock.com', 'Bob Jones', 'staff', 'Sydney Branch'),
  (uid3, org1_id, 'carol.white@securelock.com', 'Carol White', 'manager', 'Melbourne Factory'),
  (uid4, org2_id, 'david.brown@acme.com', 'David Brown', 'owner', 'Brisbane Warehouse'),
  (uid5, org1_id, 'admin@admin.com', 'System Administrator', 'system_admin', 'Global Operations');

  -- 5. Insert into public.shifts
  INSERT INTO public.shifts (id, organization_id, employee_id, site_location, start_time, end_time)
  VALUES
  (shift1_id, org1_id, uid2, 'Sydney Branch', now() - interval '2 hours', now() + interval '6 hours'),
  (shift2_id, org1_id, uid3, 'Melbourne Factory', now() + interval '1 day' + interval '8 hours', now() + interval '1 day' + interval '16 hours'),
  (gen_random_uuid(), org2_id, uid4, 'Brisbane Warehouse', now() + interval '2 days' + interval '9 hours', now() + interval '2 days' + interval '17 hours');

  -- 6. Insert Breaks
  INSERT INTO public.breaks (organization_id, shift_id, employee_id, start_time, end_time, duration_minutes, break_type)
  VALUES
  (org1_id, shift1_id, uid2, now() - interval '30 minutes', now(), 30, 'meal');

  -- 7. Insert Clock Events
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time, latitude, longitude, is_geofenced)
  VALUES
  (org1_id, uid2, 'clock_in', now() - interval '2 hours', -33.8688, 151.2093, true);

  -- 8. Insert Exception Records
  INSERT INTO public.exception_records (organization_id, employee_id, exception_type, severity, status, description)
  VALUES
  (org1_id, uid2, 'missed_clock_in', 'high', 'pending', 'Bob missed clock-in by more than 15 minutes for scheduled morning shift.'),
  (org1_id, uid3, 'excessive_overtime', 'medium', 'pending', 'Carol clocked out 45 minutes after shift end without pre-approval.'),
  (org1_id, uid2, 'geofence_violation', 'high', 'pending', 'Clock-in attempted 450m away from authorized Sydney Branch geofence.');

  -- 9. Insert Leave Requests
  INSERT INTO public.leave_requests (organization_id, employee_id, start_date, end_date, leave_type, reason, status)
  VALUES
  (org1_id, uid2, CURRENT_DATE + interval '7 days', CURRENT_DATE + interval '10 days', 'annual', 'Family vacation to Gold Coast', 'pending'),
  (org1_id, uid3, CURRENT_DATE + interval '14 days', CURRENT_DATE + interval '15 days', 'sick', 'Doctor medical procedure', 'approved'),
  (org2_id, uid4, CURRENT_DATE + interval '20 days', CURRENT_DATE + interval '25 days', 'annual', 'Summer holidays', 'pending');

  -- 10. Insert Geofence Zones
  INSERT INTO public.geofence_zones (organization_id, name, latitude, longitude, radius_meters)
  VALUES
  (org1_id, 'Oakleigh HQ', -37.8988, 145.0915, 200.0),
  (org1_id, 'Sydney Branch', -33.8688, 151.2093, 150.0),
  (org2_id, 'Brisbane Warehouse', -27.4698, 153.0251, 300.0);

  -- 11. Insert Audit Logs
  INSERT INTO public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, details)
  VALUES
  (org1_id, uid1, 'CREATE_SHIFT', 'shift', shift1_id, '{"site": "Sydney Branch", "hours": 8}'::jsonb),
  (org1_id, uid3, 'RESOLVE_EXCEPTION', 'exception_record', gen_random_uuid(), '{"note": "Approved overtime due to client rush"}'::jsonb);

END $$;
