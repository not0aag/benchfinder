set search_path = public, extensions;

-- ============ ODbL-ISOLATED ZONE ============
-- Mirror of OSM, refreshed by the import tool (service role). Never joined
-- into exports of bf_* data. See BENCHFINDER_ARCHITECTURE.md section 1.

create table osm_features (
  osm_id        bigint primary key,
  osm_type      text not null check (osm_type in ('node', 'way')),
  geom          geography(Point, 4326) not null,
  tags          jsonb not null,
  osm_version   int not null,
  osm_changeset bigint,
  imported_at   timestamptz not null default now()
);
create index idx_osm_features_geom on osm_features using gist (geom);
create index idx_osm_features_tags on osm_features using gin (tags jsonb_path_ops);

-- ============ BENCHFINDER ZONE ============

create type bench_origin       as enum ('osm', 'user', 'import');
create type bench_status       as enum ('pending', 'published', 'removed', 'merged');
create type verification_state as enum ('unconfirmed', 'community', 'confirmed', 'verified', 'disputed');
create type bench_material     as enum ('wood', 'metal', 'concrete', 'stone', 'plastic', 'composite', 'mixed', 'unknown');
create type bench_condition    as enum ('excellent', 'good', 'fair', 'poor', 'unusable');

create table bf_benches (
  id                 uuid primary key default gen_random_uuid(),
  geom               geography(Point, 4326) not null,
  origin             bench_origin not null,
  source_osm_id      bigint references osm_features (osm_id), -- ODbL provenance marker
  status             bench_status not null default 'pending',
  verification_state verification_state not null default 'unconfirmed',
  merged_into        uuid references bf_benches (id),

  -- physical attributes: null means "nobody has checked", never guess
  has_backrest   boolean,
  has_armrests   boolean,
  has_table      boolean,
  is_accessible  boolean,
  has_shade      boolean,
  is_lit         boolean,
  material       bench_material not null default 'unknown',
  condition      bench_condition,
  seats          smallint check (seats between 1 and 50),
  facing_degrees smallint check (facing_degrees between 0 and 359),

  -- derived nightly by a spatial job against osm_features, never user-entered
  nearby jsonb not null default '{}'::jsonb,

  -- denormalised aggregates, trigger-maintained, never computed on read
  photo_count    int not null default 0,
  rating_count   int not null default 0,
  scenic_avg     numeric(3, 2),
  comfort_avg    numeric(3, 2),
  favorite_count int not null default 0,
  visit_count    int not null default 0,
  confirm_count  int not null default 0,
  dispute_count  int not null default 0,

  min_zoom    smallint not null default 14, -- LOD thinning for tiles
  description text check (length(description) <= 500),
  created_by  uuid references auth.users (id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  search_tsv  tsvector generated always as (to_tsvector('english', coalesce(description, ''))) stored
);

create index idx_bench_geom      on bf_benches using gist (geom);
create index idx_bench_published on bf_benches using gist (geom) where status = 'published';
create index idx_bench_tiles     on bf_benches (min_zoom, status);
create index idx_bench_search    on bf_benches using gin (search_tsv);
create index idx_bench_creator   on bf_benches (created_by, created_at desc);
create index idx_bench_queue     on bf_benches (created_at) where status = 'pending';
create index idx_bench_source    on bf_benches (source_osm_id) where source_osm_id is not null;

-- Photos: metadata here, bytes in Storage
create table bench_photos (
  id           uuid primary key default gen_random_uuid(),
  bench_id     uuid not null references bf_benches (id) on delete cascade,
  storage_path text not null unique,
  phash        bit(64) not null,
  width        int not null,
  height       int not null,
  bytes        int not null,
  blur_score   real,
  captured_at  timestamptz,
  exif_geom    geography(Point, 4326), -- validated server-side, stripped from the stored derivative
  is_primary   boolean not null default false,
  moderation   text not null default 'pending',
  uploaded_by  uuid not null references auth.users (id),
  created_at   timestamptz not null default now()
);
create unique index idx_photo_primary on bench_photos (bench_id) where is_primary;
create index idx_photo_phash on bench_photos (phash);
create index idx_photo_bench on bench_photos (bench_id);

create table bench_ratings (
  bench_id   uuid not null references bf_benches (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  scenic     smallint check (scenic between 1 and 5),
  comfort    smallint check (comfort between 1 and 5),
  note       text check (length(note) <= 300),
  created_at timestamptz not null default now(),
  primary key (bench_id, user_id)
);

create table bench_confirmations (
  bench_id   uuid not null references bf_benches (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  present    boolean not null,
  at_geom    geography(Point, 4326) not null, -- proximity gate enforced at submit time
  created_at timestamptz not null default now(),
  primary key (bench_id, user_id)
);

create table bench_favorites (
  bench_id uuid not null references bf_benches (id) on delete cascade,
  user_id  uuid not null references auth.users (id) on delete cascade,
  primary key (user_id, bench_id) -- user-first: "my favourites" is the query
);

create table user_profiles (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  trust_score  smallint not null default 10 check (trust_score between 0 and 100),
  role         text not null default 'user' check (role in ('user', 'trusted', 'moderator', 'admin')),
  banned_until timestamptz,
  created_at   timestamptz not null default now()
);

create table moderation_events (
  id         bigserial primary key,
  bench_id   uuid references bf_benches (id),
  actor_id   uuid references auth.users (id),
  action     text not null,
  reason     text,
  payload    jsonb,
  created_at timestamptz not null default now()
);
create index idx_modevents_bench on moderation_events (bench_id, created_at desc);

-- ============ HOUSEKEEPING TRIGGERS ============

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger bf_benches_updated_at
  before update on bf_benches
  for each row execute function public.set_updated_at();

-- Every auth user gets a profile row. Trust starts at 10 (arch doc section 5).
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_profiles (user_id, display_name)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'display_name', ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'bencher-' || left(new.id::text, 8)
    )
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
