set search_path = public, extensions;

create or replace view bench_details
with (security_invoker = true)
as
select
  id,
  st_y(geom::geometry) as lat,
  st_x(geom::geometry) as lon,
  origin,
  source_osm_id,
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
