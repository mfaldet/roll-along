-- ===========================================================================
-- Roll Along — database step 12: remove the weekly pace ("+N this week")
--
-- The app no longer shows how many levels a player gained this week, and
-- nothing else used the weekly baseline (not the clan battle, rankings,
-- trophies, prizes, notifications or analytics).  This step removes it:
--   1. ra_players_guard   rewritten WITHOUT the weekly baseline; every other
--                         rule (impossible values, server-owned columns, life
--                         requests, the daily star cap, season-star counting)
--                         is unchanged, copied from docs/social-schema-v5.sql.
--   2. clan_rankings      recreated WITHOUT the week_levels column.
--   3. players            drops week_start, week_start_level, week_start_stars.
--
-- Run ONCE in the Supabase SQL editor, AFTER step 11
-- (docs/cosmetics/cosmetic-calendar.sql).  Safe to run again.
-- Run it only after the build that stops reading these columns is on every
-- test phone: an older build asks for them and would fall back to its
-- basic player query (no friend code or look) until updated.
--
-- Note: re-running the check at the bottom of social-schema-v5.sql after this
-- step reports new_columns = 15 (was 18), because the three weekly columns
-- are gone.  That is expected.  If social-schema-v5.sql is ever run again,
-- it adds the weekly columns and the old guard back: run this step again
-- right after it.
-- ===========================================================================

begin;

-- 1 · Player guard without the weekly baseline ------------------------------
create or replace function public.ra_players_guard()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
    season_now timestamp := public.ra_season_now();                               -- Eastern
    today      date      := public.ra_season_now()::date;                         -- Eastern day (star cap)
    -- True for requests from the app; false for you in the SQL editor, the
    -- scheduled jobs and the delete-account function.
    from_app   boolean   := coalesce(auth.role(), '') = 'authenticated';
    per_level  integer   := public.ra_config_int('stars_per_level_max', 3);
    daily_cap  integer   := public.ra_config_int('season_daily_star_cap', 150);
    req_life   interval  := public.ra_config_int('life_request_hours', 24) * interval '1 hour';
    cooldown   interval  := public.ra_config_int('life_request_cooldown_hours', 6) * interval '1 hour';
    was_open   boolean;
    gained     integer;
    counted    integer;
    my_clan    uuid;
begin
    -- (a) Impossible-value rule.  Refuses the write outright.  Checked only
    --     when the app is writing progress, not on unrelated updates.
    if from_app and (tg_op = 'INSERT'
        or new.climb_level      is distinct from old.climb_level
        or new.highest_unlocked is distinct from old.highest_unlocked
        or new.total_stars      is distinct from old.total_stars
        or new.coins_collected  is distinct from old.coins_collected)
       and (
           new.climb_level      < 1
        or new.highest_unlocked < 1
        or new.total_stars      < 0
        or new.coins_collected  < 0
        or new.climb_level      > new.highest_unlocked
        or new.total_stars      > per_level * new.highest_unlocked
    ) then
        raise exception 'impossible_progress'
            using hint = 'Stars cannot exceed the per-level maximum for the levels unlocked.';
    end if;

    if tg_op = 'INSERT' then
        new.stars_peak       := new.total_stars;
        new.stars_day        := today;
        new.stars_today      := 0;
        if from_app then
            new.excluded                := false;
            new.needs_lives_at          := null;
            new.lives_request_closed_at := null;
        end if;
        return new;
    end if;

    -- (b) Server-owned columns: keep the stored values, whatever was sent.
    if from_app then
        new.excluded                := old.excluded;
        new.stars_peak              := old.stars_peak;
        new.stars_day               := old.stars_day;
        new.stars_today             := old.stars_today;
        new.lives_request_closed_at := old.lives_request_closed_at;
        new.friend_code             := old.friend_code;
    end if;

    if from_app then
        -- (d) Life request: open, cancel, expiry and the wait between requests.
        was_open := old.needs_lives_at is not null;
        if was_open and old.needs_lives_at + req_life <= now() then
            -- It ran out of time before this update: it closed at that moment.
            new.lives_request_closed_at := old.needs_lives_at + req_life;
            if new.needs_lives_at is not distinct from old.needs_lives_at then
                new.needs_lives_at := null;
            end if;
            was_open := false;
        end if;
        if was_open then
            if new.needs_lives_at is null then
                new.lives_request_closed_at := now();          -- cancelled or filled
            else
                new.needs_lives_at := old.needs_lives_at;      -- cannot be re-dated
            end if;
        elsif new.needs_lives_at is not null then
            if new.lives_request_closed_at is not null
               and now() < new.lives_request_closed_at + cooldown then
                raise exception 'request_cooldown'
                    using hint = 'Wait before asking for lives again.';
            end if;
            new.needs_lives_at := now();                       -- the server's clock, not the phone's
        end if;

        -- (e) New stars, the daily cap, and the clan season score.
        if new.stars_day is distinct from today then
            new.stars_day   := today;
            new.stars_today := 0;
        end if;
        gained := new.total_stars - coalesce(old.stars_peak, old.total_stars);
        if gained > 0 then
            new.stars_peak := new.total_stars;
            counted := greatest(least(gained, daily_cap - new.stars_today), 0);
            new.stars_today := new.stars_today + counted;
            if counted > 0 and not new.excluded then
                select m.clan_id into my_clan
                  from public.clan_members m
                  join public.clans c on c.id = m.clan_id
                 where m.player_id = new.id and not c.excluded
                 limit 1;
                if my_clan is not null then
                    insert into public.clan_season_scores as sc (season, clan_id, player_id, stars)
                    values (date_trunc('month', season_now)::date, my_clan, new.id, counted)
                    on conflict (season, clan_id, player_id)
                    do update set stars = sc.stars + counted, updated_at = now();
                end if;
            end if;
        end if;
    end if;

    return new;
end $$;




-- (The players_guard trigger already points at this function; no change.)

-- 2 · Clan rankings without week_levels -------------------------------------
drop view if exists public.clan_rankings;
create view public.clan_rankings
with (security_invoker = true) as
select
    c.id, c.name, c.tag, c.description, c.owner_id, c.created_at, c.updated_at,
    count(m.player_id)::int                                              as member_count,
    coalesce(sum(p.climb_level) filter (where not p.excluded), 0)::int   as total_levels,
    coalesce(sum(p.total_stars) filter (where not p.excluded), 0)::int   as total_stars,
    coalesce((select sum(sc.stars)
                from public.clan_season_scores sc
                join public.players sp on sp.id = sc.player_id and not sp.excluded
               where sc.clan_id = c.id
                 and sc.season = date_trunc('month', public.ra_season_now())::date), 0)::int
                                                                         as season_score,
    c.season_wins, c.last_season, c.last_season_rank, c.last_season_clans,
    c.last_season_tier, c.last_season_score
from public.clans c
left join public.clan_members m on m.clan_id = c.id
left join public.players      p on p.id = m.player_id
where not c.excluded
group by c.id;

grant select on public.clan_rankings to authenticated;

-- 3 · Drop the weekly columns -----------------------------------------------
alter table public.players drop column if exists week_start;
alter table public.players drop column if exists week_start_level;
alter table public.players drop column if exists week_start_stars;

commit;

-- ---------------------------------------------------------------------------
-- Check (read-only).  Expect three true columns.
-- ---------------------------------------------------------------------------
-- select
--     (select count(*) = 0 from information_schema.columns
--       where table_schema = 'public' and table_name = 'players'
--         and column_name in ('week_start','week_start_level','week_start_stars'))  as weekly_columns_gone,
--     (select count(*) = 0 from information_schema.columns
--       where table_schema = 'public' and table_name = 'clan_rankings'
--         and column_name = 'week_levels')                                       as rankings_without_week,
--     (select pg_get_functiondef('public.ra_players_guard()'::regprocedure) not like '%week_start%')
--                                                                                as guard_without_week;
