-- ==========================================
-- VIGIL SAAS: AUTOMATED CRON SCHEDULER (PROOF OF CONCEPT)
-- ==========================================
-- This file demonstrates how Vigil achieves TRUE backend automation 
-- without relying on manual Flutter UI button clicks.
-- It utilizes PostgreSQL's pg_cron extension, which is natively supported by Supabase.

-- Enable the pg_cron extension (requires superuser)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 1. Example: Nightly Missing Clock-in Detector
-- Runs at 11:59 PM every night to scan the shifts and clock_events tables.
-- It calls a secure Supabase Edge Function to do the complex logic and push exceptions.
SELECT cron.schedule(
    'nightly-exception-scan',    -- Job Name
    '59 23 * * *',               -- Cron Schedule (11:59 PM Daily)
    $$
    SELECT net.http_post(
        url := 'https://nobpdaruaurhosimmcqk.supabase.co/functions/v1/detect_exceptions',
        headers := '{"Content-Type": "application/json", "Authorization": "Bearer YOUR_SERVICE_ROLE_KEY"}'::jsonb,
        body := '{"trigger": "cron"}'::jsonb
    );
    $$
);

-- 2. Example: Automated Scheduled Reporting (Daily at 5:00 PM)
-- Runs every day at 5:00 PM to generate the compliance CSV/PDF and email it to managers.
SELECT cron.schedule(
    'daily-compliance-report',   -- Job Name
    '0 17 * * *',                -- Cron Schedule (5:00 PM Daily)
    $$
    SELECT net.http_post(
        url := 'https://nobpdaruaurhosimmcqk.supabase.co/functions/v1/generate_reports',
        headers := '{"Content-Type": "application/json", "Authorization": "Bearer YOUR_SERVICE_ROLE_KEY"}'::jsonb,
        body := '{"target_orgs": "all"}'::jsonb
    );
    $$
);

-- ==========================================
-- HOW TO PRESENT THIS IN VIVA VOCE:
-- ==========================================
-- 1. Explain that mobile/web apps (Flutter) are just "Clients". They go to sleep.
-- 2. Real automation MUST happen on the backend.
-- 3. Show them this SQL script. Explain that Supabase pg_cron handles the scheduling, 
--    triggering Edge Functions that do the heavy lifting of PDF generation and Exception detection.
-- 4. The button in the Flutter UI is simply for "On-Demand" or "Demo" generation.
