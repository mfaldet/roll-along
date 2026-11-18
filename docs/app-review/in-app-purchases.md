# In-app purchases for Roll Along 1.0

Ten products. The product IDs, rewards and prices below are read from
`RollAlong/StoreKitManager.swift` and `RollAlong/Products.storekit`. The
product IDs in App Store Connect must match these exactly, or the app will not
find them.

| # | Product ID | Type | Name | Price (USD) | What it gives | Screen to screenshot |
|---|---|---|---|---|---|---|
| 1 | `com.macfaldet.RollAlong.lives.pack20` | Consumable | 20 Lives | $1.99 | 20 lives | Get Lives sheet |
| 2 | `com.macfaldet.RollAlong.lives.pack120` | Consumable | 120 Lives | $9.99 | 120 lives | Get Lives sheet |
| 3 | `com.macfaldet.RollAlong.lives.pack300` | Consumable | 300 Lives | $19.99 | 300 lives | Get Lives sheet |
| 4 | `com.macfaldet.RollAlong.unlimited` | Non-consumable | Diamond Balls | $49.99 | Unlimited lives forever, plus the Diamond ball skin | Get Lives sheet, scrolled so Diamond Balls is visible |
| 5 | `com.macfaldet.RollAlong.coins.100` | Consumable | 100 Coins | $0.99 | 100 coins | Get Coins sheet |
| 6 | `com.macfaldet.RollAlong.coins.600` | Consumable | 600 Coins | $4.99 | 600 coins | Get Coins sheet |
| 7 | `com.macfaldet.RollAlong.coins.1300` | Consumable | 1,300 Coins | $9.99 | 1,300 coins | Get Coins sheet |
| 8 | `com.macfaldet.RollAlong.coins.3000` | Consumable | 3,000 Coins | $19.99 | 3,000 coins | Get Coins sheet |
| 9 | `com.macfaldet.RollAlong.coins.10000` | Consumable | 10,000 Coins | $49.99 | 10,000 coins, plus the Money Ball skin the first time | Get Coins sheet, with the line "Includes the Money Ball skin" visible |
| 10 | `com.macfaldet.RollAlong.starterpack` | Non-consumable | Starter Pack | $1.99 | 500 coins and the Aurora ball, trail and boundary (one time only) | Starter Pack offer sheet |

The number in each lives product ID is the number of lives it grants
(`lives.pack20`, `lives.pack120`, `lives.pack300`). They replace the earlier
draft lives products, which are to be deleted in App Store Connect. Once created, a product ID can never change.

The number in each coin product ID is the number of coins it grants
(`coins.100` gives 100 coins, and so on), matching App Store Connect.

**Get Coins sheet bonus labels.** Each pack after the first shows how many
more coins per dollar it gives than the 100-coin pack, rounded down to a
whole percent. Base rate: 100 ÷ $0.99 = 101.01 coins per dollar.

| Pack | Same money in 100-coin packs | Bonus | Label |
|---|---|---|---|
| 600 for $4.99 | 101.01 × 4.99 = 504.0 | 600 ÷ 504.0 = 1.190 | +19% coins |
| 1,300 for $9.99 | 101.01 × 9.99 = 1,009.1 | 1,300 ÷ 1,009.1 = 1.288 | +28% coins |
| 3,000 for $19.99 | 101.01 × 19.99 = 2,019.2 | 3,000 ÷ 2,019.2 = 1.486 | +48% coins |
| 10,000 for $49.99 | 101.01 × 49.99 = 5,049.5 | 10,000 ÷ 5,049.5 = 1.980 | +98% coins |

The 100-coin pack shows no bonus label.

**Top-up line.** The 100- and 600-coin packs can't buy a cosmetic on their own
(the cheapest is 750 coins), so their cards also show a gray line under the
amount: **"Top up your balance"**. The 600-coin card shows both "+19% coins"
and that line. The other three packs show no top-up line.

## Paste into App Store Connect

Display Name limit: 30 characters. Description limit: 55 characters. Counts
include spaces and punctuation. `RollAlong/Products.storekit` uses exactly the
same text.

| # | Product ID | Display Name (chars) | Description (chars) |
|---|---|---|---|
| 1 | `com.macfaldet.RollAlong.lives.pack20` | 20 Lives (8) | 20 extra lives, used when your free lives run out. (50) |
| 2 | `com.macfaldet.RollAlong.lives.pack120` | 120 Lives (9) | 120 extra lives, used when your free lives run out. (51) |
| 3 | `com.macfaldet.RollAlong.lives.pack300` | 300 Lives (9) | 300 extra lives, used when your free lives run out. (51) |
| 4 | `com.macfaldet.RollAlong.unlimited` | Diamond Balls (13) | Unlimited lives forever, plus the Diamond ball skin. (52) |
| 5 | `com.macfaldet.RollAlong.coins.100` | 100 Coins (9) | 100 coins to spend on cosmetics in the Shop. (44) |
| 6 | `com.macfaldet.RollAlong.coins.600` | 600 Coins (9) | 600 coins to spend on cosmetics in the Shop. (44) |
| 7 | `com.macfaldet.RollAlong.coins.1300` | 1,300 Coins (11) | 1,300 coins to spend on cosmetics in the Shop. (46) |
| 8 | `com.macfaldet.RollAlong.coins.3000` | 3,000 Coins (11) | 3,000 coins to spend on cosmetics in the Shop. (46) |
| 9 | `com.macfaldet.RollAlong.coins.10000` | 10,000 Coins (12) | 10,000 coins, plus the Money Ball skin the first time. (54) |
| 10 | `com.macfaldet.RollAlong.starterpack` | Starter Pack (12) | One-time: Aurora ball, trail, boundary and 500 coins. (53) |

## How to reach each screen

- **Get Lives sheet:** Home screen → tap the lives counter at the top-left.
- **Get Coins sheet:** Home → Shop → tap the coin balance at the top-right.
- **Starter Pack offer sheet:** appears by itself on the Home screen the first
  time the coin balance reaches 250, and can be reopened for 48 hours. On a
  fresh install, the quickest route is to buy the 600-coin pack with the local
  StoreKit test configuration and go back to Home.

## What the Starter Pack sheet shows

A "WELCOME GIFT" badge, the Aurora ball, the title "Aurora" and the line "Ball ·
Trail · Boundary — plus 500 coins". Two rows list what is included: "Aurora
ball, trail and boundary — Worth 4,500 coins in the shop" (the figure is the
three items' shop prices added up by the app) and "500 coins — Spend in the
cosmetics shop". Then the 48-hour countdown, the price button "$1.99 — Claim
Offer", and "No thanks".

When it appears and stops appearing is unchanged: on Home, the first time the
coin balance reaches 250, open for 48 hours. It never appears again once
bought or after "No thanks", and it is not offered to a player who already owns
the Aurora ball, trail and boundary. The three items are gifts: Sell Back keeps
them and never refunds them. The rest of the Aurora collection stays on sale
for coins. Changed on 2026-11-18 from 3,750 coins and the full Aurora
collection; retake its review screenshot.

## What the Get Lives sheet shows

Under the "Get Lives" title, the line "You earn 1 life every 6 minutes, up to
10." sits above the row of 10 life balls and the "x / 10" count. Lives bought
earlier and not yet used show as a small gold jar with "+N" next to that row;
tapping it explains that they are used when the free lives run out.

Each lives pack is one card: a "guess how many marbles" jar (a small jar with a
few marbles for 20, a medium, fuller jar for 120, a large jar packed full for
300), the number of lives, the percent saved per life against the 20-life
pack, and the price button. With the prices above the cards read "20 Lives"
(no savings line), "120 Lives · Save 16%" and "300 Lives · Save 33%". The
percentages are computed from the live App Store prices, so they change if a
price changes:

- 20 lives: $1.99 ÷ 20 = $0.0995 a life (the base, no savings line)
- 120 lives: $9.99 ÷ 120 = $0.08325 a life; 1 − 0.08325 ÷ 0.0995 = 16.3%, shown as 16%
- 300 lives: $19.99 ÷ 300 = $0.0666 a life; 1 − 0.0666 ÷ 0.0995 = 33.0%, shown as 33%

Diamond Balls is a separate card below the packs, under the heading "OR NEVER
RUN OUT". It says "Indestructible. Unlimited lives, forever." and names the
Diamond ball skin. It shows no savings figure. Once it is owned, the packs are
hidden and the sheet shows only a "You own Diamond Balls" card.

The lives cards, prices and product IDs changed on 2026-11-18. Any screenshot
of the Get Lives sheet taken before that must be retaken for products 1 to 4.
Take them before buying Diamond Balls on the test account, or the packs will
not be shown.

## Screenshot rules (from Apple's App Store Connect Help)

- One review screenshot is required per product. It is used for review only
  and is not shown on the App Store.
- It must clearly show the item being offered. The same sheet can be used for
  several products as long as each product is visible in its own screenshot.
- Take them on the iPhone, from the build you will submit.

## Things to get right in App Store Connect

- The first purchase of each type (consumable, non-consumable) must be
  submitted together with the app version. Attach all ten to version 1.0.
- Display names and descriptions are what players see in the purchase sheet.
  For product 9, say in the description that the Money Ball skin is included,
  so the store text matches the in-app card.
- Product 4's description should mention the Diamond ball skin for the same
  reason, and product 10's should list the coins and the three Aurora items.
  Use the "Paste into App Store Connect" table above.
- Non-consumables (4 and 10) are restored by Settings → Purchases → Restore
  Purchases.

## Not verified

- The screen and button names above come from reading the code. Confirm them
  on the phone.
- Whether the Get Lives sheet shows Diamond Balls without scrolling.
- How the new jars and the gold reserve jar look on the phone.
