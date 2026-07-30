begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'alice@test.local', '', now(), '{}', '{}', now(), now());

insert into osm_features (osm_id, osm_type, geom, tags, osm_version) values
  (9100000001, 'node', st_setsrid(st_makepoint(-79.661, 43.4445), 4326)::geography, '{"amenity":"bench"}'::jsonb, 1);

insert into bf_benches (id, geom, origin, source_osm_id, status, verification_state, created_by) values
  ('80000000-0000-0000-0000-000000000001', st_setsrid(st_makepoint(-79.66, 43.444), 4326)::geography, 'user', null, 'published', 'community', '00000000-0000-0000-0000-000000000001'),
  ('80000000-0000-0000-0000-000000000002', st_setsrid(st_makepoint(-79.65, 43.445), 4326)::geography, 'user', null, 'pending', 'unconfirmed', '00000000-0000-0000-0000-000000000001'),
  ('80000000-0000-0000-0000-000000000003', st_setsrid(st_makepoint(-79.661, 43.4445), 4326)::geography, 'osm', 9100000001, 'published', 'unconfirmed', '00000000-0000-0000-0000-000000000001');

set local role anon;
select set_config('request.jwt.claims', '', true);

select is(
  (select count(*) from bench_details where id = '80000000-0000-0000-0000-000000000001'),
  1::bigint,
  'anon reads published bench through the view'
);
select is(
  (select count(*) from bench_details where id = '80000000-0000-0000-0000-000000000002'),
  0::bigint,
  'view inherits RLS: pending stays hidden'
);
select ok(
  (select abs(lat - 43.444) < 1e-9 and abs(lon - (-79.66)) < 1e-9
   from bench_details where id = '80000000-0000-0000-0000-000000000001'),
  'lat/lon unpacked from geography'
);
select is(
  (select origin from bench_details where id = '80000000-0000-0000-0000-000000000003'),
  'osm'::bench_origin,
  'origin is exposed for provenance UX'
);
select is(
  (select source_osm_id from bench_details where id = '80000000-0000-0000-0000-000000000003'),
  9100000001::bigint,
  'source_osm_id is exposed for ODbL provenance'
);

select * from finish();
rollback;
