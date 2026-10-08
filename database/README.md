# Vigil Database & Architecture Guide

## 1. Overview
The **Vigil** database is built on **PostgreSQL (Supabase)**. It provides multi-tenant isolation, real-time event streaming, Fair Work compliance rule enforcement, and RBAC (Role-Based Access Control).

---

## 2. Table Schema (10 Core Tables)

| # | Table Name | Purpose | Key Columns |
|---|------------|---------|-------------|
| 1 | `organizations` | Tenant accounts & subscription tiers | `id`, `name`, `subscription_plan`, `created_at`, `updated_at` |
| 2 | `organization_settings` | Per-tenant compliance thresholds & reporting config | `organization_id`, `allowed_late_minutes`, `allowed_overtime_minutes`, `auto_reporting_enabled`, `report_frequency` |
| 3 | `employees` | Staff & manager directory with role assignments | `id`, `organization_id`, `email`, `full_name`, `role`, `site_location` |
| 4 | `shifts` | Scheduled shifts by day, time, and site location | `id`, `organization_id`, `employee_id`, `site_location`, `start_time`, `end_time` |
| 5 | `clock_events` | Raw GPS & QR clock-in/out timestamps | `id`, `organization_id`, `employee_id`, `event_type`, `event_time`, `latitude`, `longitude`, `is_geofenced` |
| 6 | `breaks` | Shift meal & rest breaks (Fair Work compliance) | `id`, `organization_id`, `shift_id`, `employee_id`, `start_time`, `end_time`, `duration_minutes`, `break_type` |
| 7 | `exception_records` | Flagged roster breaches, overtime, missed clocks | `id`, `organization_id`, `employee_id`, `exception_type`, `severity`, `shift_id`, `status`, `description` |
| 8 | `leave_requests` | Annual, sick, and unpaid leave applications & status | `id`, `organization_id`, `employee_id`, `start_date`, `end_date`, `leave_type`, `reason`, `status` |
| 9 | `geofence_zones` | Authorized work sites with GPS coordinates & radius | `id`, `organization_id`, `name`, `latitude`, `longitude`, `radius_meters` |
| 10| `audit_logs` | Security & enterprise compliance action logs | `id`, `organization_id`, `actor_id`, `action`, `entity_type`, `entity_id`, `details` |

---

## 3. Supported Roles (`employees.role`)
- `owner`: Organization creator with billing & admin rights
- `system_admin`: Platform super admin with cross-tenant management
- `admin`: Company administrator
- `hr`: Human resources officer (leaves, compliance, audit)
- `manager`: Site supervisor (approves shifts, exceptions, leaves)
- `staff`: Frontline employee (clocks in/out, takes breaks, applies for leave)

---

## 4. Multi-Tenant Security & Row Level Security (RLS)
Every table has **Row Level Security (RLS)** enabled with database-level security helper functions:
- `get_user_org_id()`: Derives the user's organization securely from `auth.uid()`.
- `is_manager_or_admin()`: Confirms management status.
- `is_system_admin()`: Confirms system administration privileges.

Cross-organization data leakage is blocked at the database engine level.

---

## 5. Deployment / Execution Steps in Supabase
1. Open your **Supabase Dashboard** -> **SQL Editor**.
2. Run [`schema.sql`](file:///c:/vigil/vigil/database/schema.sql) to create all 10 tables, triggers, indexes, and RLS policies.
3. Run [`enable_realtime.sql`](file:///c:/vigil/vigil/database/enable_realtime.sql) to activate live stream subscriptions for dashboard updates.
4. Run [`dummy_data.sql`](file:///c:/vigil/vigil/database/dummy_data.sql) to seed initial multi-tenant test organizations, shifts, breaks, and exceptions.
