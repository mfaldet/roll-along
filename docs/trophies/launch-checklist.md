# Roll Along — Trophy System Launch Runway

> **The single ordered checklist Mac works to ship the trophy system.** Authored 2026-07-06 (S4-Runway; S4-T5 privacy + S4-T6 freeze). Consolidates the README deploy steps, the S2 device QA (PR #136), the S4-T4 beta plan + beta-data isolation decision, the criteria freeze, and the rollback plan into one runway.
>
> **Legend:** `[x]` = done in-repo (agent-completed). `[ ] MAC` = Mac-only (device / TestFlight / App Store Connect / Supabase prod / signing — an agent physically cannot do it). `[ ] TUNE` = the one pre-freeze tuning window. Every unchecked box gates submission.
>
> **The hard invariant behind all of this:** trophies never mint coins (D1, `docs/economy/07-decisions.md`, since PR #113); the signed-in showcase is identity-linked App-Functionality data; the anonymous rarity rail is never PII. Nothing below changes that.

---

## Stage 0 — Backend: apply the schema to Supabase (Mac-only, prod)

The schema + rollup exist as **files only** — `docs/trophies/trophy-schema.sql` and `docs/trophies/trophy-rollup.sql`. NOTHING is applied to any Supabase project. All of Stage 0 is Mac's, and prod migrations always need Mac's explicit OK.

- [ ] **MAC** Apply `trophy-schema.sql` on a **dev branch first**, verify RLS, then to **prod** (project `mhwpcwauzvmtmuphtajs`). Three objects: `trophy_unlocks` (anon install-UUID, INSERT-only), `player_trophies` (FK → players ON DELETE CASCADE, own-row write), `player_showcase` (anon+auth readable, own-row write), plus the `trophy_stats` aggregate.
- [ ] **MAC** Verify RLS on the applied schema: anon can **INSERT** `trophy_unlocks` but never SELECT/UPDATE/DELETE it; anon can **SELECT** `trophy_stats` only (the project's first anon-readable object — aggregates, never raw unlock rows); authenticated writes only its **own** `player_trophies` / `player_showcase` rows; a `players` cascade delete removes `player_trophies` + `player_showcase` and leaves `trophy_unlocks` untouched; a duplicate `(install_id, trophy_id)` insert is a no-op.
- [ ] **MAC** Apply `trophy-rollup.sql` (the daily rarity aggregation function + the single-row `trophy_rollup_config`).
- [ ] **MAC** Schedule the rollup **cron** (pg_cron / scheduled job) to run the rollup function daily. Rarity percentages do not move until this runs.
- [ ] **MAC** Set `trophy_rollup_config.launch_at` to the **public-launch instant** at launch. Until then it defaults to a far-future date so the 30-day cold-start gate stays CLOSED (fail-safe: rarity suppressed). The gate opens only when `denominator ≥ 500 distinct installs AND now() ≥ launch_at + 30 days` (design.md decision #6; `min_installs` / `min_days` are tunable columns).
- [ ] **MAC** Re-verify all three RLS postures **in the production project** post-apply (repeat of the dev-branch check, on prod).

## Stage 1 — App signing & privacy (Mac-only in ASC / Xcode; the code is done)

- [x] **Privacy manifest** (`RollAlong/PrivacyInfo.xcprivacy`) updated for trophy traffic (S4-T5, this task). See **§ Privacy review** below for exactly what changed and why. Manifest is a code file — done in-repo.
- [ ] **MAC** Add the **iCloud Key-Value Store entitlement** in Xcode signing (`RollAlong.entitlements` is Mac's signing step — no agent edits it). Without it, `TrophyCloudMirror` no-ops gracefully (reinstall reconcile + cross-device external-change catch-up are simply absent); with it, an unlock earned on one device union-merges into another. Confirm the container id matches the app.
- [ ] **MAC** Set the **App Privacy answers in App Store Connect** to match the manifest. See **§ Privacy review → ASC answers** for the exact toggles. (ASC state is not something an agent can set or read.)
- [ ] **MAC** Decide whether to refresh or explicitly mark stale the privacy copy in `docs/AppStore.md` (the sprint plan flags it as already stale — do not cite it as-is).

## Stage 2 — Device / visual / accessibility QA (Mac-only; simulator slice is done)

- [ ] **MAC** Run the **S2 device / visual / VoiceOver QA** checklist — it lives in **PR #136** (the S2 Presentation merge). First user-visible sprint; the checklist covers Trophy Room, toasts, capstone, ProfileTrophyCard on real hardware, Dynamic Type XL, and Reduce Motion.
- [ ] **MAC** Run the **on-device Instruments** performance pass. The authoritative budget is **< 0.5 ms p99 on the oldest supported device** for a per-bump trophy evaluation in `consumeLife` / `recordResult`; confirm zero frame drops attributable to trophy writes over a 10-minute play session. (The headless `TrophyPerformanceTests` in `PerformanceTests.swift` are relative regression guards only — they cannot substitute for the device number.)

## Stage 3 — TestFlight beta + trophy-hunter loop (Mac-only build/distribution; telemetry + isolation are wired)

- [x] **Beta telemetry wired** — a fire-and-forget `trophy_unlocked` AnalyticsClient event fires per LIVE unlock at the `routeUnlockedToPresentation` choke point in `GameState.swift`, carrying only `trophy_id` + `tier` (no PII; backfilled grandfathered grants bypass it by design). Pure builder `GameState.trophyUnlockEvent(for:)` is unit-tested for the NO-PII wire shape.
- [ ] **MAC** Cut a **TestFlight beta build** with the beta telemetry above.
- [ ] **MAC** Recruit trophy-hunters; collect structured feedback on **clarity, grind feel, and missing categories**.
- [ ] **MAC / TUNE** Run **exactly one threshold-tuning pass** on trophy criteria — **this is the last window before criteria freeze.** Any re-tune (e.g. a `pinball_score_50k` threshold) lands as one reviewed PR, then the freeze stamp goes final. After this, IDs/criteria/tiers are immutable.
- [ ] **MAC** Confirm the **beta acceptance criteria** (sprint-plan §5): crash-free ≥ 99.5%; zero lost/revoked-trophy reports; ≥ 90% of testers earn ≥ 1 trophy in session 1; healthy median trophies-per-tester; zero mid-run-interruption complaints; VoiceOver testers navigate the room unassisted. (OPEN: the capstone-progress target *band* is not defined in design.md/catalog — agree the number with Mac before beta starts; the catalog's 0.2% capstone figure is a rarity guess, not a beta bar.)

### Beta-data isolation decision — RECOMMENDED, needs Mac's confirmation

Beta installs hit the **same** `trophy_unlocks` / `events` rails as production, so beta unlocks would otherwise pollute the launch rarity percentages and the 500-install cold-start count.

- **RECOMMENDED — Option (a): tag beta installs and exclude them from the rollup.** The rollup already ships a **BETA EXCLUSION HOOK** in `docs/trophies/trophy-rollup.sql` (currently off): add a filter such as `and app_version not like '%-beta'` (or a build-tag filter) to **both** the denominator CTE (`app_launch` count) **and** the numerator CTE (the `trophy_unlocks` count) — the two filters must mirror each other or the pct math skews. This keeps beta unlock rows in the table (no data loss) while excluding them from the published percentages and the cold-start denominator until `launch_at`. Low-risk, reversible, already scaffolded.
  - **Prerequisite:** beta installs must be *distinguishable*. Confirm the beta build stamps a `-beta`-suffixed `app_version` (or an equivalent build tag) on its `events` / `app_launch` rows; if not, that stamp is the one small piece to add to the beta build before relying on option (a).
- **ALTERNATIVE — Option (b): truncate + re-baseline.** `TRUNCATE trophy_unlocks` and re-baseline `trophy_stats` from zero immediately before public launch. Simpler to reason about, but destroys the beta-era anon unlock history and briefly zeroes rarity — acceptable only because rarity is suppressed pre-launch anyway.
- **Pre-freeze-criteria rows:** state explicitly whether beta unlock rows earned under **pre-freeze** criteria (e.g. a since-re-tuned `pinball_score_50k`) are **kept** or **purged**. With option (a) they are simply excluded from the rollup (kept but ignored); with option (b) they are purged with everything else. **RECOMMENDATION:** with option (a), keep them (excluded anyway; no launch-facing effect).
- [ ] **MAC** Confirm option (a) or (b), and wire the hook (option a) or run the truncate (option b) **before public launch**.
- [ ] **MAC / done-in-repo** Trophy funnel queries appended to `docs/soft-launch-metrics.sql`; schedule the first-week review. (If not yet appended, that append is a small in-repo follow-up; the `trophy_unlocked` event they read is already emitting.)

## Stage 4 — Criteria FREEZE (the point of no return)

- [x] **Freeze-readiness stamped** in `docs/trophies/trophy-catalog.md` (header line, dated 2026-07-07, "pending Mac's launch sign-off"). Point weights remain deferred to the GC phase (catalog Q6 — nothing to freeze in v1); `whimsy_roll_call` remains blocked on the pinball ROLL rollover lanes (catalog Q9).
- [ ] **MAC / TUNE** After the single S4-T4 tuning pass closes, **freeze all 89 trophy IDs + criteria + tiers forever.** Immutability-after-publish is the cross-platform norm — treat it as law. Changing a shipped trophy's criteria orphans players who earned it under the old rule and breaks any future Game Center mirror (IDs must be GC-legal and stable from day one).
- [ ] **MAC** Rule on `whimsy_roll_call` (catalog Q9): hold it back or substitute, before the final freeze.
- [ ] **MAC** Confirm point weights stay deferred (catalog Q6) — no freeze action needed in v1, just re-affirm.
- [x] **Economy invariant re-verified** — "trophies never mint coins" is recorded in `docs/economy/07-decisions.md` (+ README pointer) since PR #113; the §5 invariant test asserts zero `addCoins` calls from trophy code. Nothing queued — re-verified in place at freeze.
- [x] **Guideline sanity check** passed — see **§ Review-guideline check** below (4.5.3 / 4.5.5 / 3.2.2).

## Stage 5 — Rollback readiness (before submission)

- [ ] **MAC** Confirm the **Trophy Room entry tile is behind a feature flag** and the **sync service no-ops when flagged off** — the app-level kill switch if the whole system needs to go dark post-ship. (Verify the flag exists / add it if missing; the sync service already tolerates an absent iCloud entitlement, but the entry-tile flag is the deliberate off switch.)
- [ ] **MAC** Verify the **per-trophy `is_paused` display kill-switch end-to-end**: set `trophy_stats.is_paused = true` for one trophy → its rarity slot hides/disables in the Trophy Room (S3-T4 honors the flag). This is the surgical switch for a single glitched trophy without shipping an app update.

## Stage 6 — Migration re-test & launch housekeeping (Mac-only for the device half)

- [ ] **MAC** Re-verify the backfill / migration against a **real device save restored from TestFlight** (not just the unit fixtures) — the idempotent backfill must not double-grant, miss grants, or storm toasts on the update path.
- [ ] **MAC** Document post-launch **headroom**: reserved trophy-id namespace (and GC point budget if the GC mirror later ships) for future minigames/tracks, so the 89-id set can grow without colliding.
- [x] **Config docs updated** — this plan's scorecard statuses and the `docs/trophies/README.md` pointer are maintained in-repo per session.

## Deferred (NOT launch blockers — explicitly out of v1)

- **Game Center mirror (D2 / decision #9)** — LATER, not this release. All trophy IDs are GC-legal already (100-slot / 1,000-point budget respected). If/when it ships: ASC achievements approved + art uploaded + localizations + GC config "Not Live" → live rides that release. This is where **point weights** get assigned (catalog Q6).
- **`whimsy_roll_call`** — blocked on the pinball ROLL rollover lanes (catalog Q9); resolved at final freeze.

---

## Privacy review (S4-T5)

**Question:** does the trophy backend traffic stay inside the app's declared privacy envelope, or does `PrivacyInfo.xcprivacy` need an update?

**Finding — the manifest needed one addition; it has been made (this task).** The trophy backend has two distinct rails:

1. **Anonymous rarity rail** — `trophy_unlocks` (anon install-UUID, INSERT-only) → `trophy_stats` (counts only). No PII, no identity linkage, never cross-app tracking. This is **already covered** by the existing not-linked `NSPrivacyCollectedDataTypeDeviceID` + not-linked `NSPrivacyCollectedDataTypeGameplayContent` entries (the same anonymous per-install analytics envelope; the `trophy_unlocked` beta event rides here too, carrying only id + tier). No change needed for this rail.
2. **Signed-in showcase rail** — `player_trophies` + `player_showcase`, keyed to `player_id = auth.uid()` (Sign in with Apple → Supabase Auth) and rendered on the public profile. Because these rows are tied to the account, this is **identity-LINKED gameplay content** — which the manifest did **not** previously declare (before this edit it declared *zero* linked data types). 

**Edit made** (`RollAlong/PrivacyInfo.xcprivacy`): added a second `NSPrivacyCollectedDataTypeGameplayContent` entry with `NSPrivacyCollectedDataTypeLinked = true`, `NSPrivacyCollectedDataTypeTracking = false`, purpose `NSPrivacyCollectedDataTypePurposeAppFunctionality` (cross-device restore + public showcase — not analytics, not tracking). The existing not-linked GameplayContent entry stays and now also names the `trophy_unlocked` event and the anon `trophy_unlocks` rail in its comment.

**Deliberately NOT added — no new data *type*.** `player_showcase` stores only trophy ids + per-grade counts; it carries no name of its own. The public **display name** shown next to a showcase comes from the pre-existing `players` row, which the Friends/Clans social system already made identity-linked long before trophies. So the trophy rail adds *linked GameplayContent* but does **not** introduce a *linked Name* data type.

> **FLAG for Mac (pre-existing, out of this task's trophy scope):** the manifest currently declares **no** `NSPrivacyCollectedDataTypeName` at all, yet the signed-in social system already collects an identity-linked **display name** (`players.display_name`, surfaced on public profiles / leaderboards / clans). That is a pre-existing gap the trophy work merely sits next to — worth Mac auditing the whole signed-in social surface (name + linked gameplay) against the manifest + ASC answers in one pass, not just the trophy slice. This task's edit is scoped to trophy traffic only.

### App Privacy answers Mac must set in App Store Connect

Match the manifest. For the trophy system specifically:

- **Gameplay Content** — collected: **Yes**. Two contexts:
  - *Analytics / not linked* (existing): the anonymous trophy rarity rail + `trophy_unlocked` funnel event. Linked to identity: **No**. Used for tracking: **No**. Purpose: **Analytics**.
  - *App Functionality / linked* (NEW this release): the signed-in `player_trophies` + `player_showcase` rows. Linked to the user's identity: **Yes**. Used for tracking: **No**. Purpose: **App Functionality**.
- **Device ID** (existing anon install-UUID) — unchanged: collected Yes, not linked, not tracking, Analytics.
- No new **Purchase History**, **Name**, **Contact Info**, or **Location** answers are introduced by the trophy work. (But see the pre-existing display-name FLAG above — Mac should reconcile the signed-in social surface's Name answer independently.)
- The **NSUserTrackingUsageDescription / ATT** posture is unchanged — trophies never touch the ad SDK and never trigger tracking.

### Review-guideline check (4.5.3 / 4.5.5 / 3.2.2)

- **4.5.3 (no incentivizing to download other apps / no misuse of push) — PASS.** No trophy criterion references downloading anything or cross-promotion.
- **4.5.5 (Game Center) — PASS / N/A this release.** No GC integration ships now; when the mirror later ships, GC config + achievement art go through ASC (Deferred section). IDs are already GC-legal.
- **3.2.2 (unacceptable business model — no pay-gated or artificially time-limited achievements) — PASS.** No trophy is pay-gated: the collection criteria **exclude the 4 IAP secrets** (`{diamond, moneyBall, moneyRoll, moneyFull}`) and `collection_complete` further excludes the 7 seasonal bundle-exclusive balls (scoped to the 207-item evergreen set) so no trophy is time-limited or requires spending money. The capstone is offline-, solo-, and $0-achievable by construction. Trophies **never mint coins** (economy invariant, test-enforced). No guideline flags.

---

## At-a-glance: what's done vs Mac-only

| Done in-repo (agent) | Mac-only (device / TestFlight / ASC / Supabase / signing) |
|---|---|
| Privacy manifest updated (linked GameplayContent for the signed-in rail) | Apply schema + rollup to Supabase (dev branch → prod), schedule cron, set `launch_at` |
| Freeze-readiness stamp on the catalog | Add iCloud KV entitlement in Xcode signing |
| Beta `trophy_unlocked` telemetry wired + unit-tested | Set App Privacy answers in ASC |
| Beta-isolation recommendation + rollup hook scaffolded | S2 device/visual/VoiceOver QA (PR #136) + on-device Instruments pass |
| Guideline sanity check passed | Cut TestFlight beta, recruit hunters, run the ONE tuning pass, hit acceptance criteria |
| Economy invariant re-verified (test-enforced) | Confirm beta-isolation option + wire hook / truncate before launch |
| This runway document | Final criteria freeze sign-off; `whimsy_roll_call` (Q9) ruling; migration re-test on a TestFlight-restored save; feature-flag + `is_paused` rollback verification |
