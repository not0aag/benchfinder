set search_path = public, extensions;

-- Aggregates on bf_benches are trigger-maintained (never computed on read).
-- Functions are SECURITY DEFINER because the writing user has no RLS
-- permission to update bf_benches; the recompute must not depend on that.

create function public.refresh_bench_photo_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bench uuid := coalesce(new.bench_id, old.bench_id);
begin
  update bf_benches b
  set photo_count = (select count(*) from bench_photos p where p.bench_id = v_bench)
  where b.id = v_bench;
  return null;
end;
$$;

create trigger bench_photos_aggregate
  after insert or update or delete on bench_photos
  for each row execute function public.refresh_bench_photo_count();

create function public.refresh_bench_ratings()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bench uuid := coalesce(new.bench_id, old.bench_id);
begin
  update bf_benches b
  set rating_count = agg.n,
      scenic_avg   = agg.scenic,
      comfort_avg  = agg.comfort
  from (
    select count(*) as n,
           round(avg(r.scenic), 2)  as scenic,
           round(avg(r.comfort), 2) as comfort
    from bench_ratings r
    where r.bench_id = v_bench
  ) agg
  where b.id = v_bench;
  return null;
end;
$$;

create trigger bench_ratings_aggregate
  after insert or update or delete on bench_ratings
  for each row execute function public.refresh_bench_ratings();

create function public.refresh_bench_favorite_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bench uuid := coalesce(new.bench_id, old.bench_id);
begin
  update bf_benches b
  set favorite_count = (select count(*) from bench_favorites f where f.bench_id = v_bench)
  where b.id = v_bench;
  return null;
end;
$$;

create trigger bench_favorites_aggregate
  after insert or delete on bench_favorites
  for each row execute function public.refresh_bench_favorite_count();

create function public.refresh_bench_confirmations()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bench uuid := coalesce(new.bench_id, old.bench_id);
begin
  update bf_benches b
  set confirm_count = agg.confirms,
      dispute_count = agg.disputes
  from (
    select count(*) filter (where c.present)     as confirms,
           count(*) filter (where not c.present) as disputes
    from bench_confirmations c
    where c.bench_id = v_bench
  ) agg
  where b.id = v_bench;
  return null;
end;
$$;

create trigger bench_confirmations_aggregate
  after insert or update or delete on bench_confirmations
  for each row execute function public.refresh_bench_confirmations();
