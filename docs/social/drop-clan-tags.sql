-- ===========================================================================
-- Roll Along — PROPOSAL (not numbered yet): clans without tags on the server
--
-- The app no longer shows or asks for a clan tag; clans are identified by
-- name only.  The database still has `clans.tag`:
--   • NOT NULL, no default                       (docs/social-schema.sql)
--   • clans_tag_len: 2–5 characters              (docs/social-schema.sql)
--   • clans_tag_derived: tag = ra_clan_tag_for(name)
--                                                (docs/social-schema-v4.sql)
--   • the old unique index on lower(tag) was already dropped in v4.
-- So the current app keeps sending the one value that check accepts — the
-- two initials + the number ("Swift Rockets 42" -> "SR42"), see
-- PresetNames.hiddenClanTag — and never shows it.
--
-- This file has two parts.  NOTHING here is required for the app to work.
--
-- PART A (safe any time after step 13):
--   A trigger fills `tag` from the name on every insert and rename, so the
--   server no longer depends on the app sending it.  The current build's
--   value is simply overwritten with the same value.
--
-- PART B (commented out — run ONLY when no phone runs a build that still
--   sends or reads `tag`.  The current build still SENDS it on create and
--   rename, so PART B would break creating and renaming clans on it):
--   drops the tag checks, the trigger and the column, and recreates
--   clan_rankings without `tag` (identical to step 13 otherwise).
--
-- Ordering: run after step 13 (docs/social/clan-look.sql), because PART B
-- recreates the clan_rankings view that step 13 defines.  Independent of
-- step 14.  If step 12 or 13 is ever re-run after PART B, they recreate the
-- view WITH `c.tag` and fail (the column is gone): remove `c.tag` from those
-- files first.
-- ===========================================================================

begin;

-- PART A · the server fills the hidden tag itself -------------------------
create or replace function public.ra_clans_fill_tag()
returns trigger language plpgsql as $$
begin
    new.tag := public.ra_clan_tag_for(new.name);
    return new;
end;
$$;

drop trigger if exists clans_fill_tag on public.clans;
create trigger clans_fill_tag
    before insert or update of name, tag on public.clans
    for each row execute function public.ra_clans_fill_tag();

commit;

-- PART B · remove the column (see the warning above) ----------------------
-- begin;
-- drop view if exists public.clan_rankings;
-- create view public.clan_rankings
-- with (security_invoker = true) as
-- select
--     c.id, c.name, c.description, c.owner_id, c.created_at, c.updated_at,
--     c.icon, c.color,
--     count(m.player_id)::int                                              as member_count,
--     coalesce(sum(p.climb_level) filter (where not p.excluded), 0)::int   as total_levels,
--     coalesce(sum(p.total_stars) filter (where not p.excluded), 0)::int   as total_stars,
--     coalesce((select sum(sc.stars)
--                 from public.clan_season_scores sc
--                 join public.players sp on sp.id = sc.player_id and not sp.excluded
--                where sc.clan_id = c.id
--                  and sc.season = date_trunc('month', public.ra_season_now())::date), 0)::int
--                                                                          as season_score,
--     c.season_wins, c.last_season, c.last_season_rank, c.last_season_clans,
--     c.last_season_tier, c.last_season_score
-- from public.clans c
-- left join public.clan_members m on m.clan_id = c.id
-- left join public.players      p on p.id = m.player_id
-- where not c.excluded
-- group by c.id;
-- grant select on public.clan_rankings to authenticated;
--
-- drop trigger if exists clans_fill_tag on public.clans;
-- drop function if exists public.ra_clans_fill_tag();
-- alter table public.clans drop constraint if exists clans_tag_derived;
-- alter table public.clans drop constraint if exists clans_tag_len;
-- drop index if exists public.clans_tag_unique_idx;
-- alter table public.clans drop column if exists tag;
-- commit;

-- ---------------------------------------------------------------------------
-- Check after PART A (read-only).  Expect two true columns.
-- ---------------------------------------------------------------------------
-- select
--     exists (select 1 from pg_trigger
--              where tgname = 'clans_fill_tag'
--                and tgrelid = 'public.clans'::regclass)                  as fill_trigger_present,
--     not exists (select 1 from public.clans
--                  where tag <> public.ra_clan_tag_for(name))               as every_tag_matches_name;
