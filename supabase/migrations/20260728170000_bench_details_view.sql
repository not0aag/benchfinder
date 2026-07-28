set search_path = public, extensions;

-- Client-facing read model for the detail sheet: geography unpacked to
-- lat/lon. security_invoker so RLS on bf_benches decides visibility.
create view bench_details
with (security_invoker = true)
as
select
  id,
  st_y(geom::geometry) as lat,
  st_x(geom::geometry) as lon,
  verification_state,
  has_backrest,
  has_armrests,
  has_table,
  is_accessible,
  has_shade,
  is_lit,
  material,
  condition,
  seats,
  facing_degrees,
  description,
  photo_count,
  rating_count,
  scenic_avg,
  comfort_avg,
  favorite_count,
  confirm_count,
  dispute_count,
  updated_at
from bf_benches;

grant select on bench_details to anon, authenticated;
