# 07 — Decisions log: Mac's five rulings + what shipped

The five standing decisions from [06-sprint-plan.md](06-sprint-plan.md) were
put to Mac on 2026-07-01 and all five are **ruled**. This doc records the
rulings verbatim-in-intent, their implications, the calibration levers already
implemented against them (branch `claude/economy-calibration-1`, build- and
diff-verified), the recomputed post-change earn table, and the tier-price
derivation memo — the one remaining item **awaiting Mac's approval**.

## The five rulings

| # | Question (from 06) | Ruling |
|---|---|---|
| 1 | Track farm: close or bless? | **Bless replay farming everywhere.** "Whether they play to level 10,000 or replay the first level 10,000 times, I don't care." Track farm stays; the climb gets replay *parity* (repeat clears pay too). |
| 2 | Target minutes per tier | **Time-to-afford: Standard 30 min, Rare 40, Epic 50, Legendary 60** of typical play. (Much longer than the Workstream A proposal — these are real saves, not impulse buys.) |
| 3 | Daily soft cap | **No cap. Monitor only.** Watch per-session payout distributions via telemetry; intervene only if the data demands it. |
| 4 | Bundle discount + sell-back pairing | **Sell Back refunds 50% of the *current* individual cosmetic cost** (reads live `coinCost`). Mac plans to subtly inflate prices over time, so refunds drift up with them. |
| 5 | Difficulty spread | **Compress and reword: Easy pays 1x, Normal 1.5x, Hard 2x** (was ×0.5/×1.0/×2.0). |

### Implications, ruling by ruling

**Ruling 1 (replay farming blessed)** dissolves the briefing's P0 "track farm"
finding — it is now policy, not exploit. The design consequence: the climb and
track are both legitimate grind surfaces, so climb replays must pay *something*
(parity) or the track farm becomes the only rational grind. Implemented as: the
climb pays its tier bonus on **every** clear (pickups stay sticky — banked coins
are un-pickable across attempts, so pickups still pay exactly once). The
resulting farm optimum is deliberate and bounded: an early last-digit-x5/x0
(veryHard) level replays at ~4 coins/20s ≈ **12 coins/min**, comfortably below
every competitive mode. The graphite sell-back exploit is *not* covered by this
blessing — that was a bug, and it's fixed on the same branch (`isSellable` now
excludes `Self.starter`).

**Ruling 2 (30/40/50/60 min)** replaces the old 50/100/200/500 price ladder's
implicit targets. At the recomputed blended typical rate (~25–32 coins/min,
see the memo below) these targets price tiers in the ~750–1,920 coin range —
a ~4–15× inflation over today's prices, with large cascades into bundles,
packs, IAP anchoring, and the post-tutorial gift. Hence the derivation memo
rather than a unilateral change.

**Ruling 3 (no cap)** removes the Workstream A "diminishing returns above
~2,500/day" proposal. The monitoring hook already exists: `minigame_result`
carries `base_payout`/`payout`/`difficulty`, and track/climb clear events carry
timing. The watch items are Coin Pit ticket-cashing frequency and Paint Ball
coverage distributions (the two paths that can push a "typical" player toward
optimizer rates).

**Ruling 4 (50% of current cost)** replaces both the old 100% refund and the
briefing's "refund-what-you-paid" proposal. Three consequences: (a) the
rotation-discount arbitrage closes — even a lucky 50%-off featured buy only
*breaks even* on resale; (b) refunds must halve to integers, so **all tier
prices must stay even forever** (the code comments now rely on exact integer
halving); (c) because the refund reads the *live* price, every future price
inflation retroactively raises the refund on items bought cheaper — a small,
blessed, positive-sum drift. Monitor it, don't fight it.

**Ruling 5 (1x/1.5x/2x)** compresses the spread from 4× to 2× and rewords the
labels so Easy no longer reads as a penalty ("0.5x coins" → "1x coins").

> **The honest EV note.** With multipliers 1x/1.5x/2x against the designed
> `targetWinRate`s of 0.80/0.45/0.22, expected value per attempt is
> **0.80 / 0.675 / 0.44** of the win payout — **Easy is EV-optimal by
> design**. This is deliberate: Easy-camping is a win-rate comfort choice,
> not a coins/min exploit, because round length is fixed and Normal/Hard
> still dominate *per minute*. It is monitored, not patched — the
> `minigame_result` event carries everything needed to detect
> Easy-camping-plus-Coin-Pit drift toward the hot scenario.

## What shipped: branch `claude/economy-calibration-1`

Seven levers, 11 files, 7 commits, independently diff-audited and
build-verified (`xcodebuild` exit 0). All tests updated to the new spec
values rather than deleted.

| Lever | Change | Verified |
|---|---|---|
| 1 — Sell Back 50% | `coinLiquidationPreview` (GameState.swift:670) and `liquidateCoinCosmetics` (:691) both refund `item.coinCost / 2`; starter/freeGranted exclusions intact; SettingsView copy updated in all 3 spots; no stale "full refund" strings; CosmeticsTests halved + new 500→250 assertion; second-pass-refunds-nothing test untouched. | ✔ |
| 2 — Difficulty compression | `payoutMultiplier` now 1.0/1.5/2.0, `payoutLabel` "1x/1.5x/2x coins" (GameState.swift:~1706-1725); `aiAccelScale` and `targetWinRate` untouched; labels render only via `MinigameDifficulty.payoutLabel` — no hardcoded strings; docs/minigame-difficulty.md EV section rewritten (0.80/0.675/0.44, Easy EV-optimal by design). | ✔ |
| 3 — Climb replay parity | Climb pays `GameState.clearCoins(for:)` + pickups on **every** clear (BallGameView.swift:5658); `isFirstClear` gate removed; sticky-pickup bank untouched so pickups still pay once. **One regression found and flagged**: a pit fall during the tutorial's first L1 attempt leaves `tutorialCoinBonus` stale and shorts the clear payout to 0 (fix: reset it at BallGameView.swift:5373 beside `coinsPickedThisAttempt`). Fix queued before merge. | ✔ (with 1 flagged edge case) |
| 4 — Solo/competitive rebalance | Sumo placement `[60,30,15,8]` (SumoSurvivalView.swift:58); Marble Cup 15/goal + 30 win, 15 loss floor via shared `matchBasePayout`; Pinball divisor 250→125 (PinballView.swift:149); Roll Out 10/clear + new 100-coin furthest-maze best bonus, matching Disco/Roll Up. | ✔ |
| 5 — Climb tier-scaled clears | Static `GameState.clearCoins(for:)` returns 2/3/4 for easy/hard/veryHard via the last-digit rule (LevelLayout.swift:114); Challenge Track fast-path still pays flat 2. Caveat stands: `tierOverrides` do **not** affect payout — digit rule only. | ✔ |
| 6 — CotD fast-path | New `.oneShot` clear path (BallGameView.swift:5616-5631): no `recordResult`, no climb coin payout, no best-time pollution; flow still lands on the flat 30-coin daily completion; new `daily_challenge_level_cleared` analytics event. | ✔ |
| 7 — Coin Pit doc/code sync | Gold Rush comment block rewritten to shipped reality (30s tickets, no cap, 2-ticket ×2 boost with back-pay, early-quit refunds); dead `goldRushMaxStake` deleted; docs/gold-rush-economy.md updated. | ✔ |

This clears S0.1 (graphite fix rides the same branch), S0.2 (ruled), S0.4,
S0.5, and the lever half of Workstream A. Sprint-0 acceptance holds: no earn
path exceeds ~150 coins/min sustained (Coin Pit bursts are ticket-gated),
two consecutive sell-backs refund 0.

## Post-change earn table (recomputed from source at 29171fc)

All numbers recomputed from the calibrated code, not the implementation
report. Rounding via `Int((base * mult).rounded())` shifts EV by <1 coin at
these bases. Baselines match the 01-earning audit (50% win rate, 7.5s
overhead, KotH 20s hold, Paint Ball 50% coverage, Marble Cup 2 goals);
added assumptions are flagged in the notes.

| Path | Formula (source) | Duration | Coins/min | Gate |
|---|---|---|---|---|
| Climb — progressing (first clears) | `clearCoins(for:)` 2/3/4 by last-digit tier (GameState.swift:1029-1035; rule LevelLayout.swift:114-122) + 1/pickup ×3 first-time (:1015); award BallGameView.swift:5658-5660 | ~45s + 5s | ~5.8 (no difficulty scaling) | lives |
| Climb — replay farm (blessed) | flat tier bonus, pickups sticky (BallGameView.swift:5636-5651): easy 2, veryHard 4 | ~15s early + 5s | easy 6.0; **best farm: veryHard 12.0**; mid-climb 4.8 | lives |
| Challenge Track replay | flat `coinPerClear` 2 (GameState.swift:1024) + sticky pickups (BallGameView.swift:5577-5578) | 15–45s + 5s | 6.0 early / 2.4 typical | free (no lives on track replays) |
| KotH | `holdSec×2 + 15` win (KingOfTheHillView.swift:52-53); 20s hold → 55/40 | 60s + 7.5s | Normal 63.6; Hard 84.4 | free |
| Paint Ball | `coveragePct + 20` win (PaintBallView.swift:49, :587); 50% → 70/50 | 60s + 7.5s | Normal 80.0; **Hard 106.7 — highest competitive faucet** | free |
| Marble Cup | `max(15, goals×15 + 30 win)` (MarbleCupView.swift:52-55) | 90s + 7.5s | Normal 41.5; Hard 55.4 | free |
| Snake / Comet Clash | `power×3 + 20` win (SnakeGameView.swift:54-55); power 8 → 44/24 | ~60s (no timer) + 7.5s | Normal 45.3; Hard 60.4 | free |
| Sumo Survival | placement `[60,30,15,8]` (SumoSurvivalView.swift:58) | ~90s (3 rounds) + 7.5s | Normal 41.5; Hard 55.4 | free |
| Gold Rush arena | `playerScore + 15` win (GoldRushEngine.swift:47, :543); ~40/35 score | 60s + 7.5s | Normal ~60; Hard ~80 | free; wins pay 1 ticket |
| Pinball (solo) | score/125 (PinballView.swift:149); ~10k score → 80 | ~4 min | ~20 (+100 one-time new-best) | free |
| Disco Ball (solo) | 3/crossing (DiscoBallView.swift:61); ~12 → 36 | ~75s | ~29 (+100 new-best) | free |
| Roll Up (solo) | 0.20/m cap 250 (RollUpView.swift:44-45); ~100m → 20 | ~90s | ~13 (+100 new-best) | free |
| Roll Out (solo) | 10/maze (RollOutView.swift:129); +100 furthest-best (:587-594) | ~60s/maze | ~10 | free |
| Coin Pit (ticket round) | 1/catch, 100 dropped per 30s ticket (GameMode.swift:277, GameState.swift:1213); ~70% catch; ×2 boost for 2 tickets | 30s/ticket | ~140 unboosted / ~280 boosted — top burst; amortizes to **+70–140 per competitive win** | tickets |
| Challenge of the Day | flat 30 on completion (GameMode.swift:525, GameState.swift:873-879); sub-levels pay 0 (`.oneShot` path) | ~5 min w/ retries | ~6, once/day | daily, lives |
| Daily login ladder | [5,8,10,12,15,20,35] = 105/week (GameState.swift:1315) | instant | ~15/day flat | daily |
| Zen Garden | min(sec/60, 15)/session (GameState.swift:1188) | continuous | 1, cap 15/session | free |

**Blended typical rate: ~32 coins/min (~1,900/hr)** for the casual archetype
(50% Normal competitive @50% win → 27.7 + 25% climb/track grind → 1.1 +
15% solo → 2.7 + 10% menus/dailies → 0.7). Hard-camping lifts the blend to
~41. Coin Pit and one-time best bonuses excluded from steady state; always
spending tickets adds ~10–20 coins/min to the competitive slice.

Ordering sanity holds the design intent: **competitive Normal (41–80) >>
solo (10–29) >> climb farm (6–12) > climb progression (~5.8)** — minigames
are the wage, the climb is the pilgrimage. Watch Paint Ball in telemetry:
coverage *is* the base, so a 60%+-coverage player exceeds 120/min at Hard.

Added assumptions beyond the 01 audit (flagged): Snake round ~60s (no timer
in code), Sumo ~90s (35s shrink forces resolution), Gold Rush score ~40/35,
Pinball 10k in 4 min, Disco 12 crossings/75s, Roll Up 100m/90s, Roll Out
60s/maze, Coin Pit 70% catch.

## Tier-price derivation memo — **awaiting Mac's approval**

Ruling 2 fixes the *time* targets; the price table follows from the assumed
earn rate R. Three scenarios were derived; **nothing here is implemented yet**.

### The three scenarios

| Scenario | R (coins/min) | Standard / Rare / Epic / Legendary | Verdict |
|---|---|---|---|
| Conservative | 20 | 600 / 800 / 1,000 / 1,200 | Cleanest halves, but under-prices the moment a player cashes *any* Coin Pit tickets or camps Paint Ball — real time-to-afford falls to ~22 min for a Standard, missing the 30-min target from below; forces earlier, more visible inflation. |
| **Central (recommended)** | 25 | **750 / 1,000 / 1,250 / 1,500** | Blended rate computes to 26.7 under the new constants; pricing at 25 lands every tier at-or-just-above the 30/40/50/60 targets with headroom for ruling-4's planned drift. Even numbers (exact halves 375/500/625/750), memorable 250-step ladder. |
| Hot | 35 | 1,050 / 1,400 / 1,750 / 2,100 | Prices for optimizers; median player's real time blows out to ~42/56/70/84 min (40% over target). This is the table to *migrate toward* via ruling-4 inflation, not to launch at. |

### Recommendation

**Ship the central table: 750 / 1,000 / 1,250 / 1,500** — one edit, the
`basePrice` switch in Cosmetics.swift:132-140 (starter stays 0). Reasons:

1. R = 26.7/min under the new payout constants; launching at the low-central
   edge means prices only ever drift *up* (loss-aversion-safe — never cut).
2. All four prices are even → sell-back halves exactly (375/500/625/750).
   **Keep every future inflated price even.**
3. Clean 250-step ladder that reads honestly next to the coin balance.
4. Conservative misses targets from below for anyone touching the Coin Pit;
   Hot violates the "typical play" framing of ruling 2.

R is a model, not telemetry. `minigame_result` already carries
base_payout/payout and clear events carry timing — **recompute R from live
data ~2 weeks post-launch** and adjust via the same single switch.

Deliberate design consequence: 750:1,000:1,250:1,500 = 1:1.33:1.67:2 versus
the old 1:2:4:10 — a Legendary is now only 2× a Standard. Rarity prestige
must come from visible quality (animated/MeshGradient renderers, the gem
badge ramp), not the price tag. The tier rules already support this, but the
price-derived bundle-rarity system does **not** survive the compression (see
cascades).

### Cascades (all pend on the price-table approval)

- **BundleRarity floors** (Cosmetics.swift:1630-1631, 700/1,100 tuned to old
  prices): naive ×4.40 rescale to 3,000/4,750 **fails** — the split collapses
  from 7/17/42 to 0/2/64 and the Standard band empties. Use re-derived floors
  **5,500/6,250** instead → 6/13/47 split, only 12 label changes. Deeper
  issue: with a near-flat ladder, bundle fullPrice measures *item count*, not
  tier mix — queue a follow-up decision to derive BundleRarity from member
  tiers before the next seasonal drop (backtoschool-2026 and earthday-2027
  sit right on the new boundaries).
- **All 66 bundles reprice automatically** (proratedPrice, no stored prices):
  cheapest permanent ~650 → ~5,000; the 9-ball Planets bundle 4,500 → 13,500
  (~9 hr of typical play — the new top anchor; decide if intended or if big
  bundles deserve a pack-style discount).
- **Ball packs** (flat 66% of member sum, Cosmetics.swift:2738-2744) reprice
  automatically and stay internally consistent; no code change. Pre-existing
  footgun unchanged: packs aren't prorated against owned members.
- **IAP coin packs**: the bottom breaks — coins100 *and* coins600 can no
  longer buy a single item (min price 750). Re-anchor onto the new price
  points, e.g. 750 / 3,300 / 8,000 / ~16,500 / ~45,000. Touches
  StoreKitManager, PurchaseSheets, Products.storekit, App Store Connect
  metadata, **and the `maxSingleAward = 10,000` clamp in GameState** (a
  16,500 grant would be silently clamped today). Separate approval — but
  don't ship the price table without at least deciding the small-pack story.
- **Sell Back refunds** become 375/500/625/750. Update CosmeticsTests.swift:343
  ("a 500-coin exclusive refunds 250" → 1,500/750).
- **Post-tutorial free bundle gift** (BallGameView.swift:4601 filters
  `rarity == .standard`): with naive rescaled floors the pool is **empty**
  and the gift flow dead-ends — the hardest cascade failure and the main
  reason for the re-derived 5,500/6,250 floors (pool: 4 permanent bundles +
  2 seasonal windows). Gift value inflates from ~25 min of play to ~3–3.5 hr;
  decide whether that endowment is intended or the gift becomes a fixed named
  bundle.
- **Stale copy sweep**: CosmeticTier case comments ("50 coins", "500 coins —
  top-tier"), per-tier `// N coins` annotations, docs/economy tables, the
  CosmeticsTests comment at line 35. Catalog sorting/badges/triplePick are
  tier-driven, not price-driven — they survive unchanged.

### Open risks

1. **R is modeled, not measured** — recompute from telemetry ~2 weeks
   post-launch; reprice is a one-switch change.
2. **Coin Pit is the wildcard**: Easy is now EV-optimal per attempt by design
   (see the honest EV note above), and Easy-camping + pit-cashing could push
   a "typical" player toward the hot scenario. Ruling 3 says monitor only.
3. **Track pickup gate cross-contamination**: the pickup loop
   (BallGameView.swift:5213) reads `coinsCollected(for: currentLevel)` even
   in Challenge Track mode, so a track level's pickups can be masked by the
   parked climb level's banked indices. Worth a look independent of pricing.
4. **Completionist runway** stretches ~44 hr → ~156 hr (coin-reachable total
   233,750 at 1,500/hr) — intended, but spread across many 1,500-coin items
   rather than a few big saves; watch mid-game purchase-milestone feel.
5. **Lever-3 tutorial regression** (stale `tutorialCoinBonus` after a pit
   fall on the first L1 run) must land before the calibration branch merges.
