import { benchDetailSchema, type BenchDetail } from '@benchfinder/api-contracts';
import type { SupabaseClient } from '@supabase/supabase-js';

export interface BenchRepository {
  findBenchById(id: string): Promise<BenchDetail | null>;
}

// Reads go through the bench_details view (security_invoker), so RLS decides
// visibility, not this code. Every row crossing the boundary is zod-parsed.
export function createBenchRepository(client: SupabaseClient): BenchRepository {
  return {
    async findBenchById(id) {
      const { data, error } = await client
        .from('bench_details')
        .select('*')
        .eq('id', id)
        .maybeSingle();
      if (error) {
        throw new Error(`findBenchById(${id}): ${error.message}`);
      }
      if (data === null) {
        return null;
      }
      return benchDetailSchema.parse(data);
    },
  };
}
