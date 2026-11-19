-- ===========================================================================
-- Roll Along — database step 16: Roll Up leaderboard columns
--
-- The app reads and writes two Roll Up columns on public.players:
--   • rollup_best          best height in meters (the Roll Up board)
--   • rollup_best_seconds  that run's time in seconds
-- (SocialClient.syncMinigameStats and fetchLeaderboard.)  No schema file in
-- the repository creates them, so a database built only from the files would
-- refuse every leaderboard read and stats sync.  The live database may
-- already have them (added by hand earlier); this step makes sure either way.
-- It only adds what is missing and changes no data.
--
-- Run ONCE in the Supabase SQL editor, after step 15.  Safe to run again.
-- ===========================================================================

begin;

alter table public.players add column if not exists rollup_best         integer not null default 0;
alter table public.players add column if not exists rollup_best_seconds integer not null default 0;

alter table public.players drop constraint if exists players_rollup_nonneg;
alter table public.players add  constraint players_rollup_nonneg
    check (rollup_best >= 0 and rollup_best_seconds >= 0) not valid;

notify pgrst, 'reload schema';

commit;

-- ---------------------------------------------------------------------------
-- Check (read-only).  Expect two true columns.
-- ---------------------------------------------------------------------------
-- select
--     (select count(*) = 2 from information_schema.columns
--       where table_schema = 'public' and table_name = 'players'
--         and column_name in ('rollup_best', 'rollup_best_seconds'))  as rollup_columns,
--     exists (select 1 from pg_constraint
--              where conrelid = 'public.players'::regclass
--                and conname = 'players_rollup_nonneg')                as rollup_check;
