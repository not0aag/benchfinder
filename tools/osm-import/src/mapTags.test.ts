import { describe, expect, it } from 'vitest';

import { mapTags } from './mapTags.js';

describe('mapTags', () => {
  it('maps explicit yes/no tags to booleans', () => {
    const attrs = mapTags({ backrest: 'yes', armrest: 'no', wheelchair: 'yes', lit: 'no' });
    expect(attrs.has_backrest).toBe(true);
    expect(attrs.has_armrests).toBe(false);
    expect(attrs.is_accessible).toBe(true);
    expect(attrs.is_lit).toBe(false);
  });

  it('leaves absent or unclear tags null, never false', () => {
    const attrs = mapTags({ backrest: 'maybe' });
    expect(attrs.has_backrest).toBeNull();
    expect(attrs.has_armrests).toBeNull();
    expect(attrs.is_accessible).toBeNull();
    expect(attrs.seats).toBeNull();
    expect(attrs.facing_degrees).toBeNull();
  });

  it('maps known materials and treats steel as metal', () => {
    expect(mapTags({ material: 'wood' }).material).toBe('wood');
    expect(mapTags({ material: 'steel' }).material).toBe('metal');
    expect(mapTags({ material: 'granite' }).material).toBe('unknown');
    expect(mapTags({}).material).toBe('unknown');
  });

  it('parses seats within the schema bounds only', () => {
    expect(mapTags({ seats: '4' }).seats).toBe(4);
    expect(mapTags({ seats: '0' }).seats).toBeNull();
    expect(mapTags({ seats: '600' }).seats).toBeNull();
    expect(mapTags({ seats: 'lots' }).seats).toBeNull();
  });

  it('parses numeric and cardinal directions', () => {
    expect(mapTags({ direction: '135' }).facing_degrees).toBe(135);
    expect(mapTags({ direction: 'SE' }).facing_degrees).toBe(135);
    expect(mapTags({ direction: '360' }).facing_degrees).toBe(0);
    expect(mapTags({ direction: '-90' }).facing_degrees).toBe(270);
    expect(mapTags({ direction: 'up' }).facing_degrees).toBeNull();
  });
});
