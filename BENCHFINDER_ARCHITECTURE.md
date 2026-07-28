# BenchFinder: Architecture Decision Record & Build Plan

**Status:** Pre-implementation. Read this fully before writing code.
**Owner:** Alen George
**Last updated:** 2026-07-27

---

## 0. Executive summary: what changes from the original brief

The original spec proposed Firebase/Firestore + Google Maps SDK + geohashing + admin-gated verification. That stack works for a single-city MVP and breaks in specific, predictable ways at the scale the mission statement describes. Seven decisions are revised:

| #   | Original                              | Revised                                                     | Reason                                                                                                                              |
| --- | ------------------------------------- | ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Build the bench database from scratch | Seed from OpenStreetMap, differentiate on metadata + photos | ~5M benches are already mapped globally. Starting at zero is the single biggest risk to the mission.                                |
| 2   | Cloud Firestore                       | Postgres + PostGIS (Supabase)                               | Geospatial queries, spatial dedupe, analytics, and per-read cost. Firestore cannot express the core query.                          |
| 3   | Geohash range queries                 | PostGIS GiST index + `ST_AsMVT` vector tiles                | Geohash needs 9 parallel queries + client-side filtering, cannot combine with attribute filters, and re-fetches on every pan.       |
| 4   | Google Maps SDK + marker clustering   | MapLibre Native + custom vector tile source                 | Google Maps SDK cannot host custom vector tile layers. Marker clustering caps out around 10k points. Also unlocks offline basemaps. |
| 5   | Admin-gated verification queue        | Optimistic publish + reputation + confirmation microtasks   | An admin-approval gate makes the founder the throughput ceiling. Fails at city #2.                                                  |
| 6   | Cloud AI image validation             | On-device gate first, cloud VLM only for ambiguous cases    | 95% of the decision is free on-device. Cloud-first costs scale linearly with submissions.                                           |
| 7   | Expo vs CLI (open question)           | Expo with prebuild / Continuous Native Generation           | Config plugins cover every native dep needed. EAS Update ships JS fixes without store review.                                       |

Everything else in the brief (TypeScript, React Query, Zustand, Vision Camera, Sentry, ESLint/Prettier/Husky, GitHub Actions) is kept.

---

## 1. The decision that reframes the project: OpenStreetMap

### The problem with "build the world's largest bench database"

It already exists. `amenity=bench` is a mature, widely-used OSM tag with several million node instances worldwide and a well-documented schema that already covers most of the requested metadata: `backrest`, `armrest`, `material`, `colour`, `seats`, `direction`, `covered`, `lit`, `access`. The OSM wiki also documents companion tags for the "nearby" attributes: `amenity=toilets`, `amenity=drinking_water`, `leisure=playground`, `amenity=parking`.

A from-scratch competitor to OSM loses. A product built _on top of_ OSM starts on day one with global coverage and competes on the axis OSM is weak at: **photos, condition, ratings, comfort, scenery, and freshness.**

### Revised positioning

> BenchFinder is a rich-metadata, photo-first layer over the world's public seating, seeded from OpenStreetMap and enriched by community contributions.

Day-one coverage in Oakville: whatever OSM already has (likely 200-800 benches in the Oakville/Bronte/Kerr Village/waterfront areas). Alen's personal verification work then becomes _enrichment and verification_, not cold-start data entry. That is a 10x better use of the same hours.

### License handling (non-negotiable, get this right at schema time)

OSM data is ODbL. ODbL is share-alike on the **database**, not on your app. The safe architecture is a hard separation:

```
osm_features        <- ODbL. Mirror of OSM. Never mixed into bf tables.
bf_benches          <- BenchFinder original. Owned outright.
bench_osm_links     <- Join table. osm_id <-> bench_id. Deliberately thin.
```

**Rules encoded in the schema:**

- `osm_features` is refreshed from Geofabrik extracts. Read-only from the app's perspective.
- `bf_benches` rows created _from_ an OSM feature store `origin='osm'` and a `source_osm_id`. Coordinates copied from OSM are ODbL-derived; treat any export containing them as a derived database and publish it under ODbL.
- User-contributed rows (`origin='user'`) with independently-captured GPS are clean. Photos, ratings, and comments are your own content regardless of origin, under your own ToS.
- Publish a public ODbL-licensed export of the OSM-derived subset. This is the cheapest possible compliance posture and it buys community goodwill.
- Attribution string "© OpenStreetMap contributors" ships in the app's About screen and on any map view using OSM-derived tiles.

**Action item:** this is a real legal question, not just an engineering one. Before any public launch, have an IP lawyer review the produced-work vs derivative-database line for your specific export plan. Nothing below substitutes for that.

### Give back

Contribute verified new benches back to OSM via the OSM API with a dedicated changeset comment and `created_by=BenchFinder`. Costs almost nothing, prevents the OSM community from treating you as a data leech, and is a genuine moat: you become the mobile capture tool the OSM bench-mappers use.

**Precedent to study:** OpenBenches (openbenches.org) already does memorial benches with CC-licensed photos and has explicit permission to reuse into OSM. Do not duplicate it. Consider linking to it.

---

## 2. Database: Postgres + PostGIS, not Firestore

### Why Firestore fails this specific workload

The core query of the entire app is:

> Give me every bench inside this map viewport, at this zoom, optionally filtered by `has_backrest AND is_accessible AND condition >= good`, sorted by distance.

Firestore cannot express it. Concretely:

1. **Geohash range queries are approximate.** The standard GeoFirestore approach computes up to 9 neighbouring geohash prefixes, issues 9 parallel range queries, then filters false positives client-side. That is 9 round trips and over-fetching by design.
2. **Range + inequality conflict.** Firestore permits range/inequality filters on one field per query. A geohash range query has already consumed it. Attribute filtering must therefore happen client-side, after paying for the reads.
3. **Per-document read billing.** Every pan and zoom re-reads documents. A user browsing downtown Toronto for 90 seconds can trigger tens of thousands of document reads. There is no viewport-level cache primitive.
4. **No spatial joins.** Duplicate detection ("is there an existing bench within 15 m of this submission?") is a spatial predicate. Firestore requires reading candidates out and comparing in application code, in a Cloud Function, per submission.
5. **No aggregation.** Heatmaps, coverage stats, per-region contributor leaderboards, and the admin analytics in the brief all require GROUP BY. Firestore's aggregation support is limited to count/sum/avg on filtered sets and does not cover spatial binning.

### Why PostGIS

- `GEOGRAPHY(POINT, 4326)` column with a GiST index. `ST_DWithin`, `ST_Distance`, `&&` bbox operators are exact, fast, and compose freely with any WHERE clause.
- `ST_AsMVT` generates Mapbox Vector Tiles directly in the database. This is the scaling unlock (section 3).
- `ST_ClusterDBSCAN` and `ST_SnapToGrid` for server-side clustering and duplicate detection.
- Row Level Security enforces authorization inside the database, so it holds regardless of which client, edge function, or admin dashboard reaches it.
- `pg_cron` for scheduled jobs (OSM refresh, materialized view rebuilds, reputation recalculation).
- `pgvector` available later if photo-embedding dedupe becomes worthwhile.
- Exit path is `pg_dump`. No lock-in.

### Why Supabase specifically (over raw RDS / Neon / self-hosted)

Supabase bundles Postgres+PostGIS, Auth, Storage, Edge Functions, and Realtime with a managed control plane. For a solo founder that is the correct trade. Alternatives considered:

| Option                                               | Verdict                                                                                                                                    |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| **Supabase**                                         | Chosen. PostGIS enabled by extension. RLS-native. Storage with image transforms. Reasonable free tier.                                     |
| Neon + separate auth (Clerk) + separate storage (R2) | More assembly, more moving parts, slightly better cold-start economics. Reconsider at Series A scale.                                      |
| AWS RDS + Cognito + S3                               | Most control, most ops burden. Wrong for a solo project. Note: this is closest to what you already know from TD, so it is a real fallback. |
| Firebase                                             | Rejected above.                                                                                                                            |

### Migration insurance

Do not write Supabase-specific SQL in the app layer. All data access goes through a repository layer (`packages/data-access`) exposing domain functions (`findBenchesInViewport`, `submitBench`). Swapping the backing store later touches one package.

---

## 3. Map rendering: vector tiles, not markers

### The scaling wall

`react-native-maps` with `supercluster` handles a few thousand markers acceptably. It does not handle a million. Every marker is a native view; clustering runs on the JS thread; the whole point set must be resident in memory.

### The correct architecture

**Serve bench data as Mapbox Vector Tiles generated by PostGIS.**

```sql
-- Edge Function: GET /tiles/benches/{z}/{x}/{y}.mvt
WITH bounds AS (SELECT ST_TileEnvelope($1, $2, $3) AS geom),
mvtgeom AS (
  SELECT
    ST_AsMVTGeom(b.geom::geometry, bounds.geom) AS geom,
    b.id, b.verification_state, b.has_backrest, b.is_accessible,
    b.condition_score, b.photo_count
  FROM bf_benches b, bounds
  WHERE b.geom::geometry && bounds.geom
    AND b.status = 'published'
    AND ($4::int IS NULL OR b.min_zoom <= $4)   -- LOD thinning
)
SELECT ST_AsMVT(mvtgeom.*, 'benches') FROM mvtgeom;
```

**Why this wins:**

- One HTTP request per tile, not per bench.
- Tiles are immutable-ish and cache at the CDN edge. Second user to view downtown Oakville pays zero database cost.
- MapLibre renders tiles on the GPU, natively, off the JS thread. A million points is a non-event.
- Clustering, filtering, and styling happen in the map style spec, not in React.
- Level-of-detail: precompute a `min_zoom` column so zoom 10 serves a thinned sample and zoom 17 serves everything.

**Cache strategy:** `Cache-Control: public, max-age=300, stale-while-revalidate=86400` on tile responses, fronted by Cloudflare. Bump a tile-version query param on bulk data changes. Individual bench edits do not need instant tile invalidation; the detail sheet fetches live data by ID.

### Why MapLibre Native over Google Maps SDK

|                                  | Google Maps SDK (react-native-maps) | MapLibre Native RN                      |
| -------------------------------- | ----------------------------------- | --------------------------------------- |
| Custom vector tile source        | No. Raster overlays only.           | Yes. First-class.                       |
| Offline basemap packs            | No                                  | Yes                                     |
| Style control (dark mode, brand) | Limited preset styles               | Full style spec                         |
| Cost                             | Mobile map loads free, unlimited    | Free, self-hosted or Protomaps/MapTiler |
| Familiarity                      | High (you used it on GOSpot)        | Learning curve, ~1 day                  |

Google Maps mobile SDK map loads are free with no usage limits, so cost is not the argument here. The argument is the custom vector tile layer, which Google's mobile SDK does not support. That capability is load-bearing for this app.

**Basemap source:** Protomaps PMTiles (a single static file on R2, no tile server) or MapTiler free tier. Both OSM-derived, both attribution-required, both work offline. Protomaps is the cheaper long-run answer: one file, served from object storage, no per-request billing.

**Avoid Google Places API entirely.** It is the expensive SKU ($5-17 per 1,000 requests depending on tier) and the app has no need for it. Reverse geocoding for "bench near Lakeshore Rd W" is served by Nominatim (self-hosted or the public instance under its usage policy) or Photon.

---

## 4. Expo with prebuild, not React Native CLI

**Decision: Expo, CNG/prebuild workflow, EAS Build, dev clients. Not Expo Go.**

The historical objection to Expo (cannot use custom native modules) has been dead since development builds and config plugins matured. Every native dependency this project needs ships a config plugin:

- `react-native-vision-camera` — official plugin
- `@maplibre/maplibre-react-native` — official plugin
- `react-native-fast-tflite` or `react-native-executorch` — plugin available
- `@sentry/react-native` — official plugin
- `expo-location`, `expo-image`, `expo-image-manipulator`, `expo-file-system` — first-party

**What Expo buys that materially matters here:**

- **EAS Update.** Ship a JS-only bug fix in minutes, not a 1-3 day store review. For a solo founder this is the single highest-leverage tool in the stack.
- **EAS Build.** iOS builds without owning a Mac. Given the Sheridan lab Mac constraints you have hit before, this is not hypothetical.
- **expo-router.** File-based routing, typed routes, deep linking (`benchfinder://bench/{id}`) mostly for free. Replaces hand-configured React Navigation.
- **Prebuild.** `android/` and `ios/` are generated artifacts, gitignored. Upgrades stop being merge-conflict archaeology.

**Cost:** an escape hatch is needed for any native lib without a plugin. Write one (`expo-module-scripts` makes this straightforward) or eject the specific directory. Both are cheap. This risk is small enough to accept.

**Not Expo Go.** Expo Go cannot load custom native code. Development builds only, from day one.

---

## 5. Verification: reputation, not an approval queue

### The problem with the proposed flow

`Submission → auto-checks → Pending Review → Admin approves → Verified` has a hard throughput ceiling equal to admin hours. At 50 submissions/day it consumes an evening. At 500/day it is a full-time job. The app cannot expand past Oakville without either hiring moderators or blocking on the founder. Every successful crowdsourced geo dataset (OSM, Waze, Wikipedia) solved this the same way: **publish optimistically, moderate reactively, and let trust accrue.**

### Revised model

```
Submission
  ↓
Synchronous gates (< 2s, mostly on-device, all free)
  ├─ GPS plausibility: submitted point within 150 m of device location fix
  ├─ EXIF timestamp within 24 h; EXIF GPS within 150 m of submitted point
  ├─ Blur check: variance of Laplacian above threshold
  ├─ On-device object detection: "bench" or "seating" class present
  └─ Spatial dedupe: ST_DWithin 15 m against existing benches
  ↓
Trust routing
  ├─ trust >= 60 → published immediately, state = 'community'
  ├─ trust 20-59 → published, state = 'unconfirmed', surfaced for confirmation
  └─ trust < 20  → held, state = 'pending', enters review queue
  ↓
Passive verification (this is the scalable part)
  ├─ Confirmation microtask: "Is this bench still here?" shown to nearby users
  ├─ 2 independent confirmations from distinct users → state = 'confirmed'
  ├─ Owner/admin physical visit → state = 'verified'
  └─ 2 independent "not there" reports → state = 'disputed', enters queue
  ↓
Reactive moderation
  └─ Flags, disputes, and low-trust submissions only
```

### Trust score

Start every account at 10. Simple, auditable, no ML:

| Event                                                  | Delta        |
| ------------------------------------------------------ | ------------ |
| Submission reaches `confirmed`                         | +5           |
| Submission reaches `verified`                          | +10          |
| Submission rejected as spam/duplicate                  | -15          |
| Accurate confirmation (agrees with eventual consensus) | +1           |
| Inaccurate confirmation                                | -3           |
| Account age > 30 days, > 3 confirmed benches           | +10 one-time |
| Manual admin grant (trusted contributor)               | +50          |

Cap at 100. Recompute nightly via `pg_cron` into a materialized `user_trust` table. Never compute on the read path.

**Anti-gaming:** confirmations only count from users who were physically within 50 m (verified by a location fix at confirmation time), max one confirmation per user per bench, rate-limit confirmations to 20/day/user, require account age > 24 h before any confirmation counts.

### Marker colours by state

`pending` (grey, admin-only visibility) · `unconfirmed` (amber) · `community` (blue) · `confirmed` (green) · `verified` (green + check) · `disputed` (red outline) · `removed` (hidden, soft-deleted)

---

## 6. AI features: on-device first, cloud only for the hard 5%

Ranked by value-per-dollar. Build in this order.

| Feature                         | Approach                                                                                                                                                                                                          | Cost                     | Priority |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------ | -------- |
| **Blur detection**              | Variance of Laplacian, pure math, on-device                                                                                                                                                                       | $0                       | P0       |
| **Spatial dedupe**              | `ST_DWithin` 15 m + attribute similarity                                                                                                                                                                          | ~$0                      | P0       |
| **Is it a bench?**              | On-device SSDLite-MobileNetV3 or MobileNetV2 classifier via `react-native-executorch` (VisionCamera v5 `runOnFrame`) or `react-native-fast-tflite` (VisionCamera v4). Live feedback in the capture viewfinder.    | $0                       | P0       |
| **Photo dedupe**                | Perceptual hash (pHash) + Hamming distance, computed on-device, compared server-side. Catches the same photo re-uploaded at a different pin.                                                                      | ~$0                      | P1       |
| **Spam / fraud**                | Rules first: submission velocity, GPS teleportation (impossible speed between consecutive submissions), duplicate device fingerprint, text profanity filter. No ML needed for v1.                                 | $0                       | P1       |
| **Metadata suggestion**         | Cloud VLM (Gemini Flash / Claude Haiku), batched, called once per submission only after it passes the on-device gate. Suggests material, backrest, armrests, condition, shade. User confirms, never auto-applies. | ~$0.001-0.005/submission | P2       |
| **Ambiguous-case adjudication** | Same VLM, invoked only when the on-device classifier confidence lands in 0.35-0.65. Expected to be < 10% of submissions.                                                                                          | Marginal                 | P2       |
| **Face / plate blurring**       | On-device face detection (ML Kit / Vision) + blur before upload. This is a privacy requirement in several jurisdictions, not a nice-to-have.                                                                      | $0                       | P1       |

**Explicitly rejected:** training a custom bench detector (no dataset, no need — COCO already has `bench` as a class), embedding-based duplicate detection at v1 (pgvector is there when spatial+pHash proves insufficient, not before), LLM-based moderation of every submission (cost scales with abuse, which is exactly backwards).

---

## 7. Schema

```sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============ ODbL-ISOLATED ZONE ============
-- Refreshed from Geofabrik extracts. Never joined into exports of bf_* data.

CREATE TABLE osm_features (
  osm_id          bigint PRIMARY KEY,
  osm_type        text NOT NULL CHECK (osm_type IN ('node','way')),
  geom            geography(Point, 4326) NOT NULL,
  tags            jsonb NOT NULL,
  osm_version     int NOT NULL,
  osm_changeset   bigint,
  imported_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_osm_features_geom ON osm_features USING GIST (geom);
CREATE INDEX idx_osm_features_tags ON osm_features USING GIN (tags jsonb_path_ops);

-- ============ BENCHFINDER ZONE ============

CREATE TYPE bench_origin        AS ENUM ('osm','user','import');
CREATE TYPE bench_status        AS ENUM ('pending','published','removed','merged');
CREATE TYPE verification_state  AS ENUM ('unconfirmed','community','confirmed','verified','disputed');
CREATE TYPE bench_material      AS ENUM ('wood','metal','concrete','stone','plastic','composite','mixed','unknown');
CREATE TYPE bench_condition     AS ENUM ('excellent','good','fair','poor','unusable');

CREATE TABLE bf_benches (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  geom                geography(Point, 4326) NOT NULL,
  origin              bench_origin NOT NULL,
  source_osm_id       bigint REFERENCES osm_features(osm_id),  -- ODbL provenance marker
  status              bench_status NOT NULL DEFAULT 'pending',
  verification_state  verification_state NOT NULL DEFAULT 'unconfirmed',
  merged_into         uuid REFERENCES bf_benches(id),

  -- physical attributes (nullable = unknown, never guess)
  has_backrest        boolean,
  has_armrests        boolean,
  has_table           boolean,
  is_accessible       boolean,
  has_shade           boolean,
  is_lit              boolean,
  material            bench_material NOT NULL DEFAULT 'unknown',
  condition           bench_condition,
  seats               smallint CHECK (seats BETWEEN 1 AND 50),
  facing_degrees      smallint CHECK (facing_degrees BETWEEN 0 AND 359),

  -- nearby amenities: derived nightly by spatial job, not user-entered
  nearby              jsonb NOT NULL DEFAULT '{}'::jsonb,
    -- { washroom_m: 45, water_m: 120, parking_m: 200, playground_m: null }

  -- denormalised aggregates, maintained by trigger. NEVER computed on read.
  photo_count         int NOT NULL DEFAULT 0,
  rating_count        int NOT NULL DEFAULT 0,
  scenic_avg          numeric(3,2),
  comfort_avg         numeric(3,2),
  favorite_count      int NOT NULL DEFAULT 0,
  visit_count         int NOT NULL DEFAULT 0,
  confirm_count       int NOT NULL DEFAULT 0,
  dispute_count       int NOT NULL DEFAULT 0,

  min_zoom            smallint NOT NULL DEFAULT 14,  -- LOD thinning for tiles
  description         text CHECK (length(description) <= 500),
  created_by          uuid REFERENCES auth.users(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  search_tsv          tsvector GENERATED ALWAYS AS
                        (to_tsvector('english', coalesce(description,''))) STORED
);

CREATE INDEX idx_bench_geom      ON bf_benches USING GIST (geom);
CREATE INDEX idx_bench_published ON bf_benches USING GIST (geom)
  WHERE status = 'published';                       -- partial: the hot path
CREATE INDEX idx_bench_tiles     ON bf_benches (min_zoom, status);
CREATE INDEX idx_bench_search    ON bf_benches USING GIN (search_tsv);
CREATE INDEX idx_bench_creator   ON bf_benches (created_by, created_at DESC);
CREATE INDEX idx_bench_queue     ON bf_benches (created_at)
  WHERE status = 'pending';                         -- moderation queue

-- Photos: metadata in Postgres, bytes in Storage
CREATE TABLE bench_photos (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bench_id      uuid NOT NULL REFERENCES bf_benches(id) ON DELETE CASCADE,
  storage_path  text NOT NULL UNIQUE,
  phash         bit(64) NOT NULL,          -- perceptual hash for dedupe
  width         int NOT NULL,
  height        int NOT NULL,
  bytes         int NOT NULL,
  blur_score    real,
  captured_at   timestamptz,
  exif_geom     geography(Point, 4326),    -- validated then discarded from EXIF
  is_primary    boolean NOT NULL DEFAULT false,
  moderation    text NOT NULL DEFAULT 'pending',
  uploaded_by   uuid NOT NULL REFERENCES auth.users(id),
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX idx_photo_primary ON bench_photos (bench_id) WHERE is_primary;
CREATE INDEX idx_photo_phash ON bench_photos (phash);

CREATE TABLE bench_ratings (
  bench_id   uuid NOT NULL REFERENCES bf_benches(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scenic     smallint CHECK (scenic BETWEEN 1 AND 5),
  comfort    smallint CHECK (comfort BETWEEN 1 AND 5),
  note       text CHECK (length(note) <= 300),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (bench_id, user_id)          -- one rating per user per bench
);

CREATE TABLE bench_confirmations (
  bench_id    uuid NOT NULL REFERENCES bf_benches(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  present     boolean NOT NULL,
  at_geom     geography(Point, 4326) NOT NULL,   -- proximity gate: must be <50m
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (bench_id, user_id)
);

CREATE TABLE bench_favorites (
  bench_id uuid NOT NULL REFERENCES bf_benches(id) ON DELETE CASCADE,
  user_id  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, bench_id)          -- user-first: "my favourites" is the query
);

CREATE TABLE user_profiles (
  user_id      uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  trust_score  smallint NOT NULL DEFAULT 10 CHECK (trust_score BETWEEN 0 AND 100),
  role         text NOT NULL DEFAULT 'user'
                 CHECK (role IN ('user','trusted','moderator','admin')),
  banned_until timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE moderation_events (
  id          bigserial PRIMARY KEY,
  bench_id    uuid REFERENCES bf_benches(id),
  actor_id    uuid REFERENCES auth.users(id),
  action      text NOT NULL,
  reason      text,
  payload     jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_modevents_bench ON moderation_events (bench_id, created_at DESC);
```

**Design notes:**

- `geography` not `geometry` for storage: metres-accurate `ST_DWithin` without projection juggling. Cast to `geometry` inside tile generation where the planar operators are faster.
- Nullable booleans everywhere physical. `NULL` means "nobody has checked," which is a different and more useful fact than `false`.
- `nearby` is a derived jsonb blob rebuilt nightly by a spatial job against `osm_features`. Never computed at read time, never user-entered.
- Aggregates (`photo_count`, `scenic_avg`, ...) are trigger-maintained. Tile generation and list rendering must never trigger a COUNT.
- Partial indexes on the hot predicates. `WHERE status='published'` covers essentially every user-facing query and keeps the index small.

### RLS policies (the security model)

```sql
ALTER TABLE bf_benches ENABLE ROW LEVEL SECURITY;

-- read: published benches are public; your own pending submissions are visible to you
CREATE POLICY bench_read ON bf_benches FOR SELECT USING (
  status = 'published'
  OR created_by = auth.uid()
  OR (SELECT role FROM user_profiles WHERE user_id = auth.uid())
       IN ('moderator','admin')
);

-- insert: authenticated, not banned, and the client cannot self-assign status
CREATE POLICY bench_insert ON bf_benches FOR INSERT WITH CHECK (
  auth.uid() IS NOT NULL
  AND created_by = auth.uid()
  AND status = 'pending'
  AND verification_state = 'unconfirmed'
  AND NOT EXISTS (
    SELECT 1 FROM user_profiles
    WHERE user_id = auth.uid() AND banned_until > now()
  )
);

-- update: attribute edits by trusted+; status transitions are function-only
CREATE POLICY bench_update ON bf_benches FOR UPDATE USING (
  (SELECT role FROM user_profiles WHERE user_id = auth.uid())
    IN ('trusted','moderator','admin')
);

-- no DELETE policy. Deletion is soft (status='removed') via SECURITY DEFINER fn.
```

**Key principle: state transitions are never client-writable.** Promotion from `pending` to `published`, or `community` to `confirmed`, happens only inside `SECURITY DEFINER` functions that the client calls as RPC. The client can request; it cannot assert. This is the single most important security decision in the schema and it is the thing Firestore rules make hard to guarantee.

---

## 8. Repo structure

Monorepo, pnpm workspaces + Turborepo.

```
benchfinder/
├── apps/
│   ├── mobile/                    # Expo app
│   │   ├── app/                   # expo-router routes
│   │   │   ├── (tabs)/            #   map, nearby, contribute, profile
│   │   │   ├── bench/[id].tsx
│   │   │   └── _layout.tsx
│   │   ├── src/
│   │   │   ├── features/          # vertical slices, not layer folders
│   │   │   │   ├── map/           #   components + hooks + state, colocated
│   │   │   │   ├── capture/
│   │   │   │   ├── bench-detail/
│   │   │   │   └── profile/
│   │   │   ├── components/        # shared, presentational only
│   │   │   ├── lib/               # native adapters: camera, location, ml
│   │   │   └── theme/             # tokens, dark mode, typography
│   │   ├── app.config.ts          # CNG config + plugins
│   │   └── eas.json
│   └── admin/                     # React + Vite + TanStack Router
│       └── src/features/          # queue, dedupe-compare, analytics, users
├── packages/
│   ├── domain/                    # pure TS: entities, value objects, invariants.
│   │                              # ZERO dependencies. Fully unit-testable.
│   ├── data-access/               # repository interfaces + Supabase impl.
│   │                              # The ONLY package that imports supabase-js.
│   ├── api-contracts/             # zod schemas, shared request/response types
│   ├── ui/                        # cross-platform primitives (mobile + admin)
│   └── config/                    # eslint, tsconfig, prettier presets
├── supabase/
│   ├── migrations/                # versioned SQL, forward-only
│   ├── functions/                 # Deno edge functions
│   │   ├── tiles/                 #   ST_AsMVT endpoint
│   │   ├── submit-bench/          #   validation gates + trust routing
│   │   └── osm-sync/              #   Geofabrik extract ingestion
│   └── tests/                     # pgTAP: RLS policy tests
├── tools/
│   └── osm-import/                # osmium/ogr2ogr pipeline scripts
└── turbo.json
```

**Why vertical feature slices instead of `components/ hooks/ services/`:** layer-first folders scale badly. Every feature change touches five directories. Feature-first means a slice is deletable in one command, and a new contributor reads one folder to understand one thing. Cross-cutting shared code lives in `packages/`, where the boundary is enforced by the build system rather than by convention.

**Dependency rule (enforced by `eslint-plugin-boundaries`):**
`domain` ← `data-access` ← `features` ← `app`. Never the reverse. `domain` importing React or Supabase is a build failure.

---

## 9. Testing

| Layer        | Tool                                            | What it covers                                                                                          |
| ------------ | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Domain logic | Vitest                                          | Trust scoring, dedupe scoring, state machine transitions. Pure functions, fast, high coverage.          |
| Components   | Jest + React Native Testing Library             | Rendering, accessibility roles, user interaction.                                                       |
| Data access  | Vitest + testcontainers (real Postgres+PostGIS) | Spatial queries against real PostGIS. Never mock the database for spatial code.                         |
| RLS policies | **pgTAP**                                       | Every policy gets a test asserting both allow and deny. Non-negotiable: RLS bugs are silent data leaks. |
| Network      | MSW                                             | Deterministic API responses in component tests.                                                         |
| E2E mobile   | **Maestro**                                     | YAML flows, works with Expo dev builds, far less brittle than Detox.                                    |
| E2E admin    | Playwright                                      | Moderation queue, merge flow, auth.                                                                     |
| Visual       | Storybook + Chromatic (optional)                | Dark mode + tablet layout regressions.                                                                  |

**Coverage targets:** `packages/domain` 90%+. `data-access` 80%+. UI components 60%+. E2E covers the five critical paths only (sign in, view map, view detail, submit bench, moderate submission). Do not chase coverage in UI code; chase it in the logic that can silently corrupt data.

---

## 10. Security decisions

| Decision                                                                                                    | Rationale                                                                                                                                               |
| ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| RLS on every table, no exceptions                                                                           | Authorization at the data layer holds regardless of which client reaches it. An admin dashboard bug cannot become a data breach.                        |
| State transitions via `SECURITY DEFINER` RPC only                                                           | Client can request, cannot assert. Prevents self-promotion to `verified`.                                                                               |
| Signed upload URLs, server-issued, single-use, 5 min TTL                                                    | Client never holds broad Storage write credentials.                                                                                                     |
| Server-side MIME sniff + re-encode on upload                                                                | Rejects polyglot files and strips embedded payloads. Never trust the client-declared content type.                                                      |
| EXIF GPS read server-side, then stripped from the stored derivative                                         | Needed for validation, dangerous to serve. Users photograph benches near their homes.                                                                   |
| Face/plate blur before public display                                                                       | Privacy obligation in several jurisdictions and basic decency.                                                                                          |
| Rate limits at the edge function: 10 submissions/hour, 20 confirmations/day, 100 photo uploads/day per user | Cheapest possible abuse containment. Enforce server-side; client-side limits are advisory only.                                                         |
| Zod validation at every trust boundary                                                                      | Same schemas shared between client and edge function via `api-contracts`. One definition, no drift.                                                     |
| Anonymous auth allowed for read, required-account for write                                                 | Lowers the barrier to browsing; keeps accountability on contribution.                                                                                   |
| Coordinates fuzzed to 5 decimal places (~1 m) in public tiles                                               | Beyond 1 m is false precision and mild fingerprinting risk.                                                                                             |
| Sentry with `beforeSend` PII scrubber                                                                       | Never ship user coordinates or emails to error tracking.                                                                                                |
| No secrets in `app.config.ts`                                                                               | EAS secrets for build-time; edge functions hold anything genuinely sensitive. The Supabase anon key is public by design; RLS is what protects the data. |

---

## 11. Cost model

Assume 10,000 MAU, 50,000 monthly map sessions, 2,000 monthly submissions.

| Line item               | Approach                                 | Est. monthly            |
| ----------------------- | ---------------------------------------- | ----------------------- |
| Basemap tiles           | Protomaps PMTiles on Cloudflare R2       | ~$1 (egress free on R2) |
| Bench vector tiles      | Edge function + CDN cache, ~90% hit rate | ~$5                     |
| Postgres                | Supabase Pro                             | $25                     |
| Storage (photos)        | ~2,000 photos/mo × 300 KB × derivatives  | ~$5                     |
| VLM metadata suggestion | 2,000 × ~$0.003                          | ~$6                     |
| Sentry                  | Free tier likely sufficient              | $0                      |
| EAS Build/Update        | Production plan                          | $19-99                  |
| **Total**               |                                          | **~$60-140/mo**         |

The same workload on the original Firestore + Google Maps design: map document reads alone at 50,000 sessions × conservative 300 doc reads/session = 15M reads/month, plus Places API calls if used for search. Comfortably 10-30x the above. The vector tile decision is the single largest cost lever in the whole architecture.

---

## 12. Build phases

Each phase has a demoable exit criterion. Do not start phase N+1 until phase N's criterion is met.

### Phase 0: Foundation (1 week)

Monorepo scaffold, Turborepo, tsconfig strict, ESLint + boundaries plugin, Prettier, Husky + lint-staged, commitlint, GitHub Actions (typecheck, lint, test, build). Expo app with dev client building on EAS for both platforms.
**Exit:** `pnpm build` and `pnpm test` green in CI. A dev build installs on a physical Android device and an iOS simulator.

### Phase 1: Data foundation + OSM ingestion (1 week)

Supabase project, PostGIS enabled, full schema migration, RLS policies, pgTAP tests for every policy. `osm-import` pipeline: load `amenity=bench` into `osm_features`, promote into `bf_benches` with `origin='osm'`.
**Amendment (2026-07-28):** v1 ingestion queries the Overpass API per region (bbox), same `pnpm osm:import <region>` interface. Region-scale data volumes (~1-2k benches) are well within Overpass usage policy and need no binary tooling. Switch the fetch backend to Geofabrik extracts + osmium when scaling past a handful of regions; the load/promote SQL is backend-agnostic.
**Exit:** Every OSM bench in Halton Region queryable. `SELECT count(*) FROM bf_benches WHERE origin='osm'` returns a real number. All pgTAP tests pass.

### Phase 2: Tile pipeline (3-4 days)

`ST_AsMVT` edge function, LOD `min_zoom` computation, CDN cache headers, tile versioning.
**Exit:** `curl /tiles/benches/14/4589/5975.mvt` returns valid MVT. Verified in a MapLibre web debug page before any mobile code is written.

### Phase 3: Map screen (1.5 weeks)

MapLibre Native, Protomaps basemap, bench tile layer, style-spec clustering, marker colours by verification state, location permission + follow-me, dark mode, viewport-driven detail fetch, offline basemap pack for Halton.
**Exit:** Smooth 60 fps pan/zoom over the full Ontario dataset on a mid-range Android device. Works in airplane mode with the cached pack.

### Phase 4: Bench detail (1 week)

Detail sheet, photo carousel with `expo-image` caching, all metadata, ratings display, favourite/visit actions, share deep link, full accessibility pass (screen reader labels, dynamic type, 4.5:1 contrast), tablet layout.
**Exit:** VoiceOver and TalkBack can complete the full read flow. Passes on a 10" tablet.

### Phase 5: Auth + profile (4 days)

Supabase Auth (Apple, Google, email OTP), anonymous read, profile screen, my-contributions list, trust score display.
**Exit:** Sign in on both platforms, RLS demonstrably blocks cross-user writes.

### Phase 6: Capture flow (2 weeks — the hardest phase)

Vision Camera, on-device bench classifier with live viewfinder feedback, blur check, GPS capture + manual pin adjust, image compression pipeline, pHash, EXIF handling, offline submission queue with background sync, `submit-bench` edge function with all validation gates and trust routing.
**Exit:** Submit a bench in airplane mode; it syncs on reconnect. A photo of a wall is rejected before upload with a clear message.

### Phase 7: Community verification (1 week)

Confirmation microtasks with proximity gate, dispute flow, ratings submission, nightly trust recomputation job.
**Exit:** A second account can confirm a bench and drive it to `confirmed`.

### Phase 8: Admin dashboard (1.5 weeks)

React + Vite, moderation queue, side-by-side duplicate comparison with a merge action, bench editor, user management, analytics with PostGIS heatmap binning, full-text search.
**Exit:** Full moderation loop performed end to end on real submissions.

### Phase 9: Production hardening (1 week)

Sentry with PII scrubbing, performance tracing, rate limits verified under load, backup and restore drill, i18n scaffolding (`i18next`, en/fr — French matters for Canada), store listings, privacy policy, OSM attribution, ODbL export endpoint.
**Exit:** Restore drill completed successfully from a backup. Store submissions accepted.

---

## 13. Deferred, deliberately

Not in v1. Listed so they are not accidentally built.

- Social graph, following, comments
- Routing/directions ("walk me to this bench")
- Gamification beyond trust score
- Web app for consumers (admin dashboard only)
- Real-time presence
- pgvector photo embeddings
- ML-based spam classification
- Bench "reservations" or occupancy
- Monetization of any kind

---

## 14. Open questions to resolve before Phase 1

1. **Legal:** ODbL produced-work boundary for the planned export. Needs an actual IP lawyer, not a forum post.
2. **Naming:** "BenchFinder" is generic and likely contested. Check CIPO and USPTO before spending on branding.
3. **OSM community:** post the plan to the OSM Canada forum before importing. Import-first-ask-later is the fastest way to get a hostile community.
4. **Photo licensing:** what license do users grant? Recommend CC BY-SA for photos to stay compatible with contributing back to OSM. Encode it in the ToS at signup, not retroactively.
5. **Region 1 scope:** Halton Region or all of the GTA? Affects OSM extract size and Phase 1 timeline.
