import type { Region } from './regions.js';

export interface OverpassElement {
  type: 'node' | 'way';
  id: number;
  lat?: number;
  lon?: number;
  center?: { lat: number; lon: number };
  tags?: Record<string, string>;
  version?: number;
  changeset?: number;
}

interface OverpassResponse {
  elements: OverpassElement[];
}

const ENDPOINT = 'https://overpass-api.de/api/interpreter';

export function buildQuery(region: Region): string {
  const bbox = region.bbox.join(',');
  return `[out:json][timeout:120];
(
  node["amenity"="bench"](${bbox});
  way["amenity"="bench"](${bbox});
);
out center meta;`;
}

export async function fetchBenches(region: Region): Promise<OverpassElement[]> {
  const query = buildQuery(region);
  const contact = process.env['OVERPASS_CONTACT'] ?? 'benchfinder-dev';
  let lastError: unknown;

  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const res = await fetch(ENDPOINT, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': `BenchFinder-osm-import/0.1 (${contact})`,
        },
        body: `data=${encodeURIComponent(query)}`,
      });
      if (res.status === 429 || res.status === 504) {
        throw new Error(`overpass busy: HTTP ${res.status}`);
      }
      if (!res.ok) {
        throw new Error(`overpass error: HTTP ${res.status}`);
      }
      const json = (await res.json()) as OverpassResponse;
      return json.elements;
    } catch (error) {
      lastError = error;
      if (attempt < 3) {
        const waitMs = attempt * 15_000;
        console.warn(`attempt ${attempt} failed (${String(error)}), retrying in ${waitMs / 1000}s`);
        await new Promise((resolve) => setTimeout(resolve, waitMs));
      }
    }
  }
  throw lastError;
}
