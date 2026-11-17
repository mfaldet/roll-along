-- ===========================================================================
-- Roll Along — social schema v5
--   weekly pace · clan member cap (12) · score guards · life-request limits ·
--   the MONTHLY CLAN BATTLE (season scores, month-end ranking, coin prizes)
--
-- Run ONCE in the Supabase SQL editor, AFTER docs/social-schema-v4.sql.
-- Then run docs/social-schedule.sql once (the two scheduled jobs).
-- Safe to run again: every statement is "if not exists" / "or replace" /
-- "drop ... if exists", and no existing row is rewritten.
--
-- Sections
--   1. ra_config               every number, changeable in the dashboard
--   2. new columns             all server-owned
--   3. season tables           scores, results, prizes
--   4. ra_players_guard        impossible-value rule, weekly baseline, daily
--                              cap, season-star counting, life-request rules
--   5. ra_clan_member_cap      a clan holds at most 12 members
--      ra_clans_guard          the app cannot write a clan's standing
--   6. ra_life_gift_request    one gift per giver per request; requests fill;
--                              one ordinary gift per friend per day
--   7. month-end               ra_close_season, ra_claim_season_prize
--   8. clan_rankings           the view the app's Rankings tab reads
--   9. clan leadership         hand over ownership; a clan is never left
--                              without an owner
--  10. friend codes            a short code per player, for "Add by code"
--  11. a check query           (expected output is described at the bottom)
--
-- The app works before this file is run (it falls back to the older
-- queries), but everything listed above needs it.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1 · Settings.  Change a value in Table Editor → ra_config; it takes effect
--     at once, with no re-run and no app update.
-- ---------------------------------------------------------------------------
create table if not exists public.ra_config (
    key    text    primary key,
    value  integer not null,
    note   text    not null default ''
);
-- Row-level security on, and NO policies: the app cannot read or write this
-- table directly.  It reads the player-facing numbers through
-- ra_social_settings() below.
alter table public.ra_config enable row level security;

insert into public.ra_config (key, value, note) values
    ('clan_member_cap',             12,     'Most members a clan can hold'),
    ('stars_per_level_max',         3,      'Impossible-value rule: stars can never exceed this many per level unlocked'),
    ('season_daily_star_cap',       150,    'Most new stars per player per day (Eastern time) that count toward the clan season score'),
    ('life_request_size',           6,      'Lives one request collects (one per clanmate) before it closes'),
    ('life_request_hours',          24,     'Hours after which an unfilled request closes by itself'),
    ('life_request_cooldown_hours', 6,      'Hours a player waits after a request closes before opening another'),
    ('gift_per_friend_per_day',     1,      'Ordinary life gifts (not answering a request) one player can send another per day (Eastern time)'),
    ('season_min_clan_score',       25,     'A clan needs this season score to be ranked at month end'),
    ('season_min_member_stars',     10,     'A member needs this many season stars for that clan to get a prize'),
    ('season_diamond_min_score',    150,    'Diamond also needs this season score; below it the clan gets Gold'),
    ('season_small_field',          20,     'With fewer ranked clans than this, tiers go by rank (1 / 2-3 / 4-8 / rest), not percentile'),
    ('season_coins_diamond',        3000,   'Prize per eligible member'),
    ('season_coins_gold',           1500,   'Prize per eligible member'),
    ('season_coins_silver',         750,    'Prize per eligible member'),
    ('season_coins_bronze',         250,    'Prize per eligible member'),
    ('season_prizes_from',          202701, 'First season (yyyymm) that awards coins and counts wins. Earlier seasons are a rehearsal: ranked and shown, no coins, no win')
on conflict (key) do nothing;

-- The game's clock: the current date and time in America/New_York.  A season
-- starts and ends at midnight Eastern; the daily star cap, the weekly pace
-- (weeks start Monday) and the one-gift-per-friend-per-day limit all reset at
-- midnight Eastern.  Using the NAMED zone means
-- daylight saving is handled by the database.  To move the battle to another
-- zone, change the name here and in `SeasonCalendar` in the app.
create or replace function public.ra_season_now()
returns timestamp
language sql stable as $$
    select now() at time zone 'America/New_York'
$$;

create or replace function public.ra_config_int(k text, fallback integer)
returns integer
language sql stable security definer set search_path = public as $$
    select coalesce((select value from public.ra_config where key = k), fallback)
$$;

-- The numbers the app shows to players, as one JSON object.
create or replace function public.ra_social_settings()
returns json
language sql stable security definer set search_path = public as $$
    select coalesce(json_object_agg(key, value), '{}'::json)
      from public.ra_config
     where key in ('clan_member_cap', 'life_request_size', 'life_request_hours',
                   'life_request_cooldown_hours', 'gift_per_friend_per_day',
                   'season_min_clan_score', 'season_min_member_stars',
                   'season_prizes_from')
$$;
revoke all on function public.ra_social_settings() from public;
grant execute on function public.ra_social_settings() to authenticated;

-- ---------------------------------------------------------------------------
-- 2 · New columns.  All are SERVER-OWNED: the guard triggers ignore whatever
--     the app sends for them.
-- ---------------------------------------------------------------------------
alter table public.players add column if not exists week_start       date;
alter table public.players add column if not exists week_start_level integer;
alter table public.players add column if not exists week_start_stars integer;
-- Highest star total ever seen: only stars ABOVE it count as new, so
-- resetting progress and re-earning the same stars scores nothing.
alter table public.players add column if not exists stars_peak       integer;
alter table public.players add column if not exists stars_day        date;
alter table public.players add column if not exists stars_today      integer not null default 0;
-- When the player's last life request closed (filled, expired or cancelled).
alter table public.players add column if not exists lives_request_closed_at timestamptz;
-- Exclusion switch.  Set to true in the dashboard to drop a player (or a
-- whole clan) from leaderboards, clan rankings, season scores and prizes.
alter table public.players add column if not exists excluded boolean not null default false;
alter table public.clans   add column if not exists excluded boolean not null default false;
-- A clan's standing, written only by the month-end job.
alter table public.clans add column if not exists season_wins       integer not null default 0;
alter table public.clans add column if not exists last_season       date;
alter table public.clans add column if not exists last_season_rank  integer;
alter table public.clans add column if not exists last_season_clans integer;
alter table public.clans add column if not exists last_season_tier  text;
alter table public.clans add column if not exists last_season_score integer;
-- Stamps a gift with the request it answers (section 6).
alter table public.life_gifts add column if not exists request_at timestamptz;

-- ---------------------------------------------------------------------------
-- 3 · Season tables.  A season is a calendar month in EASTERN TIME
--     (America/New_York: it starts and ends at midnight Eastern, with
--     daylight saving handled by the named zone), named by its first
--     day.  The app can read; only the triggers and the month-end job write.
-- ---------------------------------------------------------------------------
drop table if exists public.battle_contributions;   -- earlier draft of this file

-- Season stars per player, for the clan they were in when each was earned.
create table if not exists public.clan_season_scores (
    season     date        not null,
    clan_id    uuid        not null references public.clans (id)   on delete cascade,
    player_id  uuid        not null references public.players (id) on delete cascade,
    stars      integer     not null default 0,
    updated_at timestamptz not null default now(),
    primary key (season, clan_id, player_id)
);
create index if not exists clan_season_scores_clan_idx on public.clan_season_scores (clan_id, season);

-- One row per season the month-end job has closed.
create table if not exists public.clan_seasons (
    season       date        primary key,
    closed_at    timestamptz not null default now(),
    clans_ranked integer     not null default 0,
    with_prizes  boolean     not null default false
);

-- Where each ranked clan finished.
create table if not exists public.clan_season_results (
    season  date    not null,
    clan_id uuid    not null references public.clans (id) on delete cascade,
    score   integer not null,
    rank    integer not null,
    tier    text    not null,
    primary key (season, clan_id)
);

-- One prize per eligible player per season.  Kept until claimed; removed only
-- with the player's account.  Survives the clan being disbanded.
create table if not exists public.clan_season_prizes (
    season       date        not null,
    player_id    uuid        not null references public.players (id) on delete cascade,
    clan_id      uuid        references public.clans (id) on delete set null,
    clan_name    text        not null default '',
    clan_rank    integer     not null,
    clans_ranked integer     not null,
    tier         text        not null,
    contribution integer     not null,
    coins        integer     not null,
    created_at   timestamptz not null default now(),
    claimed_at   timestamptz,
    primary key (season, player_id)
);

alter table public.clan_season_scores  enable row level security;
alter table public.clan_seasons        enable row level security;
alter table public.clan_season_results enable row level security;
alter table public.clan_season_prizes  enable row level security;

drop policy if exists "season scores readable"  on public.clan_season_scores;
create policy "season scores readable"  on public.clan_season_scores  for select to authenticated using (true);
drop policy if exists "seasons readable"        on public.clan_seasons;
create policy "seasons readable"        on public.clan_seasons        for select to authenticated using (true);
drop policy if exists "season results readable" on public.clan_season_results;
create policy "season results readable" on public.clan_season_results for select to authenticated using (true);
-- A player sees only their own prizes; claiming goes through ra_claim_season_prize.
drop policy if exists "season prizes own"       on public.clan_season_prizes;
create policy "season prizes own"       on public.clan_season_prizes  for select to authenticated using (player_id = auth.uid());

grant select on public.clan_season_scores, public.clan_seasons,
                public.clan_season_results, public.clan_season_prizes to authenticated;

-- ---------------------------------------------------------------------------
-- 4 · Player guard: runs before every insert or update of a players row.
-- ---------------------------------------------------------------------------
create or replace function public.ra_players_guard()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
    season_now timestamp := public.ra_season_now();                               -- Eastern
    this_week  date      := date_trunc('week', public.ra_season_now())::date;     -- Monday, Eastern
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
        new.week_start       := this_week;
        new.week_start_level := new.climb_level;
        new.week_start_stars := new.total_stars;
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
        new.week_start              := old.week_start;
        new.week_start_level        := old.week_start_level;
        new.week_start_stars        := old.week_start_stars;
        new.stars_peak              := old.stars_peak;
        new.stars_day               := old.stars_day;
        new.stars_today             := old.stars_today;
        new.lives_request_closed_at := old.lives_request_closed_at;
        new.friend_code             := old.friend_code;
    end if;

    -- (c) Weekly baseline.  First update in a new week: remember where the
    --     player stood when the week began.  No scheduled job needed.
    if new.week_start is distinct from this_week then
        new.week_start       := this_week;
        new.week_start_level := old.climb_level;
        new.week_start_stars := old.total_stars;
    end if;
    -- After "Reset progress" the baseline drops with the player.
    new.week_start_level := least(coalesce(new.week_start_level, new.climb_level), new.climb_level);
    new.week_start_stars := least(coalesce(new.week_start_stars, new.total_stars), new.total_stars);

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

drop trigger if exists players_guard on public.players;
create trigger players_guard
    before insert or update on public.players
    for each row execute function public.ra_players_guard();

-- Closes requests that ran out of time.  Run every 15 minutes by
-- docs/social-schedule.sql.  (Even without the schedule an expired request
-- stops accepting gifts and the app stops showing it.)
create or replace function public.ra_expire_life_requests()
returns integer
language plpgsql security definer set search_path = public as $$
declare
    req_life interval := public.ra_config_int('life_request_hours', 24) * interval '1 hour';
    n integer;
begin
    update public.players
       set lives_request_closed_at = needs_lives_at + req_life,
           needs_lives_at          = null
     where needs_lives_at is not null
       and needs_lives_at + req_life <= now();
    get diagnostics n = row_count;
    return n;
end $$;
revoke all on function public.ra_expire_life_requests() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5 · Member cap, and the clan guard.  The clan row is locked first, so two people joining the
--     last free place at the same moment cannot both get in.
-- ---------------------------------------------------------------------------
create or replace function public.ra_clan_member_cap()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
    cap integer := public.ra_config_int('clan_member_cap', 12);
    n   integer;
begin
    perform 1 from public.clans where id = new.clan_id for update;
    select count(*) into n from public.clan_members where clan_id = new.clan_id;
    if n >= cap then
        raise exception 'clan_full' using hint = 'This clan has reached its member limit.';
    end if;
    return new;
end $$;

drop trigger if exists clan_members_cap on public.clan_members;
create trigger clan_members_cap
    before insert on public.clan_members
    for each row execute function public.ra_clan_member_cap();

-- The app (including a clan's owner) cannot write a clan's standing or its
-- exclusion switch.
create or replace function public.ra_clans_guard()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
    if coalesce(auth.role(), '') <> 'authenticated' then return new; end if;
    if tg_op = 'INSERT' then
        new.excluded          := false;
        new.season_wins       := 0;
        new.last_season       := null;
        new.last_season_rank  := null;
        new.last_season_clans := null;
        new.last_season_tier  := null;
        new.last_season_score := null;
    else
        new.excluded          := old.excluded;
        new.season_wins       := old.season_wins;
        new.last_season       := old.last_season;
        new.last_season_rank  := old.last_season_rank;
        new.last_season_clans := old.last_season_clans;
        new.last_season_tier  := old.last_season_tier;
        new.last_season_score := old.last_season_score;
        -- Ownership changes only through ra_transfer_clan_ownership or the
        -- automatic hand-over (section 9), which set this marker.
        if coalesce(current_setting('ra.owner_change', true), '') <> '1' then
            new.owner_id := old.owner_id;
        end if;
    end if;
    return new;
end $$;

drop trigger if exists clans_guard on public.clans;
create trigger clans_guard
    before insert or update on public.clans
    for each row execute function public.ra_clans_guard();

-- ---------------------------------------------------------------------------
-- 6 · Life gifts.
--     • A gift to a clanmate whose request is open answers that request: one
--       per giver per request, and the request closes when it is filled.
--     • Any other gift ("Send life" to a friend) is limited per friend per day.
--     • Giving never costs the giver anything: there is no giver-side balance
--       on the server at all.  Every gift is exactly one life.
-- ---------------------------------------------------------------------------
create unique index if not exists life_gifts_one_per_request_idx
    on public.life_gifts (sender_id, recipient_id, request_at)
    where request_at is not null;

create or replace function public.ra_life_gift_request()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
    ask       timestamptz;
    req_size  integer  := public.ra_config_int('life_request_size', 6);
    req_life  interval := public.ra_config_int('life_request_hours', 24) * interval '1 hour';
    per_day   integer  := public.ra_config_int('gift_per_friend_per_day', 1);
    day_start timestamptz := date_trunc('day', public.ra_season_now()) at time zone 'America/New_York';  -- midnight Eastern
    so_far    integer;
begin
    new.request_at := null;                       -- server-owned
    new.amount     := 1;
    select needs_lives_at into ask from public.players where id = new.recipient_id;
    if ask is not null and ask + req_life <= now() then
        ask := null;                              -- the request has expired
    end if;

    if ask is not null and exists (select 1
                     from public.clan_members a
                     join public.clan_members b on b.clan_id = a.clan_id
                    where a.player_id = new.sender_id
                      and b.player_id = new.recipient_id) then
        -- Answering a clanmate's open request.
        if exists (select 1 from public.life_gifts
                    where sender_id = new.sender_id
                      and recipient_id = new.recipient_id
                      and request_at = ask) then
            raise exception 'already_gave' using hint = 'You already gave a life to this request.';
        end if;
        new.request_at := ask;
        if req_size > 0 then
            select count(*) into so_far from public.life_gifts
             where recipient_id = new.recipient_id and request_at = ask;
            if so_far + 1 >= req_size then        -- filled: close it
                update public.players set needs_lives_at = null where id = new.recipient_id;
            end if;
        end if;
        return new;
    end if;

    -- An ordinary gift.
    if per_day > 0 then
        select count(*) into so_far from public.life_gifts
         where sender_id = new.sender_id and recipient_id = new.recipient_id
           and request_at is null and created_at >= day_start;
        if so_far >= per_day then
            raise exception 'gift_limit' using hint = 'You already sent this player a life today.';
        end if;
    end if;
    return new;
end $$;

drop trigger if exists life_gifts_request on public.life_gifts;
create trigger life_gifts_request
    before insert on public.life_gifts
    for each row execute function public.ra_life_gift_request();

-- ---------------------------------------------------------------------------
-- 7 · Month end.
--     ra_close_season() closes every finished month (Eastern time) that has
--     scores and has not been closed yet, oldest first.
--     docs/social-schedule.sql runs it every hour, so a month is closed
--     within minutes of midnight Eastern whatever the daylight-saving offset,
--     and a missed run (for example a paused project) is caught up within
--     the hour.
-- ---------------------------------------------------------------------------
create or replace function public.ra_close_one_season(s date)
returns integer
language plpgsql security definer set search_path = public as $$
declare
    min_clan    integer := public.ra_config_int('season_min_clan_score', 25);
    min_member  integer := public.ra_config_int('season_min_member_stars', 10);
    diamond_min integer := public.ra_config_int('season_diamond_min_score', 150);
    small_field integer := public.ra_config_int('season_small_field', 20);
    c_diamond   integer := public.ra_config_int('season_coins_diamond', 3000);
    c_gold      integer := public.ra_config_int('season_coins_gold', 1500);
    c_silver    integer := public.ra_config_int('season_coins_silver', 750);
    c_bronze    integer := public.ra_config_int('season_coins_bronze', 250);
    prizes_from integer := public.ra_config_int('season_prizes_from', 202701);
    with_prizes boolean := (extract(year from s)::int * 100 + extract(month from s)::int) >= prizes_from;
    n           integer;
begin
    s := date_trunc('month', s)::date;
    if exists (select 1 from public.clan_seasons where season = s) then
        return 0;                                  -- already closed: do nothing
    end if;

    -- Rank the clans.  Ties go to the older clan.
    insert into public.clan_season_results (season, clan_id, score, rank, tier)
    with scores as (
        select sc.clan_id, sum(sc.stars)::int as score, min(c.created_at) as created_at
          from public.clan_season_scores sc
          join public.clans   c on c.id = sc.clan_id   and not c.excluded
          join public.players p on p.id = sc.player_id and not p.excluded
         where sc.season = s
         group by sc.clan_id
        having sum(sc.stars) >= min_clan
    ), ranked as (
        select clan_id, score,
               row_number() over (order by score desc, created_at asc, clan_id)::int as rnk,
               count(*) over ()::int as total
          from scores
    ), tiered as (
        select clan_id, score, rnk,
               case when total >= small_field then
                        case when rnk <= ceil(total * 0.05) then 'diamond'
                             when rnk <= ceil(total * 0.20) then 'gold'
                             when rnk <= ceil(total * 0.50) then 'silver'
                             else 'bronze' end
                    else
                        case when rnk = 1  then 'diamond'
                             when rnk <= 3 then 'gold'
                             when rnk <= 8 then 'silver'
                             else 'bronze' end
               end as tier
          from ranked
    )
    select s, clan_id, score, rnk,
           case when tier = 'diamond' and score < diamond_min then 'gold' else tier end
      from tiered;
    get diagnostics n = row_count;

    -- Prizes: a member of the clan NOW (month end) who contributed the minimum.
    if with_prizes then
        insert into public.clan_season_prizes
            (season, player_id, clan_id, clan_name, clan_rank, clans_ranked, tier, contribution, coins)
        select s, sc.player_id, r.clan_id, c.name, r.rank, n, r.tier, sc.stars,
               case r.tier when 'diamond' then c_diamond when 'gold' then c_gold
                           when 'silver' then c_silver else c_bronze end
          from public.clan_season_results r
          join public.clans c              on c.id = r.clan_id
          join public.clan_season_scores sc on sc.season = r.season and sc.clan_id = r.clan_id
          join public.clan_members m        on m.clan_id = r.clan_id and m.player_id = sc.player_id
          join public.players p             on p.id = sc.player_id and not p.excluded
         where r.season = s and sc.stars >= min_member
        on conflict (season, player_id) do nothing;

        -- A win is finishing first.
        update public.clans c set season_wins = c.season_wins + 1
          from public.clan_season_results r
         where r.season = s and r.rank = 1 and r.clan_id = c.id;
    end if;

    -- Every ranked clan remembers where it finished.
    update public.clans c
       set last_season = s, last_season_rank = r.rank, last_season_clans = n,
           last_season_tier = r.tier, last_season_score = r.score
      from public.clan_season_results r
     where r.season = s and r.clan_id = c.id
       and (c.last_season is null or c.last_season <= s);

    insert into public.clan_seasons (season, clans_ranked, with_prizes) values (s, n, with_prizes);
    return n;
end $$;

create or replace function public.ra_close_season()
returns integer
language plpgsql security definer set search_path = public as $$
declare
    this_month date := date_trunc('month', public.ra_season_now())::date;   -- Eastern
    s date;
    closed integer := 0;
begin
    for s in
        select distinct sc.season from public.clan_season_scores sc
         where sc.season < this_month
           and not exists (select 1 from public.clan_seasons d where d.season = sc.season)
         order by 1
    loop
        perform public.ra_close_one_season(s);
        closed := closed + 1;
    end loop;
    return closed;
end $$;

-- Only the schedule and you (SQL editor) may close a season.
revoke all on function public.ra_close_one_season(date) from public, anon, authenticated;
revoke all on function public.ra_close_season()         from public, anon, authenticated;

-- Claim one prize.  Returns the coins to add on the device, or 0 when there
-- is nothing to claim (already claimed, or not this player's).
create or replace function public.ra_claim_season_prize(p_season date)
returns integer
language plpgsql security definer set search_path = public as $$
declare
    won integer;
begin
    update public.clan_season_prizes
       set claimed_at = now()
     where season = p_season and player_id = auth.uid() and claimed_at is null
    returning coins into won;
    return coalesce(won, 0);
end $$;
revoke all on function public.ra_claim_season_prize(date) from public, anon;
grant execute on function public.ra_claim_season_prize(date) to authenticated;

-- ---------------------------------------------------------------------------
-- 8 · Clan rankings (read-only).  security_invoker = the reader's own access
--     rules apply, exactly as if they had queried the tables themselves.
--     season_score counts every star earned for the clan this month, including
--     by players who have since left.
-- ---------------------------------------------------------------------------
drop view if exists public.clan_rankings;
create view public.clan_rankings
with (security_invoker = true) as
select
    c.id, c.name, c.tag, c.description, c.owner_id, c.created_at, c.updated_at,
    count(m.player_id)::int                                              as member_count,
    coalesce(sum(p.climb_level) filter (where not p.excluded), 0)::int   as total_levels,
    coalesce(sum(p.total_stars) filter (where not p.excluded), 0)::int   as total_stars,
    coalesce(sum(
        case when p.week_start = date_trunc('week', public.ra_season_now())::date
             then greatest(p.climb_level - p.week_start_level, 0) else 0 end
    ) filter (where not p.excluded), 0)::int                             as week_levels,
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

-- ---------------------------------------------------------------------------
-- 9 · Clan leadership.
--     • The owner can hand the clan to another member
--       (ra_transfer_clan_ownership).
--     • The owner can already remove a member: the "leave or owner removes"
--       delete rule from the first social schema allows it.
--     • A clan is never left without an owner.  If the owner leaves, or
--       deletes their account, the clan passes to the longest-standing
--       remaining member.  If nobody else is in it, the clan is removed.
-- ---------------------------------------------------------------------------
alter table public.clan_events drop constraint if exists clan_events_kind_valid;
alter table public.clan_events add constraint clan_events_kind_valid
    check (
        kind in ('created','joined','left','sent_life','requested_life','thanked',
                 'requested_promotion','renamed','removed','new_owner')
        or (kind like 'chat\_%' and char_length(kind) between 6 and 32)
    );

-- Pass a clan to its longest-standing member other than `p_leaving`.
-- Returns the new owner, or null when nobody else is in the clan.
create or replace function public.ra_hand_over_clan(p_clan uuid, p_leaving uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
    heir uuid;
begin
    select player_id into heir
      from public.clan_members
     where clan_id = p_clan and player_id <> p_leaving
     order by joined_at asc, player_id
     limit 1;
    if heir is null then return null; end if;

    perform set_config('ra.owner_change', '1', true);
    update public.clans set owner_id = heir where id = p_clan;
    perform set_config('ra.owner_change', '', true);
    update public.clan_members set role = 'owner'  where clan_id = p_clan and player_id = heir;
    update public.clan_members set role = 'member' where clan_id = p_clan and player_id = p_leaving;
    insert into public.clan_events (clan_id, actor_id, target_id, kind)
    values (p_clan, heir, heir, 'new_owner');
    return heir;
end $$;
revoke all on function public.ra_hand_over_clan(uuid, uuid) from public, anon, authenticated;

-- The owner hands the clan to a member of their choice.
create or replace function public.ra_transfer_clan_ownership(p_clan uuid, p_new_owner uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
    if not exists (select 1 from public.clans where id = p_clan and owner_id = auth.uid()) then
        raise exception 'not_owner' using hint = 'Only the clan owner can hand over the clan.';
    end if;
    if p_new_owner = auth.uid() then return; end if;
    if not exists (select 1 from public.clan_members
                    where clan_id = p_clan and player_id = p_new_owner) then
        raise exception 'not_a_member' using hint = 'That player is not in this clan.';
    end if;
    perform set_config('ra.owner_change', '1', true);
    update public.clans set owner_id = p_new_owner where id = p_clan;
    perform set_config('ra.owner_change', '', true);
    update public.clan_members set role = 'owner'  where clan_id = p_clan and player_id = p_new_owner;
    update public.clan_members set role = 'member' where clan_id = p_clan and player_id = auth.uid();
    insert into public.clan_events (clan_id, actor_id, target_id, kind)
    values (p_clan, auth.uid(), p_new_owner, 'new_owner');
end $$;
revoke all on function public.ra_transfer_clan_ownership(uuid, uuid) from public, anon;
grant execute on function public.ra_transfer_clan_ownership(uuid, uuid) to authenticated;

-- The owner's own membership row was deleted (they left): hand the clan on,
-- or remove it when it is now empty.
create or replace function public.ra_clan_owner_left()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
    if exists (select 1 from public.clans
                where id = old.clan_id and owner_id = old.player_id) then
        if public.ra_hand_over_clan(old.clan_id, old.player_id) is null then
            delete from public.clans where id = old.clan_id;
        end if;
    end if;
    return null;
end $$;

drop trigger if exists clan_members_owner_left on public.clan_members;
create trigger clan_members_owner_left
    after delete on public.clan_members
    for each row execute function public.ra_clan_owner_left();

-- A player row is about to be deleted (account deletion).  Without this the
-- clans they own would be deleted with them, members and all.  Hand each one
-- on first; a clan with nobody else in it is still removed.
create or replace function public.ra_player_hand_over()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
    c record;
begin
    for c in select id from public.clans where owner_id = old.id loop
        perform public.ra_hand_over_clan(c.id, old.id);
    end loop;
    return old;
end $$;

drop trigger if exists players_hand_over on public.players;
create trigger players_hand_over
    before delete on public.players
    for each row execute function public.ra_player_hand_over();

-- ---------------------------------------------------------------------------
-- 10 · Friend codes.  Every player gets a short code, shown on their profile,
--      that a friend types on the Friends screen to send a request.  Names
--      are not unique, so the code is how a player is found exactly.
--      Eight characters from a 15-character alphabet chosen to be easy to read
--      aloud and to type: A F H J K M R W X Y 3 4 6 7 9.  Left out: letters
--      that rhyme when spoken (B C D E G P T V Z, and N next to M), letters
--      that look like digits (I L O S), and digits that look like letters or
--      sound like words (0 1 2 5 8).  Shown as XXXX-XXXX.  15^8 is about
--      2.6 billion codes.  The app cannot write it; the database assigns it.
-- ---------------------------------------------------------------------------
alter table public.players add column if not exists friend_code text;
create unique index if not exists players_friend_code_idx on public.players (friend_code);

create or replace function public.ra_new_friend_code()
returns text
language plpgsql volatile set search_path = public as $$
declare
    alphabet constant text := 'AFHJKMRWXY34679';
    code text;
begin
    loop
        code := '';
        for i in 1..8 loop
            code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
        end loop;
        exit when not exists (select 1 from public.players where friend_code = code);
    end loop;
    return code;
end $$;
revoke all on function public.ra_new_friend_code() from public, anon, authenticated;

-- Assign a code to every new player row (the guard trigger keeps the app
-- from changing it later).
create or replace function public.ra_players_friend_code()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
    if new.friend_code is null or coalesce(auth.role(), '') = 'authenticated' then
        new.friend_code := public.ra_new_friend_code();
    end if;
    return new;
end $$;

drop trigger if exists players_friend_code on public.players;
create trigger players_friend_code
    before insert on public.players
    for each row execute function public.ra_players_friend_code();

-- Give existing players a code (only those without one, so re-running this
-- file never changes a code).
do $$
declare r record;
begin
    for r in select id from public.players where friend_code is null loop
        update public.players set friend_code = public.ra_new_friend_code() where id = r.id;
    end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 11 · Check.  Expected: settings = 16, triggers = 7, functions = 17,
--     season_tables = 4, rankings_view = 1, new_columns = 16,
--     players_without_code = 0 and
--     clans_over_cap = 0.  (A clan already over the cap keeps its members; it
--     simply cannot take new ones until it is back under.)
-- ---------------------------------------------------------------------------
select
    (select count(*) from public.ra_config)                                              as settings,
    (select count(*) from pg_trigger where not tgisinternal
        and tgname in ('players_guard','clan_members_cap','clans_guard','life_gifts_request',
                       'clan_members_owner_left','players_hand_over','players_friend_code'))                    as triggers,
    (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public'
        and p.proname in ('ra_config_int','ra_season_now','ra_social_settings','ra_players_guard',
                          'ra_expire_life_requests','ra_clan_member_cap','ra_clans_guard',
                          'ra_life_gift_request','ra_close_one_season','ra_close_season',
                          'ra_claim_season_prize','ra_hand_over_clan',
                          'ra_transfer_clan_ownership','ra_clan_owner_left',
                          'ra_player_hand_over','ra_new_friend_code',
                          'ra_players_friend_code'))                                         as functions,
    (select count(*) from information_schema.tables
      where table_schema = 'public'
        and table_name in ('clan_season_scores','clan_seasons',
                           'clan_season_results','clan_season_prizes'))                  as season_tables,
    (select count(*) from pg_views where schemaname = 'public' and viewname = 'clan_rankings') as rankings_view,
    (select count(*) from information_schema.columns
      where table_schema = 'public'
        and (   (table_name = 'players' and column_name in
                    ('week_start','week_start_level','week_start_stars','stars_peak',
                     'stars_day','stars_today','lives_request_closed_at','excluded',
                     'friend_code'))
             or (table_name = 'clans' and column_name in
                    ('excluded','season_wins','last_season','last_season_rank',
                     'last_season_clans','last_season_tier','last_season_score'))))      as new_columns,
    (select count(*) from public.players where friend_code is null)                      as players_without_code,
    (select count(*) from (select clan_id from public.clan_members
                            group by clan_id
                           having count(*) > public.ra_config_int('clan_member_cap', 12)) t) as clans_over_cap;
