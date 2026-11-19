-- ===========================================================================
-- Roll Along — database step 15: clans without tags
--
-- Clans are known by name only.  The app no longer sends, reads or shows a
-- clan tag, so the server's tag and everything that existed only for it go:
--   • the clans_tag_derived check (tag = ra_clan_tag_for(name), social v4)
--   • the clans_tag_len check (2–5 characters, docs/social-schema.sql)
--   • the old unique index on lower(tag) (already dropped in v4; dropped
--     again here only if it is still there)
--   • a fill-in trigger and its function, if an earlier draft of this file
--     was ever run (clans_fill_tag / ra_clans_fill_tag)
--   • the helper function ra_clan_tag_for(text)
--   • the clans.tag column itself
--
-- Nothing else reads or writes the tag: no function, policy, trigger or
-- search uses it, and clan_rankings no longer selects it once step 13 has
-- run (step 13 recreates that view without `tag`).  This file checks that
-- first and stops with a clear message if the view still has `tag`.
--
-- Run ONCE in the Supabase SQL editor, AFTER steps 13 and 14, and only once
-- every phone has the build that no longer sends a tag (an older build's
-- create and rename would be refused).  Safe to run again.
-- If step 12 is ever run again, run steps 13 and 15 again right after it.
-- ===========================================================================

begin;

-- 0 · Guard: clan_rankings must already be the step 13 version ---------------
do $$
begin
    if exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'clan_rankings'
                  and column_name = 'tag') then
        raise exception 'clan_rankings still has the tag column: run step 13 (docs/social/clan-look.sql) first';
    end if;
end
$$;

-- 1 · Anything that only existed for tags -----------------------------------
drop trigger  if exists clans_fill_tag on public.clans;
drop function if exists public.ra_clans_fill_tag();
alter table public.clans drop constraint if exists clans_tag_derived;
alter table public.clans drop constraint if exists clans_tag_len;
drop index    if exists public.clans_tag_unique_idx;

-- 2 · The column, then its helper function ----------------------------------
alter table public.clans drop column if exists tag;
drop function if exists public.ra_clan_tag_for(text);

commit;

-- ---------------------------------------------------------------------------
-- Check (read-only).  Expect four true columns.
-- ---------------------------------------------------------------------------
-- select
--     not exists (select 1 from information_schema.columns
--                  where table_schema = 'public' and table_name in ('clans', 'clan_rankings')
--                    and column_name = 'tag')                        as no_tag_column,
--     not exists (select 1 from pg_constraint
--                  where conrelid = 'public.clans'::regclass
--                    and conname in ('clans_tag_derived', 'clans_tag_len')) as no_tag_checks,
--     not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--                  where n.nspname = 'public'
--                    and p.proname in ('ra_clan_tag_for', 'ra_clans_fill_tag')) as no_tag_functions,
--     (select count(*) >= 0 from public.clan_rankings)                as rankings_still_work;
