-- ===========================================================================
-- Roll Along — database step 16: Roll Up leaderboard column
--
-- The app reads and writes one Roll Up column on public.players:
--   • rollup_best   best height in meters (the Roll Up board)
-- (SocialClient.syncMinigameStats and fetchLeaderboard.)  No schema file in
-- the repository creates it, so a database built only from the files would
-- refuse every leaderboard read and stats sync.  The live database may
-- already have it (added by hand earlier); this step makes sure either way.
-- It only adds what is missing and changes no data.
--
-- Roll Up is scored by height only.  The old run-time column
-- (rollup_best_seconds) is no longer added here; step 18
-- (docs/social/rollup-height-only.sql) removes it if the live database has it.
--
-- Run ONCE in the Supabase SQL editor, after step 15.  Safe to run again.
-- ===========================================================================

begin;

alter table public.players add column if not exists rollup_best integer not null default 0;

-- Non-negative height.  (If an older copy of this step created the combined
-- height-and-seconds check, it is replaced here.)
alter table public.players drop constraint if exists players_rollup_nonneg;
alter table public.players add  constraint players_rollup_nonneg
    check (rollup_best >= 0) not valid;

-- The Roll Up board orders by best height.
create index if not exists players_rollup_idx on public.players (rollup_best desc);

notify pgrst, 'reload schema';

commit;

-- ---------------------------------------------------------------------------
-- Check (read-only).  Expect three true columns.
-- ---------------------------------------------------------------------------
-- select
--     exists (select 1 from information_schema.columns
--              where table_schema = 'public' and table_name = 'players'
--                and column_name = 'rollup_best')                      as rollup_column,
--     exists (select 1 from pg_constraint
--              where conrelid = 'public.players'::regclass
--                and conname = 'players_rollup_nonneg')                as rollup_check,
--     exists (select 1 from pg_indexes
--              where schemaname = 'public' and indexname = 'players_rollup_idx') as rollup_index;
