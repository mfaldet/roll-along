-- ===========================================================================
-- Roll Along — Disco Ball leaderboard columns.
--
-- Adds two columns to public.players:
--   discoball_best         most crossings in one Disco Ball run (any difficulty)
--   discoball_best_avg_ms  that run's average time per crossing, milliseconds
--                          (only the rolling counts, not memorizing)
-- The Disco Ball board ranks by discoball_best, highest first; a tie goes to
-- the lower average time.
--
-- Run ONCE in the Supabase SQL editor, after docs/social-schema.sql (it needs
-- the players table).  Safe to run again: "if not exists" / "drop … if exists".
-- No existing row is rewritten; every player starts at 0 (not on the board)
-- and appears after their next Disco Ball run.
--
-- Access: the existing "players update own" rule and the table-level
-- UPDATE grant to `authenticated` already cover new columns, so a signed-in
-- player can write only their own row.  Nothing else is needed.
--
-- Until this file is run the app keeps working: it sends these two columns in
-- a separate request (which simply fails), and the Disco Ball board says
-- "Disco Ball rankings are not available yet."
-- ===========================================================================

alter table public.players add column if not exists discoball_best        integer not null default 0;
alter table public.players add column if not exists discoball_best_avg_ms integer not null default 0;

-- Impossible-value guard: no negatives, no more than 10,000 crossings in a
-- run, and a recorded run of at least one crossing must have an average of at
-- least a quarter of a second and at most ten minutes.  A value outside this is
-- refused.  (Cheap; it stops only the crudest fakes, like the other guards.)
alter table public.players drop constraint if exists players_discoball_sane;
alter table public.players add  constraint players_discoball_sane check (
        discoball_best between 0 and 10000
    and discoball_best_avg_ms between 0 and 600000
    and (discoball_best = 0 or discoball_best_avg_ms = 0 or discoball_best_avg_ms >= 250)
);

-- The board's ordering (descending best, ascending average), for when the
-- table grows.
create index if not exists players_discoball_board_idx
    on public.players (discoball_best desc, discoball_best_avg_ms asc)
    where discoball_best > 0;

-- ---------------------------------------------------------------------------
-- Check.  Expected: new_columns = 2, guard = 1, board_index = 1,
-- bad_rows = 0.
-- ---------------------------------------------------------------------------
select
    (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'players'
        and column_name in ('discoball_best', 'discoball_best_avg_ms'))          as new_columns,
    (select count(*) from pg_constraint
      where conname = 'players_discoball_sane')                                  as guard,
    (select count(*) from pg_indexes
      where schemaname = 'public' and indexname = 'players_discoball_board_idx') as board_index,
    (select count(*) from public.players
      where discoball_best < 0 or discoball_best_avg_ms < 0)                     as bad_rows;
