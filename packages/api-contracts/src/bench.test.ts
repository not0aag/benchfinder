import { describe, expect, it } from 'vitest';

import { benchDetailSchema } from './bench.js';

const validRow = {
  id: 'b31f9de8-0000-4000-8000-000000000001',
  lat: 43.444,
  lon: -79.66,
  origin: 'user',
  source_osm_id: null,
  verification_state: 'unconfirmed',
  has_backrest: true,
  has_armrests: null,
  has_table: null,
  is_accessible: null,
  has_shade: null,
  is_lit: false,
  material: 'wood',
  condition: null,
  seats: 3,
  facing_degrees: 180,
  description: null,
  photo_count: 0,
  rating_count: 2,
  scenic_avg: '4.50',
  comfort_avg: null,
  favorite_count: 0,
  confirm_count: 1,
  dispute_count: 0,
  updated_at: '2026-07-28T12:00:00+00:00',
};

describe('benchDetailSchema', () => {
  it('accepts a valid row and coerces numeric strings from postgrest', () => {
    const parsed = benchDetailSchema.parse(validRow);
    expect(parsed.scenic_avg).toBe(4.5);
    expect(parsed.has_armrests).toBeNull();
  });

  it('rejects unknown verification states', () => {
    expect(() =>
      benchDetailSchema.parse({ ...validRow, verification_state: 'published' }),
    ).toThrow();
  });

  it('rejects out-of-range coordinates', () => {
    expect(() => benchDetailSchema.parse({ ...validRow, lat: 91 })).toThrow();
    expect(() => benchDetailSchema.parse({ ...validRow, lon: -181 })).toThrow();
  });

  it('does not silently default unknown attributes', () => {
    const { has_backrest: _ignored, ...missing } = validRow;
    expect(() => benchDetailSchema.parse(missing)).toThrow();
  });
});
