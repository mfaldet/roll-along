-- =============================================================================
-- STEP 21 — Release calendar: every release is one or two FULL collections.
-- =============================================================================
-- Run AFTER step 20.  Safe to run more than once.  Changes rows only in
-- public.cosmetic_calendar (step 11); no table, policy or grant changes.
--
-- WHY
--   A cosmetic is now on sale only as part of a full active collection (all
--   six slots: ball, goal, trail, floor, pit, boundary).  Pieces of retired
--   sets and pieces in no collection are held, so they have no release day:
--     • the 32 retired permanent collections no longer release anything;
--     • the three loose single-piece slots (_loose-1/2/3) are gone.
--   The only dated releases left are full collections, on the dates the owner
--   set on November 20, 2026:
--     Dec 17, 2026  Candyland + Nightclub
--     Jan 14, 2027  Golf + Bloom
--     Feb 11, 2027  Ocean
--   Launch collections have no row (always available), as before.
--   Seasonal rows (ends_on not null) are KEPT unchanged: seasonal events keep
--   their yearly windows; an event now only features a full collection.
--
-- THIS STEP SETS THE FIVE DATES.  Step 11 seeded the live table with the OLD
--   dates for these five (Candyland and Nightclub Feb 11, 2027; Golf and Bloom
--   Apr 1, 2027; Ocean Jun 3, 2027).  This step overwrites them with the dates
--   above, on purpose, and inserts a row if one is missing.
--
-- UNTIL THIS STEP IS APPLIED the app keeps showing the OLD dates: the app
--   prefers the dates in this table over the ones built into it, and the live
--   table still holds the old ones.  The new dates are built into the app, but
--   they only apply when the server has no row for a collection or cannot be
--   reached.  Apply this step before Dec 17, 2026, or Candyland and Nightclub
--   will not release that day.  (A phone that has never reached the server
--   uses the built-in dates and releases them on Dec 17 regardless.)
--
-- RE-RUNNING: safe, but it sets the five dates back to the ones in this file.
--   To change a date later, edit the row in the dashboard and do not re-run
--   this file (or change the date here first).
-- =============================================================================

begin;

-- 1. Remove release rows for retired collections and loose slots.
delete from public.cosmetic_calendar
 where ends_on is null
   and collection_id not in ('candyland', 'nightclub', 'golf', 'bloom', 'ocean');

-- 2. Set the five dated full collections to their release days: move the row
--    if it holds another date, insert it if it is missing.
with wanted(collection_id, starts_on, note) as (
    values
        ('candyland', date '2026-12-17', 'Dec 17 2026 release (with Nightclub)'),
        ('nightclub', date '2026-12-17', 'Dec 17 2026 release (with Candyland)'),
        ('golf',      date '2027-01-14', 'Jan 14 2027 release (with Bloom)'),
        ('bloom',     date '2027-01-14', 'Jan 14 2027 release (with Golf)'),
        ('ocean',     date '2027-02-11', 'Feb 11 2027 release')
), moved as (
    update public.cosmetic_calendar c
       set starts_on = w.starts_on, note = w.note
      from wanted w
     where c.collection_id = w.collection_id
       and c.ends_on is null
       and (c.starts_on <> w.starts_on or c.note is distinct from w.note)
    returning c.collection_id
)
insert into public.cosmetic_calendar (collection_id, starts_on, ends_on, note)
select w.collection_id, w.starts_on, null, w.note
  from wanted w
 where not exists (
        select 1 from public.cosmetic_calendar c
         where c.collection_id = w.collection_id and c.ends_on is null);

commit;

-- To see what is scheduled, run:
--   select collection_id, starts_on, ends_on, note from public.cosmetic_calendar
--    order by ends_on is not null, starts_on, collection_id;

-- =============================================================================
-- CHECK — every column should be true.
-- =============================================================================
-- select
--   not exists (select 1 from public.cosmetic_calendar
--                where collection_id like '\_loose%')                              as no_loose_slots,
--   not exists (select 1 from public.cosmetic_calendar
--                where ends_on is null
--                  and collection_id not in ('candyland','nightclub','golf','bloom','ocean'))
--                                                                                  as only_full_collections,
--   (select count(*) from public.cosmetic_calendar where ends_on is null) = 5      as five_release_rows,
--   (select count(*) from public.cosmetic_calendar
--     where ends_on is null
--       and (collection_id, starts_on) in (('candyland', date '2026-12-17'), ('nightclub', date '2026-12-17'),
--                                          ('golf', date '2027-01-14'), ('bloom', date '2027-01-14'),
--                                          ('ocean', date '2027-02-11'))) = 5       as five_dates_set,
--   (select count(*) from public.cosmetic_calendar where ends_on is not null) >= 48 as seasonal_rows_kept,
--   has_table_privilege('anon', 'public.cosmetic_calendar', 'select')
--     and not has_table_privilege('anon', 'public.cosmetic_calendar', 'insert')
--     and not has_table_privilege('authenticated', 'public.cosmetic_calendar', 'delete')
--                                                                                  as app_reads_only;
