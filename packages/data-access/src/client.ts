import { createClient, type SupabaseClient } from '@supabase/supabase-js';

// The anon key is public by design; RLS is what protects the data.
export function createSupabaseClient(url: string, anonKey: string): SupabaseClient {
  return createClient(url, anonKey, {
    auth: {
      // mobile session persistence arrives with Phase 5 (auth)
      persistSession: false,
    },
  });
}
