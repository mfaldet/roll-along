-- =============================================================================
-- STEP 20 — Analytics retention: delete raw events older than 90 days, daily.
-- =============================================================================
-- Run AFTER steps 18 and 19.  Safe to run more than once.  Requires pg_cron
-- (already enabled live: social-schedule.sql and the trophy rollup use it).
--
-- WHY THERE IS MORE HERE THAN A DELETE
--   Only one thing needed raw events older than 90 days: the daily trophy
--   rarity rollup (public.rollup_trophy_stats, step 2).  Its denominator was
--   "every install that has EVER sent app_launch", counted from raw events.
--   Pruning would shrink that count to recent installs while the numerator
--   (trophy_unlocks) keeps every install ever — rarity would inflate.  So this
--   step adds a small permanent table, public.analytics_installs (one row per
--   install: first and last launch), backfills it from today's events, and
--   points the rollup at it.  Nothing else in the app or the database reads
--   raw events older than 90 days (the app only INSERTs events; the
--   soft-launch metrics use 14-day windows, except the install-day cohort,
--   which now uses analytics_installs.first_seen — see soft-launch-metrics.sql).
--
-- SCHEDULE
--   rollup-trophy-stats-daily  03:17 UTC (existing)
--   ra-prune-events            03:47 UTC (new; 10:47 PM Eastern standard time,
--                              11:47 PM daylight time — a quiet hour)
--   The prune also refreshes analytics_installs first, so no launch is lost
--   even if the rollup ever fails to run.
--
-- SIZE NOTE: ~360 bytes/event.  Deletes run in batches of 20,000 rows so a
--   large backlog never holds one long transaction.
-- =============================================================================

-- 1. Permanent install list (service-only; never readable or writable by the app)
create table if not exists public.analytics_installs (
    user_id    uuid        primary key,
    first_seen timestamptz not null,
    last_seen  timestamptz not null
);
alter table public.analytics_installs enable row level security;
revoke all on public.analytics_installs from anon, authenticated;
comment on table public.analytics_installs is
    'One row per install (events.user_id) that ever sent app_launch: first and last launch. Kept forever; raw events are pruned after 90 days (step 20). Trophy rarity denominator.';

-- 2. Refresh function: fold app_launch events into the install list
create or replace function public.ra_record_installs()
returns void
language sql
security definer
set search_path = public
as $fn$
    insert into public.analytics_installs (user_id, first_seen, last_seen)
    select user_id, min(created_at), max(created_at)
      from public.events
     where event_name = 'app_launch'
     group by user_id
    on conflict (user_id) do update
        set first_seen = least(analytics_installs.first_seen, excluded.first_seen),
            last_seen  = greatest(analytics_installs.last_seen, excluded.last_seen);
$fn$;
revoke all on function public.ra_record_installs() from public, anon, authenticated;

-- 3. Backfill from every event that exists today (before any pruning)
select public.ra_record_installs();

-- 4. Rollup: denominator from analytics_installs (body otherwise unchanged)
create or replace function public.rollup_trophy_stats()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_denominator  bigint;
    v_launch_at    timestamptz;
    v_min_installs bigint;
    v_min_days     int;
    v_ready        boolean;
begin
    -- --- config -------------------------------------------------------------
    select launch_at, min_installs, min_days
      into v_launch_at, v_min_installs, v_min_days
      from public.trophy_rollup_config
     where id = true;

    -- Defensive: if the config row is somehow missing, fall back to the design
    -- defaults and a CLOSED 30-day gate (suppress, never over-expose).
    if not found then
        v_launch_at    := 'infinity';
        v_min_installs := 500;
        v_min_days     := 30;
    end if;

    -- --- denominator --------------------------------------------------------
    -- (Was: distinct app_launch user_ids from public.events — see step 20.)
    -- Distinct install UUIDs that have BOOTED the game (design.md §3): the
    -- app_launch rows on the analytics rail.  SAME id rail as the numerator
    -- (events.user_id == trophy_unlocks.install_id).  Every install fires
    -- app_launch on launch, so this is the canonical "owners who booted the
    -- game" count; filtering to app_launch (vs any-event) excludes the rare
    -- install whose only surviving row is a buffered non-launch event.
    --
    -- BETA EXCLUSION HOOK (S4-T4 option (a)): to exclude tagged beta installs,
    -- add here e.g.  and app_version not like '%-beta'  (or a build-tag filter),
    -- and mirror the same filter in the numerator CTE below.  Off by default.
    -- Step 20: the denominator now comes from public.analytics_installs, the
    -- permanent list of installs that have ever launched the app, instead of
    -- raw events (which are pruned after 90 days).  Refresh it first so
    -- today's new installs count.
    perform public.ra_record_installs();
    select count(*)
      into v_denominator
      from public.analytics_installs;

    -- --- cold-start gate ----------------------------------------------------
    -- Meaningful ONLY when BOTH hold (design.md decision #6).  Computed once;
    -- written to every row so the client reads a single flag.
    v_ready := (v_denominator >= v_min_installs)
               and (now() >= v_launch_at + make_interval(days => v_min_days));

    -- --- numerator + upsert -------------------------------------------------
    -- earned_count per trophy from the ANONYMOUS rail (trophy_unlocks), NEVER
    -- player_trophies.  count(distinct install_id) is belt-and-suspenders — the
    -- UNIQUE (install_id, trophy_id) constraint already guarantees one row per
    -- (install, trophy), so a plain count() would match; distinct makes the
    -- intent explicit and stays correct even if the constraint is ever relaxed.
    with counts as (
        select trophy_id,
               count(distinct install_id) as earned_count
          from public.trophy_unlocks
         -- BETA EXCLUSION HOOK: mirror the denominator's filter here (e.g. join
         -- to a beta-install list on install_id) if S4-T4 picks option (a).
         group by trophy_id
    )
    insert into public.trophy_stats
        (trophy_id, earned_count, denominator, pct, rarity_ready, updated_at)
    select
        c.trophy_id,
        -- Clamp earned_count to the denominator INLINE.  The
        -- trophy_stats_earned_le_denom CHECK (earned_count <= denominator) is a
        -- non-deferred row constraint enforced the instant this INSERT runs, so
        -- the clamp MUST happen here — a follow-up UPDATE would be too late (the
        -- INSERT would already have aborted).  The transient race it guards:
        -- a trophy_unlocks row exists for an install whose app_launch row hasn't
        -- landed yet, so earned_count could momentarily exceed the denominator.
        -- least(...) keeps the CHECK satisfied; the next daily pass self-corrects
        -- once the app_launch row catches up.
        least(c.earned_count, v_denominator),
        v_denominator,
        -- Guard the divide; clamp to [0,1] for the trophy_stats_pct_range CHECK
        -- (same race).  Uses the same clamped numerator as earned_count.
        case when v_denominator = 0 then 0
             else least(c.earned_count, v_denominator)::double precision
                  / v_denominator
        end,
        v_ready,
        now()
    from counts c
    on conflict (trophy_id) do update
        set earned_count = excluded.earned_count,  -- already clamped above
            denominator  = excluded.denominator,
            pct          = excluded.pct,
            rarity_ready = excluded.rarity_ready,
            updated_at   = excluded.updated_at;
        -- NB: is_paused is DELIBERATELY NOT written by the rollup — it is an
        -- operator-set DISPLAY kill-switch (design.md §9), not a computed value.
        -- The rollup owns counts/denominator/pct/rarity_ready/updated_at only.
        --
        -- INCREMENT-ONLY GUARANTEE is STRUCTURAL, not a refusal-to-decrement:
        -- this is a faithful full recompute of the CURRENT trophy_unlocks state,
        -- so earned_count exactly mirrors the anon rail every pass.  It never
        -- drops on account deletion because the delete-account cascade removes
        -- ZERO trophy_unlocks rows (that table has no FK to players) — so the
        -- numerator the recompute reads is unchanged by any deletion.  A trophy
        -- CAN read 0 again only if its trophy_unlocks rows are physically purged
        -- (a deliberate operator action — the S4-T4 beta re-baseline), which is
        -- exactly when re-baselining to the current rail IS the desired result.
        -- A trophy with no current unlock rows produces no counts row, so its
        -- pre-existing trophy_stats row is left as-is by this upsert; the
        -- re-baseline path (S4-T4 option b) truncates/zeroes trophy_stats
        -- explicitly, it does not rely on the rollup to lower a stale row.
end;
$$;

revoke all on function public.rollup_trophy_stats() from public, anon, authenticated;

-- 5. Prune function: refresh installs, then delete old events in batches
create or replace function public.ra_prune_events(p_keep_days int default 90)
returns bigint
language plpgsql
security definer
set search_path = public
as $fn$
declare
    v_cutoff  timestamptz := now() - make_interval(days => greatest(p_keep_days, 30));
    v_batch   bigint;
    v_total   bigint := 0;
begin
    perform public.ra_record_installs();
    loop
        delete from public.events
         where id in (select id from public.events
                       where created_at < v_cutoff
                       limit 20000);
        get diagnostics v_batch = row_count;
        v_total := v_total + v_batch;
        exit when v_batch = 0;
    end loop;
    return v_total;
end;
$fn$;
revoke all on function public.ra_prune_events(int) from public, anon, authenticated;
comment on function public.ra_prune_events(int) is
    'Daily analytics retention (step 20): records installs, then deletes events older than p_keep_days (default 90, never fewer than 30). Returns rows deleted.';

-- 6. Schedule daily at 03:47 UTC, after the 03:17 trophy rollup
do $do$
begin
    if exists (select 1 from cron.job where jobname = 'ra-prune-events') then
        perform cron.unschedule('ra-prune-events');
    end if;
    perform cron.schedule('ra-prune-events', '47 3 * * *',
                          'select public.ra_prune_events(90);');
end;
$do$;

-- 7. Prune once now so the check below holds immediately
select public.ra_prune_events(90);

-- =============================================================================
-- CHECK — every column should be true.
-- =============================================================================
-- select
--   (select relrowsecurity from pg_class where oid = 'public.analytics_installs'::regclass)      as installs_rls_on,
--   not has_table_privilege('anon', 'public.analytics_installs', 'select')
--     and not has_table_privilege('authenticated', 'public.analytics_installs', 'select')        as installs_not_client_readable,
--   (select count(*) from public.analytics_installs)
--     >= (select count(distinct user_id) from public.events where event_name = 'app_launch')      as installs_cover_events,
--   position('analytics_installs' in pg_get_functiondef('public.rollup_trophy_stats()'::regprocedure)) > 0
--                                                                                                  as rollup_uses_installs,
--   exists (select 1 from cron.job where jobname = 'ra-prune-events' and schedule = '47 3 * * *') as prune_scheduled,
--   not exists (select 1 from public.events where created_at < now() - interval '90 days')         as no_events_older_than_90_days;
