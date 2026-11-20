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
--   The only dated releases left are full collections:
--     Feb 11, 2027  Candyland + Nightclub
--     Apr  1, 2027  Golf + Bloom
--     Jun  3, 2027  Ocean
--   Launch collections have no row (always available), as before.
--   Seasonal rows (ends_on not null) are KEPT unchanged: seasonal events keep
--   their yearly windows; an event now only features a full collection.
--
-- THE APP DOES NOT NEED THIS STEP TO BEHAVE CORRECTLY: it ignores rows whose
--   id is not a dated full collection.  The step only tidies the table so it
--   shows exactly what is scheduled.  Dates you have edited for the five
--   collections above are kept.
-- =============================================================================

begin;

-- 1. Remove release rows for retired collections and loose slots.
delete from public.cosmetic_calendar
 where ends_on is null
   and collection_id not in ('candyland', 'nightclub', 'golf', 'bloom', 'ocean');

-- 2. Make sure the five dated full collections have a row (insert only if
--    missing, so a date edited in the dashboard is never overwritten).
insert into public.cosmetic_calendar (collection_id, starts_on, ends_on, note)
select v.collection_id, v.starts_on, null, v.note
  from (values
        ('candyland', date '2027-02-11', 'Feb 11 2027 release (with Nightclub)'),
        ('nightclub', date '2027-02-11', 'Feb 11 2027 release (with Candyland)'),
        ('golf',      date '2027-04-01', 'Apr 1 2027 release (with Bloom)'),
        ('bloom',     date '2027-04-01', 'Apr 1 2027 release (with Golf)'),
        ('ocean',     date '2027-06-03', 'Jun 3 2027 release')
       ) as v(collection_id, starts_on, note)
 where not exists (
        select 1 from public.cosmetic_calendar c
         where c.collection_id = v.collection_id and c.ends_on is null);

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
--   (select count(*) from public.cosmetic_calendar where ends_on is not null) >= 48 as seasonal_rows_kept,
--   has_table_privilege('anon', 'public.cosmetic_calendar', 'select')
--     and not has_table_privilege('anon', 'public.cosmetic_calendar', 'insert')
--     and not has_table_privilege('authenticated', 'public.cosmetic_calendar', 'delete')
--                                                                                  as app_reads_only;
