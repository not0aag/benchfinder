set search_path = public, extensions;

-- State transitions are never client-writable (CLAUDE.md rule 2). Clients call
-- these SECURITY DEFINER functions; the functions decide.

-- Mirror of ALLOWED_TRANSITIONS in packages/domain/src/verificationState.ts.
-- Keep the two in sync; the pgTAP suite asserts this map.
create function public.verification_transition_allowed(
  p_from verification_state,
  p_to verification_state
)
returns boolean
language sql
immutable
as $$
  select case p_from
    when 'unconfirmed' then p_to in ('community', 'confirmed', 'verified', 'disputed')
    when 'community'   then p_to in ('confirmed', 'verified', 'disputed')
    when 'confirmed'   then p_to in ('verified', 'disputed')
    when 'verified'    then p_to in ('disputed')
    when 'disputed'    then p_to in ('unconfirmed', 'community', 'confirmed', 'verified')
  end
$$;

create function public.moderate_bench_status(
  p_bench_id uuid,
  p_status bench_status,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old bench_status;
begin
  if current_user_role() not in ('moderator', 'admin') then
    raise exception 'moderator role required' using errcode = '42501';
  end if;

  select status into v_old from bf_benches where id = p_bench_id for update;
  if not found then
    raise exception 'bench % not found', p_bench_id;
  end if;
  if v_old = p_status then
    return;
  end if;

  perform set_config('benchfinder.state_transition', 'allowed', true);
  update bf_benches set status = p_status where id = p_bench_id;
  perform set_config('benchfinder.state_transition', '', true);

  insert into moderation_events (bench_id, actor_id, action, reason, payload)
  values (
    p_bench_id,
    auth.uid(),
    'status:' || v_old || '->' || p_status,
    p_reason,
    jsonb_build_object('from', v_old, 'to', p_status)
  );
end;
$$;

create function public.set_verification_state(
  p_bench_id uuid,
  p_state verification_state,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old verification_state;
begin
  if current_user_role() not in ('moderator', 'admin') then
    raise exception 'moderator role required' using errcode = '42501';
  end if;

  select verification_state into v_old from bf_benches where id = p_bench_id for update;
  if not found then
    raise exception 'bench % not found', p_bench_id;
  end if;
  if v_old = p_state then
    return;
  end if;
  if not verification_transition_allowed(v_old, p_state) then
    raise exception 'transition % -> % is not allowed', v_old, p_state
      using errcode = '23514';
  end if;

  perform set_config('benchfinder.state_transition', 'allowed', true);
  update bf_benches set verification_state = p_state where id = p_bench_id;
  perform set_config('benchfinder.state_transition', '', true);

  insert into moderation_events (bench_id, actor_id, action, reason, payload)
  values (
    p_bench_id,
    auth.uid(),
    'verification:' || v_old || '->' || p_state,
    p_reason,
    jsonb_build_object('from', v_old, 'to', p_state)
  );
end;
$$;

-- Soft delete only. No DELETE policy exists on bf_benches.
create function public.remove_bench(p_bench_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform moderate_bench_status(p_bench_id, 'removed', p_reason);
end;
$$;

-- Callable by signed-in users only; role checks happen inside.
revoke execute on function public.moderate_bench_status(uuid, bench_status, text) from public, anon;
revoke execute on function public.set_verification_state(uuid, verification_state, text) from public, anon;
revoke execute on function public.remove_bench(uuid, text) from public, anon;
grant execute on function public.moderate_bench_status(uuid, bench_status, text) to authenticated;
grant execute on function public.set_verification_state(uuid, verification_state, text) to authenticated;
grant execute on function public.remove_bench(uuid, text) to authenticated;
