# In-app purchases for Roll Along 1.0

Ten products. The product IDs, rewards and prices below are read from
`RollAlong/StoreKitManager.swift` and `RollAlong/Products.storekit`. The
product IDs in App Store Connect must match these exactly, or the app will not
find them.

| # | Product ID | Type | Name | Price (USD) | What it gives | Screen to screenshot |
|---|---|---|---|---|---|---|
| 1 | `com.macfaldet.RollAlong.lives.pack1` | Consumable | 10 Lives | $0.99 | 10 lives added to the reserve | Buy Lives sheet |
| 2 | `com.macfaldet.RollAlong.lives.pack5` | Consumable | 60 Lives | $4.99 | 60 lives | Buy Lives sheet |
| 3 | `com.macfaldet.RollAlong.lives.pack10` | Consumable | 130 Lives | $9.99 | 130 lives | Buy Lives sheet |
| 4 | `com.macfaldet.RollAlong.unlimited` | Non-consumable | Unlimited Lives | $19.99 | Lives never run out, plus the Diamond ball skin | Buy Lives sheet, scrolled so Unlimited Lives is visible |
| 5 | `com.macfaldet.RollAlong.coins.100` | Consumable | 750 coins | $0.99 | 750 coins | Get Coins sheet |
| 6 | `com.macfaldet.RollAlong.coins.600` | Consumable | 4,500 coins | $4.99 | 4,500 coins | Get Coins sheet |
| 7 | `com.macfaldet.RollAlong.coins.1300` | Consumable | 10,000 coins | $9.99 | 10,000 coins | Get Coins sheet |
| 8 | `com.macfaldet.RollAlong.coins.3000` | Consumable | 22,500 coins | $19.99 | 22,500 coins | Get Coins sheet |
| 9 | `com.macfaldet.RollAlong.coins.10000` | Consumable | 60,000 coins | $49.99 | 60,000 coins, plus the Money Ball skin the first time | Get Coins sheet, with the line "Includes the Money Ball skin" visible |
| 10 | `com.macfaldet.RollAlong.starterpack` | Non-consumable | Starter Pack | $1.99 | 3,750 coins and the Aurora collection (ball, goal, trail, floor, pit, music) | Starter Pack offer sheet |

The numbers in some product IDs (`coins.100`, `coins.600` and so on) are
historical and do not match the coin amounts. That is fine: players never see
the ID. Do not rename them.

## How to reach each screen

- **Buy Lives sheet:** Home screen → tap the lives counter at the top-left.
- **Get Coins sheet:** Home → Shop → tap the coin balance at the top-right.
- **Starter Pack offer sheet:** appears by itself on the Home screen the first
  time the coin balance reaches 250, and can be reopened for 48 hours. On a
  fresh install, the quickest route is to buy the 750-coin pack with the local
  StoreKit test configuration and go back to Home.

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
  reason, and product 10's should list the coins and the Aurora collection.
- Non-consumables (4 and 10) are restored by Settings → Purchases → Restore
  Purchases.

## Not verified

- The screen and button names above come from reading the code. Confirm them
  on the phone.
- Whether the Buy Lives sheet shows Unlimited Lives without scrolling.
