# Trophy Engine Research — Internal Feature Inventory

**Date:** 2026-07-02
**Scope:** Everything player-facing in `RollAlong/` a trophy/achievement engine could hook into. All refs are `file:line` against the current HEAD (064f3cd). Line numbers drift with edits — anchor on the named symbols.

> **POST-AUDIT UPDATE (2026-07-02, main @ `42d1925`).** 36 commits merged the
> same day as this audit (PRs #113/#114/#118–#120/#122–#124; authority:
> `repo-delta-2026-07-02.md`). What moved for THIS doc:
> (1) Minigame difficulty payout multipliers are now **×1/×1.5/×2** (§1.4; was
> ×0.5/×1/×2 — MERGED #118; Easy is deliberately the per-attempt EV-optimal
> pick), plus payout equity buffs (Sumo 6×, Marble Cup floor, Pinball 2× coin
> rate, Roll Out rescue).
> (2) Cosmetic tier prices repriced to **750/1,000/1,250/1,500**; bundle
> `fullPrice` now runs 4,500–13,500 with rarity floors **5,500/6,500** (§4;
> MERGED #124).
> (3) Climb pays tier-scaled **2/3/4 on EVERY clear** via new
> `GameState.clearCoins(for:)` (:1060) — BallGameView no longer computes
> `isFirstClear`; a "first clear" check must derive `time(for:) == nil`
> BEFORE `recordResult` runs.
> (4) CotD gained a `.oneShot` fast-path (MERGED #123): clears return before
> `recordResult`/all climb record-keeping, guarded by new
> `ProgressionKind.recordsClimbResult`/`.banksPickupCoins` (GameMode.swift —
> only `.mainClimb` is true for either), and emit the analytics-only event
> `daily_challenge_level_cleared` (never a trophy trigger source).
> (5) New GameState funnels/keys: `purchaseBundle(_:price:)` (:1589 — bundle
> buys moved out of CosmeticShopView, PR #120), `sellBackValue` (:685) + the
> persisted `ra_paidPrices` ledger (Sell Back now refunds min(cost/2, paid));
> `grantBundleFree` mints refund-shaped compensation through `addCoins`
> (PR #114: Starter Pack restore → full 6-item Aurora collection).
> (6) GameState line refs drifted +11 to +65 — delta doc §2 has the
> symbol→line map. HomeView/ProfileView/LevelSelectView/GameMenuView refs
> below are unchanged; StoreKitManager was heavily rewritten (relocate by
> symbol).
> Tip drift: `origin/main` later moved `42d1925` → `fb98819` (one commit — the
> IAP launch-race fix merged; StoreKitManager + tests only, nothing here changes).

---

## 1. Game modes & progression

The whole game is one registry: `GameModeCatalogue.registry` (GameMode.swift:604-632) — every mode below is currently `isEnabled: true`. Mode ids are stable analytics keys / routes / test anchors and MUST be used as trophy keys.

### 1.1 Main climb ("Adventure", id `climb`)
- Endless, strictly sequential unlock: `highestUnlocked` gates level N+1 (GameState.swift:115-117, `isUnlocked` :778). No skipping.
- Procedural + deterministic per level number (LevelLayout.swift:4-11); first 100 levels are handcrafted overrides in `LevelOverrides.json` (`levels` keys "1"…"100"); `LevelLayout.layout(for:)` (LevelLayout.swift:196).
- **Worlds**: 50 named chapters × 100 levels = 5,000 named levels (`World`, LevelLayout.swift:46-89, `World.maxLevel` = 5000). World names ("Meadowgate" … "The Summit") are ready-made trophy theming.
- Difficulty tier by last digit of level (easy/hard/veryHard — LevelLayout.swift:114-122).
- Per-level scoring: 1-3 stars by time vs `goldTime`/`targetTime` (`computeStars`, BallGameView.swift:5685-5689); up to 3 pickup coins per level.
- Lives: fall costs a life (`consumeLife`, GameState.swift:944); tutorial L1-10 exempt (GameState.swift:130, :786); regen 1 per 6 min, cap 10 (GameState.swift:128-129); `unlimitedLives` subscription flag (GameState.swift:144).

### 1.2 Challenge of the Day (id `daily`)
- Deterministic per calendar date: 1-3 brutal levels, title from a pool, flat 30-coin reward (`DailyChallenge.current`, GameMode.swift:508-528).
- One shot per day: 3 free attempts per sub-level (GameState.swift:376-378); quitting mid-run forfeits the day (`forfeitDailyChallengeIfRunning`, GameState.swift:839; called HomeView.swift:402).
- Persisted outcomes: `dailyChallengeCompletions` / `dailyChallengeFailures` — **sets of "YYYY-MM-DD" strings** (GameState.swift:360-368), i.e. full completion history is already on disk (streaks/`N total` trophies derivable).

### 1.3 Challenge Tracks (Packs) — 8 tracks, id `challenge.<trackID>`
- 100-level themed side quests; clearing level 100 grants the paired cosmetic bundle free (`ChallengeTrackMode.rewardBundleID`, GameMode.swift:234-248; delivery `deliverTrackReward`, GameState.swift:1392).
- Track ids: `frozen-peaks`, `deep-cosmos`, `inferno-run`, `neon-arcade`, `haunted-manor`, `ancient-temple`, `abyssal-depths`, `golden-gauntlet` (GameMode.swift:551-600). `golden-gauntlet` is UI-locked until 3 tracks completed (ChallengeTrackSelectView.swift:59-61).
- 6-phase difficulty arc per track (GameMode.swift:190-196; docs/challenge-tracks-roadmap.md).
- Progress: `trackProgress[trackID]` high-water + `completedTracks` set (§2).

### 1.4 Minigames (all live)
| Mode id | Display | Win condition | Score unit (what `minigameBests` stores) |
|---|---|---|---|
| `snake` | Comet Clash | last comet alive | power (SnakeGameView.swift:497) |
| `sumo` | Sumo Survival | rank #1 of roster | points/knockouts (SumoSurvivalView.swift:625) |
| `paintball` | Paint Ball | most floor coverage in 60s | coverage % (PaintBallView.swift:588) |
| `goldrush` | Smash and Grab | most coins in 60s | coins collected (GoldRushView.swift:568-573) |
| `marblecup` | Marble Cup | most goals in 90s vs AI keeper | goals (MarbleCupView.swift:674) |
| `koth` | King of the Hill | most hold-time in 60s | hold seconds (KingOfTheHillView.swift:481) |
| `pinball` | Pinball | score attack, 3 balls | flat `pinballBest` (PinballView.swift:150) |
| `rollout` | Roll Out | reach maze goal (costs lives) | furthest maze, `minigameBests["rollout"]` (RollOutView.swift:590) |
| `rollup` | Roll Up | climb high (run costs a life) | height m `minigameBests["rollup"]` + `rollupBestSeconds` (RollUpView.swift:549) |
| `disco` | Disco Ball | max crossings, 3 difficulties | `minigameBests["disco"/"discoeasy"/"discohard"]` (DiscoBallView.swift:111-120, :692) |
| `zen` | Zen Garden | endless, no goal | cumulative `zenSeconds` (BallGameView.swift:856) |
| `coinpit` | "Gold Rush" 30s reward run | catch up to 100 falling coins | `goldrushBest` / `goldrushCoinsTotal` (BallGameView.swift:5539) |

- **Difficulty knobs** (the six competitive modes only): `MinigameDifficulty` easy/normal/hard (GameState.swift:1627-1715) — AI accel/speed scales, aim error, hesitation; payout ×1/×1.5/×2 (MERGED #118 — was ×0.5/×1/×2; Easy is deliberately the per-attempt EV-optimal pick); design target win-rates 0.80/0.45/0.22. Shared `MinigameAI` humanizer (GameState.swift:1725-1753).
- **Tickets**: 1 per competitive win (`recordCompetitiveWin`, GameState.swift:1260 at main); staked to buy `coinpit` rounds — stake **unlimited** (the "(max 10)" this audit originally cited was a stale code comment, wrong even at 064f3cd; internal-economy.md documents the truth and the comment is fixed on main).
- **Pinball status**: full SpriteKit rebuild v1 committed, live in catalogue; feel-tuning ongoing (docs/pinball-roadmap.md:1-25). Scoring already wired to `recordPinballScore`; coins = score/250 (PinballView.swift:149).
- **Maps**: curated map cycling per game in `MinigameMaps.swift` (docs/minigame-maps-roadmap.md); map name is in round-over analytics (e.g. SnakeGameView.swift:512).
- First-play tutorial per mode gated by `playedModeIDs` (GameMode.swift:814-841).

---

## 2. Existing player stats/counters (THE trigger substrate)

All local persistence is **UserDefaults `ra_*` keys, no iCloud sync** (audit comment GameState.swift:4-27). Everything below is `@Published` on `GameState` (ObservableObject) — a trophy engine can observe or be called from the same mutation funnels (§3).

### 2.1 Climb / core
| Property (type) | Key | Ref |
|---|---|---|
| `currentLevel: Int` | ra_level | GameState.swift:32 |
| `highestUnlocked: Int` | ra_highestUnlocked | GameState.swift:115 |
| `bestStars: [Int: Int]` (per level, 0-3, only increases) | ra_bestStars | GameState.swift:106 |
| `bestTime: [Int: TimeInterval]` (only decreases) | ra_bestTime | GameState.swift:109 |
| `collectedCoins: [Int: Set<Int>]` (banked pickup indices) | ra_collectedCoins | GameState.swift:112 |
| `totalStars` / `totalCoins` (computed sums) | — | GameState.swift:779-780 |
| `lives`, `lastLifeLostAt`, `unlimitedLives` | ra_lives etc. | GameState.swift:132-146 |

### 2.2 Economy
| Property | Key | Ref |
|---|---|---|
| `coinBalance: Int` (cap 999,999) | ra_coinBalance | GameState.swift:207, cap :1027 |
| `tickets: Int` (cap 999) | ra_tickets | GameState.swift:248, cap :1190 |
| `goldrushCoinsTotal: Int` — lifetime coins caught in coinpit runs | ra_goldrushCoinsTotal | GameState.swift:241 |
| `dailyStreak: Int` (**resets to 1** on the first claim after a missed day — `claimDailyReward` sets it to `liveStreak + 1`, and `liveStreak` is 0 once a day is skipped; a trophy engine wanting a lifetime-max streak must latch its own high-water at claim time) + `lastDailyClaim` | ra_dailyStreak | GameState.swift:155-166, :1306-1343 |
| `starterPackClaimed: Bool` (legacy IAP) | ra_starterPackClaimed | GameState.swift:184 |

- **Retro-backfill caveat:** historical streak maxima are unrecoverable from disk — after a break, only the small current `dailyStreak` survives. A retroactive grant of streak trophies (e.g. daily-login 7/30) that reads `dailyStreak` can only honor the streak the player is holding *right now*; veterans whose long streaks once broke will be under-granted. The live high-water latch (above) is the only forward-looking fix.

### 2.3 Minigame records
| Property | Key | Ref |
|---|---|---|
| `pinballBest: Int` | ra_pinballBest | GameState.swift:223 |
| `zenSeconds: Int` (cumulative) | ra_zenSeconds | GameState.swift:226 |
| `goldrushBest: Int` (best coinpit haul) | ra_goldrushBest | GameState.swift:229 |
| `rollupBestSeconds: Int` (+ `rollupBest` computed) | ra_rollupBestSeconds | GameState.swift:234-238 |
| `minigameWins: [String: Int]` lifetime wins per mode id | ra_minigameWins | GameState.swift:312 |
| `minigameBests: [String: Int]` PB per mode id (also `rollout`, `rollup`, `disco*`) | ra_minigameBests | GameState.swift:321 |
| `minigameDifficultyPlays/Wins/Bests: [String: Int]` keyed `"modeID\|difficulty"` — **per-mode attempt counts exist here** | ra_minigameDiff* | GameState.swift:329-341 |
| `minigameSuccessRate(_:_:)` derived win-rate | — | GameState.swift:1264 |

### 2.4 Modes / tracks / daily
| Property | Key | Ref |
|---|---|---|
| `trackProgress: [String: Int]` (1-100 high-water per track) | ra_trackProgress | GameState.swift:306 |
| `completedTracks: Set<String>` | ra_completedTracks | GameState.swift:345 |
| `playedModeIDs: Set<String>` (modes launched ≥1×) | ra_playedModeIDs | GameState.swift:350 |
| `currentModeID: String` (last armed mode) | ra_currentModeID | GameState.swift:356 |
| `dailyChallengeCompletions/Failures: Set<String>` date keys | ra_dailyChallengeDone/Failed | GameState.swift:360-368 |

### 2.5 Cosmetics ownership
`ownedBallSkins/Goals/Trails/Floors/Pits/Boundaries/Music/Bundles/Packs: Set<String>` + `freeGrantedItems` (GameState.swift:255-296); equipped slots (GameState.swift:434-472); `completedBundleIDs` computed completionism (GameState.swift:1426-1440); `isOwned`/`grant` (GameState.swift:1444-1471).

### 2.6 Server mirror (Supabase `players` row)
`PlayerProfile` (SocialClient.swift:613-742): climb_level, highest_unlocked, total_stars, lives, coins_collected, pinball_best, zen_seconds, goldrush_best+wins, snake/sumo/paintball/marblecup/koth best+wins, rollup_best(+seconds), needs_lives_at. Pushed by `syncProgress` (SocialClient.swift:125, fed by GameState.swift:634-648) and `syncMinigameStats` (GameState.swift:1088). Per-difficulty rows in `minigame_scores` via `syncMinigameScore` (SocialClient.swift:206; called GameState.swift:1241).

### 2.7 NOT currently tracked (trophies needing new instrumentation)
- Lifetime falls/deaths, lifetime climb attempts, total sessions/play time (only Zen time is summed).
- Lifetime coins **earned** (only balance, per-level pickup sets, and goldrushCoinsTotal exist); coins spent.
- Per-mode play counts for solo modes (`minigameDifficultyPlays` covers only the 6 competitive modes).
- Consecutive no-fall level streaks, one-life clears, speedrun aggregates.
- IAP purchase counts, rewarded-ads watched, results shared, friends/clan-mates counts locally, lives gifted/received totals.
- **Caution:** several existing stats can regress — `resetProgress()` wipes stars/times (GameState.swift:652), `liquidateCoinCosmetics()` shrinks ownership (GameState.swift:685), `liveStreak` drops to 0 on a missed day. Trophy state must be latched separately, not recomputed from these.

---

## 3. Event/hook points (where triggers fire today)

### Level & progression
- **Climb level cleared** — single funnel in BallGameView goal handler: `recordResult` (BallGameView.swift:5651; impl GameState.swift:734), coin award :5657, analytics `level_complete` :5661, 3-star review prompt :5678. Advancement: `advanceFromLevelClear` (BallGameView.swift:4886) → `gameState.advanceLevel()` :4915/:4923/:4955 (impl GameState.swift:620 → server sync :634).
- **Track level cleared** — fast-path BallGameView.swift:5576-5605 (`track_level_cleared`, `track_completed` :5595); `advanceTrackLevel` (BallGameView.swift:4901 → GameState.swift:425) → `advanceTrackProgress` (GameState.swift:1379) → **bundle granted** `deliverTrackReward` (GameState.swift:1392).
- **Daily challenge** — started HomeView.swift:466 (`daily_challenge_started`); completed BallGameView.swift:4891 → `completeTodaysDailyChallenge` (GameState.swift:871); failed `failTodaysDailyChallenge` (GameState.swift:865); attempt spent `recordDailyAttemptFailure` (GameState.swift:859).
- **Life lost** — `consumeLife` call sites: BallGameView.swift:5478 (climb fall), RollOutView.swift:608, RollUpView.swift:553; impl GameState.swift:944.

### Minigame results
- **One funnel for the 6 competitive modes**: `recordMinigameResult(modeID:difficulty:won:score:basePayout:)` (GameState.swift:1223) — bumps plays/wins/bests, pays coins, fires `minigame_result` analytics (:1248), and on win calls `recordCompetitiveWin` (:1205 — wins+1, +1 ticket, server sync). Call sites: SnakeGameView.swift:500, SumoSurvivalView.swift:627, PaintBallView.swift:590, MarbleCupView.swift:676, KingOfTheHillView.swift:483, GoldRushView.swift:568.
- PBs: `recordCompetitiveScore` (GameState.swift:1116); `recordPinballScore` (GameState.swift:1126; PinballView.swift:150); `recordGoldRushCoins` (GameState.swift:1136; BallGameView.swift:5539); `recordRollUpRun` (GameState.swift:1151; RollUpView.swift:549); `addZenSeconds` (GameState.swift:1167; BallGameView.swift:856). Disco and RollOut write `minigameBests` directly (DiscoBallView.swift:692-694, RollOutView.swift:590-591) — no funnel; a trophy engine must hook these two views or centralize them.
- **Mode first played**: `markModePlayed` (GameMode.swift:827; GameState.swift:792).

### Cosmetics & economy
- **Coin-shop purchase**: `GameState.purchase(item)` (GameState.swift:1557 at main; UI CosmeticShopView.swift:855); pack `purchasePack` (GameState.swift:1619); bundle buys now funnel through `GameState.purchaseBundle(_:price:)` (:1589 — MERGED #120, moved out of CosmeticShopView; the view keeps the collection-complete toast, CosmeticShopView.swift:166). All three record `ra_paidPrices` shares for Sell Back.
- **Any cosmetic acquisition** funnels through `grant(_:)` (GameState.swift:1460) — the single choke point for "cosmetic acquired" trophies.
- **Free grants**: tutorial bundle `grantBundleFree` (GameState.swift:1405; BallGameView.swift:4940), track rewards (above), IAP exclusives (below).
- **Coins awarded**: everything goes through `addCoins` (GameState.swift:1088 at main) / `spendCoins` (:1229) — ideal for "lifetime coins earned" instrumentation; note the refund-shaped callers a play-earned counter must exclude: Sell Back refunds and `grantBundleFree` compensation (post-#114/#120), plus IAP grants.
- **Daily reward claim**: `claimDailyReward` (GameState.swift:1334; DailyRewardView.swift:175).

### IAP (StoreKit 2)
- Products: 3 lives packs, `unlimited`, 5 coin packs (`rewardCoins` re-anchored to **750→60,000** by MERGED #124; product ids keep historical "coins.100"-style names), legacy `starterPack` (StoreKitManager.swift:36-50).
- Purchase → `iap_purchased` analytics → `deliverReward`: lives grant, coins, **the top ($49.99) pack drops one random Money cosmetic** (`grantRandomMoneyCosmetic`), **unlimited grants Diamond ball**, and — MERGED PR #114 — the starter pack now grants the **full 6-item Aurora collection** via `StoreKitManager.grantAuroraCollection` → `grantBundleFree` (compensating already-coin-bought items at `sellBackValue` through `addCoins`). `deliveryCount` published for UI. Restore: `iap_restored`. (064f3cd line refs dropped — the file was heavily rewritten on main; locate by symbol.)

### Social
- **Clan created/joined/left**: SocialClient.swift:470/:491/:501 (UI: ClansView.swift:989/:900/:657); disband :510; clan activity events `postClanEvent` :547.
- **Friend request/accept**: SocialClient.swift:383/:394 (UI: FriendsView.swift:605, PublicProfileView.swift:182-193).
- **Life gifts**: `sendLife` :314, `claimGift` :332; ask-for-lives :520.
- **Sign-in**: AppleAuthManager → `SocialClient.setSession` (SocialClient.swift:45).

### Analytics event names already emitted (Supabase `events` table, AnalyticsClient.swift:1-40)
`level_complete`, `track_level_cleared`, `track_completed`, `daily_challenge_started/completed`, `minigame_entered`, `minigame_result`, `*_round_over`/`*_match_over` per game, `ticket_earned`, `iap_purchased/restored`, `tutorial_bundle_claimed`, `result_shared`, `goldrush_double_bought`, `app_resume`, etc. Trophy triggers should co-locate with these call sites, not with the analytics layer (analytics is fire-and-forget, anonymous, non-replayable).

---

## 4. Cosmetics system shape

- **7 slots** conforming to `CosmeticItem` (Cosmetics.swift:18): Ball (`BallSkin`, 74 cases, BallSkin.swift), Goal (33), Trail (20), Floor (30), Pit (29), Boundary (13), Music (19) (enums Cosmetics.swift:278/826/942/1108/1254/1352).
- **Rarity tiers** (`CosmeticTier`, Cosmetics.swift:120-140): starter (free) / standard **750** / rare **1,000** / premium **1,250** ("Epic") / exclusive **1,500** ("Legendary") — repriced by MERGED #124 (was 50/100/200/500 at 064f3cd). Price = tier, no per-item overrides.
- **Bundles**: 66 in `CosmeticBundle.catalogue` (Cosmetics.swift:1834), incl. ~17 seasonal/limited-time windows (`availableFrom/Until` :1683-1697). `BundleRarity` bands standard/rare/legendary by `fullPrice` — post-#124 the catalogue runs 4,500–13,500 against floors **5,500/6,500** (split 6/20/40; was 450-1950 vs 700/1,100).
- **Ball Packs**: 3 (`planets`, `sports-balls`, `glass-marbles`, Cosmetics.swift:2757); equipping a pack shuffles the ball per attempt (GameState.swift:1524).
- **Gated exclusives** ("iconic", survive liquidation — BallSkin.swift/Cosmetics.swift:105): **Diamond** ball (unlimited-lives IAP, StoreKitManager.swift:388), **Money trio** (moneyBall/moneyRoll/moneyFull — hidden 10,000-coin-IAP random drop, StoreKitManager.swift:413-421; never in shop/rotation, Cosmetics.swift:256-257/:905/:1080), **Trophy** ball (champion-bundle exclusive = golden-gauntlet reward, Cosmetics.swift:2536), **Aurora** (legacy starter-pack grant + aurora coin bundle).
- **Shop rotation** (`ShopRotation`, Cosmetics.swift:1498-1619): deterministic 1-hour windows; featured bundle + loot-weighted discount (`BundleDiscount` :1444); 3 featured items per category (2 standard + 1 higher); `isFeatured` :1607.
- **Sell-back**: `liquidateCoinCosmetics` refunds sellables, keeps iconic + free-granted (GameState.swift:665-718).
- **Completionism**: `completedBundleIDs` (GameState.swift:1426) — powers a home aura ring + shop toast; obvious trophy fodder.

---

## 5. Social surface

- **Backend: custom Supabase** (project `mhwpcwauzvmtmuphtajs`), REST via `SocialClient` (SocialClient.swift:31-55) with Sign-in-with-Apple session. **No GameKit / Game Center anywhere** — zero hits in source and project file (verified 2026-07-02). Trophies will be fully custom.
- **Own profile** (ProfileView.swift): hero (ball + LVL marker + name + ShareLink :64-131), Career Stats card (stars bar, perfect-levels bar, Max Level / Streak / Coins Found / Bundles cells :268-309), **Badges card** (:476), Loadout showcase + diorama (:142), PlayerRanksCard global ranks (:626-761).
- **Public profiles** (PublicProfileView.swift:1-9): remote `PlayerProfile` only — explicitly notes local-only loadout/badges "aren't synced". Reached from Friends/clan rosters/`rollalong://player/<id>` deep links; supports add-friend + send-life.
- **Leaderboards** (LeaderboardView.swift): 10 boards (`LeaderboardBoard`, SocialClient.swift:766-768) grouped Adventure/Solo/Competitive (:755); climb board orders `climb_level desc, total_stars desc` (:813); competitive boards rank wins-then-best (:819-824); per-difficulty filter backed by `minigame_scores`; Roll Up height/time dual sort (LeaderboardView.swift:37-40). Rank lookups: `fetchAllRanks` / `fetchMinigameDifficultyRanks` (SocialClient.swift:267/:290).
- **Friends** (FriendsView.swift:1-30): gift inbox (claim lives), requests, friends list (send a life), player search. Tables `friendships`/`life_gifts`.
- **Clans** (ClansView.swift:1-19): lives-sharing community — ask-for-a-life, send-to-members, fulfill; activity feed (`clan_events`); create/join/leave/disband; browse+search; clan deep links.

---

## 6. UI surfaces where trophies could live

1. **ProfileView Badges card** — the natural home. There is already an 11-badge proto-achievement wall: `BadgeDef` + `allBadges` (ProfileView.swift:388-474; render :476-545). Current badges: first_steps, hat_trick, star_collector (50★), stellar (150★), on_a_roll (7-day), dedicated (30-day), coin_hoarder (100 found), completionist (1 bundle), bundle_hunter (3 bundles), unlimited (IAP), legend (level 50). **Limitations to fix**: view-private, computed live from GameState (can silently un-earn after resets/liquidation), no persistence, no unlock timestamps, no toast/celebration, not synced, not visible on PublicProfileView.
2. **Home screen** (HomeView.swift): nav grid rows :319-330 (a Trophies tile could join Leaderboard/Shop/…); persistent pills coin/lives/daily-reward :337-343; sign-in-gated routing pattern :321.
3. **Post-game overlays** — climb `winOverlay` (BallGameView.swift:4097; phase wiring :754), fell/out-of-lives overlays :753/:768, each minigame's result overlay (e.g. SnakeGameView finish path), plus `ResultShareCard`/`ResultShareButton` share cards (Cosmetics.swift:3707-3818) — the right spot for "trophy unlocked" moments.
4. **GameMenuView hub** (GameMenuView.swift): CotD banner :186-263, Gold Rush banner :309, shelves — room for a trophies/quests banner.
5. **LevelSelectView**: per-level stars/coins grid + world headers — natural per-world completion display.
6. **ChallengeTrackSelectView**: progress rings + DONE seals (:132-150) — per-track trophy mirrors.
7. **Settings** (SettingsView.swift) — low-priority link slot; **DailyRewardView** streak ladder sheet — streak-trophy adjacency.
8. Existing celebration patterns to reuse: shop collection-complete toast (CosmeticShopView.swift:166/:1786), IAP `DeliveryReceipt`/`deliveryCount` celebration (StoreKitManager.swift:98-104), first-play `ModeTutorialOverlay` (GameMode.swift:732).

---

## 7. Implementation notes for the trophy engine

- `GameState` is the single mutation funnel for nearly everything; the cleanest integration is trophy checks inside (or observing) `recordResult`, `advanceLevel`, `advanceTrackProgress`, `recordMinigameResult`, `recordCompetitiveWin`, record-PB functions, `grant`, `addCoins`, `claimDailyReward`, `completeTodaysDailyChallenge`, and StoreKit `deliverReward`. Disco/RollOut write bests directly in-view and would need routing through GameState first.
- Persist trophy unlocks as their own latched `ra_` store (sets + timestamps), never recomputed from live stats (see regression caveats §2.7). Follow the string-set persistence helpers (GameState.swift:1540-1613).
- Server sync, if wanted on public profiles, needs a new Supabase table/columns — `players` + `minigame_scores` are the only stat tables today (docs/social-schema.sql, social-schema-v2.sql).
- New Swift files need 4 manual `project.pbxproj` entries (explicit file refs, no synchronized groups).
- Mode ids (`climb`, `daily`, `challenge.<trackID>`, `zen`, `coinpit`, `snake`, `sumo`, `paintball`, `goldrush`, `marblecup`, `koth`, `pinball`, `rollout`, `rollup`, `disco`) and track/bundle/cosmetic rawValues are the stable vocabulary for trophy definitions.
