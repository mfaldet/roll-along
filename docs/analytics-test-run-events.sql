-- =============================================================================
-- Roll Along — find analytics events that came from TEST RUNS (read-only)
-- =============================================================================
-- Before the RuntimeEnvironment switch, running Product > Test on a phone sent
-- the test host's events to public.events. Nothing marks them as test events,
-- so this query finds them by their shape. It only SELECTs; it changes nothing.
--
-- How reliable is it?
--   • A test run is one process launch, so it is one session_id. Every event a
--     test run sent shares that session_id: that is the unit flagged below.
--   • The user_id is NOT a test signal: the test host is the real app on the
--     same phone, so it shares the phone's real install id (and so does the
--     trophy_unlocks.install_id).
--   • The flag is "a burst no human can play": many minigame_result /
--     trophy_unlocked events packed into a few seconds or minutes. A real
--     session spaces minigames out by tens of seconds each. Expect it to catch
--     unit-test runs reliably; a short UI-test run that only taps through
--     menus sends few events and may not be flagged (and also does little
--     harm). Look at the flagged sessions before acting on them.
--   • Tune the thresholds in `params` if needed.
-- =============================================================================

with params as (
    select
        interval '30 days' as lookback,
        20                 as min_burst_events,   -- minigame_result + trophy_unlocked
        2.0                as min_events_per_min  -- sustained rate no human reaches
),
per_session as (
    select
        e.session_id,
        e.user_id,
        min(e.created_at)                                              as started_at,
        max(e.created_at)                                              as ended_at,
        extract(epoch from max(e.created_at) - min(e.created_at))      as span_s,
        count(*)                                                       as events,
        count(*) filter (where e.event_name = 'minigame_result')       as minigame_results,
        count(*) filter (where e.event_name = 'trophy_unlocked')       as trophy_unlocks,
        count(*) filter (where e.event_name = 'app_launch')            as app_launches,
        max(e.app_version)                                             as app_version,
        max(e.device_model)                                            as device_model
    from public.events e, params p
    where e.created_at > now() - p.lookback
    group by e.session_id, e.user_id
)
select
    s.*,
    round(((s.minigame_results + s.trophy_unlocks)
           / greatest(s.span_s / 60.0, 1.0 / 60))::numeric, 1)       as burst_per_min
from per_session s, params p
where s.minigame_results + s.trophy_unlocks >= p.min_burst_events
  and (s.minigame_results + s.trophy_unlocks)
      / greatest(s.span_s / 60.0, 1.0 / 60) >= p.min_events_per_min
order by s.started_at desc;

-- To list the individual events of the flagged sessions, wrap the query above
-- as a CTE named `flagged` and run:
--   select e.* from public.events e join flagged f using (session_id)
--   order by e.created_at;
