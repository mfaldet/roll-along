# 01 — Every way to earn coins

All rates independently verified against source (2026-07-01). "N" = Normal
difficulty, "H" = Hard. Wall-clock durations include ~5–10s lobby/result
overhead. Assumed performance baselines are listed at the bottom.

## Master earn-rate table (sorted by coins/min)

| # | Method | Coins/event | Duration | **Coins/min** | Gate | Difficulty scaling |
|---|---|---|---|---|---|---|
| — | ~~Graphite sell-back exploit~~ | +100/cycle | ~10s | **~600 (BUG)** | none | — |
| 1 | Coin Pit round (boosted ×2) | 60–160/block | 30s/block | **160–320** | tickets (1/block + 2 for boost) | none |
| 2 | Coin Pit round (raw) | 40–80/block | 30s/block | **80–160** | tickets (1 per 30s block) | none |
| 3 | Paint Ball win | ~70 N / ~140 H | ~68s | **~62 N / ~124 H** | none | ×0.5/×1/×2 |
| 4 | King of the Hill win | ~55 N / ~110 H | ~68s | **~48 N / ~97 H** | none | ×0.5/×1/×2 |
| 5 | Smash and Grab win | ~45 N / ~90 H | ~68s | **~40 N / ~79 H** | none | ×0.5/×1/×2 |
| 6 | Comet Clash win | ~44 N / ~88 H | ~90s | **~29 N / ~59 H** | none | ×0.5/×1/×2 |
| 7 | Roll Up run | ~48 + 100 best | ~120s | **~24** | **1 life/run** | none (content ramp) |
| 8 | Disco Ball run | ~18 + 100 best | ~45s | **~24** | none | none (harder grid, same pay) |
| 9 | Challenge Track **replay farm** | 2 + pickups every clear | ~15s (early lvl) | **12–20** | lives on falls | none |
| 10 | Marble Cup win | ~27 N / ~54 H | ~98s | **~17 N / ~33 H** | none | ×0.5/×1/×2 |
| 11 | Challenge of the Day | flat 30 | ~180s | **~10, 1×/day** | daily + 3 tries/sub-level | none |
| 12 | Pinball game | ~28 + 100 best | ~180s | **~9.3** | none | none |
| 13 | Sumo Survival win | 10 N / 20 H (1st) | ~128s | **~5 N / ~10 H** | none | ×0.5/×1/×2 |
| 14 | Roll Out maze | 4/clear | ~45s | **~5.3** | **1 life/fall** | none |
| 15 | Climb first clear | 2 + pickups (max 5) | ~45s | **~4.7 (finite)** | 1 life/fall >L10 | time ×1/1.3/1.6, coins ×1 |
| 16 | Competitive loss floor | 2–20 | 60–120s | **~2–20** | none | ×0.5/×1/×2 |
| 17 | Daily login | 5→35 ladder (105/wk) | ~10s | once/day | daily | none |
| 18 | Zen Garden | min(min played, 15) | 15+ min | **≤1, cap 15/session** | session cap | none |
| 19 | Climb replay | 0 (+missed pickups) | ~45s | **~0** | lives | none |
| 20 | Rewarded ad | 0 coins (**+1 life**) | ~30s | 0 | ad fill | none |

## Per-method detail

### The climb (levels 1–5,000)
- **Pickups**: `coinPerPickup = 1` (GameState.swift:1013); generated levels
  place exactly 3 coins (LevelLayout.swift:426-428); authored override levels
  can differ; daily maps have zero (LevelLayout.swift:274).
- **First clear**: `coinPerClear = 2`, paid only when no `bestTime` exists
  (GameState.swift:1014-1017; BallGameView.swift:5636). Perfect first clear = 5.
- **Pickups bank only on a CLEARED run** (`recordResult`, GameState.swift:734);
  a fall resets the attempt's pickups (BallGameView.swift:5373). So replays can
  recover coins missed earlier, but generate ~0 sustained income.
- **Stars/times award no coins** — purely progression.
- **Tier scales time, not coins**: `timeMultiplier` 1.0/1.3/1.6
  (LevelLayout.swift:127-133) with no coin term → a veryHard level pays ~38%
  fewer coins/min than an easy one. *(Calibration lever P1.)*
- **Lives throttle**: 1 life per fall above L10 (tutorial exempt); 10-life bar
  = ~10 attempts, refills in 60 min (GameState.swift:128-130). This caps climb
  farming but — importantly — none of the high-rate earners are life-gated.

### Competitive minigames (the ×0.5/×1/×2 regime)
Single result pipeline: `recordMinigameResult` banks
`round(base × payoutMultiplier)` **win or lose**, +1 Gold Rush ticket on a win
(GameState.swift:1228-1247, 1205-1209). Bases:

| Mode | Base formula | Typical N win | Loss floor |
|---|---|---|---|
| Paint Ball | coverage% + 20 (PaintBallView.swift:436-437) | ~70 | ~20 |
| King of the Hill | holdSec × 2 + 15 (KingOfTheHillView.swift:53-54) | ~55 | hold×2 |
| Smash and Grab | playerScore + 15 (GoldRushEngine.swift:543) | ~45 | score |
| Comet Clash | power × 3 + 20 (SnakeGameView.swift:363-364) | ~44 | power×3 |
| Marble Cup | goals × 6 + 15 (MarbleCupView.swift:518-519) | ~27 | **can be 0** |
| Sumo Survival | placement [10,5,3,2] (SumoSurvivalView.swift:58) | 10 | 2–5 |

The multipliers are EV-neutralized against target win rates by design
(0.5×0.80 / 1.0×0.45 / 2.0×0.22 ≈ 0.40–0.45 — see
[minigame-difficulty.md](../minigame-difficulty.md)), **but no runtime feedback
exists**: if a player's actual Hard win rate exceeds 22%, Hard is a permanent
~2× income doubling. The `minigame_result` analytics event carries
`game/difficulty/won/payout` — the recalibration loop is designed but not yet
data-driven.

**Best-bonus asymmetry**: the flat 100-coin `minigameBestBonus`
(GameState.swift:1054) is paid by Pinball, Disco, Roll Up, and Coin Pit records
— but **never** by `recordMinigameResult` (competitive modes) and **not** by
Roll Out (clearMaze pays nothing extra, RollOutView.swift:585-592).

### Coin Pit (Gold Rush reward round) — the ticket→coin converter
- Entry: staked with **tickets** (1 per competitive win, cap 999). Each time
  ticket buys 30s and 100 dropped coins (GameMode.swift:277,
  BallGameView.swift:283-285). Catch rate 40–80%.
- In-round ×2 **payout** boost: flat 2 tickets, once/round; retroactively
  back-pays the current haul then doubles later catches
  (BallGameView.swift:4377-4379, 5532).
- Early-quit refunds 1 ticket per full unplayed 30s block (boost never refunds).
- **Doc/code drift to resolve**: GameState.swift:1184-1188 comments describe a
  per-coin-ticket drop multiplier that BallGameView no longer implements;
  [gold-rush-economy.md](../gold-rush-economy.md) says the 10-ticket
  `goldRushMaxStake` cap was removed but the constant still exists
  (GameState.swift:1191) — confirm which is authoritative.
- Blended rate including the cost of *earning* the tickets: **~45–75/min** —
  its generosity is a skill reward, which stacks with the ×2 Hard multiplier
  (skilled players get paid twice).

### Dailies
- **Login ladder** [5,8,10,12,15,20,35] = 105/perfect week; a skipped day
  resets to day 1 (GameState.swift:1294, 1307-1342). *(Recently nerfed —
  deliberate, per the teardown.)*
- **Challenge of the Day**: flat 30 coins (GameMode.swift:525-527), 1–3 brutal
  levels, 3 free attempts per sub-level, no life cost, no pickup coins.
- **Known bug**: CotD clears fall through the main-climb clear path (no
  `.oneShot` fast-path) — polluting climb bestTime/stars and paying a stray +2
  "first clear" (BallGameView.swift:5573-5605).
- Perfect week total (login + CotD): **315 coins** — less than half the
  cheapest bundle (650). Dailies are currently recognition, not income.

### Challenge Tracks
- Track clears pay `2 + all pickups` on **every** clear — the fast-path has no
  first-clear or banked-pickup check (BallGameView.swift:5576-5579), and any
  cleared level replays freely from the grid (GameState.swift:415-419).
  **This is the dominant free grind loop** (12–20/min sustained on an early
  level) and the #2 calibration priority after the graphite exploit: close it
  or bless it, but price the economy around the decision.

### Everything else
- **Roll Up**: `min(250, meters × 0.20)` ≈ 48/run + 100 best bonus; costs
  1 life per run end (RollUpView.swift:44,402,549-553).
- **Roll Out**: 4/maze, **no best bonus**, 1 life per fall — strictly dominated
  (lowest rate + life cost + missing the bonus). *(Lever P2.)*
- **Disco Ball**: 3/crossing ≈ 18/run + 100 best; difficulty changes the grid
  but not the pay (DiscoBallView.swift:61-62,693-694).
- **Pinball**: `score/250` ≈ 28/game + 100 best (PinballView.swift:149).
- **Zen Garden**: `min(sessionMinutes, 15)` per session
  (GameState.swift:1167-1173) — recognition, not income.
- **Rewarded ad**: exactly 1 life, never coins (AdManager.swift:155-157). One
  placement (out-of-lives continue). At ~30s/life it undercuts lives-pack
  urgency 12× vs regen.
- **Guardrails**: every award clamps at `maxSingleAward = 10,000` and balance
  cap 999,999 (GameState.swift:1023-1048).

## Performance baselines assumed
KotH winning hold 15–25s · Paint Ball win coverage ~50% (loss ~20%) ·
Marble Cup 2 goals · Snake power ~8 · Pinball ~7,000 pts/3 balls ·
Disco ~6 crossings · Roll Up ~240m · early-track replay ~15s · Coin Pit catch
40–80% (60% typical) · climb level 25–65s (45s typical, from
`targetTime = 4·dist + 0.35·holes + 2.5`, LevelLayout.swift:331).
