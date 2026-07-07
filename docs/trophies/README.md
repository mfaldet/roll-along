# Roll Along — Trophy System

*Package produced 2026-07-02 by a multi-agent research → design → plan → QA pipeline (24 agents across four workflow runs; every code claim adversarially verified against source).*

**Provenance:** researched and code-verified at `064f3cd`; reconciled same day to `origin/main` `42d1925` (PRs #113/#114/#118/#119/#120/#122/#123/#124 merged in range — including the tier reprice); tip-drift note for `fb98819` (IAP launch-race fix, StoreKit-only) applied. Line refs are anchored by symbol; see [research/repo-delta-2026-07-02.md](research/repo-delta-2026-07-02.md) for the symbol→line map before trusting any `file:line`.

**Status: all S0-gating rulings landed 2026-07-02** (89-trophy catalog adopted; ladder Bronze → Silver → Gold → Diamond → Platinum, with Diamond-vs-cosmetic disambiguation riders; rewards = prestige + earned-only regalia, trophies never mint coins). **Sprint 0 kicked off 2026-07-02 on branch `claude/trophies-s0`.**

---

## What this is

A PlayStation-inspired trophy system for Roll Along: tiered trophies (Bronze → Silver → Gold → Diamond → Platinum), per-trophy **rarity percentages** ("2.4% of players have this"), an in-app Trophy Room, profile showcases, and a rarity backend that works for 100% of players — signed-in or not, online or not — without breaking the no-tracking privacy posture or minting a single coin.

## The system at a glance (rulings landed 2026-07-02; remaining open decisions are pre-S3/pre-launch — see Ruling order)

- **89 trophies**: 49 Bronze / 25 Silver / 11 Gold / 3 **Diamond** (ultra-hard monuments, off the capstone path) / 1 capstone (**"Platinum"** — all 73 visible B/S/G trophies; offline-, solo-, and $0-achievable by construction).
- **Rarity**: PSN-style labels + live percentages, computed from an anonymous install-UUID rail in Supabase (`trophy_unlocks` INSERT-only + `trophy_stats` aggregate — the project's first anon-readable object), suppressed until 500 installs + 30 days post-launch (cold-start).
- **Architecture**: local latched ratchet (`ra_trophyUnlocks`, survives resets, never recomputed) → idempotent full-snapshot sync to Supabase → optional Game Center mirror later (all IDs GC-legal from day one; 100-slot/1,000-point budget respected).
- **Economy stance**: **trophies never mint coins** (RULED 2026-07-02, recorded in `docs/economy/07-decisions.md`). Prestige-first, plus 3–5 earned-only regalia cosmetics at true milestones (ruled in). No trophy requires spending money; collection criteria exclude the 4 IAP secrets (the Diamond ball + 3 Money items) and the 7 seasonal bundle-exclusives.
- **58 of 89** trophies trigger off already-persisted GameState stats; the other triggers need the 18-item instrumentation list in the catalog's §6.

## Documents

| Doc | What it holds |
|---|---|
| [design.md](design.md) | The system design: tier ladder options (incl. the Diamond naming-collision analysis), rarity thresholds + denominator + cold-start, unlock/sync/persistence architecture, reward policy, toast + Trophy Room UX, governance, anti-cheat — and **§11: the Decisions-for-Mac table (start here)** |
| [trophy-catalog.md](trophy-catalog.md) | The v1 catalog: all 89 trophies with stable IDs, testable triggers, data sources (existing stat vs NEW instrumentation), predicted rarity, hidden flags; the 18-item instrumentation gap list; open questions |
| [sprint-plan.md](sprint-plan.md) | Agent-workforce delivery plan: S0–S4, 32 tasks with acceptance criteria and file ownership, workforce roster, the mandatory engineering-gotchas briefing, QA matrix + gates, risks, D-handle → ruling map (§7) |
| [research/](research/) | Six research inputs (3 internal audits, 3 external deep-dives) + the repo-delta reconciliation briefing |

Research inputs: [internal-features.md](research/internal-features.md) (every hook point with refs), [internal-economy.md](research/internal-economy.md) (currency/IAP map + trophy-economy interaction), [internal-data-backend.md](research/internal-data-backend.md) (persistence, Supabase, identity, privacy), [playstation-trophy-system.md](research/playstation-trophy-system.md), [platform-comparison.md](research/platform-comparison.md) (deep Game Center section), [f2p-achievement-monetization.md](research/f2p-achievement-monetization.md).

## Ruling order (what's blocked on what)

**Gate 1 — unblocked Sprint 0 (all four RULED 2026-07-02):**
1. **Catalog adoption** — bless the 89-trophy catalog as v1 scope (or compress) → design.md §11 #14 + catalog Q7 — **RULED 2026-07-02: adopted as v1 scope, as recommended** (incl. the #14-folded items: 73-visible capstone scope, 5 hidden, deferred point weights, quarantined 4th tier)
2. **Ladder shape** — faithful PSN (B/S/G + capstone) vs five rungs (B/S/G/4th grade + capstone; recommended) → design.md §11 #1 — **RULED 2026-07-02: five rungs (B), as recommended**
3. **4th-grade name** — Legend (recommended) vs Summit vs Diamond → design.md §11 #2 (collision analysis in §2) — **RULED 2026-07-02: Diamond** (Mac overruled the Legend recommendation; §2 R2's disambiguation riders are now binding)
4. **Reward policy** — prestige-only vs prestige + earned-only regalia (recommended) vs coins (rejected by the economy analysis) → design.md §11 #3 — **RULED 2026-07-02: P2** (prestige + earned-only regalia; trophies never mint coins — economy log updated same day)

**Mid-S0:** retroactive backfill for existing players (#12) — proceeding per recommendation (grant from existing stats) — Mac may veto.

**Sprint 2 (Presentation) — DONE, merged via PR #136 (2026-07-07).** First user-visible sprint; device/visual/VoiceOver QA is Mac's (checklist in the PR).

**S3-gating decisions — all RULED 2026-07-07 (as recommended):**
- **Architecture (#4) = hybrid C**; **anonymous rail (#13) APPROVED** — `trophy_unlocks` (anon install-UUID, INSERT-only) + `trophy_stats` counts-only aggregate, inside the not-linked analytics envelope; **denominator (#5) = distinct install UUIDs**.
- **Cold-start (#6) = suppress until 500 installs + 30 days** (tier labels only until then).
- **Rarity vocabulary = PSN's 4 labels** (Common ≥50% / Rare <50% / Very Rare <15% / Ultra Rare <5%).
- **iCloud KV reinstall mirror (#7) = YES.**
- Proceeding on defaults: **restore-on-sign-in (#8) = yes**; **showcase default (#10) = on for signed-in**.
- **Deferred: Game Center mirror (#9) = LATER, not S3** (IDs stay GC-legal).

**Mac-owned S3 deploy steps (the sprint delivers code + SQL; Mac executes these):** apply the trophy Supabase migration to **prod** (prod migrations always need Mac's explicit OK); add the **iCloud KV entitlement** in Xcode signing; answer the **App Privacy label** for `player_trophies` + `trophy_stats`.

**Before launch:** threshold recalibration vs live prices/telemetry (catalog Q5 — unblocked now that the reprice shipped), beta-data isolation and beta acceptance band (sprint §5/S4-T4), and the Game Center mirror phase (#9) when the catalog has settled.

Full mapping: design.md §11 (14 numbered decisions — #1/#2/#3/#14 RULED 2026-07-02, the rest open) + trophy-catalog.md open questions (11 — Q1/Q2/Q4/Q7/Q11 ruled via the same rulings) + sprint-plan.md §7 (D-handles, external blockers).

## Delivery shape

Five sprints, 32 tasks, ≈26–35 focused agent sessions. Critical path is the `GameState.swift` serial lane (S0-T2 → S1-T5); most other lanes parallelize. Every implementation session must follow the gotchas briefing in sprint-plan §4 (pbxproj 4-entry registration, ViewBuilder func trap, type-checker-timeout diagnosis, explicit-path staging, compile-verify with xcodebuild before handoff).

Remaining external blockers (true externals only): App Store Connect achievement art/localizations if/when the GC mirror ships, and the pinball ROLL rollover lanes (blocks one hidden trophy, `whimsy_roll_call` — hold-back vs substitute is catalog Q9).

## QA trail

Produced via: 6 parallel research agents → 3 synthesis agents → 4 adversarial verifiers (41 findings: feasibility vs code, external fact-check, cross-doc consistency, completeness) → 4 revisers → final-coherence QA + fixes → repo-delta reconciliation (36+ commits landed on main mid-authoring; all six docs re-verified against `42d1925`, spot-drift `fb98819`). Verifiers confirmed all GameState funnel refs exact at main, catalog arithmetic row-counted (89 = 49/25/11/3/1; rarity pyramid 3/31/22/29/4; capstone 73 = 85 visible − 7 social − 5 hidden), and zero unflagged pay-gated trophies.
