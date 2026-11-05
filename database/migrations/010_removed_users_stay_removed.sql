-- ==============================================================================
-- VIGIL — REMOVED USERS STAY REMOVED MIGRATION (010)
-- ------------------------------------------------------------------------------
-- Run in the Supabase SQL Editor after 009. Idempotent and safe to re-run.
--
-- Deleting an employee leaves their login in auth.users. link_current_user() runs
-- every time the app opens, so someone who signed up with a company name and was
-- later removed got a brand-new organization and admin row the next time they
-- opened the app. Their browser's saved session was enough to trigger it.
--
-- A sign-up now creates a workspace once. A removed user is refused unless an
-- admin invites them again. Deleting the login in auth.users clears the record,
-- so that email can sign up afresh.
--
-- The record is a table rather than sign-up metadata, because users can edit
-- their own metadata.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.workspace_signups (
  auth_user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.workspace_signups ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.workspace_signups FROM PUBLIC, anon, authenticated;

-- Everyone who has already signed in with a company name, including people
-- removed before this migration. Someone who has never signed in has not had
-- their workspace yet, so they are left out.
INSERT INTO public.workspace_signups (auth_user_id)
SELECT u.id FROM auth.users u
WHERE NULLIF(trim(u.raw_user_meta_data ->> 'company_name'), '') IS NOT NULL
  AND (u.last_sign_in_at IS NOT NULL
       OR EXISTS (SELECT 1 FROM public.employees e WHERE e.auth_user_id = u.id))
ON CONFLICT (auth_user_id) DO NOTHING;

-- Called by the app whenever it opens. Returns the caller's employee row:
--   a) already linked            -> return it
--   b) invited by an admin       -> link the provisioned row by verified email
--   c) signed up as a new org    -> once only: create organization + settings + admin row
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

  -- Had a workspace already, and no row now: they were removed.
  IF EXISTS (SELECT 1 FROM public.workspace_signups WHERE auth_user_id = uid) THEN
    RAISE EXCEPTION 'This account has been removed from Vigil. Ask your administrator for an invite.';
  END IF;

  -- (c) self-service organization sign-up
  company := NULLIF(trim(au.raw_user_meta_data ->> 'company_name'), '');
  person  := COALESCE(NULLIF(trim(au.raw_user_meta_data ->> 'full_name'), ''), split_part(au.email, '@', 1));
  IF company IS NULL THEN
    RAISE EXCEPTION 'No Vigil account is provisioned for %. Ask your administrator for an invite.', au.email;
  END IF;

  INSERT INTO public.workspace_signups (auth_user_id) VALUES (uid);

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
