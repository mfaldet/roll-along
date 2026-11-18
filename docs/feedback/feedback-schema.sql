-- ===========================================================================
-- Roll Along — Send Feedback (database step 10)
--
-- Run once in Supabase → SQL Editor, after step 9
-- (docs/trophies/trophy-schema-fix-1.sql). Safe to run again.
--
-- What it does
--   * Creates public.feedback: one row per message a player sends from
--     Settings → Send Feedback.
--   * Players can WRITE feedback but can never READ it, including their own.
--     The table has row security on and no policies, and the app roles get no
--     table rights at all. The only way in is the function below. You read it
--     in the dashboard (Table Editor or SQL Editor), which uses the owner role.
--   * public.submit_feedback(...) checks and stores one message:
--       - kind is bug, idea or complaint; message 1 to 1,000 characters;
--       - the other fields are short (version, iOS, model, screen);
--       - player_id comes from the sign-in token (auth.uid()), never from
--         the request, so nobody can file feedback as someone else;
--       - a resend of the same message (same client_id) is ignored;
--       - at most 5 messages per phone per rolling 24 hours, and at most
--         200 per hour across all players, so it can't be flooded.
--   * Feedback sent while signed in is deleted with the account
--     (player_id references auth.users with on delete cascade).
--   * The phone is identified only by a one-way hash of its random install
--     ID (install_hash), used for the limit above. It is not the account,
--     not the advertising ID, and does not match the analytics install ID.
--
-- Nothing here changes any other table.
-- ===========================================================================

create table if not exists public.feedback (
    id            bigint generated always as identity primary key,
    client_id     uuid        not null unique,
    created_at    timestamptz not null default now(),
    kind          text        not null check (kind in ('bug', 'idea', 'complaint')),
    message       text        not null check (char_length(message) between 1 and 1000),
    app_version   text        not null default '' check (char_length(app_version)  <= 40),
    os_version    text        not null default '' check (char_length(os_version)   <= 40),
    device_model  text        not null default '' check (char_length(device_model) <= 40),
    source        text        not null default '' check (char_length(source)       <= 60),
    -- Deleting the account (Settings → Delete Account removes the auth user)
    -- deletes the feedback that player sent while signed in.
    player_id     uuid        null references auth.users (id) on delete cascade,
    install_hash  text        not null check (install_hash ~ '^[0-9a-f]{64}$')
);

create index if not exists feedback_created_at_idx   on public.feedback (created_at desc);
create index if not exists feedback_install_rate_idx on public.feedback (install_hash, created_at);

alter table public.feedback enable row level security;
-- No policies on purpose: with row security on and no policy, the app roles
-- can neither read nor write rows directly.
revoke all on table public.feedback from anon, authenticated;
revoke all on sequence public.feedback_id_seq from anon, authenticated;

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
    if p_kind is null or p_kind not in ('bug', 'idea', 'complaint') then
        raise exception 'feedback: kind must be bug, idea or complaint' using errcode = '22023';
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
--   to_regclass('public.feedback') is not null                                    as table_exists,
--   (select relrowsecurity from pg_class where oid = 'public.feedback'::regclass) as row_security_on,
--   not has_table_privilege('anon', 'public.feedback', 'select')
--     and not has_table_privilege('authenticated', 'public.feedback', 'select')  as players_cannot_read,
--   not has_table_privilege('anon', 'public.feedback', 'insert')
--     and not has_table_privilege('authenticated', 'public.feedback', 'insert')  as no_direct_insert,
--   has_function_privilege('anon',
--     'public.submit_feedback(uuid, text, text, text, text, text, text, text)', 'execute')
--                                                                                  as players_can_send;
