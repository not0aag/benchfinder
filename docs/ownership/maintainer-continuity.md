# Maintainer continuity notes

## Single-maintainer resilience
- Keep phase-gate status current in `docs/governance/phase-gates.json`.
- Keep runbooks updated whenever operational flows change.
- Record major architecture deltas in `BENCHFINDER_ARCHITECTURE.md`.

## Ownership map
- Mobile app: apps/mobile
- Data contracts and parsing: packages/api-contracts
- Data access: packages/data-access
- Database schema/RLS/functions/tests: supabase/migrations and supabase/tests
- Ingestion: tools/osm-import

## Session close checklist
- Document what changed, what is still risky, and what to verify next.
- Leave commands needed to reproduce validation outcomes.
