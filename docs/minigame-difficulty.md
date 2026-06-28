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
| Easy   | weakest AI | **0.5×** coins |
| Normal | medium AI  | **1×** coins (today's payout) |
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
- `payoutMultiplier`: scales the coin winnings. `Easy 0.5 · Normal 1.0 · Hard 2.0`.
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

The fairness goal: **expected coins per play should not reward sitting on Easy or
punish committing to Hard** — payout should compensate for the lower win odds.

For the win-bonus portion this is roughly EV-neutral by construction —
`payoutMultiplier × targetWinRate`:

- Easy: `0.5 × 0.80 = 0.40`
- Normal: `1.0 × 0.45 = 0.45`
- Hard: `2.0 × 0.22 = 0.44`

…all ≈ 0.4–0.45, i.e. about even. The accumulated portion (coins picked up
regardless of winning) is a deliberate "harder pays more per unit" premium and
is **not** auto-balanced — watch its total in the data.

**To retune, quarterly or after a balance patch:**

1. Pull observed win-rates per `game × difficulty` from the `minigame_result`
   events (or `minigameSuccessRate` in a debug build). Require a meaningful
   sample (≥ ~200 plays per cell) before acting.
2. **If a tier's win-rate is off its `targetWinRate`** (say Hard is winning 40%
   when we target 22%), first move `aiAccelScale` for that tier to push the
   win-rate back toward target — that keeps the three tiers meaningfully
   different.
3. **If win-rates are where we want them but the coin EV is skewed** across
   tiers (compute mean `payout` per play per tier from the events), adjust
   `payoutMultiplier` so the EVs line up. Smash and Grab is accumulation-heavy and may
   need its own multiplier if its EV curve diverges — split it out then.
4. Edit only the tables in `MinigameDifficulty`; ship; repeat.

We deliberately do **not** auto-adjust payouts at runtime — it's exploitable
(throw matches to inflate your win-rate) and hard to reason about. Calibration
stays an offline, reviewed change to the tables above.
