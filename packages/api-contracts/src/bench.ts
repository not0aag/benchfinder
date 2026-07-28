import { VERIFICATION_STATES } from '@benchfinder/domain';
import { z } from 'zod';

export const BENCH_MATERIALS = [
  'wood',
  'metal',
  'concrete',
  'stone',
  'plastic',
  'composite',
  'mixed',
  'unknown',
] as const;

export const BENCH_CONDITIONS = ['excellent', 'good', 'fair', 'poor', 'unusable'] as const;

// Shape of one row from the bench_details view. Nullable means unknown.
export const benchDetailSchema = z.object({
  id: z.uuid(),
  lat: z.number().min(-90).max(90),
  lon: z.number().min(-180).max(180),
  verification_state: z.enum(VERIFICATION_STATES),
  has_backrest: z.boolean().nullable(),
  has_armrests: z.boolean().nullable(),
  has_table: z.boolean().nullable(),
  is_accessible: z.boolean().nullable(),
  has_shade: z.boolean().nullable(),
  is_lit: z.boolean().nullable(),
  material: z.enum(BENCH_MATERIALS),
  condition: z.enum(BENCH_CONDITIONS).nullable(),
  seats: z.number().int().min(1).max(50).nullable(),
  facing_degrees: z.number().int().min(0).max(359).nullable(),
  description: z.string().max(500).nullable(),
  photo_count: z.number().int().nonnegative(),
  rating_count: z.number().int().nonnegative(),
  scenic_avg: z.coerce.number().nullable(),
  comfort_avg: z.coerce.number().nullable(),
  favorite_count: z.number().int().nonnegative(),
  confirm_count: z.number().int().nonnegative(),
  dispute_count: z.number().int().nonnegative(),
  updated_at: z.string(),
});

export type BenchDetail = z.infer<typeof benchDetailSchema>;
