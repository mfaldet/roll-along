# Payout audit — 2026-11

For every reward, price and purchase: what the screen (or the review notes /
App Store text) says, and what the code or server actually pays.  Traced by
reading the code at `7f3d942` plus the server SQL; the server side of clan
prizes was also run on a local Postgres 16 copy (steps 13–19).

Legend: ✅ match · 🔧 mismatch, fixed in this audit.

## 1. Minigames (`CoinPayouts`, `GameState.recordMinigameResult`)

| Item | Screen says | Code pays | Match? | Fix |
|---|---|---|---|---|
| Competitive coins (Sumo, Paint Ball, Smash and Grab, Marble Cup, King of the Hill, Snacky E/N/H) | End screen "+N coins" = the banked amount; review notes "1, 2 or 3 on Easy, Normal, Hard whatever the result" | 1 / 2 / 3 by difficulty, any result, via the one choke point | ✅ | — |
| Ticket per win | Games menu "Every win earns 1 ticket"; Snacky end screen "+1 ticket" on a win only | `recordCompetitiveWin` adds 1 on a win; loss or draw 0 | ✅ | — |
| Solo games (Roll Up, Disco Ball, Zen Garden, Snacky Solo) | "Solo minigames pay no coins"; no coin line shown | 0 (Roll Up / Disco show "+N" only when N > 0) | ✅ | — |
| Personal-best bonus | Not shown | 0 | ✅ | — |

## 2. Gold Rush (`BallGameView` coin pit)

| Item | Screen says | Code pays | Match? | Fix |
|---|---|---|---|---|
| Round cost | "A round costs 5 tickets"; "+30 s for 5 tickets" | 5 tickets per 30-second block | ✅ | — |
| ×2 boost | "Double your coins mid-round for 10 tickets" | 10 tickets; back-pays the haul so far, then ×2 per catch | ✅ | — |
| Payout | Stake screen "everything you catch is yours" | 1 coin per coin caught, up to 100 per block | ✅ | — |
| Payout (review notes) | "pays up to about 100 coins" | up to 100 per block, ×2 with the boost | 🔧 | Review notes now say "each coin caught pays 1 coin (up to 100), or 2 after an optional 10-ticket boost" |
| Early exit refund | — | Full unplayed blocks refunded; boost never | ✅ | — |

## 3. Levels, streaks, challenges, trophies

| Item | Screen says | Code pays | Match? | Fix |
|---|---|---|---|---|
| Adventure clear | Level Clear "+N coins" (`lastClearedCoinReward`) | 2 / 3 / 4 by tier + 1 per new pickup (tutorial bonus counted once) | ✅ | — |
| Challenge Track level | "+N coins" | 2 + 1 per pickup | ✅ | — |
| Challenge Track completion | Reward card "Complete to Earn — <collection>" | Grants the collection | 🔧 | Items were granted as ordinary items, so **Sell Back refunded half the collection's price** for a free reward. Now granted as a gift (`grantBundleFree`): kept by Sell Back, refunds nothing; pieces already bought are compensated first |
| Daily reward | Ladder tiles and "Claim N coins" | Same ladder 5/8/10/12/15/20/35 | ✅ | — |
| Trophies | Review notes "never grant coins or purchasable items" | No trophy path calls `addCoins` | ✅ | — |
| Challenge of the Day | Hidden for 1.0 | — | n/a | — |

## 4. Clan season prizes (server)

| Item | Screen says | Server pays | Match? | Fix |
|---|---|---|---|---|
| Tier amounts | Rankings card: Diamond 1000 · Gold 500 · Silver 250 · Bronze 100 (built into the app) | `ra_config` season_coins_* — but `social-schema-v5.sql` inserts them with "on conflict do nothing", so an older value on the live database would win | 🔧 | **Step 19** (`docs/economy/season-prize-settings.sql`) sets the four rows to 1000/500/250/100 and adds them to `ra_social_settings`; the card now shows the server's numbers |
| Who qualifies | Info: "coins for each member who helped" | Member at month end with ≥ 10 season stars | 🔧 | Info text now says "each member still in the clan who earned at least N of those stars" (N from the server) |
| Claim | "Claim N coins" = the prize row's coins | `ra_claim_season_prize` returns that row's coins once, then 0 | ✅ (local test: 1000, then 0) | — |
| Warm-up December 2026 | "Warm-up month · no prizes" | `season_prizes_from` 202701 → no prize rows | ✅ | — |

## 5. Shop and collections

| Item | Screen says | Code charges / refunds | Match? | Fix |
|---|---|---|---|---|
| Item price | Tile and Buy button: `coinCost` | Charges `coinCost` (750 / 1,000 / 1,250 / 1,500 by tier) | ✅ | — |
| Collection price | Catalog: prorated price; Shop: discounted featured price | `purchaseBundle(price:)` gets the same `bundleCost` the button shows; music not charged | ✅ | — |
| Ball pack | `pack.price` | Same, 66% of members floored to 20 | ✅ | — |
| Not-enough-coins alert | "…or buy a coin pack (coming with the next update)" | Coin packs exist | 🔧 | Now "…or buy a coin pack." |
| Sell Back | Alert: "half their current coin value … Only your Iconic items are kept" | Half the current price, never more than paid; also keeps gifts (tutorial gift, Starter Pack items, now Challenge Track rewards) | 🔧 | Alert now says "(never more than you paid)" and lists gifts as kept |

## 6. Purchases (`StoreKitManager`, `Products.storekit`)

| Product | Screen / store text | Code grants | Match? | Fix |
|---|---|---|---|---|
| lives.pack20 / 120 / 300 | "20 / 120 / 300 Lives", $1.99 / $9.99 / $19.99 | 20 / 120 / 300 reserve lives | ✅ | — |
| unlimited (Diamond Balls) | Store: "Unlimited lives forever, plus the Diamond ball skin"; card: "Indestructible. Unlimited lives, forever." | Unlimited lives + Diamond ball (also on restore) | 🔧 | Card now says "Unlimited lives, forever, plus the Diamond ball skin."; review notes mention the skin |
| coins.100 … coins.10000 | "100 … 10,000 Coins"; bonus labels | 100 / 600 / 1,300 / 3,000 / 10,000 | ✅ | — |
| Money Ball | "Includes the Money Ball skin" (until owned); store "the first time" | Granted on the first 10,000 purchase only | ✅ | Stale code comment ("random Money cosmetic, up to three") corrected |
| starterpack | "Ball · Trail · Boundary — plus 500 coins", "Worth 4,500 coins in the shop" | 500 coins once + Aurora ball, trail, boundary as gifts; restore gives the items, not the coins | ✅ | — |

## 7. Lives

| Item | Screen says | Code | Match? | Fix |
|---|---|---|---|---|
| Free lives | "You earn 1 life every 6 minutes, up to 10." | 360 s, cap 10 | ✅ | — |
| Rewarded ad | "Watch ad — +1 life" | `addLives(1)` on reward | ✅ | — |
| Clan life request | "Up to 6 lives, one from each clanmate. Closes after 24 hours." | Server: size 6, 24 h, one per giver; each gift amount 1 | ✅ | — |
| Claiming a gift | "Claimed N life/lives" = gift amount | `addLives(gift.amount)` | ✅ | — |

## Totals

33 items checked: 25 matched, 7 mismatches fixed (one needs database step 19), 1 not in 1.0.
