-- ==========================================
-- VIGIL SAAS: MULTI-TENANT DATABASE SCHEMA
-- ==========================================

-- Clean up existing tables to prevent 'already exists' errors
DROP TABLE IF EXISTS public.exception_records CASCADE;
DROP TABLE IF EXISTS public.clock_events CASCADE;
DROP TABLE IF EXISTS public.shifts CASCADE;
DROP TABLE IF EXISTS public.employees CASCADE;
DROP TABLE IF EXISTS public.organizations CASCADE;


-- 1. Organizations Table (The core of Multi-Tenancy)
CREATE TABLE public.organizations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    subscription_plan TEXT DEFAULT 'freemium' CHECK (subscription_plan IN ('freemium', 'pro', 'enterprise')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Employees Table (Linked to Organization)
CREATE TABLE public.employees (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'hr', 'manager', 'staff')),
    site_location TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(organization_id, email)
);

-- 3. Shifts (Roster) Table
CREATE TABLE public.shifts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    site_location TEXT NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Clock Events Table (With Geofencing Data)
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

-- 5. Exception Records Table
CREATE TABLE public.exception_records (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    exception_type TEXT NOT NULL CHECK (exception_type IN ('missed_clock_in', 'excessive_overtime', 'roster_breach', 'geofence_violation')),
    severity TEXT NOT NULL CHECK (severity IN ('high', 'medium', 'low')),
    shift_id UUID REFERENCES public.shifts(id) ON DELETE SET NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'resolved', 'ignored', 'acknowledged')),
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

-- ==========================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ==========================================

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clock_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exception_records ENABLE ROW LEVEL SECURITY;

-- Helper Function: Get the current user's organization_id
CREATE OR REPLACE FUNCTION get_user_org_id()
RETURNS UUID
LANGUAGE sql SECURITY DEFINER
AS $$
  SELECT organization_id FROM public.employees WHERE id = auth.uid() LIMIT 1;
$$;

-- 1. Organizations Policy: Users can only view their own organization
CREATE POLICY "Users view own organization" 
ON public.organizations FOR SELECT 
USING (id = get_user_org_id());

-- 2. Employees Policy: Users can view everyone in their organization
CREATE POLICY "Users view own org employees" 
ON public.employees FOR SELECT 
USING (organization_id = get_user_org_id());

-- 3. Shifts Policy: Users can view shifts in their organization
CREATE POLICY "Users view own org shifts" 
ON public.shifts FOR SELECT 
USING (organization_id = get_user_org_id());

-- 4. Clock Events Policy: Users can view clock events in their organization
CREATE POLICY "Users view own org clock events" 
ON public.clock_events FOR SELECT 
USING (organization_id = get_user_org_id());

-- 5. Exceptions Policy: Users can view and update exceptions in their org
CREATE POLICY "Users view own org exceptions" 
ON public.exception_records FOR SELECT 
USING (organization_id = get_user_org_id());

CREATE POLICY "Users update own org exceptions" 
ON public.exception_records FOR UPDATE 
USING (organization_id = get_user_org_id());

-- ==========================================
-- NOTE TO FOUNDER / DEVELOPER:
-- In a real SaaS, Registration/Sign-up flow would use a Supabase Edge Function 
-- to automatically create an Organization and insert the Owner into Employees.
-- ==========================================
