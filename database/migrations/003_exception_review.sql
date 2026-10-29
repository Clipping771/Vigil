-- ==============================================================================
-- VIGIL — EXCEPTION REVIEW MIGRATION (003)
-- ------------------------------------------------------------------------------
-- Run in the Supabase SQL Editor after 002. Idempotent and safe to re-run.
--
-- 1. Records WHO reviewed each exception (resolved / acknowledged / dismissed)
--    and WHEN. Set by the database from the signed-in user, never trusted
--    from the client.
-- 2. Writes every review action to audit_logs.
-- 3. Staff can only see their own exceptions; managers see the organization's.
-- ==============================================================================

ALTER TABLE public.exception_records
  ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.stamp_exception_review()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.reviewed_by := NULL;
    NEW.reviewed_at := NULL;
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'pending' THEN
      NEW.reviewed_by := NULL;
      NEW.reviewed_at := NULL;
      NEW.resolved_at := NULL;
    ELSE
      NEW.reviewed_by := public.current_employee_id();  -- NULL when the server acts
      NEW.reviewed_at := now();
      IF NEW.status = 'resolved' AND NEW.resolved_at IS NULL THEN
        NEW.resolved_at := now();
      END IF;
    END IF;

    INSERT INTO public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, details)
    VALUES (
      NEW.organization_id, NEW.reviewed_by, 'exception_' || NEW.status, 'exception_record', NEW.id,
      jsonb_build_object('type', NEW.exception_type, 'employee_id', NEW.employee_id,
                         'previous_status', OLD.status, 'note', NEW.resolution_note)
    );
  ELSE
    -- Reviewer fields cannot be edited directly.
    NEW.reviewed_by := OLD.reviewed_by;
    NEW.reviewed_at := OLD.reviewed_at;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_exception_review ON public.exception_records;
CREATE TRIGGER trg_exception_review
  BEFORE INSERT OR UPDATE ON public.exception_records
  FOR EACH ROW EXECUTE FUNCTION public.stamp_exception_review();

-- Staff see only their own exceptions; managers and admins see everyone's.
DROP POLICY IF EXISTS exceptions_select ON public.exception_records;
CREATE POLICY exceptions_select ON public.exception_records FOR SELECT TO authenticated
  USING ((organization_id = public.get_user_org_id()
          AND (public.is_manager_or_admin() OR employee_id = public.current_employee_id()))
         OR public.is_system_admin());
