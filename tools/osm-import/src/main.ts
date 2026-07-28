import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { parseArgs } from 'node:util';

import { createClient, loadAndPromote } from './db.js';
import { fetchBenches } from './overpass.js';
import { getRegion } from './regions.js';

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      region: { type: 'string', short: 'r' },
    },
  });
  if (!values.region) {
    throw new Error('usage: pnpm osm:import --region <halton|oakville>');
  }

  const region = getRegion(values.region);
  console.log(`fetching benches for ${region.name} from Overpass...`);
  const elements = await fetchBenches(region);
  console.log(`fetched ${elements.length} elements`);

  const dataDir = path.join(import.meta.dirname, '..', 'data');
  await mkdir(dataDir, { recursive: true });
  const snapshot = path.join(
    dataDir,
    `${values.region}-${new Date().toISOString().slice(0, 10)}.json`,
  );
  await writeFile(snapshot, JSON.stringify(elements, null, 1), 'utf8');
  console.log(`snapshot written to ${snapshot}`);

  const client = createClient();
  await client.connect();
  try {
    const result = await loadAndPromote(client, elements);
    console.log(
      `osm_features loaded/updated: ${result.loaded}, ` +
        `bf_benches promoted: ${result.promoted}, skipped: ${result.skipped}`,
    );
  } finally {
    await client.end();
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
