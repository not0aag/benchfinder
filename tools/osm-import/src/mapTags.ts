// OSM tag -> bf_benches attribute mapping. Only faithful semantics are
// mapped; anything ambiguous stays null (null means "nobody has checked").

export interface BenchAttributes {
  has_backrest: boolean | null;
  has_armrests: boolean | null;
  is_accessible: boolean | null;
  is_lit: boolean | null;
  material: 'wood' | 'metal' | 'concrete' | 'stone' | 'plastic' | 'composite' | 'mixed' | 'unknown';
  seats: number | null;
  facing_degrees: number | null;
}

const MATERIALS: Record<string, BenchAttributes['material']> = {
  wood: 'wood',
  metal: 'metal',
  steel: 'metal',
  concrete: 'concrete',
  stone: 'stone',
  plastic: 'plastic',
  composite: 'composite',
};

const CARDINALS: Record<string, number> = {
  N: 0,
  NNE: 22,
  NE: 45,
  ENE: 67,
  E: 90,
  ESE: 112,
  SE: 135,
  SSE: 157,
  S: 180,
  SSW: 202,
  SW: 225,
  WSW: 247,
  W: 270,
  WNW: 292,
  NW: 315,
  NNW: 337,
};

function yesNo(value: string | undefined): boolean | null {
  if (value === 'yes') return true;
  if (value === 'no') return false;
  return null;
}

function parseSeats(value: string | undefined): number | null {
  if (!value) return null;
  const n = Number.parseInt(value, 10);
  return Number.isInteger(n) && n >= 1 && n <= 50 ? n : null;
}

function parseDirection(value: string | undefined): number | null {
  if (!value) return null;
  const cardinal = CARDINALS[value.toUpperCase()];
  if (cardinal !== undefined) return cardinal;
  const n = Number.parseFloat(value);
  if (!Number.isFinite(n)) return null;
  const normalized = Math.round(((n % 360) + 360) % 360);
  return normalized === 360 ? 0 : normalized;
}

export function mapTags(tags: Record<string, string>): BenchAttributes {
  return {
    has_backrest: yesNo(tags['backrest']),
    has_armrests: yesNo(tags['armrest']),
    is_accessible: yesNo(tags['wheelchair']),
    is_lit: yesNo(tags['lit']),
    material: MATERIALS[tags['material'] ?? ''] ?? 'unknown',
    seats: parseSeats(tags['seats']),
    facing_degrees: parseDirection(tags['direction']),
  };
}
