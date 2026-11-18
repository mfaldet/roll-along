# 2026-11 coin packs at App Store Connect amounts

**Status:** the coin packs are changed in the app (built). The Starter Pack
section and the recommendations are proposals only; nothing there is changed.

## What changed

App Store Connect sells the coin packs at the amounts in their product IDs.
The game had been granting 7.5 times more (the 2026-07 re-anchor in
`08-reprice.md`). The game now grants exactly what App Store Connect says.

| Product ID | Price | Game gave before | Game gives now | Coins per $ |
|---|---|---|---|---|
| `coins.100` | $0.99 | 750 | **100** | 101.0 |
| `coins.600` | $4.99 | 4,500 | **600** | 120.2 |
| `coins.1300` | $9.99 | 10,000 | **1,300** | 130.1 |
| `coins.3000` | $19.99 | 22,500 | **3,000** | 150.1 |
| `coins.10000` | $49.99 | 60,000 + Money Ball skin (first time) | **10,000** + Money Ball skin (first time) | 200.0 |

Bonus labels on the Get Coins sheet are measured against the 100-coin pack
(101.01 coins per $) and rounded down to a whole percent: +19%, +28%, +48%,
+98% (arithmetic in `docs/app-review/in-app-purchases.md`). The 100-coin
pack shows none.

Nothing else changed: cosmetic prices, earning, the daily reward, Gold Rush,
clan prizes and the Starter Pack are as before.

## What a coin costs in dollars at each pack

| | 100 pack | 600 pack | 1,300 pack | 3,000 pack | 10,000 pack |
|---|---|---|---|---|---|
| $ per 1,000 coins | $9.90 | $8.32 | $7.68 | $6.66 | $5.00 |

## What things cost in dollars

Coin price × the pack's dollars per coin.

| Item | Coins | 100 pack | 600 pack | 1,300 pack | 3,000 pack | 10,000 pack |
|---|---|---|---|---|---|---|
| Standard item | 750 | $7.42 | $6.24 | $5.76 | $5.00 | $3.75 |
| Rare item | 1,000 | $9.90 | $8.32 | $7.68 | $6.66 | $5.00 |
| Premium item | 1,250 | $12.38 | $10.40 | $9.61 | $8.33 | $6.25 |
| Legendary item | 1,500 | $14.85 | $12.47 | $11.53 | $9.99 | $7.50 |
| Smallest collection (Nature, Diamond, Earth Day) | 5,750 | $56.92 | $47.82 | $44.19 | $38.31 | $28.74 |
| Typical Legendary collection | 8,250 | $81.67 | $68.61 | $63.40 | $54.97 | $41.24 |
| Aurora collection | 9,750 | $96.53 | $81.09 | $74.92 | $64.97 | $48.74 |
| Planets collection | 21,500 | $212.85 | $178.81 | $165.22 | $143.26 | $107.48 |

Collections are seven items, full price; the Shop's featured bundle takes
10–50% off one collection at a time.

## What free play is worth in dollars (at the 100-coin pack rate)

From `2026-11-coin-rebalance.md`, round 3.

| Source | Coins | At $9.90 per 1,000 |
|---|---|---|
| 20 minutes of Adventure a day (plus daily reward) | about 108 a day | about $1.07 a day |
| Daily reward, one week | 105 | $1.04 |
| One Gold Rush round (5 tickets) | about 70 | $0.69 |
| Clan prize, Diamond / Gold / Silver / Bronze (monthly) | 1,000 / 500 / 250 / 100 | $9.90 / $4.95 / $2.48 / $0.99 |
| Trophies | none pay coins | — |

## The Starter Pack today

- **Product:** `com.macfaldet.RollAlong.starterpack`, non-consumable, $1.99.
- **Gives:** 3,750 coins and the complete Aurora collection: ball, goal,
  trail, floor, boundary and music (Legendary, 1,500 each) and pit (750),
  9,750 coins of items. The items are marked as gifts, so Sell Back never
  refunds them. The coins are paid once, even on a restore.
- **When it is offered:** on the Home screen, by itself, the first time the
  coin balance reaches 250 (`GameState.starterPackTriggerCoins`), after the
  tutorial. It can be reopened for 48 hours from that moment. It is never
  offered once bought, after "No thanks", or if the player already owns the
  whole Aurora collection. It needs the product to have loaded from the App
  Store.
- **Value at 100 coins per $0.99:** 3,750 coins = $37.12, plus the Aurora
  collection = $96.53. **$133.65 for $1.99, about 67 times the price.** The
  coins alone are worth about 19 times the price.

## Starter Pack options for $1.99 (not built)

A generous first-purchase deal is usually worth 10 to 25 times its price.
Values at the 100-coin pack rate ($9.90 per 1,000 coins).

| Option | Contents | Value | Times the price |
|---|---|---|---|
| A. Aurora ball | Aurora ball (1,500) + 1,000 coins | $14.85 + $9.90 = **$24.75** | 12× |
| B. Aurora starter kit (recommended) | Aurora ball, trail and boundary (4,500) + 500 coins | $44.55 + $4.95 = **$49.50** | 25× |
| C. Aurora collection, no coins | All seven Aurora items (9,750) | **$96.53** | 48× |

- **A** is closest to the original 2026 offer (500 coins + the Aurora ball)
  and leaves room for the coin packs.
- **B** gives the three most visible Aurora pieces, so the player sees it on
  every level, and the rest of the collection is something to earn.
- **C** keeps today's headline ("the complete collection") and only drops the
  3,750 coins, which on their own are now worth 19 times the price.

Whichever is chosen, the sheet text, `rewardCoins` for `.starterPack`,
`grantAuroraCollection`, `Products.storekit`, the review notes and
`in-app-purchases.md` change together. Restores of an earlier purchase must
still deliver what was sold; nobody has bought it yet, so there is nothing to
migrate.

## Anything now out of line

1. **The two smallest coin packs buy nothing on their own.** The cheapest
   item is 750 coins. The 100-coin pack ($0.99) and the 600-coin pack
   ($4.99) only top up earned coins; 1,300 ($9.99) is the first pack that
   buys an item by itself. Players who buy the $0.99 pack expecting a skin
   may feel cheated. Options: (a) accept it, and show on each pack card what
   it can buy ("Tops up your coins"); (b) lower cosmetic prices (for example
   Standard 500, Rare 600, Premium 800, Legendary 1,000, so 600 coins buys a
   Rare), which also makes free players about 1.5 times faster; (c) change
   the App Store Connect amounts.
2. **A cosmetic now costs $3.75 to $14.85.** That is 7.5 times what the
   2026-07 design intended ($0.99 for a Standard item). It is high for a
   casual game, where single skins usually cost $1 to $5. Free-play pacing
   is unchanged (about 7 days of Adventure for a Standard item), so coins
   are now mainly a time-saver: $1 buys about a day of play.
3. **The Starter Pack** is about 67 times its price (above).
4. **Clan prizes are in line:** a monthly Diamond finish (1,000) is one Rare
   item, about $9.90; Bronze (100) equals the $0.99 pack.
5. **Daily reward and Gold Rush are in line:** a week of daily rewards is
   about $1; a Gold Rush round about $0.69.
6. **Trophies** pay no coins, so nothing to change. "Nest Egg" (hold 1,000
   coins at once) can now be reached by buying the 1,300-coin pack; before,
   the 750-coin pack almost reached it. Purchases never count toward
   "Working Capital" (coins earned from play).
7. **Sell Back** returns half the coin price, as before. Selling a bought
   Legendary item returns 750 coins, about $7.42 at the smallest pack rate.
   Fine, because it is a refund of coins already spent.
8. **Top coin pack bonus item:** the code grants the Money Ball skin the
   first time only, and the pack card says "Includes the Money Ball skin".
   Older research notes describe a random Money ball, trail or floor; the
   code does not do that. Make sure the App Store Connect description says
   the Money Ball skin is included.

## Recommendations (not built)

- **Decided and built (2026-11-18):** Starter Pack Option B (Aurora ball,
  trail and boundary + 500 coins, $1.99; granted by
  `StoreKitManager.grantStarterPackItems`). Cosmetic prices stay; the 100- and
  600-coin packs show "Top up your balance" on the Get Coins sheet. The
  Money Ball stays in the 10,000-coin pack.
- Keep clan prizes, the daily reward, Gold Rush and trophies as they are.
