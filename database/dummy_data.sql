-- ==============================================================================
-- DUMMY DATA SEED FOR VIGIL SAAS MULTI-TENANT SYSTEM
-- Run this in Supabase SQL Editor after executing schema.sql
-- ==============================================================================

DO $$ 
DECLARE
  org1_id UUID := gen_random_uuid();
  org2_id UUID := gen_random_uuid();
  uid1 UUID := gen_random_uuid();
  uid2 UUID := gen_random_uuid();
  uid3 UUID := gen_random_uuid();
  uid4 UUID := gen_random_uuid();
  uid5 UUID := gen_random_uuid();
  shift1_id UUID := gen_random_uuid();
  shift2_id UUID := gen_random_uuid();
BEGIN
  -- 1. Insert Organizations
  INSERT INTO public.organizations (id, name, subscription_plan)
  VALUES 
  (org1_id, 'SecureLock Global', 'enterprise'),
  (org2_id, 'Acme Corp', 'pro');

  -- 2. Insert Organization Settings
  INSERT INTO public.organization_settings (organization_id, allowed_late_minutes, allowed_overtime_minutes, auto_reporting_enabled, report_frequency, delivery_email)
  VALUES
  (org1_id, 15, 30, true, 'Daily', 'hr@securelock.com'),
  (org2_id, 10, 20, false, 'Weekly', 'admin@acme.com');

  -- 3. Insert into auth.users (if using Supabase Auth)
  INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES 
  ('00000000-0000-0000-0000-000000000000', uid1, 'authenticated', 'authenticated', 'alice.smith@securelock.com', 'dummy', now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', uid2, 'authenticated', 'authenticated', 'bob.jones@securelock.com', 'dummy', now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', uid3, 'authenticated', 'authenticated', 'carol.white@securelock.com', 'dummy', now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', uid4, 'authenticated', 'authenticated', 'david.brown@acme.com', 'dummy', now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', uid5, 'authenticated', 'authenticated', 'admin@admin.com', 'dummy', now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now())
  ON CONFLICT (id) DO NOTHING;

  -- 4. Insert into public.employees
  INSERT INTO public.employees (id, organization_id, email, full_name, role, site_location)
  VALUES
  (uid1, org1_id, 'alice.smith@securelock.com', 'Alice Smith', 'owner', 'Oakleigh HQ'),
  (uid2, org1_id, 'bob.jones@securelock.com', 'Bob Jones', 'staff', 'Sydney Branch'),
  (uid3, org1_id, 'carol.white@securelock.com', 'Carol White', 'manager', 'Melbourne Factory'),
  (uid4, org2_id, 'david.brown@acme.com', 'David Brown', 'owner', 'Brisbane Warehouse'),
  (uid5, org1_id, 'admin@admin.com', 'System Administrator', 'system_admin', 'Global Operations');

  -- 5. Insert into public.shifts
  INSERT INTO public.shifts (id, organization_id, employee_id, site_location, start_time, end_time)
  VALUES
  (shift1_id, org1_id, uid2, 'Sydney Branch', now() - interval '2 hours', now() + interval '6 hours'),
  (shift2_id, org1_id, uid3, 'Melbourne Factory', now() + interval '1 day' + interval '8 hours', now() + interval '1 day' + interval '16 hours'),
  (gen_random_uuid(), org2_id, uid4, 'Brisbane Warehouse', now() + interval '2 days' + interval '9 hours', now() + interval '2 days' + interval '17 hours');

  -- 6. Insert Breaks
  INSERT INTO public.breaks (organization_id, shift_id, employee_id, start_time, end_time, duration_minutes, break_type)
  VALUES
  (org1_id, shift1_id, uid2, now() - interval '30 minutes', now(), 30, 'meal');

  -- 7. Insert Clock Events
  INSERT INTO public.clock_events (organization_id, employee_id, event_type, event_time, latitude, longitude, is_geofenced)
  VALUES
  (org1_id, uid2, 'clock_in', now() - interval '2 hours', -33.8688, 151.2093, true);

  -- 8. Insert Exception Records
  INSERT INTO public.exception_records (organization_id, employee_id, exception_type, severity, status, description)
  VALUES
  (org1_id, uid2, 'missed_clock_in', 'high', 'pending', 'Bob missed clock-in by more than 15 minutes for scheduled morning shift.'),
  (org1_id, uid3, 'excessive_overtime', 'medium', 'pending', 'Carol clocked out 45 minutes after shift end without pre-approval.'),
  (org1_id, uid2, 'geofence_violation', 'high', 'pending', 'Clock-in attempted 450m away from authorized Sydney Branch geofence.');

  -- 9. Insert Leave Requests
  INSERT INTO public.leave_requests (organization_id, employee_id, start_date, end_date, leave_type, reason, status)
  VALUES
  (org1_id, uid2, CURRENT_DATE + interval '7 days', CURRENT_DATE + interval '10 days', 'annual', 'Family vacation to Gold Coast', 'pending'),
  (org1_id, uid3, CURRENT_DATE + interval '14 days', CURRENT_DATE + interval '15 days', 'sick', 'Doctor medical procedure', 'approved'),
  (org2_id, uid4, CURRENT_DATE + interval '20 days', CURRENT_DATE + interval '25 days', 'annual', 'Summer holidays', 'pending');

  -- 10. Insert Geofence Zones
  INSERT INTO public.geofence_zones (organization_id, name, latitude, longitude, radius_meters)
  VALUES
  (org1_id, 'Oakleigh HQ', -37.8988, 145.0915, 200.0),
  (org1_id, 'Sydney Branch', -33.8688, 151.2093, 150.0),
  (org2_id, 'Brisbane Warehouse', -27.4698, 153.0251, 300.0);

  -- 11. Insert Audit Logs
  INSERT INTO public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, details)
  VALUES
  (org1_id, uid1, 'CREATE_SHIFT', 'shift', shift1_id, '{"site": "Sydney Branch", "hours": 8}'::jsonb),
  (org1_id, uid3, 'RESOLVE_EXCEPTION', 'exception_record', gen_random_uuid(), '{"note": "Approved overtime due to client rush"}'::jsonb);

END $$;
