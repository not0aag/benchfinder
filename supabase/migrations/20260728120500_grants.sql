-- Table-level grants: what each API role may attempt. RLS then filters rows.
-- Local stack does not apply default privileges to migration-created tables,
-- so grants are explicit. No client role ever gets DDL or delete-on-bench.

grant usage on schema public to anon, authenticated, service_role;

-- service role (edge functions, import tooling) sees everything; RLS does not
-- apply to it.
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;

-- read-only public data
grant select on osm_features to anon, authenticated;
grant select on bf_benches to anon, authenticated;
grant select on bench_photos to anon, authenticated;
grant select on bench_ratings to anon, authenticated;
grant select on user_profiles to anon, authenticated;

-- authenticated contributions (own-row enforcement lives in RLS policies)
grant insert, update on bf_benches to authenticated;
grant insert, update, delete on bench_photos to authenticated;
grant insert, update, delete on bench_ratings to authenticated;
grant select, insert, update on bench_confirmations to authenticated;
grant select, insert, delete on bench_favorites to authenticated;
grant update on user_profiles to authenticated;

-- audit log is read-only for clients; rows come from definer functions.
grant select on moderation_events to authenticated;
