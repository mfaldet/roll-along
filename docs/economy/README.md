# Roll Along — Coin Economy Briefing

A full audit of every way coins **enter** and **leave** the player's balance,
with measured earn rates (coins/min), a cosmetics cost census, an IAP
time-savings model, and a prioritized calibration plan. Compiled 2026-07-01 by
a multi-agent analysis pass over the entire codebase (every number cited to
`file:line`, adversarially re-verified by independent agents), plus external
research into how top F2P games calibrate the same systems.

## The tree

| Doc | Contents |
|---|---|
| [01-earning.md](01-earning.md) | Every earn path, formulas, coins/min master table, gates |
| [02-spending.md](02-spending.md) | Tier price ladder, full cosmetics census, bundles/packs, sinks, sell-back |
| [03-iap-value.md](03-iap-value.md) | $ → coins → hours-of-grind-saved model; lives packs; Diamond breakeven |
| [04-equity-gaps.md](04-equity-gaps.md) | Quantified inequities + the P0–P3 calibration levers (file:line) |
| [05-benchmarks.md](05-benchmarks.md) | External research: how top games calibrate earn equity, rarity curves, IAP value |
| [06-sprint-plan.md](06-sprint-plan.md) | Multi-agent sprint plan: standards, verification, AI calibration, QA |
| [07-decisions.md](07-decisions.md) | Mac's five rulings, shipped calibration levers, post-change earn table, tier-price memo (pending approval) |

## Headline findings

1. **There is a live infinite-coin exploit.** Sell Back re-grants the graphite
   trail (`TrailColor.starter = .graphite`, tier `.rare`/100) and refunds it on
   every cycle → **+100 coins per ~10s button press, forever** (~600/min, 4.3×
   the best legitimate rate). Everything else is calibration; this is a bug.
   *(Fix chip already queued.)*

2. **Challenge Track replays are an unbounded farm.** The track clear path pays
   `2 + pickups` on **every** re-clear (no first-clear check), while climb
   replays pay 0. An early track level is a 12–20 coins/min forever-farm that
   dwarfs the climb's one-time ~4.7/min.

3. **Earn equity is wildly off across modes** — a 14× spread between
   comparable competitive modes (Paint Ball ~62/min vs Sumo ~5/min at Normal,
   same cost, same ticket reward), and a ~140× full dynamic range (Zen 1/min ↔
   Paint Ball Hard ~124/min).

4. **Difficulty scaling exists in three inconsistent regimes**: competitive
   minigames scale payout ×0.5/×1.0/×2.0 (EV-neutralized against target win
   rates — good design, see [minigame-difficulty.md](../minigame-difficulty.md));
   the climb scales *time* but not coins (harder levels pay **less** per
   minute); solo minigames (Pinball/Disco/Roll Up/Roll Out) have **no** payout
   scaling at all.

5. **Coin IAPs are weak value at the small end** (~$12/hour-of-grind-saved for
   the $0.99 pack at casual rates — worse than just playing) and only become
   sensible at $49.99 (~$6/hr + exclusive Money cosmetic). Lives packs are the
   opposite: cheap ($0.77–0.99 per regen-hour) but **the store copy
   under-promises them by ~40%** (says 6/36/78 lives, code grants 10/60/130 —
   compliance/trust issue, fix chip queued).

6. **The catalogue is deep and the sink is single**: 218 items across 7
   categories, 54,550 coins total (52,550 coin-reachable), 66 bundles — but
   cosmetics are the *only* coin sink (3 spend call sites in the whole app).
   Time to own everything: ~44 hr at typical rates, ~7 hr for a skilled
   grinder — after the P0 exploit/farm fixes, roughly double that.

## The three currencies (context for everything else)

| Currency | Faucets | Sinks | Gate role |
|---|---|---|---|
| **Coins** | level clears, pickups, minigame payouts, dailies, Coin Pit, IAP | cosmetics (items, bundles, ball packs) — *only sink* | the chase |
| **Lives** | regen (1/6 min, cap 10), gifts, rewarded ad (+1), IAP | climb/track attempts, Roll Up runs, Roll Out falls | throttles the *climb*, not minigames |
| **Tickets** | +1 per competitive-minigame win (cap 999) | Coin Pit staking (30s/ticket) + in-round ×2 boost (2 tickets) | converts *skill wins* into the fastest coin faucet |

## Methodology & assumptions

- **Typical-casual rate = 20 coins/min (1,200/hr)**: Normal difficulty, ~50%
  win rate, blend of minigames + climb + dailies.
- **Best-sustained rate = 120 coins/min (7,200/hr)**: Hard Paint Ball mastery
  + tickets routed into boosted Coin Pit blocks. Theoretical ceiling ~155/min.
- Event durations include 5–10s lobby/result overhead. Every constant was
  spot-verified against source on 2026-07-01; the two independent verifier
  agents corrected 30+ claims before synthesis (corrections applied throughout).
- **Biggest unknown: real win rates.** No telemetry was pulled; Hard-mode
  sustainability assumes the designed `targetWinRate` (0.22). The
  `minigame_result` analytics event already carries everything needed to close
  this gap — see the sprint plan.
