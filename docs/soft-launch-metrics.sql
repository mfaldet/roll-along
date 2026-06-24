-- =============================================================================
-- Roll Along — Soft-Launch Metrics Dashboard
-- =============================================================================
-- Run these in the Supabase SQL Editor signed in with the SERVICE_ROLE key
-- (the anon client can only INSERT — see docs/supabase-schema.sql).
--
-- Each query is standalone; copy-paste the one you want.  The KPIs and the
-- go/no-go gates they feed are in docs/research/08-soft-launch.md.
--
-- Caveat: a friends-and-family cohort inflates retention.  Treat numbers as a
-- ceiling and weight the watch+interview signal heavily.
-- =============================================================================


-- 0. Sanity — is data even arriving?  Run a day into the test.
select count(*) as events,
       count(distinct user_id) as users,
       min(created_at) as first_event,
       max(created_at) as last_event
from events;


-- 1. DAU + sessions per user (last 14 days) ---------------------------------
select created_at::date                                              as day,
       count(distinct user_id)                                       as dau,
       count(distinct session_id)                                    as sessions,
       round(count(distinct session_id)::numeric
             / nullif(count(distinct user_id), 0), 2)                as sessions_per_user
from events
where created_at > now() - interval '14 days'
group by 1
order by 1 desc;


-- 2. ⭐ D1 / D7 RETENTION by install-day cohort (the headline gate) ----------
-- install_day = the user's first-ever event day.  d1/d7 = % of that cohort
-- with ANY event 1 / 7 days later.  Gate: D1 >~ 35%, D7 >~ 10% (cohort-biased).
with first_seen as (
    select user_id, min(created_at)::date as install_day
    from events
    group by user_id
),
active_days as (
    select distinct user_id, created_at::date as d
    from events
)
select fs.install_day,
       count(distinct fs.user_id)                                    as installs,
       round(100.0 * count(distinct d1.user_id)
             / nullif(count(distinct fs.user_id), 0), 1)             as d1_pct,
       round(100.0 * count(distinct d7.user_id)
             / nullif(count(distinct fs.user_id), 0), 1)             as d7_pct
from first_seen fs
left join active_days d1 on d1.user_id = fs.user_id and d1.d = fs.install_day + 1
left join active_days d7 on d7.user_id = fs.user_id and d7.d = fs.install_day + 7
group by fs.install_day
order by fs.install_day desc;


-- 3. Session length (approx: min→max event time within a session) -----------
with s as (
    select session_id,
           extract(epoch from (max(created_at) - min(created_at))) as secs
    from events
    group by session_id
)
select round(avg(secs) / 60.0, 1)                                          as avg_session_min,
       round(percentile_cont(0.5) within group (order by secs) / 60.0, 1)  as median_session_min,
       count(*)                                                            as sessions
from s
where secs > 0;


-- 4. Mode popularity — what do they actually play? --------------------------
select event_name                                                     as mode_start,
       count(*)                                                       as rounds,
       count(distinct user_id)                                        as players
from events
where event_name like '%_round_started'
   or event_name like '%_match_started'
   or event_name like '%_game_started'
   or event_name = 'minigame_entered'
group by event_name
order by rounds desc;


-- 5. Core climb funnel — is the level curve tuned? --------------------------
-- Overall clear rate, plus a per-difficulty-tier breakdown.
select count(*) filter (where event_name = 'level_complete')          as completes,
       count(*) filter (where event_name = 'level_fail')              as fails,
       round(100.0 * count(*) filter (where event_name = 'level_complete')
             / nullif(count(*) filter (where event_name in ('level_complete','level_fail')), 0), 1)
                                                                      as clear_rate_pct
from events
where created_at > now() - interval '14 days';

select properties->>'tier'                                            as level_tier,
       count(*) filter (where event_name = 'level_complete')          as completes,
       count(*) filter (where event_name = 'level_fail')              as fails,
       round(100.0 * count(*) filter (where event_name = 'level_complete')
             / nullif(count(*) filter (where event_name in ('level_complete','level_fail')), 0), 1)
                                                                      as clear_rate_pct
from events
where event_name in ('level_complete', 'level_fail')
group by 1
order by clear_rate_pct;


-- 6. Competitive round completion + win-rate per mode -----------------------
-- Started vs over = do rounds get finished (or rage-quit)?  win-rate from the
-- 'won' property on the *_over events.
select replace(replace(replace(event_name, '_round_over',''), '_match_over',''), '_game_over','') as mode,
       count(*)                                                       as rounds_over,
       count(*) filter (where properties->>'won' = 'true')            as wins,
       round(100.0 * count(*) filter (where properties->>'won' = 'true')
             / nullif(count(*), 0), 1)                                as player_win_pct
from events
where event_name like '%_over'
group by 1
order by rounds_over desc;


-- 7. ⭐ SHARE-RATE — are wins share-worthy? (the virality experiment) --------
-- Shares ÷ round-ends.  Gate: materially > 0 (≈ ≥3%) greenlights clip capture;
-- near-zero means the moments aren't compelling — don't build ReplayKit yet.
select count(*) filter (where event_name = 'result_shared')          as shares,
       count(*) filter (where event_name like '%_over')              as round_ends,
       round(100.0 * count(*) filter (where event_name = 'result_shared')
             / nullif(count(*) filter (where event_name like '%_over'), 0), 2)
                                                                      as share_rate_pct
from events
where created_at > now() - interval '14 days';

-- Share-rate by mode (which moments are worth sharing?)
select coalesce(properties->>'mode', 'unknown')                       as shared_mode,
       count(*)                                                       as shares
from events
where event_name = 'result_shared'
group by 1
order by shares desc;


-- 8. Cosmetic pull — does the catalogue create desire? ----------------------
select properties->>'category'                                        as category,
       properties->>'item'                                            as item,
       properties->>'tier'                                            as tier,
       count(*)                                                       as equips,
       count(distinct user_id)                                        as users
from events
where event_name = 'cosmetic_equipped'
group by 1, 2, 3
order by equips desc
limit 25;

-- Equip volume by rarity tier (is rarity-as-status pulling toward Epic/Legendary?)
select properties->>'tier'                                            as tier,
       count(*)                                                       as equips
from events
where event_name = 'cosmetic_equipped'
group by 1
order by equips desc;


-- 9. Monetization — directional only at this cohort size --------------------
select event_name,
       count(*)                                                       as n,
       count(distinct user_id)                                        as users
from events
where event_name in ('iap_purchased','bundle_purchased','pack_purchased',
                     'cosmetic_purchased','buy_coins_sheet_opened','buy_lives_sheet_opened')
group by event_name
order by n desc;


-- 10. Onboarding completion — do they get past the intro into a round? ------
with cohort as (
    select distinct user_id from events                      -- everyone seen
),
onboarded as (
    select distinct user_id from events
    where event_name in ('welcome_moment_dismissed','onboarding_dismissed')
),
played as (
    select distinct user_id from events
    where event_name like '%_round_started'
       or event_name like '%_match_started'
       or event_name = 'level_complete'
)
select (select count(*) from cohort)                                  as users,
       (select count(*) from onboarded)                               as dismissed_intro,
       (select count(*) from played)                                  as reached_a_round,
       round(100.0 * (select count(*) from played)
             / nullif((select count(*) from cohort), 0), 1)           as pct_reached_a_round
;
