import { createBenchRepository, createSupabaseClient } from '@benchfinder/data-access';

const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error(
    'EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_ANON_KEY must be set (see .env.example)',
  );
}

export const supabase = createSupabaseClient(url, anonKey);
export const benchRepository = createBenchRepository(supabase);

export const tilesUrl = process.env.EXPO_PUBLIC_TILES_URL ?? `${url}/functions/v1/tiles`;
