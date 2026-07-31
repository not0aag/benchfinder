# CLAUDE.md — BenchFinder

Operating instructions for Claude Code on this repository.

---

## Read first

`BENCHFINDER_ARCHITECTURE.md` is the source of truth for every architectural decision. Read it at the start of every session. If a request in chat contradicts it, say so and ask before proceeding. If you believe a decision in it is wrong, argue the case with pros/cons/alternatives before writing code, not after.

---

## Project

Mobile app cataloguing public benches. Seeded from OpenStreetMap, enriched by community contributions. Expo + TypeScript + MapLibre + Supabase (Postgres/PostGIS). Target: production-quality, expandable from Oakville to global.

Solo developer. Optimize for maintainability by one person, not for team throughput.

---

## Non-negotiable rules

1. **Never mix ODbL and proprietary data.** `osm_features` and `bf_benches` stay separate. Any query joining them for an export must be flagged in review. Any bench row with `source_osm_id IS NOT NULL` carries ODbL provenance.
2. **Never let the client write a state transition.** `status` and `verification_state` change only inside `SECURITY DEFINER` functions. If you find yourself writing `.update({ status: 'published' })` in app code, stop.
3. **Never mock PostGIS in tests.** Spatial queries get a real Postgres via testcontainers. Mocked spatial logic is worse than no test.
4. **Never fetch bench collections as rows for map display.** Map data comes from vector tiles. Row queries are for the detail sheet, the nearby list, and the admin dashboard only.
5. **Every RLS policy gets a pgTAP test** asserting both the allow case and the deny case. A policy without a deny test is not done.
6. **`packages/domain` has zero runtime dependencies.** No React, no Supabase, no fetch. If you need one, the logic belongs elsewhere.
7. **No secrets in committed files.** EAS secrets for build-time, edge function env for runtime.
8. **Nullable means unknown.** Do not default physical attributes to `false`. `NULL` and `false` carry different meaning in this domain.
9. **Migrations must be executed, not reviewed.** Every SQL migration runs against a live
   Postgres via `pnpm db:reset` followed by a full `pnpm test:db` before it is committed.
   A migration that has only been read is not validated.
10. **No CI gate over hand-authored data.** If a check's input is not produced by an
    automated measurement, it is a checklist item, not a pipeline step.

---

## Working style

- **Build in phases.** Phase list is section 12 of the architecture doc. Complete a phase and hit its exit criterion before starting the next. Do not scaffold ahead.
- **Before writing code for a phase:** state what you are building, why, what files you will touch, and what the acceptance test is. Wait for confirmation.
- **Never dump the whole phase at once.** Work in reviewable increments. One coherent unit of work, then stop.
- **When a decision has real trade-offs, present them.** Two or three options, pros/cons, your recommendation with reasoning. Do not silently pick.
- **Prefer boring.** Fewer dependencies, standard patterns, obvious code. Cleverness is a maintenance tax paid by future-Alen alone.
- **Delete rather than comment out.** Git remembers.

---

## Code standards

- TypeScript strict mode. `any` requires a comment justifying it.
- No default exports except expo-router route files.
- Zod at every trust boundary, schemas shared via `packages/api-contracts`.
- Async errors handled explicitly. No unhandled promise rejections.
- Every user-facing string goes through i18n from day one, even while English-only.
- Every interactive element gets an accessibility label and a role.
- Components under 200 lines. Past that, extract.
- SQL migrations forward-only, timestamped, never edited after merge.
- Conventional commits.

---

## Writing style for docs and comments

- Direct and terse. No filler, no preamble.
- No em dashes.
- Comments explain _why_, never _what_. If the what is unclear, rename things.
- No "AI-sounding" prose in READMEs. Write like a developer explaining to another developer.

---

## Commands

```bash
pnpm dev:mobile          # Expo dev server
pnpm dev:admin           # Admin dashboard
pnpm test                # All tests
pnpm test:db             # pgTAP RLS tests
pnpm typecheck
pnpm lint
supabase db reset        # Rebuild local DB from migrations
supabase functions serve # Local edge functions
pnpm osm:import <region> # Ingest a Geofabrik extract
```

---

## Definition of done, per phase

- [ ] Exit criterion from the architecture doc demonstrably met
- [ ] Tests written and passing at the layer appropriate to the code
- [ ] pgTAP tests updated if any policy or table changed
- [ ] Typecheck and lint clean
- [ ] Accessibility pass on any new UI (screen reader, contrast, dynamic type)
- [ ] Dark mode verified
- [ ] Tablet layout verified for any new screen
- [ ] Works or degrades gracefully offline
- [ ] Runs on a physical mid-range Android device, not just the simulator
- [ ] `BENCHFINDER_ARCHITECTURE.md` updated if a decision changed

---

## Anti-patterns for this codebase specifically

- Adding a dependency to solve something 40 lines of code solves
- Client-side filtering of data that should have been filtered in SQL
- `useEffect` for data fetching (React Query owns the server cache)
- Zustand storing anything derivable from server state
- Optimistic UI without a rollback path
- Computing aggregates on read (they are trigger-maintained columns)
- Calling a cloud model where an on-device model or plain math suffices
- Google Places API. It is expensive and this app does not need it.
