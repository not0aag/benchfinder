begin;
create extension if not exists pgtap with schema extensions;
select plan(31);

-- ---------- fixtures ----------
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'alice@test.local', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'bob@test.local', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'mod@test.local', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'banned@test.local', '', now(), '{}', '{}', now(), now());

select set_config('benchfinder.state_transition', 'allowed', true);
update user_profiles set role = 'moderator' where user_id = '00000000-0000-0000-0000-000000000003';
update user_profiles set banned_until = now() + interval '1 day' where user_id = '00000000-0000-0000-0000-000000000004';
select set_config('benchfinder.state_transition', '', true);

insert into bf_benches (id, geom, origin, status, verification_state, created_by) values
  ('40000000-0000-0000-0000-000000000001', st_setsrid(st_makepoint(-79.70, 43.45), 4326)::geography, 'user', 'published', 'community', '00000000-0000-0000-0000-000000000002'),
  ('40000000-0000-0000-0000-000000000002', st_setsrid(st_makepoint(-79.71, 43.46), 4326)::geography, 'user', 'pending', 'unconfirmed', '00000000-0000-0000-0000-000000000001');

-- ---------- bench_photos ----------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$insert into bench_photos (id, bench_id, storage_path, phash, width, height, bytes, uploaded_by)
    values ('50000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 'p/1.jpg', b'0'::bit(64), 100, 100, 1000, '00000000-0000-0000-0000-000000000001')$$,
  'user can add a photo to a published bench'
);
select throws_ok(
  $$insert into bench_photos (bench_id, storage_path, phash, width, height, bytes, uploaded_by)
    values ('40000000-0000-0000-0000-000000000001', 'p/2.jpg', b'0'::bit(64), 100, 100, 1000, '00000000-0000-0000-0000-000000000002')$$,
  '42501',
  null,
  'uploader cannot be spoofed'
);
select lives_ok(
  $$insert into bench_photos (id, bench_id, storage_path, phash, width, height, bytes, uploaded_by)
    values ('50000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000002', 'p/3.jpg', b'0'::bit(64), 100, 100, 1000, '00000000-0000-0000-0000-000000000001')$$,
  'owner can add a photo to own pending bench'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select throws_ok(
  $$insert into bench_photos (bench_id, storage_path, phash, width, height, bytes, uploaded_by)
    values ('40000000-0000-0000-0000-000000000002', 'p/4.jpg', b'0'::bit(64), 100, 100, 1000, '00000000-0000-0000-0000-000000000002')$$,
  '42501',
  null,
  'stranger cannot attach photos to an invisible pending bench'
);

reset role;
set local role anon;
select set_config('request.jwt.claims', '', true);
select is(
  (select count(*) from bench_photos where bench_id = '40000000-0000-0000-0000-000000000001'),
  1::bigint,
  'anon sees photos of published benches'
);
select is(
  (select count(*) from bench_photos where bench_id = '40000000-0000-0000-0000-000000000002'),
  0::bigint,
  'anon cannot see photos of pending benches'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
update bench_photos set moderation = 'approved' where id = '50000000-0000-0000-0000-000000000001';
reset role;
select is(
  (select moderation from bench_photos where id = '50000000-0000-0000-0000-000000000001'),
  'pending',
  'non-moderator cannot change photo moderation'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
update bench_photos set moderation = 'approved' where id = '50000000-0000-0000-0000-000000000001';
reset role;
select is(
  (select moderation from bench_photos where id = '50000000-0000-0000-0000-000000000001'),
  'approved',
  'moderator can change photo moderation'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
delete from bench_photos where id = '50000000-0000-0000-0000-000000000001';
reset role;
select is(
  (select count(*) from bench_photos where id = '50000000-0000-0000-0000-000000000001'),
  1::bigint,
  'stranger cannot delete another user''s photo'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
delete from bench_photos where id = '50000000-0000-0000-0000-000000000001';
reset role;
select is(
  (select count(*) from bench_photos where id = '50000000-0000-0000-0000-000000000001'),
  0::bigint,
  'uploader can delete own photo'
);

select is(
  (select photo_count from bf_benches where id = '40000000-0000-0000-0000-000000000001'),
  0,
  'photo_count aggregate tracks deletes'
);
select is(
  (select photo_count from bf_benches where id = '40000000-0000-0000-0000-000000000002'),
  1,
  'photo_count aggregate tracks inserts'
);

-- ---------- bench_ratings ----------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$insert into bench_ratings (bench_id, user_id, scenic, comfort)
    values ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 5, 4)$$,
  'user can rate a published bench'
);
select throws_ok(
  $$insert into bench_ratings (bench_id, user_id, scenic, comfort)
    values ('40000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 3, 3)$$,
  '42501',
  null,
  'cannot rate a pending bench'
);
select throws_ok(
  $$insert into bench_ratings (bench_id, user_id, scenic, comfort)
    values ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 1, 1)$$,
  '42501',
  null,
  'cannot rate as someone else'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select lives_ok(
  $$insert into bench_ratings (bench_id, user_id, scenic, comfort)
    values ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 3, 2)$$,
  'second user can rate the same bench'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","role":"authenticated"}', true);
select throws_ok(
  $$insert into bench_ratings (bench_id, user_id, scenic, comfort)
    values ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004', 1, 1)$$,
  '42501',
  null,
  'banned user cannot rate'
);

reset role;
select is(
  (select rating_count from bf_benches where id = '40000000-0000-0000-0000-000000000001'),
  2,
  'rating_count aggregate maintained'
);
select is(
  (select scenic_avg from bf_benches where id = '40000000-0000-0000-0000-000000000001'),
  4.00::numeric(3, 2),
  'scenic_avg aggregate maintained'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
update bench_ratings set scenic = 1
  where bench_id = '40000000-0000-0000-0000-000000000001'
    and user_id = '00000000-0000-0000-0000-000000000001';
reset role;
select is(
  (select scenic from bench_ratings
   where bench_id = '40000000-0000-0000-0000-000000000001'
     and user_id = '00000000-0000-0000-0000-000000000001'),
  5::smallint,
  'user cannot edit another user''s rating'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
update bench_ratings set scenic = 4
  where bench_id = '40000000-0000-0000-0000-000000000001'
    and user_id = '00000000-0000-0000-0000-000000000001';
reset role;
select is(
  (select scenic from bench_ratings
   where bench_id = '40000000-0000-0000-0000-000000000001'
     and user_id = '00000000-0000-0000-0000-000000000001'),
  4::smallint,
  'user can edit own rating'
);

set local role anon;
select set_config('request.jwt.claims', '', true);
select is(
  (select count(*) from bench_ratings where bench_id = '40000000-0000-0000-0000-000000000001'),
  2::bigint,
  'anon can read ratings of published benches'
);

-- ---------- bench_confirmations ----------
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$insert into bench_confirmations (bench_id, user_id, present, at_geom)
    values ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', true, st_setsrid(st_makepoint(-79.70, 43.45), 4326)::geography)$$,
  'user can confirm a published bench'
);
select throws_ok(
  $$insert into bench_confirmations (bench_id, user_id, present, at_geom)
    values ('40000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', true, st_setsrid(st_makepoint(-79.71, 43.46), 4326)::geography)$$,
  '42501',
  null,
  'cannot confirm a pending bench'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select lives_ok(
  $$insert into bench_confirmations (bench_id, user_id, present, at_geom)
    values ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', false, st_setsrid(st_makepoint(-79.70, 43.45), 4326)::geography)$$,
  'second user can report not-there'
);
select is(
  (select count(*) from bench_confirmations where bench_id = '40000000-0000-0000-0000-000000000001'),
  1::bigint,
  'users see only their own confirmations'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
select is(
  (select count(*) from bench_confirmations where bench_id = '40000000-0000-0000-0000-000000000001'),
  2::bigint,
  'moderator sees all confirmations'
);

reset role;
select is(
  (select confirm_count from bf_benches where id = '40000000-0000-0000-0000-000000000001'),
  1,
  'confirm_count aggregate maintained'
);
select is(
  (select dispute_count from bf_benches where id = '40000000-0000-0000-0000-000000000001'),
  1,
  'dispute_count aggregate maintained'
);

-- ---------- bench_favorites ----------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$insert into bench_favorites (bench_id, user_id)
    values ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001')$$,
  'user can favourite a bench'
);
select throws_ok(
  $$insert into bench_favorites (bench_id, user_id)
    values ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002')$$,
  '42501',
  null,
  'cannot favourite as someone else'
);
select is(
  (select count(*) from bench_favorites),
  1::bigint,
  'user sees own favourites'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select is(
  (select count(*) from bench_favorites),
  0::bigint,
  'favourites are private to their owner'
);

reset role;
select is(
  (select favorite_count from bf_benches where id = '40000000-0000-0000-0000-000000000001'),
  1,
  'favorite_count aggregate maintained'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
delete from bench_favorites
  where bench_id = '40000000-0000-0000-0000-000000000001'
    and user_id = '00000000-0000-0000-0000-000000000001';
reset role;
select is(
  (select favorite_count from bf_benches where id = '40000000-0000-0000-0000-000000000001'),
  0,
  'unfavourite removes the row and updates the aggregate'
);

select * from finish();
rollback;
