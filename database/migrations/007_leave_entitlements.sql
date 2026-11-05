-- ==============================================================================
-- VIGIL — LEAVE ENTITLEMENTS MIGRATION (007)
-- ------------------------------------------------------------------------------
-- Run in the Supabase SQL Editor after 006. Idempotent and safe to re-run.
--
-- Stores each employee's employment type and yearly annual and sick leave
-- allowance. Existing employees become full-time on 20 and 10 days, the values
-- the app used for everyone until now, so managers must update anyone else.
--
-- Employees may update their own row (see employees_update), so a trigger stops
-- them changing these columns. Managers cannot change their own either.
-- ==============================================================================

ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS employment_type TEXT NOT NULL DEFAULT 'full_time',
  ADD COLUMN IF NOT EXISTS annual_leave_days INTEGER NOT NULL DEFAULT 20,
  ADD COLUMN IF NOT EXISTS sick_leave_days INTEGER NOT NULL DEFAULT 10;

ALTER TABLE public.employees DROP CONSTRAINT IF EXISTS employees_employment_type_check;
ALTER TABLE public.employees ADD CONSTRAINT employees_employment_type_check
  CHECK (employment_type IN ('full_time', 'part_time', 'casual'));

ALTER TABLE public.employees DROP CONSTRAINT IF EXISTS employees_annual_leave_days_check;
ALTER TABLE public.employees ADD CONSTRAINT employees_annual_leave_days_check
  CHECK (annual_leave_days BETWEEN 0 AND 366);

ALTER TABLE public.employees DROP CONSTRAINT IF EXISTS employees_sick_leave_days_check;
ALTER TABLE public.employees ADD CONSTRAINT employees_sick_leave_days_check
  CHECK (sick_leave_days BETWEEN 0 AND 366);

CREATE OR REPLACE FUNCTION public.guard_leave_entitlements()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.employment_type IS NOT DISTINCT FROM OLD.employment_type
     AND NEW.annual_leave_days IS NOT DISTINCT FROM OLD.annual_leave_days
     AND NEW.sick_leave_days IS NOT DISTINCT FROM OLD.sick_leave_days THEN
    RETURN NEW;
  END IF;

  -- No signed-in user means the SQL Editor or a server-side job.
  IF auth.uid() IS NULL OR public.is_system_admin() THEN
    RETURN NEW;
  END IF;

  IF NOT public.is_manager_or_admin() THEN
    RAISE EXCEPTION 'Only managers can change leave entitlements';
  END IF;
  IF OLD.auth_user_id = auth.uid() AND NOT public.is_org_admin() THEN
    RAISE EXCEPTION 'You cannot change your own leave entitlements';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_employees_guard_leave ON public.employees;
CREATE TRIGGER trg_employees_guard_leave
  BEFORE UPDATE ON public.employees
  FOR EACH ROW EXECUTE FUNCTION public.guard_leave_entitlements();
