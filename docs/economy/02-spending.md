# 02 — Every way to spend coins

Coins have exactly **three spend call sites** in the entire app — all
cosmetics:

1. Single item at `tier.basePrice` — `spendCoins(item.coinCost)`
   (GameState.swift:1476-1481)
2. Bundle at prorated/featured price (CosmeticShopView.swift:1762)
3. Ball pack (GameState.swift:1497)

There is no coins→lives conversion, no entry fees, no consumables, no
upgrades. (Coin Pit rounds are staked with **tickets**, not coins.) This
single-sink structure is the teardown's flagged weakness — every coin chases
the same catalogue.

## Tier price ladder

Uniform across all categories — `coinCost = tier.basePrice`, no per-item
overrides (Cosmetics.swift:129-137):

| Tier (label) | Price | Curve step |
|---|---|---|
| starter (Free) | 0 | — |
| standard (Standard) | 50 | — |
| rare (Rare) | 100 | ×2 |
| premium (Epic) | 200 | ×2 |
| exclusive (Legendary) | 500 | ×2.5 |

A clean geometric ~×2–2.5 ladder — structurally healthy (see benchmarks doc).
The equity problem is **not the ladder** but which tiers each category
actually uses (below).

## Full census (corrected by adversarial recount, 2026-07-01)

| Category | Items | By tier | Coin total |
|---|---|---|---|
| Balls | 74 | 1 free · 13 std · 15 epic · 45 legendary | **26,150** |
| Goals | 33 | 1 free · 10 std · 10 epic · 12 legendary | **8,500** |
| Trails | 20 | 1 none · 5 std · 5 rare · 9 legendary | **5,250** |
| Floors | 30 | — | **5,050** |
| Pits | 29 | — | **4,100** |
| Boundaries | 13 | incl. rare tier (neon/gold/ice) | **2,100** |
| Music | 19 | — | **3,400** |
| **Total** | **218** | | **54,550** |

- **Coin-reachable total: 52,550** — excludes the 4 IAP-only secrets
  (Diamond + Money Ball balls, Money Roll trail, Money Full floor, nominal
  500 each; Cosmetics.swift:93-96, 902-903, 1077-1078).
- **Category tier-usage is inconsistent** (the real equity gap): Balls/Goals
  skip *rare*; Trails/Boundaries have it; only some categories span the full
  ladder. A player chasing trails hits a 100-coin mid-rung that ball chasers
  never see. → Standardize which rungs every category uses (sprint plan,
  workstream A).
- Balls are ~48% of the entire catalogue's value (45 legendaries — the
  identity item, sensibly deepest; matches the strategy of making the ball
  PvP-visible).

## Bundles (66) and packs

- `CosmeticBundle.catalogue` holds **66 bundles** (Cosmetics.swift:1831-2722).
- **Bundles are not a discount**: `proratedPrice` charges the sum of *unowned*
  items only (Cosmetics.swift:1770-1778) — identical to buying singles. Their
  value is curation + the auto-equip UX.
- **Bundle rarity** derives from the **member tier mix**, not price
  (`CosmeticBundle.rarity` via `tierCounts()`): ≥2 legendary members →
  Legendary; ≥2 epic-or-legendary members → Rare; else Standard. Prices
  appear nowhere in the rule, so reprices can't reshuffle the bands — see
  [08-reprice](08-reprice.md) "Follow-up closed". Examples: Hellfire (3
  legendary members) and Champion (2) are Legendary; Pastel (2 epic) is
  Rare; Bloom (1 legendary showpiece, rest standard) is Standard.
- **The only true discounts**:
  - **Featured-shop rotation** — hourly, one of 10/15/25/50% off at weights
    50/30/15/5 → expected ~15.75% (Cosmetics.swift:1441-1496), floored to ×5.
  - **Ball packs** — flat 66% of member-skin sum, floored to ×20 — e.g.
    Planets 2,640 (vs 4,000 in singles), Sports 520, Vintage Glass 1,120
    (Cosmetics.swift:2737-2741). **Not prorated** — a player owning members
    still pays full pack price (footgun; lever P2/UX).
- Routed optimally (packs + waiting on rotations), a completionist saves
  ~10–15% off list → everything for roughly **45–47k coins**.

## Sell-back (the reverse faucet)

`liquidateCoinCosmetics` (Settings → Sell Back, GameState.swift:665-718)
refunds **100% of coinCost** for every sellable coin-bought item, keeps
starters + Iconics, relocks the rest. Seasonal/limited cosmetics are sellable;
the tutorial's free bundle never refunds (`freeGrantedItems`,
GameState.swift:1402-1412).

- 100% refund means cosmetics are a **zero-risk parking account**, and
  rotation discounts are technically arbitrageable (buy at −50%, refund at
  100% — bounded, but worth deciding on).
- **The graphite bug lives here**: the strip loop re-inserts each category's
  starter (GameState.swift:692), but `TrailColor.starter = .graphite` is tier
  `.rare`/100 and not Iconic → every cycle refunds +100 and re-grants it.
  Infinite faucet (~600/min). *(P0; fix chip queued.)*

## Time-to-afford (typical 1,200/hr · best 7,200/hr)

| Milestone | Cost | Typical | Best grind | Dailies only |
|---|---|---|---|---|
| Standard item | 50 | ~2.5 min | <1 min | 1–4 days |
| Epic item | 200 | ~10 min | ~2 min | ~1 wk |
| Legendary item | 500 | ~25 min | ~4 min | ~1.6 wk |
| Standard bundle | ~650 | ~33 min | ~5 min | ~2 wk |
| Legendary bundle | 1,650–4,500 | 1.4–3.75 hr | 14–37 min | months |
| **Everything** | 52,550 | **~44 hr** | **~7.3 hr** | ~3.2 yr |

Post-P0 fixes (exploit + track farm closed), typical rates fall toward
~600–900/hr — roughly **doubling** all typical times. That's the moment to
re-price coin IAPs (see [03-iap-value.md](03-iap-value.md)) so bought coins
buy *meaningful* time.
