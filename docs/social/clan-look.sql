-- ===========================================================================
-- Roll Along — database step 13: a clan's icon and color
--
-- The owner picks one icon from a preset set of symbols and one color from a
-- preset palette (Clan settings → Personalization).  No typed text.
--   1. clans          gains `icon` and `color`, each checked against the
--                     same preset lists the app uses (ClanLook in
--                     RollAlong/SocialClient.swift — change both together).
--   2. Who can change them: only the clan's owner, through the existing
--                     "clans update by owner" rule.  Members, other players
--                     and signed-out users cannot.
--   3. clan_rankings  recreated with `icon` and `color`, so the Rankings
--                     list can show them, and without the old `tag`
--                     column (clans are known by name only; step 15
--                     removes the column).  Otherwise identical to the view
--                     in step 12 (docs/social/drop-weekly-pace.sql).
--
-- Run ONCE in the Supabase SQL editor, AFTER step 12 and BEFORE steps 14
-- and 15.  Safe to run again.
-- If step 12 is ever run again, run steps 13 and 15 again right after it
-- (step 12 recreates clan_rankings with the old tag column and without the
-- two new columns).
-- ===========================================================================

begin;

-- 1 · The columns ------------------------------------------------------------
alter table public.clans add column if not exists icon  text not null default 'shield.fill';
alter table public.clans add column if not exists color text not null default 'blue';

alter table public.clans drop constraint if exists clans_icon_preset;
alter table public.clans add constraint clans_icon_preset check (icon in (
    'shield.fill', 'flame.fill', 'bolt.fill', 'star.fill',
    'crown.fill', 'leaf.fill', 'moon.stars.fill', 'sun.max.fill',
    'snowflake', 'drop.fill', 'mountain.2.fill', 'tree.fill',
    'pawprint.fill', 'hare.fill', 'tortoise.fill', 'bird.fill',
    'fish.fill', 'heart.fill', 'diamond.fill', 'trophy.fill',
    'flag.fill', 'sparkles', 'atom', 'puzzlepiece.fill'));

alter table public.clans drop constraint if exists clans_color_preset;
alter table public.clans add constraint clans_color_preset check (color in (
    'red', 'orange', 'gold', 'lime', 'green', 'teal',
    'sky', 'blue', 'indigo', 'purple', 'pink', 'silver'));

-- 2 · Who can change them ---------------------------------------------------
-- Nothing new: "clans update by owner" (docs/social-schema.sql) already
-- limits every update of a clan row to its owner, and the clans_guard
-- trigger (docs/social-schema-v5.sql) keeps the server-owned columns.

-- 3 · Clan rankings with the icon and color ---------------------------------
drop view if exists public.clan_rankings;
create view public.clan_rankings
with (security_invoker = true) as
select
    c.id, c.name, c.description, c.owner_id, c.created_at, c.updated_at,
    c.icon, c.color,
    count(m.player_id)::int                                              as member_count,
    coalesce(sum(p.climb_level) filter (where not p.excluded), 0)::int   as total_levels,
    coalesce(sum(p.total_stars) filter (where not p.excluded), 0)::int   as total_stars,
    coalesce((select sum(sc.stars)
                from public.clan_season_scores sc
                join public.players sp on sp.id = sc.player_id and not sp.excluded
               where sc.clan_id = c.id
                 and sc.season = date_trunc('month', public.ra_season_now())::date), 0)::int
                                                                         as season_score,
    c.season_wins, c.last_season, c.last_season_rank, c.last_season_clans,
    c.last_season_tier, c.last_season_score
from public.clans c
left join public.clan_members m on m.clan_id = c.id
left join public.players      p on p.id = m.player_id
where not c.excluded
group by c.id;

grant select on public.clan_rankings to authenticated;

commit;

-- ---------------------------------------------------------------------------
-- Check (read-only).  Expect four true columns.
-- ---------------------------------------------------------------------------
-- select
--     (select count(*) = 2 from information_schema.columns
--       where table_schema = 'public' and table_name = 'clans'
--         and column_name in ('icon', 'color'))                        as clan_columns,
--     (select count(*) = 2 from pg_constraint
--       where conrelid = 'public.clans'::regclass
--         and conname in ('clans_icon_preset', 'clans_color_preset'))  as preset_checks,
--     (select count(*) = 2 from information_schema.columns
--       where table_schema = 'public' and table_name = 'clan_rankings'
--         and column_name in ('icon', 'color'))                        as rankings_columns,
--     (select count(*) = 0 from public.clans
--       where icon is null or color is null)                          as every_clan_has_a_look;
