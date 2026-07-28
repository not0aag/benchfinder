set search_path = public, extensions;

-- ============ HELPERS ============
-- SECURITY DEFINER so policies can consult user_profiles without RLS recursion.

create function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from user_profiles where user_id = auth.uid()
$$;

create function public.current_user_banned()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select banned_until > now() from user_profiles where user_id = auth.uid()),
    false
  )
$$;

-- ============ COLUMN GUARDS ============
-- RLS cannot compare OLD with NEW, so protected columns are enforced here.
-- State transitions happen only inside SECURITY DEFINER functions, which set
-- benchfinder.state_transition for the local transaction before writing.

create function public.guard_bench_protected_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_setting('benchfinder.state_transition', true) = 'allowed' then
    return new;
  end if;
  if new.status is distinct from old.status
     or new.verification_state is distinct from old.verification_state
     or new.merged_into is distinct from old.merged_into then
    raise exception 'state transitions are function-only'
      using errcode = '42501';
  end if;
  if new.created_by is distinct from old.created_by
     or new.origin is distinct from old.origin
     or new.source_osm_id is distinct from old.source_osm_id then
    raise exception 'provenance columns are immutable'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger bf_benches_guard
  before update on bf_benches
  for each row execute function public.guard_bench_protected_columns();

create function public.guard_profile_protected_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_setting('benchfinder.state_transition', true) = 'allowed' then
    return new;
  end if;
  if new.trust_score is distinct from old.trust_score
     or new.role is distinct from old.role
     or new.banned_until is distinct from old.banned_until then
    raise exception 'trust, role and ban changes are function-only'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger user_profiles_guard
  before update on user_profiles
  for each row execute function public.guard_profile_protected_columns();

-- ============ ROW LEVEL SECURITY ============

alter table osm_features        enable row level security;
alter table bf_benches          enable row level security;
alter table bench_photos        enable row level security;
alter table bench_ratings       enable row level security;
alter table bench_confirmations enable row level security;
alter table bench_favorites     enable row level security;
alter table user_profiles       enable row level security;
alter table moderation_events   enable row level security;

-- osm_features: public read; writes only via the import tool (service role).
create policy osm_read on osm_features for select using (true);

-- bf_benches
create policy bench_read on bf_benches for select using (
  status = 'published'
  or created_by = auth.uid()
  or current_user_role() in ('moderator', 'admin')
);

create policy bench_insert on bf_benches for insert with check (
  auth.uid() is not null
  and created_by = auth.uid()
  and status = 'pending'
  and verification_state = 'unconfirmed'
  and origin = 'user'
  and source_osm_id is null
  and not current_user_banned()
);

-- Attribute edits by trusted+. Protected columns are enforced by
-- bf_benches_guard; deletion is soft and function-only (no delete policy).
create policy bench_update on bf_benches for update
  using (current_user_role() in ('trusted', 'moderator', 'admin'))
  with check (current_user_role() in ('trusted', 'moderator', 'admin'));

-- bench_photos
create policy photo_read on bench_photos for select using (
  uploaded_by = auth.uid()
  or current_user_role() in ('moderator', 'admin')
  or exists (
    select 1 from bf_benches b
    where b.id = bench_id and (b.status = 'published' or b.created_by = auth.uid())
  )
);

create policy photo_insert on bench_photos for insert with check (
  auth.uid() is not null
  and uploaded_by = auth.uid()
  and not current_user_banned()
  and exists (
    select 1 from bf_benches b
    where b.id = bench_id and (b.status = 'published' or b.created_by = auth.uid())
  )
);

create policy photo_moderate on bench_photos for update
  using (current_user_role() in ('moderator', 'admin'))
  with check (current_user_role() in ('moderator', 'admin'));

create policy photo_delete on bench_photos for delete using (
  uploaded_by = auth.uid()
  or current_user_role() in ('moderator', 'admin')
);

-- bench_ratings: public read on published benches, own-row writes.
create policy rating_read on bench_ratings for select using (
  exists (select 1 from bf_benches b where b.id = bench_id and b.status = 'published')
  or user_id = auth.uid()
);

create policy rating_insert on bench_ratings for insert with check (
  auth.uid() is not null
  and user_id = auth.uid()
  and not current_user_banned()
  and exists (select 1 from bf_benches b where b.id = bench_id and b.status = 'published')
);

create policy rating_update on bench_ratings for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy rating_delete on bench_ratings for delete using (user_id = auth.uid());

-- bench_confirmations: own rows only; consensus reads happen server-side.
create policy confirmation_read on bench_confirmations for select using (
  user_id = auth.uid()
  or current_user_role() in ('moderator', 'admin')
);

create policy confirmation_insert on bench_confirmations for insert with check (
  auth.uid() is not null
  and user_id = auth.uid()
  and not current_user_banned()
  and exists (select 1 from bf_benches b where b.id = bench_id and b.status = 'published')
);

create policy confirmation_update on bench_confirmations for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- bench_favorites: private to their owner.
create policy favorite_read on bench_favorites for select using (user_id = auth.uid());

create policy favorite_insert on bench_favorites for insert with check (
  auth.uid() is not null and user_id = auth.uid()
);

create policy favorite_delete on bench_favorites for delete using (user_id = auth.uid());

-- user_profiles: public read (display data), own-row update for display_name.
-- trust_score / role / banned_until are guarded by user_profiles_guard.
create policy profile_read on user_profiles for select using (true);

create policy profile_update on user_profiles for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- moderation_events: moderators only; rows are written by definer functions.
create policy modevents_read on moderation_events for select using (
  current_user_role() in ('moderator', 'admin')
);
