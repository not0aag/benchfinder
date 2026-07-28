// Bounding boxes, not Overpass area lookups: deterministic and immune to
// name ambiguity. Overpass bbox order is (south, west, north, east).
export interface Region {
  readonly name: string;
  readonly bbox: readonly [south: number, west: number, north: number, east: number];
}

export const REGIONS: Record<string, Region> = {
  halton: {
    name: 'Halton Region, Ontario',
    bbox: [43.28, -80.16, 43.76, -79.54],
  },
  oakville: {
    name: 'Oakville, Ontario',
    bbox: [43.38, -79.83, 43.53, -79.59],
  },
};

export function getRegion(key: string): Region {
  const region = REGIONS[key];
  if (!region) {
    throw new Error(`unknown region "${key}" (known: ${Object.keys(REGIONS).join(', ')})`);
  }
  return region;
}
