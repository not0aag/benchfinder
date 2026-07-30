# Supabase outage runbook

## Detection
- Supabase status page incident
- Elevated connection errors, auth failures, or storage upload failures

## Actions
1. Confirm outage scope: auth, database, storage, or edge functions.
2. Switch app messaging to degraded-mode copy for impacted flows.
3. Pause write-heavy jobs and ingestion pipelines.
4. Keep offline queue operational client-side where possible.
5. Resume background jobs after service stability is confirmed.

## Communication
- Post user-facing status notice for Sev1 outages over 15 minutes.
- Record outage start/end and affected features.

## Exit criteria
- Error rates return to baseline for 30 minutes.
- Auth sign-in and bench detail reads pass smoke checks.
- Deferred jobs and queues are drained safely.
