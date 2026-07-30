# BenchFinder

Find a good place to sit.

BenchFinder is a mobile app that maps public benches: where they are, what shape they're in, whether they have a backrest, shade, or a view. Seeded from OpenStreetMap, kept alive by people who actually sit on them.

![Expo](https://img.shields.io/badge/Expo-SDK%2057-000020?logo=expo&logoColor=white)
![TypeScript](https://img.shields.io/badge/TypeScript-strict-3178C6?logo=typescript&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-Postgres%20%2B%20PostGIS-3FCF8E?logo=supabase&logoColor=white)
![MapLibre](https://img.shields.io/badge/MapLibre-vector%20tiles-396CB2?logo=maplibre&logoColor=white)

## How it works

- **The map is tiles, not markers.** Bench data is served as MapLibre vector tiles straight out of PostGIS. The client never fetches bench collections as rows, so the map stays fast whether it shows one town or the whole planet. Row queries exist only for the detail sheet, nearby list, and admin dashboard.
- **OSM data and community data never mix.** OpenStreetMap features (ODbL) live in `osm_features`; community contributions live in `bf_benches`. Provenance is tracked per row, so licensing stays clean as the dataset grows.
- **Trust, not moderation queues.** Contributions move through verification states (`unverified`, `community_verified`, `flagged`) driven by contributor reputation. State transitions happen only inside `SECURITY DEFINER` Postgres functions; the client cannot write them, and every RLS policy has a pgTAP test for both its allow and deny case.
- **Unknown is not false.** Physical attributes (backrest, armrests, material) are nullable. A bench nobody has inspected is different from a bench without a backrest.

The full reasoning behind every one of these calls is in [`BENCHFINDER_ARCHITECTURE.md`](BENCHFINDER_ARCHITECTURE.md).

## Repo layout

```
apps/
  mobile/            Expo app (expo-router, MapLibre Native, React Query)
packages/
  domain/            Pure domain logic, zero runtime dependencies
  api-contracts/     Zod schemas shared across every trust boundary
  data-access/       Supabase client + repositories
  config/            Shared tsconfig / eslint / prettier
supabase/
  migrations/        Forward-only SQL: schema, RLS, transitions, tiles
  tests/             pgTAP tests for RLS policies
tools/
  osm-import/        Overpass ingestion for a region's benches
  tile-debug/        Throwaway page for inspecting tile output
```

## Getting started

Prereqs: Node 22+, pnpm, Docker (for local Supabase), Supabase CLI.

```bash
pnpm install
supabase start           # local Postgres + PostGIS + auth
supabase db reset        # apply migrations
pnpm osm:import oakville # seed benches from OpenStreetMap
pnpm dev:mobile          # Expo dev server
```

Other useful commands:

```bash
pnpm test        # unit tests (vitest)
pnpm test:db     # pgTAP RLS tests against real Postgres
pnpm typecheck
pnpm lint
```

Spatial logic is never mocked in tests. If a query touches PostGIS, the test runs against real Postgres.

## Status

Built in phases, each with an exit criterion. Done so far:

| Phase | What                                                                     |
| ----- | ------------------------------------------------------------------------ |
| 0     | Monorepo, tooling, CI hooks, EAS project                                 |
| 1     | Schema, RLS, state transition functions, OSM ingestion (Oakville seeded) |
| 2     | Vector tile pipeline out of PostGIS                                      |
| 3     | Map screen: bench tile layer, detail card, follow-me                     |

Next up: bench detail sheet, auth and profiles, the capture flow, community verification, admin dashboard.

## Data licensing

Bench data derived from OpenStreetMap is © OpenStreetMap contributors and used under the [ODbL](https://www.openstreetmap.org/copyright). Community-contributed data is stored separately and never mixed into ODbL exports.
