begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

-- ---------- fixtures ----------
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'alice@test.local', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'bob@test.local', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'mod@test.local', '', now(), '{}', '{}', now(), now());

select set_config('benchfinder.state_transition', 'allowed', true);
update user_profiles set role = 'moderator' where user_id = '00000000-0000-0000-0000-000000000003';
select set_config('benchfinder.state_transition', '', true);

insert into bf_benches (id, geom, origin, status, verification_state, created_by) values
  ('60000000-0000-0000-0000-000000000001', st_setsrid(st_makepoint(-79.70, 43.45), 4326)::geography, 'user', 'pending', 'unconfirmed', '00000000-0000-0000-0000-000000000001');

-- ---------- profile creation ----------
select is(
  (select trust_score from user_profiles where user_id = '00000000-0000-0000-0000-000000000001'),
  10::smallint,
  'new accounts start at trust 10'
);
select is(
  (select role from user_profiles where user_id = '00000000-0000-0000-0000-000000000001'),
  'user',
  'new accounts start as plain users'
);

-- ---------- profile read ----------
set local role anon;
select set_config('request.jwt.claims', '', true);
select is(
  (select count(*) from user_profiles),
  3::bigint,
  'profiles are publicly readable'
);

-- ---------- profile update ----------
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$update user_profiles set display_name = 'alice-renamed' where user_id = '00000000-0000-0000-0000-000000000001'$$,
  'user can rename themselves'
);

update user_profiles set display_name = 'gotcha' where user_id = '00000000-0000-0000-0000-000000000002';
reset role;
select is(
  (select display_name from user_profiles where user_id = '00000000-0000-0000-0000-000000000002'),
  'bob',
  'user cannot rename someone else'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select throws_ok(
  $$update user_profiles set trust_score = 100 where user_id = '00000000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'trust score is not client-writable'
);
select throws_ok(
  $$update user_profiles set role = 'admin' where user_id = '00000000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'role is not client-writable'
);
select throws_ok(
  $$update user_profiles set banned_until = now() + interval '10 years' where user_id = '00000000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'ban timestamps are not client-writable'
);

-- ---------- moderation_events ----------
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}', true);

select lives_ok(
  $$select moderate_bench_status('60000000-0000-0000-0000-000000000001', 'published', 'test event')$$,
  'moderator action creates an event'
);
select is(
  (select count(*) from moderation_events where bench_id = '60000000-0000-0000-0000-000000000001'),
  1::bigint,
  'moderator can read events'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select is(
  (select count(*) from moderation_events where bench_id = '60000000-0000-0000-0000-000000000001'),
  0::bigint,
  'plain user cannot read the audit log'
);
select throws_ok(
  $$insert into moderation_events (bench_id, actor_id, action)
    values ('60000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'forged')$$,
  '42501',
  null,
  'clients cannot write audit events'
);

reset role;
set local role anon;
select set_config('request.jwt.claims', '', true);
select is(
  (select count(*) from moderation_events),
  0::bigint,
  'anon cannot read the audit log'
);

-- banned_until=null probe above must not have changed anything
reset role;
select ok(
  (select banned_until is null from user_profiles where user_id = '00000000-0000-0000-0000-000000000001'),
  'failed probes leave state untouched'
);

select * from finish();
rollback;
