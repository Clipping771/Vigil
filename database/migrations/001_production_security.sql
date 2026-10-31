-- ==============================================================================
-- VIGIL — PRODUCTION SECURITY MIGRATION (001)
-- ------------------------------------------------------------------------------
-- Run ONCE in the Supabase SQL Editor, after schema.sql (fresh install) or on top
-- of an existing prototype database. It is idempotent and safe to re-run.
--
-- What it does:
--   1. Links employees to Supabase Auth via a dedicated `auth_user_id` column
--      (instead of overwriting the employee primary key, which broke shifts FKs).
--   2. Replaces every prototype "USING (true)" policy with tenant-isolated RLS.
--   3. Blocks privilege escalation (users editing their own role / organization).
--   4. Moves organization sign-up and invited-user account linking into
--      SECURITY DEFINER RPCs so the client never needs broad INSERT rights.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. AUTH LINK COLUMN
-- ------------------------------------------------------------------------------
ALTER TABLE public.employees
    ADD COLUMN IF NOT EXISTS auth_user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL;

-- Backfill: prototype setup flow overwrote employees.id with the auth uid.
UPDATE public.employees e
SET auth_user_id = e.id
WHERE e.auth_user_id IS NULL
  AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = e.id);

CREATE INDEX IF NOT EXISTS idx_employees_email_lower ON public.employees (lower(email));

-- Keep the original exception description intact when a manager resolves it.
ALTER TABLE public.exception_records ADD COLUMN IF NOT EXISTS resolution_note TEXT;

-- Undo prototype bypasses.
ALTER TABLE public.organizations       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employees           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shifts              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clock_events        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.breaks              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exception_records   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leave_requests      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.geofence_zones      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs          ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------------------------
-- 2. HELPER FUNCTIONS (resolve the caller's employee row from auth.uid())
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.current_employee_id()
RETURNS UUID LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT id FROM public.employees WHERE auth_user_id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_user_org_id()
RETURNS UUID LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT organization_id FROM public.employees WHERE auth_user_id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS TEXT LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT role FROM public.employees WHERE auth_user_id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.is_manager_or_admin()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT COALESCE(public.get_user_role() IN ('owner', 'admin', 'system_admin', 'manager', 'hr'), false);
$$;

CREATE OR REPLACE FUNCTION public.is_org_admin()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT COALESCE(public.get_user_role() IN ('owner', 'admin', 'system_admin'), false);
$$;

CREATE OR REPLACE FUNCTION public.is_system_admin()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT COALESCE(public.get_user_role() = 'system_admin', false);
$$;

-- ------------------------------------------------------------------------------
-- 3. DROP EVERY EXISTING POLICY ON VIGIL TABLES (prototype + legacy)
-- ------------------------------------------------------------------------------
DO $$
DECLARE pol record;
BEGIN
  FOR pol IN
    SELECT policyname, tablename FROM pg_policies
    WHERE schemaname = 'public' AND tablename IN (
      'organizations', 'organization_settings', 'employees', 'shifts', 'clock_events',
      'breaks', 'exception_records', 'leave_requests', 'geofence_zones', 'audit_logs')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
  END LOOP;
END $$;

-- ------------------------------------------------------------------------------
-- 4. TENANT-ISOLATED POLICIES
-- ------------------------------------------------------------------------------
-- Organizations: created only via register_organization() or by a system admin.
CREATE POLICY org_select ON public.organizations FOR SELECT TO authenticated
  USING (id = public.get_user_org_id() OR public.is_system_admin());
CREATE POLICY org_insert ON public.organizations FOR INSERT TO authenticated
  WITH CHECK (public.is_system_admin());
CREATE POLICY org_update ON public.organizations FOR UPDATE TO authenticated
  USING ((id = public.get_user_org_id() AND public.is_org_admin()) OR public.is_system_admin());
CREATE POLICY org_delete ON public.organizations FOR DELETE TO authenticated
  USING (public.is_system_admin());

-- Organization settings
CREATE POLICY org_settings_select ON public.organization_settings FOR SELECT TO authenticated
  USING (organization_id = public.get_user_org_id() OR public.is_system_admin());
CREATE POLICY org_settings_write ON public.organization_settings FOR ALL TO authenticated
  USING ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin())
  WITH CHECK ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin());

-- Employees (role/org changes are additionally guarded by trg_employees_guard)
CREATE POLICY employees_select ON public.employees FOR SELECT TO authenticated
  USING (organization_id = public.get_user_org_id() OR public.is_system_admin());
CREATE POLICY employees_insert ON public.employees FOR INSERT TO authenticated
  WITH CHECK ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin());
CREATE POLICY employees_update ON public.employees FOR UPDATE TO authenticated
  USING (auth_user_id = auth.uid()
         OR (organization_id = public.get_user_org_id() AND public.is_manager_or_admin())
         OR public.is_system_admin());
CREATE POLICY employees_delete ON public.employees FOR DELETE TO authenticated
  USING (((organization_id = public.get_user_org_id() AND public.is_org_admin()) OR public.is_system_admin())
         AND auth_user_id IS DISTINCT FROM auth.uid());

-- Shifts
CREATE POLICY shifts_select ON public.shifts FOR SELECT TO authenticated
  USING (organization_id = public.get_user_org_id() OR public.is_system_admin());
CREATE POLICY shifts_write ON public.shifts FOR ALL TO authenticated
  USING ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin())
  WITH CHECK ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin());

-- Clock events: immutable punch log; staff can only punch for themselves.
CREATE POLICY clock_select ON public.clock_events FOR SELECT TO authenticated
  USING (organization_id = public.get_user_org_id() OR public.is_system_admin());
CREATE POLICY clock_insert ON public.clock_events FOR INSERT TO authenticated
  WITH CHECK (organization_id = public.get_user_org_id()
              AND (employee_id = public.current_employee_id() OR public.is_manager_or_admin()));

-- Breaks
CREATE POLICY breaks_select ON public.breaks FOR SELECT TO authenticated
  USING (organization_id = public.get_user_org_id() OR public.is_system_admin());
CREATE POLICY breaks_write ON public.breaks FOR ALL TO authenticated
  USING (organization_id = public.get_user_org_id()
         AND (employee_id = public.current_employee_id() OR public.is_manager_or_admin()))
  WITH CHECK (organization_id = public.get_user_org_id()
              AND (employee_id = public.current_employee_id() OR public.is_manager_or_admin()));

-- Exceptions: any org member may raise (client-side engine); only managers resolve.
CREATE POLICY exceptions_select ON public.exception_records FOR SELECT TO authenticated
  USING (organization_id = public.get_user_org_id() OR public.is_system_admin());
CREATE POLICY exceptions_insert ON public.exception_records FOR INSERT TO authenticated
  WITH CHECK (organization_id = public.get_user_org_id()
              AND (employee_id = public.current_employee_id() OR public.is_manager_or_admin()));
CREATE POLICY exceptions_update ON public.exception_records FOR UPDATE TO authenticated
  USING ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin());

-- Leave requests
CREATE POLICY leave_select ON public.leave_requests FOR SELECT TO authenticated
  USING (organization_id = public.get_user_org_id() OR public.is_system_admin());
CREATE POLICY leave_insert ON public.leave_requests FOR INSERT TO authenticated
  WITH CHECK (organization_id = public.get_user_org_id()
              AND (employee_id = public.current_employee_id() OR public.is_manager_or_admin()));
-- Managers/HR cannot approve their own leave; owners and admins may.
CREATE POLICY leave_update ON public.leave_requests FOR UPDATE TO authenticated
  USING ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()
          AND (employee_id IS DISTINCT FROM public.current_employee_id() OR public.is_org_admin()))
         OR public.is_system_admin());
CREATE POLICY leave_delete ON public.leave_requests FOR DELETE TO authenticated
  USING ((employee_id = public.current_employee_id() AND status = 'pending')
         OR (organization_id = public.get_user_org_id() AND public.is_manager_or_admin())
         OR public.is_system_admin());

-- Geofence zones
CREATE POLICY geofence_select ON public.geofence_zones FOR SELECT TO authenticated
  USING (organization_id = public.get_user_org_id() OR public.is_system_admin());
CREATE POLICY geofence_write ON public.geofence_zones FOR ALL TO authenticated
  USING ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin())
  WITH CHECK ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin());

-- Audit logs: append-only.
CREATE POLICY audit_select ON public.audit_logs FOR SELECT TO authenticated
  USING ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin());
CREATE POLICY audit_insert ON public.audit_logs FOR INSERT TO authenticated
  WITH CHECK (organization_id = public.get_user_org_id() OR public.is_system_admin());

-- ------------------------------------------------------------------------------
-- 5. PRIVILEGE-ESCALATION GUARD ON EMPLOYEES
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_employee_changes()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller_role TEXT := public.get_user_role();
BEGIN
  -- Service role / SQL editor run without an auth uid; link_current_user() sets a
  -- transaction-local flag (set_config is not exposed through PostgREST).
  IF auth.uid() IS NULL OR current_setting('vigil.trusted_rpc', true) = 'on' THEN
    RETURN NEW;
  END IF;

  IF NEW.role = 'system_admin' AND caller_role IS DISTINCT FROM 'system_admin'
     AND (TG_OP = 'INSERT' OR OLD.role IS DISTINCT FROM 'system_admin') THEN
    RAISE EXCEPTION 'Only a system administrator can grant the system_admin role';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.role IN ('owner', 'admin') AND caller_role NOT IN ('owner', 'admin', 'system_admin') THEN
      RAISE EXCEPTION 'Only owners and admins can create admin accounts';
    END IF;
    -- Accounts are linked only through link_current_user(); never trust client input.
    NEW.auth_user_id := NULL;
    RETURN NEW;
  END IF;

  IF NEW.auth_user_id IS DISTINCT FROM OLD.auth_user_id AND caller_role IS DISTINCT FROM 'system_admin' THEN
    RAISE EXCEPTION 'auth_user_id cannot be changed from the client';
  END IF;

  IF (NEW.role IS DISTINCT FROM OLD.role OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
      OR lower(NEW.email) IS DISTINCT FROM lower(OLD.email)) THEN
    IF caller_role = 'system_admin' THEN
      RETURN NEW;
    END IF;
    IF NOT public.is_manager_or_admin() OR OLD.organization_id <> public.get_user_org_id()
       OR NEW.organization_id <> OLD.organization_id THEN
      RAISE EXCEPTION 'You are not allowed to change role, email or organization';
    END IF;
    IF OLD.auth_user_id = auth.uid() AND NEW.role IS DISTINCT FROM OLD.role THEN
      RAISE EXCEPTION 'You cannot change your own role';
    END IF;
    IF (NEW.role IN ('owner', 'admin') OR OLD.role IN ('owner', 'admin'))
       AND caller_role NOT IN ('owner', 'admin') THEN
      RAISE EXCEPTION 'Only owners and admins can change admin roles';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_employees_guard ON public.employees;
CREATE TRIGGER trg_employees_guard
  BEFORE INSERT OR UPDATE ON public.employees
  FOR EACH ROW EXECUTE FUNCTION public.guard_employee_changes();

-- ------------------------------------------------------------------------------
-- 6. SESSION BOOTSTRAP RPC
-- ------------------------------------------------------------------------------
-- Called by the app right after sign-in. Returns the caller's employee row:
--   a) already linked            -> return it
--   b) invited by an admin       -> link the provisioned row by verified email
--   c) signed up as a new org    -> create organization + settings + owner row
--      (company_name / full_name are taken from the sign-up user metadata)
CREATE OR REPLACE FUNCTION public.link_current_user()
RETURNS public.employees
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid UUID := auth.uid();
  au auth.users%ROWTYPE;
  emp public.employees%ROWTYPE;
  new_org UUID;
  company TEXT;
  person TEXT;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  PERFORM set_config('vigil.trusted_rpc', 'on', true);

  SELECT * INTO emp FROM public.employees WHERE auth_user_id = uid;
  IF FOUND THEN
    RETURN emp;
  END IF;

  SELECT * INTO au FROM auth.users WHERE id = uid;
  IF au.email IS NULL OR au.email_confirmed_at IS NULL THEN
    RAISE EXCEPTION 'Please verify your email address before signing in';
  END IF;

  -- (b) invited employee
  SELECT * INTO emp FROM public.employees
  WHERE lower(email) = lower(au.email) AND auth_user_id IS NULL
  ORDER BY created_at
  LIMIT 1;
  IF FOUND THEN
    UPDATE public.employees SET auth_user_id = uid WHERE id = emp.id RETURNING * INTO emp;
    RETURN emp;
  END IF;

  -- (c) self-service organization sign-up
  company := NULLIF(trim(au.raw_user_meta_data ->> 'company_name'), '');
  person  := COALESCE(NULLIF(trim(au.raw_user_meta_data ->> 'full_name'), ''), split_part(au.email, '@', 1));
  IF company IS NULL THEN
    RAISE EXCEPTION 'No Vigil account is provisioned for %. Ask your administrator for an invite.', au.email;
  END IF;

  INSERT INTO public.organizations (name, subscription_plan)
  VALUES (left(company, 120), 'freemium')
  RETURNING id INTO new_org;

  INSERT INTO public.organization_settings (organization_id) VALUES (new_org)
  ON CONFLICT DO NOTHING;

  INSERT INTO public.employees (organization_id, email, full_name, role, auth_user_id)
  VALUES (new_org, au.email, left(person, 120), 'admin', uid)
  RETURNING * INTO emp;

  INSERT INTO public.audit_logs (organization_id, actor_id, action, entity_type, entity_id)
  VALUES (new_org, emp.id, 'organization_created', 'organization', new_org);

  RETURN emp;
END;
$$;

REVOKE ALL ON FUNCTION public.link_current_user() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_current_user() TO authenticated;

-- ------------------------------------------------------------------------------
-- 7. KEEP ORGANIZATION SETTINGS ROWS PRESENT
-- ------------------------------------------------------------------------------
INSERT INTO public.organization_settings (organization_id)
SELECT o.id FROM public.organizations o
ON CONFLICT (organization_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.create_default_org_settings()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.organization_settings (organization_id) VALUES (NEW.id)
  ON CONFLICT (organization_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_org_default_settings ON public.organizations;
CREATE TRIGGER trg_org_default_settings
  AFTER INSERT ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.create_default_org_settings();
