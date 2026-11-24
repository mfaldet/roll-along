-- =============================================================================
-- STEP 22 — Weekly level snapshot
-- =============================================================================
-- Run after step 20. Safe to run more than once.
--
-- WHY
--   Raw events are deleted after 90 days. This keeps one small row per level
--   and week forever, so a level can still be judged against its past after
--   the events behind it are gone.
--
-- WHAT IT ADDS
--   1. A table, public.level_weekly_stats: one row per level and week.
--   2. A function, public.snapshot_level_week(week_start), that works the
--      row out from that week's events and saves it. Running it again for
--      the same week replaces that week's rows.
--   3. A weekly job that snapshots the week that has just ended.
--   4. A one-time fill for every past week still in the events table.
--
--   Nothing here is readable or writable by the app. Nothing changes what the
--   app sends. No new information about a player is collected: every figure
--   is a count over events already stored, with no user_id kept.
--
-- THE COLUMNS
--   week_start             Monday of the week, US Eastern time.
--   level                  Adventure level number.
--   level_packs            The level pack versions seen that week (from the
--                          level_pack value on each event; empty for events
--                          sent before version 1.1).
--   attempts               level_attempt events.
--   clears                 level_complete events.
--   fails                  level_fail events.
--   median_clear_seconds   Median of the clear time.
--   one_star_share, two_star_share, three_star_share
--                          Share of clears that earned 1, 2 and 3 stars
--                          (0 to 1; they add up to 1 when there are clears).
--   fails_ending_the_day   Fails that were that install's last event of the
--                          Eastern calendar day: the player fell and did not
--                          do anything else in the game that day.
--   fail_ended_day_share   fails_ending_the_day divided by fails (0 to 1).
--
-- OLDER EVENTS
--   Before version 1.1 these events did not say which mode they came from. A
--   Challenge Track or Challenge of the Day run sent level_attempt and
--   level_fail carrying the player's Adventure level number, so weeks filled
--   from 1.0 and 1.0.1 events can overstate attempts and fails on a level.
--   From 1.1 each event carries game_mode and only Adventure ("climb") counts.
--
-- A WEEK is Monday 00:00 to the next Monday 00:00, US Eastern time, the same
-- clock the game uses for its own days.
-- =============================================================================

-- 1. The table (service-only; the app can neither read nor write it)
create table if not exists public.level_weekly_stats (
    week_start             date        not null,
    level                  int         not null,
    level_packs            int[]       not null default '{}',
    attempts               int         not null default 0,
    clears                 int         not null default 0,
    fails                  int         not null default 0,
    median_clear_seconds   numeric(8,2),
    one_star_share         numeric(5,4),
    two_star_share         numeric(5,4),
    three_star_share       numeric(5,4),
    fails_ending_the_day   int         not null default 0,
    fail_ended_day_share   numeric(5,4),
    computed_at            timestamptz not null default now(),
    primary key (week_start, level)
);
alter table public.level_weekly_stats enable row level security;
revoke all on public.level_weekly_stats from anon, authenticated;
comment on table public.level_weekly_stats is
    'One row per Adventure level and week (Monday, US Eastern): attempts, clears, fails, median clear time, star shares, and how often a fail was the install''s last event that day. Kept forever; filled by snapshot_level_week.';

-- 2. The function
create or replace function public.snapshot_level_week(p_week_start date)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
    v_from timestamptz;
    v_to   timestamptz;
    v_rows int;
begin
    if extract(isodow from p_week_start) <> 1 then
        raise exception 'week_start must be a Monday, got %', p_week_start;
    end if;
    v_from := (p_week_start::timestamp)        at time zone 'America/New_York';
    v_to   := ((p_week_start + 7)::timestamp)  at time zone 'America/New_York';

    delete from public.level_weekly_stats where week_start = p_week_start;

    with week_events as (
        select e.user_id, e.created_at, e.id, e.event_name, e.level, e.properties,
               (e.created_at at time zone 'America/New_York')::date as day
        from public.events e
        where e.created_at >= v_from and e.created_at < v_to
    ),
    last_of_day as (
        -- Each install's last event of each Eastern day in the week.
        select distinct on (w.user_id, w.day) w.id
        from week_events w
        order by w.user_id, w.day, w.created_at desc, w.id desc
    ),
    level_events as (
        select w.*,
               (w.id in (select id from last_of_day)) as is_last_of_day
        from week_events w
        where w.level is not null
          and w.event_name in ('level_attempt', 'level_complete', 'level_fail')
          -- Adventure only. From version 1.1 each of these events names its
          -- mode; an event with no mode is from an older version (see the note
          -- on older events at the top).
          and coalesce(w.properties->>'game_mode', 'climb') = 'climb'
    ),
    packs as (
        select l.level,
               array_agg(distinct (l.properties->>'level_pack')::int order by (l.properties->>'level_pack')::int) as level_packs
        from level_events l
        where l.properties->>'level_pack' ~ '^[0-9]+$'
        group by l.level
    ),
    agg as (
        select
            l.level,
            count(*) filter (where l.event_name = 'level_attempt')  as attempts,
            count(*) filter (where l.event_name = 'level_complete') as clears,
            count(*) filter (where l.event_name = 'level_fail')     as fails,
            percentile_cont(0.5) within group (order by (l.properties->>'time')::numeric)
                filter (where l.event_name = 'level_complete'
                          and l.properties->>'time' ~ '^[0-9]+(\.[0-9]+)?$')            as median_clear,
            count(*) filter (where l.event_name = 'level_complete' and l.properties->>'stars' = '1') as one_star,
            count(*) filter (where l.event_name = 'level_complete' and l.properties->>'stars' = '2') as two_star,
            count(*) filter (where l.event_name = 'level_complete' and l.properties->>'stars' = '3') as three_star,
            count(*) filter (where l.event_name = 'level_fail' and l.is_last_of_day)    as fails_ending
        from level_events l
        group by l.level
    )
    insert into public.level_weekly_stats
        (week_start, level, level_packs, attempts, clears, fails, median_clear_seconds,
         one_star_share, two_star_share, three_star_share,
         fails_ending_the_day, fail_ended_day_share, computed_at)
    select
        p_week_start,
        a.level,
        coalesce(p.level_packs, '{}'),
        a.attempts, a.clears, a.fails,
        round(a.median_clear::numeric, 2),
        case when a.clears > 0 then round(a.one_star::numeric   / a.clears, 4) end,
        case when a.clears > 0 then round(a.two_star::numeric   / a.clears, 4) end,
        case when a.clears > 0 then round(a.three_star::numeric / a.clears, 4) end,
        a.fails_ending,
        case when a.fails > 0 then round(a.fails_ending::numeric / a.fails, 4) end,
        now()
    from agg a
    left join packs p on p.level = a.level;

    get diagnostics v_rows = row_count;
    return v_rows;
end;
$$;
revoke all on function public.snapshot_level_week(date) from public, anon, authenticated;

-- 3. The weekly job: every Monday at 05:30 UTC (after midnight Eastern in
--    both standard and daylight time), snapshot the week that just ended.
--    Raw events are kept 90 days, so a missed week can be re-run by hand.
do $$
begin
    if exists (select 1 from pg_extension where extname = 'pg_cron') then
        perform cron.unschedule(jobid) from cron.job where jobname = 'ra-level-weekly-stats';
        perform cron.schedule('ra-level-weekly-stats', '30 5 * * 1',
            $job$select public.snapshot_level_week(
                     (date_trunc('week', (now() at time zone 'America/New_York')) - interval '7 days')::date)$job$);
    else
        raise notice 'pg_cron is not installed: the weekly job was not scheduled.';
    end if;
end;
$$;

-- 4. One-time fill: every full week that still has events.
select w::date as week_start, public.snapshot_level_week(w::date) as levels_saved
from generate_series(
        date_trunc('week', (select min(created_at) at time zone 'America/New_York' from public.events)),
        date_trunc('week', (now() at time zone 'America/New_York')) - interval '7 days',
        interval '7 days') as w
order by 1;

-- =============================================================================
-- CHECKS (read-only; run after the above)
-- =============================================================================
-- a) The table has rows, newest week first:
--      select * from public.level_weekly_stats order by week_start desc, level limit 20;
-- b) The job is scheduled:
--      select jobname, schedule from cron.job where jobname = 'ra-level-weekly-stats';
-- c) The app cannot read it (both should be false):
--      select has_table_privilege('anon', 'public.level_weekly_stats', 'select'),
--             has_table_privilege('authenticated', 'public.level_weekly_stats', 'select');
--
-- TO RE-RUN ONE WEEK BY HAND (the date must be a Monday):
--      select public.snapshot_level_week(date '2026-11-16');
