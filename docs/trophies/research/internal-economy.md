# Internal Economy & Monetization Audit — input for trophy-system design

Date: 2026-07-02 · Audited at HEAD `064f3cd` (main + IAP launch-race fix).
All file:line refs are to that revision.

> **POST-AUDIT UPDATE (2026-07-02, main @ `42d1925`) — supersedes the original
> merge-state caveat that stood here.** Nearly everything that block listed as
> unmerged MERGED the same day (authority: `repo-delta-2026-07-02.md`): #113
> (docs/economy/ briefing), #118 (calibration-1: sell-back →
> `min(coinCost/2, paidPrice)`, difficulty 1×/1.5×/2×, climb replay parity +
> tier-scaled clear payouts via `clearCoins(for:)`, minigame equity buffs),
> #119 (track-coin masking fix), #120 (`ra_paidPrices` ledger +
> `purchaseBundle` funnel), #114 (Starter Pack → full Aurora collection),
> #122 (clan chat/settings), #123 (CotD `.oneShot` fast-path), and **#124 —
> the tier reprice itself: 750/1,000/1,250/1,500 is LIVE** (bundle floors
> 5,500/6,500, IAP coin packs 750/4,500/10,000/22,500/60,000,
> `maxSingleAward` 60,000, canonical earn rate ~25 coins/min —
> docs/economy/07-decisions.md ruling 2 / 08-reprice.md). Only
> `claude/reserve-lives` remains unmerged from the old list — the IAP
> launch-race fix merged later the same day (`origin/main` `42d1925` →
> `fb98819`; StoreKitManager + tests only). Load-bearing claims below are corrected in place and marked
> "(MERGED …)"; per-mode payout constants and blended rates in §1 remain the
> audit-time pre-calibration values — use docs/economy/07-decisions.md for
> post-calibration rates. GameState line refs drifted +11 to +65; the delta
> doc §2 has the symbol→line map.

---

## 1. Currency map

### Coins (soft currency, the identity economy)

- Balance: `GameState.coinBalance` (GameState.swift:207), no floor below 0,
  hard cap 999,999 (`maxCoinBalance`, GameState.swift:1079). All grants must
  go through `addCoins` (GameState.swift:1088), which clamps any single award
  to `maxSingleAward = 60,000` (GameState.swift:1075; was 10,000 pre-#124) —
  sized exactly to the largest IAP. Spends via `spendCoins` (GameState.swift:1229).
- Distinct metric: `totalCoins` (GameState.swift:813) counts level **pickup**
  coins collected (max 3/level), not the balance. The existing "Coin Hoarder"
  badge checks this, not `coinBalance` (ProfileView.swift:445).

**Sources (earn rates verified at HEAD; pre-calibration constants):**

| Source | Amount | Rate / gate | Ref |
|---|---|---|---|
| Climb clear (MERGED #118: pays on EVERY clear, tier-scaled) | 2/3/4 by difficulty tier + 1/pickup (≤3, pickups stay sticky/once) | repeatable faucet — replay farming is blessed; BallGameView no longer computes `isFirstClear` | `GameState.clearCoins(for:)` GameState.swift:1060 |
| Challenge Track clear | 2 + pickups **every** clear | 12–20/min early-level farm (blessed by ruling 1) | BallGameView.swift:5576-5579 |
| Competitive minigames | base × difficulty — 1×/1.5×/2× (MERGED #118; was 0.5/1/2 — Easy is now deliberately the per-attempt EV-optimal pick), paid win **or** lose | pre-calibration modeled rates (equity buffs merged: Sumo 6×, Marble Cup floor, Pinball 2× coin rate, Roll Out rescue — post-calibration table: docs/economy/07-decisions.md): Paint Ball ~62–124/min (top faucet); KotH ~48–97; Smash&Grab ~40–79; Comet ~29–59; Marble Cup ~17–33; Sumo ~5–10 | GameState.swift:1223-1259; PaintBallView.swift:49; KingOfTheHillView.swift:52-53; GoldRushEngine.swift:45-47; SnakeGameView.swift:54-55; MarbleCupView.swift:54-55; SumoSurvivalView.swift:58 |
| Coin Pit (Gold Rush round) | 1/coin caught × (×2 boost), ~100 dropped/30s ticket | 80–320/min burst, ticket-gated | BallGameView.swift:240, 5532; GameMode.swift:277 |
| Solo modes | Roll Up 0.20/m cap 250 (RollUpView.swift:44-45); Roll Out 4/maze (RollOutView.swift:129); Disco 3/crossing (DiscoBallView.swift:61); Pinball score/250 (PinballView.swift:149); Zen ≤15/session (GameState.swift:1170) | ~5–24/min | — |
| New-personal-best bonus | flat 100 (`minigameBestBonus`) — Pinball, Gold Rush, Roll Up, Disco only | one-time per record | GameState.swift:1054, 1129, 1140 |
| Daily login ladder | [5,8,10,12,15,20,35] = 105/perfect week (nerfed 2026-06-11 from 755/wk) | once/day | GameState.swift:1294, 1334-1342 |
| Challenge of the Day | flat 30 | once/day, 1–3 brutal levels, 3 free tries each | GameMode.swift:525; GameState.swift:871-877 |
| Sell Back | refunds `min(coinCost/2, paidPrices[key] ?? coinCost)` (MERGED #118 + #120's `ra_paidPrices` ledger; the 100%-refund behavior audited at 064f3cd is gone) | Settings danger zone | `sellBackValue` GameState.swift:685; `liquidateCoinCosmetics` :715 |
| IAP coin packs | 750 / 4,500 / 10,000 / 22,500 / 60,000 (re-anchored, MERGED #124; product ids keep historical "coins.100"-style names) | real money | StoreKitManager.swift (`rewardCoins`, relocate by symbol) |

Blended typical rate at the audited revision: **~1,200 coins/hr casual,
~7,200/hr optimized** (docs/economy/01-earning.md). The calibration (now
MERGED) recomputes ~1,900/hr typical after its buffs; the **canonical
planning rate post-merge is ~25 coins/min (~1,500/hr)** — ruling 2,
docs/economy/07-decisions.md.

**Sinks (exactly three, all cosmetics):** single item at `tier.basePrice`
(`purchase`, GameState.swift:1557), bundle at prorated/discounted price via
`purchaseBundle(_:price:)` (GameState.swift:1589 — MERGED #120 moved the
bundle buy out of CosmeticShopView into a GameState funnel), ball pack
(`purchasePack`, GameState.swift:1619). There
is **no coins→lives conversion, no entry fees, no upgrades** — every coin
chases the catalogue. This single-sink structure is the teardown's flagged
weakness (docs/research/01-roll-along-teardown.md §5).

### Lives (energy gate, the friction economy)

- Cap 10 natural (`livesMax`, GameState.swift:128); regen 1 per 6 min
  (GameState.swift:129); purchased lives stockpile **unbounded**
  (GameState.swift:959-970, StoreKitManager.swift:367-376).
- **Consumed by** (`LivesPolicy == .consume`, fall/run above tutorial L10 —
  BallGameView.swift:5472-5479): the main climb, Challenge Tracks
  (GameMode.swift:208), Roll Out per fall (RollOutView.swift:608,
  GameMode.swift:427), Roll Up per run (RollUpView.swift:553,
  GameMode.swift:444). Competitive/solo/Zen/CotD/Coin Pit never consume
  (CotD explicitly grants 3 free attempts per sub-level instead,
  GameState.swift:376-378, GameMode.swift:480).
- **Sources:** regen; rewarded ad +1 (no cap, AdManager.swift:8, 156);
  friend gift +1 each (FriendsView.swift:640, 593); IAP packs 10/60/130;
  Unlimited Lives non-consumable.
- Local notification re-engages at exact restock time
  (GameState.swift:979-995).

### Tickets (skill currency, competitive → Coin Pit converter)

- `GameState.tickets`, cap 999 (GameState.swift:248, 1190). Earned **1 per
  competitive-minigame win** (`recordCompetitiveWin`,
  GameState.swift:1205-1209). Only sink: Coin Pit rounds — 1 ticket = 30 s
  of coin rain (~100 coins dropped per block), stake unlimited, plus a flat
  2-ticket once-per-round ×2 payout boost (back-pays the haul); early quit
  refunds full unplayed 30 s blocks (BallGameView.swift:4377-4378,
  4552, 4585; docs/gold-rush-economy.md).
- Note: the stale comment (retired "coin ticket" multipliers, removed
  10-stake cap) that stood at GameState.swift:1185-1192 was fixed by the
  merged calibration-1 — code and comments now agree: stake unlimited.

### Non-currencies that matter to trophies

Stars (`totalStars`, GameState.swift:779) and per-mode wins/bests
(`minigameWins`/`minigameBests`, GameState.swift:312-341) drive leaderboards
and profile only — no coin value. Completed tracks (`completedTracks`,
GameState.swift:345) and `completedBundleIDs` (GameState.swift:1426-1440)
gate cosmetic rewards and UI flourishes (home aura ring, collection toast).

---

## 2. IAP catalog (10 products, StoreKitManager.swift:35-50; Products.storekit)

| Product | Price | Grants | Notes |
|---|---|---|---|
| lives.pack1 | $0.99 | 10 lives | copy fixed to match grant (PR #111) |
| lives.pack5 | $4.99 | 60 lives | |
| lives.pack10 | $9.99 | 130 lives | stockpiles unbounded; clears regen timer |
| unlimited ("Diamond Balls") | $19.99 | unlimited lives forever + exclusive **Diamond** ball (only source) | entitlement mirrored on every launch; refund revokes lives but never the skin (StoreKitManager.swift:241-246, 541-549) |
| coins.100 | $0.99 | 750 coins (was 100 — re-anchored, MERGED #124; ids keep historical names) | exactly one Standard item; ~30 min of play at ~25/min |
| coins.600 | $4.99 | 4,500 coins (was 600) | |
| coins.1300 | $9.99 | 10,000 coins (was 1,300) | |
| coins.3000 | $19.99 | 22,500 coins (was 3,000) | shares price point with unlimited (deliberate anchor) |
| coins.10000 | $49.99 | 60,000 coins (was 10,000) **+ ONE random unowned "Money" cosmetic** — Money Ball / Money Roll (trail) / Money Full (floor); trio completes across repeat purchases (~$150 all-in); drop gating unchanged by #124 | StoreKitManager.swift (relocate by symbol — file heavily rewritten post-064f3cd) |
| starterpack | $1.99 (retired, restore-only) | historically 500 coins + Aurora ball; **MERGED PR #114:** restore now grants the **full 6-item Aurora bundle** via `StoreKitManager.grantAuroraCollection` → `grantBundleFree`, which compensates any already-coin-bought bundle item at `sellBackValue` **through `addCoins`** (a refund-shaped credit — exclude it from any earned-from-play counter) | Aurora itself is a coin-buyable Legendary |

Delivery on the audited revision is ledger-guarded and refund-proof
(delivered-transaction ledger + revocation skip) — the ledger
(`ra_iapDeliveredTxnIDs`) originally lived on the `claude/fix-iap-launch-race`
branch (064f3cd = main + that branch) and was absent at `42d1925`, but it
**MERGED to `origin/main` at `fb98819`** (2026-07-02, after this audit's
reconciliation) — it is now main behavior. Purchase surfaces:
out-of-lives overlay in-game (BallGameView.swift:3979, 4018), Get Lives /
Get Coins sheets from Home pills (HomeView.swift:164-165, 501), the shop's
coin pill and the **shortfall alert → "Get more coins"** flow
(CosmeticShopView.swift:267-284). Unlimited owners see a celebration instead
of purchasables (PurchaseSheets.swift:37-41). Old research mentions seven
$2.99 seasonal-bundle IAPs — retired; seasonal bundles are now coin-priced
catalogue windows (`availableFrom/Until`, Cosmetics.swift:1679-1717).

---

## 3. Cosmetics pricing

- **Tier ladder — REPRICED, LIVE on main (MERGED #124, 2026-07-02)** (single
  source of truth, `CosmeticTier.basePrice`): starter 0 · standard **750** ·
  rare **1,000** · premium ("Epic") **1,250** · exclusive ("Legendary")
  **1,500** — ruling 2's 30/40/50/60-min time-to-afford targets at ~25
  coins/min (at the audited 064f3cd it was still 50/100/200/500). Shipped
  cascades: bundle rarity floors 700/1,100 → **5,500/6,500** (bundle
  `fullPrice` now runs 4,500–13,500; split Standard 6 / Rare 20 / Legendary
  40), IAP coin packs re-anchored (see §2), sell-back halves exactly (every
  price stays even — test-pinned; prices only ever drift up),
  `maxSingleAward` → 60,000, and a post-tutorial-gift pool fix (6 permanent
  Standard bundles, regression-tested). Trophy coin values (if D1 ever
  allows any) derive against THIS table — see docs/economy/08-reprice.md.
- **Census** (docs/economy/02-spending.md, adversarially recounted
  2026-07-01 — item counts current; coin sums are PRE-reprice): 218 items ≈
  54,550 coins total; **52,550 coin-reachable** (excludes the 4 IAP secrets:
  Diamond, Money Ball, Money Roll, Money Full). Balls are ~48% of catalogue
  value (45 Legendaries). At live #124 prices the same census re-prices to
  roughly 4× — e.g. the 74-ball shelf alone: 13×750 + 15×1,250 + 45×1,500 =
  **96,000**; the full-catalogue re-derivation is trophy-catalog §6 item 16.
- **Bundles**: 66 (`CosmeticBundle.catalogue`, Cosmetics.swift:1834).
  `proratedPrice` charges only unowned items — bundles are curation, not a
  discount (Cosmetics.swift:1773-1781). Bundle rarity derives from
  `fullPrice()` vs floors **5,500/6,500** (MERGED #124; were 700/1,100). ~20 are
  seasonal-windowed. 8 are Challenge-Track rewards, granted free at track
  level 100 (GameMode.swift:234-248; GameState.swift:1392-1399) — incl.
  `champion` with the earned-exclusive **Trophy ball** (Cosmetics.swift:2536-2543,
  BallSkin iconic set Cosmetics.swift:105).
- **Only true discounts**: (a) hourly shop rotation's featured bundle at
  10/15/25/50% off, loot-weighted 50/30/15/5 (expected ~15.75%), floored to
  ×5 (Cosmetics.swift:1444-1478, 1548-1562, 1785-1789); (b) ball packs at
  flat 66% of member sum floored to ×20 — at live #124 prices **Planets
  7,920, Sports 3,300, Vintage Glass 3,780** (were 2,640/520/1,120
  pre-reprice) — not prorated against owned members (Cosmetics.swift:2738-2744).
- **Shop rotation cadence**: 1-hour deterministic windows
  (`ShopRotation.windowSeconds`, Cosmetics.swift:1498-1510): one featured
  bundle + discount, and per-category triples (2 Standard + 1 better,
  Cosmetics.swift:1584-1602). Opt-in "fresh shop" notification re-arms per
  view (GameState.swift:1000-1006).
- **Sell Back (MERGED #118 + #120)** refunds `min(coinCost/2, paidPrices[key]
  ?? coinCost)` — 50% of the *current* price capped at what was actually paid
  (`sellBackValue`, GameState.swift:685; the persisted `ra_paidPrices` ledger
  records purchase prices, `purchase()` clears stale records, and
  `liquidateCoinCosmetics` (:715) clears entries as it refunds). Starters and
  Iconics (Trophy, Diamond, Money, starter looks) still never refund
  (`isSellable`, Cosmetics.swift:47-60); the graphite infinite-faucet is
  fixed (PR #112). The 100%-refund behavior audited at 064f3cd is gone.
- **Post-tutorial gift**: pick one full Standard-rarity bundle free after L10
  (BallGameView.swift:4599-4601); granted via `grantBundleFree` (GameState.swift:1473),
  marked `freeGrantedItems` so it can never be sold. Post-#114/#120,
  `grantBundleFree` also mints `sellBackValue` compensation via `addCoins`
  for bundle items the player already coin-bought — a refund-shaped credit
  any earned-from-play counter must exclude (trophy-catalog §6 item 4).

---

## 4. Engagement loops that monetize

1. **Identity loop (coins → shop)**: play anything → coins → hourly rotation
   + discounts create check-in pressure → shortfall alert upsells coin packs
   (CosmeticShopView.swift:272-277). Competitive minigames are the wage;
   the climb is the pilgrimage (design intent, docs/economy/07-decisions.md).
2. **Session loop (lives → relief)**: climb/track/Roll Out/Roll Up falls burn
   lives → out-of-lives overlay → rewarded ad (+1, free, uncapped), friend
   gifts, life packs, or the $19.99 unlimited flagship. Lives are priced ~10×
   more attractively per hour than coins ($0.77–0.99/regen-hr;
   docs/economy/03-iap-value.md) — monetization's center of gravity today is
   friction, flagged for rebalance toward desire
   (docs/research/01-roll-along-teardown.md §6, 04-gap-analysis.md).
3. **Skill loop (wins → tickets → Coin Pit)**: competitive wins mint tickets;
   Coin Pit converts them to the game's biggest coin bursts, which land back
   in the shop. Amortized +70–140 coins per competitive win.
4. **Completion loops**: Challenge Tracks (100 levels → free themed bundle —
   "primary skill-reward loop", docs/challenge-tracks-roadmap.md); bundle
   completionism (`completedBundleIDs` → aura ring + toast); the 10,000-coin
   pack's Money-drop repeats (the store's strongest perceived-value device).
5. **Dailies**: login ladder + CotD (~315/wk perfect) are recognition, not
   income — Mac deliberately nerfed the ladder 755→105/wk. Trophy design
   must respect that sensitivity to sign-in freebies.
6. **Planned (not built)**: the ~$5 seasonal "Roll Pass" is the monetization
   headline (docs/research/05-opportunities.md P5). Trophies must not occupy
   the pass's reward territory before it exists.

Existing achievement-shaped systems trophies must reconcile with: the profile
badge wall — **11 checks, zero rewards** (ProfileView.swift:388-474), level-
select completion nicknames (LevelSelectView.swift:92), the completionist
aura, and the earned Trophy ball precedent (golden-gauntlet track).

---

## 5. Trophy ↔ economy interaction analysis

### (a) Achievements that naturally drive monetized surfaces

- **Collection/bundle completion**: "Complete any collection / 3 / 10"
  extends the existing Completionist/Bundle Hunter badges
  (ProfileView.swift:447-459) and pushes players into the shop's prorated
  bundles and rotation discounts — the direct coin sink. Category ladders
  ("own 10/25/45 balls") aim at the deepest catalogue (96,000 coins of balls
  at live #124 prices; 26,150 pre-reprice).
- **Pack completion**: "Own a ball pack / all 3 packs" (7,920+3,300+3,780 =
  15,000 coins at live #124 prices; was 4,280) is a clean mid-game coin sink
  and teaches the shuffle-equip feature (`purchasePack`, GameState.swift:1619).
- **Track completion**: per-track and all-8-tracks trophies reinforce the
  free-bundle loop and lives spend (tracks consume lives on falls) — engaged
  track pushers are the natural lives-IAP audience.
- **Competitive/ticket trophies**: "win N per mode" (data already in
  `minigameWins`), "stake N tickets in one Coin Pit round", "buy the ×2
  boost" — deepen the ticket loop that feeds shop spending.
- **Shop-behavior trophies (use care)**: "buy a featured bundle at 50% off"
  gamifies rotation checking (good for DAU, slightly manipulative); prefer
  "complete a seasonal collection during its window".
- **New-best trophies**: mirror the 100-coin best bonus modes (Pinball, Roll
  Up, Disco, Gold Rush) — pure engagement, no monetization distortion.

### (b) Naively designed = pay-gated (dangerous)

- **Money cosmetics** (Money Ball/Roll/Full): only obtainable via repeat
  $49.99 purchases — ~$150 for the trio (StoreKitManager.swift:413-421). Any
  "own every ball/trail/floor" or "100% the catalogue" trophy that counts
  them converts completion into a ~$150 paywall. They are also deliberately
  **secret**; a visible locked trophy leaks the surprise.
- **Diamond ball / Unlimited Lives**: the existing "Unlimited Power" badge
  (ProfileView.swift:461-466) already rewards a $19.99 purchase. Elevating
  that pattern into a trophy system reads as pay-to-achieve, invites App
  Store review/goodwill risk, and clashes with the documented no-tracking /
  player-fair posture. Keep purchases out of trophy criteria entirely.
- **Big-spend trophies** ("spend 10,000 coins", "buy N IAPs"): (1) Sell Back
  (MERGED #118/#120) refunds `min(coinCost/2, paidPrice)` — the old
  100%-refund zero-cost farm is closed, but a coins-spent counter still
  churns at a 50% loss per cycle, and refunds are recycled capital, not play
  income. Track *ownership*, never *spend*.
  (2) IAP-count trophies are straight pay-gates.
- **Structural safeguard worth preserving**: no `CosmeticBundle` contains an
  IAP secret (the "diamond" bundle is baseball-themed, Cosmetics.swift:2484-2495),
  so `completedBundleIDs` is 100% coin/skill-reachable today. Define
  catalogue-completion trophies over coin-reachable sets (52,550 pre-reprice;
  on the order of ~200k at live #124 prices — re-derive per trophy-catalog §6
  item 16) and Iconics-excluded, exactly as Sell Back already does
  (Cosmetics.swift:47-60).
- **Perverse-incentive traps**: "run out of lives N times", "watch N ads",
  "lose N matches" monetize failure and train bad sessions. Avoid.

### (c) Would trophies granting coins break calibration? (quantified)

Reference points at the audited revision (pre-calibration/pre-reprice):
typical earn ~1,200/hr; dailies-only ~315/wk; first-session tutorial income
~50 coins + free Standard bundle; coin-reachable catalogue 52,550; IAP
anchors 100/600/1,300/3,000/10,000. **Post-merge (#118/#124) the live
anchors are:** canonical ~25 coins/min (~1,500/hr), IAP packs
750/4,500/10,000/22,500/60,000, catalogue on the order of ~200k. The
scenario table below is stated in pre-reprice equivalents — directionally, a
1,000–2,000-coin sweep now buys at most ~1 Legendary (1,500) instead of 2–4,
and the smallest IAP pack alone is 750 coins.

| Scenario (hypothetical 40-trophy set) | Injection | Equivalent | Verdict |
|---|---|---|---|
| Bronze sweep @ 25 coins | 1,000 | ~50 min of typical play; ~3.2 wk of dailies-only; 2 Legendaries (pre-reprice prices; <1 at the live 1,500) | Material but survivable; front-loading is the problem (most bronzes land in week 1) |
| Bronze sweep @ 50 coins | 2,000 | 4 Legendary items; ⅔ of the $19.99 coin pack | Cannibalizes small/mid coin IAPs; day-1 balance ~10× normal |
| Full sweep incl. silver/gold @ 100–500 | 5,000–10,000 | 1.5–3× the $19.99 pack; ~10–19% of the whole catalogue (pre-reprice equivalents) | Breaks calibration — collapses ruling 2's 30–60-min time-to-afford targets, now live via the shipped #124 reprice |

Aggravators: (1) **retroactive unlock on launch** — existing players receive
the sweep as one lump; (2) rewards double-pay surfaces that already pay
(daily streak trophies stack on the ladder Mac cut by 86%; per-mode-win
trophies stack on the 100-coin best bonuses and ticket mints); (3) any award
> 60,000 silently clamps (`maxSingleAward` — raised from 10,000 by the
merged #124; GameState.swift:1075), and awards must use `addCoins` — never
write `coinBalance` directly.

**Recommendation:** pay trophies in **status, not currency** — emblems/frames,
a trophy-exclusive cosmetic per milestone (Trophy-ball precedent), and
profile/leaderboard visibility. If coins are wanted for feel, cap the entire
lifetime trophy pool at roughly **one perfect daily week (~105–315 coins)**,
weight it toward late/gold tiers (nothing >35/trophy — the ladder's day-7
value). Re-derivation is **UNBLOCKED**: the 750–1,500 reprice shipped
2026-07-02 (MERGED #124) — every coin figure above moves with it, so
re-derive against the live table (docs/economy/08-reprice.md) before any D1
coin ruling.

---

## 6. Gaps / verify before build

- PR numbers were inferred from memory/log at audit time — since confirmed by
  the merge commits on main (#113/#114/#118/#119/#120/#122/#123/#124; see
  `repo-delta-2026-07-02.md`).
- Coin Pit catch-rate (40–80%) and per-mode durations are the briefing's
  modeled baselines, not telemetry (`minigame_result` events will supersede).
- Track pickup/lives edge cases: track falls consume lives whenever the
  *parked climb level* is >10 (BallGameView.swift:5476-5478 reads
  `gameState.currentLevel`); the track-pickup masking by the parked climb
  level's banked indices is **FIXED on main** (MERGED #119,
  `bankedCoinIndices` in BallGameView).
- CotD climb-path pollution (stray +2 and record pollution) is **FIXED on
  main** (MERGED #123): `.oneShot` clears return before all climb
  record-keeping, emit the analytics-only `daily_challenge_level_cleared`
  event, and an `assert(activeMode.progression.recordsClimbResult)` guards
  the climb path (`ProgressionKind.banksPickupCoins`/`.recordsClimbResult`,
  GameMode.swift — only `.mainClimb` is true for either).
