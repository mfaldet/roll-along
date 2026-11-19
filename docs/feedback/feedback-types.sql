-- ===========================================================================
-- Roll Along — feedback types (database step 17)
--
-- Run once in Supabase → SQL Editor, after step 16
-- (docs/social/rollup-columns.sql). Safe to run again.
--
-- What it does
--   * Feedback types become bug, idea, question and compliment
--     (they were bug, idea and complaint).
--   * Existing rows stored as "complaint" become "compliment". They are the
--     developer's own test messages: the old third button is the one that
--     became Compliment in the app.
--   * public.submit_feedback(...) accepts exactly the four new types. Its
--     other checks, limits and behavior are unchanged from step 10.
--
-- Order matters: the old type rule is dropped first, then the rows are
-- relabeled, then the new rule is added, so no existing row ever breaks a
-- rule. Nothing else changes.
-- ===========================================================================

-- 1. Drop every CHECK on public.feedback that tests the "kind" column
--    (the step 10 one is named feedback_kind_check by Postgres; this also
--    catches a re-run that already added the new one).
do $$
declare
    c record;
begin
    for c in
        select con.conname
          from pg_constraint con
         where con.conrelid = 'public.feedback'::regclass
           and con.contype = 'c'
           and pg_get_constraintdef(con.oid) ~ '\mkind\M'
    loop
        execute format('alter table public.feedback drop constraint %I', c.conname);
    end loop;
end;
$$;

-- 2. Relabel the old test rows.
update public.feedback set kind = 'compliment' where kind = 'complaint';

-- 3. The new rule.
alter table public.feedback
    add constraint feedback_kind_check
    check (kind in ('bug', 'idea', 'question', 'compliment'));

-- 4. The submit function, with the new list (everything else as in step 10).
create or replace function public.submit_feedback(
    p_client_id    uuid,
    p_kind         text,
    p_message      text,
    p_app_version  text,
    p_os_version   text,
    p_device_model text,
    p_source       text,
    p_install_hash text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_message text := btrim(coalesce(p_message, ''));
    v_recent  int;
begin
    if p_client_id is null then
        raise exception 'feedback: missing client_id' using errcode = '22023';
    end if;
    if p_kind is null or p_kind not in ('bug', 'idea', 'question', 'compliment') then
        raise exception 'feedback: kind must be bug, idea, question or compliment' using errcode = '22023';
    end if;
    if char_length(v_message) < 1 or char_length(v_message) > 1000 then
        raise exception 'feedback: message must be 1 to 1000 characters' using errcode = '22023';
    end if;
    if p_install_hash is null or p_install_hash !~ '^[0-9a-f]{64}$' then
        raise exception 'feedback: bad install hash' using errcode = '22023';
    end if;

    -- A retried send of a message already stored is a quiet no-op.
    if exists (select 1 from public.feedback where client_id = p_client_id) then
        return;
    end if;

    -- Per phone: 5 in a rolling 24 hours.
    select count(*) into v_recent
      from public.feedback
     where install_hash = p_install_hash
       and created_at > now() - interval '24 hours';
    if v_recent >= 5 then
        raise exception 'feedback: limit reached for this phone, try again tomorrow'
              using errcode = 'P0001';
    end if;

    -- Everyone together: 200 an hour (stops a flood from many fake phones).
    select count(*) into v_recent
      from public.feedback
     where created_at > now() - interval '1 hour';
    if v_recent >= 200 then
        raise exception 'feedback: too many messages right now, try again later'
              using errcode = 'P0001';
    end if;

    insert into public.feedback
        (client_id, kind, message, app_version, os_version, device_model,
         source, player_id, install_hash)
    values
        (p_client_id, p_kind, v_message,
         left(coalesce(p_app_version,  ''), 40),
         left(coalesce(p_os_version,   ''), 40),
         left(coalesce(p_device_model, ''), 40),
         left(coalesce(p_source,       ''), 60),
         auth.uid(),
         p_install_hash)
    on conflict (client_id) do nothing;
end;
$$;

revoke all on function public.submit_feedback(uuid, text, text, text, text, text, text, text) from public;
grant execute on function public.submit_feedback(uuid, text, text, text, text, text, text, text)
      to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Check (run on its own after the step; read-only). Expect every column true.
-- ---------------------------------------------------------------------------
-- select
--   not exists (select 1 from public.feedback where kind = 'complaint')         as no_complaint_rows,
--   exists (select 1 from pg_constraint
--            where conrelid = 'public.feedback'::regclass
--              and conname = 'feedback_kind_check'
--              and pg_get_constraintdef(oid) like '%question%'
--              and pg_get_constraintdef(oid) like '%compliment%'
--              and pg_get_constraintdef(oid) not like '%complaint%')           as table_rule_updated,
--   (select count(*) from pg_constraint
--     where conrelid = 'public.feedback'::regclass and contype = 'c'
--       and pg_get_constraintdef(oid) ~ '\mkind\M') = 1                       as one_kind_rule,
--   (select prosrc like '%''question'', ''compliment''%'
--           and prosrc not like '%complaint%'
--      from pg_proc where proname = 'submit_feedback'
--       and pronamespace = 'public'::regnamespace)                            as function_updated,
--   has_function_privilege('anon',
--     'public.submit_feedback(uuid, text, text, text, text, text, text, text)', 'execute')
--     and has_function_privilege('authenticated',
--     'public.submit_feedback(uuid, text, text, text, text, text, text, text)', 'execute') as players_can_submit,
--   not has_table_privilege('anon', 'public.feedback', 'select')
--     and not has_table_privilege('authenticated', 'public.feedback', 'select') as players_still_cannot_read;
