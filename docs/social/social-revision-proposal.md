# Social and clans: the design as built

**Status (2026-11-15): built on the branch for version 1.0. Nothing has been
applied to the database.** The app side is in `SocialClient.swift`,
`ClansView.swift`, `FriendsView.swift` and `HomeView.swift`; the database
side is `docs/social-schema-v5.sql` and `docs/social-schedule.sql`.

This file began as a proposal. Sections a to c below keep its reasoning; the
rest describes what was decided and built. An earlier weekly event ("Battle
Week") was replaced by the monthly clan battle and is no longer part of the
design.

**Decisions**

- A player's Adventure level is their public standing: a badge next to their
  name everywhere.
- Friends and clan lists show levels gained this week.
- A clan holds up to **12** members.
- Clans compete in a **monthly clan battle** with coin prizes. It ships in
  version 1.0.
- Clan life requests have limits (below). Giving never costs the giver.
- Promote and remove-member controls are **not built**; see the end.

---

## What exists today

| | Today |
|---|---|
| **Friends list** | Name and Adventure level per friend, plus "Send life". No stars, no activity. Unsorted. No way to remove a friend. |
| **Public profile** | Name, level, lives, a stat grid (level, stars, coins), trophy showcase, leaderboard ranks. Does not show the player's clan. |
| **Clans page** | Two tabs: My Clan and Browse. My Clan shows tag, name, description; member count; a combined-levels total added up on the phone; "Ask for a life"; an invite link; the member list; the fixed-phrase chat. |
| **Clan member list** | Name, level, "needs a life" marker, "Send life". Sorted owner first, then by level. Other members' roles are not shown. |
| **Browse clans** | Tag, name, description. No member count, no totals, no ranking. Newest first. |
| **Joining** | Open and instant. One clan per player. |
| **Roles** | Owner, officer, member exist in the database. There is no way to promote, demote or remove anyone. |
| **Member cap** | None, in the app or the database. |
| **Leaderboards** | Adventure (by level, then stars), Zen Garden, Roll Up, and the six competitive games (with Easy/Normal/Hard views). Global top 100 only. No friends or clan view. Your own rank is found by fetching the top 500. |
| **Clan ranking** | None. |
| **What the server stores** | Per player: name, level, stars, coins collected, lives, minigame bests and wins, and a "needs a life" time. Clans, memberships (with join date), friendships, life gifts, clan chat events. **No history**: only current values. |
| **When progress is sent** | Only when the player advances a level in Adventure, and only while signed in. Stars gained by replaying a level are not sent until the next advance. A failed send is not retried. |
| **Trust** | A signed-in player's own row accepts any level and star count the app sends. |
| **Wallet** | Coins, tickets and cosmetics live only on the phone. The server holds no balance. |
| **Notifications** | Local only. No push. |

Two things in that table shape everything below: the server keeps no history,
and it believes whatever the app says.

---

## a) Adventure level as identity

**A level badge.** One small shared component, used everywhere a player's
name appears: a rounded capsule reading "Lv 142", tinted with the color of
the world that level is in (the Level Select banner already uses world
colors). Milestone levels (100, 500, 1,000, 2,500, 5,000) get a thin gold
outline. It reads the same at every size and needs no new art.

**Where it goes**

| Place | Today | Change |
|---|---|---|
| Friends list, search, requests | Level shown, own styling | Use the badge |
| Clan member lists | Level shown, own styling | Use the badge |
| Adventure leaderboard | "LVL" column | Use the badge |
| Public profile | "Level N" pill | Use the badge |
| Other leaderboards (minigames, per-difficulty) | No level | Add the badge after the name |
| Clan chat bubbles and system lines | No level | Add the badge after the name |
| Gift inbox ("X sent you a life") | No level | Add the badge |
| Own profile header | No level | Add the badge |
| Home greeting | No level | Leave as is; the Play button already shows the level |
| In-game name tags | No level | Leave as is; no room |

**One definition to settle.** The public "level" today is the level the
player is *on* (highest cleared plus one). The share card uses a different
number. Pick one and use it everywhere; I suggest the level they are on,
since that is what the leaderboard already ranks by.

**Size:** about 150 lines, app only. No database change.

---

## b) Seeing others' pace

Show "+12 this week" next to each player in the friends list and the clan
member list.

**How it is stored.** Three new columns on each player's row:

| Column | Holds |
|---|---|
| `week_start` | The Monday (UTC) of the week the baseline belongs to |
| `week_start_level` | The player's level when that week began |
| `week_start_stars` | The player's stars when that week began |

**How it is kept current.** A small database trigger. Whenever a player's
row is updated, the trigger checks whether a new week has started since
`week_start`; if so it copies the *old* level and stars into the baseline
columns and moves `week_start` forward. No scheduled job is needed.

**How the app shows it.** "This week" is the current level minus
`week_start_level`. If `week_start` is from an earlier week, the player has
not played this week and the app shows "+0".

**Also needed.** The friends list should sort by this week's progress by
default, with level as the alternative, so the most active friends rise to
the top.

**Size:** about 40 lines of SQL and 120 lines of app code.

---

## c) Clan rankings

### The ranking

A new "Rankings" section on the clans page listing all clans, sortable by
this season's score (the default), total levels passed and total stars.

Each row: rank, tag and name, member count out of the cap, the total being
sorted by, wins and last month's finish. Your own clan's row is highlighted.

**How it is computed.** A database view that adds up each clan's members'
levels and stars. At launch scale (hundreds of clans) the view can be
computed on each request. If clans reach the thousands it becomes a table
refreshed every few minutes by a scheduled job; the app does not change.

### Opening a clan

A compact header: name, tag, "7 of 12 members", total levels, total stars,
this season's score, wins, and last month's finish.

Then the ranked member list. Each row: rank, name, role, level badge, stars,
this week's contribution. Sorted by this week's contribution, with level as
the alternative.

### Member cap: 12

There was none. It is now **12**, enforced in the database so a modified app
cannot exceed it (`clan_member_cap` in `docs/social-schema-v5.sql`; the app
shows the same number from `Clan.memberCap`).

- Large enough for a friend group or a family.
- Small enough that a ranking by totals is a fair fight. Without a cap the
  biggest clan always wins and everyone joins it.
- Season scores are totals, so the cap is what keeps them comparable.

### Roles

Showing roles in the list makes them matter, so the missing controls should
come with it: the owner can promote a member to officer, demote, and remove
a member; a leaving owner hands the clan to an officer. The database today
does not allow a role to be changed at all, so this needs a small rule
change as well as the screens. This could be deferred, but a ranked member
list with no way to remove an inactive member will be the first complaint.

**Size:** about 80 lines of SQL and 400 lines of app code, plus about 150
more for the role controls.

---


## d) The monthly clan battle

A **season** is a calendar month, measured in UTC so it starts and ends at
the same moment for everyone.

**Season score.** A clan's score is the new Adventure stars its members
earned that month. The server counts them, not the app: a trigger on the
player row sees every increase in a player's star total and adds it to a
record for that player **and the clan they are in at that moment**. A star
stays with the clan it was earned for; leaving does not move it.

- Only stars above the player's highest-ever total count, so resetting
  progress and re-earning stars scores nothing.
- At most 150 new stars per player per day count (50 levels at three stars).
- The app sends the star total whenever it rises, not only on a new level.

**Where it shows**

- Clans → Rankings sorts by this season's score by default and shows "December
  season · 16 days left". Total levels and total stars are the other sorts.
- Each rankings row and the clan header show the clan's wins and where it
  finished last month.
- The clan page shows the clan's season score and each member's stars this
  season.

**Month end.** A scheduled database job runs every day at 00:10 UTC and
closes any finished month that has not been closed. On the 1st that is the
month that just ended; a missed run is caught up the next day.

1. Clans with at least 25 season stars are ranked by score. Ties go to the
   older clan.
2. Tiers, by percentile of the ranked clans:

   | Tier | Clans | Coins per eligible member |
   |---|---|---|
   | Diamond | Top 5% | 3,000 |
   | Gold | Next 15% (to the top 20%) | 1,500 |
   | Silver | Next 30% (to the top 50%) | 750 |
   | Bronze | The rest of the ranked clans | 250 |

   With fewer than 20 ranked clans, tiers go by rank: 1st Diamond, 2nd and
   3rd Gold, 4th to 8th Silver, 9th and below Bronze. Diamond also needs a
   score of at least 150; below that the clan gets Gold.
3. **Eligible** means a member of the clan when the job runs who earned at
   least 10 season stars for that clan. This stops hopping into the winning
   clan on the last day.
4. **A win** is finishing first. The clan's win count goes up by one.
5. Every ranked clan records its finish, shown as "Last month: 3rd of 40 ·
   Gold" for the following month.

**Prizes are coins only**: no skin, no tickets. For scale: an active player
earns roughly 600 to 1,000 coins a day; the $0.99 pack is 750 coins and the
$4.99 pack is 4,500. Diamond is worth about four days of play, or a little
under $4 at pack prices, once a month.

**Claiming.** The job writes one prize record per eligible player. The next
time the player opens the Clans screen, a card shows the month, the clan's
finish, the tier and a Claim button. The server marks the prize claimed
first and the app then adds the coins. Unclaimed prizes are kept until
claimed, with no expiry; they are removed only when the account is deleted.
The coin balance lives on the device, so the server can only ensure each
prize is claimed once.

**The first season.** December 2026 is a partial month (launch is December
15). It runs as a rehearsal: clans are ranked and the finish is shown, with
no coins and no win counted. The first prize season is January 2027. This is
one setting (`season_prizes_from`).

## e) Clan life requests and gifts

| Rule | Value | Setting |
|---|---|---|
| Lives one request collects, one per clanmate | 6 | `life_request_size` |
| An unfilled request closes after | 24 hours | `life_request_hours` |
| Wait after a request closes (filled, expired or cancelled) | 6 hours | `life_request_cooldown_hours` |
| "Send life" outside a request, per player per day | 1 | `gift_per_friend_per_day` |
| Clan member cap | 12 | `clan_member_cap` |

- Giving never costs the giver a life.
- A player can give to any one request only once.
- The ask button shows the remaining wait.
- A red count on Home's Clans button, on the Roster header and on each
  request row shows open requests this player has not given to.

All of these are rows in the `ra_config` table and take effect when changed
in the dashboard; the app reads them when the Clans screen opens. None needs
an app update.

## What runs on the server

| Piece | When | How |
|---|---|---|
| Weekly baseline, daily star cap, season-star counting, request rules | On each player update | Trigger |
| Member cap | On each join | Trigger |
| One gift per request; request fills; one gift per friend per day | On each gift | Trigger |
| Close finished months, rank clans, write prizes | Daily at 00:10 UTC | Scheduled job (`pg_cron`) |
| Close life requests older than 24 hours | Every 15 minutes | Scheduled job (`pg_cron`) |

Set up once: run `docs/social-schema-v5.sql`, then `docs/social-schedule.sql`.
Nothing needs doing each month. If the Supabase project is paused the jobs
do not run; the month-end job catches up the day after the project wakes.

## How scores could be faked, and the guards in place

A signed-in player can write their own row with the public key. The guards:

1. **Impossible-value rule.** Stars can never exceed three per level
   unlocked; the write is refused.
2. **Daily cap** on the stars that count toward a season (150).
3. **Only stars above the player's highest-ever total count.**
4. **Server-owned columns.** The app cannot write the weekly baseline, the
   season records, a clan's wins or finish, or the exclusion switch.
5. **Exclusion switch.** `excluded` on a player or a clan, set in the
   dashboard, removes them from leaderboards, rankings, season scores and
   prizes.
6. **Modest prizes.** Coins that only buy cosmetics, at most about four days
   of play per month.

This stops casual tampering and makes the rest visible. It does not stop a
determined cheater, who can still send plausible-looking progress.

## Privacy

Other players can see a player's level, stars, levels gained this week and
stars earned for their clan this season, and that they have asked for a
life. The privacy page says so. The App Privacy answers and the privacy
file in the project are unchanged: this is gameplay content linked to the
account, already declared.

## Not built: promote and remove-member controls

Today a clan has an owner and members, and roles cannot change. With a cap
of 12, an owner needs to remove inactive members. The database already
allows an owner to remove a member; the app has no button for it. Promotion
needs a small database rule as well. This is waiting on a decision.
