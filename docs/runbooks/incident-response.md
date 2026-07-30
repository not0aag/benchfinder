# Incident response runbook

## Trigger conditions
- Crash loops, blank map, auth failures, or data corruption reports from users
- Tile endpoint returning sustained 5xx
- Supabase auth/db/storage degraded for more than 5 minutes

## Severity
- Sev1: Core app flows unavailable for most users
- Sev2: Degraded performance or one major flow down
- Sev3: Localized bug with workaround

## Response loop
1. Acknowledge incident and assign incident lead.
2. Freeze non-incident deployments.
3. Capture timeline in UTC and preserve logs/screenshots.
4. Mitigate user impact first, then investigate root cause.
5. Post status updates every 15 minutes for Sev1 and every 30 minutes for Sev2.
6. Resolve, verify recovery, then announce closure.

## Evidence to collect
- Sentry issue IDs and stack traces
- Supabase status and query error rates
- Tile endpoint response codes and latency
- Last successful deploy SHA

## Post-incident review
- Publish root cause, customer impact, and corrective actions within 48 hours.
- Add at least one automated guardrail to prevent recurrence.
