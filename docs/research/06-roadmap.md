# 06 — Build-Ready Roadmap

_Artifact 6 (capstone). Reads `04-gap-analysis.md` + `05-opportunities.md`. Sequences the
opportunities by **dependency**, tied to real files, each with the metric it should move and
the analytics event that measures it. Aligned to `00-brief.md` guardrails throughout._

## Sequencing logic

- **Brief weighting:** popularity / retention / joy first, self-sufficient monetization second.
- **Async-first:** the multiplayer beachhead is **ghost racing**, not real-time servers (solo
  ops bandwidth + needs player density). Real-time MP is a *parked* far-future bet.
- **Remote config is an early enabler** — built in Phase 0 so later balance/season changes
  don't need an App Store release (a solo-dev superpower).
- **Pre- vs post-launch:** Phase 1 makes the core thesis *true* and ships at launch. Phases
  2–4 are post-launch waves, each a **hypothesis** validated by the analytics that go live.
- **Effort:** S ≈ days · M ≈ 1–2 wks · L ≈ several wks · XL ≈ month+ (one developer).

## Projected scorecard, climbing by phase

| Axis | Now | P1 | P2 | P3 | Final |
|---|---|---|---|---|---|
| Core | 4 | 4 | 4 | 4 | **5** |
| Onboarding | 3 | 3 | 3 | 3 | **4** |
| Retention | 2 | 2 | 3 | **4** | 4 |
| Meta | 3 | **4** | 4 | 4 | 4 |
| Economy | 3 | 3 | 3 | 3 | **4** |
| Monetization | 2 | **3** | 3 | **5** | 5 |
| Virality | 1 | **3** | **4** | 4 | 4 |
| Social | 1 | **3** | **4** | 4 | 4 |
| LiveOps | 1 | 1 | **3** | **4** | 4 |

---

## Phase 0 — Foundations (enablers; build first)

| Item | Files / systems | Effort |
|---|---|---|
| **Remote config service** | New `RemoteConfig` (Supabase PostgREST, mirror `SocialClient` style) → feeds `GameState` tunables (difficulty scales, daily ladder, event/season defs). | M |
| **Shared Season + Leaderboard service** | Extend `SocialClient` (`fetchLeaderboard` already exists) into a reusable `seasons` + `scores` service — used by ranked (P3), tournaments + Season Hunt (P4). Build once, use four times. | M |

_Metric: enablement (no direct KPI). Guardrail: config can only tune fairness-safe values._

---

## Phase 1 — Pre-launch must-haves: make identity public, desirable, shareable ⭐

The keystone + the cheapest virality + desire-on-existing-catalogue. Mostly client-side, low risk.

| Item | What | Files | Metric → analytics event | Effort |
|---|---|---|---|---|
| **Show opponents' cosmetics** (keystone) | Render each rival's **ball skin + trail** in competitive modes; viewer's **floor/goal stay their own**. AI rivals draw from a curated **desirable** skin/trail pool (a walking catalogue showcase). | `GoldRushEngine`/`GoldRushView` (`Racer.colorIndex` → equipped skin+trail; reuse the trail renderer from `HomeView`), then `MarbleCupView`, `KingOfTheHillView`, `PaintBallView`, `SnakeGameView`, `SumoSurvivalView`. Cosmetic source: `BallSkin`, `TrailColor`. | Cosmetic equip + shop conversion → add `cosmetic_equipped`, `cosmetic_admired` (tap a rival's skin) events alongside existing shop purchase tracking. | **M** |
| **Rarity-as-status** | Surface `CosmeticTier` (common→legendary) visibly in shop, profile, and on the in-game skin. | `Cosmetics.swift` (`CosmeticTier`), `CosmeticShopView`, `ProfileView`, `BallSkinView`. | Shop browse→buy rate → `shop_item_viewed` / purchase events. | **S** |
| **Shareable result card** | A **Share** button on every round-over overlay → renders an image (your skin, score, placement, a "beat me" deep link). | Round-over overlays: `GoldRushView.gameOverOverlay`, `BallGameView.coinPitPayoutOverlay`, competitive views' end screens. Reuse `ShareLink` (already in `ProfileView`) + a `UIGraphicsImageRenderer` card. | Share rate + install k-factor → `result_shared` event + deep-link attribution. | **S** |
| **Profile drip showcase** | Profile shows your equipped loadout as social capital; visible when others view you. | `ProfileView`, `SocialClient.fetchProfile`. | Profile views → `profile_viewed`. | S–M |

_Guardrail check: ✅ all cosmetic/visibility, no P2W, no ads, no FOMO._

---

## Phase 2 — Virality clips + LiveOps engine room 📣⚙️

| Item | What | Files | Metric → event | Effort |
|---|---|---|---|---|
| **Challenge deep links** | "Beat my run" — share a seeded challenge; friend plays the same and compares. | Deep-link router (`Navigator`/`HomeRoute`), seed in the engines, `SocialClient` friends graph. | Challenge sends/accepts → `challenge_sent` / `challenge_accepted`. | M |
| **Monthly season + Season Hunt** | A rotating theme (remote-config) that drops limited cosmetics; collect tokens through play → earn the limited ball/trail. | `RemoteConfig` (season def), new `SeasonHunt` progress on `GameState`, reward grants via `GameState.grant`, seasonal skins already exist as bundle-exclusive in `Cosmetics`/`BallSkin`. | D7/D30 retention; token-collection completion → `season_progress` / `season_reward_claimed`. | **L** |
| **Weekly missions** | The missing D7 hook — 3–5 rotating goals/week, cosmetic + coin rewards. | New `Missions` (remote-config defined), progress on `GameState`, `AnalyticsClient`. | D7 retention; mission completion → `mission_completed`. | M |
| **Clip / replay capture** | Record a round → share a watermarked clip (your cosmetics on screen). *After* result-card proves sharing behavior. | `ReplayKit` (`RPScreenRecorder`) in the competitive views; share sheet. | Clip share rate + k-factor → `clip_shared`. | **L** |

---

## Phase 3 — Social Stakes 🤝 (elevated) + the Roll Pass 🎟️

| Item | What | Files | Metric → event | Effort |
|---|---|---|---|---|
| **Make leaderboards matter** | Ranked **seasons** with cosmetic-only rewards + a **visible rank badge** (shown in competition + profile). | Season/Leaderboard service (Phase 0), `LeaderboardView`, reward grants, a rank-badge cosmetic. | Ranked D7/D30; rank-up → `rank_promoted`, `season_reward_granted`. | M |
| **Async ghost racing** | Race friends'/global **recorded runs** — the affordable multiplayer beachhead. (Record the marble path, not the RNG — engines use `CGFloat.random`.) | `GoldRushEngine` (record/replay path), new `GhostRun` model + Supabase store, competitive view renders a ghost racer wearing their cosmetics. | Race plays/session; head-to-head completion → `ghost_race_played`. | **L** |
| **Friend challenges / clan goals** | Async duels via the friends graph; a weekly **clan challenge** + shared cosmetic unlock (clans currently do nothing). | `SocialClient` (friends + clan methods exist), `FriendsView`, `ClansView`, reward grants. | Clan activity; challenge completion → `clan_goal_progress`. | M–L |
| **Event tournaments** | Time-boxed competitive events, **cosmetic-only** top-placement rewards (Stumble's Mythic-per-tournament, fair). | Reuses the Season/Leaderboard service + remote config. | Event participation → `tournament_entered` / `tournament_reward`. | M |
| **The Roll Pass** | Cheap (~$5), fair, cosmetic-heavy **seasonal pass** (free + premium track). One-time per season, **not** auto-renew. Optimize for *many buyers*. | New `Pass` service (rides the monthly season), `StoreKitManager` (new non-consumable seasonal SKU per `Products.storekit` pattern), reward grants, a Pass UI. | Pass attach rate (% DAU) + ARPDAU → `pass_purchased`, `pass_tier_claimed`. | **L** |

_Guardrail check: ✅ cosmetic-only rewards, no P2W, one-time pass (no sub), no loot boxes, no forced ads. Tournaments framed as "this season's ladder," not punitive timers._

---

## Phase 4 — Hook, rebalance & bigger bets 🎯

| Item | What | Files | Metric → event | Effort |
|---|---|---|---|---|
| **Race-first onboarding** | Open with a legible ~30s race/scramble (joy + cosmetics in minute one), *then* reveal the climb. | `HomeView.onboardingOverlay`, a quick intro race, `BallGameView` tutorial. | D1 retention → `onboarding_completed` (exists-ish via `seenOnboarding`). | M |
| **Win celebrations / emotes** | New cosmetic category — a flourish your ball does on winning, visible to opponents + clip-able. | New `Celebration` cosmetic enum in `Cosmetics`, render in competitive end screens, add to shop/pass. | New-category attach → `celebration_equipped`. | M |
| **Lives → cosmetics rebalance** | Soften lives gating; add rewarded-video **fair faucets** (double coins, daily-skin trial). | `GameState` lives constants, `AdManager` (new rewarded placements — opt-in only). | Coin faucet health; rewarded opt-in rate → `rewarded_completed`. | S–M |
| **Parked bets** | Real-time multiplayer; web (CrazyGames/Poki) distribution. Revisit only with a live player base. | — | — | XL |

---

## Build Monday: the first three

1. **Phase 0 remote config** (M) — unblocks everything; do it first even though it's "boring."
2. **Show opponents' cosmetics** (Phase 1, M) — the keystone; turns the whole thesis on.
3. **Shareable result card** (Phase 1, **S**) — the cheapest virality unlock you have.

Those three alone move **Virality 1→3, Social 1→3, Monetization 2→3, Meta 3→4** — the reds start
turning green, almost entirely by wiring up assets you already own.

## Risk & guardrail ledger

| Risk | Mitigation |
|---|---|
| Solo time/ops bandwidth | Async-first; remote config to avoid release churn; reuse one season/leaderboard service four ways. |
| Ghost-racing determinism | Record the **marble path**, not the RNG (engines use `CGFloat.random`). |
| Cosmetics-led revenue is modest | Fine — goal is self-sufficiency, not maximization; the pass + public cosmetics carry it (Brawl's "breadth not depth"). |
| Content-novelty treadmill (Stumble's decline) | The monthly season + remote config make fresh drops *cheap and repeatable*; community polls pick themes. |
| Drift from guardrails | Every monetized item above is cosmetic/convenience, one-time pass, rewarded-only ads, fair-FOMO. No loot boxes, no P2W. |

---

## Chain complete

`00`→`06` is the full recursive analysis. The strategic spine — **make a player's identity and
skill visible to others** — converts Roll Along's existing assets (deep cosmetics, real social
backend, content longevity, day-one fairness) into the popularity, virality, and fair
self-sufficiency the brief asked for. The refinement loop is available on demand: pick any
opportunity for a deep design spike (mechanic + economy math + SwiftUI sketch + A/B plan), or a
red-team pass on these recommendations.
