# 04 — Equity gaps + the calibration levers

## Quantified gaps

1. **Paint Ball pays 14× Sumo per minute** at identical difficulty/outcome
   (~62/min vs ~5/min Normal win) — same cost (free), same ticket (+1). Sumo
   is strictly worse for coins *and* tickets/min (its ~120s matches also halve
   ticket velocity).
2. **Marble Cup can pay 0 for a full 90s match** (0-goal loss) while every
   other competitive mode has a loss floor.
3. **Three inconsistent difficulty regimes**: competitive payout ×0.5/×1/×2;
   climb time ×1/1.3/1.6 with *no* coin term (harder = ~38% fewer coins/min);
   solo modes (Pinball/Disco/Roll Up/Roll Out) no scaling at all.
4. **Hard is a 4× spread over Easy** (0.5→2.0). EV-neutral *only if* actual
   win rates hit targets (0.80/0.45/0.22) — no runtime feedback loop exists
   yet, so a Hard-capable player permanently doubles income.
5. **Track replays pay full reward forever; climb replays pay 0** — identical
   gameplay, infinite disparity, and the tracks' 12–20/min dwarfs the climb's
   one-time 4.7/min.
6. **Life-gating is inverted**: the only two life-gated minigames pay 24/min
   (Roll Up) and 5.3/min (Roll Out) while every life-FREE competitive mode
   pays up to 124/min. Roll Out is strictly dominated (lowest rate + life cost
   + missing the 100 best bonus).
7. **Ticket earn is flat 1/win regardless of match length** — a 60s KotH win
   funds Coin Pit as fast as a ~128s Sumo win (2× ticket-velocity gap,
   compounding the coin gap).
8. **Best-bonus asymmetry**: 100-coin `minigameBestBonus` paid by
   Pinball/Disco/RollUp/CoinPit-record; never by competitive modes; not by
   Roll Out.
9. **Dailies don't matter**: perfect week = 315 coins < half the cheapest
   bundle; day-7 jackpot (35) < one Normal Paint Ball win. *(The nerf was
   deliberate — revisit only with post-fix data.)*
10. **The exploit + the farm** (graphite ~600/min; tracks 12–20/min) sit above
    every legitimate rate, so today's real economy is defined by whether the
    player has found them.

## Calibration levers (priority order, with exact knobs)

### P0 — stop the bleeding (before any other tuning)
| Lever | Knob | Change |
|---|---|---|
| Kill graphite faucet | Cosmetics.swift:891 or GameState.swift:685-692 | `.graphite` → `.starter` tier, or skip refunds for re-granted starters. Regression test: 2nd consecutive sell-back refunds 0. *(chip queued)* |
| Close/bless track farm | BallGameView.swift:5576-5579 | Add climb-style `isFirstClear` + banked-pickup filter; **or** bless as the intended grind at pickups-only and re-baseline all rates around ~1,200/hr |

### P1 — mode equity (competitive band ≈ 30–60/min Normal)
| Lever | Knob | Change |
|---|---|---|
| Sumo payout | SumoSurvivalView.swift:58 | `[10,5,3,2]` → `[60,30,15,8]` → ~30/min N |
| Marble Cup payout + floor | MarbleCupView.swift:52-53 | goals×6+15 → goals×15+30 (loss ≥ ~15) |
| Climb tier coins | GameState.swift:1017 + LevelLayout tier | `coinPerClear` 2 → 2/3/4 by easy/hard/veryHard (kills the harder-pays-less inversion); consider +1 replay coin |
| Compress difficulty spread | GameState.swift:1687-1693 | ×0.5/1.0/2.0 → ×0.7/1.0/1.4, **and** wire `targetWinRate` feedback from `minigame_result` telemetry |

### P2 — solo-mode dignity + consistency
| Lever | Knob | Change |
|---|---|---|
| Pinball | PinballView.swift:149 | score/250 → score/125 (~18/min) |
| Roll Out rescue | RollOutView.swift:129, 585-592, 608 | 4 → 10/clear, add the missing best bonus, or drop the life cost |
| Best-bonus parity | GameState.swift:1228-1247 | Add per-difficulty bests for competitive modes, or document the asymmetry |
| Ball-pack proration | Cosmetics.swift:2737-2741 | Prorate owned members (or warn in UI) |
| CotD fallthrough | BallGameView.swift:5573-5605 | Give dailies their own clear path (stop polluting climb bests + stray +2) |

### P3 — monetization polish (after P0–P1 data settles)
| Lever | Knob | Change |
|---|---|---|
| Daily uplift | GameState.swift:1294; GameMode.swift:525-527 | day-7 35→60; CotD 30→50 → perfect week ~455 ≈ a standard bundle |
| Coin-pack re-anchor | StoreKitManager.swift:78-82 | Post-fix, size packs to bundle price points (650/950/1,650/2,640) |
| Ticket duration-weighting | GameState.swift:1205-1209 | 2 tickets for 90–120s modes |
| Lives copy | Products.storekit:17,32,47 | 6/36/78 → 10/60/130 *(chip queued)* |
| Cap UX | GameState.swift:1023-1048 | Warn when coins10000 would clip vs 999,999 cap |

## The target picture (post-calibration)

- **Every competitive mode**: 30–60 coins/min at Normal with a >0 loss floor;
  Hard ≈ +40% (×1.4), verified against live win-rate telemetry quarterly.
- **Every solo mode**: 15–25 coins/min, each with the 100 best bonus.
- **Climb**: the *progression* spine, ~5–8 coins/min with tier-scaled clears —
  not a farm, but never paying less for harder.
- **Coin Pit**: the skill-funded jackpot at 2–4× the competitive band —
  visibly the best rate in the game, gated by earned tickets.
- **Dailies**: a perfect week ≈ one standard bundle — enough to feel like a
  paycheck, not enough to replace play.
- **IAP**: packs land on bundle price points; $/hr-saved in the $3–6 band vs
  post-fix typical rates; money also buys exclusivity (Money set, seasonal
  bundles, Diamond).
