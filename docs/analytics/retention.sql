-- =============================================================================
-- Retention: how many installs come back 1, 7 and 30 days after first launch
-- =============================================================================
-- Read-only. Changes nothing. Paste into the Supabase SQL editor and run.
--
-- WHAT IT MEASURES
--   One row per week of first launches. For the installs that first launched
--   in that week, the share that opened the game again exactly 1, 7 and 30
--   days after their first day.
--
--   • An install is one events.user_id: the random number made on the phone.
--     It is not an account and says nothing about who the player is.
--   • "Opened the game" is an app_launch or an app_resume event.
--   • Days are calendar days in US Eastern time, the same clock the game uses
--     for its own days. An install that first launches at 11 PM Monday and
--     comes back at 7 AM Tuesday counts as a day-1 return.
--   • Weeks start on Monday.
--
-- WHERE THE FIRST LAUNCH COMES FROM
--   Raw events are deleted after 90 days (step 20). So the first launch is
--   read from public.analytics_installs, the permanent one-row-per-install
--   table that step 20 fills from app_launch events. Reading it from raw
--   events alone would make an old install look new once its first events
--   were deleted.
--
-- WHAT THE LIMITS MEAN
--   • A rate shows as blank (null) until every install in the week has had
--     the chance to return: day 30 for a week is blank until 30 full days
--     after that week's last day.
--   • Only weeks from the last 90 days appear, because older return visits
--     have been deleted and their rates could no longer be worked out.
--   • Rows with few installs swing widely. Read the installs column first.
-- =============================================================================

with installs as (
    select
        i.user_id,
        (i.first_seen at time zone 'America/New_York')::date as first_day
    from public.analytics_installs i
    where i.first_seen >= now() - interval '90 days'
),
active_days as (
    -- Every Eastern calendar day on which an install opened the game.
    select distinct
        e.user_id,
        (e.created_at at time zone 'America/New_York')::date as day
    from public.events e
    where e.event_name in ('app_launch', 'app_resume')
      and e.created_at >= now() - interval '90 days'
),
per_install as (
    select
        i.user_id,
        i.first_day,
        date_trunc('week', i.first_day)::date as first_week,
        exists (select 1 from active_days a where a.user_id = i.user_id and a.day = i.first_day + 1)  as back_day_1,
        exists (select 1 from active_days a where a.user_id = i.user_id and a.day = i.first_day + 7)  as back_day_7,
        exists (select 1 from active_days a where a.user_id = i.user_id and a.day = i.first_day + 30) as back_day_30
    from installs i
),
today as (
    select (now() at time zone 'America/New_York')::date as d
)
select
    p.first_week                                                  as first_launch_week,
    count(*)                                                      as installs,
    -- A rate is shown only once the whole week's installs have passed that day.
    case when max(p.first_day) + 1  < (select d from today)
         then round(100.0 * count(*) filter (where p.back_day_1)  / count(*), 1) end as day_1_return_pct,
    case when max(p.first_day) + 7  < (select d from today)
         then round(100.0 * count(*) filter (where p.back_day_7)  / count(*), 1) end as day_7_return_pct,
    case when max(p.first_day) + 30 < (select d from today)
         then round(100.0 * count(*) filter (where p.back_day_30) / count(*), 1) end as day_30_return_pct
from per_install p
group by p.first_week
order by p.first_week desc;
