-- ===========================================================================
-- Roll Along — social schema v5: weekly pace, clan rankings, member cap (12),
-- first guards against faked scores, battle-star counting, and the
-- give-once-per-request rule for clan life requests.
--
-- Run ONCE in the Supabase SQL editor, AFTER docs/social-schema-v4.sql.
-- Safe to run again: every statement is "if not exists" / "or replace" /
-- "drop ... if exists", and no existing row is rewritten.
--
-- What this adds
--   1. ra_config            settings you can change in the dashboard
--   2. players / clans      new server-owned columns
--   3. battle_contributions battle stars per player per clan per Battle Week
--   4. ra_players_guard     trigger: impossible-value rule, weekly baseline,
--                           daily cap, battle-star counting
--   5. ra_clan_member_cap   trigger: a clan holds at most 12 members
--   6. clan_rankings        read-only view the app's Rankings tab reads
--   7. ra_life_gift_request trigger: one gift per giver per life request
--   8. a check query        (expected output is described at the bottom)
--
-- The app works before this file is run (it falls back to the older
-- queries), but weekly pace, clan rankings and the member cap need it.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1 · Settings.  Change a value in Table Editor → ra_config; no re-run needed.
-- ---------------------------------------------------------------------------
create table if not exists public.ra_config (
    key    text    primary key,
    value  integer not null,
    note   text    not null default ''
);
-- Row-level security on, and NO policies: the app cannot read or write this
-- table.  Only the functions below (and you, in the dashboard) can.
alter table public.ra_config enable row level security;

insert into public.ra_config (key, value, note) values
    ('clan_member_cap',       12,  'Most members a clan can hold'),
    ('stars_per_level_max',   3,   'Impossible-value rule: stars can never exceed this many per level unlocked'),
    ('battle_daily_star_cap', 150, 'Most new stars per player per UTC day that count as battle stars'),
    ('life_request_size',     0,   'Lives one clan life request collects before it closes by itself. 0 = no fixed size (closes only when the asker cancels)')
on conflict (key) do nothing;

create or replace function public.ra_config_int(k text, fallback integer)
returns integer
language sql stable security definer set search_path = public as $$
    select coalesce((select value from public.ra_config where key = k), fallback)
$$;

-- ---------------------------------------------------------------------------
-- 2 · New columns.  All are SERVER-OWNED: the trigger in section 4 ignores
--     whatever the app sends for them.
-- ---------------------------------------------------------------------------
alter table public.players add column if not exists week_start       date;
alter table public.players add column if not exists week_start_level integer;
alter table public.players add column if not exists week_start_stars integer;
-- Highest star total ever seen: only stars ABOVE it count as new, so
-- resetting progress and re-earning the same stars scores nothing.
alter table public.players add column if not exists stars_peak       integer;
alter table public.players add column if not exists stars_day        date;
alter table public.players add column if not exists stars_today      integer not null default 0;
-- Exclusion switch.  Set to true in the dashboard to drop a player (or a
-- whole clan) from leaderboards, clan rankings and battle counting.
alter table public.players add column if not exists excluded boolean not null default false;
alter table public.clans   add column if not exists excluded boolean not null default false;

-- ---------------------------------------------------------------------------
-- 3 · Battle stars.  One row per (Battle Week, clan, player).  The app can
--     read these; only the trigger can write them.
--     battle_start is the 1st of the month the Battle Week belongs to.
-- ---------------------------------------------------------------------------
create table if not exists public.battle_contributions (
    battle_start date        not null,
    clan_id      uuid        not null references public.clans (id)   on delete cascade,
    player_id    uuid        not null references public.players (id) on delete cascade,
    stars        integer     not null default 0,
    updated_at   timestamptz not null default now(),
    primary key (battle_start, clan_id, player_id)
);
alter table public.battle_contributions enable row level security;
drop policy if exists "battle_contributions readable by authenticated" on public.battle_contributions;
create policy "battle_contributions readable by authenticated"
    on public.battle_contributions for select to authenticated using (true);
grant select on public.battle_contributions to authenticated;

-- ---------------------------------------------------------------------------
-- 4 · Player guard: runs before every insert or update of a players row.
-- ---------------------------------------------------------------------------
create or replace function public.ra_players_guard()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
    now_utc    timestamp := now() at time zone 'utc';
    this_week  date      := date_trunc('week', now() at time zone 'utc')::date;   -- Monday
    today      date      := (now() at time zone 'utc')::date;
    -- True for requests from the app; false for you in the SQL editor and
    -- for the delete-account function.
    from_app   boolean   := coalesce(auth.role(), '') = 'authenticated';
    per_level  integer   := public.ra_config_int('stars_per_level_max', 3);
    daily_cap  integer   := public.ra_config_int('battle_daily_star_cap', 150);
    gained     integer;
    counted    integer;
    my_clan    uuid;
begin
    -- (a) Impossible-value rule.  Refuses the write outright.
    if from_app and (
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
        if from_app then new.excluded := false; end if;
        return new;
    end if;

    -- (b) Server-owned columns: keep the stored values, whatever was sent.
    if from_app then
        new.excluded         := old.excluded;
        new.week_start       := old.week_start;
        new.week_start_level := old.week_start_level;
        new.week_start_stars := old.week_start_stars;
        new.stars_peak       := old.stars_peak;
        new.stars_day        := old.stars_day;
        new.stars_today      := old.stars_today;
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

    -- (d) New stars, daily cap, battle stars.  App requests only.
    if from_app then
        if new.stars_day is distinct from today then
            new.stars_day   := today;
            new.stars_today := 0;
        end if;
        gained := new.total_stars - coalesce(old.stars_peak, old.total_stars);
        if gained > 0 then
            new.stars_peak := new.total_stars;
            counted := greatest(least(gained, daily_cap - new.stars_today), 0);
            new.stars_today := new.stars_today + counted;
            -- Battle Week is days 1 to 7 of each month, UTC.
            if counted > 0 and extract(day from now_utc) <= 7 and not new.excluded then
                select m.clan_id into my_clan
                  from public.clan_members m
                  join public.clans c on c.id = m.clan_id
                 where m.player_id = new.id and not c.excluded
                 limit 1;
                if my_clan is not null then
                    insert into public.battle_contributions as b (battle_start, clan_id, player_id, stars)
                    values (date_trunc('month', now_utc)::date, my_clan, new.id, counted)
                    on conflict (battle_start, clan_id, player_id)
                    do update set stars = b.stars + counted, updated_at = now();
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

-- ---------------------------------------------------------------------------
-- 5 · Member cap.  The clan row is locked first, so two people joining the
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

-- ---------------------------------------------------------------------------
-- 6 · Clan rankings (read-only).  security_invoker = the reader's own access
--     rules apply, exactly as if they had queried the tables themselves.
-- ---------------------------------------------------------------------------
create or replace view public.clan_rankings
with (security_invoker = true) as
select
    c.id, c.name, c.tag, c.description, c.owner_id, c.created_at, c.updated_at,
    count(m.player_id)::int                                              as member_count,
    coalesce(sum(p.climb_level) filter (where not p.excluded), 0)::int   as total_levels,
    coalesce(sum(p.total_stars) filter (where not p.excluded), 0)::int   as total_stars,
    coalesce(sum(
        case when p.week_start = date_trunc('week', now() at time zone 'utc')::date
             then greatest(p.climb_level - p.week_start_level, 0) else 0 end
    ) filter (where not p.excluded), 0)::int                             as week_levels
from public.clans c
left join public.clan_members m on m.clan_id = c.id
left join public.players      p on p.id = m.player_id
where not c.excluded
group by c.id;

grant select on public.clan_rankings to authenticated;

-- ---------------------------------------------------------------------------
-- 7 · Clan life requests: a player can give to any ONE request only once.
--     A "request" is a clanmate's open ask (players.needs_lives_at).  A gift
--     sent to a clanmate while their ask is open is stamped with that ask's
--     time in request_at; the unique index refuses a second one.
--     Giving never costs the giver anything (there is no giver-side balance
--     on the server at all), and gifts outside a request are unchanged.
-- ---------------------------------------------------------------------------
alter table public.life_gifts add column if not exists request_at timestamptz;

create unique index if not exists life_gifts_one_per_request_idx
    on public.life_gifts (sender_id, recipient_id, request_at)
    where request_at is not null;

create or replace function public.ra_life_gift_request()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
    ask       timestamptz;
    req_size  integer := public.ra_config_int('life_request_size', 0);
    so_far    integer;
begin
    new.request_at := null;                       -- server-owned
    select needs_lives_at into ask from public.players where id = new.recipient_id;
    if ask is null then return new; end if;       -- not asking: an ordinary gift
    if not exists (select 1
                     from public.clan_members a
                     join public.clan_members b on b.clan_id = a.clan_id
                    where a.player_id = new.sender_id
                      and b.player_id = new.recipient_id) then
        return new;                               -- not clanmates: an ordinary gift
    end if;
    if exists (select 1 from public.life_gifts
                where sender_id = new.sender_id
                  and recipient_id = new.recipient_id
                  and request_at = ask) then
        raise exception 'already_gave' using hint = 'You already gave a life to this request.';
    end if;
    new.request_at := ask;
    new.amount     := 1;
    -- Optional fixed request size: close the request when it is filled.
    if req_size > 0 then
        select count(*) into so_far from public.life_gifts
         where recipient_id = new.recipient_id and request_at = ask;
        if so_far + 1 >= req_size then
            update public.players set needs_lives_at = null where id = new.recipient_id;
        end if;
    end if;
    return new;
end $$;

drop trigger if exists life_gifts_request on public.life_gifts;
create trigger life_gifts_request
    before insert on public.life_gifts
    for each row execute function public.ra_life_gift_request();

-- ---------------------------------------------------------------------------
-- 8 · Check.  Expected: settings = 4, the three triggers = 1 each,
--     rankings_view = 1, new_player_columns = 7, gift_column = 1, and
--     clans_over_cap = 0.  (A clan already over the cap keeps its members;
--     it simply cannot take new ones until it is back under.)
-- ---------------------------------------------------------------------------
select
    (select count(*) from public.ra_config)                                              as settings,
    (select count(*) from pg_trigger where tgname = 'players_guard'      and not tgisinternal) as players_trigger,
    (select count(*) from pg_trigger where tgname = 'clan_members_cap'   and not tgisinternal) as cap_trigger,
    (select count(*) from pg_trigger where tgname = 'life_gifts_request' and not tgisinternal) as gift_trigger,
    (select count(*) from pg_views   where schemaname = 'public' and viewname = 'clan_rankings') as rankings_view,
    (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'players'
        and column_name in ('week_start','week_start_level','week_start_stars',
                            'stars_peak','stars_day','stars_today','excluded'))          as new_player_columns,
    (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'life_gifts'
        and column_name = 'request_at')                                                  as gift_column,
    (select count(*) from (select clan_id from public.clan_members
                            group by clan_id
                           having count(*) > public.ra_config_int('clan_member_cap', 12)) t) as clans_over_cap;
