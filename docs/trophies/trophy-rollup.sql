-- =============================================================================
-- Roll Along — Trophy rarity ROLLUP job (S3-T2)
-- =============================================================================
-- ⚠️ AUTHORED FOR MAC TO APPLY — not yet deployed.  Nothing in this file has
--    been run against any Supabase project (live project ref
--    mhwpcwauzvmtmuphtajs).  This is the DDL/function copy the sprint plan
--    (S3-T2) requires to live in docs/trophies/; scheduling it (pg_cron job
--    or edge-function cron) is MAC'S deploy step.  See "DEPLOY (Mac's step)".
--
-- Depends on docs/trophies/trophy-schema.sql (S3-T1): the three objects
--   public.trophy_unlocks / public.player_trophies / public.trophy_stats.
-- Apply trophy-schema.sql FIRST, then this file.  Idempotent: safe to re-run.
-- =============================================================================
--
-- WHAT THIS DOES (design.md §3, sprint-plan.md §2 S3-T2):
--   Recomputes, per trophy, the rarity aggregate written into public.trophy_stats:
--     • earned_count = distinct installs that unlocked the trophy, counted from
--       public.trophy_unlocks — the ANONYMOUS rarity rail, NEVER player_trophies.
--     • denominator  = distinct install UUIDs that have booted the game, counted
--       from public.events app_launch rows — the SAME id rail as the numerator
--       (trophy_unlocks.install_id == events.user_id), so numerator and
--       denominator can never diverge across the two identity systems that
--       deliberately never join (analytics user_id ≠ auth.uid()).
--     • pct = earned_count / denominator (0 when denominator = 0).
--   Runs DAILY (design.md §3 "Update cadence"); the client caches the last
--   fetched stats and renders stale data gracefully (rarity is a garnish).
--
-- INCREMENT-ONLY / SURVIVES ACCOUNT DELETION (research internal-data-backend.md
-- §6.3 recommendation (b); design.md §4):
--   Both the numerator and the denominator are read from ANONYMOUS, install-
--   scoped rails (trophy_unlocks, events) that carry no auth linkage and are
--   NEVER touched by the delete-account cascade (which only tears down
--   player_trophies + the player's social rows).  Therefore deleting a player
--   CANNOT decrement trophy_stats: the fact that *some install* earned a trophy
--   survives, exactly like PSN and exactly like today's events rows.  The rollup
--   is a full recompute (not a running delta), so it is inherently idempotent
--   and self-correcting — re-running it never double-counts.  earned_count only
--   ever rises as new distinct installs unlock a trophy; it can dip only if
--   trophy_unlocks rows are physically purged (a deliberate operator action —
--   e.g. the S4-T4 beta re-baseline), never as a side effect of account or data
--   deletion.
--
-- DOUBLE-COUNT CAVEATS (design.md §3, backend §5 — accepted, documented):
--   The install-UUID rail is the closest analogue to PSN's "owners who booted
--   the game," but it is not a person count:
--     • Reinstall on the same device regenerates the analytics UUID → the same
--       human counts as a NEW install in BOTH numerator and denominator.
--     • A multi-device player counts once per device in BOTH.
--     • An offline-forever install never reaches the server → counted in NEITHER.
--   Because the SAME rail feeds numerator and denominator, these biases are
--   SYMMETRIC and the *ratio* stays sane (a reinstaller who re-earns the trophy
--   adds 1 to both earned_count and denominator).  A reinstaller who does NOT
--   re-earn adds 1 to the denominator only, nudging pct DOWN — acceptable noise
--   for a cosmetic garnish, and the reason rarity never drives gameplay/reward
--   (design.md §3 "Never hard-code any gameplay ... to a live rarity number").
--
-- COLD-START (design.md §3 / decision #6):  pct is only MEANINGFUL once the
--   denominator ≥ 500 distinct installs AND ≥ 30 days post-launch.  This rollup
--   still WRITES the real numbers every day (so the table is warm the instant
--   the gate opens); suppression is enforced at DISPLAY (S3-T4) AND surfaced
--   here as a computed boolean column note (see trophy_stats_rollup_meta below)
--   so the client needs a single fetch to know whether to render.  The rollup
--   never fabricates or zeroes numbers to "hide" them — hiding is the client's
--   job; the rollup's job is to keep the counts correct.
--
-- ANTI-SPAM / RATE PLAUSIBILITY (design.md §10 — the aggregate is spam-resistant,
--   not cheat-proof):  the UNIQUE (install_id, trophy_id) constraint on
--   trophy_unlocks already collapses a spamming install to one row per trophy,
--   so no single install can inflate earned_count past 1.  A rate-plausibility
--   filter (an install that unlocked the ENTIRE catalog within seconds of its
--   first launch) is left as an OPTIONAL numerator refinement below, disabled by
--   default — cosmetic status is client-trusted by design and no money/gameplay
--   advantage is at stake, so the plain count ships in v1.
--
-- BETA-TRAFFIC NOTE (sprint-plan.md S4-T4):  beta installs hit the same rails.
--   Before public launch, either (a) tag beta installs and exclude them here, or
--   (b) truncate trophy_unlocks and re-baseline.  A commented exclusion hook is
--   provided (see "BETA EXCLUSION HOOK") for option (a); the decision is S4-T4's.
-- =============================================================================


-- =============================================================================
-- 0. Launch-date anchor for the 30-day cold-start gate.
-- =============================================================================
-- The 30-day half of the cold-start rule needs a fixed "public launch" instant.
-- We do NOT derive it from min(events.created_at): the analytics rail predates
-- public launch (internal-testing / TestFlight rows), so the earliest event is
-- not launch day and would open the 30-day gate too early.  Store it explicitly
-- as a one-row config the operator sets at launch; the rollup reads it.
--
-- Until Mac sets a real launch_at, the row defaults to a FAR-FUTURE sentinel so
-- the 30-day gate stays CLOSED (fail-safe: cold-start suppressed) rather than
-- accidentally open.  (design.md §3: day-1 percentages are noise — suppress.)
create table if not exists public.trophy_rollup_config (
    id             boolean     primary key default true,   -- single-row guard
    -- The public-launch instant.  The 30-day cold-start gate opens at
    -- launch_at + interval '30 days'.  Operator sets this at App Store launch.
    launch_at      timestamptz not null default 'infinity',
    -- Cold-start thresholds (design.md decision #6).  Stored so they are tunable
    -- without editing the function body (D9 lets Mac adjust at freeze).
    min_installs   bigint      not null default 500,
    min_days       int         not null default 30,
    constraint trophy_rollup_config_singleton check (id = true),
    constraint trophy_rollup_config_min_installs_nonneg check (min_installs >= 0),
    constraint trophy_rollup_config_min_days_nonneg     check (min_days >= 0)
);

comment on table public.trophy_rollup_config is
    'Single-row config for the rarity rollup (S3-T2). launch_at anchors the 30-day cold-start gate; min_installs/min_days are the design.md decision #6 thresholds. Operator (Mac) sets launch_at at public launch; defaults keep the gate CLOSED.';

-- Seed the singleton row if absent (leaves an existing row untouched — its
-- launch_at/thresholds are operator-owned).
insert into public.trophy_rollup_config (id)
values (true)
on conflict (id) do nothing;

-- RLS: config is service_role-only (like the rollup itself).  No client grants.
alter table public.trophy_rollup_config enable row level security;
-- (No policies → no client role can read or write it; service_role bypasses RLS.)


-- =============================================================================
-- 1. Add the rollup-meta columns to trophy_stats (idempotent ALTERs).
-- =============================================================================
-- rarity_ready is the single boolean the client (S3-T4) reads to decide whether
-- to render a band at all: TRUE only when BOTH cold-start conditions hold.
-- Computed once per rollup pass (same for every row in a pass) so the client
-- needs no second query and no clock of its own.
alter table public.trophy_stats
    add column if not exists rarity_ready boolean not null default false;

comment on column public.trophy_stats.rarity_ready is
    'Cold-start gate (design.md §3 / decision #6): TRUE only when denominator >= min_installs AND now() >= launch_at + min_days. The client (S3-T4) shows a rarity band ONLY when this is true (AND is_paused is false). Written by the daily rollup; same value for every row in a pass.';


-- =============================================================================
-- 2. The rollup function.  Runs as SECURITY DEFINER (owner = a role that can
--    read trophy_unlocks/events and write trophy_stats — i.e. the migration
--    owner / postgres).  Scheduled DAILY (see "DEPLOY" below).
-- =============================================================================
-- Full recompute, single statement, wrapped in a function so the scheduler has
-- one entry point and the logic lives in the DB (versioned here, not in cron).
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
    select count(distinct user_id)
      into v_denominator
      from public.events
     where event_name = 'app_launch';

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

comment on function public.rollup_trophy_stats() is
    'Daily rarity rollup (S3-T2). Recomputes trophy_stats from trophy_unlocks (anon numerator) over distinct app_launch install UUIDs (denominator, same id rail). Increment-only / survives account deletion; is_paused untouched; cold-start gate written to rarity_ready. Run daily via pg_cron or an edge-function cron.';

-- Lock the function down: only service_role (the scheduler / admin) may execute
-- it.  No client role can trigger a recompute.
revoke all on function public.rollup_trophy_stats() from public;
revoke all on function public.rollup_trophy_stats() from anon;
revoke all on function public.rollup_trophy_stats() from authenticated;
grant execute on function public.rollup_trophy_stats() to service_role;


-- =============================================================================
-- 3. DEPLOY (Mac's step — NOT run by this file).
-- =============================================================================
-- The function above is the whole rollup; scheduling it is a separate operator
-- action.  Pick ONE of the two cadence mechanisms.  Both run DAILY.
--
-- OPTION A — pg_cron (recommended; zero extra infra, runs in-database):
--   1) Enable the extension once (Supabase: Database → Extensions → enable
--      "pg_cron", or SQL):
--         create extension if not exists pg_cron;
--   2) Schedule a daily run (03:17 UTC chosen to avoid top-of-hour contention;
--      any low-traffic time is fine — rarity is a garnish, timing is not
--      load-bearing):
--         select cron.schedule(
--             'rollup-trophy-stats-daily',
--             '17 3 * * *',                     -- daily 03:17 UTC
--             $cron$ select public.rollup_trophy_stats(); $cron$
--         );
--   3) Inspect / change / remove later:
--         select * from cron.job where jobname = 'rollup-trophy-stats-daily';
--         select cron.unschedule('rollup-trophy-stats-daily');
--   (pg_cron runs as the job's owner; ensure the owner can execute the function
--   — the migration owner / postgres does.  SECURITY DEFINER above means the
--   function itself runs with its definer's rights regardless.)
--
-- OPTION B — Supabase Edge Function on a schedule (if Mac prefers the function
-- layer, e.g. to add alerting):  deploy a tiny edge function that calls the RPC
-- with the service_role key, and schedule it with Supabase's cron (or an
-- external scheduler).  Reference edge-function body (Deno / TypeScript):
--
--     // supabase/functions/rollup-trophy-stats/index.ts
--     import { createClient } from "jsr:@supabase/supabase-js@2";
--     Deno.serve(async () => {
--       const supabase = createClient(
--         Deno.env.get("SUPABASE_URL")!,
--         Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,   // service_role: bypasses RLS
--       );
--       const { error } = await supabase.rpc("rollup_trophy_stats");
--       if (error) {
--         console.error("rollup_trophy_stats failed:", error.message);
--         return new Response(error.message, { status: 500 });
--       }
--       return new Response("ok", { status: 200 });
--     });
--
--   Then schedule it daily (Supabase Dashboard → Edge Functions → Cron, or
--   `supabase functions deploy rollup-trophy-stats` + a cron trigger).  The
--   pg_cron path (Option A) is simpler and has no cold-start latency; prefer it
--   unless edge-function tooling/alerting is wanted.
--
-- ONE-OFF MANUAL RUN (any option; run as service_role in the SQL Editor):
--     select public.rollup_trophy_stats();
--
-- LAUNCH-DAY OPERATOR STEP (do NOT skip — the 30-day gate stays CLOSED until):
--     update public.trophy_rollup_config set launch_at = now() where id = true;
--   (or the actual public-launch timestamp).  Until this is set, rarity_ready
--   is always false and the client shows "Rarity coming soon" — the safe
--   default.


-- =============================================================================
-- 4. Verification queries (run with service_role — the rollup's own inputs).
-- =============================================================================
-- Denominator (must match the rollup's v_denominator):
--   select count(distinct user_id) from public.events where event_name = 'app_launch';
--
-- Numerator per trophy (must match trophy_stats.earned_count after a rollup):
--   select trophy_id, count(distinct install_id) as earned_count
--   from public.trophy_unlocks group by trophy_id order by earned_count desc;
--
-- Full aggregate after a run:
--   select trophy_id, earned_count, denominator, pct, rarity_ready, is_paused,
--          updated_at
--   from public.trophy_stats order by pct;
--
-- Cold-start readiness right now:
--   select (select count(distinct user_id) from public.events
--            where event_name = 'app_launch') as installs,
--          launch_at, min_installs, min_days,
--          now() >= launch_at + make_interval(days => min_days) as day_gate_open
--   from public.trophy_rollup_config where id = true;
--
-- Proof that deleting a player does NOT decrement trophy_stats:
--   trophy_stats derives ONLY from trophy_unlocks (no FK to players) and events
--   (no FK to players); the delete-account cascade touches neither.  Delete a
--   player, re-run rollup_trophy_stats(), and every earned_count/denominator is
--   unchanged.  (S3-T5 / S3-T7 exercise this against a dev branch.)
-- =============================================================================
