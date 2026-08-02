# Work order: what to do after the photo removal

**For:** Claude Code
**Prereq reading:** `BENCHFINDER_ARCHITECTURE.md`, `CLAUDE.md`
**Written:** 2026-08-02, on `feat/remove-photos`
**Supersedes:** `whatsnext.txt` (untracked, written 2026-07-28, still describes the photo-based plan)

---

## State of the repo, honestly

Do not take the phase list at face value. What is actually true:

| Phase                   | Status                                                                                                                                   |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| 0 Foundation            | CI green. **Not** closed: no EAS dev build has been installed on a physical Android device or an iOS simulator.                          |
| 1 Data foundation + OSM | 2,863 Halton benches imported, pgTAP green. **Local Postgres only.** No hosted Supabase project exists.                                  |
| 2 Tile pipeline         | Done. MVT verified through `tools/tile-debug`.                                                                                           |
| 3 Map screen            | Code exists and runs in simulator. **Exit criterion unverified:** no physical mid-range Android run, no offline basemap pack for Halton. |
| 4 Bench detail          | Next real feature work, blocked by phase 3 per `CLAUDE.md` "Build in phases".                                                            |
| 5 Auth + profile        | Blocked on hosted Supabase (OAuth needs real redirect URLs).                                                                             |
| 6 Submission flow       | Rewritten to 2 days by the photo removal. Spec in task 5 below.                                                                          |
| 7-9                     | Untouched.                                                                                                                               |

Two governance changes landed alongside this work and are worth knowing about:

- `tools/phase-gate/check-phase-gates.mjs` was deleted and its CI step removed (commit `994a7f1`). It gated the pipeline on `docs/governance/phase-gates.json`, which is hand-authored, and `CLAUDE.md` rule 10 forbids exactly that. It had also wedged: it enforces a strictly linear phase model and could not express "phase 0 has an open loose end while phase 1 landed", so the only way to green it was to falsify a criterion.
- `docs/governance/phase-gates.json` survives as a checklist document. Keep it accurate by hand. Do not re-add a CI gate over it.

---

## Task 1: Merge `feat/remove-photos`

Open the PR, confirm `ci` and `db` are both green, merge. Everything below assumes it has landed.

---

## Task 2: Close phase 3

`CLAUDE.md` phase discipline blocks phase 4 until phase 3's exit criterion is genuinely met, not
approximately met. Three things:

1. **Physical device run.** Needs an EAS dev build on a mid-range Android. This is the same blocker
   as phase 0's `dev-builds` criterion, so it closes both. `eas login` is interactive, so the human
   runs it; the agent can run `eas build --profile development --platform android` after.
2. **Offline basemap pack for Halton.** This may not exist at all yet. Check before assuming it is a
   small task. Protomaps PMTiles per section 3 of the architecture doc.
3. **Marker colours by verification state.** Confirm `MapScreen.tsx` actually wires the style
   expression to `verification_state`, and that the palette matches section 5: `unconfirmed` amber,
   `community` blue, `confirmed` green, `verified` green with a check, `disputed` red outline.

Update `docs/governance/phase-gates.json` when each one is genuinely done. Not before.

---

## Task 3: Stand up hosted Supabase

Blocks phases 5 and 7, and it is the reason phase 1's data is unreachable off one laptop. Doing it
now avoids discovering local-only assumptions baked into phase 4 and 5 code later.

- Create the project, link it, push all migrations including `20260802120000_remove_photos.sql`.
- Verify the migration chain applies cleanly to an empty hosted database, not just to a local reset.
- Move the anon key into the app config, the service role key into edge function env. `CLAUDE.md`
  rule 7: no secrets in committed files.
- Re-run the OSM import against hosted, or dump and restore from local. Either is fine, pick one and
  write down which.

---

## Task 4: Phase 4, bench detail

Scope, now that the photo carousel is gone: detail sheet with all metadata, ratings display,
favourite and visit actions, share deep link (`benchfinder://bench/{id}`), full accessibility pass,
tablet layout.

`BenchDetailCard.tsx` already renders most of the metadata as a map overlay card. Phase 4 is the
full sheet, so decide early whether the card becomes the sheet or stays as a peek affordance above
it. That decision drives the file layout, so make it before writing code.

Per `CLAUDE.md` working style: state what you are building, why, which files, and the acceptance
test, then wait. This is UI-heavy with real a11y and tablet requirements. Do it in increments, not
one dump.

**Exit:** VoiceOver and TalkBack complete the full read flow. Passes on a 10 inch tablet.

---

## Task 5: Phase 6, the submission flow

This is the phase the photo removal rewrote. Roughly two days.

### The RPC

One `SECURITY DEFINER` function, `public.submit_bench(...)`. It is the only path that creates a
user-origin bench. `CLAUDE.md` rule 2: the client never writes a state transition, so the client
must not be able to insert a `published` row directly.

Gates, all enforced inside the function, in this order:

| Gate        | Rule                                                                        | Error to surface                  |
| ----------- | --------------------------------------------------------------------------- | --------------------------------- |
| Auth        | `auth.uid()` is not null, and the user is not banned                        | not signed in / account suspended |
| Account age | `user_profiles.created_at` older than 1 hour                                | too new to submit                 |
| Rate limit  | fewer than 10 by this user in the last hour, fewer than 30 in the last 24 h | slow down                         |
| Proximity   | `ST_DWithin(submitted_point, device_fix, 150)`                              | move closer to the bench          |
| Duplicate   | no existing bench within 15 m (`ST_DWithin`)                                | a bench is already mapped here    |

On success it inserts `status='published'`, `verification_state='unconfirmed'`, `origin='user'`,
`source_osm_id=null`, and writes a `moderation_events` row.

Note the device fix is a client-supplied parameter, so it is a claim, not proof. That is accepted:
at Oakville scale with a handful of contributors this raises the cost of bad data enough. Do not
build more. Say so in a comment so nobody "improves" it later.

### RLS change this forces

`bench_insert` on `bf_benches` currently requires `status = 'pending'`, which no longer matches any
real flow. Decide between:

- **Revoke client insert on `bf_benches` entirely** and drop the `bench_insert` policy, routing
  everything through the RPC. Cleaner, and the recommended option.
- Keep the policy for an admin path. Only if something actually needs it.

Whichever you pick, `CLAUDE.md` rule 5 applies: every policy gets a pgTAP allow case **and** a deny
case. A new suite, `007_submit_bench.sql`, should cover each gate above failing and the happy path
succeeding, and assert that a direct client insert of a `published` row is rejected.

Rule 9 also applies: run `pnpm db:reset` then `pnpm test:db` against live Postgres before committing.

### Client

Submission form with map pin adjustment, GPS capture via `expo-location`, structured attribute entry
(nullable tri-state for the physical booleans, never defaulting to `false`, per rule 8), and an
offline queue with background sync.

**Exit:** submit a bench in airplane mode, it syncs on reconnect. A submission 1 km from the device
fix is rejected server-side with a clear message.

---

## Task 6: Open questions still outstanding

Architecture doc section 14. Item 4, photo licensing, is now moot and marked as such. The rest are
live:

1. **ODbL produced-work boundary.** Needs an actual IP lawyer before any public export. Not a
   blocker for local development.
2. **The name "BenchFinder".** Generic and likely contested. Check CIPO and USPTO before spending
   anything on branding.
3. **OSM Canada forum post.** Should arguably have preceded the phase 1 import. Do it now. It is a
   conversation, not code, and it gets harder to explain the longer it waits.
4. ~~Photo licensing.~~ Moot.
5. **Region 1 scope.** Halton only, or the full GTA? Affects extract size retroactively and the
   phase 9 scaling notes.

---

## Standing constraints

Nothing here changes the rules in `CLAUDE.md`. The ones this work order will actually collide with:

- Migrations are executed, never merely reviewed (rule 9).
- Every RLS policy gets both an allow and a deny pgTAP test (rule 5).
- Nullable means unknown. Do not default physical attributes to `false` (rule 8).
- No photo capture, image storage, or image-processing dependency. Deliberately removed.
- `MapScreen.tsx` imports a component named `Camera`. That is the MapLibre map camera. Leave it alone.
