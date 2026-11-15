-- ===========================================================================
-- Roll Along — the two scheduled jobs.  Run ONCE in the Supabase SQL editor,
-- after docs/social-schema-v5.sql.  Safe to run again: scheduling a job under
-- a name that already exists replaces it.
--
-- Times are UTC.
-- ===========================================================================
create extension if not exists pg_cron;

-- Month end: every day at 00:10 UTC, close any finished month that has not
-- been closed yet.  On the 1st this closes the month that just ended; on any
-- other day it does nothing (or catches up a missed run).
select cron.schedule('ra-close-season', '10 0 * * *',
                     $$select public.ra_close_season()$$);

-- Life requests: every 15 minutes, close the ones older than the limit.
select cron.schedule('ra-expire-life-requests', '*/15 * * * *',
                     $$select public.ra_expire_life_requests()$$);

-- Check: expect two rows.
select jobname, schedule, active from cron.job where jobname like 'ra-%' order by jobname;

-- To stop a job later:
--   select cron.unschedule('ra-close-season');
--   select cron.unschedule('ra-expire-life-requests');
