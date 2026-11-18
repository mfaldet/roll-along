-- ===========================================================================
-- Roll Along — DATABASE STEP 11: the cosmetic release calendar.
--
-- Run after step 10 (docs/feedback/feedback-schema.sql).  Safe to run more
-- than once: it never overwrites a date you have changed in the dashboard.
--
-- What it is
--   One table, public.cosmetic_calendar, that the app reads at launch and on
--   return (at most every 6 hours) and caches.  The app has the same dates
--   built in (CosmeticSchedule in RollAlong/Cosmetics.swift) and uses them
--   when it has never reached the server.  Changing a date here needs no app
--   update.
--
--   • Permanent collections: one row each, ends_on NULL.  The collection is
--     released at midnight EASTERN (America/New_York) at the start of
--     starts_on.  Launch collections have no row; they are always available.
--   • Items in no collection: three rows, _loose-1, _loose-2, _loose-3.
--   • Seasonal collections: one row per year.  Open from midnight Eastern on
--     starts_on until midnight Eastern on ends_on (ends_on is the FIRST day
--     it is gone).  A year with no row uses the yearly window built into the
--     app.
--
-- Editing
--   Change a date: update starts_on / ends_on in the Table Editor.
--   Remove a row: that collection goes back to its built-in date.
--   A collection a phone has already seen released stays released there even
--   if you move its date later.  Owned items are never taken away.
--   Rows with an id the app doesn't know are ignored.
--
-- Access: anyone (signed in or not) may READ.  Nobody can write from the app;
-- only you, in the dashboard (service role).
-- ===========================================================================

create table if not exists public.cosmetic_calendar (
  collection_id text        not null check (length(collection_id) between 1 and 64),
  starts_on     date        not null,
  ends_on       date        null,
  note          text        null,
  updated_at    timestamptz not null default now(),
  primary key (collection_id, starts_on),
  constraint cosmetic_calendar_window_order check (ends_on is null or ends_on > starts_on)
);

comment on table public.cosmetic_calendar is
  'Cosmetic release calendar read by the app (step 11). Permanent rows: ends_on null, released at midnight America/New_York on starts_on. Seasonal rows: one per year, open starts_on to ends_on (first day gone).';

-- One permanent row per collection; one seasonal row per collection per year.
create unique index if not exists cosmetic_calendar_one_release
  on public.cosmetic_calendar (collection_id) where ends_on is null;
create unique index if not exists cosmetic_calendar_one_window_per_year
  on public.cosmetic_calendar (collection_id, (extract(year from starts_on))) where ends_on is not null;

-- updated_at follows edits made in the dashboard.
create or replace function public.cosmetic_calendar_touch()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists cosmetic_calendar_touch on public.cosmetic_calendar;
create trigger cosmetic_calendar_touch
  before update on public.cosmetic_calendar
  for each row execute function public.cosmetic_calendar_touch();

-- Read-only for the app's roles.
alter table public.cosmetic_calendar enable row level security;
revoke all on public.cosmetic_calendar from anon, authenticated;
grant select on public.cosmetic_calendar to anon, authenticated;

drop policy if exists cosmetic_calendar_read on public.cosmetic_calendar;
create policy cosmetic_calendar_read on public.cosmetic_calendar
  for select to anon, authenticated using (true);

-- Seed: the approved calendar (docs/proposals/cosmetic-calendar.md).
-- 40 permanent rows (37 collections + 3 loose slots) and 48 seasonal
-- rows (16 collections x 2026, 2027, 2028).  A row is only added when that
-- collection (and, for seasonal rows, that year) has no row yet, so dates you
-- have edited are kept.
insert into public.cosmetic_calendar (collection_id, starts_on, ends_on, note)
select v.collection_id, v.starts_on, v.ends_on, v.note
from (values
  ('cathedral', date '2026-12-17', null, 'Drop 1, ahead of Christmas'),
  ('velvet-night', date '2026-12-17', null, 'Drop 1, ahead of Christmas'),
  ('crystal-cavern', date '2026-12-17', null, 'Drop 1, ahead of Christmas'),
  ('zen-garden', date '2027-01-14', null, 'Drop 2, new year'),
  ('clockwork', date '2027-01-14', null, 'Drop 2, new year'),
  ('noir', date '2027-01-14', null, 'Drop 2, new year'),
  ('candyland', date '2027-02-11', null, 'Drop 3, Valentine''s week'),
  ('nightclub', date '2027-02-11', null, 'Drop 3, Valentine''s week'),
  ('heavens', date '2027-02-11', null, 'Drop 3, Valentine''s week'),
  ('full-court', date '2027-03-11', null, 'Drop 4, ahead of March Madness'),
  ('planets', date '2027-03-11', null, 'Drop 4, ahead of March Madness'),
  ('space-travel', date '2027-03-11', null, 'Drop 4, ahead of March Madness'),
  ('diamond', date '2027-04-01', null, 'Drop 5, Opening Day, the Masters, spring'),
  ('golf', date '2027-04-01', null, 'Drop 5, Opening Day, the Masters, spring'),
  ('bloom', date '2027-04-01', null, 'Drop 5, Opening Day, the Masters, spring'),
  ('pastel', date '2027-04-01', null, 'Drop 5, Opening Day, the Masters, spring'),
  ('arcade', date '2027-05-06', null, 'Drop 6'),
  ('lava-lamp', date '2027-05-06', null, 'Drop 6'),
  ('plasma-globe', date '2027-05-06', null, 'Drop 6'),
  ('tempest', date '2027-05-06', null, 'Drop 6'),
  ('ocean', date '2027-06-03', null, 'Drop 7, start of summer'),
  ('aquarium', date '2027-06-03', null, 'Drop 7, start of summer'),
  ('soccer', date '2027-06-03', null, 'Drop 7, start of summer'),
  ('golden-hour', date '2027-07-01', null, 'Drop 8, high summer'),
  ('dune', date '2027-07-01', null, 'Drop 8, high summer'),
  ('paper-world', date '2027-07-01', null, 'Drop 8, high summer'),
  ('eclipse', date '2027-07-29', null, 'Drop 9, ahead of the Aug 2 eclipse'),
  ('magma-core', date '2027-07-29', null, 'Drop 9, ahead of the Aug 2 eclipse'),
  ('billiards-hall', date '2027-09-02', null, 'Drop 10, fall'),
  ('geode', date '2027-09-02', null, 'Drop 10, fall'),
  ('realistic-marble', date '2027-09-02', null, 'Drop 10, fall'),
  ('hellfire', date '2027-10-07', null, 'Drop 11, ahead of Halloween'),
  ('midnight-carnival', date '2027-10-07', null, 'Drop 11, ahead of Halloween'),
  ('oracle', date '2027-10-07', null, 'Drop 11, ahead of Halloween'),
  ('high-roller', date '2027-11-11', null, 'Drop 12, ahead of Black Friday'),
  ('neon-city', date '2027-11-11', null, 'Drop 12, ahead of Black Friday'),
  ('quicksilver', date '2027-11-11', null, 'Drop 12, ahead of Black Friday'),
  ('_loose-1', date '2027-02-11', null, 'Items in no collection, slot 1'),
  ('_loose-2', date '2027-05-06', null, 'Items in no collection, slot 2'),
  ('_loose-3', date '2027-07-29', null, 'Items in no collection, slot 3'),
  ('winter-2026', date '2026-12-01', date '2027-01-06', 'Winter Wonderland 2026'),
  ('newyear-2027', date '2026-12-26', date '2027-01-05', 'Countdown 2026'),
  ('valentines-2027', date '2026-02-01', date '2026-02-15', 'Sweetheart 2026'),
  ('stpatricks-2027', date '2026-03-01', date '2026-03-18', 'Luck of the Roll 2026'),
  ('spring-2027', date '2026-03-20', date '2026-05-01', 'Spring Fling 2026'),
  ('earthday-2027', date '2026-04-12', date '2026-04-26', 'Earth Day 2026'),
  ('pride-2027', date '2026-06-01', date '2026-06-30', 'Spectrum 2026'),
  ('summer-2026', date '2026-06-01', date '2026-09-01', 'Summer Vibes 2026'),
  ('july4-2026', date '2026-06-21', date '2026-07-06', 'Star-Spangled 2026'),
  ('backtoschool-2026', date '2026-08-01', date '2026-09-08', 'Back to School 2026'),
  ('halloween-2026', date '2026-10-01', date '2026-11-01', 'Trick or Roll 2026'),
  ('muertos-2026', date '2026-10-21', date '2026-11-03', 'Dia de los Muertos 2026'),
  ('harvest-2026', date '2026-11-01', date '2026-11-30', 'Harvest Moon 2026'),
  ('lunar-2027', date '2026-01-27', date '2026-02-20', 'Lunar New Year 2026'),
  ('mardigras-2027', date '2026-01-28', date '2026-02-10', 'Mardi Gras 2026'),
  ('oktoberfest-2026', date '2026-09-16', date '2026-10-04', 'Oktoberfest 2026'),
  ('winter-2026', date '2027-12-01', date '2028-01-06', 'Winter Wonderland 2027'),
  ('newyear-2027', date '2027-12-26', date '2028-01-05', 'Countdown 2027'),
  ('valentines-2027', date '2027-02-01', date '2027-02-15', 'Sweetheart 2027'),
  ('stpatricks-2027', date '2027-03-01', date '2027-03-18', 'Luck of the Roll 2027'),
  ('spring-2027', date '2027-03-20', date '2027-05-01', 'Spring Fling 2027'),
  ('earthday-2027', date '2027-04-12', date '2027-04-26', 'Earth Day 2027'),
  ('pride-2027', date '2027-06-01', date '2027-06-30', 'Spectrum 2027'),
  ('summer-2026', date '2027-06-01', date '2027-09-01', 'Summer Vibes 2027'),
  ('july4-2026', date '2027-06-21', date '2027-07-06', 'Star-Spangled 2027'),
  ('backtoschool-2026', date '2027-08-01', date '2027-09-08', 'Back to School 2027'),
  ('halloween-2026', date '2027-10-01', date '2027-11-01', 'Trick or Roll 2027'),
  ('muertos-2026', date '2027-10-21', date '2027-11-03', 'Dia de los Muertos 2027'),
  ('harvest-2026', date '2027-11-01', date '2027-11-30', 'Harvest Moon 2027'),
  ('lunar-2027', date '2027-01-27', date '2027-02-20', 'Lunar New Year 2027'),
  ('mardigras-2027', date '2027-01-28', date '2027-02-10', 'Mardi Gras 2027'),
  ('oktoberfest-2026', date '2027-09-16', date '2027-10-04', 'Oktoberfest 2027'),
  ('winter-2026', date '2028-12-01', date '2029-01-06', 'Winter Wonderland 2028'),
  ('newyear-2027', date '2028-12-26', date '2029-01-05', 'Countdown 2028'),
  ('valentines-2027', date '2028-02-01', date '2028-02-15', 'Sweetheart 2028'),
  ('stpatricks-2027', date '2028-03-01', date '2028-03-18', 'Luck of the Roll 2028'),
  ('spring-2027', date '2028-03-20', date '2028-05-01', 'Spring Fling 2028'),
  ('earthday-2027', date '2028-04-12', date '2028-04-26', 'Earth Day 2028'),
  ('pride-2027', date '2028-06-01', date '2028-06-30', 'Spectrum 2028'),
  ('summer-2026', date '2028-06-01', date '2028-09-01', 'Summer Vibes 2028'),
  ('july4-2026', date '2028-06-21', date '2028-07-06', 'Star-Spangled 2028'),
  ('backtoschool-2026', date '2028-08-01', date '2028-09-08', 'Back to School 2028'),
  ('halloween-2026', date '2028-10-01', date '2028-11-01', 'Trick or Roll 2028'),
  ('muertos-2026', date '2028-10-21', date '2028-11-03', 'Dia de los Muertos 2028'),
  ('harvest-2026', date '2028-11-01', date '2028-11-30', 'Harvest Moon 2028'),
  ('lunar-2027', date '2028-01-16', date '2028-02-10', 'Lunar New Year 2028'),
  ('mardigras-2027', date '2028-02-17', date '2028-03-01', 'Mardi Gras 2028'),
  ('oktoberfest-2026', date '2028-09-14', date '2028-10-04', 'Oktoberfest 2028')
) as v(collection_id, starts_on, ends_on, note)
where not exists (
  select 1 from public.cosmetic_calendar c
  where c.collection_id = v.collection_id
    and (
      (v.ends_on is null and c.ends_on is null)
      or (v.ends_on is not null and c.ends_on is not null
          and extract(year from c.starts_on) = extract(year from v.starts_on))
    )
);

-- ---------------------------------------------------------------------------
-- Check (expect every column true):
--
-- select
--   to_regclass('public.cosmetic_calendar') is not null                          as table_exists,
--   (select relrowsecurity from pg_class where oid = 'public.cosmetic_calendar'::regclass) as rls_on,
--   has_table_privilege('anon', 'public.cosmetic_calendar', 'select')             as anon_can_read,
--   not has_table_privilege('anon', 'public.cosmetic_calendar', 'insert')
--     and not has_table_privilege('authenticated', 'public.cosmetic_calendar', 'update')
--     and not has_table_privilege('authenticated', 'public.cosmetic_calendar', 'delete') as app_cannot_write,
--   (select count(*) from public.cosmetic_calendar where ends_on is null) >= 40  as permanent_rows,
--   (select count(*) from public.cosmetic_calendar where ends_on is not null) >= 48 as seasonal_rows;
--
-- Read the calendar, earliest first:
--
-- select collection_id, starts_on, ends_on, note
-- from public.cosmetic_calendar
-- order by starts_on, collection_id;
-- ---------------------------------------------------------------------------
