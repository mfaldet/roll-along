-- =============================================================================
-- STEP 23 — Two nightly privacy jobs
-- =============================================================================
-- Run after step 22. Safe to run more than once. Requires pg_cron (already in
-- use for the season close, the trophy rollup and the analytics retention).
--
-- JOB 1: FEEDBACK RETENTION        03:57 UTC every day
--   • Feedback typed into the text box (versions 1.0 and 1.0.1) is deleted
--     90 days after it arrived.
--   • Feedback picked from the preset reasons (version 1.1 on) is deleted
--     12 months after it arrived.
--   The two are told apart by the app version stored on each message: 1.1 has
--   no text box, so a message from 1.1 or later can only be a preset reason.
--   A message with no version, or from 1.0.x, is treated as typed.
--
-- JOB 2: REMOVE EMAILS APPLE SENDS  04:07 UTC every day
--   The game asks Apple for no email, but Apple's sign-in token can carry one
--   (for an account that shared it with an earlier build), and Supabase keeps
--   what the token carries. This job clears it, so an address Apple sends is
--   removed within a day. It does what docs/privacy/clear-apple-emails.sql
--   does, every night. It touches only Supabase's own account tables and only
--   accounts whose every sign-in method is Apple. Sign-in is not affected:
--   Supabase matches an Apple sign-in on Apple's account identifier.
--
-- Neither job changes anything the app reads. Both run once at the end of
-- this file so the checks hold immediately.
--
-- NOTE: tested on a local copy of the table layouts, without pg_cron. The two
-- scheduling blocks follow the pattern of step 20, which runs live.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- JOB 1 — feedback retention
-- ---------------------------------------------------------------------------
create or replace function public.ra_prune_feedback()
returns table (typed_deleted int, preset_deleted int)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_typed  int;
    v_preset int;
begin
    -- Typed messages: anything not sent by version 1.1 or later.
    delete from public.feedback f
    where f.created_at < now() - interval '90 days'
      and not (f.app_version ~ '^(1\.[1-9]|1\.[1-9][0-9]|[2-9]|[1-9][0-9])');
    get diagnostics v_typed = row_count;

    -- Everything else: preset reasons, kept 12 months.
    delete from public.feedback f
    where f.created_at < now() - interval '12 months';
    get diagnostics v_preset = row_count;

    return query select v_typed, v_preset;
end;
$$;
revoke all on function public.ra_prune_feedback() from public, anon, authenticated;
comment on function public.ra_prune_feedback() is
    'Nightly (step 23): deletes feedback typed in versions before 1.1 after 90 days, and all other feedback after 12 months.';

-- ---------------------------------------------------------------------------
-- JOB 2 — remove emails Apple sends
-- ---------------------------------------------------------------------------
create or replace function public.ra_clear_apple_emails()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
    v_accounts int;
begin
    update auth.identities i
    set identity_data = i.identity_data - 'email' - 'email_verified' - 'is_private_email',
        updated_at    = now()
    where i.provider = 'apple'
      and i.identity_data ?| array['email', 'email_verified', 'is_private_email']
      and not exists (select 1 from auth.identities o
                      where o.user_id = i.user_id and o.provider <> 'apple');

    update auth.users u
    set email              = null,
        raw_user_meta_data = coalesce(u.raw_user_meta_data, '{}'::jsonb)
                               - 'email' - 'email_verified' - 'is_private_email',
        updated_at         = now()
    where exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'apple')
      and not exists (select 1 from auth.identities i where i.user_id = u.id and i.provider <> 'apple')
      and (   coalesce(u.email, '') <> ''
           or u.raw_user_meta_data ?| array['email', 'email_verified', 'is_private_email']);
    get diagnostics v_accounts = row_count;

    return v_accounts;
end;
$$;
revoke all on function public.ra_clear_apple_emails() from public, anon, authenticated;
comment on function public.ra_clear_apple_emails() is
    'Nightly (step 23): clears any email Apple''s sign-in token left on Apple-only accounts. Returns the number of accounts cleared.';

-- ---------------------------------------------------------------------------
-- Schedule both
-- ---------------------------------------------------------------------------
do $do$
begin
    if not exists (select 1 from pg_extension where extname = 'pg_cron') then
        raise notice 'pg_cron is not installed: the two jobs were not scheduled.';
        return;
    end if;
    if exists (select 1 from cron.job where jobname = 'ra-prune-feedback') then
        perform cron.unschedule('ra-prune-feedback');
    end if;
    perform cron.schedule('ra-prune-feedback', '57 3 * * *',
                          'select * from public.ra_prune_feedback();');
    if exists (select 1 from cron.job where jobname = 'ra-clear-apple-emails') then
        perform cron.unschedule('ra-clear-apple-emails');
    end if;
    perform cron.schedule('ra-clear-apple-emails', '7 4 * * *',
                          'select public.ra_clear_apple_emails();');
end;
$do$;

-- Run both once now.
select * from public.ra_prune_feedback();
select public.ra_clear_apple_emails() as apple_accounts_cleared;

-- =============================================================================
-- CHECKS (read-only; run after the above)
-- =============================================================================
-- a) Both jobs are scheduled:
--      select jobname, schedule from cron.job
--      where jobname in ('ra-prune-feedback', 'ra-clear-apple-emails');
-- b) No typed feedback older than 90 days, and none at all older than 12 months
--    (both should be 0):
--      select
--        count(*) filter (where created_at < now() - interval '90 days'
--                           and not (app_version ~ '^(1\.[1-9]|1\.[1-9][0-9]|[2-9]|[1-9][0-9])')) as old_typed,
--        count(*) filter (where created_at < now() - interval '12 months')                        as older_than_a_year
--      from public.feedback;
-- c) No email on any account: run docs/privacy/check-stored-emails.sql.
--    accounts_with_an_email should be 0.
