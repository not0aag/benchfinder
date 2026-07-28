set search_path = public, extensions;

-- Vector tile generation (arch doc section 3). SECURITY INVOKER: callers see
-- only what their RLS allows, and the status filter matches the anon policy,
-- so the function grants nothing extra.
create function public.bench_tile(z int, x int, y int)
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
      b.condition,
      b.photo_count
    from bf_benches b, bounds
    where b.geom && bounds.geog
      and b.status = 'published'
      and b.min_zoom <= greatest(z, 10) -- below z10 the z10 sample still shows
  )
  select st_asmvt(mvtgeom.*, 'benches') into result from mvtgeom;

  return result;
end;
$$;

grant execute on function public.bench_tile(int, int, int) to anon, authenticated;

-- Level-of-detail thinning: min_zoom 14 shows everything; zooms 13 down to 10
-- keep one representative bench per grid cell, and each level's sample is a
-- subset of the level below, so benches never pop out while zooming in.
-- Deterministic (order by id). Run after every import; nightly on hosted.
create function public.compute_bench_min_zoom()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  lvl int;
  cell double precision;
begin
  update bf_benches set min_zoom = 14 where min_zoom <> 14;

  for lvl in reverse 13 .. 10 loop
    -- roughly four representatives per tile edge at each zoom
    cell := 360.0 / (power(2, lvl) * 4);
    update bf_benches b
    set min_zoom = lvl
    where b.id in (
      select distinct on (st_snaptogrid(b2.geom::geometry, cell)) b2.id
      from bf_benches b2
      where b2.status = 'published'
        and b2.min_zoom = lvl + 1
      order by st_snaptogrid(b2.geom::geometry, cell), b2.id
    );
  end loop;
end;
$$;

revoke execute on function public.compute_bench_min_zoom() from public, anon, authenticated;
