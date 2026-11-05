-- ==============================================================================
-- VIGIL ENTERPRISE WORKFORCE & COMPLIANCE DATABASE SCHEMA
-- PostgreSQL / Supabase Migration
-- ==============================================================================

-- Clean up existing tables
DROP TABLE IF EXISTS public.public_holidays CASCADE;
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

-- 1. Organizations Table
CREATE TABLE public.organizations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    subscription_plan TEXT DEFAULT 'freemium' CHECK (subscription_plan IN ('freemium', 'pro', 'enterprise')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Organization Settings Table (for grace periods & reporting frequencies)
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
-- Uses UUID primary key with default gen_random_uuid(). 
-- Supports both Auth-linked users and provisioned staff records.
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

-- ==============================================================================
-- DATABASE INDEXES (Performance Optimization)
-- ==============================================================================
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

-- ==============================================================================
-- AUTOMATIC TIMESTAMPS TRIGGER FUNCTION
-- ==============================================================================
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

-- ==============================================================================
-- ROW LEVEL SECURITY (RLS) HELPER FUNCTIONS
-- ==============================================================================
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

-- ==============================================================================
-- ENABLE ROW LEVEL SECURITY ON ALL TABLES
-- ==============================================================================
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

-- ==============================================================================
-- RLS POLICIES (Multi-Tenant & Role-Based Isolation)
-- ==============================================================================

-- 1. Organizations Policies
CREATE POLICY "Users view own organization or system admin view all"
ON public.organizations FOR SELECT
USING (id = public.get_user_org_id() OR public.is_system_admin());

CREATE POLICY "Allow authenticated user to insert organization on registration"
ON public.organizations FOR INSERT
TO authenticated
WITH CHECK (true);

CREATE POLICY "Admins or System Admin update organization"
ON public.organizations FOR UPDATE
USING ((id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin());

CREATE POLICY "System Admin delete organization"
ON public.organizations FOR DELETE
USING (public.is_system_admin());

-- 2. Organization Settings Policies
CREATE POLICY "Users view own org settings"
ON public.organization_settings FOR SELECT
USING (organization_id = public.get_user_org_id() OR public.is_system_admin());

CREATE POLICY "Managers and Admins manage org settings"
ON public.organization_settings FOR ALL
USING ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin())
WITH CHECK ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin());

-- 3. Employees Policies
CREATE POLICY "Users view own org employees or system admin view all"
ON public.employees FOR SELECT
USING (organization_id = public.get_user_org_id() OR public.is_system_admin());

CREATE POLICY "Allow insert during registration or by manager"
ON public.employees FOR INSERT
TO authenticated
WITH CHECK (
    id = auth.uid() 
    OR (organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) 
    OR public.is_system_admin()
);

CREATE POLICY "Allow employee update own profile or manager update"
ON public.employees FOR UPDATE
USING (
    id = auth.uid() 
    OR (organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) 
    OR public.is_system_admin()
);

CREATE POLICY "Managers or System Admin delete employee"
ON public.employees FOR DELETE
USING (
    (organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) 
    OR public.is_system_admin()
);

-- 4. Shifts Policies
CREATE POLICY "Users view own org shifts"
ON public.shifts FOR SELECT
USING (organization_id = public.get_user_org_id() OR public.is_system_admin());

CREATE POLICY "Managers manage shifts"
ON public.shifts FOR ALL
USING ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin())
WITH CHECK ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin());

-- 5. Clock Events Policies
CREATE POLICY "Users view own org clock events"
ON public.clock_events FOR SELECT
USING (organization_id = public.get_user_org_id() OR public.is_system_admin());

CREATE POLICY "Users insert own clock events"
ON public.clock_events FOR INSERT
WITH CHECK (organization_id = public.get_user_org_id() OR public.is_system_admin());

-- 6. Breaks Policies
CREATE POLICY "Users view own org breaks"
ON public.breaks FOR SELECT
USING (organization_id = public.get_user_org_id() OR public.is_system_admin());

CREATE POLICY "Users manage own breaks or managers manage all org breaks"
ON public.breaks FOR ALL
USING (organization_id = public.get_user_org_id() OR public.is_system_admin())
WITH CHECK (organization_id = public.get_user_org_id() OR public.is_system_admin());

-- 7. Exception Records Policies
CREATE POLICY "Users view own org exceptions"
ON public.exception_records FOR SELECT
USING (organization_id = public.get_user_org_id() OR public.is_system_admin());

CREATE POLICY "Insert exceptions for own org"
ON public.exception_records FOR INSERT
WITH CHECK (organization_id = public.get_user_org_id() OR public.is_system_admin());

CREATE POLICY "Managers update/resolve exceptions"
ON public.exception_records FOR UPDATE
USING ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin());

-- 8. Leave Requests Policies
CREATE POLICY "Users view own org leave requests"
ON public.leave_requests FOR SELECT
USING (organization_id = public.get_user_org_id() OR public.is_system_admin());

CREATE POLICY "Employees insert own leave requests"
ON public.leave_requests FOR INSERT
WITH CHECK (organization_id = public.get_user_org_id() OR public.is_system_admin());

CREATE POLICY "Managers update/approve leave requests"
ON public.leave_requests FOR UPDATE
USING ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin());

CREATE POLICY "Employees or Managers delete leave requests"
ON public.leave_requests FOR DELETE
USING (
    (employee_id = auth.uid() AND status = 'pending')
    OR (organization_id = public.get_user_org_id() AND public.is_manager_or_admin())
    OR public.is_system_admin()
);

-- 9. Geofence Zones Policies
CREATE POLICY "Users view own org geofences"
ON public.geofence_zones FOR SELECT
USING (organization_id = public.get_user_org_id() OR public.is_system_admin());

CREATE POLICY "Managers manage geofence zones"
ON public.geofence_zones FOR ALL
USING ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin())
WITH CHECK ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin());

-- 10. Audit Logs Policies
CREATE POLICY "Managers view own org audit logs"
ON public.audit_logs FOR SELECT
USING ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin());

CREATE POLICY "Allow authenticated users to insert audit logs"
ON public.audit_logs FOR INSERT
WITH CHECK (organization_id = public.get_user_org_id() OR public.is_system_admin());
