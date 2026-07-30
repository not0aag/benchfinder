# Tile pipeline failure runbook

## Symptoms
- Map renders basemap but bench layer is missing
- `/tiles/benches/{z}/{x}/{y}.mvt` returns 500 or high latency

## Triage
1. Check edge function logs for `tile generation failed`.
2. Run a known-good tile curl check from `BENCHFINDER_ARCHITECTURE.md` phase 2 exit tile.
3. Validate `bench_tile(z,x,y)` directly in Postgres.
4. Confirm recent schema changes did not break `bench_tile` or `compute_bench_min_zoom`.

## Immediate mitigation
- Serve stale CDN tiles while investigating.
- If a regression came from a release, roll back edge function code.
- If failure is data-shape related, hotfix with forward SQL migration.

## Recovery validation
- p95 tile latency back under SLO budget.
- Tile tests (`supabase/tests/005_tiles.sql`) pass.
- Map layer renders in mobile dev build and tile debug page.
