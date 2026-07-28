-- Extensions live in the "extensions" schema per Supabase convention.
create extension if not exists postgis with schema extensions;
create extension if not exists pgcrypto with schema extensions;

-- pg_cron is configured on the hosted project only (nightly trust recompute,
-- nearby-amenities rebuild). The local dev image does not schedule jobs.
