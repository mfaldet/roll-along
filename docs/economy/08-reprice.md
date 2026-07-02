# 08 — The shipped reprice (2026-07-02)

Mac approved the central scenario from the [07-decisions](07-decisions.md)
tier-price memo. This doc records exactly what shipped on branch
`claude/economy-reprice-v2`, the derived cascade values, and the App Store
Connect follow-ups that only Mac can do.

## Tier price ladder (Cosmetics.swift `CosmeticTier.basePrice`)

The ladder encodes ruling 2's time-to-afford targets — Standard 30 min,
Rare 40, Epic 50, Legendary 60 minutes of typical play at ~25 coins/min.

| Tier (player name) | Old | **New** | Sell-back half | Minutes @ 25/min |
|---|---:|---:|---:|---:|
| starter (Free) | 0 | **0** | — | — |
| standard (Standard) | 50 | **750** | 375 | 30 |
| rare (Rare) | 100 | **1,000** | 500 | 40 |
| premium (Epic) | 200 | **1,250** | 625 | 50 |
| exclusive (Legendary) | 500 | **1,500** | 750 | 60 |

Standing invariants (now also pinned by
`testCosmeticTier_basePricesMatchApprovedLadderAndAreEven`):

1. **Every price stays EVEN forever** — Sell Back refunds exactly half the
   current cost as an integer.
2. **Prices only ever drift up** (ruling 4's planned inflation); never cut.

### Legacy purchases are arbitrage-safe

`sellBackValue = min(coinCost / 2, paidPrice)` (GameState.swift, shipped
pre-reprice in PR #120 and untouched here) is what makes a reprice safe at
all: an item bought at the old 500 refunds at most the 500 that was paid,
not 750 — the price bump can never be minted into profit. Full-price legacy
buys with no `paidPrices` record refund half the *current* cost (blessed
positive-sum drift per ruling 4).

## Bundle rarity floors — derived, not guessed

Old floors 700/1,100 were tuned to bundles running 450–1,950. Under the new
prices the catalogue runs **4,500–13,500** (66 bundles), so every bundle
read Legendary and the post-tutorial gift pool (Standard-rarity, available)
was **empty** — the memo's predicted worst cascade.

The distribution was dumped from the live catalogue on the simulator
(`test_bundleRarityDistribution`, prints price + PERMANENT/seasonal per
bundle) and the floors chosen from the actual data:

| Floor | Old | **New** |
|---|---:|---:|
| `rareFloor` (below → Standard) | 700 | **5,500** |
| `legendaryFloor` (below → Rare, else Legendary) | 1,100 | **6,500** |

Resulting split: **Standard 6 / Rare 20 / Legendary 40** (9% / 30% / 61%) —
a pyramid proportionally close to the old 7/17/42. Six bundles sit at
exactly 5,500; the next round step up (5,750) would balloon the permanent
gift pool to 10, so 5,500 it is.

**Permanent Standard pool (the post-tutorial gift can never dead-end):**

| Bundle | fullPrice | Availability |
|---|---:|---|
| diamond (baseball-themed) | 4,500 | permanent |
| nature | 5,000 | permanent |
| citrus | 5,000 | permanent |
| sketchbook | 5,250 | permanent |
| backtoschool-2026 | 4,500 | seasonal window |
| earthday-2027 | 5,000 | seasonal window |

Guarded by the new regression test
`testTutorialGift_permanentStandardBundlePool_neverEmpty` — a future price
or bundle change that empties the pool fails CI, not prod.

Known follow-up (unchanged from the memo): with a near-flat 1:2 tier ladder,
bundle `fullPrice` mostly measures *item count*, not tier mix. Deriving
BundleRarity from member tiers instead of total price is queued as a design
decision before the next seasonal drop.

## IAP coin packs — re-anchored

The old bottom packs (100 / 600 coins) could no longer buy a single item
(minimum price 750). New amounts, coins-per-dollar **strictly rising** with
pack size:

| Product ID (immutable) | $ | Coins old → new | Coins/$ | Badge |
|---|---:|---:|---:|---|
| …coins.100 | 0.99 | 100 → **750** | 758 | (base rate) |
| …coins.600 | 4.99 | 600 → **4,500** | 902 | +20% coins |
| …coins.1300 | 9.99 | 1,300 → **10,000** | 1,001 | +30% coins |
| …coins.3000 | 19.99 | 3,000 → **22,500** | 1,126 | +50% coins |
| …coins.10000 | 49.99 | 10,000 → **60,000** | 1,200 | +60% coins (diamond shimmer) |

- The `ProductID` case names and App Store Connect product IDs keep their
  historical numbers — ASC IDs are immutable. `rewardCoins` is the single
  source of truth; the Get Coins sheet now reads amounts from it.
- The top pack's old "×2 coins" claim (true at 10,000) would be false at
  60,000 (1.58×); the badge now shows the same honestly-computed +60% as
  the other packs, in the diamond shimmer style.
- The coins.10000 product keeps its secret Money-cosmetic drop, untouched.
  Its comments were renamed "top coin pack ($49.99)" because the coins.1300
  pack now grants exactly 10,000 coins — the old moniker became misleading.
- `GameState.maxSingleAward` 10,000 → **60,000** so the top grant is not
  silently clamped (pinned by `testAddCoins_topCoinPackGrant_isNotClamped`).
  The 999,999 balance ceiling stays.
- Products.storekit (simulator/StoreKit-config testing) copy updated to the
  new amounts.

### App Store Connect follow-ups — Mac only

The live product metadata still shows the old amounts until Mac updates ASC
(display name + description per product; prices unchanged):

| Product ID | Display name | Description |
|---|---|---|
| com.macfaldet.RollAlong.coins.100 | 750 coins | 750 coins added to your balance. |
| com.macfaldet.RollAlong.coins.600 | 4,500 coins | 4,500 coins (+20% more per dollar than the base pack). |
| com.macfaldet.RollAlong.coins.1300 | 10,000 coins | 10,000 coins (+30% more per dollar than the base pack). |
| com.macfaldet.RollAlong.coins.3000 | 22,500 coins | 22,500 coins — a big haul (+50% more per dollar than the base pack). |
| com.macfaldet.RollAlong.coins.10000 | 60,000 coins | 60,000 coins — the best coins-per-dollar in the store (+60% over the base pack). |

**Sequencing note:** ship the app update and the ASC metadata change
together. The in-game grant follows the app version (a pre-update client
still grants the old amounts), so update metadata when the release goes
live, not before.

## What deliberately did NOT change

- `sellBackValue = min(cost/2, paid)` — the arbitrage guard, see above.
- Bundle/pack pricing formulas — `fullPrice`/`proratedPrice`/66%-pack
  pricing all read `coinCost` and repriced automatically.
- Lives packs, Unlimited, and the retired Starter Pack.
- Money-cosmetic and Diamond gating.
- Earn rates (calibration-1 constants) — this reprice is the spend side of
  those numbers.

## Monitoring

R = 25 coins/min is a model, not telemetry. `minigame_result` carries
base_payout/payout/difficulty and clear events carry timing — recompute R
from live data ~2 weeks post-launch and adjust via the same
`basePrice` switch (keep prices even; only drift up).
