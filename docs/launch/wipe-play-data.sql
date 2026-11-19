-- ===========================================================================
-- Roll Along — wipe test play data before App Store submission
-- ===========================================================================
-- Run ONCE, right before submitting, after database steps 1–20 are applied
-- (step 20 creates analytics_installs, which this also clears).
-- Paste each PART into the Supabase SQL editor separately, in order:
--   PART 1  preview  (read-only: row counts now)
--   PART 2  wipe     (one transaction; nothing changes unless all of it works)
--   PART 3  check    (every column should be true)
--
-- CLEARED (every row deleted)
--   events                analytics events
--   analytics_installs    the permanent install list (trophy rarity denominator)
--   minigame_scores       per-difficulty minigame leaderboards (best, wins)
--   trophy_unlocks        anonymous trophy unlocks (per install)
--   player_trophies       signed-in trophy unlocks
--   player_showcase       trophy counts and showcases on profiles
--   trophy_stats          trophy rarity figures (the daily rollup rebuilds them)
--   clan_season_scores    season stars per clan member
--   clan_season_results   closed-season clan ranks
--   clan_season_prizes    season prizes (claimed and unclaimed)
--   clan_seasons          the record of which months were closed
--   clan_events           clan chat and join/leave/rename lines
--   life_gifts            life gifts and clan life-request gifts
--   feedback              Send Feedback messages
--
-- RESET (rows kept, only these columns go back to their defaults)
--   players: every minigame best and win count, which feed the minigame
--     leaderboards and Profile records —
--     pinball_best, zen_seconds, goldrush_best, snake_best, sumo_best,
--     paintball_best, marblecup_best, koth_best, rollup_best → 0;
--     snake_wins, sumo_wins, paintball_wins, marblecup_wins, koth_wins,
--     goldrush_wins → 0.
--   players: open life requests and the day's season-star count —
--     needs_lives_at, lives_request_closed_at → null; stars_today → 0.
--   clans: season history shown on Rankings —
--     season_wins → 0; last_season, last_season_rank, last_season_clans,
--     last_season_tier, last_season_score → null.
--
-- KEPT UNCHANGED
--   auth.users (accounts), players' identity and look (nickname, friend code,
--   accent, ball skin), Adventure progress (climb_level, highest_unlocked,
--   total_stars, coins_collected, stars_peak), clans (name, icon, color,
--   description, owner), clan_members, friendships, cosmetic_calendar,
--   ra_config, trophy_rollup_config.
--
-- WHY ADVENTURE PROGRESS IS KEPT
--   It is the player's own game progress, which the phone re-sends on its
--   next sync anyway.  Zeroing total_stars and stars_peak on the server would
--   also make that re-sent progress count as brand-new season stars for the
--   player's clan.  If you want the Adventure leaderboard empty too, the test
--   phones must delete and reinstall the app (their progress is stored on the
--   phone); then delete those test accounts in Settings → Delete Account.
--
-- IMPORTANT: phones re-send what they store
--   Each phone keeps its own minigame bests, Adventure progress and trophy
--   list and uploads them on the next sync.  After this wipe, a test phone
--   that opens the app again will put its scores and trophies back.  For a
--   clean start, delete the app on both test phones before running PART 2
--   (or don't open it again until after release).
--
-- SCHEDULED JOBS (social-schedule.sql, trophy-rollup cron lines)
--   ra-close-season (hourly) only closes months that have season scores, so
--   with clan_season_scores empty it does nothing until play resumes.
--   ra-expire-life-requests (every 15 min) finds no open requests.
--   The daily trophy rollup rebuilds trophy_stats from trophy_unlocks (empty,
--   so every trophy shows 0 earned; rarity bands stay hidden until the
--   cold-start gate opens).
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- PART 1 — PREVIEW (read-only).  Row counts before the wipe.
-- ---------------------------------------------------------------------------
select 'clear' as action, 'events' as table_name, count(*) as rows from public.events
union all select 'clear', 'analytics_installs',  count(*) from public.analytics_installs
union all select 'clear', 'minigame_scores',     count(*) from public.minigame_scores
union all select 'clear', 'trophy_unlocks',      count(*) from public.trophy_unlocks
union all select 'clear', 'player_trophies',     count(*) from public.player_trophies
union all select 'clear', 'player_showcase',     count(*) from public.player_showcase
union all select 'clear', 'trophy_stats',        count(*) from public.trophy_stats
union all select 'clear', 'clan_season_scores',  count(*) from public.clan_season_scores
union all select 'clear', 'clan_season_results', count(*) from public.clan_season_results
union all select 'clear', 'clan_season_prizes',  count(*) from public.clan_season_prizes
union all select 'clear', 'clan_seasons',        count(*) from public.clan_seasons
union all select 'clear', 'clan_events',         count(*) from public.clan_events
union all select 'clear', 'life_gifts',          count(*) from public.life_gifts
union all select 'clear', 'feedback',            count(*) from public.feedback
union all select 'reset', 'players with a minigame best, win, life request or star count',
       count(*) from public.players
       where pinball_best + zen_seconds + goldrush_best + snake_best + sumo_best
           + paintball_best + marblecup_best + koth_best + rollup_best
           + snake_wins + sumo_wins + paintball_wins + marblecup_wins + koth_wins
           + goldrush_wins + stars_today > 0
          or needs_lives_at is not null or lives_request_closed_at is not null
union all select 'reset', 'clans with season history',
       count(*) from public.clans
       where season_wins > 0 or last_season is not null
union all select 'keep', 'auth.users',        count(*) from auth.users
union all select 'keep', 'players',           count(*) from public.players
union all select 'keep', 'clans',             count(*) from public.clans
union all select 'keep', 'clan_members',      count(*) from public.clan_members
union all select 'keep', 'friendships',       count(*) from public.friendships
union all select 'keep', 'cosmetic_calendar', count(*) from public.cosmetic_calendar
union all select 'keep', 'ra_config',         count(*) from public.ra_config
order by 1, 2;


-- ---------------------------------------------------------------------------
-- PART 2 — WIPE.  One transaction.  Saves the kept-table counts first so
-- PART 3 can prove nothing kept was touched.
-- ---------------------------------------------------------------------------
begin;

create table if not exists public.ra_wipe_snapshot (
    table_name text primary key,
    rows       bigint not null,
    taken_at   timestamptz not null default now()
);
alter table public.ra_wipe_snapshot enable row level security;   -- no policies: app roles can't read it
revoke all on public.ra_wipe_snapshot from anon, authenticated;
truncate public.ra_wipe_snapshot;
insert into public.ra_wipe_snapshot (table_name, rows)
select 'auth.users',        count(*) from auth.users
union all select 'players',           count(*) from public.players
union all select 'clans',             count(*) from public.clans
union all select 'clan_members',      count(*) from public.clan_members
union all select 'friendships',       count(*) from public.friendships
union all select 'cosmetic_calendar', count(*) from public.cosmetic_calendar
union all select 'ra_config',         count(*) from public.ra_config
union all select 'players with friend code', count(*) from public.players where friend_code is not null
union all select 'adventure stars total',    coalesce(sum(total_stars), 0) from public.players;

truncate table
    public.events,
    public.analytics_installs,
    public.minigame_scores,
    public.trophy_unlocks,
    public.player_trophies,
    public.player_showcase,
    public.trophy_stats,
    public.clan_season_prizes,
    public.clan_season_results,
    public.clan_season_scores,
    public.clan_seasons,
    public.clan_events,
    public.life_gifts,
    public.feedback
restart identity;

-- Run as the table owner (SQL editor), so the players and clans guards treat
-- these as server updates and leave every other column alone.
update public.players set
    pinball_best = 0, zen_seconds = 0, goldrush_best = 0, snake_best = 0,
    sumo_best = 0, paintball_best = 0, marblecup_best = 0, koth_best = 0,
    rollup_best = 0,
    snake_wins = 0, sumo_wins = 0, paintball_wins = 0, marblecup_wins = 0,
    koth_wins = 0, goldrush_wins = 0,
    needs_lives_at = null, lives_request_closed_at = null, stars_today = 0;

update public.clans set
    season_wins = 0, last_season = null, last_season_rank = null,
    last_season_clans = null, last_season_tier = null, last_season_score = null;

commit;


-- ---------------------------------------------------------------------------
-- PART 3 — CHECK.  Every column should be true.
-- ---------------------------------------------------------------------------
-- select
--   (select count(*) from public.events) = 0
--     and (select count(*) from public.analytics_installs) = 0 as events_empty,
--   (select count(*) from public.minigame_scores) = 0        as minigame_scores_empty,
--   (select count(*) from public.trophy_unlocks) = 0
--     and (select count(*) from public.player_trophies) = 0
--     and (select count(*) from public.player_showcase) = 0
--     and (select count(*) from public.trophy_stats) = 0     as trophies_empty,
--   (select count(*) from public.clan_season_scores) = 0
--     and (select count(*) from public.clan_season_results) = 0
--     and (select count(*) from public.clan_season_prizes) = 0
--     and (select count(*) from public.clan_seasons) = 0     as seasons_empty,
--   (select count(*) from public.clan_events) = 0            as clan_chat_empty,
--   (select count(*) from public.life_gifts) = 0             as life_gifts_empty,
--   (select count(*) from public.feedback) = 0               as feedback_empty,
--   not exists (select 1 from public.players
--       where pinball_best + zen_seconds + goldrush_best + snake_best + sumo_best
--           + paintball_best + marblecup_best + koth_best + rollup_best
--           + snake_wins + sumo_wins + paintball_wins + marblecup_wins + koth_wins
--           + goldrush_wins + stars_today > 0
--          or needs_lives_at is not null or lives_request_closed_at is not null)
--                                                             as player_scores_reset,
--   not exists (select 1 from public.clans
--       where season_wins > 0 or last_season is not null)     as clan_history_reset,
--   not exists (
--       select 1 from public.ra_wipe_snapshot s
--        where s.rows <> case s.table_name
--          when 'auth.users'        then (select count(*) from auth.users)
--          when 'players'           then (select count(*) from public.players)
--          when 'clans'             then (select count(*) from public.clans)
--          when 'clan_members'      then (select count(*) from public.clan_members)
--          when 'friendships'       then (select count(*) from public.friendships)
--          when 'cosmetic_calendar' then (select count(*) from public.cosmetic_calendar)
--          when 'ra_config'         then (select count(*) from public.ra_config)
--          when 'players with friend code'
--               then (select count(*) from public.players where friend_code is not null)
--          when 'adventure stars total'
--               then (select coalesce(sum(total_stars), 0) from public.players)
--        end)                                                 as kept_tables_unchanged;
--
-- Optional, once the check is all true: remove the snapshot table.
--   drop table public.ra_wipe_snapshot;
