# Next steps

**Read this first, then stop reading.** This file is the entry point. It supersedes
`whatsnext.txt` (untracked, 2026-07-28, written before the photo removal). `plan2.md` is still
accurate for the detailed specs of tasks 4 and 5 below, so this file points at it instead of
repeating it.

**Written:** 2026-08-02, after the first successful Android run.
**Rules that still govern everything:** `CLAUDE.md`, `BENCHFINDER_ARCHITECTURE.md`.

---

## Where the project actually is

| Phase                   | Status                                                                                 |
| ----------------------- | -------------------------------------------------------------------------------------- |
| 0 Foundation            | CI green. Open: no build on a physical device or iOS simulator. Emulator now works.    |
| 1 Data foundation + OSM | 2,863 Halton benches, pgTAP green. Local Postgres only.                                |
| 2 Tile pipeline         | Done. Verified again 2026-08-02 from the Android emulator.                             |
| 3 Map screen            | Runs on the emulator. **Blocked by task 1 below.** Offline basemap pack still missing. |
| 4 Bench detail          | Not started. Spec in `plan2.md` task 4.                                                |
| 5 Auth + profile        | Blocked on hosted Supabase.                                                            |
| 6 Submission flow       | Not started. Full spec in `plan2.md` task 5, including the RPC gate table.             |
| 7-9                     | Untouched.                                                                             |

---

## Environment: already solved, do not re-derive

These cost hours on 2026-08-02. They are fixed. Do not rediscover them.

- **JDK.** `JAVA_HOME` is now `C:\Program Files\Amazon Corretto\jdk21.0.8_9`, set persistently.
  It previously pointed at `jdk1.8.0_202`, and Gradle honours `JAVA_HOME` over `PATH`, so every
  build failed. If a build reports an ancient JVM, check this first.
- **pnpm layout.** `pnpm-workspace.yaml` sets `nodeLinker: hoisted`. Required: the isolated store
  puts CMake object paths ~135 chars over the 250 char cap, and `react-native-screens` and
  `react-native-worklets` fail with `ninja: manifest still dirty`. Do not remove it.
- **After changing the linker or moving packages**, clear `apps/mobile/android/build`,
  `apps/mobile/android/app/build`, and `apps/mobile/android/.gradle`. Autolinking caches absolute
  paths and will keep pointing at the old ones.
- **Emulator.** AVD `Medium_Phone`, API 37, x86_64. Boot it, then
  `adb emu geo fix -79.68 43.43` to put the device in Oakville.
- **Supabase edge runtime does not always come back.** If tiles return 503 after a Docker restart,
  the container exited and `supabase start` will not revive it:
  `docker start supabase_edge_runtime_BenchApp`. `EDGE_DB_URL` lives in `supabase/.env`.
- **Disk.** `C:` filled to zero mid-build on 2026-08-02 and OOM-killed containers. Docker's 24.6 GB
  is live data, not reclaimable cache. Check the Recycle Bin and unused AVD system images instead.

Run the app:

```bash
cd apps/mobile && pnpm exec expo run:android
```

---

## Task 1: fix the bench tap, then close phase 3

**This is the next thing to do. It is small and it blocks phase 3.**

Tapping a bench marker never opens `BenchDetailCard`. Confirmed on the emulator against a dense
marker cluster, so it is not a hit-target miss, and logcat is clean.

Cause, documented in the library at
`node_modules/@maplibre/maplibre-react-native/src/components/map/Map.tsx:452-456`: a single tap
emits on both `Map` and `Source`. In `apps/mobile/src/features/map/MapScreen.tsx`, the
`VectorSource` handler (line 60) sets `selectedBenchId`, then the `Map` handler (line 53) fires for
the same tap and resets it to `null`.

Fix: call `event.stopPropagation()` at the top of the `VectorSource` `onPress` handler.

**Acceptance:** tap a bench, the card opens showing state, material and provenance. Tap empty map,
the card closes. Verify on the emulator, not by reading the diff.

Then the rest of phase 3's exit criterion:

1. **Offline basemap pack for Halton.** May not exist at all. Check before assuming it is small.
   Protomaps PMTiles per architecture section 3. The map currently uses
   `tile.openstreetmap.org` raster, marked `TODO(protomaps)` in `MapScreen.tsx`.
2. **Physical mid-range Android device.** Needs `eas login`, which is interactive, so the human runs
   it. Then `eas build --profile development --platform android`. This also closes phase 0's
   dev-build criterion.

Marker colours by `verification_state` are **done**. Verified 2026-08-02: `MapScreen.tsx:76-90`
matches architecture section 5, and OSM benches render amber. Do not re-check this.

Update `docs/governance/phase-gates.json` by hand as each item genuinely lands. Do not add a CI gate
over it (`CLAUDE.md` rule 10).

---

## Task 2: stand up hosted Supabase

Blocks phases 5 and 7, and it is why phase 1's data is stuck on one laptop. Doing it before phase 4
avoids baking local-only assumptions into new code.

Details in `plan2.md` task 3. Summary: create and link the project, push all migrations including
`20260802120000_remove_photos.sql`, verify the chain applies to an empty hosted database, keep keys
out of committed files (`CLAUDE.md` rule 7), then either re-run the OSM import or dump and restore.
Write down which one you picked.

---

## Task 3: phase 4, bench detail

Full spec in `plan2.md` task 4. The one decision to make before writing any code: does
`BenchDetailCard` become the full sheet, or stay as a peek affordance above it? That drives the file
layout.

---

## Task 4: phase 6, submission flow

Full spec in `plan2.md` task 5, including the `submit_bench` RPC gate table, the `bench_insert` RLS
decision, and the pgTAP suite it forces. Do not re-plan it from scratch.

---

## Task 5: non-code items still open

Architecture section 14, unchanged by today's work: the ODbL produced-work boundary needs a real
lawyer before any public export, the name "BenchFinder" needs a CIPO and USPTO check, the OSM Canada
forum post is overdue, and region 1 scope (Halton or full GTA) is still undecided. Photo licensing
is moot.
