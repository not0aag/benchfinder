begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

-- ---------- fixtures ----------
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'alice@test.local', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'mod@test.local', '', now(), '{}', '{}', now(), now());

select set_config('benchfinder.state_transition', 'allowed', true);
update user_profiles set role = 'moderator' where user_id = '00000000-0000-0000-0000-000000000003';
select set_config('benchfinder.state_transition', '', true);

insert into bf_benches (id, geom, origin, status, verification_state, created_by) values
  ('30000000-0000-0000-0000-000000000001', st_setsrid(st_makepoint(-79.70, 43.45), 4326)::geography, 'user', 'pending', 'unconfirmed', '00000000-0000-0000-0000-000000000001'),
  ('30000000-0000-0000-0000-000000000002', st_setsrid(st_makepoint(-79.71, 43.46), 4326)::geography, 'user', 'published', 'verified', '00000000-0000-0000-0000-000000000001'),
  ('30000000-0000-0000-0000-000000000003', st_setsrid(st_makepoint(-79.72, 43.47), 4326)::geography, 'user', 'published', 'unconfirmed', '00000000-0000-0000-0000-000000000001');

-- ---------- moderate_bench_status ----------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select throws_ok(
  $$select moderate_bench_status('30000000-0000-0000-0000-000000000001', 'published', 'nope')$$,
  '42501',
  null,
  'plain user cannot moderate status'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}', true);

select lives_ok(
  $$select moderate_bench_status('30000000-0000-0000-0000-000000000001', 'published', 'looks real')$$,
  'moderator can publish a pending bench'
);

reset role;
select is(
  (select status from bf_benches where id = '30000000-0000-0000-0000-000000000001'),
  'published'::bench_status,
  'status transition applied'
);
select is(
  (select count(*) from moderation_events
   where bench_id = '30000000-0000-0000-0000-000000000001'
     and action = 'status:pending->published'),
  1::bigint,
  'transition wrote an audit event'
);

select lives_ok(
  $$select moderate_bench_status('30000000-0000-0000-0000-000000000001', 'published', 'same state no-op')$$,
  'same status moderation call is a no-op'
);
select is(
  (select count(*) from moderation_events
   where bench_id = '30000000-0000-0000-0000-000000000001'
     and action = 'status:pending->published'),
  1::bigint,
  'no duplicate audit event for no-op status update'
);

set local role anon;
select set_config('request.jwt.claims', '', true);
select throws_ok(
  $$select moderate_bench_status('30000000-0000-0000-0000-000000000001', 'removed', null)$$,
  '42501',
  null,
  'anon cannot execute moderation functions'
);

-- ---------- set_verification_state ----------
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}', true);

select lives_ok(
  $$select set_verification_state('30000000-0000-0000-0000-000000000003', 'community', null)$$,
  'moderator can advance verification state'
);

reset role;
select is(
  (select verification_state from bf_benches where id = '30000000-0000-0000-0000-000000000003'),
  'community'::verification_state,
  'verification transition applied'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
select throws_ok(
  $$select set_verification_state('30000000-0000-0000-0000-000000000002', 'community', null)$$,
  '23514',
  null,
  'verified cannot be demoted to community'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select throws_ok(
  $$select set_verification_state('30000000-0000-0000-0000-000000000003', 'confirmed', null)$$,
  '42501',
  null,
  'plain user cannot set verification state'
);

-- ---------- remove_bench ----------
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}', true);

select lives_ok(
  $$select remove_bench('30000000-0000-0000-0000-000000000001', 'duplicate')$$,
  'moderator can soft-delete'
);

reset role;
select is(
  (select status from bf_benches where id = '30000000-0000-0000-0000-000000000001'),
  'removed'::bench_status,
  'soft delete sets status=removed'
);

-- ---------- transition map parity with packages/domain ----------
select is(
  (select bool_or(verification_transition_allowed(s, s))
   from unnest(enum_range(null::verification_state)) s),
  false,
  'no self-transitions'
);
select ok(
  verification_transition_allowed('unconfirmed', 'confirmed'),
  'unconfirmed can be confirmed directly'
);
select ok(
  verification_transition_allowed('disputed', 'verified'),
  'moderation can resolve a dispute to verified'
);
select ok(
  not verification_transition_allowed('verified', 'unconfirmed'),
  'verified never demotes except to disputed'
);

select * from finish();
rollback;
