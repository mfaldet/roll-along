# Roll Along — v1 Trophy Catalog

> **FREEZE-READY as of 2026-07-07 (S4-T6), pending Mac's launch sign-off.** All 89 trophy IDs + criteria + tiers are frozen-ready — immutable after publish per the cross-platform norm (treat as law). This is NOT yet the final freeze: the one S4-T4 threshold-tuning window (the last chance to re-tune a criterion) must close first, then Mac signs off. Two carve-outs remain deferred by design and are NOT blockers to this stamp: (1) **point weights** stay deferred to the Game Center mirror phase (catalog Q6 / sprint-plan D2) — nothing to freeze in v1; (2) **`whimsy_roll_call`** stays blocked on the pinball ROLL rollover lanes (catalog Q9) — hold-back-vs-substitute is Mac's call before the final freeze. Full ordered launch runway: `docs/trophies/launch-checklist.md`.
> Status: **ADOPTED — RULED 2026-07-02 (design.md §11 #14):** v1 scope as-authored (89 trophies, 5 hidden, 73-visible capstone, point weights deferred), with two same-day naming overrides — rung 4 = **Diamond**, not Legend (design.md §11 #2; R2 disambiguation riders active), and the capstone's display name = **Platinum** (§5). All trophy ids unchanged.
> Date: 2026-07-02
> Provenance: every code claim verified at `064f3cd`, reconciled same-day to `origin/main` `42d1925` (PRs #113/#114/#118–#120/#122–#124 merged 2026-07-02 — economy calibration + tier reprice are LIVE); line refs anchored by symbol, see `research/repo-delta-2026-07-02.md`.
> Tip drift (2026-07-02, post-reconciliation): `origin/main` has since moved `42d1925` → `fb98819` — one commit, the IAP launch-race fix (StoreKitManager delivery ledger `ra_iapDeliveredTxnIDs`) is now MERGED; touches StoreKitManager + its tests only, no GameState or trophy-surface changes.
> Inputs: all six research briefs in `docs/trophies/research/` (internal features / economy /
> data-backend, PlayStation system, platform comparison, F2P monetization). This doc is the
> design source of truth for the v1 trophy list; the research docs are the authority for
> every code/stat claim referenced here.

**The list at a glance: 89 trophies — 49 Bronze / 25 Silver / 11 Gold / 3 Diamond / 1 Platinum capstone.**
Diamond = ultra-hard monuments that do NOT gate the capstone (Sony first-party house rule:
difficulty quarantined off the platinum path). Capstone (**Platinum**) = the platinum-equivalent
umbrella — now literally so. The ruled ladder: Bronze → Silver → Gold → Diamond → Platinum.

> **RULED 2026-07-02 (was OPEN) — reconciliation with design.md:** this catalog diverges from
> the design brief as originally argued; design.md was revised the same day to face this
> catalog directly. Its header callout now enumerates **six** deltas between the two docs and
> consolidates the ruling into **decision #14** (rung-4 naming folded into decision #2) so
> Mac rules on the final shape exactly once — nothing is settled until he does.
> Where the revised design.md landed: it now recommends **adopting this catalog as-authored**
> — Option B with R1 and rung 4 named **Legend**, the **Roll of Honor** capstone, 89
> trophies, 5 hidden, capstone = the 73 visible B/S/G — reversing its original Summit-tier +
> literal-Platinum recommendation (that original argument, including R3's case against a
> flavored capstone name, is preserved in design.md §2 for the record). Downstream specs
> already track this catalog's shape: design.md §6 specifies Legend haptics, design.md §9
> scopes the capstone to the 73 visible B/S/G (Legends and Social quarantined off the path),
> and sprint S2-T1 styles every rung of the D10 ladder. If Mac overrules toward a **Summit**
> grade instead, note this catalog spends "The Summit" on the `climb_summit` trophy — that
> trophy needs renaming (e.g. "World Fifty") and the "Grand Summit" capstone candidate falls
> away (design.md decision #2 spells out the rename chain). Item-level detail lives in open
> questions 1 (naming/gating), 7 (list size vs design.md's original ~40–55 sketch), and
> 11 (hidden count vs P9's original 0–2 target).
>
> → **RULED 2026-07-02:** Mac adopted this catalog via design.md §11 #14 — 89 trophies,
> 5 hidden, capstone = the 73 visible B/S/G, point weights deferred — but overruled both
> names: rung 4 is **Diamond** (design.md §2 R2, overruling Legend and Summit alike; the
> disambiguation riders are active) and the capstone's display name is **Platinum**
> ("Roll of Honor" survives only as an optional future name idea for the Trophy Room
> *screen*, not the trophy). `climb_summit` keeps "The Summit" — the grade isn't Summit,
> so no rename chain fires. Ids unchanged everywhere. Downstream operative text (design.md
> §6 haptics, §9 capstone scope, sprint S2-T1 styling) now reads Diamond/Platinum. Outcomes:
> open questions 1, 2, 4, 7, and 11 are ruled below; 3, 5, 6, 8, 9, and 10 stay open.

## 1. Catalog principles

1. **Pyramid shape.** Everyone always has a next goal: ~55% bronze texture, chunky silver
   mid-goals, few prestigious golds, 4 sub-1% peaks. First third of the list is where most
   players live (median main-path completion is ~10% industry-wide) — front-load delight.
2. **Every trigger objectively testable.** Each trophy names a stat and a comparison. No
   vibes, no judgment calls, no hidden state a player can't reason about.
3. **No trophy requires spending real money — ever.** No IAP counts, no Diamond/Money/
   unlimited-lives criteria (the existing "Unlimited Power" badge anti-pattern is dropped in
   migration). All collection math excludes the 4 IAP secrets (Diamond ball, Money Ball/Roll/
   Full). Borderline cases (coin-balance trophies an IAP can shortcut) are flagged inline.
4. **A climb "level" is a map in an unlock sequence, NOT a difficulty rung.** Level-number
   ladders are framed as journey/persistence milestones, never skill claims. Difficulty tier
   comes from the last digit (1–4 easy, 6–9 hard, 0/5 veryHard) and every level is designed
   passable by all players eventually.
5. **Never key a trophy to a specific level layout.** Climb levels are swappable content
   (`LevelOverrides.json`). Triggers key to lifetime stats and level *numbers/ranges* only.
6. **Lives are friction, never trophy fuel.** Lives are consumed only by climb + Challenge
   Packs (plus Roll Out falls / Roll Up runs under the same `LivesPolicy`). No trophy rewards
   losing lives, running out of lives, watching ads, or losing matches — nothing monetizes
   failure or trains bad sessions.
7. **Daily Challenge is deliberately brutal.** One completion is a real feat; totals and
   streaks are priced accordingly (first clear = bronze but predicted ~15% rarity; 7-day
   completion streak is a gold).
8. **Trophies are ratchets.** Latched into their own `ra_` store with timestamps at unlock,
   never recomputed from live stats, never revoked — `resetProgress()`, Sell Back
   liquidation, and the broken `liveStreak` cannot un-earn anything.
9. **No time-limited trophies, no missables.** Seasonal bundles get shop windows, not
   trophies. Every trophy is earnable forever by any player starting today.
10. **Status-first rewards.** v1 trophies pay **zero coins** (the bounded cosmetic economy
    cannot absorb a permanent faucet; see internal-economy §5c). Earned-regalia cosmetics for
    the capstone/Diamond trophies: **RULED 2026-07-02 — approved** (design.md §11 #3, P2;
    Trophy-ball gating precedent; Mac: "Do not mint coins for trophy rewards"). Binding rider
    (design.md §2 R2): no regalia cosmetic may reference the Diamond ball.
11. **Hidden = secrets and whimsy only** (5 of 89, ~6%). Everything else — including the
    Diamond trophies — is visible: players want targetable mountains. Note: 5 deliberately
    exceeds design.md P9's 0–2 target — a policy divergence ratified 2026-07-02 via decision
    #14 (§4, open question 11).
12. **Toast discipline.** Unlocks earned mid-run queue and present one coalesced banner at
    run end. Never interrupt an active tilt run.
13. **IDs are forever.** Snake_case, alphanumeric+underscore, Game Center-legal, stable across
    all future releases (platform norm: criteria immutable after publish). Snake_case is the
    standard: design.md §9's guardrail wording ("lowercase-kebab") fails its own
    "alphanumeric" GC-legal rule (hyphens) and needs a one-word fix to snake_case —
    kebab-case remains the repo's *filename* convention only. GC budget note: the mirror is a
    curated canon subset (design.md §8: "spend well under half" of the 100-slot budget,
    mirror only stable canon) — do NOT read "89 < 100" as headroom; mirroring all 89 would
    spend 89% of the slots and leave 11 for every future minigame/track.
14. **English-only, unlocalized.** The app has zero i18n infrastructure (no `.lproj`, no
    `.xcstrings`, no `NSLocalizedString`) and the trophy titles lean on English wordplay by
    design. Titles/descriptions ship unlocalized; ids are language-neutral, so localization
    later is a pure data change. The "≥1 localization" a GC mirror requires (sprint S3-T6)
    is just en-US.

## 2. Tier budget

| Category | Bronze | Silver | Gold | Diamond | Capstone | Total |
|---|---|---|---|---|---|---|
| Climb | 5 | 3 | 3 | 1 | — | 12 |
| Challenge Tracks | 2 | 2 | 1 | 1 | — | 6 |
| Daily Challenge & Streaks | 3 | 2 | 2 | — | — | 7 |
| Minigames — arcade-wide | 4 | 1 | 2 | — | — | 7 |
| Minigames — per-game (12 games) | 16 | 8 | 1 | — | — | 25 |
| Cosmetics & Collection | 6 | 1 | 1 | 1 | — | 9 |
| Economy & Shop | 3 | 1 | — | — | — | 4 |
| Social — Friends & Clans | 4 | 3 | — | — | — | 7 |
| Skill & Style | 3 | 2 | 1 | — | — | 6 |
| Secret & Whimsy (all hidden) | 3 | 2 | — | — | — | 5 |
| Capstone | — | — | — | — | 1 | 1 |
| **Total (89)** | **49 (55%)** | **25 (28%)** | **11 (12%)** | **3** | **1** | **89** |

Challenge Tracks get their own category (not in the original category list) because they are
the game's primary permanent skill-reward loop — exactly the "permanent monument" the F2P
research says deserves trophies.

## 3. The catalog

Column key — **data_source**: `EXISTING` names the persisted `GameState` property from
internal-features.md §2; `NEW:` names required instrumentation (deduplicated in §6).
**predicted_rarity** bands: common ≥50% · uncommon 15–49% · rare 5–14% · very-rare 1–4.9% ·
ultra-rare <1% of installs that ever launched (denominator decision: internal-data-backend §5).
All %s are pre-launch guesses — recalibrate from telemetry, and suppress player-facing
percentages until a minimum earner population exists (cold-start noise).

> **OPEN — rarity band reconciliation:** the bands above are this catalog's *internal
> prediction* bands. The *player-facing* labels design.md §3 adopts (and sprint S3-T4
> implements: "labels match cutoffs from design.md") are PSN's four: Common ≥50% · Rare
> <50% · Very Rare <15% · **Ultra Rare <5%**. Mapping: catalog "uncommon" → displays Rare;
> catalog "rare" (5–14%) → displays Very Rare; catalog "very-rare" AND "ultra-rare"
> (everything <5% — 33 of 89 trophies) → all display **Ultra Rare**. So "only the monuments
> are ultra-rare" is true of the internal <1% band but NOT of the shipped label. Mac must
> pick one band set for display: bless the PSN cutoffs (and read §7 in display terms), or
> adopt this finer 5-band scheme in design.md §3 / decision #6 (open question 8).

### 3.1 Climb

| id | name | tier | trigger | data_source | predicted_rarity | notes |
|---|---|---|---|---|---|---|
| climb_first_clear | Get the Ball Rolling | bronze | Clear climb level 1 | EXISTING `highestUnlocked` ≥ 2 (checked in `recordResult`) | common 90% | The hello-world trophy; near-guaranteed first toast |
| climb_level_10 | Training Wheels Off | bronze | Clear climb level 10 | EXISTING `highestUnlocked` ≥ 11 | common 60% | Tutorial ends; lives start mattering; free bundle pick lands here |
| climb_level_50 | Gathering Momentum | bronze | Clear climb level 50 | EXISTING `highestUnlocked` ≥ 51 | uncommon 28% | Successor to the retired "legend" badge — NOT exact parity: the badge fired on *unlocking* L50 (`highestUnlocked` ≥ 50, ProfileView), this trigger on *clearing* it (≥ 51). A veteran at exactly 50 re-earns it one level later; accept + document, or set ≥ 50 for strict parity (see migration note, §6) |
| climb_level_100 | Beyond the Meadow | silver | Clear climb level 100 (all of World 1, Meadowgate) | EXISTING `highestUnlocked` ≥ 101 | rare 12% | World names are stable code (LevelLayout), safe to theme on |
| climb_level_250 | Boulder and Bolder | silver | Clear climb level 250 | EXISTING `highestUnlocked` ≥ 251 | rare 5% | |
| climb_level_500 | The Long Roll | gold | Clear climb level 500 | EXISTING `highestUnlocked` ≥ 501 | very-rare 2.5% | |
| climb_level_1000 | Unstoppable Force | gold | Clear climb level 1,000 | EXISTING `highestUnlocked` ≥ 1001 | very-rare 1.2% | Persistence monument, not a skill claim (principle 4) |
| climb_summit | The Summit | **diamond** | Clear climb level 5,000 — the last level of World 50, "The Summit" | EXISTING `highestUnlocked` ≥ 5001 | ultra-rare 0.05% | The named-world ceiling; climb continues beyond but the story peak is here. Off capstone path |
| climb_stars_25 | Star Search | bronze | Earn 25 total climb stars | EXISTING `totalStars` ≥ 25 (latched) | uncommon 45% | Latch — `resetProgress()` can shrink the live sum |
| climb_stars_150 | Star-Studded | silver | Earn 150 total climb stars | EXISTING `totalStars` ≥ 150 (latched) | rare 10% | Parity with retired "stellar" badge |
| climb_perfect_world | One Hundred Perfect Rolls | gold | Hold 3 stars on every level of any single world (all 100 levels of one `World.levelRange`) | EXISTING `bestStars` scan over world ranges | very-rare 1.5% | Keys to star dict + number ranges, not layouts — content swaps safe |
| climb_pickups_100 | Magpie | bronze | Bank 100 level pickup coins lifetime | EXISTING `totalCoins` ≥ 100 (latched) | uncommon 30% | `totalCoins` = pickups found, NOT coin balance (the old Coin Hoarder badge's trap, documented) |

**Implementation guard:** climb triggers must ignore Daily Challenge runs. The CotD
`.oneShot` fast-path is MERGED (PR #123): a CotD clear now returns before `recordResult` —
no stars/time stamping, no `highestUnlocked` bump — and BallGameView asserts
`activeMode.progression.recordsClimbResult` before the climb record path, so the pollution
bug is fixed at source. The trophy engine's own gate is **defense-in-depth**: key climb
checks to `activeMode.progression.recordsClimbResult` (only `.mainClimb` is true; GameMode.swift)
or the mode id `climb`, mirroring the shipped assert.

### 3.2 Challenge Tracks

| id | name | tier | trigger | data_source | predicted_rarity | notes |
|---|---|---|---|---|---|---|
| track_first_level | Sidetracked | bronze | Clear level 1 of any Challenge Track | EXISTING any `trackProgress[id]` ≥ 1 | uncommon 25% | Discovery pointer at the 8 tracks |
| track_halfway | Deep in the Pack | bronze | Reach level 50 in any single track | EXISTING any `trackProgress[id]` ≥ 50 | rare 8% | Mid-track motivation through the 6-phase difficulty arc |
| track_first_complete | Track Record | silver | Complete any Challenge Track (level 100) | EXISTING `completedTracks.count` ≥ 1 | very-rare 3.5% | Pairs with the free bundle grant — trophy + loot in one moment |
| track_triple | Triple Crown | silver | Complete 3 Challenge Tracks | EXISTING `completedTracks.count` ≥ 3 | very-rare 1.8% | Exactly the golden-gauntlet unlock gate — trophy doubles as signpost |
| track_gauntlet | Run the Gauntlet | gold | Complete the golden-gauntlet track | EXISTING `"golden-gauntlet"` ∈ `completedTracks` | very-rare 1.2% | Lands with the champion bundle + earned-exclusive Trophy ball; the game's existing trophy-as-cosmetic precedent |
| track_all_eight | Full Circuit | **diamond** | Complete all 8 Challenge Tracks | EXISTING `completedTracks.count` ≥ 8 | ultra-rare 0.3% | 800 levels of arc content; off capstone path |

### 3.3 Daily Challenge & Streaks

| id | name | tier | trigger | data_source | predicted_rarity | notes |
|---|---|---|---|---|---|---|
| daily_first_start | Glutton for Punishment | bronze | Start your first Challenge of the Day | NEW: insert `"daily"` into `playedModeIDs` at the daily start site (§6 item 18) | uncommon 35% | Discovery trophy; starting is free (3 attempts/sub-level, no lives). The stat exists but nothing writes `"daily"` at HEAD: the daily route builds BallGameView without `.firstPlayTutorial`, and `ModeTutorial.for("daily")` is nil so `markModePlayed` would no-op anyway |
| daily_first_clear | Carpe Rollem | bronze | Complete your first Challenge of the Day | EXISTING `dailyChallengeCompletions.count` ≥ 1 | uncommon 15% | Bronze by position, brutal by design — rarity will run low and that's intended (principle 7) |
| daily_login_7 | Seven-Day Roller | bronze | Reach a 7-day daily-reward streak | EXISTING `dailyStreak` ≥ 7 (latched) | uncommon 20% | Parity with retired "on_a_roll" badge; latch — do not use the broken computed `liveStreak` |
| daily_clears_10 | Ten Brutal Mornings | silver | Complete 10 Challenges of the Day lifetime | EXISTING `dailyChallengeCompletions.count` ≥ 10 | very-rare 4% | Full date-set already on disk — zero new instrumentation |
| daily_login_30 | Month of Marbles | silver | Reach a 30-day daily-reward streak | EXISTING `dailyStreak` ≥ 30 (latched) | rare 6% | Parity with retired "dedicated" badge |
| daily_clears_50 | Fifty Days of Grit | gold | Complete 50 Challenges of the Day lifetime | EXISTING `dailyChallengeCompletions.count` ≥ 50 | very-rare 1.5% | Minimum 50 calendar days — a months-long chase by construction |
| daily_week_streak | The Brutal Week | gold | Complete the Challenge of the Day on 7 consecutive calendar dates | EXISTING derived from `dailyChallengeCompletions` date set (NEW derivation helper, no storage) | very-rare 1.2% | The hardest repeatable feat in the game; deliberately gold not diamond so it stays on the capstone path |

### 3.4 Minigames — arcade-wide

| id | name | tier | trigger | data_source | predicted_rarity | notes |
|---|---|---|---|---|---|---|
| arcade_sampler | Taste of the Arcade | bronze | Play 5 different minigames | EXISTING `playedModeIDs` ∩ 12 minigame ids ≥ 5 | uncommon 40% | Discovery-map trophy (players read trophy lists, skip tutorials) |
| arcade_grand_tour | The Grand Tour | bronze | Play all 12 minigames at least once | EXISTING `playedModeIDs` covers all 12 ids | rare 12% | Includes zen + coinpit (coinpit needs a ticket → nudges a competitive win) |
| arcade_first_win | Opening Night | bronze | Win your first competitive minigame (any of snake/sumo/paintball/goldrush/marblecup/koth) | EXISTING sum of `minigameWins` over 6 ids ≥ 1 | uncommon 25% | Also the moment the player mints their first ticket |
| arcade_all_six | Six of the Best | silver | Win at least once in each of the 6 competitive modes | EXISTING `minigameWins[id]` ≥ 1 for all 6 ids | rare 6% | |
| arcade_hard_once | Hard Bargain | bronze | Win any competitive minigame on Hard difficulty | EXISTING any `minigameDifficultyWins["<id>\|hard"]` ≥ 1 | rare 8% | Hard targets a 0.22 win rate — a few honest attempts |
| arcade_wins_100 | Hundred-Round Veteran | gold | 100 lifetime competitive-minigame wins (sum across the 6 modes) | EXISTING sum of `minigameWins` ≥ 100 | very-rare 2% | Accrues from natural play; also ≈100 tickets minted |
| arcade_hard_all | Master of All Six | gold | Win on Hard in all 6 competitive modes | EXISTING `minigameDifficultyWins["<id>\|hard"]` ≥ 1 for all 6 | very-rare 1.2% | Hard AI is surgical by design — this is the arcade skill crown |

### 3.5 Minigames — per game

**Naming trap (implementers):** mode id `goldrush` = the Smash and Grab minigame;
`goldrushBest`/`goldrushCoinsTotal` stats = the ticket-staked **Coin Pit** reward run.
`minigameWins["goldrush"]` counts Smash and Grab wins, not Coin Pit anything.

All PB-threshold triggers below marked *calibrate* must be re-derived from `minigame_result`
telemetry before ship — the numbers here are design intents, not measured percentiles.

| id | name | tier | trigger | data_source | predicted_rarity | notes |
|---|---|---|---|---|---|---|
| snake_first_win | Last Comet Standing | bronze | Win a Comet Clash round | EXISTING `minigameWins["snake"]` ≥ 1 | uncommon 15% | |
| snake_wins_10 | Ten-Tail Comet | bronze | Win 10 Comet Clash rounds lifetime | EXISTING `minigameWins["snake"]` ≥ 10 | rare 5% | |
| sumo_first_win | King of the Ring | bronze | Win a Sumo Survival match (rank #1) | EXISTING `minigameWins["sumo"]` ≥ 1 | uncommon 15% | |
| sumo_wins_10 | Immovable Object | bronze | Win 10 Sumo Survival matches lifetime | EXISTING `minigameWins["sumo"]` ≥ 10 | rare 5% | |
| paintball_first_win | Fresh Coat | bronze | Win a Paint Ball round | EXISTING `minigameWins["paintball"]` ≥ 1 | uncommon 18% | |
| paintball_coverage_60 | Wall-to-Wall | silver | Finish a Paint Ball round with ≥60% floor coverage | EXISTING `minigameBests["paintball"]` ≥ 60 | very-rare 4% | *calibrate*; coverage % is a bounded, legible unit |
| goldrush_first_win | Smash Hit | bronze | Win a Smash and Grab round | EXISTING `minigameWins["goldrush"]` ≥ 1 | uncommon 15% | |
| goldrush_wins_10 | Serial Smasher | bronze | Win 10 Smash and Grab rounds lifetime | EXISTING `minigameWins["goldrush"]` ≥ 10 | rare 5% | |
| marblecup_first_win | Top Corner | bronze | Win a Marble Cup match | EXISTING `minigameWins["marblecup"]` ≥ 1 | uncommon 15% | |
| marblecup_wins_10 | League Regular | bronze | Win 10 Marble Cup matches lifetime | EXISTING `minigameWins["marblecup"]` ≥ 10 | rare 5% | |
| koth_first_win | Hill, Claimed | bronze | Win a King of the Hill round | EXISTING `minigameWins["koth"]` ≥ 1 | uncommon 15% | |
| koth_hold_45 | Squatter's Rights | silver | Hold the hill for ≥45 seconds total in a single 60-second round | EXISTING `minigameBests["koth"]` ≥ 45 | very-rare 3% | *calibrate*; hold-seconds is the stored score unit |
| pinball_score_10k | Bumper Crop | bronze | Score 10,000+ in a single Pinball game | EXISTING `pinballBest` ≥ 10,000 | uncommon 20% | *calibrate* — the shipped table's only scorers are 3 bumpers ×100 pts + 2 slingshots ×10 pts, so today's realistic ceiling sits far below all three tiers (150k ≈ 1,500 bumper hits in one 3-ball game); thresholds assume the roadmap's target/lane scoring lands — re-derive all three tiers post-tune (§6 item 16) |
| pinball_score_50k | Silver Ball Society | silver | Score 50,000+ in a single Pinball game | EXISTING `pinballBest` ≥ 50,000 | rare 6% | *calibrate* |
| pinball_score_150k | Lit the Special | gold | Score 150,000+ in a single Pinball game | EXISTING `pinballBest` ≥ 150,000 | very-rare 1.5% | *calibrate*; the EM-"Special" flavor names a lit-target sequence that exists only in the pinball roadmap, NOT in the shipped table — keep the name only if that roadmap scoring work ships, else rename |
| rollout_first_maze | Out of the Woods | bronze | Reach the goal of your first Roll Out maze | EXISTING `minigameBests["rollout"]` ≥ 1 | uncommon 20% | Roll Out writes bests in-view — needs funnel reroute (§6 item 12) |
| rollout_maze_10 | Ten-Maze March | silver | Reach maze 10 in Roll Out | EXISTING `minigameBests["rollout"]` ≥ 10 | very-rare 4% | *calibrate*; falls cost lives here — chase interacts with the friction economy, keep threshold honest |
| rollup_100m | The Only Way Is Up | bronze | Reach 100 m height in a Roll Up run | EXISTING `minigameBests["rollup"]` ≥ 100 | uncommon 18% | *calibrate*; each run costs a life |
| rollup_500m | Head in the Clouds | silver | Reach 500 m height in a Roll Up run | EXISTING `minigameBests["rollup"]` ≥ 500 | very-rare 3% | *calibrate* |
| disco_cross_25 | Crossing Guard | bronze | Make 25 crossings in a single Disco Ball run (any difficulty) | EXISTING max over `minigameBests["discoeasy"/"disco"/"discohard"]` ≥ 25 | uncommon 15% | *calibrate*; Disco writes bests in-view — needs funnel reroute (§6 item 12) |
| disco_hard_10 | Dancing in the Dark | silver | Make 10 crossings in a single Disco Ball run on Hard | EXISTING `minigameBests["discohard"]` ≥ 10 | very-rare 3% | *calibrate* |
| zen_hour | Inner Peace | bronze | Accumulate 1 hour of Zen Garden time | EXISTING `zenSeconds` ≥ 3,600 | rare 12% | |
| zen_10_hours | Garden Sage | silver | Accumulate 10 hours of Zen Garden time | EXISTING `zenSeconds` ≥ 36,000 | very-rare 3% | AFK-farmable (endless, no fail state) — silver ceiling is deliberate; never gold |
| coinpit_first_round | Pit Stop | bronze | Play your first Coin Pit round | EXISTING `"coinpit"` ∈ `playedModeIDs` | uncommon 15% | Requires a ticket → implicitly requires a competitive win; teaches the skill loop |
| coinpit_catch_90 | Cloudburst | silver | Catch 90+ coins in a single Coin Pit round | EXISTING `goldrushBest` ≥ 90 | very-rare 2.5% | *calibrate*; ~100 coins drop per 30s block, modeled catch rate 40–80% — 90 is elite reflexes |

### 3.6 Cosmetics & Collection

All ownership counts **exclude the 4 IAP secrets** (Diamond ball, Money Ball, Money Roll,
Money Full) so no collection trophy is a paywall in costume. The earned-exclusive Trophy ball
and coin-buyable Aurora DO count (skill/coin-reachable). Note on Aurora: PR #114 (merged)
makes a Starter Pack restore grant the full 6-item Aurora bundle free — a small
legacy-buyer-only shortcut toward collection counts, not a pay-gate, since Aurora is
coin-reachable for everyone. All coin figures in §3.6–§3.7 were derived at `064f3cd`
(pre-reprice) prices — **the tier reprice is now MERGED** (PR #124, 2026-07-02: tiers
750/1,000/1,250/1,500, bundle floors 5,500/6,500, bundle fullPrice 4,500–13,500, canonical
earn rate ~25 coins/min), so the §6 item 16 price re-derivation pass is **unblocked and
mandatory** before the S4-T6 criteria freeze. Directional post-reprice figures are inlined
per row below; treat them as estimates until item 16 runs.

| id | name | tier | trigger | data_source | predicted_rarity | notes |
|---|---|---|---|---|---|---|
| cosmetic_first_buy | Retail Therapy | bronze | Buy any cosmetic, bundle, or ball pack with coins | EXISTING hook at `GameState.purchase`/`purchaseBundle`/`purchasePack` (all GameState funnels since PR #120 moved the bundle buy out of CosmeticShopView; latch on first success) | uncommon 45% | Free grants (tutorial gift, track rewards) do NOT count — must be a coin spend |
| cosmetic_full_kit | The Full Fit | bronze | Have a non-starter cosmetic equipped in all 7 slots simultaneously | EXISTING equipped-slot properties, checked on equip | uncommon 25% | Teaches that there ARE 7 slots (Ball/Goal/Trail/Floor/Pit/Boundary/Music) |
| bundle_first | Boxed Set | bronze | Complete any cosmetic bundle | EXISTING `completedBundleIDs.count` ≥ 1 | common 55% | The post-tutorial free Standard bundle auto-completes one at ~L10 — intended as the bundle-system intro |
| balls_own_10 | Bag of Marbles | bronze | Own 10 ball skins | EXISTING `ownedBallSkins.count` (IAP secrets excluded) ≥ 10 | uncommon 20% | 74-ball catalogue; aims players at its deepest shelf |
| bundle_5 | Curator | bronze | Complete 5 cosmetic bundles | EXISTING `completedBundleIDs.count` ≥ 5 | rare 6% | Retunes the retired "bundle_hunter" badge (was 3) |
| items_own_50 | Collector's Eye | bronze | Own 50 cosmetics total across all 7 slots | EXISTING sum of owned sets (IAP secrets excluded) ≥ 50 | rare 8% | 218-item catalogue; mid-game accumulation marker |
| pack_first | Pack Animal | silver | Own any ball pack (Planets / Sports / Vintage Glass) | EXISTING `ownedPacks.count` ≥ 1 | rare 5% | Cheapest pack is now Sports at 3,300 coins post-reprice (was 520; live: Planets 7,920 / Sports 3,300 / Vintage Glass 3,780); teaches shuffle-equip |
| balls_own_40 | Marble Baron | gold | Own 40 ball skins | EXISTING `ownedBallSkins.count` (IAP secrets excluded) ≥ 40 | very-rare 1.2% | ~37–45k coins by the cheapest 40-ball route post-reprice (à la carte cheapest-40 = 45,000: 13×750 + 15×1,250 + 11×1,500; the three packs shave it to ~37k; full ball shelf ≈ 96k; was ~26k pre-reprice) — the long identity chase; re-derive at §6 item 16 |
| collection_complete | Every Marble Has a Home | **diamond** | Own every *evergreen* coin-or-skill-reachable cosmetic (207 items: 218 total − 4 IAP secrets − 7 seasonal bundle-exclusive balls) | EXISTING owned sets vs full catalogue minus the 4 IAP secrets and the 7 seasonal exclusives | ultra-rare 0.1% | The pre-reprice pre-exclusion total was ~52,550 coins ≈ 44h — both numbers are now stale: re-derive the 207-item evergreen set from the live catalogue (tiers 750–1,500, bundle fullPrice 4,500–13,500; the balls/goals/trails censuses alone re-price to ~150k coins, putting the full evergreen set on the order of ~200k ≈ 130+ h at the canonical ~25 coins/min) at §6 item 16; off capstone path. Guardrail: keep bundles IAP-secret-free forever so this stays $0-reachable |

> **OPEN — seasonal exclusives vs principle 9:** beachBall, pumpkin, ornament, heartstone,
> shamrock, confetti, and speckledEgg are `isBundleExclusive` (never sold individually, never
> in shop rotation) and each lives ONLY in a seasonal bundle with a hard-coded one-shot
> 2026–27 window (`availableFrom/Until` in Cosmetics.swift; e.g. summer-2026 ends 2026-09-01,
> spring-2027 ends 2027-05-01). Once a window lapses the item is permanently unobtainable
> without a code change — requiring them would make this trophy time-limited and eventually
> dead, the exact grievance principle 9 and design.md P5 forbid, so they are excluded above
> (mirroring the IAP-secret exclusion). Alternative if Mac wants the full 214: make the
> seasonal windows recurring (or add a permanent acquisition path for seasonal exclusives) as
> a shipping prerequisite, recorded in §6 and the sprint plan (open question 10).

### 3.7 Economy & Shop

Deliberately thin — the economy is where trophy design goes wrong. No "coins spent" trophies
(Sell Back now refunds `min(coinCost/2, paidPrice)` — PR #118 closed the old 100%-refund
zero-cost farm, but a spend counter is still churnable at a 50% loss per cycle, and refunds
are recycled capital, not play income), no IAP trophies, no shop-checking gamification.

| id | name | tier | trigger | data_source | predicted_rarity | notes |
|---|---|---|---|---|---|---|
| econ_nest_egg | Nest Egg | bronze | Hold 1,000 coins at once | EXISTING `coinBalance` ≥ 1,000 (latched) | uncommon 35% | **FLAGGED borderline — stronger post-reprice:** the smallest coin pack alone ($0.99 = 750) nearly clears it, and 1,000 coins no longer buys even two Standard items (750 each). Earnable free in ~40 min at the canonical ~25 coins/min; likely needs raising or re-flagging at §6 item 16. Accepted per "money may accelerate, never be required" — but Mac should veto or re-price at Q3 |
| econ_punch_card | Punch Card | bronze | Claim 30 daily login rewards lifetime | NEW: lifetime claim counter in `claimDailyReward` | uncommon 15% | Counts claims, not streaks — kind to imperfect schedules; no coin payout (respects the 86% ladder nerf) |
| econ_working_capital | Working Capital | bronze | Earn 5,000 lifetime coins from play | NEW: source-tagged lifetime-earned counter in `addCoins` (excludes IAP grants, Sell Back refunds, AND `grantBundleFree` bundle-gift compensation) | uncommon 22% | The exclusions stay load-bearing post-#118: Sell Back now refunds `min(coinCost/2, paidPrice)` — no longer mints coins, but refunds are recycled capital, not play income (a wardrobe liquidation would jump an inclusive counter without play), and PR #114's `grantBundleFree` mints refund-shaped compensation through `addCoins`. Climb now pays tier-scaled 2/3/4 on EVERY clear (replay parity, PR #118), so lifetime play-earned accrues much faster — recheck the 5,000 threshold and the 22% rarity guess at §6 item 16 |
| econ_pit_boss | Pit Boss | silver | Catch 2,500 lifetime coins in Coin Pit rounds | EXISTING `goldrushCoinsTotal` ≥ 2,500 | very-rare 3% | Rewards the wins→tickets→Coin Pit skill loop the economy wants players in |

### 3.8 Social — Friends & Clans

**Off the capstone path** (Sony house rule: no online/population-dependent trophies gate the
platinum; also every trophy here requires Sign-in-with-Apple, and sign-in conversion is ~0%
today). These are the retention handoff — research says social carries the endgame — so they
exist to point players at Friends/Clans, not to gate anyone's completion.

| id | name | tier | trigger | data_source | predicted_rarity | notes |
|---|---|---|---|---|---|---|
| social_sign_in | Hello, Rollers | bronze | Sign in with Apple for the first time | NEW: latch on `SocialClient.setSession` success | uncommon 18% | Free, private (no-PII posture); the gateway to everything below |
| social_first_friend | Rolling Together | bronze | Have your first accepted friend | NEW: latch on friend-accept / first fetch showing ≥1 accepted friendship | rare 6% | Population-dependent — acceptable off-capstone |
| social_friends_5 | Rolling Deep | silver | Have 5 accepted friends | NEW: friend-count high-water latch | very-rare 2% | |
| social_send_life | Lifesaver | bronze | Send a life to a friend | NEW: latch on `sendLife` success | rare 5% | Generosity, not consumption — gives are free to the sender's cap |
| social_lives_sent_25 | Guardian Marble | silver | Send 25 lives lifetime (friend gifts + clan fulfillments) | NEW: lifetime lives-sent counter | very-rare 1.5% | |
| clan_join | Strength in Numbers | bronze | Join or create a clan | NEW: latch on `joinClan`/`createClan` success | rare 8% | |
| clan_fulfill | Clutch Delivery | silver | Fulfill a clan-mate's life request | NEW: latch on clan life-request fulfillment | very-rare 3% | The clans-as-lives-community loop in one act |

### 3.9 Skill & Style

The "for the love of the roll" category — precision feats that are fun-hard, not chore-hard.

| id | name | tier | trigger | data_source | predicted_rarity | notes |
|---|---|---|---|---|---|---|
| skill_ace_veryhard | Peak Performance | bronze | Earn 3 stars on any veryHard climb level (number ending in 0 or 5) above level 10 | EXISTING `bestStars[L]` == 3 for some L > 10 with L % 5 == 0 | uncommon 25% | Digit rule is the stable difficulty vocabulary (LevelLayout) |
| skill_speed_10s | Gone in Ten Seconds | bronze | Clear any climb level in 10 seconds or less | EXISTING any `bestTime[L]` ≤ 10.0 | uncommon 30% | Layout-agnostic because ANY level qualifies |
| skill_clean_sheet_10 | Clean Sheet | silver | Clear 10 climb levels in a row without a single fall | NEW: consecutive no-fall clear streak counter (reset on any climb fall) | rare 5% | Streak persists across sessions; climb-mode only |
| skill_first_try | First Try! | bronze | Earn 3 stars on a level on your very first attempt at it | NEW: first-attempt detection in the run lifecycle (no prior clear, no fall/restart before the goal) | uncommon 35% | Happens naturally on early levels — a delight generator |
| skill_spotless | Spotless | silver | In one single run: 3 stars AND all 3 pickup coins on the same level | NEW: run-scoped composite check at `recordResult` (stars==3 + pickups banked this run) | rare 12% | The "perfect line" trophy |
| skill_clean_sheet_25 | Untouchable | gold | Clear 25 climb levels in a row without a single fall | NEW: same streak counter as Clean Sheet | very-rare 1.5% | The skill crown of the climb; same counter, second threshold |

### 3.10 Secret & Whimsy — all hidden

| id | name | tier | trigger | data_source | predicted_rarity | notes |
|---|---|---|---|---|---|---|
| whimsy_gravity_check | Gravity Check | bronze | Fall into the pit on climb level 1 | NEW: fall-event hook on tutorial levels (falls ≤L10 never call `consumeLife` — hook the fell-overlay path) | uncommon 40% | Costs nothing (tutorial exempt); turns the first faceplant into a laugh |
| whimsy_night_bloom | Night Bloom | bronze | Tend the Zen Garden between midnight and 4 AM local time | NEW: wall-clock check in `addZenSeconds` | very-rare 3% | Whimsy for night owls; hidden so it never becomes an obligation |
| whimsy_roll_call | R-O-L-L Call | silver | Complete all four ROLL rollover lanes in a single pinball ball | NEW — **FUTURE, blocked on the ROLL-lanes build-out:** the shipped table has NO rollover lanes (its only scorers are 3 bumpers + 2 slingshots); the lanes must be BUILT before any event can be wired (§6 item 11) | very-rare 2% | The ROLL top lanes exist only in docs/pinball-roadmap.md — the SpriteKit rebuild itself has landed (the shipped table is the SpriteKit one), but its ROLL-lanes roadmap item is still unbuilt. Hold this trophy back until the lanes ship (post-launch additive is fine) or substitute a v1 whimsy silver keyed to the shipped table — Mac's call (open question 9) |
| whimsy_high_roller | High Roller | silver | Stake 5+ tickets on a single Coin Pit round | NEW: round stake-count hook at Coin Pit round start | very-rare 3% | Rewards confidence in the ticket loop; discoverable by natural big-stake behavior |
| whimsy_back_to_basics | Back to Basics | bronze | Equip the full all-starter loadout while owning 20+ cosmetics | EXISTING equipped slots + owned counts, checked on equip | very-rare 2% | The nostalgia wink — dressing down after making it |

### 3.11 Capstone

| id | name | tier | trigger | data_source | predicted_rarity | notes |
|---|---|---|---|---|---|---|
| capstone_all | **Platinum** (see §5 — RULED 2026-07-02; id unchanged) | capstone | Unlock every visible Bronze, Silver, and Gold trophy (73 trophies: all categories except Social, Secret & Whimsy, and the 3 Diamonds) | Trophy ledger itself (union of the others — zero extra bookkeeping) | ultra-rare 0.2% | Offline-achievable, $0-achievable, no 2-4-AM requirements, no other humans required — "did everything meaningful once" |

## 4. Hidden trophies

Exactly the 5 Secret & Whimsy trophies are hidden (name + description masked until unlock;
show them as "???" rows so the count is visible). Why these and only these:

- They are jokes/surprises meant to be stumbled on — revealing "play Zen at 3 AM" up front
  converts a wink into a checklist obligation (the anti-pattern the research warns about).
- Nothing hidden gates the capstone, so hiding costs no player their completion.
- Everything else — including the three Diamond trophies — is visible: players want targetable
  mountains (hidden-trophy usage industry-wide fell to 10–15% for this reason; we're at ~6%).
- Do not leak hidden state: if a Game Center mirror ships later, never report interim
  progress on these five (any progress report reveals a hidden GC achievement).
- **Policy divergence:** 5 hidden deliberately exceeds design.md P9's original "0–2,
  spoilers only" target. Revised design.md P9 now flags the catalog's 5 and folds
  ratification into decision #14; if Mac rules the other way, cut to 0–2 by making the
  least spoiler-like visible (`whimsy_back_to_basics` and `whimsy_high_roller` are the
  candidates). Open question 11. → **RULED 2026-07-02: ratified at 5** (via #14).

## 5. The capstone

The platinum-equivalent, awarded for all 73 visible bronze/silver/gold trophies. Naming:
design.md originally argued the capstone should simply be called **Platinum** (rejecting a
flavored name as resolution R3), but its revised decision #14 now recommends adopting this
catalog's **Roll of Honor** — R3's argument stands in design.md §2 for the record, and Mac
rules once via design.md §11 (see the reconciliation note at the top and open question 1).
If the flavored route survives that ruling, name candidates in Roll Along's voice:

1. **Roll of Honor** — *recommended.* The pun does triple duty (roll of honor / the honor of
   the roll / a literal scroll of trophies), and it names the trophy-room screen for free.
2. **The Grand Summit** — climbing theme; echoes World 50 ("The Summit") without colliding
   with the `climb_summit` legend.
3. **Marble Monument** — what the whole list is: a permanent monument in marble.

→ **RULED 2026-07-02: the capstone's display name is "Platinum"** (design.md §11 #14
naming override; id `capstone_all` unchanged). The flavored route did not survive the
ruling — the candidates above stand as history. "Roll of Honor" survives only as an
optional future name idea for the Trophy Room *screen* (not the trophy).

Ceremony: escalate exactly once, here — unique full-screen moment, unique sound, confetti,
auto-generated `ResultShareCard` (the mobile analog of the PS5 platinum clip). Every other
trophy shares one consistent toast + signature sound. Earned-regalia cosmetics are
**approved (RULED 2026-07-02**, design.md §11 #3 / principle 10**)** — this is the moment
that pays one: engraved-gold
"Laurel" ball via the existing iconic/earned gating (Trophy-ball pattern), never sellable,
never in shop or rotation. Binding rider (design.md §2 R2): the regalia may never visually
reference the Diamond ball.

## 6. Instrumentation gap checklist (deduplicated — feeds the sprint plan)

Existing-stat trophies (58 of 89 — `daily_first_start` turned out to need wiring, item 18)
need only the ledger + checks at the GameState choke points. The rest need the items below.

1. **Trophy ledger (foundation, all 89):** `ra_trophyUnlocks` id set + `ra_trophyUnlockDates`
   timestamps; latched, never revoked; survives `resetProgress()` and Sell Back; string-set
   persistence per the existing GameState helpers.
2. **Trigger evaluation at choke points (foundation):** `recordResult`, `advanceLevel`,
   `advanceTrackProgress`, `recordMinigameResult`, `recordCompetitiveWin`, the record-PB
   functions, `grant`, `addCoins`, `claimDailyReward`, `completeTodaysDailyChallenge`,
   `purchase`/`purchaseBundle`/`purchasePack`, equip setters. Plus retro-evaluation of all
   derivable triggers once at first launch (grandfathering — players keep their history).
3. **Climb-mode guard (defense-in-depth):** the `.oneShot` fast-path is MERGED (PR #123) —
   CotD clears return before `recordResult` and an assert on
   `progression.recordsClimbResult` guards the climb path — but trophy checks still gate on
   `progression.recordsClimbResult` (or mode id `climb`) so no future mode pollutes climb
   trophies.
4. **Lifetime play-earned coins counter** with source tagging in `addCoins`
   (play / daily / IAP / refund / gift-compensation; exclude IAP grants, Sell Back refunds,
   and `grantBundleFree` bundle-gift compensation — PR #114 mints refund-shaped credits
   through `addCoins`) → `econ_working_capital`.
5. **Lifetime daily-reward claim counter** in `claimDailyReward` → `econ_punch_card`.
6. **Consecutive no-fall clear streak counter** (increment on fall-free climb clear, reset on
   climb fall; persisted) → `skill_clean_sheet_10`, `skill_clean_sheet_25`.
7. **First-attempt detection** (transient run flag: level had no prior clear and no
   fall/restart before the goal) → `skill_first_try`. Post-#118 note: BallGameView no
   longer computes `isFirstClear` (climb pays on every clear now) — derive "no prior
   clear" from `time(for: level) == nil` / no `bestStars` entry BEFORE `recordResult`
   stamps them; the payout code no longer does this for you.
8. **Run-scoped composite check** at `recordResult` (3 stars + 3 pickups same run) →
   `skill_spotless`.
9. **Fall hook on tutorial levels** (fell-overlay path; `consumeLife` never fires ≤L10) →
   `whimsy_gravity_check`.
10. **Wall-clock check** in `addZenSeconds` → `whimsy_night_bloom`.
11. **Pinball ROLL lanes — must be BUILT, then instrumented** → `whimsy_roll_call`. The
    shipped table has no rollover lanes (PinballView's only scorers are 3 pop bumpers and
    2 slingshots); the SpriteKit rebuild itself has landed, but the ROLL lanes are a
    still-unbuilt pinball-roadmap item. This trophy is blocked on that work — an external
    blocker the sprint plan must list — and only then needs the lanes-complete-per-ball
    event routed to GameState.
12. **Reroute Disco + Roll Out best-writing through GameState** (both write `minigameBests`
    directly in-view today) so their trophies share the central hook → 4 trophies.
13. **Coin Pit round stake-count hook** at round start → `whimsy_high_roller`.
14. **Social latches/counters** (client-side): sign-in success, accepted-friend count
    high-water, lifetime lives-sent (friend + clan), clan join/create, clan fulfill →
    all 7 Social trophies.
15. **CotD consecutive-date derivation helper** over the existing completions date set (no
    new storage) → `daily_week_streak`.
16. **Threshold calibration pass** from `minigame_result` telemetry before ship for every
    row marked *calibrate* (paintball 60, koth 45, pinball 10k/50k/150k, rollout 10,
    rollup 100/500, disco 25/hard-10, coinpit 90, and the 10-second speed clear). Plus the
    **price re-derivation pass — now UNBLOCKED and mandatory: the tier reprice MERGED
    2026-07-02 (PR #124)** — for every economy/collection figure against the live catalogue
    (tiers 750/1,000/1,250/1,500, bundle floors 5,500/6,500, canonical ~25 coins/min):
    `econ_nest_egg` 1,000, `econ_working_capital` 5,000, `balls_own_40` (~26k framing →
    ~37–45k live), `pack_first` (cheapest pack 520 → 3,300), and `collection_complete`'s coin
    total / time-to-earn framing — none of these pre-reprice numbers may reach the S4-T6
    freeze unreviewed.
17. **Persistence/sync architecture** (separate design, per internal-data-backend): local
    ledger is source of truth; server sync as idempotent full-snapshot upsert ("all my
    unlocked ids"), per-player rows ON DELETE CASCADE; no reliance on the memory-only
    analytics buffer for unlock delivery.
18. **Daily-start mode marker** — insert `"daily"` into `playedModeIDs` at the daily start
    site (the HomeView daily route, next to the `daily_challenge_started` analytics call, or
    latched inside `startDailyChallenge()`) → `daily_first_start`. The stat exists but
    nothing writes `"daily"` (verified still true at `origin/main` `42d1925`): the daily
    route builds BallGameView without `.firstPlayTutorial`, and `ModeTutorial.for("daily")`
    returns nil so `markModePlayed` would no-op even if it did. Note: the merged CotD
    fast-path (PR #123) emits a NEW analytics event `daily_challenge_level_cleared`
    (`sub_level`, `time`) from BallGameView — fire-and-forget and non-replayable, so it must
    NOT become a trigger source; daily trophies stay keyed to
    `completeTodaysDailyChallenge`/`dailyChallengeCompletions` (unchanged). That fast-path
    block is, however, the natural view-layer hook site if a per-sub-level daily trophy is
    ever added.

**View-layer hooks (sprint ownership):** items 9, 12, and 13 need edits outside
`GameState.swift` — BallGameView's fell-overlay path, the Disco/RollOut views, and the Coin
Pit stake overlay (also in BallGameView) — and item 11 will too once the ROLL lanes exist
(PinballScene). The sprint plan now owns them: S1-T7 (BallGameView/PinballView event hooks,
with `whimsy_roll_call` carved out of the S1 gates pending open question 9), S1-T4 (the
Disco/RollOut reroute), and matching file-ownership-map exceptions. Item 18 needs no view
edit — sprint S1-T2 latches `"daily"` inside `startDailyChallenge()` (the GameState-funnel
option above), so HomeView stays untouched by S1.

**Deliberately absent (do not add later without re-reading the research):** IAP/purchase
trophies, ads-watched, out-of-lives/failure counts, coins-spent totals, seasonal-window
trophies, shop-rotation-checking trophies, friend-count extremes, anything keyed to a
specific level layout, and coin payouts on any trophy.

**Badge-wall migration:** the 11 ProfileView badges map into this catalog — first_steps→
`climb_first_clear`, legend(50)→`climb_level_50` (**boundary off-by-one:** badge at
`highestUnlocked` ≥ 50, trophy at ≥ 51 — a veteran at exactly 50 does not auto-earn it; see
the row note), star_collector→`climb_stars_25` (retuned),
stellar→`climb_stars_150`, on_a_roll→`daily_login_7`, dedicated→`daily_login_30`,
coin_hoarder→`climb_pickups_100`, completionist→`bundle_first`, bundle_hunter→`bundle_5`
(retuned), hat_trick→superseded by `skill_spotless`/`skill_first_try`, and **unlimited
("Unlimited Power") is dropped** — a $19.99 purchase is not an achievement (principle 3).
Retro-evaluation at first launch grandfathers everything the player's live stats already earn.
Add a per-badge boundary-parity row to the S0-T4 migration fixtures so all 11 mappings are
audited at their exact threshold values — the legend(50) off-by-one above was caught by hand,
not by a fixture.

## 7. Rarity pyramid sanity check

| Predicted band | Count | Share | What lives here |
|---|---|---|---|
| common (≥50%) | 3 | 3% | First clear, level 10, first bundle — guaranteed early toasts |
| uncommon (15–49%) | 31 | 35% | Discovery map + first wins + early ladders — the week-one texture |
| rare (5–14%) | 22 | 25% | Mid-game: world 1 done, 10-win counters, mode chases |
| very-rare (1–4.9%) | 29 | 33% | Golds, PB thresholds, deep counters, social, most secrets |
| ultra-rare (<1%) | 4 | 4% | Exactly the 3 Diamond trophies + the capstone — the brag wall |

Checks:

- **Day-one achievable:** yes — `climb_first_clear`, `climb_level_10`, `bundle_first`,
  `arcade_sampler`, `arcade_first_win`, `whimsy_gravity_check`, `skill_first_try`,
  `cosmetic_first_buy` are all reachable in session one.
- **Months-long chases:** yes — `daily_clears_50` (≥50 calendar days by construction),
  `climb_level_1000`, `balls_own_40`, `arcade_wins_100`, plus all three Diamond trophies.
- **Ultra-rares (internal band):** exactly 4 sub-1% trophies (spec asks 2–4), and by design
  they are precisely the three Diamond trophies + capstone — a clean story: "the only sub-1%
  trophies are the monuments." **Display caveat:** under design.md §3's adopted PSN labels (Ultra
  Rare = <5%), 33 of 89 trophies (the 29 very-rare + these 4) would all render "Ultra Rare" —
  the monuments story holds at display time only if Mac adopts this catalog's finer bands
  (see the OPEN note in §3's column key, open question 8).
- **Shape caveat:** the very-rare band (33%) is fatter than a console list because the
  denominator is *every install that ever launched* — mobile funnels push deep-funnel
  trophies rarer than their console-equivalent effort would suggest. Tier ≠ rarity: tiers
  encode intended effort, rarity is emergent and will be recalibrated from live telemetry.
- **Denominator + display:** rarity denominator decision and the anon-readable
  `trophy_stats` aggregate are backend work (internal-data-backend §5/§8). Player-facing
  percentages stay suppressed until a minimum earner population exists; tier labels can show
  from day one.

## Open questions for Mac

1. Tier ladder + capstone naming: this catalog's **Legend + Roll of Honor** — which revised
   design.md now recommends adopting (decisions #2 + #14; its original recommendation was a
   **Summit** tier + literal **Platinum** capstone, and R3's case against a flavored name is
   preserved there for the record). If Mac overrules toward Summit, the `climb_summit`
   trophy needs renaming (e.g. "World Fifty"). Capstone gating rides the same ruling:
   design.md §9 now matches this catalog (73 visible B/S/G; Legends and Social quarantined
   off the path) pending #14. If the flavored capstone survives: **Roll of Honor** vs The
   Grand Summit vs Marble Monument.
   → **RULED 2026-07-02:** rung 4 = **Diamond** (design.md §2 R2 — Legend and Summit both
   passed over; disambiguation riders active), capstone display name = **Platinum** (the
   flavored-capstone sub-question fell away; "Roll of Honor" survives only as an optional
   future Trophy Room screen-name idea). `climb_summit` keeps "The Summit" — no rename
   needed. Capstone gating confirmed at the 73 visible B/S/G (#14).
2. Earned-regalia cosmetics for capstone/legends (3–5 items max, Trophy-ball gating): yes/no.
   → **RULED 2026-07-02: yes** (P2, design.md §11 #3) — earned-only regalia; trophies never
   mint coins. Rider: no regalia references the Diamond ball.
3. `econ_nest_egg` borderline flag (IAP-shortcuttable coin-balance trophy): keep or cut.
4. Social category confirmed off-capstone-path (recommended), or required for capstone.
   → **RULED 2026-07-02 (via #14):** confirmed off-capstone-path — the adopted capstone
   scope is the 73 visible B/S/G.
5. PB thresholds marked *calibrate*: sign off after the telemetry pass, pre-ship — plus the
   economy/collection figures re-derived against the merged tier reprice (PR #124, shipped
   2026-07-02; §6 item 16 is unblocked and mandatory).
6. Game Center mirror (Option C in platform-comparison) is Phase 2 — ids here are GC-legal
   and stable so nothing blocks it; point weights deferred to that decision. The mirror is a
   curated canon subset (design.md §8) — decide roughly how many of the 100 slots it spends.
7. Catalog size: 89 here vs design.md's original ~40–55 sketch — its appendix now records 89
   as the superseding scope and decision #14 recommends blessing it; §8's Game Center
   rationing still binds (the GC mirror stays a curated subset, see principle 13). If Mac
   cuts instead, the 16 per-game first-win/10-win bronzes are the obvious compression target.
   → **RULED 2026-07-02: 89 adopted as v1 scope** (design.md §11 #14); no compression.
8. Rarity bands for display: design.md §3's PSN labels (under which 33 of 89 show
   "Ultra Rare") vs this catalog's finer 5-band scheme — see the OPEN note in §3.
9. `whimsy_roll_call`: hold back until the pinball rebuild ships the ROLL lanes (post-launch
   additive), or substitute a v1 whimsy silver keyed to the shipped table.
10. `collection_complete`: confirm the 7 seasonal bundle-exclusive balls stay excluded
    (evergreen-only 207-item set, per principle 9), or make the seasonal windows recurring
    and require all 214.
11. Hidden-trophy count: ratify 5 (raise design.md P9 to match) or cut to 0–2 by making the
    least spoiler-y whimsies visible.
    → **RULED 2026-07-02: ratified at 5** (via #14; design.md P9 carries the ratified note).
