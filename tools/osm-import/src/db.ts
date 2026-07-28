import pg from 'pg';

import { mapTags } from './mapTags.js';
import type { OverpassElement } from './overpass.js';

// Local supabase db by default. The import runs as postgres/service role:
// osm_features has no client write policies by design.
const DEFAULT_DB_URL = 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';

export function createClient(): pg.Client {
  return new pg.Client({ connectionString: process.env['SUPABASE_DB_URL'] ?? DEFAULT_DB_URL });
}

interface LoadResult {
  loaded: number;
  promoted: number;
  skipped: number;
}

export async function loadAndPromote(
  client: pg.Client,
  elements: OverpassElement[],
): Promise<LoadResult> {
  let loaded = 0;
  let skipped = 0;

  await client.query('begin');
  try {
    for (const el of elements) {
      const lat = el.lat ?? el.center?.lat;
      const lon = el.lon ?? el.center?.lon;
      if (lat === undefined || lon === undefined || !el.tags || el.version === undefined) {
        skipped++;
        continue;
      }
      await client.query(
        `insert into osm_features (osm_id, osm_type, geom, tags, osm_version, osm_changeset, imported_at)
         values ($1, $2, st_setsrid(st_makepoint($3, $4), 4326)::geography, $5, $6, $7, now())
         on conflict (osm_id) do update
           set geom = excluded.geom,
               tags = excluded.tags,
               osm_version = excluded.osm_version,
               osm_changeset = excluded.osm_changeset,
               imported_at = now()`,
        [el.id, el.type, lon, lat, el.tags, el.version, el.changeset ?? null],
      );
      loaded++;
    }

    // Promote unpromoted bench features. Coordinates copied from OSM keep
    // ODbL provenance via source_osm_id; attributes are re-derived in SQL-free
    // TS for testability, but promotion is one set-based statement per run.
    const promoted = await promoteNew(client, elements);

    if (promoted > 0) {
      await client.query('select compute_bench_min_zoom()');
    }

    await client.query('commit');
    return { loaded, promoted, skipped };
  } catch (error) {
    await client.query('rollback');
    throw error;
  }
}

async function promoteNew(client: pg.Client, elements: OverpassElement[]): Promise<number> {
  let promoted = 0;
  for (const el of elements) {
    if (!el.tags) continue;
    const attrs = mapTags(el.tags);
    const result = await client.query(
      `insert into bf_benches
         (geom, origin, source_osm_id, status, verification_state,
          has_backrest, has_armrests, is_accessible, is_lit, material, seats, facing_degrees)
       select f.geom, 'osm', f.osm_id, 'published', 'unconfirmed',
              $2, $3, $4, $5, $6, $7, $8
       from osm_features f
       where f.osm_id = $1
         and not exists (select 1 from bf_benches b where b.source_osm_id = f.osm_id)`,
      [
        el.id,
        attrs.has_backrest,
        attrs.has_armrests,
        attrs.is_accessible,
        attrs.is_lit,
        attrs.material,
        attrs.seats,
        attrs.facing_degrees,
      ],
    );
    promoted += result.rowCount ?? 0;
  }
  return promoted;
}
