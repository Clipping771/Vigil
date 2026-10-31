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

-- ==============================================================================
-- Everything is now 100% clean.
-- You can now go to the landing page and choose "Workspace admin setup"
-- to create your fresh SecureLock Global workspace!
-- ==============================================================================
