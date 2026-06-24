# Gold Rush — Ticket Economy

Gold Rush (internally the **Coin Pit**, a `.collectCount` mode) is the
ticket-driven reward round: coins rain down for a bought stretch of time and you
bank everything you roll over. All of this lives in `BallGameView.swift`.

---

## Tickets

- Earned by **winning a competitive minigame** (one per win).
- Balance is `GameState.tickets` (persisted). Spent via `gameState.spendTickets(_:) -> Bool`.
- Entering Gold Rush with **zero** tickets is blocked at the Games hub and again
  on the stake overlay.

---

## Buying the round — the stake overlay

Before the clock starts, `coinPitStakeOverlay` lets the player buy **time**:

- **Every time ticket = +30 s** (`GameState.goldRushSecondsPerTicket`).
- Stake **as many tickets as you hold** — there is no per-round cap. (The old
  10-ticket `goldRushMaxStake` cap was removed.) The picker's upper bound is the
  player's balance.
- With exactly 1 ticket the picker is skipped — Start stakes it for a straight
  30 s round.
- Tickets are consumed on **Start** (`startCoinPitRound`), which freezes
  `coinPitTimeTicketsStaked` (for refund math) and sets
  `coinPitStakedMultiplier = 1`.

**Refunds:** quitting early refunds **one ticket per full un-played 30 s block**.
The in-round ×2 boost is **never** refunded.

Round length: `coinPitStakedDuration = timeTicketsStaked × 30 s`.

---

## The ×2-coins boost (the only in-round upsell)

A single mid-round purchase, `coinPitDoubleButton` (bottom-centre during play):

- Costs a **flat 2 tickets**, available once per round.
- It **doubles your payout, not the coin count.** When bought it:
  1. back-pays the current haul once (`addCoins(coinPitScore × payout)`), so
     everything caught *before* the buy is retroactively worth ×2, then
  2. sets `coinPitStakedMultiplier = 2`, so every later catch credits ×2.
- The button greys out when you can't afford it and disappears once bought (the
  HUD then shows the ×2 badge).
- There are **no other multipliers** — no ×3/×4/×5. That's by design (see below).

---

## Why ×2 multiplies payout, not coin density

Originally the multiplier scaled the **number of coins dropped**
(`effectiveTarget = base × timeBlocks × multiplier`). At ×4–×5 the field filled
with hundreds of falling, spinning coins and the frame rate tanked.

The fix decoupled reward from density:

```
coinPitEffectiveTarget = base × timeBlocks          // coin COUNT — never scaled by the boost
banked / live credit   = coinsCaught × payout × mult // coin VALUE — what the boost doubles
```

So on-screen coin density is constant regardless of the boost — no lag — while
the player still earns 2× coins. Because the boost back-pays the existing haul,
the simple display formula `coinPitScore × payout × multiplier` stays exact.

---

## Banking

Coins are credited **live** as caught (`gameState.addCoins(caught × payout ×
multiplier)` each tick), not in a lump at the end. The payout overlay's
`+N coins banked` is display-only and matches the live total.

---

## Key symbols

| Symbol | Meaning |
|---|---|
| `coinPitStaked` | round paid & live |
| `coinPitStakeTime` | picker value: time tickets to stake (≥1) |
| `coinPitTimeTicketsStaked` | frozen at Start; drives duration + refunds |
| `coinPitStakedMultiplier` | 1, or 2 after the in-round buy |
| `coinPitScore` | coins caught this round (the count shown in the HUD) |
| `coinPitEffectiveTarget` | total coins dropped = base × time blocks |
| `GameState.goldRushSecondsPerTicket` | 30 |
| `coinPitPayoutPerCoin` | coins banked per coin caught (×multiplier) |
