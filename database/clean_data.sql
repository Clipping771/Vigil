-- ==============================================================================
-- VIGIL / SECURELOCK GLOBAL — COMPLETE DATA RESET SCRIPT
-- ==============================================================================
-- Run this in your Supabase SQL Editor to wipe all existing data and start fresh.
-- This keeps all table structures, triggers, RPC functions and RLS policies intact,
-- but removes all organizations, employees, shifts, clocks, and users.
-- ==============================================================================

-- 1. Wipe all application data across all Vigil tables
TRUNCATE TABLE 
    public.audit_logs,
    public.breaks,
    public.clock_events,
    public.exception_records,
    public.leave_requests,
    public.shifts,
    public.geofence_zones,
    public.organization_settings,
    public.employees,
    public.organizations
CASCADE;

-- 2. Clear all authentication users (auth.users)
-- This removes old login sessions and passwords so you can register fresh accounts.
DELETE FROM auth.users;

-- 3. Update the self-service sign-up RPC so the workspace creator is provisioned as 'admin' (not owner)
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

  -- (c) self-service organization sign-up -> creates workspace with 'admin' role
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

-- ==============================================================================
-- Everything is now 100% clean and ready for Admin!
-- You can now go to the landing page and choose "Workspace admin setup"
-- to create your fresh SecureLock Global workspace with an Administrator account!
-- ==============================================================================
