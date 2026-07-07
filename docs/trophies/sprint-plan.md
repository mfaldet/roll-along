# Trophy System — Sprint Plan

> Status: **ACTIVE — the S0-gating rulings (D1/D4/D10 = design.md §11 #1/#2/#3/#14) RULED 2026-07-02; Sprint 0 kicked off 2026-07-02 on branch `claude/trophies-s0`.** Ladder: Bronze → Silver → Gold → Diamond → Platinum. Remaining D-handles stay open — see §7.
> Date: 2026-07-02 (reconciled against landed design.md + trophy-catalog.md same day) · Owner: delivery lead · Executors: Claude agent sessions (single or hive-mind)
> Inputs: all six research docs in `docs/trophies/research/` (read them per task, see roster), plus sibling
> deliverables `docs/trophies/design.md` (architecture + numbered decisions) and
> `docs/trophies/trophy-catalog.md` (the v1 trophy list + stat gap list).
> All `file:line` refs anchor on **symbol names**; line numbers drift.
> Provenance: every code claim verified at `064f3cd`, reconciled same-day to `origin/main` `42d1925` (PRs #113/#114/#118–#120/#122–#124 merged 2026-07-02 — economy calibration + tier reprice are LIVE); GameState refs below re-anchored to `origin/main`; see `research/repo-delta-2026-07-02.md`.
> Tip drift (2026-07-02, post-reconciliation): `origin/main` has since moved `42d1925` → `fb98819` — one commit, the IAP launch-race fix (StoreKitManager delivery ledger `ra_iapDeliveredTxnIDs`) is now MERGED; touches StoreKitManager + its tests only, no GameState re-anchoring needed.

## 1. Delivery overview

**Program definition of done:**

1. **Trophies live** — every v1 catalog trophy is earnable end-to-end, offline, latched (never revoked),
   with correct retroactive backfill for existing saves.
2. **Rarity showing** — tier labels render in the Trophy Room from the architecture design.md picked,
   with cold-start suppression so day-1 numbers are never embarrassing.
3. **QA green** — the full test matrix (§5) passes; no regression to GameState, profiles, leaderboards,
   or the economy; unlock checks provably never hitch the game loop.
4. **App Store safe** — no pay-gated or time-limited trophies, privacy manifest reviewed, review-guideline
   check done (4.5.3/4.5.5/3.2.2(x)), TestFlight beta feedback incorporated, IDs/criteria frozen forever.

**Sprint sequence (one line each):**

| # | Sprint | Goal | User-visible? |
|---|--------|------|---------------|
| S0 | Foundation | Catalog model, engine, stat instrumentation, persistence + migration, test scaffolding — zero UI change | No |
| S1 | Trigger wiring | Every catalog trophy fires from its real hook point; cumulative progress; offline-safe unlock recording | No |
| S2 | Presentation | Toasts, Trophy Room, profile showcase, capstone celebration | Yes |
| S3 | Rarity backend | Server aggregate + sync per design.md (Supabase and/or Game Center mirror); cold-start rules; delete/reinstall handling | Yes |
| S4 | Hardening & launch | Full QA, performance validation, TestFlight beta loop, App Store metadata, launch checklist | Ship |

**Dependency graph:**

```
S0 Foundation
  └─► S1 Trigger wiring
        ├─► S2 Presentation ──────────────┐
        └─► S3 Rarity backend ────────────┼─► S4 Hardening & launch
                                          │
S3-T1/T2 (Supabase DDL + rollup job) depend only on S0-T1's frozen IDs
and the D12 ruling, and touch no app files — they may start in parallel with S1.
S2 and S3 run in parallel lanes (disjoint files) once S1 lands.
```

**Sizing model (per task):** **S** = small, sub-session, one tight diff. **M** = one focused
single-agent session including tests + xcodebuild verify. **L** = one long session at the limit —
if an L task is going sideways, split it and hand back. Nothing in this plan is bigger than L by design;
that is the unit the hive-mind schedules.

**Session protocol:** one task per session; branch per task (`claude/trophies-<task-id>`); PR per task or
small cluster; every session ends with a green `xcodebuild` and explicit-path staging (§4). The QA verifier
gates each sprint before the next begins.

**Sprint scorecard (living — update status as tasks land):**

| # | Sprint | Exit criteria | Est. sessions | Status |
|---|--------|---------------|---------------|--------|
| 0 | Foundation | Engine + stats + migration all unit-tested; zero visible change; files pre-registered | 4–5 | 🟢 done 2026-07-02 (gate green) |
| 1 | Trigger wiring | Every catalog trophy trigger-tested (boundary + idempotency); unlocks durable | 7–9 | 🟢 done 2026-07-06 (gate green; 88/89 wired, whimsy_roll_call blocked on pinball ROLL lanes; 310 tests, 0 failures) |
| 2 | Presentation | Toasts/room/profile/capstone/pinning on device; VoiceOver smoke; no mid-run toast | 5–7 | 🟢 done 2026-07-06 (logic gate green; 405 tests 0 failures; device/visual/VoiceOver QA pending Mac — see PR) |
| 3 | Rarity backend | Sync replay + rarity correctness + delete/reinstall + showcase verified | 6–8 (+1 if D2=yes, +1 if D11=yes) | 🟢 done 2026-07-07 (logic gate green; 494 tests 0 failures; GC mirror deferred; Mac deploy steps pending — see PR) |
| 4 | Hardening & launch | Full matrix, perf budget, beta criteria, freeze + submission | 4–6 | ⚪ not started |

Total ≈ **27–36 focused agent sessions**. The GameState serial lane (S0-T2 → S1-T7) is the critical path
at ~9 sessions; everything else parallelizes around it.

**File-ownership / conflict map (who may write what):**

| File(s) | Writer | Contention notes |
|---------|--------|------------------|
| `GameState.swift` | ENG only | THE serial bottleneck — one session at a time, S0-T2 through S1-T5 in order |
| `TrophyCatalog/Engine/Stats.swift` | ENG | new files, no contention after S0-T1 stubs |
| `TrophyRoomView/TrophyToastView.swift` | UI | new files; internal order S2-T1 → T5 → T6 |
| `ProfileView/HomeView/BallGameView` + minigame views | UI (S2 only) | untouched by S1 **except** Disco/RollOut (S1-T4, ENG) and the BallGameView/PinballView event hooks (S1-T7, ENG) — S2-T2 waits for S1 gate |
| `SocialClient/TrophySyncService/GameCenterMirror.swift` | BE | parallel-safe vs. ENG and UI lanes |
| `FriendsView/ClansView.swift` | BE (S1-T6) | parallel-safe vs. GameState lane |
| `RollAlongTests/Trophy*.swift`, `PerformanceTests.swift` | QA | parallel-safe |
| `project.pbxproj` | S0-T1 batch, then coordinate | any unplanned new file = announce in PR, add the 4 entries yourself |
| Supabase project (migrations/functions) | BE | dev-branch first, managed migrations only, DDL copies in `docs/trophies/` |

## 2. Sprint detail

### S0 — Foundation (engine exists, nothing visible)

Exit criteria: all S0 tests green, `xcodebuild` clean, app behavior unchanged, all planned new files
pre-registered in `project.pbxproj`.

| ID | Task | Files | Acceptance criteria | Size | Deps | Owner |
|----|------|-------|---------------------|------|------|-------|
| S0-T1 | **TrophyCatalog data model.** Codable `TrophyDefinition` (stable string id, tier, category, title, pre/post descriptions, secret flag, criteria = metric key + threshold, optional reward ref, `addedInVersion` — fields per design.md §9; **no points field in v1** — point weights are deferred to the GC phase per trophy-catalog.md open Q6). Catalog **content ships as bundled `TrophyCatalog.json`** (design.md §9's LevelOverrides pattern); `TrophyCatalog.swift` is the model + loader + guardrail validation. IDs must be GC-legal from day one (alphanumeric, ≤100 chars, permanent) even if the GC mirror is deferred. Tier names/rungs per D10 — RULED 2026-07-02: Bronze / Silver / Gold / Diamond + the "Platinum" capstone. Vocabulary: GameMode ids (`climb`, `daily`, `challenge.<trackID>`, `zen`, `coinpit`, `snake`, `sumo`, `paintball`, `goldrush`, `marblecup`, `koth`, `pinball`, `rollout`, `rollup`, `disco`) + cosmetic/bundle rawValues. **Also create empty stubs for every planned new file (below) and register all pbxproj entries in this one session** to minimize later pbxproj conflicts. | NEW `RollAlong/TrophyCatalog.swift`, NEW `RollAlong/TrophyCatalog.json` (bundle resource entry), stubs: `TrophyEngine.swift`, `TrophyStats.swift`, `TrophyRoomView.swift`, `TrophyToastView.swift`, `TrophySyncService.swift`; NEW `RollAlongTests/TrophyEngineTests.swift`, `TrophyStatsTests.swift`, `TrophyMigrationTests.swift`; `RollAlong.xcodeproj/project.pbxproj` | Catalog decodes/encodes round-trip; unit test asserts every id is GC-legal and unique; every criteria metric key resolves to a known metric enum case (exhaustive switch); guardrail test rejects layout-keyed or IAP-keyed criteria; build green with stubs | M | D4 + D10 — both RULED 2026-07-02 (catalog adopted; ladder Bronze → Silver → Gold → Diamond → Platinum): dep satisfied | ENG |
| S0-T2 | **Stat instrumentation layer.** New counters/derivations required by trophy-catalog.md §6 (items 4–6, 15 — the GameState-funnel subset; view-layer hooks are S1-T7, social latches are S1-T6): source-tagged lifetime coins **earned from play** (hook `addCoins`, GameState.swift:1088; exclude IAP grants, Sell Back refunds, AND `grantBundleFree` bundle-gift compensation — PR #114 mints refund-shaped credits through `addCoins`; the exclusions are load-bearing, §6 item 4), lifetime daily-reward claim counter in `claimDailyReward` (item 5), consecutive no-fall clear streak (climb-mode-gated reset; item 6), CotD consecutive-date derivation helper over the existing completions date set (item 15, no new storage). All persist as new `ra_trophy*` UserDefaults keys via a `TrophyStats` store bumped from GameState funnels. **Never** implement a "coins spent" counter (Sell Back now refunds `min(coinCost/2, paidPrice)` — PR #118/#120 closed the old 100%-refund zero-cost farm, but a spend counter is still churnable at a 50% loss per cycle and refunds are recycled capital, not play income — internal-economy.md §5b), and **never a falls/failure counter** — trophy-catalog.md's "deliberately absent" list bans out-of-lives/failure counts (principle 6: nothing rewards losing); the tutorial-fall *event* for `whimsy_gravity_check` is a one-shot latch wired in S1-T7, not a counter. No speculative counters (results-shared, session count, lives received, climb attempts): no v1 trophy consumes them. | `RollAlong/TrophyStats.swift`, `RollAlong/GameState.swift` (funnel call sites only) | Each counter has a unit test proving increment at its funnel + persistence round-trip; counters are monotonic; every counter maps 1:1 to a trophy-catalog.md §6 item (test-enumerated); `resetProgress()` (GameState.swift:663) and `liquidateCoinCosmetics()` (:715) provably do NOT touch them | L | S0-T1 | ENG |
| S0-T3 | **TrophyEngine evaluation core.** Metric-keyed index (`[Metric: [TrophyID]]` built once) so a stat bump only evaluates interested trophies; latched unlock set + timestamps in `ra_trophyUnlocks`/`ra_trophyUnlockDates` (string-set helpers pattern, GameState.swift:1673-1690); monotonic progress API for UI. Trophy state lives in its own `ObservableObject` — NOT `@Published` on `GameState` — so gameplay views observing GameState don't re-render on trophy writes. | `RollAlong/TrophyEngine.swift` | Double-fire idempotency test; unlock never revoked when the underlying stat regresses (reset/liquidation fixtures); evaluation per stat bump is O(interested trophies) with no JSON encode of large dicts on the hot path; unit-tested with injected UserDefaults (GameStateTests pattern) | L | S0-T1 | ENG |
| S0-T4 | **Persistence + migration/backfill strategy.** First launch with trophies: evaluate the full catalog against existing stats and grant retroactively with a `legacy` timestamp marker; set a "backfill happened" flag S2 uses for one coalesced reveal instead of a toast storm. Handle fresh install, mid-progress, and veteran saves. | `RollAlong/TrophyEngine.swift`, `RollAlongTests/TrophyMigrationTests.swift` | Migration tests pass against three pre-trophy save fixtures (fresh / mid / veteran, built from real `ra_*` key dumps); backfill is idempotent across relaunches; no unlock timestamps in the future | M | S0-T2, S0-T3 | ENG |
| S0-T5 | **Unit-test scaffolding.** Shared fixtures: `makeGameState(defaults:)` helper, canned save-data dumps, a `TrophyTestHarness` that drives GameState public API and asserts unlock sets. XCUITest explicitly out of scope for trigger logic (§4g). | `RollAlongTests/TrophyEngineTests.swift`, `TrophyStatsTests.swift` | Harness compiles + demo test passes; documented in-file for later sessions to copy | S | S0-T3 | QA |

### S1 — Trigger wiring (every trophy connected to reality)

Exit criteria: every v1 catalog trophy has a passing trigger test driven through the public GameState API
(sole exception: `whimsy_roll_call`, externally blocked on the unbuilt pinball ROLL lanes — §7);
boundary + idempotency matrix green; unlock records are durable at the moment of unlock.

All hook points below are from internal-features.md §3 (the authority). GameState.swift tasks **serialize**
(single lane); view-file tasks can parallelize.

| ID | Task | Files | Acceptance criteria | Size | Deps | Owner |
|----|------|-------|---------------------|------|------|-------|
| S1-T1 | **Climb hooks.** `recordResult` (GameState.swift:767), `advanceLevel` (:631), `consumeLife` (:977), stars via `bestStars` mutation. Covers level/world/star/no-fall-streak trophies. **Mode-guard warning:** `consumeLife` is mode-agnostic — it is also called from `RollOutView.swift:611`, `RollUpView.swift:553`, and the shared fell path — so the no-fall-streak reset (and any climb-keyed check riding it) must gate on `activeMode.progression.recordsClimbResult` (or mode id `climb`) — the shipped vocabulary: the merged CotD `.oneShot` fast-path (PR #123) asserts exactly this before the climb record path; otherwise Roll Out/Roll Up falls wrongly reset `skill_clean_sheet_*`. Note also that tutorial falls (L1–10) never reach `consumeLife` at all — the streak reset should ride S1-T7's fall funnel, not `consumeLife` alone. Never key to specific level layouts — climb levels are swappable content (`LevelOverrides.json`). | `RollAlong/GameState.swift` | Trigger tests for each climb trophy at threshold−1 / threshold / threshold+1; a Roll Out/Roll Up life consumption provably does NOT reset the no-fall streak; CotD runs do not pollute climb trophies — test the MERGED `.oneShot` behavior: a CotD clear must never reach `recordResult` or climb trophies (the trophy-side gate is defense-in-depth, catalog §6 item 3) | M | S0 gate | ENG |
| S1-T2 | **Track + daily hooks.** `advanceTrackProgress` (GameState.swift:1436), `deliverTrackReward` (:1449), `completeTodaysDailyChallenge` (:904), `failTodaysDailyChallenge` (:898), `claimDailyReward` (:1389), `dailyStreak` (:155-166). Daily-history trophies derive from the persisted date sets (:370) — zero new instrumentation for those; two exceptions: `econ_punch_card`, which needs S0-T2's lifetime claim counter at `claimDailyReward` (catalog §6 item 5), and `daily_first_start`, which needs catalog §6 item 18's daily-start mode marker — latch `"daily"` into `playedModeIDs` inside `startDailyChallenge()` (GameState.swift:862; nothing writes `"daily"` — verified still true at `origin/main` `42d1925`: the daily route skips `.firstPlayTutorial` and `ModeTutorial.for("daily")` is nil). Latching in the GameState funnel is the catalog's own alternative site: no HomeView edit, so the ownership map's "HomeView untouched by S1" holds. Daily trophies stay keyed to `completeTodaysDailyChallenge`/`dailyChallengeCompletions` — the NEW `daily_challenge_level_cleared` analytics event (merged CotD fast-path, PR #123) is fire-and-forget and must NOT become a trigger source (§4 addenda). | `RollAlong/GameState.swift` | Trigger tests incl. all-8-tracks and golden-gauntlet completion; `daily_first_start` fires on first `startDailyChallenge()` (item-18 latch, no view edit); streak trophies latch (a missed day never revokes) | M | S1-T1 (same file) | ENG |
| S1-T3 | **Minigame funnel hooks.** `recordMinigameResult` (GameState.swift:1278), `recordCompetitiveWin` (:1260), `recordPinballScore` (:1178), `recordGoldRushCoins` (:1188), `recordRollUpRun` (:1203), `addZenSeconds` (:1219), `markModePlayed` (:825), per-difficulty dicts (:331-344). | `RollAlong/GameState.swift` | Trigger tests per mode incl. difficulty-specific trophies; ticket-earn trophies fire via `recordCompetitiveWin` only | M | S1-T2 (same file) | ENG |
| S1-T4 | **Reroute Disco + Roll Out bests through GameState.** Both write `minigameBests` directly in-view (DiscoBallView.swift:692, RollOutView.swift:591-593 — verified still true at `origin/main`) — add `recordDiscoResult`/`recordRollOutResult` funnels and call them from the views, then hook trophies there. | `RollAlong/GameState.swift`, `RollAlong/DiscoBallView.swift`, `RollAlong/RollOutView.swift` | Bests behave identically pre/post reroute (regression test); trophies fire from the new funnels; no other view writes `minigameBests` directly (grep-verified) | M | S1-T3 (same file) | ENG |
| S1-T5 | **Cosmetic + economy hooks.** `grant` (GameState.swift:1541) as the single "cosmetic acquired" choke point; `completedBundleIDs` (:1507); coin-purchase latch for `cosmetic_first_buy` at `purchase` (:1557) / `purchaseBundle` (:1589) / `purchasePack` (:1619) — **all three are GameState funnels now**: PR #120 (merged) moved the bundle buy out of CosmeticShopView into `purchaseBundle(_:price:)` and added the persisted `ra_paidPrices` ledger (refund bookkeeping only — it never affects ownership sets or trophy criteria); lifetime-coins-earned via S0-T2. **Exclusion sets are load-bearing — and neither is the iconic set:** define a dedicated, unit-tested trophy exclusion constant = exactly the 4 IAP secrets **{diamond, moneyBall, moneyRoll, moneyFull}**, applied to every collection criterion. `collection_complete` **additionally** excludes the 7 seasonal `isBundleExclusive` balls (their bundle windows are hard-coded one-shot 2026–27 ranges — requiring them makes the trophy time-limited and eventually dead), scoping it to the **207-item evergreen set** (218 − 4 IAP secrets − 7 seasonal) per trophy-catalog.md §3.6 / open Q10 — pending Mac's Q10 ruling (recurring seasonal windows would restore the full 214). Do **not** reuse `isIconic`/`iconicBalls` (Cosmetics.swift:45-51, :107) — Iconic = starter looks + {Trophy, Diamond, Money Ball} (verified at `origin/main`; Aurora is NOT in it), and the starter looks and the earned-exclusive **Trophy ball** DO count toward collection criteria per trophy-catalog.md §3.6 (as does coin-buyable Aurora); reusing it would silently miscount `collection_complete` and `balls_own_10/40`. Counting the 4 IAP secrets, conversely, creates a ~$150 pay-gated trophy (f2p research §7.7). | `RollAlong/GameState.swift` | Completion-trophy tests prove Money/Diamond ownership neither helps nor hurts AND that Trophy ball/Aurora/starters DO count; base exclusion constant unit-tested against exactly the 4 IAP-secret rawValues; `collection_complete` test proves the 7 seasonal `isBundleExclusive` balls are also excluded (207-item evergreen denominator — re-verify against Mac's Q10 ruling before freeze); bundle-completion trophy fires on `completedBundleIDs` change; no trophy references a purchase or IAP count | M | S1-T4 (same file) | ENG |
| S1-T6 | **Social hooks.** The full catalog §6 item-14 latch set: **sign-in latch** on `SocialClient.setSession` success (`social_sign_in`), first-friend + accepted-friend high-water (accept path, SocialClient.swift:394 / FriendsView → `social_first_friend`, `social_friends_5`), clan create/join (SocialClient.swift:470/:491 / ClansView → `clan_join`), life gifted — friend send (:314) + clan fulfillment paths → `social_send_life`, `social_lives_sent_25`, `clan_fulfill`. No result-shared or lives-received hooks: no catalog trophy consumes them. Early trophies deliberately point at Friends/Clans (retention hand-off, f2p research §1). Signed-out players: these trophies simply remain locked — no error paths. | `RollAlong/FriendsView.swift`, `RollAlong/ClansView.swift`, `RollAlong/SocialClient.swift` (success paths) | Trigger tests via mocked success paths covering all 7 Social trophies; no trophy requires another player to *exist* beyond one friend/clan action (no population-dependent rot) | M | S0 gate (parallel with S1-T1..T5) | BE |
| S1-T7 | **View-layer event hooks** (the trophy-catalog.md §6 items — 7, 8, 9, 11, 13 — that no GameState funnel can see; pattern per S1-T4: views call **new GameState funnels**, trophy checks live in the funnel, never in the view). (1) **Tutorial-fall event** from the fell path (`fireFell`, BallGameView.swift — falls on L1–10 are tutorial-exempt and never call `consumeLife`, so `whimsy_gravity_check` and the no-fall-streak reset need a direct `recordFall(level:mode:)`-style funnel); (2) **Coin Pit stake-count hook** at round start (stake overlay Start action, BallGameView.swift:4564 / `spendTickets`) → `whimsy_high_roller`; (3) **run-lifecycle flags** for `skill_first_try` (no prior clear, no fall/restart before the goal — post-#118, BallGameView no longer computes `isFirstClear`: derive "no prior clear" from `time(for: level) == nil` BEFORE `recordResult` stamps it, catalog §6 item 7) and `skill_spotless` (3 stars + all 3 pickups this run) — run state only BallGameView knows, passed into `recordResult`; (4) **PinballScene ROLL-lanes-complete-per-ball event** (PinballView.swift) → `whimsy_roll_call` — **EXTERNALLY BLOCKED (§7):** the SpriteKit rebuild itself has landed (PinballScene is live at HEAD), but the shipped table has no ROLL rollover lanes — they are an unbuilt pinball-roadmap item, so there is nothing to wire yet. Carved out of this task's and S1-T9's coverage gate pending Mac's catalog open-Q9 ruling (hold back vs substitute a shipped-table whimsy); wire + verify the event only once the lanes exist. | `RollAlong/BallGameView.swift`, `RollAlong/PinballView.swift`, `RollAlong/GameState.swift` (new funnels) | Trigger tests for the four wireable trophies via the new funnels (`whimsy_roll_call` excluded — blocked on the unbuilt ROLL lanes, §7); a fall on climb L1 fires `whimsy_gravity_check` without consuming a life; stake hook fires only on round start (never on refund); first-try flag resets on fall/restart; all funnels mode-guarded (CotD/other modes don't pollute) | M | S1-T5 (GameState lane serializes) | ENG |
| S1-T8 | **Cumulative progress + offline-safe recording.** Progress snapshots for UI (`percent toward threshold`); unlock writes are synchronous UserDefaults at unlock time; a `ra_trophySyncDirty` flag (full-snapshot sync pattern — internal-data-backend.md §7 — replaces a fragile per-event outbox) armed on every unlock for S3 to drain. | `RollAlong/TrophyEngine.swift` | Kill-the-app-after-unlock test: unlock survives relaunch; dirty flag survives relaunch; progress API returns monotonic values | M | S1-T1..T7 | ENG |
| S1-T9 | **Full trigger test sweep.** One test per catalog trophy minimum, boundary + double-unlock idempotency matrix, all through public API (no engine internals). This is the S1 gate artifact. | `RollAlongTests/TrophyEngineTests.swift` | 100% of v1 catalog covered — sole allowed exception: `whimsy_roll_call` (blocked on the unbuilt pinball ROLL lanes, §7; hold-back vs substitute per catalog open Q9); suite runs in CI-viable time (<60s) | L | S1-T1..T8 | QA |

### S2 — Presentation (players can see it)

Exit criteria: unlock moments feel right on device, Trophy Room navigable, VoiceOver smoke pass,
no toast can interrupt an active tilt run.

| ID | Task | Files | Acceptance criteria | Size | Deps | Owner |
|----|------|-------|---------------------|------|------|-------|
| S2-T1 | **Toast component + queue.** Tier-differentiated banner (per-grade styling for every rung of the ruled D10 ladder — Bronze / Silver / Gold / **Diamond**, RULED 2026-07-02; the "Platinum" capstone hands off to S2-T5); unlocks earned mid-run are queued and presented **coalesced at run end** — never during play (tilt game; f2p research §7.10). **Binding Diamond riders (design.md §2 R2):** the Diamond grade gets its own glyph/color treatment, visually and contextually distinct from the Diamond ball / Iconic cosmetic gating tier (the $19.99 paid exclusive); toast copy never reads "Diamond cosmetic" for the grade nor "Diamond trophy" for the cosmetic. Accessible: VoiceOver announcement, Dynamic Type, Reduce Motion honored. | `RollAlong/TrophyToastView.swift` | Queue coalesces N unlocks into one batched presentation; zero presentation while a run is active (unit-test the queue's gating); VoiceOver announces title + tier; Diamond-grade glyph/color shares no iconography with the Diamond-ball cosmetic treatment, and copy follows the disambiguation riders (design.md §2/§6) | M | S1 gate | UI |
| S2-T2 | **Surface wiring.** Present the toast queue at: climb `winOverlay`/fell/out-of-lives overlays (BallGameView.swift:4109, :765-781), each minigame result overlay, GameMenuView return. Reuse the existing celebration grammar (shop collection toast CosmeticShopView.swift:166, IAP `DeliveryReceipt`). | `RollAlong/BallGameView.swift`, minigame views, `RollAlong/GameMenuView.swift` | Manual matrix: earn a trophy in climb / each minigame class / daily → toast appears at result screen only; no frame hitch on presentation | L | S2-T1 | UI |
| S2-T3 | **Trophy Room UI.** New screen: grouped by category, locked/unlocked/progress states, secret trophies masked until earned (spoilers-only policy), rarity slot rendering "—" until S3 feeds it, header with overall completion % + per-grade counts (a points level is explicitly NOT v1 — design.md §2 ships grades + capstone only). Entry tile in Home nav grid (HomeView.swift:319-330). | `RollAlong/TrophyRoomView.swift`, `RollAlong/HomeView.swift` | Renders full catalog from TrophyEngine only (no direct GameState reads); scrolls smoothly with all v1 trophies; secret trophies leak nothing pre-unlock | L | S2-T1 | UI |
| S2-T4 | **Profile integration.** Replace the view-private 11-badge wall (ProfileView.swift:388-474) with engine-backed persisted trophies (keeps the card's visual slot); showcase pinned/recent trophies; drop the pay-gated "Unlimited Power" badge pattern (internal-economy.md §4). PublicProfileView display is S3 territory (S3-T9, needs server data) — leave a seam, not a fake. | `RollAlong/ProfileView.swift` | Badge card shows persisted unlocks with timestamps; nothing un-earns after `resetProgress()`/liquidation (device-verified); old badge definitions retired in the same PR | M | S2-T3 | UI |
| S2-T5 | **Capstone celebration.** Full-screen one-time moment for the capstone **"Platinum"** (display name RULED 2026-07-02; id `capstone_all` unchanged) — unique sound + haptics + confetti — auto-offers a `ResultShareCard`-based share. Escalate exactly once — standard unlocks stay small (PS research: single escalation). | `RollAlong/TrophyToastView.swift` (+ share card reuse in `Cosmetics.swift` read-only) | Fires exactly once ever (latched); share card renders trophy art + name; Reduce Motion swaps confetti for a static treatment | M | S2-T1 | UI |
| S2-T6 | **Retroactive-grant reveal.** Consume S0-T4's backfill flag: first open after update shows one "Trophy Room unlocked — you've already earned N" moment (in Trophy Room or as a single banner), not N toasts. | `RollAlong/TrophyRoomView.swift`, `RollAlong/TrophyToastView.swift` | Veteran-save fixture on device shows exactly one coalesced reveal; flag clears after presentation | S | S2-T3, S0-T4 | UI |
| S2-T7 | **Trophy pinning + chase chips.** Pin up to 3 trophies from the Trophy Room; pinned trophies surface as a compact progress chip on `GameMenuView` and pre-run screens (design.md §7 — the standing answer to "what am I chasing?"). Pin state is a local `ra_trophyPins` key; chips read TrophyEngine's progress API only. | `RollAlong/TrophyRoomView.swift`, `RollAlong/GameMenuView.swift` | Pins persist across relaunch; chip shows live progress and updates after a run; VoiceOver labels on pin controls and chips | S | S2-T3 | UI |

### S3 — Rarity backend (per design.md's architecture ruling)

Exit criteria: unlocks reach the server and survive offline/replay — the **anonymous rail counts all
players** (design.md §4 Option C / decision #13: without it, rarity exists for ~0% of players), the
signed-in rail powers showcases; rarity labels correct against synthetic cohorts; delete-account and
reinstall semantics verified. S3-T6 is conditional on D2, S3-T8 on D11, S3-T9 on D6.

| ID | Task | Files | Acceptance criteria | Size | Deps | Owner |
|----|------|-------|---------------------|------|------|-------|
| S3-T1 | **Supabase schema migration.** Three objects per design.md §4 Option C: (1) **`trophy_unlocks(install_id, trophy_id, unlocked_at timestamptz DEFAULT now())`** — the anonymous rarity rail (design decision #13, gated as D12): UNIQUE (install_id, trophy_id), **INSERT-only for anon** (upsert-ignore = idempotent; server-side timestamp, ignore client clocks); (2) `player_trophies(player_id FK → players ON DELETE CASCADE, trophy_id, unlocked_at)` — the signed-in showcase rail; (3) `trophy_stats(trophy_id, earned_count, denominator, pct, is_paused boolean DEFAULT false)` aggregate — `is_paused` is the per-trophy display kill-switch from design.md §9. RLS: anon INSERT-only (never SELECT) on `trophy_unlocks`; own-row write for `player_trophies`; `trophy_stats` gets the project's **first anon-readable SELECT** — aggregates only, never raw unlock rows (internal-data-backend.md §6). Enter as a proper managed migration; DDL copy into `docs/trophies/`. | Supabase project `mhwpcwauzvmtmuphtajs` (migration), `docs/trophies/trophy-schema.sql` | Migration applies on a dev branch; RLS verified: anon can INSERT `trophy_unlocks` but never read/update/delete it, and can read `trophy_stats` only; duplicate (install_id, trophy_id) insert is a no-op; authenticated can write only own `player_trophies` rows; cascade delete from `players` removes `player_trophies` and leaves `trophy_unlocks` untouched | M | S0-T1 (frozen IDs), D12; may run during S1 | BE |
| S3-T2 | **Rarity rollup job.** Scheduled aggregation (pg_cron or edge function per design.md) computing `earned_count` per trophy **from `trophy_unlocks` — the anonymous rail, never `player_trophies`** — over the denominator per D3 (design decision #5 recommends **distinct install UUIDs** from `events` `app_launch`: the *same UUID rail as the numerator*, so numerator and denominator can never diverge across the two identity systems that deliberately never join; document the double-count caveats). Increment-only counters survive account deletion (recommendation (b), internal-data-backend.md §6.3). | Supabase (function/cron), `docs/trophies/trophy-schema.sql` | Rollup produces correct counts on seeded data; counts include unlocks from installs that never signed in; deleting a player does not decrement `trophy_stats`; cadence documented | M | S3-T1 | BE |
| S3-T3 | **Client sync service.** Idempotent **full-snapshot upsert** of all unlocked ids on launch/foreground/sign-in when `ra_trophySyncDirty` (converts one-shot unlocks into self-healing snapshots — the codebase's proven pattern; no fragile per-event queue). **Two push paths:** (1) *all* players — signed-in or not — push to `trophy_unlocks` keyed by the install UUID (anon INSERT, upsert-ignore; do NOT route through `AnalyticsClient`, its buffer is memory-only); (2) signed-in players additionally upsert `player_trophies` (showcase rail). Signed-out players therefore still count for rarity; only the `player_trophies` push is a silent no-op until sign-in. Flag clears only when every applicable path succeeds. Never a hydrate that *overwrites* local. | `RollAlong/TrophySyncService.swift`, `RollAlong/SocialClient.swift` (thin REST additions) | Offline unlock → relaunch online → exactly one `trophy_unlocks` row per trophy (replay test), plus `player_trophies` rows when signed in; a signed-out unlock reaches `trophy_unlocks`; repeated syncs are no-ops; signed-out never throws into UI | L | S1-T8, S3-T1 | BE |
| S3-T4 | **Rarity display wiring + cold-start rules.** Fetch `trophy_stats` into Trophy Room; **suppress percentages below the minimum-population threshold from design.md** (players table has 1 row today — day-1 numbers are noise); tier labels first, raw % on detail view only. Honor the `is_paused` flag: a paused trophy renders its rarity slot hidden/disabled (the design.md §9 kill-switch for a glitched trophy). | `RollAlong/TrophySyncService.swift`, `RollAlong/TrophyRoomView.swift` | Below threshold: UI shows "—"/no label, no 100%/0% ever renders; at threshold: labels match cutoffs from design.md; rarity display uses **no diamond iconography at any band** (binding Diamond rider, design.md §2 R2 / §3 — the diamond glyph belongs to the Diamond trophy grade, never to rarity); a row with `is_paused = true` renders hidden/disabled; signed-out players still see rarity (anon read) | M | S3-T2, S2-T3 | BE |
| S3-T5 | **Delete-account + reinstall handling.** Verify `delete-account` edge function needs no change (cascade covers `player_trophies`); implement trophy **hydrate-on-sign-in as max-merge union** (server unlock set ∪ local unlock set — the app's first server→local restore path, trophies only, per D7); reinstall semantics for anonymous players depend on D11: if the iCloud KV mirror ships (S3-T8), it closes the hole; if D11 = no, document that UserDefaults-only players keep today's loss-on-reinstall semantics. | `RollAlong/TrophySyncService.swift`, Supabase (verification only) | Delete account → player_trophies gone, trophy_stats unchanged; reinstall + sign-in → server trophies reappear locally and local-only unlocks push up (union, never subtraction) | M | S3-T3 | BE |
| S3-T6 | **Game Center mirror (CONDITIONAL on D2).** `GameCenterMirror`: silent `authenticateHandler` at launch, catalog→GC achievement id map, re-report all unlocked at 100% on launch (idempotent, GC keeps max), `showsCompletionBanner = false` (custom toast owns the moment), read `rarityPercent` (nil-tolerant) as a second rarity source. ASC config + 1024×1024 art per achievement + ≥1 localization are **Mac-owned assets** — flag early. | NEW `RollAlong/GameCenterMirror.swift`, `project.pbxproj`, App Store Connect | Declined sign-in degrades to custom-only silently; report queue survives kill; no GameKit type leaks into views other than the mirror; only trophies with final criteria are mirrored (permanent-ID rule) | L | D2 ruling, S3-T3 | BE |
| S3-T7 | **Synthetic-cohort rarity QA.** On a Supabase dev branch, seed N synthetic installs (`trophy_unlocks`) + players spanning the tier cutoffs and the suppression threshold; verify math, labels, and suppression end-to-end in-app. | Supabase dev branch, `RollAlongTests/` (parser/label unit tests) | Cutoff boundary cases (exactly at each tier edge) label correctly; suppression flips at exactly the threshold; dev branch torn down after | M | S3-T4 | QA |
| S3-T8 | **iCloud KV trophy-ratchet mirror (CONDITIONAL on D11 — design decision #7, a posture change).** Mirror `ra_trophyUnlocks`/`ra_trophyUnlockDates` to `NSUbiquitousKeyValueStore` (the ratchet is tiny — well under the 1 MB / 1024-key caps); merge rule is **union with max-merge on timestamps, never subtraction** (design.md §4). Requires adding the iCloud KV entitlement — a **Mac-owned capability change** (today's posture is "no iCloud KV in use"); flag before the session starts. | `RollAlong/TrophyEngine.swift` (mirror helper), entitlements file, `project.pbxproj` if a new file is added | Delete + reinstall without a backup restores the unlock set; two-device divergence test converges both devices to the union; kill-app-mid-write leaves a consistent ratchet; if D11 = no, this task is skipped and S3-T5's loss-on-reinstall documentation stands | M | D11 ruling, S0-T3 (unlock store), S1 gate (ENG lane free) | ENG |
| S3-T9 | **Public showcase + Settings toggle (gated on D6 — design decision #10).** Per design.md §7: sync per-grade counts + up to 3 showcased trophy ids (player-chosen, default = rarest earned) on the signed-in rail (schema addition: showcase columns or a small `player_showcase` table — decide in the migration, DDL copy in `docs/trophies/`); render on `PublicProfileView` (fills S2-T4's seam); Settings toggle, **default on for signed-in players** per the design recommendation. | Supabase (migration), `RollAlong/TrophySyncService.swift`, `RollAlong/PublicProfileView.swift`, `RollAlong/SettingsView.swift` | Showcase renders on a friend's public profile with correct grade counts; toggle off removes it server-side (not just hides locally); default state matches D6's ruling; signed-out viewers can see a signed-in player's showcase | M | S3-T3, S2-T4 (seam), D6 ruling | BE |

### S4 — Hardening & launch

Exit criteria: launch checklist fully checked, beta acceptance criteria met, submission ready.

| ID | Task | Files | Acceptance criteria | Size | Deps | Owner |
|----|------|-------|---------------------|------|------|-------|
| S4-T1 | **Full QA regression pass.** Run the entire §5 matrix on device + simulator; regression sweep over GameState behaviors (economy, lives, resets), profiles, leaderboards. | all (read), `RollAlongTests/` | Matrix green; zero regressions filed or all triaged | L | S2+S3 gates | QA |
| S4-T2 | **Performance validation.** Unlock checks must never hitch the game loop: `consumeLife`/`recordResult` fire mid-run — measure evaluation cost there; assert no main-thread I/O storms; add trophy micro-benchmarks to `PerformanceTests.swift`; Instruments pass on device. | `RollAlongTests/PerformanceTests.swift` | Per-bump evaluation under budget (target <0.5ms p99 on oldest supported device); zero frame drops attributable to trophy writes in a 10-min play session | M | S4-T1 | QA |
| S4-T3 | **Accessibility pass.** VoiceOver through Trophy Room, toasts, capstone; Dynamic Type XL; Reduce Motion. | `RollAlong/TrophyRoomView.swift`, `TrophyToastView.swift` (fixes) | Every trophy element has a label; unlock announced; no motion-triggered content behind Reduce Motion | S | S4-T1 | UI |
| S4-T4 | **TestFlight beta + trophy-hunter loop.** Beta build with trophy funnel telemetry (`trophy_unlocked` analytics event piggybacking the existing rail); structured feedback prompts for hunters (clarity, grind feel, missing categories); one tuning pass on thresholds — **this is the last window before criteria freeze**. **Beta traffic must not pollute production rarity:** beta installs hit the same `trophy_unlocks`/`events` rail, so decide and document one of — (a) tag beta installs (build-type column or the events build tag) and exclude them in the S3-T2 rollup and the 500-install cold-start count, or (b) truncate `trophy_unlocks` and re-baseline `trophy_stats` before public launch; state explicitly whether beta-era unlock rows earned under pre-freeze criteria (e.g. a re-tuned `pinball_score_50k`) are kept or purged. | TestFlight, `RollAlong/AnalyticsClient.swift` call sites | Beta acceptance criteria (§5) met; tuning changes land as one reviewed PR; beta-data handling decision recorded and implemented before launch; funnel queries appended to `docs/soft-launch-metrics.sql` | M | S4-T1..T3 | QA + ENG |
| S4-T5 | **App Store metadata + privacy review.** Verify trophy sync stays in the not-linked envelope or update `PrivacyInfo.xcprivacy` + App Privacy answers (note: `docs/AppStore.md` privacy copy is already stale — do not cite it); review-guideline check; screenshots/release notes if Trophy Room is marketed. | `RollAlong/PrivacyInfo.xcprivacy`, `docs/AppStore.md`, ASC | Privacy manifest accurate for `player_trophies` + `trophy_stats` traffic; no guideline flags; metadata drafted for Mac's approval | M | S3 gate | BE + REV |
| S4-T6 | **Launch checklist + freeze.** IDs, criteria, and tiers frozen and recorded (point weights are deferred to the GC phase per trophy-catalog.md Q6 — nothing to freeze in v1); rarity suppression threshold configured; beta-data handling per S4-T4 verified done; migration re-tested against a fresh TestFlight-restored save; economy note per D1 is **DONE (2026-07-02)** — "trophies never mint coins" recorded as the trophy-system addendum in `docs/economy/07-decisions.md` (the rulings log, on main since PR #113) with the one-line pointer from `docs/economy/README.md` in place; S4-T6 only re-verifies both at freeze, nothing is queued; rollback plan (feature-flag the Trophy Room entry tile; `is_paused` display kill-switch verified). | `docs/trophies/sprint-plan.md` (status), `docs/trophies/trophy-catalog.md` (freeze stamp) | Every checklist item checked in the PR description; Mac signs off | S | S4-T1..T5 | REV |

## 3. Workforce roster

| Role | Handle | Owns | Standing instructions |
|------|--------|------|----------------------|
| Trophy-engine engineer | **ENG** | S0-T1..T4, S1-T1..T5, S1-T7 (view hooks), S1-T8, S3-T8 (if D11), S4-T4 (tuning) | **Sole writer of `GameState.swift`, `TrophyEngine.swift`, `TrophyStats.swift`, `TrophyCatalog.swift`** — plus the S1-T7 event-hook edits to `BallGameView.swift`/`PinballView.swift` (S1-T4 precedent; announce in the PR, UI lane holds off). Read design.md + trophy-catalog.md + §4 before every session. Tests accompany every trigger. Never write `coinBalance` directly (use `addCoins`, 60k single-award clamp post-#124). Anchor on symbols, not line numbers. |
| UI engineer | **UI** | S2-T1..T7, S4-T3 | Owns `TrophyRoomView.swift`, `TrophyToastView.swift`, and the S2 edits to `ProfileView`/`HomeView`/`BallGameView`/`GameMenuView`/minigame views. Read §4(b) (ViewBuilder rule) and §4(c) before touching SwiftUI. Reads TrophyEngine's public API only — no GameState spelunking. |
| Backend engineer | **BE** | S1-T6, S3-T1..T6, S3-T9 (if D6), S4-T5 | Owns `TrophySyncService.swift`, `SocialClient.swift` edits, `GameCenterMirror.swift`, `PublicProfileView`/`SettingsView` showcase edits (S3-T9), Supabase migrations (MCP, dev-branch first). Schema changes ship as managed migrations + DDL copies in `docs/trophies/`. Never grant anon SELECT on row-level unlock data (`trophy_unlocks` is anon INSERT-only). |
| QA verifier | **QA** | S0-T5, S1-T9, S3-T7, S4-T1/T2/T4, all sprint gates | Owns `RollAlongTests/Trophy*.swift` + `PerformanceTests.swift` additions. Gates every sprint: no next-sprint task starts until the gate is green. Prefers unit tests over XCUITest (§4g). Builds save-data fixtures from real `ra_*` dumps. |
| Code-reviewer | **REV** | Every PR; S4-T5/T6 | Runs `/code-review` on each PR; enforces the §4 checklist mechanically (pbxproj entries present, no `git add -A`, exhaustive switches updated, xcodebuild evidence in PR); checks that no trophy criterion references IAP, time-limited content, or specific level layouts. |

**Parallel-lane safety:**

- **Safe in parallel** (disjoint files): S2 (UI lane: new view files + ProfileView/HomeView) ∥ S3 (BE lane:
  sync service + SocialClient + Supabase). S3-T1/T2 (pure backend) ∥ all of S1. S1-T6 (social views) ∥
  S1-T1..T5 (GameState).
- **Must serialize:** anything touching `GameState.swift` (S0-T2 → S1-T1 → T2 → T3 → T4 → T5 → T7, one
  session at a time — this is the plan's critical path); `project.pbxproj` (mitigated by S0-T1
  pre-registering all planned files — any later new file needs a coordination note in the PR);
  `BallGameView.swift` (S1-T7 → S2-T2, in that order); `TrophyToastView.swift` (S2-T1 → T5 → T6).
- **Hive-mind rule:** before starting, `git log --oneline -5` your branch — a concurrent agent may have
  committed; rebase mentally, stage only your own paths.

**Per-session handoff checklist (every agent, every session, no exceptions):**

- [ ] Read §4 of this doc + `design.md` + `trophy-catalog.md` before writing code; read the research doc
      your task cites (e.g. S1 tasks → `internal-features.md` §3) for hook-point details.
- [ ] Re-locate every `file:line` ref by symbol name before editing — lines drift (GameState refs in
      this plan were re-anchored to `origin/main` `42d1925` on 2026-07-02; re-locate regardless).
- [ ] New files: 4 pbxproj entries each (app target) / same for test target — verify by building.
- [ ] Tests written or extended for the task's acceptance criteria; suite green locally.
- [ ] `xcodebuild` green (Xcode 26.5); paste the tail of the build output in the PR description.
- [ ] `git add <explicit paths>` only; commit message references the task id (e.g. `S1-T3: minigame funnel hooks`).
- [ ] PR notes: what's done, what's deliberately deferred, any drift discovered vs. this plan (flag it —
      the delivery lead updates the plan, agents don't silently diverge).
- [ ] If blocked on a D-ruling (§7): stop, write up the smallest question, do not guess.

## 4. Roll Along engineering gotchas — MANDATORY briefing for every implementation agent

Read this before writing any code. Violations are the top historical cause of broken builds in this repo.

- **(a) pbxproj registration:** every new `.swift` file needs **4 manual `project.pbxproj` entries**
  (explicit file refs — this project has no synchronized groups) or the build breaks. Test-target files
  need the same treatment against the test target. S0-T1 pre-registers this plan's files; if you add an
  unplanned file, you own its 4 entries.
- **(b) No nested `func` + `return` inside SwiftUI ViewBuilder closures** — it breaks result builders and
  cascades into misleading "Content could not be inferred" errors. Hoist helpers to methods on the view.
- **(c) A screenful of "Cannot find type X" errors** usually means a Swift type-checker **timeout on one
  expression**, not missing types. Break up the big expression; diagnose with
  `-warn-long-expression-type-checking` before chasing ghosts.
- **(d) Compile-verify before ending any session:** `xcodebuild` (Xcode 26.5 via `xcode-select`) must be
  green. Paste the result in your handoff/PR. Never hand off a red build.
- **(e) Concurrent agent writers exist** (hive-mind/pinball agents may commit to your branch mid-session):
  stage **explicit paths only** — `git add RollAlong/TrophyEngine.swift …` — **never `git add -A`**.
- **(f) Exhaustive-switch cosmetic wiring:** cosmetic enums are matched exhaustively across many files;
  if any task adds a cosmetic (e.g. a capstone regalia item per D8), follow the full add-a-cosmetic
  checklist (project memory: 7+ switch sites) or the build breaks silently elsewhere.
- **(g) XCUITest has known gotchas in this repo** — put trigger logic, migration, and queue behavior in
  unit tests (`RollAlongTests/`, injected-UserDefaults pattern from `GameStateTests.swift`). UI tests only
  for smoke, if at all.

Trophy-specific addenda (from the research, same severity):

- **Never key a trophy to a specific level layout** — climb levels are swappable content
  (`LevelOverrides.json`); key to lifetime stats only.
- **Exclude the Diamond ball + Money Ball/Roll/Full from every completion criterion** (secret IAP drops;
  counting them = a hidden ~$150 pay-gate and leaks the secret).
- **"Diamond" means two things now — never let them blur (D10 ruling riders, design.md §2 R2,
  2026-07-02):** the **Diamond trophy grade** and the **Diamond ball cosmetic** are distinct concepts.
  The grade's glyph/color never borrows the ball's treatment; rarity display never uses diamond
  iconography at any band; no regalia cosmetic references the Diamond ball; copy never says "Diamond
  trophy" of the cosmetic or "Diamond cosmetic" of the grade. (Enforced in S2-T1 and S3-T4 acceptance
  criteria.)
- **Trophy state is a ratchet.** Never derive unlocks live from regressable stats (`resetProgress`,
  `liquidateCoinCosmetics`, `liveStreak`); latch once, forever.
- **No coin values hardcoded against pre-reprice prices** — the economy calibration (PR #118) AND the
  tier reprice (PR #124: 750/1,000/1,250/1,500, bundle floors 5,500/6,500) are **MERGED** (2026-07-02);
  any coin-adjacent number re-derives against the live catalogue at the canonical ~25 coins/min
  (docs/economy/07-decisions.md ruling 2) and still goes through D1.
- **Analytics is fire-and-forget and non-replayable** — never make it the source of truth for an unlock;
  co-locate triggers with game logic (GameState funnels), emit analytics as a side effect. This includes
  the NEW `daily_challenge_level_cleared` event (merged CotD fast-path, PR #123): analytics-only, never
  a trophy trigger source — daily trophies key to `completeTodaysDailyChallenge`/`dailyChallengeCompletions`.
- **All coin awards go through `addCoins`** (single-award clamp 60,000 post-#124, balance cap 999,999).

## 5. QA plan

**Per-sprint gates (QA verifier owns; next sprint blocked until green):**

| Gate | Must hold |
|------|-----------|
| S0 → S1 | All S0 unit tests green; xcodebuild clean; zero visible behavior change; pbxproj complete for all stubs |
| S1 → S2/S3 | S1-T9 sweep green: every catalog trophy trigger-tested (including the S1-T7 view-layer hooks; sole exception `whimsy_roll_call`, externally blocked per §7 / catalog open Q9), boundary + double-unlock idempotency matrix passes; migration fixtures pass; unlock durability (kill-app) test passes |
| S2 → S4 | Device manual matrix (toast timing per surface); no mid-run presentation possible; VoiceOver smoke; retro-grant reveal verified on veteran fixture |
| S3 → S4 | Offline unlock → sync replay test (both rails); synthetic-cohort rarity correctness (S3-T7); delete-account cascade + reinstall max-merge verified; anon RLS verified (INSERT-only `trophy_unlocks`, read-only `trophy_stats`); if D11=yes: two-device iCloud KV divergence test; if D6=yes: showcase round-trip verified |
| S4 → ship | Full matrix + performance budget + beta acceptance criteria + launch checklist |

**Test matrix (the canonical list):**

1. **Every trigger unit-tested** through public GameState API — threshold−1 / threshold / threshold+1,
   and double-fire idempotency (unlock exactly once, timestamp stable).
2. **Migration tests from pre-trophy save data** — fresh / mid-progress / veteran `ra_*` fixtures →
   correct backfill set, legacy timestamps, idempotent across relaunches.
3. **Ratchet tests** — `resetProgress()`, `liquidateCoinCosmetics()`, streak breaks: unlocks and lifetime
   counters unaffected.
4. **Offline unlock → sync replay** — unlock offline, kill app, relaunch online: exactly one
   `trophy_unlocks` row per trophy on the anonymous rail (signed-in players get `player_trophies` rows
   too); repeat sync is a no-op; the dirty flag stays armed until every applicable path succeeds.
5. **Rarity pipeline with synthetic cohorts** — tier-cutoff boundaries, suppression threshold flip,
   deletion does not decrement aggregates.
6. **Toast performance + discipline** — coalescing under burst (10 unlocks in one run → 1 presentation);
   zero presentations mid-run; no dropped frames on presentation.
7. **VoiceOver pass** — room, toasts, capstone, secret-trophy masking.
8. **Economy invariants** — D1 RULED 2026-07-02: trophies never mint coins (prestige + earned-only
   regalia) — assert zero `addCoins` calls from trophy code (the test enforces the ruling; the
   "if D1 grants any coins" arm is retired).

**Regression risks to existing systems:**

| System | Risk | Watch |
|--------|------|-------|
| GameState | Hot-path cost in `consumeLife`/`recordResult`; accidental `@Published` trophy state re-rendering gameplay views; `ra_*` key collisions | S4-T2 benchmarks; S0-T3 acceptance (separate ObservableObject); key audit header (GameState.swift:5-27) updated |
| Profiles | Badge-wall replacement changes ProfileView layout; PublicProfileView expectations | S2-T4 visual parity; public display deferred to S3 |
| Leaderboards / SocialClient | New REST calls or schema breaking existing fetch paths; players-table untouched by design | S3-T3 additive-only; existing SocialClient tests still green |
| Economy | Coin injection (if D1 allows), retroactive lump grants | §5 economy invariants; internal-economy.md §5c math re-run against the merged reprice (PR #124, live since 2026-07-02) |
| Minigames | Disco/RollOut reroute (S1-T4) altering PB behavior | regression test pre/post parity |

**Beta acceptance criteria (S4-T4):**

- Crash-free sessions ≥ 99.5%; zero reports of a lost/unearned-then-revoked trophy.
- ≥ 90% of testers earn ≥ 1 trophy in their first session (discovery-map front-load working).
- Funnel sanity: first-trophy ~100%; median trophies-per-tester lands in a healthy mid-band.
  > **OPEN:** neither design.md nor trophy-catalog.md defines a capstone-progress/completion target band —
  > agree the numeric band with Mac before beta starts (the catalog's 0.2% capstone figure is a rarity
  > guess, not a beta criterion).
- Zero complaints of mid-run interruption; VoiceOver testers can navigate the room unassisted.
- One thresholds-tuning pass completed and re-verified before criteria freeze.

**Launch checklist (S4-T6 works this list; all boxes checked before submission):**

- [ ] Trophy IDs, criteria, and tiers frozen (point weights deferred to the GC phase per
      trophy-catalog.md Q6); freeze stamp + date recorded in `trophy-catalog.md`
      (immutability-after-publish is the cross-platform norm — treat it as law).
- [ ] Post-launch headroom documented: reserved id namespace (and GC point budget, if D2=yes) for
      future minigames/tracks.
- [ ] Migration re-verified against a real device save restored from TestFlight (not just fixtures).
- [ ] Rarity suppression threshold configured and verified against live row counts (D9).
- [ ] `player_trophies` cascade + `trophy_unlocks` anon-INSERT-only + `trophy_stats` anon-read RLS
      re-verified in production project.
- [ ] Beta data handled per the S4-T4 ruling: beta installs excluded from the rollup/denominator, or
      `trophy_unlocks` truncated and `trophy_stats` re-baselined pre-launch; decision recorded.
- [ ] Rollback ready: Trophy Room entry tile behind a feature flag; sync service no-ops if flagged off;
      per-trophy `is_paused` display kill-switch verified end-to-end (set flag → rarity slot hides).
- [ ] Trophy funnel queries appended to `docs/soft-launch-metrics.sql`; first-week review scheduled.
- [x] Economy note per D1 recorded ("trophies never mint coins") in `docs/economy/07-decisions.md`
      (+ README pointer) where balance passes will see it — **DONE 2026-07-02** (trophy-system addendum
      landed with the ruling; at freeze just re-verify both are still in place).
- [ ] Privacy manifest + App Privacy answers match actual trophy traffic; `docs/AppStore.md` refreshed
      or explicitly marked stale.
- [ ] If D2=yes: ASC achievements approved, art uploaded, GC config "Not Live" → live rides this release.
- [ ] `config`-level docs updated: this plan's scorecard statuses, `docs/trophies/` README pointer if added.

## 6. Risks & mitigations

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|------------|
| 1 | Save-data migration/backfill wrong (double grants, missed grants, toast storm on update) | Med | High | S0-T4 fixtures from real key dumps; idempotent backfill; S2-T6 coalesced reveal; re-test on TestFlight-restored save (S4-T6) |
| 2 | Rarity cold-start embarrassment (players table = 1 row today; 0%/100% labels) | High | Med | Hard suppression threshold before any % renders (S3-T4); tiers-first display; denominator decision documented (D3) |
| 3 | GC adoption assumptions wrong (`rarityPercent` nil for months; signed-out minority) | Med | Low | GC is a conditional mirror (D2), never the source of truth; custom room serves 100% of players; nil-tolerant UI |
| 4 | Catalog scope creep (89 → 150 trophies; GC 100-slot/1,000-point ceiling; Steam spam lesson) | Med | Med | trophy-catalog.md is the frozen scope (D4); id namespace rationed with post-launch headroom (point weights deferred to the GC phase); REV rejects unlisted trophies |
| 5 | Economy inflation if coin rewards chosen (bronze sweep = 1-2k coins week-1, retroactive lump at launch) | Med | High | Retired by the D1 ruling (2026-07-02): status + earned-only regalia, **never coins** — the coin arm is closed; the §5 invariant test asserts zero `addCoins` from trophy code |
| 6 | Concurrent-writer merge conflicts on `GameState.swift` / `project.pbxproj` | High | Med | Single-writer lane for GameState; S0-T1 pre-registers all files; explicit-path staging only; task-scoped branches |
| 7 | Unlock checks hitch the tilt game loop (evaluation inside `consumeLife`/`recordResult`) | Low | High | Metric-indexed evaluation (S0-T3); no hot-path JSON encodes; S4-T2 device benchmarks with a hard budget |
| 8 | Criteria immutability trap — shipping a trophy keyed to swappable levels, stale pre-reprice economy constants, or churning minigame scoring; IDs frozen too early for GC | Med | High | §4 addenda rules; S4-T4 tuning window before freeze; mirror only stable "canon" trophies to GC (S3-T6) |

## 7. Open items blocked on Mac's rulings (mapped to design.md §11)

`docs/trophies/design.md` landed the same day as this plan; the table below is **reconciled against its
§11 "Decisions for Mac" table** — the **"design.md §11 #" column is where Mac's actual ruling lives**;
this plan's D-handles are stable and are what the task tables reference. D4's ruling lives in design.md
§11 **#14** (the consolidated adopt-the-catalog decision) together with trophy-catalog.md's
"Open questions for Mac" section, which carries the item-level detail. **D1, D4, and D10 were
RULED 2026-07-02 — S0 is unblocked and kicked off the same day (branch `claude/trophies-s0`).**
The unruled handles below stay open.

| Ref | design.md §11 # | Decision (topic handle) | Blocks |
|-----|-----------------|------------------------|--------|
| D1 | **#3** | Reward philosophy: status-only vs. small coins vs. earned-regalia cosmetics at milestones — **RULED 2026-07-02: P2** (prestige + earned-only regalia; trophies never mint coins; economy-log addendum DONE same day) | S0-T1 (reward field), S1-T5, §5 economy invariants, S4-T6 economy note |
| D2 | **#9** | Game Center mirror: yes/no, and launch-with vs. fast-follow | S3-T6, ASC asset production (Mac-owned art + localizations), S4-T5 |
| D3 | **#5** | Rarity denominator: `players` (signed-in, biased) vs. distinct install UUIDs from `events` (recommended — same rail as the D12 numerator) vs. per-trophy eligible population | S3-T1/T2/T4 |
| D4 | **#14** (+ trophy-catalog.md open questions) | v1 catalog sign-off: trophy list, tiers, capstone condition (point weights deferred per catalog Q6) — **RULED 2026-07-02: catalog adopted as v1 scope** (89 trophies; 73-visible capstone; 5 hidden; point weights deferred; quarantined 4th tier) with naming overrides: rung 4 = **Diamond**, capstone display name = **Platinum**; all ids unchanged | S0-T1 and everything downstream |
| D5 | **#12** | Retroactive backfill semantics: legacy timestamps + coalesced reveal (planned default) vs. earn-fresh-from-zero — *open; proceeding per the planned default (grant from existing stats); Mac may veto* | S0-T4, S2-T6 |
| D6 | **#10** | Public-profile trophy showcase: default-on for signed-in with Settings toggle (design recommendation) vs. opt-in vs. own-profile only at launch | S2-T4 seam, S3-T1 RLS, S3-T9 |
| D7 | **#8** | Reinstall/hydrate semantics: trophies-only max-merge restore on sign-in (planned default) vs. keep strict one-way push | S3-T5 |
| D8 | **#3** (P2 detail) + catalog open Q2 | Capstone regalia cosmetic: mint a new earned-exclusive item (Trophy-ball gating pattern, triggers §4(f) wiring) or reuse existing — *P2/regalia approved 2026-07-02 (Q2 = yes); the mint-new vs reuse detail is still open. Binding rider: no regalia references the Diamond ball* | S2-T5, S1-T5, possible new cosmetic task |
| D9 | **#6** | Rarity display thresholds: tier cutoffs + minimum-population suppression value (design recommends 500 installs + 30 days) | S3-T4, S3-T7 |
| D10 | **#1 + #2** | Tier ladder shape + rung-4 name: five rungs recommended; "Summit" vs. the literal "Diamond" vs. the catalog's current "Legend" label — one word must win before ids/styling are cut — **RULED 2026-07-02: five rungs; rung 4 = "Diamond"** (Mac overruled Legend/Summit; R2 disambiguation riders binding — see design.md §2 and S2-T1/S3-T4 acceptance criteria). Ladder: Bronze → Silver → Gold → Diamond → Platinum | S0-T1 tier vocabulary, S2-T1 tier styling |
| D11 | **#7** | iCloud KV entitlement for the trophy ratchet (posture change from "no iCloud KV in use") | S3-T8, S3-T5 reinstall wording |
| D12 | **#13** | Anonymous unlock counting table (`trophy_unlocks`, INSERT-only anon; posture change: first anon-readable aggregate) — without it, rarity exists for ~0% of players | S3-T1/T2/T3, S3-T4 anon read |
| D13 | **#11** | Pay-adjacent trophies: none ever (design recommendation) vs. allow "own Diamond/Money" style — *open; D1's never-mint-coins ruling (2026-07-02) affirms the spirit, but the row awaits its own ruling* | S1-T5 exclusion set, REV checklist |

(design.md #4 — the hybrid rarity architecture, Option C — is the premise of the whole S3 sprint rather
than a single task gate; if Mac overrules it, S3 is re-planned, not patched.)

**External blockers (not design.md):** the economy calibration (PR #118) and the tier reprice
(PR #124: 750/1,000/1,250/1,500) are **both MERGED** (2026-07-02, `origin/main` `42d1925`) — the former
"wait for the reprice ruling" gate is gone; any D1 coin math re-derives against the live catalogue NOW
(catalog §6 item 16 is unblocked and mandatory before the S4-T6 freeze). The CotD `.oneShot` fast-path
(PR #123) and track-coin-masking fix (PR #119) are merged too — S1-T1/T2 test the MERGED behavior (the
climb-record pollution bug is fixed at source; the trophy-side guard is defense-in-depth). Remaining
true externals: ASC achievement art (1024×1024 per trophy) and localization strings are Mac-owned
deliverables if D2 is yes. And the **pinball ROLL rollover lanes do not exist in the shipped table** —
the SpriteKit rebuild itself has landed, but the lanes are a still-unbuilt pinball-roadmap item —
blocking `whimsy_roll_call` (carved out of S1-T7/S1-T9; catalog open Q9 rules hold-back vs substitute).
