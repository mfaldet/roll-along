-- ===========================================================================
-- Roll Along — leaderboards kept PER DIFFICULTY (minigame_scores), including
-- Disco Ball.
--
-- Every leaderboard for a game with difficulty levels keeps separate rankings
-- for Easy, Normal and Hard (Disco Ball calls its hardest level "Hardcore"),
-- and a run counts only on the board for the difficulty it was played on:
--   • the six competitive games (snake, sumo, paintball, goldrush, marblecup,
--     koth): ranked by wins, then best score;
--   • Disco Ball (game "disco"): ranked by most crossings in one run, then the
--     faster average time per crossing;
--   • Snacky Solo (game "snake", difficulty "solo"): a fourth board on Snacky,
--     ranked by most orbs eaten in one run (best; wins stays 0).
-- One row per player per game per difficulty in public.minigame_scores.
--
-- The table already exists on the live database (added 2026-06-28 with the
-- competitive per-difficulty boards); until now it was only described in a
-- comment in docs/social-schema.sql.  This file:
--   1. creates it if it is missing (so the repository matches the database),
--   2. adds best_avg_ms (Disco Ball's average time per crossing, ms),
--   3. replaces any check rule on game / difficulty with one that allows
--      "disco" and Snacky's "solo" difficulty, plus a sanity rule on the
--      numbers,
--   4. (re)states the access rules: everyone signed in can read; a player
--      can write only their own rows,
--   5. adds the indexes the boards are ordered by.
--
-- An earlier draft of this file added discoball_best columns to players.
-- That draft was never run; those columns are not used.
--
-- Run ONCE in the Supabase SQL editor, after docs/social-schema-v5.sql.
-- Safe to run again: "if not exists" / "drop … if exists" / "or replace".
-- No existing row is changed or removed.
--
-- Until this file is run the app keeps working: the competitive boards work
-- as before, and the Disco Ball board says "Disco Ball rankings are not
-- available yet."
-- ===========================================================================

-- 1 · The table (no-op on the live database, where it already exists).
create table if not exists public.minigame_scores (
    player_id  uuid        not null references public.players (id) on delete cascade,
    game       text        not null,
    difficulty text        not null,
    wins       integer     not null default 0,
    best       integer     not null default 0,
    updated_at timestamptz not null default now(),
    primary key (player_id, game, difficulty)
);

-- 2 · Disco Ball's average time per crossing for the best run, milliseconds.
--     null = unknown (a best set before times were recorded); ranked last
--     among equal crossings.  Unused by the competitive games.
alter table public.minigame_scores add column if not exists best_avg_ms integer;

-- 3 · Value rules.  Any existing CHECK rule on this table is dropped first —
--     the live table may limit `game` to the six competitive games, which
--     would refuse Disco Ball — and replaced by the rules below.  They are
--     added NOT VALID: they apply to every new write, and existing rows are
--     never re-checked (so this file can never fail on old data).
do $$
declare c record;
begin
    for c in select conname from pg_constraint
              where conrelid = 'public.minigame_scores'::regclass and contype = 'c'
    loop
        execute format('alter table public.minigame_scores drop constraint %I', c.conname);
    end loop;
end $$;

alter table public.minigame_scores add constraint minigame_scores_game_valid
    check (game in ('snake', 'sumo', 'paintball', 'goldrush', 'marblecup', 'koth', 'disco'))
    not valid;
alter table public.minigame_scores add constraint minigame_scores_difficulty_valid
    check (difficulty in ('easy', 'normal', 'hard')
           or (difficulty = 'solo' and game = 'snake'))   -- Snacky Solo (2026-11-18)
    not valid;
-- Sanity: no negatives, no absurd numbers; a Disco Ball time is between a
-- quarter of a second and ten minutes per crossing.
alter table public.minigame_scores add constraint minigame_scores_values_sane
    check (    wins between 0 and 1000000
           and best between 0 and 100000000
           and (best_avg_ms is null or best_avg_ms between 250 and 600000))
    not valid;

-- 4 · Access.  Signed-in players can read every row (the boards); a player
--     can insert and update only their own rows.  Nobody can delete through
--     the app (rows go with the account).
alter table public.minigame_scores enable row level security;

drop policy if exists "minigame_scores readable by authenticated" on public.minigame_scores;
create policy "minigame_scores readable by authenticated"
    on public.minigame_scores for select to authenticated using (true);

drop policy if exists "minigame_scores insert own" on public.minigame_scores;
create policy "minigame_scores insert own"
    on public.minigame_scores for insert to authenticated
    with check (player_id = auth.uid());

drop policy if exists "minigame_scores update own" on public.minigame_scores;
create policy "minigame_scores update own"
    on public.minigame_scores for update to authenticated
    using (player_id = auth.uid()) with check (player_id = auth.uid());

grant select, insert, update on public.minigame_scores to authenticated;

-- updated_at follows every write (set_updated_at is from docs/social-schema.sql).
drop trigger if exists minigame_scores_set_updated_at on public.minigame_scores;
create trigger minigame_scores_set_updated_at
    before update on public.minigame_scores
    for each row execute function public.set_updated_at();

-- 5 · Board order.
create index if not exists minigame_scores_board_idx
    on public.minigame_scores (game, difficulty, wins desc, best desc);
create index if not exists minigame_scores_disco_board_idx
    on public.minigame_scores (difficulty, best desc, best_avg_ms asc nulls last)
    where game = 'disco';

-- ---------------------------------------------------------------------------
-- Check.  Expected: table = 1, avg_column = 1, rules = 3, policies = 3,
-- indexes = 2, rows_by_game lists only known games.
-- ---------------------------------------------------------------------------
select
    (select count(*) from information_schema.tables
      where table_schema = 'public' and table_name = 'minigame_scores')        as "table",
    (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'minigame_scores'
        and column_name = 'best_avg_ms')                                       as avg_column,
    (select count(*) from pg_constraint
      where conrelid = 'public.minigame_scores'::regclass and contype = 'c'
        and conname in ('minigame_scores_game_valid', 'minigame_scores_difficulty_valid',
                        'minigame_scores_values_sane'))                        as rules,
    (select count(*) from pg_policies
      where schemaname = 'public' and tablename = 'minigame_scores'
        and policyname in ('minigame_scores readable by authenticated',
                           'minigame_scores insert own',
                           'minigame_scores update own'))                      as policies,
    (select count(*) from pg_indexes
      where schemaname = 'public'
        and indexname in ('minigame_scores_board_idx',
                          'minigame_scores_disco_board_idx'))                  as indexes,
    (select coalesce(string_agg(game || ' ' || n, ', ' order by game), 'none')
       from (select game, count(*) n from public.minigame_scores group by game) g) as rows_by_game;
