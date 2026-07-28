begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

-- ---------- fixtures (as postgres, bypasses RLS) ----------
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'alice@test.local', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'bob@test.local', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'mod@test.local', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'banned@test.local', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'trusted@test.local', '', now(), '{}', '{}', now(), now());

select set_config('benchfinder.state_transition', 'allowed', true);
update user_profiles set role = 'moderator' where user_id = '00000000-0000-0000-0000-000000000003';
update user_profiles set banned_until = now() + interval '1 day' where user_id = '00000000-0000-0000-0000-000000000004';
update user_profiles set role = 'trusted' where user_id = '00000000-0000-0000-0000-000000000005';
select set_config('benchfinder.state_transition', '', true);

insert into bf_benches (id, geom, origin, status, verification_state, created_by) values
  ('20000000-0000-0000-0000-000000000001', st_setsrid(st_makepoint(-79.70, 43.45), 4326)::geography, 'user', 'published', 'community', '00000000-0000-0000-0000-000000000002'),
  ('20000000-0000-0000-0000-000000000002', st_setsrid(st_makepoint(-79.71, 43.46), 4326)::geography, 'user', 'pending', 'unconfirmed', '00000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000003', st_setsrid(st_makepoint(-79.72, 43.47), 4326)::geography, 'user', 'pending', 'unconfirmed', '00000000-0000-0000-0000-000000000002');

-- ---------- bench_read: anon ----------
set local role anon;
select set_config('request.jwt.claims', '', true);

select is(
  (select count(*) from bf_benches where id = '20000000-0000-0000-0000-000000000001'),
  1::bigint,
  'anon sees published benches'
);
select is(
  (select count(*) from bf_benches where status = 'pending'),
  0::bigint,
  'anon cannot see pending benches'
);

-- ---------- bench_read: owner and stranger ----------
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select is(
  (select count(*) from bf_benches where id = '20000000-0000-0000-0000-000000000002'),
  1::bigint,
  'owner sees own pending submission'
);
select is(
  (select count(*) from bf_benches where id = '20000000-0000-0000-0000-000000000003'),
  0::bigint,
  'user cannot see another user''s pending submission'
);

-- ---------- bench_read: moderator ----------
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}', true);

select is(
  (select count(*) from bf_benches where id = '20000000-0000-0000-0000-000000000003'),
  1::bigint,
  'moderator sees pending benches'
);

-- ---------- bench_insert ----------
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$insert into bf_benches (geom, origin, status, verification_state, created_by)
    values (st_setsrid(st_makepoint(-79.73, 43.44), 4326)::geography, 'user', 'pending', 'unconfirmed', '00000000-0000-0000-0000-000000000001')$$,
  'user can submit a pending bench'
);
select throws_ok(
  $$insert into bf_benches (geom, origin, status, verification_state, created_by)
    values (st_setsrid(st_makepoint(-79.73, 43.44), 4326)::geography, 'user', 'published', 'unconfirmed', '00000000-0000-0000-0000-000000000001')$$,
  '42501',
  null,
  'client cannot self-publish on insert'
);
select throws_ok(
  $$insert into bf_benches (geom, origin, status, verification_state, created_by)
    values (st_setsrid(st_makepoint(-79.73, 43.44), 4326)::geography, 'user', 'pending', 'unconfirmed', '00000000-0000-0000-0000-000000000002')$$,
  '42501',
  null,
  'client cannot attribute a submission to someone else'
);
select throws_ok(
  $$insert into bf_benches (geom, origin, status, verification_state, created_by)
    values (st_setsrid(st_makepoint(-79.73, 43.44), 4326)::geography, 'osm', 'pending', 'unconfirmed', '00000000-0000-0000-0000-000000000001')$$,
  '42501',
  null,
  'client cannot claim osm origin'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","role":"authenticated"}', true);

select throws_ok(
  $$insert into bf_benches (geom, origin, status, verification_state, created_by)
    values (st_setsrid(st_makepoint(-79.73, 43.44), 4326)::geography, 'user', 'pending', 'unconfirmed', '00000000-0000-0000-0000-000000000004')$$,
  '42501',
  null,
  'banned user cannot submit'
);

-- ---------- bench_update ----------
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

update bf_benches set has_backrest = true where id = '20000000-0000-0000-0000-000000000001';
select ok(
  (select has_backrest from bf_benches where id = '20000000-0000-0000-0000-000000000001') is null,
  'plain user cannot edit bench attributes'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","role":"authenticated"}', true);

update bf_benches set has_backrest = true where id = '20000000-0000-0000-0000-000000000001';
select is(
  (select has_backrest from bf_benches where id = '20000000-0000-0000-0000-000000000001'),
  true,
  'trusted user can edit bench attributes'
);

select throws_ok(
  $$update bf_benches set status = 'removed' where id = '20000000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'trusted user cannot write a status transition'
);
select throws_ok(
  $$update bf_benches set created_by = '00000000-0000-0000-0000-000000000005' where id = '20000000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'provenance columns are immutable from the client'
);

-- ---------- no delete ----------
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

delete from bf_benches where id = '20000000-0000-0000-0000-000000000001';
select is(
  (select count(*) from bf_benches where id = '20000000-0000-0000-0000-000000000001'),
  1::bigint,
  'no client can hard-delete a bench'
);

select * from finish();
rollback;
