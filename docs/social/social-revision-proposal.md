# Social and clans revision proposal

**Status: proposal only. Nothing built, nothing applied to the database.**
Written 2026-11-15.

**Goal:** a player's Adventure level becomes their public standing, other
players' progress is easy to see, and clans compete.

**In short:** parts (a) and (b) and a read-only version of (c) are small and
could ship with version 1.0. Battle Week (d) needs server jobs, a prize
claim, and a guard against faked scores; it should be the first update. A
January 1 start is possible but tight.

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
total levels passed and total stars. During Battle Week it sorts by battle
stars automatically and says so in the header.

Each row: rank, tag and name, member count out of the cap, the total being
sorted by. Your own clan is pinned at the bottom of the screen with its rank
when it is not in view.

**How it is computed.** A database view that adds up each clan's members'
levels and stars. At launch scale (hundreds of clans) the view can be
computed on each request. If clans reach the thousands it becomes a table
refreshed every few minutes by a scheduled job; the app does not change.

### Opening a clan

A compact header: name, tag, "23 / 30 members", total levels, total stars,
this week's levels (battle stars during Battle Week).

Then the ranked member list. Each row: rank, name, role, level badge, stars,
this week's contribution. Sorted by this week's contribution, with level as
the alternative.

### Member cap: 30

There is none today. I propose **30**, enforced in the database so a
modified app cannot exceed it.

- Large enough for a friend group or a family and their friends.
- Small enough that a ranking by totals is a fair fight. Without a cap the
  biggest clan always wins and everyone joins it.
- Battle Week scores are totals, so the cap is what keeps them comparable.

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

## d) Battle Week

Days 1 to 7 of every month. A clan's score is its **battle stars**: the new
Adventure stars its members earned in that week. First one: January 1 to 7,
2027.

**The week is measured in UTC**, so it starts and ends at the same moment
for everyone. The app shows the countdown in the player's local time.

### How battle stars are counted

The server counts them, not the app. A trigger on the player row sees every
increase in a player's star total. During Battle Week it adds the increase
to a contribution record for that player **and the clan they are in at that
moment**.

This requires one app change: send progress whenever stars increase, not
only on a level advance. Otherwise stars earned by replaying levels would
not count until the player's next new level.

### Joining or leaving mid-week

- **Stars stay with the clan they were earned for.** Leaving does not take
  them away from the old clan, and does not bring them to the new one.
- **A player who joins mid-week** contributes to the new clan from that
  moment.
- **A prize needs two things:** being a member when the week ends, and
  having contributed at least 10 battle stars to that clan. This stops
  players hopping into the winning clan on day 7.
- **The member cap still applies**, so a full clan cannot be stacked.

### Tiers and prizes

Clans that scored at least 25 battle stars are ranked. Tiers are by
percentile of those clans:

| Tier | Clans | Prize per eligible member |
|---|---|---|
| Diamond | Top 5% | 3,000 coins and 5 tickets |
| Gold | Next 15% (to the top 20%) | 1,500 coins and 3 tickets |
| Silver | Next 30% (to the top 50%) | 750 coins and 1 ticket |
| Bronze | Everyone else who qualified | 250 coins |

How those sit in the existing economy:

- An active player earns roughly 600 to 1,000 coins a day from play.
- A Standard cosmetic costs 750; a Legendary 1,500; collections run from
  4,500 to 13,500.
- A perfect week of daily rewards pays 105.

So Bronze is a small thank-you, Silver is one Standard cosmetic, Gold is one
Legendary, and Diamond is two Legendary items or most of a small collection:
worth chasing once a month, not enough to replace playing or buying.

A note on an earlier decision: the repo records that *trophies* never grant
coins. Battle prizes would be the first coins granted for a social result.
That is a choice to make knowingly. A coin-free alternative is an exclusive
cosmetic per tier, which costs art.

### When there are only a handful of clans

Percentiles do not work with eight clans. Rule: **with fewer than 20
qualifying clans, tiers are by rank.**

| Rank | Tier |
|---|---|
| 1st | Diamond |
| 2nd and 3rd | Gold |
| 4th to 8th | Silver |
| 9th and below | Bronze |

Two guards keep this honest when there are very few clans:

- The 25-star minimum still applies, so an idle clan gets nothing.
- Diamond also requires at least 150 battle stars. A lone clan that barely
  played gets Gold at most.

### How a member sees their own contribution

On the clan page during Battle Week: "Your battle stars: 37, 3rd in the
clan", above the member list, with the clan's current rank and the gap to
the clan above. The member list shows each member's battle stars.

### How the result is announced and the prize claimed

There is no push, so:

- **In the app.** The first time the app opens after the week ends, a result
  sheet shows the clan's rank, its tier and the player's prize, with a Claim
  button.
- **A local notification.** For players who turn it on, the phone schedules
  "Battle Week results are in" for the morning of the 8th. This is the same
  kind of opt-in local notification the app already has.
- **Claiming.** The closing job writes one prize record per eligible player.
  Claiming marks the record as claimed on the server, then adds the coins and
  tickets on the phone. This is the same pattern as claiming a life gift.
  Because the wallet lives on the phone, the server cannot enforce the
  balance; it can only ensure each prize is claimed once.
- **Unclaimed prizes** stay available until the next Battle Week ends.

### Outside Battle Week

The clans page shows a countdown to the next one, last month's top three
clans, and your own clan's rank and tier from last month. The ranking falls
back to total levels and total stars.

**Size:** about 250 lines of SQL and 700 lines of app code.

---

## What must run on the server

| Job | When | How |
|---|---|---|
| Weekly baseline (part b) | On each player update | Trigger. No schedule. |
| Clan totals (part c) | On request | View. No schedule at launch scale. |
| Member cap (part c) | On each join | Trigger. |
| Battle star counting (part d) | On each player update during the week | Trigger. |
| Closing a Battle Week: rank clans, assign tiers, write prize records | 8th of each month, shortly after 00:00 UTC | Scheduled database function. |

**The schedule.** Supabase can run a database function on a timer with its
`pg_cron` extension. The trophy rarity job already in this repo
(`docs/trophies/trophy-rollup.sql`) was designed the same way and has not
been deployed yet, so this would be the same setup done once for both.

**What you would set up yourself**

1. Turn on the `pg_cron` extension in the Supabase dashboard.
2. Run the SQL file for each part in the SQL editor, in order.
3. Run one line that schedules the closing job, and check it is listed.
4. After the first Battle Week, check the result and prize tables look right
   before the next one.

I would write the SQL files and a one-step-at-a-time guide. I cannot apply
them or see the result, so the first real run of the closing job is the
riskiest moment in this whole proposal. A dry-run mode, which computes the
result without writing prizes, should be part of it.

---

## How scores could be faked, and the smallest reasonable guard

**How.** A tampered app can sign in normally and tell the server its player
has any level and any number of stars. Today nothing checks. Once stars
decide prizes, someone will try.

**Guards, in order of value for effort**

1. **An impossible-value rule.** Stars can never exceed three per level
   passed. One line in the database; blocks the crudest fakes.
2. **A rate limit on battle stars.** The trigger counts at most a set number
   of new stars per player per day toward the battle (I suggest 150, which is
   50 levels at three stars, more than a long day of real play). Anything
   above still shows on the profile but does not score.
3. **A limit on level jumps.** A level can rise by at most a set amount per
   update.
4. **An exclusion switch.** A flag on a player and on a clan that removes
   them from rankings and prizes, set by you in the dashboard after looking
   at an outlier report the closing job produces.
5. **Keep prizes modest.** Coins that only buy cosmetics, in amounts a player
   could earn in a few days, give little reason to cheat.

That is the smallest reasonable set: about 60 lines of SQL. It stops casual
tampering and makes the rest visible. It does not stop a determined cheater
who fakes plausible play; only checking every run on the server would, and
that is a different project.

---

## Privacy page, App Privacy answers, review notes

- **Privacy page.** One sentence to add: other players can see your weekly
  progress and your clan's results. The page already says level and progress
  are shown to other players.
- **App Privacy answers.** No change. Weekly progress and battle stars are
  "Gameplay Content, linked to the user, App Functionality", which is already
  declared.
- **Privacy file in the project.** No change, same reason.
- **Review notes.** Add a short Battle Week paragraph: a monthly in-game clan
  event, prizes are in-game coins and tickets with no cash value, nothing is
  bought to enter.
- **Age rating questionnaire.** "Contests" would be answered yes. Apple's
  definitions put infrequent contests at 4+ and frequent ones at 13+; the app
  is already aiming for 13+, so either answer is covered.
- **Names.** Nothing here adds typed text. Everything shown is a preset name
  and numbers.

---

## Optional idea: house clans

Openly labeled clans run by the game, so the rankings are not empty in the
first weeks.

**What I think.** It is acceptable if done strictly, and I would still
rather not.

If it is done, the rules that keep it honest:

- A distinct badge and the words "House clan, run by Roll Along" wherever it
  appears. No member list of invented players.
- House clans **never take a prize tier**. Tiers are computed from real
  clans only; house clans are shown as pace markers in the list.
- Their scores follow a published, fixed pace (for example "a steady 40
  stars a day"), not a number tuned to stay just ahead of players.
- They cannot be joined.
- They disappear automatically once there are 20 real clans.

**Why I would rather not.** Even labeled, a ranking half-filled by the house
reads as padding, and it adds a moving part to the closing job on its first
runs. The handful-of-clans rule above already makes a small ranking work,
and an honest "8 clans competing" is fine for a first month among family
and friends. If the ranking feels empty after the first Battle Week, house
clans can be added then without changing anything else.

---

## Size of the work, and what fits before December 15

| Part | App code | SQL | Needs a server job | Risk |
|---|---|---|---|---|
| a) Level badge everywhere | ~150 lines | none | no | Low |
| b) Weekly pace | ~120 lines | ~40 lines | no (trigger) | Low |
| c) Clan rankings, clan header, ranked members, cap of 30 | ~400 lines | ~80 lines | no (view) | Medium |
| c) Role controls | ~150 lines | ~30 lines | no | Medium |
| Anti-faking guards | none | ~60 lines | no | Low |
| d) Battle Week | ~700 lines | ~250 lines | yes | High |

None of it can be compiled or run against the database here, so each part
needs a build and a test pass on your side.

### Before the December 15 launch

- **a) Level badge.** App only.
- **b) Weekly pace.**
- **c) Rankings by total levels and stars**, the clan header, the ranked
  member list and the cap of 30.
- **The first two anti-faking guards**, since rankings make faked numbers
  visible to everyone.
- **Sending progress when stars change**, which (d) needs later and which
  fixes stale star counts today.

That is roughly 700 lines of app code and 180 of SQL. It is achievable, but
it is added to a launch build that already has a long list of untested
changes waiting for you. Role controls can wait.

### First update

- **d) Battle Week**, with the remaining guards and the closing job.
- **Role controls.**

**About January 1.** For the first Battle Week to run January 1 to 7, the
update has to be approved and in players' hands before then. That means
submitting around December 20, in the days when App Review is typically at
its slowest. The safer plan is to put the **counting** on the server before
January 1 (it needs no app update beyond sending stars promptly, which is in
the launch build), so January's battle stars are recorded either way, and
let the Battle Week screens and prizes arrive with the update. If the update
slips, January still has a real result to show; if that feels too tight, the
first Battle Week moves to February 1 to 7 with nothing lost.

---

## Decisions needed

1. Member cap of 30?
2. Coins and tickets as prizes, or exclusive cosmetics, or both?
3. The tier amounts above?
4. Role controls with the launch, or in the first update?
5. House clans: no for now?
6. First Battle Week January 1 to 7, with counting on the server first and
   the screens in the update, or February 1 to 7?
