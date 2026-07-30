import { describe, expect, it, vi } from 'vitest';

import { createBenchRepository } from './benchRepository.js';

const validBenchRow = {
  id: 'b31f9de8-0000-4000-8000-000000000001',
  lat: 43.444,
  lon: -79.66,
  origin: 'user',
  source_osm_id: null,
  verification_state: 'community',
  has_backrest: true,
  has_armrests: false,
  has_table: null,
  is_accessible: true,
  has_shade: null,
  is_lit: false,
  material: 'wood',
  condition: 'good',
  seats: 3,
  facing_degrees: 90,
  description: null,
  photo_count: 1,
  rating_count: 1,
  scenic_avg: 4,
  comfort_avg: 4,
  favorite_count: 0,
  confirm_count: 2,
  dispute_count: 0,
  updated_at: '2026-07-30T00:00:00Z',
};

function makeClient(result: { data: unknown; error: { message: string } | null }) {
  const maybeSingle = vi.fn().mockResolvedValue(result);
  const eq = vi.fn(() => ({ maybeSingle }));
  const select = vi.fn(() => ({ eq }));
  const from = vi.fn(() => ({ select }));
  return {
    client: { from } as unknown as import('@supabase/supabase-js').SupabaseClient,
    spies: { from, select, eq, maybeSingle },
  };
}

describe('createBenchRepository', () => {
  it('returns null when no row is found', async () => {
    const { client } = makeClient({ data: null, error: null });
    const repo = createBenchRepository(client);

    await expect(repo.findBenchById('missing')).resolves.toBeNull();
  });

  it('parses and returns bench details for a valid row', async () => {
    const { client } = makeClient({ data: validBenchRow, error: null });
    const repo = createBenchRepository(client);

    await expect(repo.findBenchById(validBenchRow.id)).resolves.toEqual(validBenchRow);
  });

  it('throws a wrapped error when supabase returns an error', async () => {
    const { client } = makeClient({ data: null, error: { message: 'permission denied' } });
    const repo = createBenchRepository(client);

    await expect(repo.findBenchById('bench-id')).rejects.toThrow(
      'findBenchById(bench-id): permission denied',
    );
  });
});
