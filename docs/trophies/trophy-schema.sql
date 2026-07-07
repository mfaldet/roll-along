-- =============================================================================
-- Roll Along — Trophy backend schema (rarity + showcase rails)
-- =============================================================================
-- ⚠️ AUTHORED FOR MAC TO APPLY — not yet migrated; prod apply needs Mac's
--    explicit OK.  Nothing in this file has been run against any Supabase
--    project (live project ref mhwpcwauzvmtmuphtajs).  This is the DDL copy
--    the sprint plan (S3-T1) requires to live in docs/trophies/; the managed
--    migration is Mac's step.
-- =============================================================================
--
-- Idempotent: safe to re-run.  Paste the whole file into Supabase's SQL Editor
-- (Project → SQL Editor → New query → paste → Run) OR apply as a managed
-- migration.  Mirrors the house style of docs/supabase-schema.sql (analytics)
-- and docs/social-schema.sql (social): drop-and-recreate policies, explicit
-- grants, `create ... if not exists`.
--
-- WHY THREE OBJECTS (design.md §4 Option C — the hybrid architecture Mac ruled
-- 2026-07-07):
--
--   1. public.trophy_unlocks  — the ANONYMOUS rarity rail.  One row per
--      (install, trophy).  INSERT-only for both anon and authenticated
--      (every player, signed-in or not, counts toward rarity); NEVER readable
--      by a client.  Keyed by the SAME anonymous install UUID the analytics
--      `events` table already uses (events.user_id — a device-install UUID in
--      UserDefaults, no PII).  This is the numerator rail for rarity.
--
--   2. public.player_trophies — the SIGNED-IN showcase rail.  FK → players
--      ON DELETE CASCADE, so account deletion removes a player's personal
--      trophy rows (personal data) while the anonymous counts in (1) survive
--      — exactly like `events` today, and exactly like PSN.  Own-row write,
--      readable by any authenticated user (public-profile showcase, S3-T9).
--
--   3. public.trophy_stats    — the counts-only aggregate.  The project's
--      FIRST anon-READABLE object (an explicit RLS decision, design.md §4 /
--      decision #13 / internal-data-backend.md §6).  Exposes aggregates only
--      (earned_count / denominator / pct / is_paused), NEVER raw unlock rows.
--      Written by the scheduled rollup job (S3-T2), read by the Trophy Room.
--
-- IDENTITY & PRIVACY POSTURE (do not weaken without a ruling):
--   • trophy_unlocks carries NO PII and NO account linkage — it is
--     install-scoped only (install_id = the anonymous analytics UUID).  anon
--     may INSERT it but may NEVER SELECT/UPDATE/DELETE it.
--   • trophy_stats exposes counts / percentages only — never raw unlock rows.
--   • player_trophies is the only trophy object linked to an identity
--     (player_id = auth.uid()); it cascades away on account deletion.
--
-- DENOMINATOR NOTE (design.md §3 / decision #5): rarity's denominator is the
-- count of DISTINCT install UUIDs on the analytics rail
-- (`select count(distinct user_id) from public.events`) — the SAME UUID rail
-- as trophy_unlocks.install_id, so numerator and denominator can never diverge
-- across the two identity systems that deliberately never join.  The rollup
-- job (S3-T2, authored separately) writes that number into
-- trophy_stats.denominator; this schema only stores it.
--
-- ANTI-CHEAT (design.md §10): client-trusted by design — cosmetic status and
-- percentages only, no money or gameplay advantage at stake.  The aggregate is
-- kept spam-resistant (not cheat-proof): the UNIQUE (install_id, trophy_id)
-- constraint makes a re-insert a no-op (idempotent snapshot upsert), and the
-- server-side `unlocked_at DEFAULT now()` ignores client clocks for counting.
-- Rate-plausibility exclusion (an install unlocking the whole catalog in a
-- minute) lives in the rollup job, not here.
--
-- COLD-START (design.md §3 / decision #6): rarity is SUPPRESSED until the
-- denominator reaches 500 distinct installs AND 30 days post-launch.  That is
-- a CLIENT display rule (S3-T4) plus a rollup gate (S3-T2); trophy_stats just
-- holds whatever the rollup last wrote.  `is_paused` is the separate per-trophy
-- display kill-switch (design.md §9) for a single glitched trophy.
-- =============================================================================

-- uuid_generate_v4() (already enabled in default Supabase projects; kept for
-- standalone runs — matches supabase-schema.sql / social-schema.sql).
create extension if not exists "uuid-ossp";

-- =============================================================================
-- Table: public.trophy_unlocks  — ANONYMOUS rarity rail (the numerator).
-- =============================================================================
-- One row per (install, trophy).  INSERT-only for clients; the rollup job runs
-- as service_role and reads it.  The client pushes an idempotent full snapshot
-- of all unlocked ids (S3-T3): "here are ALL my unlocked ids", with
-- `ON CONFLICT (install_id, trophy_id) DO NOTHING`.  The UNIQUE constraint
-- makes every re-insert a no-op, so replaying the snapshot is safe.
create table if not exists public.trophy_unlocks (
    id           uuid        primary key default uuid_generate_v4(),

    -- Anonymous device-install UUID — the SAME id as public.events.user_id
    -- (persisted in UserDefaults, no PII).  This is the rarity numerator's key
    -- and shares the denominator's rail (distinct install UUIDs from events).
    install_id   uuid        not null,

    -- Stable, GC-legal trophy id from the bundled TrophyCatalog.json
    -- (e.g. 'climb_first_clear').  Text, not an FK — the catalog is bundled
    -- client-side content, never a DB table (design.md §9, LevelOverrides
    -- pattern), so there is no players-style parent row to reference.
    trophy_id    text        not null,

    -- SERVER-SIDE timestamp.  Client clocks are ignored for counting
    -- (design.md §10); the client's local unlock time lives on-device.
    unlocked_at  timestamptz not null default now(),

    -- Idempotency + anti-spam: one row per (install, trophy).  Makes the
    -- snapshot upsert a no-op on replay.
    constraint trophy_unlocks_unique_install_trophy unique (install_id, trophy_id),

    -- Sanity: trophy ids are short kebab-case strings; GC caps ids at 100 chars.
    constraint trophy_unlocks_trophy_id_len check (char_length(trophy_id) between 1 and 100)
);

comment on table public.trophy_unlocks is
    'ANONYMOUS trophy-unlock facts, one row per (install_id, trophy_id). INSERT-only for clients; never client-readable. Rarity numerator; install_id = public.events.user_id (anonymous, no PII). See TrophySyncService.swift.';
comment on column public.trophy_unlocks.install_id is
    'Anonymous device-install UUID — same id as public.events.user_id (UserDefaults, no PII). Rarity numerator + shares the denominator rail.';
comment on column public.trophy_unlocks.trophy_id is
    'Stable GC-legal id from bundled TrophyCatalog.json (e.g. climb_first_clear). Not an FK — the catalog is client-bundled content.';

-- Rollup job groups by trophy_id to compute earned_count — index it.
create index if not exists trophy_unlocks_trophy_id_idx
    on public.trophy_unlocks (trophy_id);

-- =============================================================================
-- Table: public.player_trophies  — SIGNED-IN showcase rail.
-- =============================================================================
-- FK → players ON DELETE CASCADE: account deletion removes these rows (personal
-- data) while trophy_unlocks (anonymous counts) survives.  Powers the
-- public-profile showcase (S3-T9).  Own-row write; readable by any signed-in
-- user so a friend's profile renders.
create table if not exists public.player_trophies (
    player_id    uuid        not null
                 references public.players (id) on delete cascade,
    trophy_id    text        not null,
    unlocked_at  timestamptz not null default now(),

    -- One row per (player, trophy); makes the signed-in snapshot upsert
    -- idempotent (ON CONFLICT (player_id, trophy_id) DO NOTHING).
    primary key (player_id, trophy_id),

    constraint player_trophies_trophy_id_len check (char_length(trophy_id) between 1 and 100)
);

comment on table public.player_trophies is
    'SIGNED-IN trophy rows, FK → players ON DELETE CASCADE. Own-row write, readable by authenticated. Powers public-profile showcase. Linked to identity (player_id = auth.uid()); cascades on account deletion.';

-- Showcase / restore-on-sign-in reads a player''s full set — the PK's leading
-- player_id column already covers (player_id) lookups, so no extra index needed.

-- =============================================================================
-- Table: public.player_showcase  — the CURATED public showcase (S3-T9).
-- =============================================================================
-- A small, curated PUBLIC projection of a signed-in player's trophies — NOT
-- their raw unlock rows.  design.md §7 "Profile showcase" / decision #10 (D6,
-- ruled 2026-07-07: on for signed-in, Settings toggle):
--   • per-grade counts (bronze…platinum earned tallies) + overall earned/total,
--   • up to 3 showcased trophy ids (player-chosen; client default = rarest
--     earned), stored as a text[] so PublicProfileView renders the grade
--     glyphs without a second query,
--   • the capstone (Platinum) flag for the crown highlight.
--
-- WHY A SEPARATE TABLE (not columns on player_trophies, not player_trophies
-- itself): player_trophies is the FULL unlock set — dozens of rows a viewer has
-- no business enumerating on someone else''s profile.  The showcase is a single
-- curated row: three ids + a handful of counts.  Keeping it separate lets the
-- raw unlock rows stay a private-ish own/authenticated read while the showcase
-- is the intentionally public face, and lets the Settings toggle turn the
-- public projection OFF (DELETE this row) WITHOUT deleting the player''s unlock
-- history on player_trophies (which the rarity/restore rails still need).
--
-- One row per player.  FK → players ON DELETE CASCADE, so account deletion
-- removes the public showcase with the rest of the personal rows.  Own-row
-- write; readable by BOTH anon and authenticated (a signed-out viewer opening a
-- rollalong://player/<id> deep link still sees the showcase — S3-T9 acceptance).
create table if not exists public.player_showcase (
    player_id      uuid        primary key
                   references public.players (id) on delete cascade,

    -- Up to 3 curated trophy ids (client caps + orders them; default = rarest
    -- earned).  text[] so the client fetches the strip in one row.
    showcased_ids  text[]      not null default '{}',

    -- Per-grade EARNED counts (the public grade strip).  Small non-negative ints.
    bronze_count   integer     not null default 0,
    silver_count   integer     not null default 0,
    gold_count     integer     not null default 0,
    diamond_count  integer     not null default 0,
    platinum_count integer     not null default 0,

    -- Overall earned / catalog total (header "N of M"), and the capstone crown.
    earned_count   integer     not null default 0,
    total_count    integer     not null default 0,
    capstone       boolean     not null default false,

    updated_at     timestamptz not null default now(),

    -- At most 3 showcased ids, each a short GC-legal id.
    constraint player_showcase_ids_cap check (cardinality(showcased_ids) <= 3),
    constraint player_showcase_counts_nonneg check (
        bronze_count >= 0 and silver_count >= 0 and gold_count >= 0
        and diamond_count >= 0 and platinum_count >= 0
        and earned_count >= 0 and total_count >= 0
    )
);

comment on table public.player_showcase is
    'CURATED public trophy showcase (S3-T9), one row per player. FK → players ON DELETE CASCADE. Own-row write; readable by anon AND authenticated (public-profile face). A small projection — per-grade counts + up to 3 showcased ids — NEVER the raw unlock rows (those live in player_trophies). Toggling the showcase off DELETEs this row without touching player_trophies.';
comment on column public.player_showcase.showcased_ids is
    'Up to 3 curated trophy ids (client default = rarest earned). text[] so PublicProfileView fetches the strip in one row.';

-- =============================================================================
-- Table: public.trophy_stats  — counts-only aggregate (anon-READABLE).
-- =============================================================================
-- The project's FIRST anon-readable object.  Written by the scheduled rollup
-- job (S3-T2) from trophy_unlocks (the anonymous rail) over the distinct-install
-- denominator.  Read by the Trophy Room (S3-T4).  Aggregates ONLY — never a
-- window into raw unlock rows.
create table if not exists public.trophy_stats (
    trophy_id     text        primary key,

    -- Numerator: distinct installs that have unlocked this trophy.
    earned_count  bigint      not null default 0,

    -- Denominator: distinct install UUIDs from the events rail at rollup time
    -- (same for every row in a given rollup pass — stored per-row so the client
    -- needs a single fetch and no second query).
    denominator   bigint      not null default 0,

    -- Convenience: earned_count / denominator, precomputed by the rollup so the
    -- client renders a band without dividing.  0 when denominator = 0.
    pct           double precision not null default 0,

    -- Per-trophy DISPLAY kill-switch (design.md §9): set true to hide a glitched
    -- trophy's rarity slot within a day without an app update.  Unlock logic
    -- stays client-side and additive; this only affects display.
    is_paused     boolean     not null default false,

    updated_at    timestamptz not null default now(),

    constraint trophy_stats_trophy_id_len   check (char_length(trophy_id) between 1 and 100),
    constraint trophy_stats_earned_nonneg   check (earned_count >= 0),
    constraint trophy_stats_denom_nonneg    check (denominator  >= 0),
    constraint trophy_stats_pct_range       check (pct >= 0 and pct <= 1),
    -- A trophy can't be earned by more installs than exist.
    constraint trophy_stats_earned_le_denom check (earned_count <= denominator)
);

comment on table public.trophy_stats is
    'Counts-only rarity aggregate. The project''s FIRST anon-readable object (aggregates only, never raw unlock rows). Written by the daily rollup (S3-T2) from trophy_unlocks; read by the Trophy Room (S3-T4). is_paused = per-trophy display kill-switch (design.md §9).';
comment on column public.trophy_stats.denominator is
    'Distinct install UUIDs from public.events at rollup time (design.md §3 / decision #5). Same UUID rail as trophy_unlocks.install_id.';
comment on column public.trophy_stats.is_paused is
    'Per-trophy DISPLAY kill-switch (design.md §9). true → client hides this trophy''s rarity slot. Does not affect client-side unlock logic.';

-- =============================================================================
-- Row-Level Security
-- =============================================================================
alter table public.trophy_unlocks  enable row level security;
alter table public.player_trophies enable row level security;
alter table public.player_showcase enable row level security;
alter table public.trophy_stats    enable row level security;

-- ---- trophy_unlocks : anonymous rail — INSERT-ONLY for clients ---------------
-- ALL players (anon + authenticated) may INSERT (every player counts toward
-- rarity — signed-in players ALSO write player_trophies below).  NO client
-- role gets SELECT/UPDATE/DELETE: the anonymous unlock rows are never readable
-- or mutable by any client — only service_role (which bypasses RLS) reads them
-- in the rollup.  This is the load-bearing privacy guarantee.
drop policy if exists "anon can insert trophy_unlocks" on public.trophy_unlocks;
create policy "anon can insert trophy_unlocks"
    on public.trophy_unlocks
    for insert
    to anon
    with check (true);

drop policy if exists "authenticated can insert trophy_unlocks" on public.trophy_unlocks;
create policy "authenticated can insert trophy_unlocks"
    on public.trophy_unlocks
    for insert
    to authenticated
    with check (true);

-- Deliberately NO select/update/delete policy on trophy_unlocks for anon OR
-- authenticated → clients can write but never read/modify the anonymous rail.

-- ---- player_trophies : signed-in showcase — own-row write, authed read -------
-- Readable by any signed-in user (public-profile showcase renders a friend's
-- trophies).  A player may write only their OWN rows (player_id = auth.uid()),
-- mirroring the players/friendships own-row pattern in social-schema.sql.
drop policy if exists "player_trophies readable by authenticated" on public.player_trophies;
create policy "player_trophies readable by authenticated"
    on public.player_trophies for select to authenticated using (true);

drop policy if exists "player_trophies insert own" on public.player_trophies;
create policy "player_trophies insert own"
    on public.player_trophies for insert to authenticated
    with check (player_id = auth.uid());

drop policy if exists "player_trophies update own" on public.player_trophies;
create policy "player_trophies update own"
    on public.player_trophies for update to authenticated
    using (player_id = auth.uid()) with check (player_id = auth.uid());

drop policy if exists "player_trophies delete own" on public.player_trophies;
create policy "player_trophies delete own"
    on public.player_trophies for delete to authenticated
    using (player_id = auth.uid());

-- ---- player_showcase : PUBLIC read (anon + authed), own-row write ------------
-- The curated showcase is the PUBLIC face of a signed-in player''s trophies, so
-- BOTH anon and authenticated may SELECT it (a signed-out viewer on a deep link
-- still sees it — S3-T9 acceptance).  A player may insert/update/delete only
-- their OWN row (player_id = auth.uid()), so toggling the showcase off (DELETE)
-- or refreshing it (upsert) is scoped to self.  Unlike player_trophies, this is
-- a single curated row — never a window into the raw unlock set.
drop policy if exists "player_showcase readable by anon" on public.player_showcase;
create policy "player_showcase readable by anon"
    on public.player_showcase for select to anon using (true);

drop policy if exists "player_showcase readable by authenticated" on public.player_showcase;
create policy "player_showcase readable by authenticated"
    on public.player_showcase for select to authenticated using (true);

drop policy if exists "player_showcase insert own" on public.player_showcase;
create policy "player_showcase insert own"
    on public.player_showcase for insert to authenticated
    with check (player_id = auth.uid());

drop policy if exists "player_showcase update own" on public.player_showcase;
create policy "player_showcase update own"
    on public.player_showcase for update to authenticated
    using (player_id = auth.uid()) with check (player_id = auth.uid());

drop policy if exists "player_showcase delete own" on public.player_showcase;
create policy "player_showcase delete own"
    on public.player_showcase for delete to authenticated
    using (player_id = auth.uid());

-- ---- trophy_stats : anon-READABLE aggregate ---------------------------------
-- The project's first anon-readable SELECT.  Aggregates only (the table holds
-- no raw unlock rows).  Both anon and authenticated may read; NO client writes
-- (the rollup job runs as service_role and bypasses RLS).
drop policy if exists "anon can read trophy_stats" on public.trophy_stats;
create policy "anon can read trophy_stats"
    on public.trophy_stats for select to anon using (true);

drop policy if exists "authenticated can read trophy_stats" on public.trophy_stats;
create policy "authenticated can read trophy_stats"
    on public.trophy_stats for select to authenticated using (true);

-- Deliberately NO insert/update/delete policy on trophy_stats for any client
-- role → only the service_role rollup writes it.

-- =============================================================================
-- Permission grants
-- =============================================================================
-- Follows the Data API role chain used by events/social: grant only what each
-- role's policies allow.  RLS narrows to the right rows on top of these grants.

-- trophy_unlocks: INSERT only, for both client roles.  Deliberately NO select
-- (matches events, which grants insert-only to anon/authenticated).
grant insert on public.trophy_unlocks to anon;
grant insert on public.trophy_unlocks to authenticated;

-- player_trophies: signed-in only.  select+insert+update+delete, RLS scopes to
-- own rows for writes and all rows for reads.
grant select, insert, update, delete on public.player_trophies to authenticated;

-- player_showcase: PUBLIC read (anon + authed), signed-in write.  RLS scopes
-- writes to own row and reads to all rows (the public showcase face).
grant select on public.player_showcase to anon;
grant select, insert, update, delete on public.player_showcase to authenticated;

-- trophy_stats: read-only for both client roles (aggregates only).
grant select on public.trophy_stats to anon;
grant select on public.trophy_stats to authenticated;

-- The rollup job (S3-T2) and any admin query run with service_role, which
-- bypasses RLS entirely — no explicit grant needed for it to read
-- trophy_unlocks or write trophy_stats.

-- =============================================================================
-- Delete-account interaction (verification note — no code change here)
-- =============================================================================
-- The existing `delete-account` edge function deletes the auth.users row; the
-- players FK ON DELETE CASCADE tears down the player's social rows, and
-- player_trophies (FK → players ON DELETE CASCADE, above) is torn down with
-- them — no edge-function change needed (S3-T5 verifies this).  trophy_unlocks
-- has NO FK to players and is therefore UNTOUCHED by account deletion: the
-- anonymous rarity counts survive, exactly like `events` rows.  This is the
-- design (design.md §4 / §10): deletion removes personal data, not aggregate
-- history.
--
-- S3-T5 VERIFICATION (2026-07-06 — no code change): the edge function's own
-- body deletes ONLY the auth.users / players row (RollAlong/SocialClient.swift
-- `deleteMyAccount` → POST /functions/v1/delete-account); it never names
-- player_trophies, trophy_unlocks, or trophy_stats.  Therefore:
--   • player_trophies — removed automatically by THIS file's FK ON DELETE
--     CASCADE when the parent players row goes.  ✓ personal trophy data gone.
--   • player_showcase — same FK ON DELETE CASCADE (S3-T9) ⇒ the curated public
--     showcase row is torn down with the player.  ✓ public showcase gone.
--   • trophy_unlocks  — no FK to players ⇒ zero rows touched by the cascade.
--     ✓ the anonymous rarity numerator survives (rarity persists post-delete).
--   • trophy_stats    — an aggregate derived only from trophy_unlocks + events
--     (see trophy-rollup.sql); with trophy_unlocks untouched, a re-run of
--     rollup_trophy_stats() produces the SAME earned_count/denominator ⇒ a
--     deletion cannot decrement any aggregate.  ✓
-- Client-side restore is the sign-in HYDRATE (S3-T5): TrophySyncService
-- `hydrateOnSignIn` fetches player_trophies and UNIONS it into the local ledger
-- (TrophyEngine.mergeUnlocks — server ∪ local, never subtraction), so a
-- reinstall + sign-in re-materialises the signed-in player's showcase rail
-- locally.  Anonymous reinstallers are covered by the iCloud KV mirror (S3-T8,
-- D11 = yes); an anon player with iCloud KV unavailable keeps today's
-- loss-on-reinstall (design.md §4 "Net:" — accepted, shrunk to near-zero).

-- =============================================================================
-- Useful queries (run with service_role, or as the rollup job — S3-T2).
-- =============================================================================

-- Rarity denominator — distinct install UUIDs on the analytics rail (the SAME
-- rail as trophy_unlocks.install_id):
--   select count(distinct user_id) as denominator from public.events;

-- earned_count per trophy from the anonymous rail (NEVER from player_trophies):
--   select trophy_id, count(distinct install_id) as earned_count
--   from public.trophy_unlocks
--   group by trophy_id;

-- The full rollup job (S3-T2) — the daily aggregation that writes trophy_stats
-- from trophy_unlocks over the distinct-install denominator, increment-only and
-- cold-start-aware — is authored as a SIBLING FILE: docs/trophies/trophy-rollup.sql.
-- Apply THIS schema file first, then trophy-rollup.sql.  It adds:
--   • public.trophy_rollup_config (launch_at anchor + cold-start thresholds),
--   • trophy_stats.rarity_ready (the cold-start gate the client reads),
--   • public.rollup_trophy_stats() (the daily recompute function),
--   • the pg_cron / edge-function scheduling notes (Mac's deploy step).
-- The denominator is count(distinct user_id) from public.events WHERE
-- event_name = 'app_launch' (the "booted the game" rail, per design.md §3);
-- earned_count is count(distinct install_id) from trophy_unlocks (this table),
-- NEVER from player_trophies.  is_paused is never overwritten by the rollup.
-- Sketch of the core upsert (see trophy-rollup.sql for the authoritative,
-- cold-start-guarded, race-clamped version):
--   with denom as (
--       select count(distinct user_id) d from public.events
--        where event_name = 'app_launch'
--   ),
--   counts as (
--       select trophy_id, count(distinct install_id) c
--       from public.trophy_unlocks group by trophy_id
--   )
--   insert into public.trophy_stats (trophy_id, earned_count, denominator, pct, updated_at)
--   select c.trophy_id, c.c, d.d,
--          case when d.d = 0 then 0 else least(c.c::double precision / d.d, 1.0) end, now()
--   from counts c cross join denom d
--   on conflict (trophy_id) do update
--       set earned_count = excluded.earned_count,
--           denominator  = excluded.denominator,
--           pct          = excluded.pct,
--           updated_at   = excluded.updated_at;
--       -- NB: is_paused is intentionally NOT overwritten by the rollup — it is
--       --     an operator-set display flag, not a computed value.
