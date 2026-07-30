begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

-- ---------- fixtures ----------
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'alice@test.local', '', now(), '{}', '{}', now(), now());

-- tile z14 x4566 y5992 covers lon [-79.6729, -79.6509], lat [43.437, 43.455]
insert into bf_benches (id, geom, origin, status, verification_state, created_by) values
  ('70000000-0000-0000-0000-000000000001', st_setsrid(st_makepoint(-79.660, 43.444), 4326)::geography, 'user', 'published', 'community', '00000000-0000-0000-0000-000000000001');

-- adjacent tile z14 x4567 y5992 gets only a pending bench
insert into bf_benches (id, geom, origin, status, verification_state, created_by) values
  ('70000000-0000-0000-0000-000000000002', st_setsrid(st_makepoint(-79.645, 43.444), 4326)::geography, 'user', 'pending', 'unconfirmed', '00000000-0000-0000-0000-000000000001');

-- ---------- tiles as anon ----------
set local role anon;
select set_config('request.jwt.claims', '', true);

select ok(
  coalesce(length(bench_tile(14, 4566, 5992)), 0) > 0,
  'anon gets a tile with published benches'
);
select ok(
  coalesce(length(bench_tile(14, 0, 5992)), 0) = 0,
  'empty region yields an empty tile'
);
select ok(
  coalesce(length(bench_tile(14, 4567, 5992)), 0) = 0,
  'pending benches never appear in tiles'
);
select throws_ok(
  $$select bench_tile(99, 0, 0)$$,
  '22023',
  null,
  'invalid zoom is rejected'
);
select throws_ok(
  $$select bench_tile(14, 16384, 0)$$,
  '22023',
  null,
  'invalid x coordinate is rejected'
);

-- publish the pending bench through the sanctioned path, tile appears
reset role;
select set_config('benchfinder.state_transition', 'allowed', true);
update bf_benches set status = 'published'
  where id = '70000000-0000-0000-0000-000000000002';
select set_config('benchfinder.state_transition', '', true);

set local role anon;
select set_config('request.jwt.claims', '', true);
select ok(
  coalesce(length(bench_tile(14, 4567, 5992)), 0) > 0,
  'published bench appears in its tile'
);

select * from finish();
rollback;
