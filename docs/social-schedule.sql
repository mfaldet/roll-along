-- ===========================================================================
-- Roll Along — the two scheduled jobs.  Run ONCE in the Supabase SQL editor,
-- after docs/social-schema-v5.sql.  Safe to run again: scheduling a job under
-- a name that already exists replaces it.
--
-- The scheduler's own clock is UTC, but midnight Eastern is 05:00 UTC in
-- winter and 04:00 UTC in summer.  So the month-end job runs EVERY HOUR and
-- decides for itself, in Eastern time, whether a month has ended.
-- ===========================================================================
create extension if not exists pg_cron;

-- Month end: at ten past every hour, close any finished month (Eastern time)
-- that has not been closed yet.  The first run after midnight Eastern on the
-- 1st closes the month that just ended; every other run does nothing.
select cron.schedule('ra-close-season', '10 * * * *',
                     $$select public.ra_close_season()$$);

-- Life requests: every 15 minutes, close the ones older than the limit.
select cron.schedule('ra-expire-life-requests', '*/15 * * * *',
                     $$select public.ra_expire_life_requests()$$);

-- Check: expect two rows.
select jobname, schedule, active from cron.job where jobname like 'ra-%' order by jobname;

-- To stop a job later:
--   select cron.unschedule('ra-close-season');
--   select cron.unschedule('ra-expire-life-requests');
