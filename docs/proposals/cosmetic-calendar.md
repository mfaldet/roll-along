# Cosmetic calendar on fixed dates (proposal, not built)

> **Superseded (November 20, 2026).** This is the original proposal. The calendar that ships is much smaller: every release is one or two full collections, and the owner set the dates to **Dec 17, 2026** (Candyland and Nightclub), **Jan 14, 2027** (Golf and Bloom) and **Feb 11, 2027** (Ocean). See `docs/proposals/collection-gaps.md` ("Release dates moved") and database step 21 (`docs/cosmetics/cosmetic-calendar-full-collections.sql`). The tables below are kept as history.


Status: **approved and built** (November 18, 2026). Decisions: dates and groups as below; seasonal changes as below with "Year of the Dragon" renamed "Lunar New Year"; releases at midnight Eastern (America/New_York); a collection already released on a phone stays released if its date is later moved back. Built in `CosmeticSchedule` / `CosmeticCalendarStore` (`RollAlong/Cosmetics.swift`) and database step 11 (`docs/cosmetics/cosmetic-calendar.sql`). Section (a) below describes the old schedule. Note: Marble Baron (section d) is not in the shipped trophy catalog; no trophy depends on the calendar.

## (a) How the schedule works today

All of it lives in `CosmeticSchedule` in `RollAlong/Cosmetics.swift`.

- **One launch date:** `launchDate = December 15, 2026`, at the start of the day on the player's phone.
- **Drops:** 12 drops of permanent collections. Drop *n* unlocks on launch + *n* × 28 days, so Jan 12, 2027 through Nov 16, 2027.
- **Launch collections:** 13 are available on day one (`launchBundleIDs`):
  - The Starter Pack and the gift pool: Aurora, Nature, Citrus, Sketchbook, Midas.
  - The Challenge Track rewards: Winter, Cosmos, Lava Flow, Neon, Haunted, Ancient Temple, Abyssal Depths, Champion.
- **Later collections:** the 37 other permanent collections arrive in the 12 drops.
- **Single items** follow the earliest permanent collection that contains them. Items in no collection are spread by a hash of their name across launch and drops 3, 6 and 9.
- **Packs** (Planets, Sports, Vintage Glass) appear once every ball in them is released.
- **Seasonal collections:** there are 16. They ignore the launch date. Each has a fixed yearly window (`availableFrom` / `availableUntil`, repeated every year by `CosmeticBundle.currentWindow`).
- **"Coming soon"** in Shop › Catalog shows the next drop's collections and its date (`CosmeticSchedule.nextDrop()`).
- **Clock:** everything uses the phone's own clock and time zone, like the hourly shop rotation.

## (b) Proposed calendar, December 2026 to November 2027

Rules I followed:
- Launch collections are available from the first time the app is opened, with no launch date.
- Each later drop is on a fixed date. I picked Thursdays about four weeks apart, so the cadence stays roughly what it is today.
- Holiday-themed drops come one to three weeks *before* their holiday.
- Dates start at the beginning of the day on the player's phone, as today.

| # | Date | Collections | Why this date |
|---|---|---|---|
| 1 | Thu **Dec 17, 2026** | Cathedral, Velvet Night, Crystal Cavern | Ahead of Christmas: stained glass, a deep night and an icy cave. New phones are opened on Dec 25. |
| 2 | Thu **Jan 14, 2027** | Zen Garden, Clockwork, Noir | A calm new year, and "time" for the new year. |
| 3 | Thu **Feb 11, 2027** | Candyland, Nightclub, Heavens | Valentine's week (Feb 14). |
| 4 | Thu **Mar 11, 2027** | Full Court, Planets, Space Travel | Ahead of March Madness (about Mar 16). Planets stays early so the 40-ball trophy is not delayed (see d). |
| 5 | Thu **Apr 1, 2027** | Diamond (baseball), Golf, Bloom, Pastel | Baseball Opening Day (late March), the Masters (Apr 8–11), and spring. |
| 6 | Thu **May 6, 2027** | Arcade, Lava Lamp, Plasma Globe, Tempest | Retro "fun" drop, and spring storms. |
| 7 | Thu **Jun 3, 2027** | Ocean, Aquarium, Soccer | Start of summer. The Women's World Cup starts about Jun 24. |
| 8 | Thu **Jul 1, 2027** | Golden Hour, Dune, Paper World | High summer: sun, sand, and a summer-break craft theme. |
| 9 | Thu **Jul 29, 2027** | Eclipse, Magma Core | Ahead of the total solar eclipse on Aug 2, 2027. |
| 10 | Thu **Sep 2, 2027** | Billiards Hall, Geode, Realistic Marble | Back to school and fall: game room and stones. |
| 11 | Thu **Oct 7, 2027** | Hellfire, Midnight Carnival, Oracle | Spooky season, ahead of Halloween. |
| 12 | Thu **Nov 11, 2027** | High Roller, Neon City, Quicksilver | Ahead of Black Friday (Nov 26) and the holidays. |

That is 37 collections, each scheduled once.

**Collections with no real theme date:**
- Arcade, Lava Lamp, Plasma Globe, Quicksilver, Neon City and High Roller have no holiday. I grouped them by mood.
- Paper World only loosely fits summer. It can move to any date.

**Note on drop 1:** if Apple approves after Dec 17, drop 1 is simply open on the first launch, alongside the launch collections. Nothing breaks.

**Items in no collection:** they still follow drops 3, 6 and 9, which become Feb 11, May 6 and Jul 29.

**After November 2027:** nothing more is scheduled. You add new rows to the table for later drops.

## (c) Seasonal collections: today's yearly windows and proposed windows

Seasonal collections keep their yearly windows. With the new table, a window can also be set **per year** for holidays that move: Lunar New Year, Mardi Gras and Oktoberfest. Today they repeat on the same days every year, which drifts off the holiday.

| Seasonal collection | Window today (each year) | Proposed window | Change |
|---|---|---|---|
| Winter Wonderland | Dec 1 – Jan 6 | Dec 1 – Jan 6 | keep (Christmas in early December) |
| Countdown (New Year) | Dec 28 – Jan 5 | **Dec 26** – Jan 5 | opens right after Christmas |
| Year of the Dragon | Jan 29 – Feb 19 | 2027: **Jan 27 – Feb 20** (Lunar New Year is Feb 6) | per-year row. **2027 is the Year of the Goat, not the Dragon.** Rename it "Lunar New Year" or fix the name each year. |
| Mardi Gras | Feb 5 – Feb 17 | 2027: **Jan 28 – Feb 10** (Mardi Gras is Feb 9) | per-year row (2028: Feb 29) |
| Sweetheart (Valentine's) | Feb 1 – Feb 15 | Feb 1 – Feb 15 | keep |
| Luck of the Roll (St. Patrick's) | Mar 1 – Mar 18 | Mar 1 – Mar 18 | keep |
| Spring Fling | Mar 20 – May 1 | Mar 20 – May 1 | keep (Easter 2027 is Mar 28, inside the window) |
| Earth Day | Apr 18 – Apr 26 | **Apr 12** – Apr 26 | opens about 10 days ahead of Apr 22 |
| Spectrum (Pride) | Jun 1 – Jun 30 | Jun 1 – Jun 30 | keep |
| Summer Vibes | Jun 1 – Sep 1 | Jun 1 – Sep 1 | keep |
| Star-Spangled (July 4) | Jun 28 – Jul 6 | **Jun 21** – Jul 6 | two weeks ahead |
| Back to School | Aug 15 – Sep 8 | **Aug 1** – Sep 8 | many US schools start in early August |
| Oktoberfest | Sep 19 – Oct 5 | 2027: **Sep 16 – Oct 4** (festival Sep 18 – Oct 3) | per-year row |
| Trick or Roll (Halloween) | Oct 1 – Nov 1 | Oct 1 – Nov 1 | keep |
| Día de los Muertos | Oct 28 – Nov 3 | **Oct 21** – Nov 3 | opens about 10 days ahead |
| Harvest Moon | Nov 1 – Nov 30 | Nov 1 – Nov 30 | keep (Thanksgiving is Nov 25, 2027) |

In the calendar months, seasonal and permanent releases fit together like this:
- **December:** Winter Wonderland (Dec 1) → drop 1 (Dec 17) → Countdown (Dec 26).
- **February:** Sweetheart and Mardi Gras → drop 3 (Feb 11).
- **October:** Trick or Roll (Oct 1) → drop 11 (Oct 7) → Día de los Muertos (Oct 21).

## (d) What depends on the launch date today, and what changes

| Depends on `launchDate` today | After the change |
|---|---|
| `CosmeticSchedule.launchDate`, `dropIntervalDays`, `releaseDate(forDrop:)` | Removed. Each drop has its own date, read from the table or from the built-in copy. |
| `isReleased(drop:)` and `nextDrop()`, used by the Catalog, the Shop rotation pools, the pack listing and "Coming soon" | They read the drop dates instead. "Coming soon" shows the next real date from the table. |
| `CosmeticsTests` (release calendar section): asserts on `launchDate` and the 28-day spacing | Rewritten. Every permanent collection is scheduled exactly once, gift and reward collections are at launch, built-in dates are in order, and a table date overrides a built-in one. |
| Review notes ("13 at launch, then a new group every 4 weeks. … Nothing is switched on remotely.") | Must change. Dates now come from a server table the app reads, so the line about nothing being switched on remotely is no longer true. New text: the release dates are listed in the app and can be adjusted from the server; no hidden features. |
| Code comments in `Cosmetics.swift` and `docs/trophies/trophy-revision-proposal.md` ("40 ball skins reachable from March 9, 2027") | Text updates only. |

**What does not depend on the launch date** (checked with grep):
- Trophies, Platinum, analytics, seasons, streaks, the daily reward and lives never read `launchDate`.
- The only trophy link is indirect. Platinum requires **Marble Baron (own 40 ball skins)**, and how soon 40 balls can be bought depends on the drop dates.
- I counted coin-buyable balls by drop (seasonal and IAP-only balls left out):

| | Launch | Drop 1 | Drop 2 | Drop 3 | Drop 4 | Drop 5 | Drop 6 |
|---|---|---|---|---|---|---|---|
| Today | 15 | 19 | 22 | 37 | **40 (Apr 6)** | 43 | 47 |
| Proposed | 15 | 18 | 21 | 27 | 38 | **42 (Apr 1)** | 47 |

- So the earliest possible Platinum stays in early April 2027 (Apr 1 instead of Apr 6).
- That is why Planets stays early, in March. Moving it to July, where its space theme would fit Moon Landing Day, would delay Platinum to July.
- Seasonal balls can make 40 reachable sooner in both versions.

## (e) Build plan (only after you approve)

**Database: new step 11, `docs/cosmetics/cosmetic-calendar.sql`, not applied.** It follows step 10, the trophy fix.

- **Table** `public.cosmetic_calendar`:
  - `collection_id text`, `starts_on date`, `ends_on date null` (null means permanent), `note text`, `updated_at timestamptz`.
  - Key: `(collection_id, starts_on)`.
- **Row types:**
  - A permanent collection has one row with `ends_on` null.
  - A seasonal collection has one row **per year**, with `starts_on` and `ends_on`.
  - Items in no collection use three named rows: `_loose-1`, `_loose-2`, `_loose-3`.
- **Access:**
  - Anyone, signed in or not, can read it. It holds only dates and collection ids.
  - Nobody can write to it from the app. You edit it in the Supabase dashboard.
- **Seeding:** the step fills the table with the dates above and ends with a check query.

**App changes:**
- `CosmeticSchedule` keeps a built-in copy of every date above as the fallback. Launch collections have no row and are always available.
- **Reading the table:** once at launch and again on return to the app, at most every 6 hours. It is a single read-only GET with the public key, and it is skipped during tests (the item 2 switch).
- **Caching:** the result is saved on the phone, so an offline launch uses the last dates it saw, or the built-in copy if it has never connected.
- **Bad rows:** rows with unknown ids or broken dates are ignored. A collection with no row uses its built-in date.
- **Seasonal fallback:** a seasonal collection with no row for the current year falls back to its built-in yearly window.

**When you change a date, a player who already has the app:**
- **Moving a date earlier:** the collection appears on the next launch or return to the app, once the new table is read, within about 6 hours.
- **Moving a date later, for a collection that has not released yet:** "Coming soon" shows the new date after the next read.
- **Moving a date later, for a collection the player's phone has already seen released:**
  - Recommendation: **it stays released on that phone.** The app remembers each collection it has seen released, so it is never taken away.
  - Owned items are always kept in any case, as today.
  - New players would see the later date.
- **Changing a seasonal window:** it takes effect on the next read. Owned seasonal items are never removed.
- **Offline phones** keep the last dates they saw until they reconnect.
- **Phones on the current build** (TestFlight testers only) keep the old built-in schedule until they update.
- **Clock:** a player who sets their phone's clock forward can still open drops early, as today. This is the same rule as the hourly shop rotation.

**Open choices for you:**
1. Do you approve the drop dates and groups in (b), or want changes?
2. Do you approve the seasonal window changes in (c), including renaming "Year of the Dragon" to "Lunar New Year"?
3. Should releases begin at midnight on the player's phone (as today), or at midnight Eastern, to match seasons and the social clock?
4. Moving a date later: should an already-released collection stay released on that phone (my recommendation), or be hidden again?
