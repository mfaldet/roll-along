-- =============================================================================
-- Export the routes marbles took through Adventure levels
-- =============================================================================
-- Read-only. Changes nothing. Paste into the Supabase SQL editor and run, then
-- use the editor's "Export" / "Download CSV" button to save the result.
--
-- WHY
--   From version 1.1 every Adventure run sends the marble's route with its
--   level_complete or level_fail event. Raw events are deleted after 90 days
--   (step 20), and the weekly level table does not keep routes. Run this
--   before then to keep the routes you want.
--
-- WHAT IT RETURNS, one row per run
--   level        the Adventure level number
--   result       'complete' (the marble reached the goal) or 'fail' (it fell)
--   route        the marble's positions in order, as text "x,y;x,y;…".
--                Each number is thousandths of the playfield: 0,0 is the
--                top-left corner and 1000,1000 the bottom-right. These are
--                the level pack's own units times 1000.
--   route_step   seconds of play between two points (0.05 for a run of up to
--                30 seconds; a longer run is thinned and the step doubles).
--                The last point is where the run ended and may come sooner.
--   app_version  the game version that sent the run
--
-- WHAT IS LEFT OUT
--   • Test runs: only events marked build = 'release' (TestFlight and the App
--     Store) are returned.
--   • Runs with no route (other game modes, and versions before 1.1).
--
-- NOTHING HERE IDENTIFIES A PLAYER
--   The result has no install number, session, time or device.
--
-- TO NARROW IT
--   Uncomment one or more of the lines marked OPTIONAL below.
--
-- SIZE
--   A route is about 2 to 5 KB of text. The editor may limit how many rows it
--   shows; if so, export one level or one date range at a time.
-- =============================================================================

select
    e.level                                   as level,
    case e.event_name
        when 'level_complete' then 'complete'
        else 'fail'
    end                                       as result,
    e.properties ->> 'route'                  as route,
    (e.properties ->> 'route_step')::numeric  as route_step,
    e.app_version                             as app_version
from public.events e
where e.event_name in ('level_complete', 'level_fail')
  and e.properties ->> 'build' = 'release'
  and coalesce(e.properties ->> 'route', '') <> ''
  -- OPTIONAL: one level only
  -- and e.level = 37
  -- OPTIONAL: one level pack version only
  -- and (e.properties ->> 'level_pack')::int = 1
  -- OPTIONAL: only runs received on or after a date (UTC)
  -- and e.created_at >= timestamptz '2026-12-01'
  -- OPTIONAL: only runs received before a date (UTC)
  -- and e.created_at <  timestamptz '2027-01-01'
order by e.level, e.created_at;
