# Trophy revision proposal

> **Not adopted (2026-11-15).** This 48-trophy proposal was replaced by the
> owner's own design: 92 trophies as stacks and feats. See
> [`trophy-list.md`](trophy-list.md). Kept for the record only.

**Status: proposal only.** Nothing in the catalog, the Swift code or the tests
has been changed. Written 2026-11-15 against the 85-trophy catalog on the
`claude/upbeat-einstein-3c16ns` branch.

**In short:** cut from 85 trophies to 48, give each one its own icon,
and replace the eleven-section list with six groups of icon tiles. Platinum
would require 36 trophies instead of 70. The trophy SQL does not
depend on the list and can be applied before or after.

The icon names below are written from memory of Apple's SF Symbols catalog. I
could not open the SF Symbols app or run the app here, so **none of the symbol
names is verified**. Section 2 says how to verify all of them in one step.

---

## 1. Cut list

### Rules used

- Where a trophy has two steps of the same measure, one is kept. "Merge" means
  the smaller step folds into the larger; "cut" means the trophy goes with no
  successor.
- Where a minigame had a plain win trophy and a distinctive one, the
  distinctive one is kept.
- Every minigame keeps exactly one trophy of its own.
- The four secret trophies, the three Diamonds and Platinum are kept.
- No tier changes and no changes to what a kept trophy asks for.

### Counts

| Category | Before | After |
|---|---|---|
| Climb | 12 | 6 |
| Challenge Tracks | 6 | 4 |
| Daily | 7 | 3 |
| Minigames (all) | 7 | 3 |
| Minigames (per game) | 22 | 11 |
| Cosmetics | 9 | 5 |
| Economy | 4 | 2 |
| Social | 7 | 4 |
| Skill | 6 | 5 |
| Secret | 4 | 4 |
| Platinum | 1 | 1 |
| **Total** | **85** | **48** |

| Tier | Before | After |
|---|---|---|
| Bronze | 48 | 20 |
| Silver | 23 | 17 |
| Gold | 10 | 7 |
| Diamond | 3 | 3 |
| Platinum | 1 | 1 |
| **Total** | **85** | **48** |

Bronze falls from 56% of the list to 42%.

The result is 48, a little under the target of 50. If you want exactly
50, the two I would add back are "Opening Night" (first competitive win, an
easy early bronze) and "Hundred-Round Veteran" (100 competitive wins, a
long-haul gold).

### Platinum

Platinum requires every visible Bronze, Silver and Gold trophy outside the
Social and Secret groups. That rule stays. The list it produces shrinks from
70 to **36**, because 34 of the trophies it named are cut or merged.

What that changes for a player chasing Platinum:

- Still required: climb level 1,000, a perfect world, the seven-day daily
  streak, a Hard win in all six competitive games, the Golden Gauntlet track,
  25 levels without a fall, and 40 ball skins (reachable from March 9, 2027
  under the release calendar).
- No longer required: 10 hours in the Zen Garden, 100 competitive wins, 50
  daily challenges, 2,500 lifetime Gold Rush coins, and 50 owned cosmetics.

The Platinum trophy's own text says "All 70 visible..." and would change to
36.

### Every trophy

**Climb** (12 → 6)

| Trophy | Tier | What it asks | Decision | Why |
|---|---|---|---|---|
| Get the Ball Rolling | Bronze | Clear climb level 1. | keep | The first trophy every player earns. |
| Training Wheels Off | Bronze | Clear climb level 10. | cut | Ladder step. Level 1 and level 100 already bracket it. |
| Gathering Momentum | Bronze | Clear climb level 50. | cut | Ladder step with nothing distinctive at level 50. |
| Beyond the Meadow | Silver | Clear climb level 100 — all of World 1, Meadowgate. | keep | A real milestone: the whole first world. |
| Boulder and Bolder | Silver | Clear climb level 250. | cut | Ladder step between 100 and 1,000. |
| The Long Roll | Gold | Clear climb level 500. | cut | Ladder step between 100 and 1,000. |
| Unstoppable Force | Gold | Clear climb level 1,000. | keep | The long-haul climb goal below the summit. |
| The Summit | Diamond | Clear climb level 5,000 — the last level of World 50, The Summit. | keep | The end of the climb. Diamond. |
| Star Search | Bronze | Earn 25 climb stars. | merge into "Star-Studded" | Two steps of the same count. Keep the larger. |
| Star-Studded | Silver | Earn 150 climb stars. | keep | The one star-count trophy. |
| One Hundred Perfect Rolls | Gold | Hold 3 stars on every level of any single world. | keep | Distinctive: a whole world at three stars. |
| Magpie | Bronze | Bank 100 level pickup coins. | cut | A plain count; Spotless already rewards collecting pickup coins. |

**Challenge Tracks** (6 → 4)

| Trophy | Tier | What it asks | Decision | Why |
|---|---|---|---|---|
| Sidetracked | Bronze | Clear level 1 of any Challenge Track. | cut | One level is not an achievement; the halfway trophy is the entry point. |
| Deep in the Pack | Bronze | Reach level 50 in any single Challenge Track. | keep | Early goal for players trying a track. |
| Track Record | Silver | Complete any Challenge Track. | keep | Finishing a 100-level track. |
| Triple Crown | Silver | Complete 3 Challenge Tracks. | cut | Ladder step between one track and all eight. |
| Run the Gauntlet | Gold | Complete the Golden Gauntlet track. | keep | The hardest track; distinctive. |
| Full Circuit | Diamond | Complete all 8 Challenge Tracks. | keep | All eight tracks. Diamond. |

**Daily** (7 → 3)

| Trophy | Tier | What it asks | Decision | Why |
|---|---|---|---|---|
| Glutton for Punishment | Bronze | Start your first Challenge of the Day. | cut | Rewards only pressing Start; the first clear covers it. |
| Carpe Rollem | Bronze | Complete your first Challenge of the Day. | keep | Entry point for the daily challenge. |
| Seven-Day Roller | Bronze | Reach a 7-day daily reward streak. | merge into "Month of Marbles" | Two steps of the same streak. Keep the larger. |
| Ten Brutal Mornings | Silver | Complete 10 Challenges of the Day. | cut | Ladder step; the seven-day streak is the distinctive daily goal. |
| Month of Marbles | Silver | Reach a 30-day daily reward streak. | keep | The one login-streak trophy. |
| Fifty Days of Grit | Gold | Complete 50 Challenges of the Day. | cut | A plain count; 50 days is grind without a new skill. |
| The Brutal Week | Gold | Complete the Challenge of the Day on 7 consecutive days. | keep | Distinctive: seven daily clears in a row. |

**Minigames (all)** (7 → 3)

| Trophy | Tier | What it asks | Decision | Why |
|---|---|---|---|---|
| Taste of the Arcade | Bronze | Play 5 different minigames. | merge into "The Grand Tour" | Two steps of the same count. Keep "play them all". |
| The Grand Tour | Bronze | Play all 11 minigames at least once. | keep | Gets players to try every minigame. |
| Opening Night | Bronze | Win your first competitive minigame. | cut | Covered by winning once in each competitive game. |
| Six of the Best | Silver | Win at least once in each of the 6 competitive minigames. | keep | A win in each of the six competitive games. |
| Hard Bargain | Bronze | Win any competitive minigame on Hard difficulty. | merge into "Master of All Six" | Two steps of the same count. Keep the larger. |
| Hundred-Round Veteran | Gold | Win 100 competitive minigame rounds. | cut | A plain win count; each game keeps its own. |
| Master of All Six | Gold | Win on Hard in all 6 competitive minigames. | keep | The hard-mode goal across all six. |

**Minigames (per game)** (22 → 11)

| Trophy | Tier | What it asks | Decision | Why |
|---|---|---|---|---|
| Last Comet Standing | Bronze | Win a Comet Clash round. | merge into "Ten-Tail Comet" | Win 1 and win 10; keep one. |
| Ten-Tail Comet | Bronze | Win 10 Comet Clash rounds. | keep | Comet Clash's trophy. |
| King of the Ring | Bronze | Win a Sumo Survival match. | merge into "Immovable Object" | Win 1 and win 10; keep one. |
| Immovable Object | Bronze | Win 10 Sumo Survival matches. | keep | Sumo Survival's trophy. |
| Fresh Coat | Bronze | Win a Paint Ball round. | cut | The coverage trophy is the distinctive one. |
| Wall-to-Wall | Silver | Finish a Paint Ball round with 60% floor coverage. | keep | Distinctive: 60% floor coverage. |
| Smash Hit | Bronze | Win a Smash and Grab round. | merge into "Serial Smasher" | Win 1 and win 10; keep one. |
| Serial Smasher | Bronze | Win 10 Smash and Grab rounds. | keep | Smash and Grab's trophy. |
| Top Corner | Bronze | Win a Marble Cup match. | merge into "League Regular" | Win 1 and win 10; keep one. |
| League Regular | Bronze | Win 10 Marble Cup matches. | keep | Marble Cup's trophy. |
| Hill, Claimed | Bronze | Win a King of the Hill round. | cut | The hold-time trophy is the distinctive one. |
| Squatter's Rights | Silver | Hold the hill for 45 seconds total in a single round. | keep | Distinctive: hold the hill 45 seconds. |
| Out of the Woods | Bronze | Reach the goal of your first Roll Out maze. | merge into "Ten-Maze March" | Two steps of the same measure. Keep the larger. |
| Ten-Maze March | Silver | Reach maze 10 in Roll Out. | keep | Roll Out's trophy. |
| The Only Way Is Up | Bronze | Reach 100 m height in a Roll Up run. | merge into "Head in the Clouds" | Two steps of the same measure. Keep the larger. |
| Head in the Clouds | Silver | Reach 500 m height in a Roll Up run. | keep | Roll Up's trophy ("Head in the Clouds"). |
| Crossing Guard | Bronze | Make 25 crossings in a single Disco Ball run on any difficulty. | cut | The Hard-mode trophy is the distinctive one. |
| Dancing in the Dark | Silver | Make 10 crossings in a single Disco Ball run on Hard. | keep | Distinctive: ten crossings on Hard. |
| Inner Peace | Bronze | Accumulate 1 hour of Zen Garden time. | keep | Zen Garden's trophy. One hour is reachable. |
| Garden Sage | Silver | Accumulate 10 hours of Zen Garden time. | merge into "Inner Peace" | Two steps of the same clock. Ten hours is pure waiting. |
| Pit Stop | Bronze | Play your first Coin Pit round. | cut | Rewards only starting a round. |
| Cloudburst | Silver | Catch 90 coins in a single Coin Pit round. | keep | Gold Rush's trophy: catch 90 falling coins. |

**Cosmetics** (9 → 5)

| Trophy | Tier | What it asks | Decision | Why |
|---|---|---|---|---|
| Retail Therapy | Bronze | Buy any cosmetic, bundle, or ball pack with coins. | cut | Rewards a single purchase; the full outfit is the better early goal. |
| The Full Fit | Bronze | Have a non-starter cosmetic equipped in all 7 slots at once. | keep | Distinctive: a non-starter item in all seven slots. |
| Boxed Set | Bronze | Complete any cosmetic bundle. | merge into "Curator" | Two steps of the same count. Keep the larger. |
| Bag of Marbles | Bronze | Own 10 ball skins. | merge into "Marble Baron" | Two steps of the same count. Keep the larger. |
| Curator | Bronze | Complete 5 cosmetic bundles. | keep | The one collection-count trophy. |
| Collector's Eye | Bronze | Own 50 cosmetics across all 7 slots. | cut | A third ownership count beside balls and collections. |
| Pack Animal | Silver | Own any ball pack. | keep | Ball packs are their own thing. |
| Marble Baron | Gold | Own 40 ball skins. | keep | The big ball-collection goal. |
| Every Marble Has a Home | Diamond | Own every evergreen coin-or-skill-reachable cosmetic. | keep | Everything collected. Diamond. |

**Economy** (4 → 2)

| Trophy | Tier | What it asks | Decision | Why |
|---|---|---|---|---|
| Nest Egg | Bronze | Hold 1,000 coins at once. | keep | A simple, early coin goal. |
| Punch Card | Bronze | Claim 30 daily login rewards. | cut | Overlaps the 30-day login streak. |
| Working Capital | Bronze | Earn 5,000 lifetime coins from play. | keep | Lifetime coins earned from play. |
| Pit Boss | Silver | Catch 2,500 lifetime coins in Coin Pit rounds. | cut | A second Gold Rush trophy; the catch-90 one is kept. |

**Social** (7 → 4)

| Trophy | Tier | What it asks | Decision | Why |
|---|---|---|---|---|
| Hello, Rollers | Bronze | Sign in with Apple for the first time. | cut | Joining a clan or adding a friend already implies it. |
| Rolling Together | Bronze | Have your first accepted friend. | merge into "Rolling Deep" | Two steps of the same count. Keep the larger. |
| Rolling Deep | Silver | Have 5 accepted friends. | keep | The one friends trophy. |
| Lifesaver | Bronze | Send a life to a friend. | merge into "Guardian Marble" | Two steps of the same count. Keep the larger. |
| Guardian Marble | Silver | Send 25 lives to friends and clanmates. | keep | The one life-gifting trophy. |
| Strength in Numbers | Bronze | Join or create a clan. | keep | Entry point for clans. |
| Clutch Delivery | Silver | Fulfill a clanmate's life request. | keep | Distinctive: answer a clanmate's request. |

**Skill** (6 → 5)

| Trophy | Tier | What it asks | Decision | Why |
|---|---|---|---|---|
| Peak Performance | Bronze | Earn 3 stars on any very-hard climb level above level 10. | keep | Three stars on a very hard level. |
| Gone in Ten Seconds | Bronze | Clear any climb level in 10 seconds or less. | keep | Clear a level in ten seconds. |
| Clean Sheet | Silver | Clear 10 climb levels in a row without a single fall. | merge into "Untouchable" | Two steps of the same streak. Keep the larger. |
| First Try! | Bronze | Earn 3 stars on a level on your very first attempt. | keep | Three stars on the first attempt. |
| Spotless | Silver | Earn 3 stars and bank all 3 pickup coins in one single run. | keep | Three stars and all three coins in one run. |
| Untouchable | Gold | Clear 25 climb levels in a row without a single fall. | keep | 25 levels without a fall. |

**Secret** (4 → 4)

| Trophy | Tier | What it asks | Decision | Why |
|---|---|---|---|---|
| Gravity Check | Bronze | Fall into the pit on climb level 1. | keep | Secret. |
| Night Bloom | Bronze | Tend the Zen Garden between midnight and 4 AM. | keep | Secret. |
| High Roller | Silver | Stake 5 or more tickets on a single Coin Pit round. | keep | Secret. |
| Back to Basics | Bronze | Equip the full all-starter loadout while owning 20 or more cosmetics. | keep | Secret. |

**Platinum** (1 → 1)

| Trophy | Tier | What it asks | Decision | Why |
|---|---|---|---|---|
| Platinum | Platinum | Unlock every visible Bronze, Silver, and Gold trophy. | keep | Platinum. |

### Two things noticed while reading the list

- **"Coin Pit" in trophy text.** The Gold Rush trophies say "Coin Pit" in their
  descriptions, but the game calls the mode "Gold Rush". The text should say
  Gold Rush. This applies to "Cloudburst" and the secret "High Roller".
- **Roll Out.** "Ten-Maze March" asks for maze 10 and there are five mazes on
  repeat. It is reachable (the counter keeps rising through the repeats), but
  a player will see each maze twice.

---

## 2. Icons

One SF Symbol per kept trophy, no symbol used twice (checked by script). The
tier color stays as the ring around the icon; a locked trophy shows the icon
dimmed, and a secret trophy shows a question mark until earned.

| Trophy | Icon (SF Symbol name) |
|---|---|
| Get the Ball Rolling | `flag.fill` |
| Beyond the Meadow | `figure.hiking` |
| Unstoppable Force | `bolt.fill` |
| The Summit | `mountain.2.fill` |
| Star-Studded | `star.fill` |
| One Hundred Perfect Rolls | `globe.americas.fill` |
| Deep in the Pack | `signpost.right.fill` |
| Track Record | `checkmark.seal.fill` |
| Run the Gauntlet | `bolt.shield.fill` |
| Full Circuit | `8.circle.fill` |
| Carpe Rollem | `sunrise.fill` |
| Month of Marbles | `calendar` |
| The Brutal Week | `flame.fill` |
| The Grand Tour | `map.fill` |
| Six of the Best | `gamecontroller.fill` |
| Master of All Six | `medal.fill` |
| Ten-Tail Comet | `scribble.variable` |
| Immovable Object | `figure.wrestling` |
| Wall-to-Wall | `paintbrush.fill` |
| Serial Smasher | `burst.fill` |
| League Regular | `soccerball` |
| Squatter's Rights | `crown.fill` |
| Ten-Maze March | `arrow.triangle.turn.up.right.diamond.fill` |
| Head in the Clouds | `cloud.fill` |
| Dancing in the Dark | `figure.dance` |
| Inner Peace | `leaf.fill` |
| Cloudburst | `cloud.rain.fill` |
| The Full Fit | `tshirt.fill` |
| Curator | `shippingbox.fill` |
| Pack Animal | `circle.grid.2x2.fill` |
| Marble Baron | `circle.hexagongrid.fill` |
| Every Marble Has a Home | `house.fill` |
| Nest Egg | `dollarsign.circle.fill` |
| Working Capital | `banknote.fill` |
| Rolling Deep | `person.2.fill` |
| Guardian Marble | `heart.fill` |
| Strength in Numbers | `person.3.fill` |
| Clutch Delivery | `gift.fill` |
| Peak Performance | `scope` |
| Gone in Ten Seconds | `stopwatch.fill` |
| First Try! | `1.circle.fill` |
| Spotless | `sparkles` |
| Untouchable | `hand.raised.slash.fill` |
| Gravity Check | `arrow.down.to.line` |
| Night Bloom | `moon.stars.fill` |
| High Roller | `dice.fill` |
| Back to Basics | `arrow.uturn.backward.circle.fill` |
| Platinum | `trophy.fill` |

### Weak fits

These have no symbol that says the thing directly. The first option is the one
in the table.

| Trophy | Problem | Option 1 | Option 2 |
|---|---|---|---|
| Ten-Tail Comet (Comet Clash) | No comet or light-trail symbol | `scribble.variable` (a trail) | `sparkle` |
| Immovable Object (Sumo) | No sumo ring | `figure.wrestling` | `circle.circle.fill` (a ring) |
| Serial Smasher (Smash and Grab) | "Smash" has no symbol | `burst.fill` | `hammer.fill` |
| Ten-Maze March (Roll Out) | No maze symbol | `arrow.triangle.turn.up.right.diamond.fill` (a turn sign) | `square.grid.3x3.fill` |
| Dancing in the Dark (Disco Ball) | No disco ball or lit floor | `figure.dance` | `light.max` |
| Marble Baron (40 balls) | No marble symbol | `circle.hexagongrid.fill` (many circles) | `circle.grid.3x3.fill` |
| Pack Animal (ball pack) | Close to Marble Baron | `circle.grid.2x2.fill` | `square.stack.3d.up.fill` |
| Beyond the Meadow (level 100) | Nothing says "first world" | `figure.hiking` | `leaf.circle.fill` |
| Peak Performance (very hard level) | Abstract | `scope` (precision) | `target` |

### How to verify every icon at once

Add one unit test that loads the catalog and asserts
`UIImage(systemName: icon) != nil` for every trophy, and that no two trophies
share an icon. Run on an iOS 18 simulator, it fails by name for any symbol that
does not exist. That test would be part of the build work, so a wrong name
cannot reach the app.

---

## 3. Trophy Room layout

### Today

Read from `RollAlong/TrophyRoomView.swift`:

- One long scrolling list.
- A header with the completion percentage and a count per tier.
- A caption about pinning.
- Eleven sections with sticky headers, in this order: Climb, Challenge Tracks,
  Daily Challenge & Streaks, Minigames — Arcade-Wide, Minigames — Per Game,
  Cosmetics & Collection, Economy & Shop, Social, Skill, Secret, Platinum.
- Inside a section, trophies appear in catalog order.
- Each trophy is a full-width row: a tier-colored glyph on the left (the same
  glyph for every trophy of that tier), the title, a rarity label, the
  description, a progress bar and a pin button.

With 85 rows and five glyphs, the screen is about 85 near-identical lines.

### Proposed

**Six groups instead of eleven**, so no group has fewer than four trophies:

| Group | Made from | Trophies |
|---|---|---|
| Climb | Climb + Skill | 11 |
| Challenges | Challenge Tracks + Daily | 7 |
| Minigames | Arcade-wide + per game | 14 |
| Collection | Cosmetics + Economy | 7 |
| Friends & Clans | Social | 4 |
| Secrets | Secret | 4 |

Platinum is not a group. It sits in the header as one large badge with its
progress ("12 of 36").

**A grid of tiles instead of rows.** Three tiles per row. Each tile is the
trophy's icon inside a ring in its tier color, with the title underneath in
two lines at most. The whole room fits in about five screens instead of
fifteen or more.

**Tap a tile for the detail.** A small sheet shows the description, progress,
rarity, the date earned and the pin button. That detail is what makes today's
rows tall; moving it behind a tap is what makes the grid possible.

**Sorting inside a group:** Bronze, then Silver, then Gold, then Diamond, and
catalog order within a tier. The order never changes when a trophy is earned,
so a player learns where things are. Earned tiles are full color; locked tiles
are dimmed.

**Not proposed:** filters, search, tabs or a sort menu. With 48 tiles in six
groups they are not needed.

One thing to decide: the data model keeps the eleven categories or drops to
six. Keeping eleven in the data and mapping them to six groups on screen is
the smaller change, and it leaves the anonymous trophy statistics unaffected.

---

## 4. What the change touches

| Area | What changes | Size |
|---|---|---|
| `TrophyCatalog.json` | Remove 37 trophies; add an `icon` to each of the 48; Platinum list and count to 36; "Coin Pit" wording | Small, mechanical |
| `TrophyCatalog.swift` | New `icon` field; validation that every trophy has one and none repeats | Small |
| `TrophyRoomView.swift` | Six groups, tile grid, detail sheet, Platinum in the header | **The largest piece.** Mostly a rewrite of the screen; the model underneath is reusable |
| Toasts, capstone screen, profile card, public profile | Show the trophy's own icon inside the tier ring instead of the tier glyph | Small to medium; four places |
| Trophy pinning and "chase chips" | Use the icon | Small |
| Tests | Counts (85, 84, 70, 58, tier counts, secrets); the list of trophies with trigger tests; tests that exercise a cut trophy are deleted or pointed at its successor; new icon test; Trophy Room model tests for six groups | Medium. About ten test files reference specific trophies |
| Metrics for cut trophies | Left in place. A metric nothing watches costs nothing, and removing them touches the engine | None |
| Trophy SQL (`trophy-schema.sql`, `trophy-rollup.sql`) | **Nothing.** See below | None |
| Review notes | Nothing; they do not mention a trophy count | None |
| README | "85 trophies ... 70" becomes "48 ... 36" | One line |
| `docs/trophies/trophy-catalog.md` | A note at the top, as was done for Pinball | Small |

### Does the SQL depend on the trophy list?

No. Both files store a trophy as its id in a plain text column, checked only
for length (1 to 100 characters). Neither file lists trophy ids, counts them,
or names a category. The public showcase table stores a count per tier, not a
list. **The trophy tables are safe to apply before or after this change.**

One effect to know about: a phone that already unlocked a trophy that is later
cut keeps that id in its saved data, and would send it to the server. The app
ignores ids it does not know, and the statistics table would simply hold a row
nobody displays. Before launch that only concerns test devices.

### Overall size

Roughly 600 to 900 changed lines, about half of them tests. The catalog and
test edits are mechanical. The Trophy Room screen is the part that needs your
eye on a phone, because layout cannot be checked without running it. As with
the rest of this branch, none of it can be compiled here.

Suggested order if you approve: catalog and icon field with tests first (the
icon test proves the symbol names), then the icon in the existing rows and
toasts, then the new Trophy Room layout last.

---

## Quick table

| Trophy | Category | Tier | Icon | Decision |
|---|---|---|---|---|
| Get the Ball Rolling | Climb | Bronze | `flag.fill` | keep |
| Training Wheels Off | Climb | Bronze | — | cut |
| Gathering Momentum | Climb | Bronze | — | cut |
| Beyond the Meadow | Climb | Silver | `figure.hiking` | keep |
| Boulder and Bolder | Climb | Silver | — | cut |
| The Long Roll | Climb | Gold | — | cut |
| Unstoppable Force | Climb | Gold | `bolt.fill` | keep |
| The Summit | Climb | Diamond | `mountain.2.fill` | keep |
| Star Search | Climb | Bronze | — | merge |
| Star-Studded | Climb | Silver | `star.fill` | keep |
| One Hundred Perfect Rolls | Climb | Gold | `globe.americas.fill` | keep |
| Magpie | Climb | Bronze | — | cut |
| Sidetracked | Challenge Tracks | Bronze | — | cut |
| Deep in the Pack | Challenge Tracks | Bronze | `signpost.right.fill` | keep |
| Track Record | Challenge Tracks | Silver | `checkmark.seal.fill` | keep |
| Triple Crown | Challenge Tracks | Silver | — | cut |
| Run the Gauntlet | Challenge Tracks | Gold | `bolt.shield.fill` | keep |
| Full Circuit | Challenge Tracks | Diamond | `8.circle.fill` | keep |
| Glutton for Punishment | Daily | Bronze | — | cut |
| Carpe Rollem | Daily | Bronze | `sunrise.fill` | keep |
| Seven-Day Roller | Daily | Bronze | — | merge |
| Ten Brutal Mornings | Daily | Silver | — | cut |
| Month of Marbles | Daily | Silver | `calendar` | keep |
| Fifty Days of Grit | Daily | Gold | — | cut |
| The Brutal Week | Daily | Gold | `flame.fill` | keep |
| Taste of the Arcade | Minigames (all) | Bronze | — | merge |
| The Grand Tour | Minigames (all) | Bronze | `map.fill` | keep |
| Opening Night | Minigames (all) | Bronze | — | cut |
| Six of the Best | Minigames (all) | Silver | `gamecontroller.fill` | keep |
| Hard Bargain | Minigames (all) | Bronze | — | merge |
| Hundred-Round Veteran | Minigames (all) | Gold | — | cut |
| Master of All Six | Minigames (all) | Gold | `medal.fill` | keep |
| Last Comet Standing | Minigames (per game) | Bronze | — | merge |
| Ten-Tail Comet | Minigames (per game) | Bronze | `scribble.variable` | keep |
| King of the Ring | Minigames (per game) | Bronze | — | merge |
| Immovable Object | Minigames (per game) | Bronze | `figure.wrestling` | keep |
| Fresh Coat | Minigames (per game) | Bronze | — | cut |
| Wall-to-Wall | Minigames (per game) | Silver | `paintbrush.fill` | keep |
| Smash Hit | Minigames (per game) | Bronze | — | merge |
| Serial Smasher | Minigames (per game) | Bronze | `burst.fill` | keep |
| Top Corner | Minigames (per game) | Bronze | — | merge |
| League Regular | Minigames (per game) | Bronze | `soccerball` | keep |
| Hill, Claimed | Minigames (per game) | Bronze | — | cut |
| Squatter's Rights | Minigames (per game) | Silver | `crown.fill` | keep |
| Out of the Woods | Minigames (per game) | Bronze | — | merge |
| Ten-Maze March | Minigames (per game) | Silver | `arrow.triangle.turn.up.right.diamond.fill` | keep |
| The Only Way Is Up | Minigames (per game) | Bronze | — | merge |
| Head in the Clouds | Minigames (per game) | Silver | `cloud.fill` | keep |
| Crossing Guard | Minigames (per game) | Bronze | — | cut |
| Dancing in the Dark | Minigames (per game) | Silver | `figure.dance` | keep |
| Inner Peace | Minigames (per game) | Bronze | `leaf.fill` | keep |
| Garden Sage | Minigames (per game) | Silver | — | merge |
| Pit Stop | Minigames (per game) | Bronze | — | cut |
| Cloudburst | Minigames (per game) | Silver | `cloud.rain.fill` | keep |
| Retail Therapy | Cosmetics | Bronze | — | cut |
| The Full Fit | Cosmetics | Bronze | `tshirt.fill` | keep |
| Boxed Set | Cosmetics | Bronze | — | merge |
| Bag of Marbles | Cosmetics | Bronze | — | merge |
| Curator | Cosmetics | Bronze | `shippingbox.fill` | keep |
| Collector's Eye | Cosmetics | Bronze | — | cut |
| Pack Animal | Cosmetics | Silver | `circle.grid.2x2.fill` | keep |
| Marble Baron | Cosmetics | Gold | `circle.hexagongrid.fill` | keep |
| Every Marble Has a Home | Cosmetics | Diamond | `house.fill` | keep |
| Nest Egg | Economy | Bronze | `dollarsign.circle.fill` | keep |
| Punch Card | Economy | Bronze | — | cut |
| Working Capital | Economy | Bronze | `banknote.fill` | keep |
| Pit Boss | Economy | Silver | — | cut |
| Hello, Rollers | Social | Bronze | — | cut |
| Rolling Together | Social | Bronze | — | merge |
| Rolling Deep | Social | Silver | `person.2.fill` | keep |
| Lifesaver | Social | Bronze | — | merge |
| Guardian Marble | Social | Silver | `heart.fill` | keep |
| Strength in Numbers | Social | Bronze | `person.3.fill` | keep |
| Clutch Delivery | Social | Silver | `gift.fill` | keep |
| Peak Performance | Skill | Bronze | `scope` | keep |
| Gone in Ten Seconds | Skill | Bronze | `stopwatch.fill` | keep |
| Clean Sheet | Skill | Silver | — | merge |
| First Try! | Skill | Bronze | `1.circle.fill` | keep |
| Spotless | Skill | Silver | `sparkles` | keep |
| Untouchable | Skill | Gold | `hand.raised.slash.fill` | keep |
| Gravity Check | Secret | Bronze | `arrow.down.to.line` | keep |
| Night Bloom | Secret | Bronze | `moon.stars.fill` | keep |
| High Roller | Secret | Silver | `dice.fill` | keep |
| Back to Basics | Secret | Bronze | `arrow.uturn.backward.circle.fill` | keep |
| Platinum | Platinum | Platinum | `trophy.fill` | keep |
