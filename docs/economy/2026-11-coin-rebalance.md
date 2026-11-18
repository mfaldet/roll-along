# 2026-11 coin rebalance: minigames pay tickets, not coins

**Status:** Part A is built (minigame payouts). Everything under "Proposals"
is a proposal only; nothing there is changed yet.

**Update 2026-11-18:** the coin packs now grant what App Store Connect sells
(100 / 600 / 1,300 / 3,000 / 10,000 coins), not the 750 to 60,000 below.
See `2026-11-iap-coin-rates.md` for dollar values and the Starter Pack
proposal. Pack figures further down this page are the old amounts.

## The rule

- Every minigame pays **1 to 5 coins a game**, about what one Adventure level
  pays.
- A competitive **win also earns 1 ticket** (unchanged).
- **Gold Rush**, paid for with tickets, is the place for larger amounts:
  about 100 coins a round at most.
- Cosmetics are unchanged: Standard 750, Rare 1,000, Premium 1,250,
  Legendary 1,500 coins.

## What one Adventure level pays (the yardstick)

From `GameState.clearCoins(for:)` and `coinPerPickup`:

| Part | Coins |
|---|---|
| Clear, every time (first or replay), by the level's tier: easy / hard / very hard | 2 / 3 / 4 |
| Each coin picked up on the floor (up to 3 per level, first time only) | 1 |

A first clear pays 2 to 7; a replay pays 2 to 4. Over a normal session
(mostly new levels, some pickups missed) a level averages about **3.5 coins**.

## Part A: minigame payouts as built (`CoinPayouts` in `GameState.swift`)

**Competitive games** (Comet Clash, Sumo Survival, Paint Ball, Smash and Grab,
Marble Cup, King of the Hill):

| Result | Easy | Normal | Hard | Ticket |
|---|---|---|---|---|
| Win (1st) | 3 | 4 | 5 | +1 |
| 2nd or 3rd of 4 | 2 | 2 | 2 | — |
| Last (4th of 4; 2nd of 2 in Marble Cup) | 1 | 1 | 1 | — |
| Marble Cup draw after sudden death | 2 | 2 | 2 | — |

Placement comes from each game's own result: Comet Clash by how many comets
outlived you, Sumo Survival by match points, Paint Ball by floor covered,
Smash and Grab by coins grabbed, King of the Hill by hold time. Marble Cup is
two-sided, so a loss is last place.

**Solo games:**

| Game | Pays |
|---|---|
| Roll Up | 1 coin, +1 per 40 m climbed, at most 5 (0 m pays nothing) |
| Disco Ball | 1 coin, +1 per 4 crossings, at most 5 (0 crossings pays nothing) |
| Zen Garden | 1 coin per full minute in the garden, at most 5 a visit |
| Roll Out (held back from 1.0) | 3 per maze cleared |

**Removed:** the 100-coin personal-best bonus (Roll Up, Disco Ball, Gold Rush,
Roll Out). The best is still recorded and shown. The difficulty multiplier
(1× / 1.5× / 2×) is gone; difficulty now sets the win payout directly.

**Gold Rush** is unchanged in shape: one time ticket buys a 30-second round in
which 100 coins fall; each coin caught pays 1 (2 after the in-round ×2 buy,
which costs 2 more tickets). A strong round catches 80 to 100; an average
round about 50 to 70. Only its 100-coin new-best bonus is removed, so a round
can no longer pay about 200.

## Proposals (not built)

### 1. Every way a player gets coins

| Source | Today | Under the new rule |
|---|---|---|
| Adventure level | 2–4 per clear + 1 per pickup (≤3, first time) | Same |
| Challenge Track level | 2 per clear + 1 per pickup; finishing a track grants a collection (cosmetics, no coins) | Same |
| Comet Clash | 3 × power + 20 on a win, × 1 / 1.5 / 2 by difficulty (Normal win ~45–65) | 1–5 (table above) |
| Sumo Survival | 60 / 30 / 15 / 8 by placing, × multiplier | 1–5 |
| Paint Ball | coverage % + 20 on a win, × multiplier (Normal win ~70) | 1–5 |
| Smash and Grab | coins grabbed + 15 on a win, × multiplier (Normal win ~45) | 1–5 |
| Marble Cup | 15 per goal + 30 on a win, at least 15, × multiplier | 1–5 |
| King of the Hill | 2 per second held + 15 on a win, × multiplier (Normal win ~55) | 1–5 |
| Roll Up | 0.2 per meter, up to 250, + 100 on a new best | 1–5 |
| Disco Ball | 3 per crossing + 100 on a new best | 1–5 |
| Zen Garden | 1 per minute, up to 15 a visit | 1 per minute, up to 5 |
| Gold Rush (1 ticket) | 1 per coin caught (×2 option), up to ~100, + 100 on a new best | Same, without the best bonus |
| Daily reward ladder | 5, 8, 10, 12, 15, 20, 35 (days 1–7, repeating; 15 a day on average) | Same |
| Clan battle (monthly, per eligible member) | Diamond 3,000 · Gold 1,500 · Silver 750 · Bronze 250 | See proposal 3 |
| Trophies | None (no trophy grants coins; checked in `TrophyCatalog.swift`) | None |
| Rewarded ad | Lives only, no coins | Same |
| Life gifts | Lives only | Same |
| Sell Back | Half the price paid (a refund, not income) | Same |
| Collection gift compensation | Coins back for pieces already bought when a collection is given free (a refund) | Same |
| Challenge of the Day (held back) | 30 per clear | Not in 1.0 |
| Starter Pack ($1.99) | 3,750 coins + the Aurora collection | Same |
| Coin packs | 750 ($0.99), 4,500 ($4.99), 10,000 ($9.99), 22,500 ($19.99), 60,000 ($49.99, plus the Money Ball skin the first time) | **Changed 2026-11-18:** 100, 600, 1,300, 3,000, 10,000 (App Store Connect amounts) |

### 2. Days to one 1,000-coin cosmetic for a free player at about 20 minutes a day

**Assumptions** (estimates, not measured):

- An Adventure level takes about 45 seconds including retries and the result
  screen, and pays about 3.5 coins.
- A competitive game takes about 80 seconds including menus; the player picks
  Normal and wins about half the time.
- A Gold Rush round takes about 45 seconds including the stake screen and
  catches about 70 coins.
- The daily reward averages 105 ÷ 7 = 15 coins a day.

**Player A, mixed: 10 minutes of Adventure, 10 minutes of minigames.**

- Adventure: 600 s ÷ 45 s ≈ 13 levels × 3.5 ≈ **46 coins**.
- Minigames: about 6 competitive games (480 s) and 2 Gold Rush rounds (90 s),
  using the 3 tickets won.
  - Today: 6 games × about 35 average (Normal, wins and losses) ≈ **210**;
    Gold Rush 2 × 70 = **140**.
  - New: 3 wins × 4 + 3 losses × 1.5 ≈ **17**; Gold Rush unchanged, **140**.
- Daily reward: **15**.
- **Today:** 46 + 210 + 140 + 15 ≈ **411 a day** → 1,000 ÷ 411 ≈ **2.4 days**.
- **New:** 46 + 17 + 140 + 15 ≈ **218 a day** → 1,000 ÷ 218 ≈ **4.6 days**.

**Player B, Adventure only: 20 minutes.**

- 1,200 s ÷ 45 s ≈ 27 levels × 3.5 ≈ 94, plus 15 daily ≈ **109 a day** →
  **9.2 days**, today and after (Adventure is unchanged).

**Player C, minigames only: 20 minutes** (about 12 competitive games and 5
Gold Rush rounds with the 6 tickets won, about 1,200 s).

- Today: 12 × 35 + 5 × 70 + 15 ≈ 785 a day → **1.3 days**.
- New: (6 × 4 + 6 × 1.5) + 5 × 70 + 15 ≈ 33 + 350 + 15 ≈ 398 a day →
  **2.5 days**.

**Range:** about **2.5 to 9 days** after the change, against **1.3 to 9 days**
today. The change mostly removes the minigame shortcut; Adventure players are
unaffected. Gold Rush now carries most minigame income, so the ticket supply
(1 per competitive win) is the lever to watch.

### 3. Clan battle prizes

So a monthly first place (Diamond) is worth about one cosmetic:

| Tier | Today | Proposed |
|---|---|---|
| Diamond | 3,000 | **1,000** |
| Gold | 1,500 | **500** |
| Silver | 750 | **250** |
| Bronze | 250 | **100** |

These are rows in the `ra_config` table (`season_coins_*`), so they change in
the Supabase dashboard with no app update. The text in the review notes and
the social design document would need the new numbers too.

### 4. Coin trophies

| Trophy | Rule | Counts | Days to earn after the change | Suggestion |
|---|---|---|---|---|
| Nest Egg (Bronze) | Hold 1,000 coins at once | Balance high-water | About 4.6 (A), 9.2 (B) | Keep at 1,000 |
| Working Capital (Bronze) | Earn 5,000 coins from play | Play and daily-reward coins only (no purchases, refunds or gift compensation) | About 23 (A), 46 (B); today about 12 (A) | Lower to **2,500** (about 11 days for A, 23 for B) |
| Pit Boss (Silver) | Catch 2,500 coins in Gold Rush | Gold Rush catches only | About 36 rounds ≈ 36 tickets ≈ 72 competitive games at a 50% win rate: about 18 days for A | Keep (Gold Rush is unchanged) |
| Cloudburst (Silver) | Catch 90 in one Gold Rush round | Single round | Unchanged | Keep |
| Punch Card (Bronze) | Claim 30 daily rewards | Claims, not coins | Unchanged | Keep |

No other trophy counts coins.

### 5. Coin packs after the change

Price per 1,000-coin cosmetic, and how many days of free play each pack
equals (using Player A's 411 coins a day today and 218 after, and Player B's
109):

| Pack | Coins | Price | Price per 1,000 coins | Days for A today | Days for A after | Days for B (unchanged) |
|---|---|---|---|---|---|---|
| Small | 750 | $0.99 | $1.32 | 1.8 | 3.4 | 6.9 |
| Starter Pack | 3,750 + Aurora collection | $1.99 | $0.53 (coins only) | 9.1 | 17.2 | 34.4 |
| Medium | 4,500 | $4.99 | $1.11 | 10.9 | 20.6 | 41.3 |
| Large | 10,000 | $9.99 | $1.00 | 24.3 | 45.9 | 91.7 |
| Huge | 22,500 | $19.99 | $0.89 | 54.7 | 103 | 206 |
| Top | 60,000 (+ Money Ball) | $49.99 | $0.83 | 146 | 275 | 550 |

The price of a cosmetic in dollars does not change. What changes is that a
pack now stands for about twice as many days of mixed play, so packs look
better value against grinding minigames. The two largest packs now equal
more than three months of mixed play; consider whether they are still
needed at 1.0.

---

## Round 2 (built, 2026-11-17)

The ticket route was still far faster than Adventure (about 1,300 coins an
hour against 280). Changes, all in `CoinPayouts` (`RollAlong/GameState.swift`)
unless noted:

- **Every minigame pays at most 3 coins.** Competitive, on every difficulty:
  win 3 (+1 ticket), any middle place 2 (including a non-winning first place),
  last 1, Marble Cup draw 2. Solo: Roll Up 1 / 2 from 60 m / 3 from 150 m;
  Disco Ball 1 / 2 from 5 crossings / 3 from 12; Zen Garden 1 a minute, up
  to 3 a visit. A new best pays no bonus.
- **Gold Rush costs 5 tickets a round** (each extra 30 seconds also 5; the
  ×2 boost 10; an early quit refunds 5 per full un-played block). Payout
  unchanged: 1 per coin caught, up to about 100 a round. "Can't play" now
  means fewer than 5 tickets.
- **Clan battle prizes** (defaults in `docs/social-schema-v5.sql`): Diamond
  1,000, Gold 500, Silver 250, Bronze 100.
- **Working Capital**: 2,500 coins earned from play.
- **High Roller** (secret): 15 tickets on one round (three 30-second blocks);
  at 5 tickets a round, the old "5 tickets" would have latched on every round.
  **Round 3:** 25 tickets on one round, counting the time blocks plus the ×2
  boost (10) — five rounds' worth, the same as the original 5 when a round
  cost 1.  The most one round can take is 995 tickets: the balance is capped at
  999, so either 199 blocks (995) with no boost, or 197 blocks (985) plus the
  10-ticket boost.  25 is reachable, for example three blocks and the boost,
  or five blocks.

### Assumptions (as before)

Adventure level 45 s, 3.5 coins. Competitive game 80 s. Gold Rush round
about 60 s including the stake screen, about 70 coins. Daily reward 15 a
day. Win rates are the targets in `MinigameDifficulty.targetWinRate`: Easy
70%, Normal 50%, Hard 30%. A loss is a middle place two times in three
(2 coins) and last one time in three (1 coin): 1.67 coins on average.

### Coins per competitive game

| | Win rate | Coins per game |
|---|---|---|
| Easy | 70% | 0.7 × 3 + 0.3 × 1.67 = 2.60 |
| Normal | 50% | 0.5 × 3 + 0.5 × 1.67 = 2.33 |
| Hard | 30% | 0.3 × 3 + 0.7 × 1.67 = 2.07 |

### Tickets per hour (competitive games only)

3,600 ÷ 80 = 45 games an hour. Easy 45 × 0.7 = **31.5**, Normal 45 × 0.5 =
**22.5**, Hard 45 × 0.3 = **13.5** tickets an hour.

### Coins per hour

| Player | Cycle | Coins per cycle | Per hour, after | Before |
|---|---|---|---|---|
| Adventure only | 1 level = 45 s | 3.5 | 3,600 ÷ 45 × 3.5 = **280** | 280 |
| Ticket loop, Easy | 5 ÷ 0.7 = 7.1 games (571 s) + 1 Gold Rush (60 s) = 631 s | 7.1 × 2.60 + 70 = 88.6 | 88.6 × 3,600 ÷ 631 = **505** | about 1,300 |
| Ticket loop, Normal | 10 games (800 s) + 60 s = 860 s | 10 × 2.33 + 70 = 93.3 | **391** | about 1,300 |
| Ticket loop, Hard | 16.7 games (1,333 s) + 60 s = 1,393 s | 16.7 × 2.07 + 70 = 104.5 | **270** | about 1,300 |
| Mix: half Adventure, half Normal loop | | | (280 + 391) ÷ 2 = **335** | about 790 |

The ticket loop on Normal is now about 1.4 times Adventure, not 4.6 times;
on Hard it is slightly below Adventure.

### Days to a 1,000-coin cosmetic at 20 minutes a day (daily reward included)

| Player | Coins a day | Days, after | Days, before |
|---|---|---|---|
| Adventure only | 280 ÷ 3 + 15 = 108 | **9.2** | 9.2 |
| Ticket loop, Easy | 505 ÷ 3 + 15 = 183 | **5.5** | about 1.3 to 2.5 |
| Ticket loop, Normal | 391 ÷ 3 + 15 = 145 | **6.9** | about 2.5 |
| Ticket loop, Hard | 270 ÷ 3 + 15 = 105 | **9.5** | |
| Mix (10 min Adventure + 10 min Normal loop) | 46.7 + 65.2 + 15 = 127 | **7.9** | 4.6 |

Tickets carry over between days, so a 20-minute session that ends partway
through a 14-minute Normal cycle loses nothing.

### Trophies under round 2

- **Working Capital (2,500 from play):** about 23 days Adventure only, 20 for
  the mix, 17 on the Normal loop.
- **Pit Boss (2,500 caught in Gold Rush):** about 36 rounds at 70 a round =
  180 tickets = 360 Normal games. That is about 26 days of 20-minute Normal
  ticket-loop play, or about 51 days for the mix. Still reachable, but slow
  for a Silver. **Lowered to 1,000 in round 3** (about 14 rounds, 10 days on
  the Normal loop).
- **Pit Stop** (play one Gold Rush round) now needs 5 wins first; fine.
- **Cloudburst** (90 in one round) is unaffected.

## Round 3 (built, 2026-11-18)

Simpler rule, all in `CoinPayouts` (`RollAlong/GameState.swift`):

- **Solo minigames pay no coins**: Roll Up, Disco Ball, Zen Garden and
  Snacky's Solo option. They are played for a best score only.
- **A competitive game pays by difficulty, whatever the result**: Easy 1,
  Normal 2, Hard 3. A win, a loss, a draw and every placement pay the same.
- **A competitive win also earns 1 ticket.** A loss or a draw earns none.
- Gold Rush unchanged: 5 tickets a round, 1 coin per coin caught, about 70
  a round on average (up to about 100).

### Assumptions (same as round 2)

Adventure level 45 s, 3.5 coins. Competitive game 80 s. Gold Rush round
about 60 s including the stake screen, about 70 coins. Daily reward 15 a
day. Win rates Easy 70%, Normal 50%, Hard 30%. A 20-minute day is one third
of an hour.

### Coins per competitive game

| | Round 3 | Round 2 |
|---|---|---|
| Easy | **1** | 0.7 × 3 + 0.3 × 1.67 = 2.60 |
| Normal | **2** | 0.5 × 3 + 0.5 × 1.67 = 2.33 |
| Hard | **3** | 0.3 × 3 + 0.7 × 1.67 = 2.07 |

### Tickets per hour (competitive games only, unchanged)

3,600 ÷ 80 = 45 games an hour. Easy 45 × 0.7 = **31.5**, Normal 45 × 0.5 =
**22.5**, Hard 45 × 0.3 = **13.5**.

### Coins per hour

A ticket-loop cycle is the games needed to win 5 tickets (5 ÷ win rate),
then one Gold Rush round.

| Player | Cycle | Coins per cycle | Per hour, round 3 | Round 2 |
|---|---|---|---|---|
| Adventure only | 1 level = 45 s | 3.5 | 3,600 ÷ 45 × 3.5 = **280** | 280 |
| Ticket loop, Easy | 5 ÷ 0.7 = 7.14 games (7.14 × 80 = 571 s) + 60 s = 631 s | 7.14 × 1 + 70 = 77.1 | 77.1 × 3,600 ÷ 631 = **440** | 505 |
| Ticket loop, Normal | 5 ÷ 0.5 = 10 games (800 s) + 60 s = 860 s | 10 × 2 + 70 = 90.0 | 90.0 × 3,600 ÷ 860 = **377** | 391 |
| Ticket loop, Hard | 5 ÷ 0.3 = 16.67 games (1,333 s) + 60 s = 1,393 s | 16.67 × 3 + 70 = 120.0 | 120.0 × 3,600 ÷ 1,393 = **310** | 270 |
| Mix: half Adventure, half Normal loop | | | (280 + 376.7) ÷ 2 = **328** | 335 |
| Solo minigames | any | 0 | **0** | about 135 to 150 |

The difficulty order now runs the right way: Hard pays the most per hour of
the three loops, Easy the least. Every loop stays within about 1.1 to 1.6
times Adventure.

### Days to a 1,000-coin cosmetic at 20 minutes a day (daily reward included)

| Player | Coins a day | Days, round 3 | Days, round 2 |
|---|---|---|---|
| Adventure only | 280 ÷ 3 + 15 = 108.3 | 1,000 ÷ 108.3 = **9.2** | 9.2 |
| Ticket loop, Easy | 439.8 ÷ 3 + 15 = 161.6 | 1,000 ÷ 161.6 = **6.2** | 5.5 |
| Ticket loop, Normal | 376.7 ÷ 3 + 15 = 140.6 | 1,000 ÷ 140.6 = **7.1** | 6.9 |
| Ticket loop, Hard | 310.0 ÷ 3 + 15 = 118.3 | 1,000 ÷ 118.3 = **8.4** | 9.5 |
| Mix (10 min Adventure + 10 min Normal loop) | 46.7 + 62.8 + 15 = 124.5 | 1,000 ÷ 124.5 = **8.0** | 7.9 |
| Solo minigames only | 0 + 15 = 15 | **67** (daily reward alone) | about 12 |

### Trophies under round 3

- **Working Capital (2,500 from play):** about 23 days Adventure only
  (2,500 ÷ 108.3), 20 for the mix (2,500 ÷ 124.5), 18 on the Normal loop
  (2,500 ÷ 140.6).
- **Pit Boss (1,000 caught in Gold Rush):** unchanged, about 14 rounds.
- Coin trophies can no longer be reached by playing solo minigames alone.
