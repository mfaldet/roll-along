# 03 — IAP value: what a dollar actually buys

The calibration currency for coin IAPs is **hours of grind saved**. Model:
`hours saved = coins ÷ earn rate`, `$/hr-saved = price ÷ hours saved`, at both
the typical-casual rate (1,200/hr) and best-sustained rate (7,200/hr).
Lower $/hr-saved = stronger perceived value.

## Coin packs

| SKU | Price | Coins | Hrs saved (typical) | $/hr (typical) | $/hr (best) | What it buys |
|---|---|---|---|---|---|---|
| coins100 | $0.99 | 100 | 5 min | **$11.88** | $71.30 | one Rare item; ≈ one Paint Ball win |
| coins600 | $4.99 | 600 | 30 min | **$9.98** | $59.90 | one Legendary + change |
| coins1300 | $9.99 | 1,300 | 65 min | **$9.22** | $55.30 | a mid legendary bundle |
| coins3000 | $19.99 | 3,000 | 2.5 hr | **$8.00** | $48.00 | Planets ball pack (2,640) + change |
| coins10000 | $49.99 | 10,000 | 8.3 hr | **$6.00** | $36.00 | ~19% of the catalogue **+ 1 random Money cosmetic** |

(StoreKitManager.swift `rewardCoins`; Products.storekit price tiers — the table
amounts predate the 2026-07 reprice. Starter Pack $1.99 → 3,750 coins + the full
Aurora collection, free-granted: un-retired 2026-07 as the one-time 48-hour
welcome offer. Its coin component was repriced 7.5× with the coin packs (500 →
3,750), so at ~1,884 coins/$ it stays the best coin value ever sold — the
intended one-time hook — and sits outside the coins-per-dollar ladder above.)

**Reading:**
- **The small packs are anti-value**: $0.99 buys 5 minutes of play. Nobody
  should feel smart buying it, and the ladder teaches players that coins are
  expensive relative to just playing. Top games invert this — see benchmarks.
- Value curve improves monotonically with size (good anchoring shape), but the
  *absolute* range ($6–12/hr saved vs typical play) is weak against the
  industry's ~$1–5/hr comfort band for casual titles.
- **coins10000 has real teeth** only because of the Money-cosmetic drop
  (exclusive, never coin-buyable; full 3-piece set = 3 × $49.99). That is the
  correct pattern: *money buys exclusivity + time, not just time*.
- **Guardrail interaction**: the 10,000 grant sits exactly at
  `maxSingleAward = 10,000`, and the 999,999 balance cap silently eats
  overflow (GameState.swift:1023-1048). Warn in purchase UI near cap. (P3.)

## Lives IAPs (a different product: relief, not coins)

| SKU | Price | Lives (code) | Regen skipped | $/regen-hr | Store copy says |
|---|---|---|---|---|---|
| livesPack1 | $0.99 | 10 | 1 hr | $0.99 | **"6 lives"** ✗ |
| livesPack5 | $4.99 | 60 | 6 hr | $0.83 | **"36 lives"** ✗ |
| livesPack10 | $9.99 | 130 | 13 hr | $0.77 | **"78 lives"** ✗ |

(StoreKitManager.swift:66-71 vs Products.storekit:17,32,47 — the copy
under-promises by ~40%. Compliance/trust fix chip queued.)

- In *play* terms 10 lives ≈ 4–11 min of actual climb play — the product is
  really "keep your session going," a **friction reliever**. The teardown
  already flags that monetization's center of gravity is friction (lives)
  rather than desire (cosmetics); these numbers confirm lives are priced ~10×
  more attractively per hour than coins.
- **The rewarded ad undercuts all of this**: +1 life per ~30s ad, unlimited
  fill permitting (AdManager.swift:155-157) — 12× faster than regen, free.
  Deliberate generosity, but it caps lives-pack urgency at "ad-averse players
  only."

## Diamond Balls — $19.99 non-consumable

Unlimited lives forever + the exclusive Diamond skin (only source).

- Breakeven vs livesPack10 pricing: ~260 lives.
- A heavy player net-consumes 10–20 lives/hr beyond regen (hard climb pushes,
  Roll Up farming at ~30 runs/hr) → **pays for itself in ~13–26 hours of hard
  play**, then free forever. It also uniquely converts Roll Up (24/min,
  life-gated) into an unlimited grinder.
- It shares the $19.99 price point with coins3000 — a deliberate-looking
  anchor: same money, *permanent utility + identity* vs 2.5 hours of coins.
  Diamond wins for anyone who does the math, which is fine — it's the
  flagship.

## Calibration stance (feeds 04 + benchmarks)

1. **Fix free rates first** (P0 exploit + track farm), else every IAP number
   is priced against a broken baseline.
2. **Re-anchor coin packs** post-fix: either raise small-pack amounts
   (100 → 150–200) or reposition packs to land exactly on bundle price points
   (650 / 950 / 1,650 / 2,640) so every purchase completes a *visible want*
   rather than adding an abstract balance. "Buys exactly the Hellfire bundle"
   beats "+1,300 coins."
3. **Keep lives cheap** (they're retention, not margin) but fix the copy, and
   consider surfacing the rewarded ad *inside* the Get Lives sheet as the
   honest free alternative — trust converts better than friction.
4. **Lean into money-buys-exclusivity**: the Money-cosmetic pattern
   (coins10000) is the strongest perceived-value device in the store;
   the seasonal $2.99 bundles are the same idea at impulse price.
