# Moderation hardening baseline

## Abuse controls
- Rate limit submissions and confirmations per account and device.
- Enforce proximity checks for confirmation actions.
- Flag impossible travel speed across sequential submissions.
- Treat repeated rejected duplicates as spam risk signals.

## Review workflow
- Add explicit appeal state and moderator response SLA.
- Require reason codes for removals and verification demotions.
- Log every moderator action in `moderation_events` with actor and payload.

## Audit visibility
- Weekly review of moderation_events for outlier moderator behavior.
- Monthly threshold tuning based on false-positive and false-negative rates.
