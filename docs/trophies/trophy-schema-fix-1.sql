-- =============================================================================
-- Roll Along — Trophy schema fix 1: let the app record anonymous unlocks
-- =============================================================================
-- STEP ORDER: run AFTER docs/trophies/trophy-schema.sql (and before or after
-- trophy-rollup.sql; it does not depend on it). Safe to run more than once.
--
-- WHY THIS IS NEEDED
--   The app pushed unlocks to public.trophy_unlocks as a PostgREST upsert
--   (?on_conflict=install_id,trophy_id + Prefer: resolution=ignore-duplicates),
--   which PostgREST turns into INSERT ... ON CONFLICT (install_id, trophy_id)
--   DO NOTHING. Postgres requires SELECT privilege on the conflict columns for
--   that statement, and the anon/authenticated roles only have INSERT on this
--   table (by design: it must never be client-readable). Every push was
--   refused with "permission denied for table trophy_unlocks" (42501, HTTP
--   401), so the table stayed empty. Because the app stopped at that first
--   failure, it never went on to write player_trophies either.
--
--   Granting SELECT is not an option: once SELECT is needed, row-level
--   security also requires a SELECT policy that lets the caller see the new
--   row, which would make the table readable.
--
-- THE FIX
--   A small SECURITY DEFINER function the app calls instead
--   (POST /rest/v1/rpc/record_trophy_unlocks). It does the duplicate-safe
--   insert as the table owner, so the table stays insert-only and unreadable
--   for clients. It accepts at most 500 ids per call and skips blank or
--   over-long ids. Returns the number of NEW rows (0 on a replay).
--
--   Nothing in public.player_trophies changes: signed-in players already have
--   the permissions that upsert needs.
-- =============================================================================

create or replace function public.record_trophy_unlocks(
    p_install_id  uuid,
    p_trophy_ids  text[]
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    inserted integer := 0;
begin
    if p_install_id is null or p_trophy_ids is null then
        return 0;
    end if;
    if cardinality(p_trophy_ids) > 500 then
        raise exception 'record_trophy_unlocks: at most 500 trophy ids per call'
            using errcode = '22023';
    end if;

    insert into public.trophy_unlocks (install_id, trophy_id)
    select p_install_id, ids.trophy_id
    from (select distinct unnest(p_trophy_ids) as trophy_id) as ids
    where ids.trophy_id is not null
      and char_length(ids.trophy_id) between 1 and 100
    on conflict (install_id, trophy_id) do nothing;

    get diagnostics inserted = row_count;
    return inserted;
end;
$$;

comment on function public.record_trophy_unlocks(uuid, text[]) is
    'App entry point for the anonymous trophy rail: duplicate-safe insert into trophy_unlocks without making the table client-readable. See TrophySyncService.swift and docs/trophies/trophy-schema-fix-1.sql.';

-- Only the app roles may call it (functions are executable by PUBLIC by default).
revoke all on function public.record_trophy_unlocks(uuid, text[]) from public;
grant execute on function public.record_trophy_unlocks(uuid, text[]) to anon, authenticated;

-- Ask PostgREST to pick up the new function right away.
notify pgrst, 'reload schema';

-- -----------------------------------------------------------------------------
-- CHECK (read-only): expect one row with all three columns = true.
-- -----------------------------------------------------------------------------
-- select
--     p.prosecdef                                                         as is_security_definer,
--     has_function_privilege('anon', p.oid, 'execute')                    as anon_can_call,
--     has_function_privilege('authenticated', p.oid, 'execute')           as authenticated_can_call
-- from pg_proc p
-- join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public' and p.proname = 'record_trophy_unlocks';
