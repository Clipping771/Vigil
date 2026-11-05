-- ==============================================================================
-- VIGIL — PUBLIC HOLIDAYS MIGRATION (009)
-- ------------------------------------------------------------------------------
-- Run in the Supabase SQL Editor after 008. Idempotent and safe to re-run.
--
-- Stores each organization's own list of public holidays. Leave balances do not
-- count these dates. The list starts empty because holidays differ by state, so
-- each organization adds its own in Settings.
--
-- Everyone in the organization can read the list, because balances need it.
-- Only managers and admins can change it, matching organization_settings.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.public_holidays (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  holiday_date DATE NOT NULL,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Also serves as the index for looking up an organization's holidays.
ALTER TABLE public.public_holidays DROP CONSTRAINT IF EXISTS public_holidays_org_date_key;
ALTER TABLE public.public_holidays ADD CONSTRAINT public_holidays_org_date_key
  UNIQUE (organization_id, holiday_date);

ALTER TABLE public.public_holidays DROP CONSTRAINT IF EXISTS public_holidays_name_check;
ALTER TABLE public.public_holidays ADD CONSTRAINT public_holidays_name_check
  CHECK (length(btrim(name)) BETWEEN 1 AND 100);

DROP TRIGGER IF EXISTS trg_public_holidays_updated_at ON public.public_holidays;
CREATE TRIGGER trg_public_holidays_updated_at
  BEFORE UPDATE ON public.public_holidays
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.public_holidays ENABLE ROW LEVEL SECURITY;

-- Supabase gives anon access to new tables by default.
REVOKE ALL ON public.public_holidays FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.public_holidays TO authenticated;

DROP POLICY IF EXISTS public_holidays_select ON public.public_holidays;
CREATE POLICY public_holidays_select ON public.public_holidays FOR SELECT TO authenticated
  USING (organization_id = public.get_user_org_id() OR public.is_system_admin());

DROP POLICY IF EXISTS public_holidays_write ON public.public_holidays;
CREATE POLICY public_holidays_write ON public.public_holidays FOR ALL TO authenticated
  USING ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin())
  WITH CHECK ((organization_id = public.get_user_org_id() AND public.is_manager_or_admin()) OR public.is_system_admin());

-- Live updates. If the publication does not exist yet, enable_realtime.sql adds
-- this table when it creates the publication.
ALTER TABLE public.public_holidays REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'public_holidays'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.public_holidays;
  END IF;
END $$;
