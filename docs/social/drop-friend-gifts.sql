-- ===========================================================================
-- Roll Along — database step 14: lives go only to a clanmate's open request
--
-- The app no longer has "Send life" for friends.  A life can be given only
-- to a clanmate's open request that is not yet filled and that the giver has
-- not already given to.  This step makes the server enforce exactly that and
-- removes the one-gift-per-friend-per-day limit, which nothing else used:
--   1. ra_life_gift_request   rewritten: a gift that does not answer an open
--                             request from a clanmate is refused
--                             ('no_request').  The request rules are
--                             unchanged from docs/social-schema-v5.sql
--                             section 6: one gift per giver per request
--                             ('already_gave'), and the request closes when
--                             it is filled.
--   2. ra_config              the 'gift_per_friend_per_day' row is deleted.
--   3. ra_social_settings     no longer lists that setting.
--
-- Kept on purpose: the life_gifts table (clan request gifts are stored and
-- claimed there), its policies, and the one-per-request index.  Gifts
-- already sent and not yet claimed can still be claimed: this step only
-- changes what may be INSERTED.
--
-- Run ONCE in the Supabase SQL editor, AFTER step 13.  Safe to run again.
-- Run it only after the build without "Send life" is on every test phone:
-- an older build still offers "Send life" to friends, and the server would
-- refuse those gifts (the old build shows "Couldn't send a life").
--
-- Note: re-running the check at the bottom of social-schema-v5.sql after this
-- step reports settings one lower, because the gift setting is gone.  That is
-- expected.  If social-schema-v5.sql is ever run again, it puts the old gift
-- rule and setting back: run this step again right after it.
-- ===========================================================================

begin;

-- 1 · Gifts only answer a clanmate's open request ----------------------------
create or replace function public.ra_life_gift_request()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
    ask       timestamptz;
    req_size  integer  := public.ra_config_int('life_request_size', 6);
    req_life  interval := public.ra_config_int('life_request_hours', 24) * interval '1 hour';
    so_far    integer;
begin
    new.request_at := null;                       -- server-owned
    new.amount     := 1;
    select needs_lives_at into ask from public.players where id = new.recipient_id;
    if ask is not null and ask + req_life <= now() then
        ask := null;                              -- the request has expired
    end if;

    -- No open request, or the two players are not in the same clan.
    if ask is null or not exists (select 1
                     from public.clan_members a
                     join public.clan_members b on b.clan_id = a.clan_id
                    where a.player_id = new.sender_id
                      and b.player_id = new.recipient_id) then
        raise exception 'no_request'
            using hint = 'Lives can only be given to a clanmate''s open request.';
    end if;

    -- One gift per giver per request.
    if exists (select 1 from public.life_gifts
                where sender_id = new.sender_id
                  and recipient_id = new.recipient_id
                  and request_at = ask) then
        raise exception 'already_gave' using hint = 'You already gave a life to this request.';
    end if;

    new.request_at := ask;
    if req_size > 0 then
        select count(*) into so_far from public.life_gifts
         where recipient_id = new.recipient_id and request_at = ask;
        if so_far + 1 >= req_size then            -- filled: close it
            update public.players set needs_lives_at = null where id = new.recipient_id;
        end if;
    end if;
    return new;
end $$;

drop trigger if exists life_gifts_request on public.life_gifts;
create trigger life_gifts_request
    before insert on public.life_gifts
    for each row execute function public.ra_life_gift_request();

-- 2 · The per-friend daily limit is gone --------------------------------------
delete from public.ra_config where key = 'gift_per_friend_per_day';

-- 3 · Settings the app reads, without it --------------------------------------
create or replace function public.ra_social_settings()
returns json
language sql stable security definer set search_path = public as $$
    select coalesce(json_object_agg(key, value), '{}'::json)
      from public.ra_config
     where key in ('clan_member_cap', 'life_request_size', 'life_request_hours',
                   'life_request_cooldown_hours',
                   'season_min_clan_score', 'season_min_member_stars',
                   'season_prizes_from')
$$;
revoke all on function public.ra_social_settings() from public;
grant execute on function public.ra_social_settings() to authenticated;

commit;

-- ---------------------------------------------------------------------------
-- Check.  Expected: three true columns.
-- ---------------------------------------------------------------------------
-- select
--     not exists (select 1 from public.ra_config
--                  where key = 'gift_per_friend_per_day')                      as setting_removed,
--     (select prosrc like '%no_request%' from pg_proc p
--        join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public' and p.proname = 'ra_life_gift_request')     as gifts_need_request,
--     (select count(*) = 1 from pg_trigger
--       where not tgisinternal and tgname = 'life_gifts_request')              as trigger_in_place;
