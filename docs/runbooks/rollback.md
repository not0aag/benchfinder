# Rollback runbook

## Deploy rollback
1. Identify target SHA from the last known good deploy.
2. Roll back app and edge function release artifacts to that SHA.
3. Verify map load, bench detail fetch, and auth read flows.
4. Keep rollback as active release until fix is validated in staging.

## Database rollback policy
- Migrations are forward-only. Do not edit merged migrations.
- For breaking data changes, ship corrective forward migration.
- If data integrity is affected, restore from backup to a clean environment and replay safe migrations.

## Validation checklist
- Tile endpoint returns 200/204 only for sampled tiles.
- `pnpm test:db` passes against restored schema.
- Bench detail sheet still respects RLS for pending benches.
