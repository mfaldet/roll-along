-- ===========================================================================
-- Step 19 · Clan season prizes: the server pays what the app shows
--
-- Run AFTER step 18 (docs/social/rollup-height-only.sql).  Safe to run again.
--
-- Why (2026-11 payout audit, docs/economy/2026-11-payout-audit.md):
--   1. social-schema-v5.sql inserts the four season_coins_* rows with
--      "on conflict do nothing", so a database where an earlier draft ran
--      keeps whatever amounts it had.  This step sets them to the design
--      amounts the app and the review notes state:
--          Diamond 1,000 · Gold 500 · Silver 250 · Bronze 100 (per member).
--   2. ra_social_settings now also returns those four numbers, so the
--      Rankings season card shows the server's own amounts instead of a copy
--      built into the app.  Its other keys are the same as step 14's.
--
-- Nothing else changes: who qualifies, tiers, the warm-up season
-- (season_prizes_from) and the claim function are untouched.
-- ===========================================================================

begin;

-- 1 · The four prize amounts --------------------------------------------------
insert into public.ra_config (key, value, note) values
    ('season_coins_diamond', 1000, 'Prize per eligible member (about one cosmetic)'),
    ('season_coins_gold',     500, 'Prize per eligible member'),
    ('season_coins_silver',   250, 'Prize per eligible member'),
    ('season_coins_bronze',   100, 'Prize per eligible member')
on conflict (key) do update set value = excluded.value;

-- 2 · Settings the app reads, now with the prize amounts ----------------------
create or replace function public.ra_social_settings()
returns json
language sql stable security definer set search_path = public as $$
    select coalesce(json_object_agg(key, value), '{}'::json)
      from public.ra_config
     where key in ('clan_member_cap', 'life_request_size', 'life_request_hours',
                   'life_request_cooldown_hours',
                   'season_min_clan_score', 'season_min_member_stars',
                   'season_prizes_from',
                   'season_coins_diamond', 'season_coins_gold',
                   'season_coins_silver', 'season_coins_bronze')
$$;
revoke all on function public.ra_social_settings() from public;
grant execute on function public.ra_social_settings() to authenticated;

commit;

-- ---------------------------------------------------------------------------
-- Check.  Expected: three true columns.
-- ---------------------------------------------------------------------------
-- select
--     (select array_agg(value order by key) from public.ra_config
--       where key in ('season_coins_bronze', 'season_coins_diamond',
--                     'season_coins_gold', 'season_coins_silver'))
--         = array[100, 1000, 500, 250]                          as prize_amounts,
--     (public.ra_social_settings()::jsonb ->> 'season_coins_diamond')::int = 1000
--                                                               as settings_show_prizes,
--     not (public.ra_social_settings()::jsonb ? 'gift_per_friend_per_day')
--                                                               as no_friend_gift_limit;
