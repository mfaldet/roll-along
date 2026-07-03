# Repo Delta Audit — 064f3cd → origin/main (2026-07-02)

> Purpose: the trophy doc package (`design.md`, `trophy-catalog.md`, `sprint-plan.md`,
> and the three `internal-*.md` research audits) was verified against commit `064f3cd`.
> Since then **origin/main gained 36 commits** (all merged 2026-07-02). This doc is the
> authoritative list of what changed that MATTERS to those docs, what each change
> invalidates, and the corrected `GameState.swift` line refs. Read this BEFORE trusting
> any merge-state claim, coin figure, or `file:line` ref in the trophy docs.

- **Commit range audited:** `064f3cd..origin/main`
- **origin/main at audit time:** **`42d1925`** ("Merge pull request #124 from mfaldet/claude/economy-reprice-v2")
- **Merged PRs in range:** #113 (economy briefing docs), #118 (economy calibration-1),
  #119 (track-coin masking fix), #120 (sell-back mint fix / `paidPrices` ledger),
  #122 (clan chat + settings), #123 (CotD `.oneShot` fast-path), #114 (Starter Pack →
  Aurora collection), **#124 (the tier reprice — see headline below)**.

## 0. HEADLINE: the tier reprice is MERGED, not pending

Every trophy doc treats the 750/1,000/1,250/1,500 reprice as "pending Mac's approval"
(and several conflate it with "PR #118"). Both framings are now wrong:

1. **PR #118 (calibration-1) is merged** (`c7ed47c`): sell-back → `min(coinCost/2, paidPrice)`,
   minigame difficulty multipliers 1×/1.5×/2× (was 0.5×/1×/2×), climb replay parity +
   tier-scaled clear payouts, Sumo/MarbleCup/Pinball/RollOut payout buffs, CotD
   `.oneShot` fast-path, dead `goldRushMaxStake` deleted.
2. **PR #124 (the reprice itself) is ALSO merged** (`42d1925` — the current main tip;
   branch `claude/economy-reprice-v2`, previously described as "awaiting approval").
   `docs/economy/08-reprice.md` records it as **SHIPPED**. Live values:
   - `CosmeticTier.basePrice`: **750 / 1,000 / 1,250 / 1,500** (was 50/100/200/500).
   - Bundle rarity floors: `rareFloor` **5,500**, `legendaryFloor` **6,500** (was 700/1,100);
     bundle `fullPrice` now runs 4,500–13,500 across the 66 bundles.
   - IAP coin packs re-anchored: product IDs keep historical names but `rewardCoins` is now
     **750 / 4,500 / 10,000 / 22,500 / 60,000** for $0.99/$4.99/$9.99/$19.99/$49.99.
   - `GameState.maxSingleAward`: **60,000** (was 10,000).
   - Canonical earn rate for time-to-afford math: **~25 coins/min** (Standard = 30 min,
     Rare 40, Epic 50, Legendary 60 — docs/economy/07-decisions.md ruling 2).
   - Standing invariants (test-pinned): every tier price stays EVEN forever (sell-back
     halves exactly); prices only ever drift UP.

**Consequence:** there is no longer any "wait for the reprice ruling" gate. The catalog's
§6 item 16 price re-derivation pass is **unblocked and mandatory now** — every HEAD-price
figure in the docs is stale (see table rows 4–6).

## 1. Material changes table

| # | What changed on main | Trophy doc / section it invalidates | Required correction |
|---|---|---|---|
| 1 | **Sell Back is no longer a 100% refund.** `sellBackValue(item) = min(coinCost/2, paidPrices[key] ?? coinCost)` (GameState.swift:685); `liquidateCoinCosmetics` refunds that and clears the item's `paidPrices` entry. | `trophy-catalog.md` §3.7 preamble ("Sell Back makes spend counters infinitely farmable at HEAD") and the `econ_working_capital` row note ("farmable via buy→sell at HEAD's 100% refund — the exclusion is load-bearing"); `sprint-plan.md` S0-T2 ("sell-back at HEAD refunds 100% — infinitely farmable"); `design.md` §1 principle 2 + decision #11 rationale ("Sell Back makes spend-counters farmable anyway"); `internal-economy.md` §1 table, §3, §5b. | The DESIGN survives; the RATIONALE must change. Correct post-#118 rationale: sell-back refunds 50% of the current price capped at what was paid, so buy→sell no longer mints coins — but refunds are still **recycled capital, not play income**: a coins-EARNED counter that counted refunds would jump on any wardrobe liquidation without play, and a coins-SPENT counter is still churnable (at a 50%-loss per cycle, no longer free). So: keep banning spend counters, keep `econ_working_capital` as earned-from-play **excluding IAP grants AND Sell Back refunds** — and now ALSO excluding `grantBundleFree`'s compensation credits (see row 8). |
| 2 | **Climb pays on EVERY clear, tier-scaled.** `GameState.clearCoins(for:)` (line 1060) pays 2/3/4 by difficulty tier on first clears AND replays ("replay farming is blessed"); pickups stay sticky/once. BallGameView no longer computes `isFirstClear`. | `internal-economy.md` §1 earn table ("Climb first clear 2 flat … replays pay ~0 (first-clear gate)") and the blended-rate figures; `trophy-catalog.md` `econ_working_capital` (5,000 lifetime) + every *calibrate* threshold that assumed climb replays pay ~0. | Climb is now a legitimate repeatable faucet like tracks. Lifetime-earned-from-play accrues materially faster → re-derive `econ_working_capital`'s 5,000 threshold and its 22% rarity guess. Note for any future "first clear" trophy: detect via `time(for: level) == nil` BEFORE `recordResult` runs — the payout code no longer does this for you. |
| 3 | **CotD `.oneShot` fast-path merged — the climb-record pollution bug is FIXED at source.** In BallGameView's goal handler, `.oneShot` clears return before all climb record-keeping (no `recordResult`, no stars/time stamping, no `highestUnlocked` bump, no clear bonus), emit the NEW analytics event `daily_challenge_level_cleared` (props `sub_level`, `time`; BallGameView.swift:5641), and an `assert(activeMode.progression.recordsClimbResult)` guards the climb path. `ProgressionKind` gained `banksPickupCoins` / `recordsClimbResult` (GameMode.swift) — only `.mainClimb` is true for either. The track-coin-masking fix (#119) merged too (`bankedCoinIndices` in BallGameView). | `trophy-catalog.md` §3.1 "Implementation guard" + §6 item 3 ("at HEAD, CotD clears still route through the climb path (unmerged `.oneShot` fastpath fix)"); `sprint-plan.md` S1-T1 acceptance ("known unmerged CotD fast-path — test the HEAD behavior explicitly") and §7 external blockers ("unmerged CotD fast-path and track-coin-masking fixes"); `design.md` appendix ("Unmerged-branch coupling: CotD clear pollution and track-coin masking fixes should land before trophies key off climb records"); `internal-economy.md` §6. | Both fixes are merged — the "land before trophies" precondition is satisfied. Rewrite the guard guidance: the trophy engine's climb-mode guard is now **defense-in-depth**, and the shipped vocabulary to gate on is `activeMode.progression.recordsClimbResult` (or mode id `climb`), mirroring the shipped assert. S1-T1 tests the MERGED behavior: a `.oneShot` clear must never reach `recordResult` or climb trophies. The new `daily_challenge_level_cleared` event is analytics-only (fire-and-forget, non-replayable — the docs' own rule) and must NOT become a trophy trigger source; daily trophies stay keyed to `completeTodaysDailyChallenge` / `dailyChallengeCompletions`, which are unchanged. The fast-path block in BallGameView is, however, the natural view-layer hook site if a per-sub-level daily trophy is ever added. **Still true at main:** nothing writes `"daily"` into `playedModeIDs` — catalog §6 item 18 / S1-T2's `startDailyChallenge()` latch (now line 862) is still required for `daily_first_start`. |
| 4 | **Reprice shipped (see §0): all HEAD-price arithmetic is stale.** | `trophy-catalog.md` §3.6 preamble ("pending tier reprice (750/1,000/1,250/1,500, PR #118 family)") and rows: `pack_first` ("cheapest pack 520 coins" — Sports pack is now 66% of 4×1,250 ≈ **3,300**), `balls_own_40` ("~26k coins of balls"), `collection_complete` ("~52,550 coins ≈ 44h"), `econ_nest_egg` ("earnable free in ~1h"); §6 item 16; open question 5. `internal-economy.md` §3 (whole tier/census/discount section), §5c reference points. `internal-features.md` §4 ("standard 50 / rare 100 / premium 200 / exclusive 500"; bundle bands "450-1950"). | Run the §6-item-16 re-derivation pass NOW (it was gated on the merge; the merge happened). Use ~25 coins/min as the canonical rate. Directional guidance: catalogue prices rose ~7–15×, so `econ_nest_egg` (1,000) no longer buys even two Standard items and is out-earned by the smallest IAP pack (750) — likely needs raising or re-flagging for Mac's Q3; `econ_working_capital` (5,000) ≈ 3.3h at 25/min but only ~3 Standard items — recheck intent; `balls_own_40` framing ≈ 50k+ coins of balls now; `collection_complete`'s coin total/time framing must be recomputed from the live catalogue (bundle fullPrice range 4,500–13,500). |
| 5 | **IAP coin packs re-anchored; `maxSingleAward` = 60,000.** `rewardCoins`: 750/4,500/10,000/22,500/60,000 (StoreKitManager.swift; product IDs keep historical "coins.100"-style names). | `internal-economy.md` §2 IAP table (100/600/1,300/3,000/10,000) and §5c aggravator (3) ("any award > 10,000 silently clamps"); `sprint-plan.md` §4 addendum + ENG standing instructions ("single-award clamp 10,000"). `design.md` §2's "$19.99 unlimited-lives IAP (StoreKitManager.swift:388)" line ref also drifted (file heavily rewritten). | Update the clamp to 60,000 everywhere it is cited as a guardrail number. The `econ_nest_egg` "IAP shortcuts this instantly" flag is now stronger: the $0.99 pack alone (750) nearly clears 1,000; the $4.99 pack (4,500) nearly clears `econ_working_capital`'s figure if it were balance-shaped (it isn't — earned-from-play tagging is what keeps it honest). |
| 6 | **Minigame difficulty multipliers now 1× / 1.5× / 2×** (was 0.5×/1×/2×); Easy is deliberately the EV-optimal per-attempt pick. Equity buffs merged (Sumo 6×, Marble Cup floor, Pinball 2× coin rate, Roll Out rescue). | `internal-features.md` §1.4 ("payout ×0.5/×1/×2"); `internal-economy.md` §1 competitive-modes row (rates + "(0.5/1/2)") and per-mode coins/min figures. | Update the multiplier facts. No trophy trigger changes (arcade trophies are win-count/PB-based, not payout-based), but earn-rate-derived framing (rarity guesses for grind trophies, time-to-afford talk) should use the post-calibration table in `docs/economy/07-decisions.md`. |
| 7 | **`paidPrices` ledger + new GameState purchase funnels (PR #120).** New persisted key **`ra_paidPrices`** (`[String: Int]`, key = `"<Type>:<rawValue>"` via `paidPriceKey`); `purchase()` clears stale records; NEW **`purchaseBundle(_:price:)`** (GameState.swift:1589) is now the bundle-buy choke point (records prorated paid shares); `purchasePack` (1619) records 66%-shares. | `internal-data-backend.md` §2.2 key inventory (missing `ra_paidPrices`); `trophy-catalog.md` `cosmetic_first_buy` row ("hook at `GameState.purchase`/`purchasePack`/bundle buy"); `sprint-plan.md` S1-T5. | Good news: the bundle buy that previously lived in CosmeticShopView now has a proper GameState funnel — S1-T5 hooks exactly `purchase` / `purchaseBundle` / `purchasePack`, all in GameState. Add `ra_paidPrices` to the key inventory. No collection/exclusion logic changes: `paidPrices` affects refunds only, never ownership sets. |
| 8 | **Starter Pack grants the full Aurora collection; `grantBundleFree` now MINTS compensation coins.** (PR #114 + `b2afb79` + #120 interplay.) `StoreKitManager.grantAuroraCollection` delivers the whole "aurora" bundle via `grantBundleFree`, which now pays `sellBackValue` compensation **through `addCoins`** for any bundle item the player already coin-bought, then free-marks everything (rawValue-keyed `freeGrantedItems`; five items share "aurora"). Old delivered-transaction-ledger code from 064f3cd is NOT on main (064f3cd = main + the still-unmerged IAP launch-race fix branch). | `internal-economy.md` §2 starterpack row ("at HEAD restore re-grants the Aurora ball only … PR #114 unmerged") and the "Delivery is ledger-guarded" sentence (ledger refs don't resolve at origin/main); `internal-data-backend.md` §2.2 "IAP ledger `ra_iapDeliveredTxnIDs`" row (key not present at origin/main); `sprint-plan.md`/`trophy-catalog.md` lifetime-coins-earned spec (§6 item 4 / S0-T2). | **The load-bearing correction:** the S0-T2 source-tagged `addCoins` counter has a NEW call site to exclude — `grantBundleFree` compensation is a refund-shaped credit (it pays exactly what Sell Back would), not play income. The exclusion list becomes: IAP grants, Sell Back refunds, **and bundle-gift compensation**. Also note for collection trophies: legacy Starter Pack buyers get 6 Aurora items free on restore — Aurora already counts toward collection criteria (catalog §3.6), so this is a small legacy-only shortcut, not a pay-gate; acceptable, but say so. Ledger caveat: cite the delivered-transaction ledger as "on the unmerged launch-race branch," not as main behavior. |
| 9 | **`docs/economy/` exists on main** (9 files, incl. `07-decisions.md` — Mac's rulings log, "approved → 08" — and `08-reprice.md` — the shipped reprice). | `design.md` §5 ("Commit this in writing (this doc + a note in `docs/economy/`): trophies never mint coins"); `sprint-plan.md` S4-T6 ("economy note recorded per D1 … in `docs/economy/` when that lands"). | "When that lands" is now. Concrete landing spot: **`docs/economy/07-decisions.md`** (the decisions log — add the D1 ruling as its next entry when Mac rules), with a one-line pointer from `docs/economy/README.md`. S4-T6's wording should name the file. |
| 10 | **External-blocker language naming "PR #118" / "the unmerged reprice".** | `sprint-plan.md` §4 trophy addenda ("the tier reprice (750/1,000/1,250/1,500) and calibration branch (PR #118) are unmerged and awaiting Mac's approval") and §7 "External blockers"; `design.md` §5 P3 ("re-derived after the pending reprice") and appendix ("coin values (if any ever) wait for the tier reprice ruling"); `internal-economy.md` merge-state caveat block (lines 7–14) — its entire unmerged list (#113, #118, starterpack, track-coin-masking, daily-oneshot) is merged; only `claude/reserve-lives` and the IAP launch-race fix remain unmerged from that list. | Delete/rewrite every "unmerged/pending" blocker: the ONLY remaining economy gate for trophies is Mac's D1 ruling itself. The pinball ROLL-lanes blocker (`whimsy_roll_call`) is unaffected — still unbuilt, still blocked. |
| 11 | **All GameState line refs drifted (+11 to +65 lines);** BallGameView `winOverlay` 4097 → 4109; Cosmetics/StoreKitManager/SocialClient/ClansView refs drifted (ClansView +591 lines). | Every `file:line` ref in all six docs (they all say "anchor on symbols" — good). | Use the §2 table below for GameState symbols. Anything citing StoreKitManager internals should be re-located by symbol — that file was heavily rewritten twice in this range. |

## 2. GameState.swift symbol → line map (origin/main `42d1925`)

| Symbol | 064f3cd (docs) | origin/main | Notes |
|---|---:|---:|---|
| `resetProgress()` | 650 | 663 | |
| `sellBackValue(_:)` | — | **685** | NEW (PR #118/#120) |
| `liquidateCoinCosmetics()` | 665–718 | 715 | now refunds `sellBackValue`, clears `paidPrices` |
| `recordResult(level:stars:time:coinIndices:)` | 734 | **767** | body unchanged — still the climb record funnel |
| `markModePlayed(_:)` | 792 | 825 | |
| `startDailyChallenge()` | 829 | **862** | still does NOT write `playedModeIDs` (item 18 stands) |
| `forfeitDailyChallengeIfRunning()` | 839 | 872 | |
| `recordDailyAttemptFailure()` | 859 | 892 | |
| `failTodaysDailyChallenge()` | 865 | 898 | |
| `completeTodaysDailyChallenge()` | 871 | **904** | unchanged — still the daily-trophy trigger source |
| `consumeLife()` | 944 | **977** | |
| `clearCoins(for:)` | — | **1060** | NEW — tier-scaled climb clear bonus 2/3/4 |
| `maxSingleAward` | 1023 (10,000) | 1075 (**60,000**) | |
| `addCoins(_:)` | 1036 | **1088** | new refund-shaped caller: `grantBundleFree` compensation |
| `recordPinballScore(_:)` | 1126 | 1178 | |
| `recordGoldRushCoins(_:)` | 1136 | 1188 | |
| `recordRollUpRun(height:seconds:)` | 1151 | 1203 | |
| `addZenSeconds(_:)` | 1167 | 1219 | |
| `spendCoins(_:)` | 1177 | 1229 | |
| `recordCompetitiveWin(_:)` | 1205 | 1260 | |
| `recordMinigameResult(...)` | 1223 | **1278** | |
| `dailyRewardLadder` | 1294 | 1349 | values unchanged [5,8,10,12,15,20,35] |
| `claimDailyReward()` | 1334 | **1389** | |
| `advanceTrackProgress(trackID:to:)` | 1379 | 1436 | |
| `deliverTrackReward(for:)` | 1392 | 1449 | |
| `grantBundleFree(_:)` | 1405 | 1473 | now compensates already-owned items via `addCoins` |
| `grant(_:)` | 1460 | **1541** | unchanged — still the cosmetic choke point |
| `purchase(_:)` | 1476 | 1557 | now clears the item's `paidPrices` record |
| `purchaseBundle(_:price:)` | — | **1589** | NEW — the bundle-buy funnel (was view-side) |
| `purchasePack(_:)` | 1495 | 1619 | now records paid shares |

Other drifted anchors: BallGameView `winOverlay` **4109** (was 4097); the CotD fast-path +
`daily_challenge_level_cleared` emit at BallGameView **~5628–5651**; `ProgressionKind.banksPickupCoins`
/ `.recordsClimbResult` in GameMode.swift (new, ~line 88–113).

## 3. Checked and immaterial

- **Clan chat + clan settings (PR #122):** widens `clan_events.kind` (`chat_*` premade
  messages, `requested_promotion`, `renamed` — docs/social-schema-v3.sql), adds
  `SocialClient.renameClan`. The catalog's 7 Social trophies hook join/create/send-life/
  fulfill paths, all unchanged. Chat/promotion events are a **future-only** trophy surface
  (nothing to do now); only ClansView line refs drifted for S1-T6.
- **`goldRushMaxStake` deleted + ticket-comment sync:** the 10-stake cap was already dead;
  `whimsy_high_roller` (stake 5+ tickets, one round) is unaffected. `internal-features.md`
  §1.4's "(max 10; GameState.swift:1190-1192)" was already wrong at 064f3cd and
  `internal-economy.md` already documented the truth; the stale comment is now fixed in code.
- **`tutorialCoinBonus` fix (346cb3d) + L1 tour-fall payout:** payout accounting only; no
  effect on `skill_spotless`/`skill_first_try` semantics (stars/pickup banking unchanged).
- **`recordResult` internals:** byte-identical behavior (stars max, time min, coins union,
  `highestUnlocked` bump) — all climb trophy triggers keyed to it are safe.
- **Daily reward ladder:** values unchanged (105/perfect week); only the comment reframed
  against repriced items. `econ_punch_card` unaffected.
- **Aurora no longer in `coinExclusiveBalls`:** already true at 064f3cd (catalog counts
  Aurora as coin-reachable); the comment cleanup on main changes nothing.
- **HomeView / ProfileView / LevelSelectView / GameMenuView:** untouched in this range —
  all cited refs (Home nav grid 319–330, badge wall 388–474, `trophy.fill` glyph collision)
  remain valid.
- **AnalyticsClient.swift:** untouched — memory-only buffer caveats stand as written.
- **Supabase-side facts** (tables, RLS, delete-account, migrations) in
  `internal-data-backend.md`: no schema change in this range except the additive
  clan_events check constraint (v3); rarity-architecture reasoning unaffected.
- **Products.storekit / PurchaseSheets / CosmeticShopView diffs:** display-name and
  copy updates for the re-anchored packs; no trophy-relevant surface.
- **BallSkin/BallSkinView/FriendsView/SumoSurvivalView/MarbleCupView/PinballView/
  RollOutView gameplay diffs:** payout/equity tuning + comments; no stat, funnel, or
  id changes trophies key on (PB units unchanged: Disco/RollOut still write bests
  in-view — S1-T4's reroute is still needed).
- **`docs/minigame-difficulty.md`, `docs/gold-rush-economy.md`, `docs/cosmetics-rendering.md`
  updates:** documentation catching up to the merged calibration; nothing new to react to.
