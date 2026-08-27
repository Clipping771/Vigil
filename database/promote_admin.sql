-- PRODUCTION SECURITY SCRIPT
-- Purpose: Safely promote an existing staff/manager to System Admin.
-- Instructions: Run this in your Supabase SQL Editor.

-- Replace 'admin@yourcompany.com' with the email of the person you want to promote.
UPDATE public.employees
SET role = 'system_admin'
WHERE email = 'admin@yourcompany.com';
