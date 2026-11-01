-- ==============================================================================
-- VIGIL — ADMIN ROLE & WORKSPACE FOUNDER MIGRATION (004)
-- ------------------------------------------------------------------------------
-- Run in the Supabase SQL Editor after 003. Idempotent and safe to re-run.
--
-- The 'owner' role has been replaced by 'admin'. This migration:
-- 1. Converts any remaining 'owner' rows to 'admin'.
-- 2. Records the founder of each organization (the person who created the
--    workspace) so other admins cannot demote, move or remove them. Only a
--    system administrator can.
-- ==============================================================================

-- 1. Legacy owners become admins.
UPDATE public.employees SET role = 'admin' WHERE role = 'owner';

-- 2. Founder column, backfilled from the sign-up audit entry, else the earliest admin.
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS founder_employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL;

UPDATE public.organizations o
SET founder_employee_id = COALESCE(
  (SELECT a.actor_id FROM public.audit_logs a
   JOIN public.employees e ON e.id = a.actor_id AND e.organization_id = o.id
   WHERE a.organization_id = o.id AND a.action = 'organization_created'
   ORDER BY a.created_at LIMIT 1),
  (SELECT e.id FROM public.employees e
   WHERE e.organization_id = o.id AND e.role = 'admin'
   ORDER BY e.created_at LIMIT 1))
WHERE o.founder_employee_id IS NULL;

-- The first admin added to an organization without a founder becomes its
-- founder (covers self-service sign-up through link_current_user()).
CREATE OR REPLACE FUNCTION public.set_org_founder()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.role = 'admin' THEN
    UPDATE public.organizations SET founder_employee_id = NEW.id
    WHERE id = NEW.organization_id AND founder_employee_id IS NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_employees_set_founder ON public.employees;
CREATE TRIGGER trg_employees_set_founder
  AFTER INSERT ON public.employees
  FOR EACH ROW EXECUTE FUNCTION public.set_org_founder();

-- Other admins cannot demote, move or remove the founder.
CREATE OR REPLACE FUNCTION public.guard_founder()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Service role / SQL editor, system admins, and cascades (e.g. deleting the
  -- whole organization) are not restricted.
  IF auth.uid() IS NULL OR public.is_system_admin() OR pg_trigger_depth() > 1
     OR NOT EXISTS (SELECT 1 FROM public.organizations WHERE founder_employee_id = OLD.id) THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'The workspace founder cannot be removed';
  END IF;
  IF NEW.role IS DISTINCT FROM OLD.role OR NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
    RAISE EXCEPTION 'The workspace founder''s role cannot be changed';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_employees_guard_founder ON public.employees;
CREATE TRIGGER trg_employees_guard_founder
  BEFORE UPDATE OR DELETE ON public.employees
  FOR EACH ROW EXECUTE FUNCTION public.guard_founder();

-- Admins may update their organization (org_update policy) but not reassign
-- the founder. Nested updates from set_org_founder() and FK actions are allowed.
CREATE OR REPLACE FUNCTION public.guard_org_founder_column()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.founder_employee_id IS DISTINCT FROM OLD.founder_employee_id
     AND auth.uid() IS NOT NULL AND NOT public.is_system_admin() AND pg_trigger_depth() = 1 THEN
    RAISE EXCEPTION 'Only a system administrator can change the workspace founder';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_org_guard_founder ON public.organizations;
CREATE TRIGGER trg_org_guard_founder
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.guard_org_founder_column();
