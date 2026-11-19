-- ===========================================================================
-- Roll Along — database step 18: Roll Up is scored by height only
--
-- The app no longer records or ranks Roll Up run time.  This step removes the
-- run-time column public.players.rollup_best_seconds and everything that
-- used it:
--   • the combined non-negative check (re-created for height only)
--   • any index on the column (dropped with the column)
-- No function, view, policy or trigger in the repository reads or writes
-- rollup_best_seconds; the Roll Up board orders by rollup_best alone.
--
-- If the live database has a hand-made view or function that still uses the
-- column, the drop below stops with a "depends on" error instead of removing
-- it silently.  Send that error over and it will be handled.
--
-- Run ONCE in the Supabase SQL editor, after step 17.  Safe to run again, and
-- safe whether or not the column exists.
-- ===========================================================================

begin;

-- 1. The height column the board needs (no-op after step 16).
alter table public.players add column if not exists rollup_best integer not null default 0;

-- 2. Height-only check (replaces a combined height-and-seconds check).
alter table public.players drop constraint if exists players_rollup_nonneg;
alter table public.players add  constraint players_rollup_nonneg
    check (rollup_best >= 0) not valid;

-- 3. Remove the run-time column.  No CASCADE on purpose (see header).
alter table public.players drop column if exists rollup_best_seconds;

-- 4. Height ordering index (no-op after step 16).
create index if not exists players_rollup_idx on public.players (rollup_best desc);

notify pgrst, 'reload schema';

commit;

-- ---------------------------------------------------------------------------
-- Check (read-only).  Expect four true columns.
-- ---------------------------------------------------------------------------
-- select
--     not exists (select 1 from information_schema.columns
--                  where table_schema = 'public' and table_name = 'players'
--                    and column_name = 'rollup_best_seconds')           as no_seconds_column,
--     exists (select 1 from information_schema.columns
--              where table_schema = 'public' and table_name = 'players'
--                and column_name = 'rollup_best')                       as height_column,
--     exists (select 1 from pg_constraint
--              where conrelid = 'public.players'::regclass
--                and conname = 'players_rollup_nonneg'
--                and pg_get_constraintdef(oid) not like '%seconds%')    as height_only_check,
--     exists (select 1 from pg_indexes
--              where schemaname = 'public' and indexname = 'players_rollup_idx') as height_index;
