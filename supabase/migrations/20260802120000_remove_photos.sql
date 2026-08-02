set search_path = public, extensions;

-- Photo capture and storage are removed from the product. Contributors submit
-- coordinates plus structured attributes; verification happens in person.
-- See BENCHFINDER_ARCHITECTURE.md sections 5 and 13.

drop trigger bench_photos_aggregate on bench_photos;
drop function public.refresh_bench_photo_count();

-- RLS policies, indexes and grants go with the table.
drop table bench_photos;

-- bench_details depends on photo_count, so the view has to go before the
-- column. Recreated below, minus that one line.
drop view bench_details;

alter table bf_benches drop column photo_count;

create view bench_details
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
  rating_count,
  scenic_avg,
  comfort_avg,
  favorite_count,
  confirm_count,
  dispute_count,
  updated_at
from bf_benches;

grant select on bench_details to anon, authenticated;

-- plpgsql bodies are not dependency-tracked, so dropping the column leaves this
-- function compiling fine and failing at call time. Recreate it now.
create or replace function public.bench_tile(z int, x int, y int)
returns bytea
language plpgsql
stable
set search_path = public, extensions
as $$
declare
  result bytea;
begin
  if z < 0 or z > 22 or x < 0 or y < 0 or x >= (1 << z) or y >= (1 << z) then
    raise exception 'invalid tile coordinates z=% x=% y=%', z, x, y
      using errcode = '22023';
  end if;

  -- bbox test runs in geography so idx_bench_published (GIST) applies;
  -- geometry math happens only on the rows that survive it.
  with bounds as (
    select st_tileenvelope(z, x, y) as geom_3857,
           st_transform(st_tileenvelope(z, x, y), 4326)::geography as geog
  ),
  mvtgeom as (
    select
      st_asmvtgeom(st_transform(b.geom::geometry, 3857), bounds.geom_3857) as geom,
      b.id,
      b.verification_state,
      b.has_backrest,
      b.is_accessible,
      b.condition
    from bf_benches b, bounds
    where b.geom && bounds.geog
      and b.status = 'published'
      and b.min_zoom <= greatest(z, 10) -- below z10 the z10 sample still shows
  )
  select st_asmvt(mvtgeom.*, 'benches') into result from mvtgeom;

  return result;
end;
$$;
