import postgres from 'npm:postgres@3.4.5';

// Public vector tile endpoint: GET /tiles/benches/{z}/{x}/{y}.mvt[?v=N]
// verify_jwt is off (config.toml): tiles carry only published-bench data and
// must be CDN-cacheable without auth. ?v= is a cache-buster bumped on bulk
// data changes; the handler ignores it.
const sql = postgres(Deno.env.get('SUPABASE_DB_URL')!, {
  prepare: false,
  max: 4,
});

const BASE_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Cache-Control': 'public, max-age=300, stale-while-revalidate=86400',
};

const PATH = /\/benches\/(\d{1,2})\/(\d{1,8})\/(\d{1,8})(?:\.mvt)?$/;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: BASE_HEADERS });
  }
  if (req.method !== 'GET') {
    return new Response('method not allowed', { status: 405, headers: BASE_HEADERS });
  }

  const match = PATH.exec(new URL(req.url).pathname);
  if (!match) {
    return new Response('not found', { status: 404, headers: BASE_HEADERS });
  }

  const z = Number(match[1]);
  const x = Number(match[2]);
  const y = Number(match[3]);
  if (z > 22 || x >= 2 ** z || y >= 2 ** z) {
    return new Response('invalid tile coordinates', { status: 400, headers: BASE_HEADERS });
  }

  try {
    const [row] = await sql`select bench_tile(${z}, ${x}, ${y}) as tile`;
    const tile = row?.tile as Uint8Array | null;

    if (!tile || tile.length === 0) {
      return new Response(null, { status: 204, headers: BASE_HEADERS });
    }
    return new Response(tile, {
      status: 200,
      headers: {
        ...BASE_HEADERS,
        'Content-Type': 'application/vnd.mapbox-vector-tile',
      },
    });
  } catch (error) {
    console.error('tile generation failed', error);
    return new Response('tile generation failed', {
      status: 500,
      headers: { ...BASE_HEADERS, 'Cache-Control': 'no-store' },
    });
  }
});
