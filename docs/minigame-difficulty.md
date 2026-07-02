# Minigame difficulty & payout

How the competitive minigames let the player trade risk for reward, and how we
keep that trade **fair** over time.

## What the player sees

The old global **Settings → Minigame Difficulty** control is gone. Instead,
every competitive minigame shows a **difficulty picker at its start screen**
(Easy / Normal / Hard), and each option states its **coin payout** so the player
sees the reward before committing:

| Difficulty | Rivals | Payout |
|-----------|--------|--------|
| Easy   | weakest AI | **1×** coins |
| Normal | medium AI  | **1.5×** coins |
| Hard   | full-strength AI | **2×** coins |

The choice is remembered (`GameState.minigameDifficulty`) and re-shown each time.
For the multi-round game (Sumo Survival) the picker only appears on round 1 so
difficulty can't be changed mid-match.

Covers all six `section == .competitive` modes: Comet Clash (`snake`), Sumo
Survival (`sumo`), Paint Ball (`paintball`), Smash and Grab (`goldrush`), Marble Cup
(`marblecup`), King of the Hill (`koth`).

## The two knobs (single source of truth)

Both live on `MinigameDifficulty` in `RollAlong/GameState.swift` — **these tables
are the only things you edit to retune.**

- `aiAccelScale` (and `aiSpeedScale`, Smash and Grab only): scales rival AI strength.
  `Easy 0.55 · Normal 0.78 · Hard 1.0`. **Hard == the original pre-difficulty
  AI**; Easy/Normal handicap it. Each game multiplies its base rival
  acceleration (`aiAccelBase`) by `aiAccelScale`.
- `payoutMultiplier`: scales the coin winnings. `Easy 1.0 · Normal 1.5 · Hard 2.0`
  (compressed from `0.5 / 1.0 / 2.0` in the 2026-07-01 economy calibration —
  decision recorded in `docs/economy/07-decisions.md`).
- `targetWinRate`: the win-rate each tier is *designed* to land near
  (`Easy 0.80 · Normal 0.45 · Hard 0.22`) — the calibration target, not used by
  runtime logic.

## How payout is applied

Each game computes a raw `basePayout` from its own formula (e.g. Sumo placement
coins `[10,5,3,2]`; Comet Clash `power×3 + winBonus`; Smash and Grab = coins
collected). The award and the on-screen "+N coins" both run through:

- `GameState.minigamePayout(base:difficulty:)` — pure, for the result-screen and
  picker display, so display and award never disagree.
- `GameState.recordMinigameResult(modeID:difficulty:won:basePayout:)` — the
  single result entry point. It records the attempt + win (below), banks the
  **scaled** payout, and on a win bumps the lifetime tally + Gold Rush ticket.

## Tracking success rates

`recordMinigameResult` maintains two persisted dictionaries keyed
`"<modeID>|<difficulty>"` (e.g. `"snake|hard"`):

- `GameState.minigameDifficultyPlays` — attempts (incremented every match).
- `GameState.minigameDifficultyWins` — wins.
- `GameState.minigameSuccessRate(modeID, difficulty)` → `wins / attempts`.

Every match also emits the analytics event **`minigame_result`** with
`game, difficulty, won, base_payout, payout`, so win-rates can be aggregated
server-side per game and per difficulty (the per-game events —
`comet_round_over`, `sumo_match_over`, … — also now carry `difficulty` and
`base_coins`).

## Calibration loop (manual, data-driven)

Honest math, post-compression: the win-bonus portion is **no longer
EV-neutral**. Expected value per attempt = `payoutMultiplier × targetWinRate`:

- Easy: `1.0 × 0.80 = 0.80`
- Normal: `1.5 × 0.45 = 0.675`
- Hard: `2.0 × 0.22 = 0.44`

**Easy is the EV-optimal per-attempt pick — by design.** This is a deliberate
2026-07-01 decision (see `docs/economy/07-decisions.md`): grinding is blessed,
and a player who camps Easy earns coins fastest per attempt on the win bonus.
Hard still pays the most per WIN, and the accumulated portion (coins picked up
regardless of winning) still pays more on Hard — that "harder pays more per
unit" premium is unchanged and **not** auto-balanced. Telemetry (the
`minigame_result` event) will monitor how much Easy-camping actually happens;
revisit only if the data shows it distorting the economy.

**To retune, quarterly or after a balance patch:**

1. Pull observed win-rates per `game × difficulty` from the `minigame_result`
   events (or `minigameSuccessRate` in a debug build). Require a meaningful
   sample (≥ ~200 plays per cell) before acting.
2. **If a tier's win-rate is off its `targetWinRate`** (say Hard is winning 40%
   when we target 22%), first move `aiAccelScale` for that tier to push the
   win-rate back toward target — that keeps the three tiers meaningfully
   different.
3. **If the coin EV drifts from the intended shape** (Easy-leaning per attempt,
   Hard-leaning per win — compute mean `payout` per play per tier from the
   events), adjust `payoutMultiplier` toward that shape. Smash and Grab is
   accumulation-heavy and may need its own multiplier if its EV curve
   diverges — split it out then.
4. Edit only the tables in `MinigameDifficulty`; ship; repeat.

We deliberately do **not** auto-adjust payouts at runtime — it's exploitable
(throw matches to inflate your win-rate) and hard to reason about. Calibration
stays an offline, reviewed change to the tables above.
