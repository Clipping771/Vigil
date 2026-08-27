-- DUMMY DATA FOR MULTI-TENANT SAAS PROTOTYPE
-- Run this in your Supabase SQL Editor.

DO $$ 
DECLARE
  org1_id UUID := gen_random_uuid();
  org2_id UUID := gen_random_uuid();
  uid1 UUID := gen_random_uuid();
  uid2 UUID := gen_random_uuid();
  uid3 UUID := gen_random_uuid();
  uid4 UUID := gen_random_uuid();
BEGIN
  -- 1. Insert Organizations
  INSERT INTO public.organizations (id, name, subscription_plan)
  VALUES 
  (org1_id, 'SecureLock Global', 'enterprise'),
  (org2_id, 'Acme Corp', 'pro');

  -- 2. Insert into auth.users
  INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES 
  ('00000000-0000-0000-0000-000000000000', uid1, 'authenticated', 'authenticated', 'alice.smith@securelock.com', 'dummy', now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', uid2, 'authenticated', 'authenticated', 'bob.jones@securelock.com', 'dummy', now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', uid3, 'authenticated', 'authenticated', 'carol.white@securelock.com', 'dummy', now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', uid4, 'authenticated', 'authenticated', 'david.brown@acme.com', 'dummy', now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now());

  -- 3. Insert into public.employees
  INSERT INTO public.employees (id, organization_id, email, full_name, role, site_location)
  VALUES
  (uid1, org1_id, 'alice.smith@securelock.com', 'Alice Smith', 'owner', 'Oakleigh HQ'),
  (uid2, org1_id, 'bob.jones@securelock.com', 'Bob Jones', 'staff', 'Sydney Branch'),
  (uid3, org1_id, 'carol.white@securelock.com', 'Carol White', 'manager', 'Melbourne Factory'),
  (uid4, org2_id, 'david.brown@acme.com', 'David Brown', 'owner', 'Brisbane Warehouse');

  -- 4. Insert into public.shifts
  INSERT INTO public.shifts (organization_id, employee_id, site_location, start_time, end_time)
  VALUES
  (org1_id, uid2, 'Sydney Branch', now() + interval '1 day' + interval '9 hours', now() + interval '1 day' + interval '17 hours'),
  (org1_id, uid3, 'Melbourne Factory', now() + interval '1 day' + interval '6 hours', now() + interval '1 day' + interval '14 hours'),
  (org2_id, uid4, 'Brisbane Warehouse', now() + interval '2 days' + interval '10 hours', now() + interval '2 days' + interval '18 hours');

  -- 5. Insert into public.exception_records
  INSERT INTO public.exception_records (organization_id, employee_id, exception_type, severity, status, description)
  VALUES
  (org1_id, uid2, 'missed_clock_in', 'high', 'pending', 'Bob failed to clock in for morning shift.'),
  (org1_id, uid3, 'excessive_overtime', 'medium', 'pending', 'Carol clocked out 2.5 hours after shift ended.'),
  (org2_id, uid4, 'geofence_violation', 'high', 'pending', 'David clocked in 5km away from the warehouse.');

END $$;
