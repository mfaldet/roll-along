# 06 — The calibration sprint plan (multi-agent runbook)

A concrete, agent-executable plan to take the economy from "audited" to
"calibrated and continuously verified." Each workstream is specified as an
agent fleet (what to spin up, inputs, outputs, acceptance criteria) so any
session can execute it with a Workflow run. Ordering matters: **Sprint 0 is a
precondition for everything** — tuning an economy with a live infinite faucet
is meaningless.

## Operating principles (from the analysis + benchmarks)

1. **Anchor chain, in order**: target minutes-of-play per rarity tier →
   cosmetic prices → per-mode payouts → coin-pack sizing. Never pick a payout
   number directly. (Benchmarks findings 2 & 9.)
2. **Telemetry over assumption**: the `minigame_result` event already carries
   game/difficulty/won/base_payout/payout — every calibration decision should
   close its loop against observed win rates (≥200 plays per cell).
3. **Every economy constant gets a guardrail test** — the graphite exploit
   survived because nothing asserted "sell-back is idempotent."
4. **One PR per lever** — payout changes are cheap to ship and easy to revert
   individually; batching hides regressions.

---

## Sprint 0 — Stop the bleeding + instrument (precondition)

| Item | What | Status |
|---|---|---|
| S0.1 | Fix graphite sell-back exploit + idempotence regression test | **chip queued** |
| S0.2 | Close/bless the Challenge Track replay farm (decision: Mac) | decision needed |
| S0.3 | Fix lives-pack copy (6/36/78 → 10/60/130) + stale comments | **chip queued** |
| S0.4 | Fix CotD → climb clear-path fallthrough (stray +2, best-time pollution) | small PR |
| S0.5 | Resolve Coin Pit doc/code drift (GameState comment vs BallGameView; `goldRushMaxStake` removed-or-not) | small PR |
| S0.6 | Verify analytics coverage: every earn path emits an event with coins granted (add where missing) | 1 agent audit |

**Acceptance**: no earn path exceeds ~150 coins/min; two consecutive
sell-backs refund 0; every `addCoins` call site has a test or an emitting
event.

---

## Workstream A — Economy calibration (the anchor chain)

**Objective**: pick target grind times per tier, then derive and ship the
P1/P2 payout constants; validate with a simulated-player harness.

**Fleet** (1 workflow, ~8 agents):
1. *Simulator builder* (2 agents): a Swift-package or script harness that
   replays player archetypes (casual 20 min/day; regular 60; grinder 180)
   against the earn tables in [01-earning.md](01-earning.md) and outputs
   coin-balance curves per week. Validates the min/max bounds method
   (benchmarks finding 2). Deliverable: `scripts/economy-sim/` + a CI check
   that re-runs it when economy constants change.
2. *Constant-change agents* (4, one per P1 lever): Sumo `[60,30,15,8]`,
   Marble Cup `goals×15+30`, climb tier-scaled `coinPerClear 2/3/4`,
   difficulty compression ×0.7/1.0/1.4 (see [04-equity-gaps.md](04-equity-gaps.md)
   for exact file:line). Each: change + unit test + build + PR.
3. *Verifier agents* (2): re-run the earn-rate analysis on the changed tree
   and confirm the competitive band lands in 30–60/min Normal, solo 15–25/min.

**Decision inputs for Mac** (before the fleet runs):
- Target minutes per tier — proposal: Standard ≈ 3 min, Rare ≈ 6, Epic ≈ 12,
  Legendary ≈ 30, at *post-fix* typical rates (~900/hr blended).
- Daily soft cap: adopt or not (benchmarks finding 3) — proposal: diminishing
  returns above ~2,500 coins/day from repeatable sources rather than a hard
  wall; dailies/first-wins exempt.

**Acceptance**: simulator shows a casual player affords a Standard bundle in
~1 week, a Legendary bundle in ~1 month; no archetype's balance grows
unboundedly; all modes within 2× of the band's center.

---

## Workstream B — Cosmetic standards (quality ↔ cost ↔ rarity)

**Objective**: a written standard for what each tier *looks like* and *costs*,
then an audit fleet that grades all 218 items + 66 bundles against it and
files the misfits.

**The standard to draft first** (1 agent + Mac review; extends the tier table
in [02-spending.md](02-spending.md)):
- **Visual bar per tier** — e.g. Legendary requires animated/bespoke rendering
  (MeshGradient/Canvas — the Aurora/planets precedent), Epic requires a custom
  gradient + at least one distinctive feature, Standard is palette-level. Per
  category (ball/goal/trail/floor/pit/music) since their render surfaces differ.
- **Rung standardization**: which tiers each category may use (today
  balls/goals skip Rare while trails/boundaries have it). Either all
  categories span all rungs, or the skips are documented as policy.
- **Bundle policy**: rarity thresholds (700/1,100) stay cost-derived; adopt the
  visible ~20% bundle discount (benchmarks finding 6) **paired with**
  refund-what-you-paid sell-back; ball packs get proration or a UI warning.

**Fleet** (1 workflow, ~12 agents after the standard is approved):
- *Census graders* (7, one per category): grade every item against the visual
  bar (they read the actual renderers — BallSkinView switch, goal/floor/pit
  overlays), flag under-tier and over-tier items with evidence.
- *Bundle auditors* (2): recompute all 66 fullPrice/rarity values, flag
  contents that cross the standard (e.g. free items padding bundles).
- *Adversarial verifier* (2): re-grade a sample of every grader's calls.
- *Synthesizer* (1): the re-tiering worklist as a PR-able table.

**Acceptance**: every item has a graded tier with evidence; misfit list ≤10%
of catalogue or re-tiering PRs filed; standard checked into
`docs/economy/standards-cosmetics.md`.

---

## Workstream C — Level & map verification

**Objective**: every shipped climb level (and eventually tracks) is
hand-verified in Marble Mapper, and every level's coin geometry meets the
economy's assumptions.

**Pipeline already exists**: LevelOverrides.json is the climb SSOT authored in
Marble Mapper (with a per-publication `verified` flag), and only 10/100 climb
levels are currently verified.

**Fleet** (repeating batch, ~10 agents per batch of 20 levels):
- *Geometry checkers* (5): for each level — 3 coins present and **reachable**
  (not inside holes/walls; path exists from start), start→goal solvable,
  targetTime formula sane vs layout, tier (digit rule) matches actual
  difficulty of the geometry.
- *Economy checkers* (2): pickup coins consistent with the earn model
  (3/level; authored overrides that differ get flagged to the model).
- *Verifier* (1) + *worklist synthesizer* (1): levels to fix in Marble Mapper
  vs levels to mark `verified: true` in the next export.
- Mac plays/approves each batch's fix list in Marble Mapper (human step —
  the `verified` flag stays human-granted).

**Acceptance**: 100/100 climb levels verified; the guardrail test extended to
assert every level's coin count matches the economy model's assumption table.

---

## Workstream D — AI opponent calibration

**Objective**: observed win rates per mode×difficulty hit the designed
`targetWinRate` (0.80/0.45/0.22) within ±10 points, making the payout
multipliers actually EV-fair.

**Fleet** (1 workflow, ~8 agents):
- *Headless sim agents* (6, one per competitive mode): drive the game loop (or
  extract the AI + physics into a testable harness) with a scripted
  median-skill player model; measure win rates per difficulty across ≥200
  simulated rounds. Where headless simulation is impractical, fall back to
  the persisted `minigameSuccessRate` dictionaries from real play + TestFlight
  telemetry.
- *Knob-tuning agents* (2): adjust per-mode `aiAccelBase` (and Smash and Grab's
  `aiSpeedScale`) so each tier lands its target, per the documented
  calibration loop in [minigame-difficulty.md](../minigame-difficulty.md).
  MinigameAI's weave/hesitation humanizer stays; only strength scales.

**Acceptance**: per mode×difficulty, simulated (or observed, n≥200) win rate
within ±10 points of target; `minigame_result` dashboards confirm post-ship.

---

## Workstream E — Economy QA & run verification (the permanent fleet)

**Objective**: the economy can't silently drift again.

**Deliverables** (1 workflow, ~6 agents, then CI):
- *Golden economy tests*: for every earn path, a unit/integration test
  asserting the exact documented payout (table in 01-earning.md becomes the
  fixture). Every spend path asserts price = tier table.
- *Invariant tests*: sell-back idempotence; replay-farming caps; addCoins
  clamps (`maxSingleAward`, balance cap); ticket conservation (wins → tickets
  → Coin Pit blocks); no path grants coins without an analytics event.
- *Exploit hunters* (2 adversarial agents, quarterly): free-form hunt for
  loops like graphite (state machines that grant+refund, prorate+restore,
  discount+refund arbitrage).
- *Docs sync check*: a CI script asserting the constants cited in
  docs/economy match source (grep-able `file:line` table) so the briefing
  can't rot.

**Acceptance**: a PR changing any economy constant fails CI unless the docs
table and golden tests are updated with it.

---

## Workstream F — Store & monetization polish

**Objective**: apply the perceived-value findings at the moment of purchase.

- Show **"+X% bonus"** badges on the coin ladder (it's already monotonic:
  101→200 coins/$ — display it); smallest pack framed as starter conversion.
- Re-anchor pack sizes onto bundle price points (650/950/1,650/2,640) *after*
  Workstream A settles rates.
- **Endowed progress**: pre-filled "first Epic" coin meter for new players
  (justified welcome bonus, denominated in coins — benchmarks finding 8);
  consider a piggy-bank accumulator later.
- Bundle discount UI (from Workstream B policy) + owned-member warnings on
  ball packs.
- Rewarded-ad placement inside Get Lives sheet as the honest free alternative;
  revisit lives pricing only after (teardown stance: sell desire, not
  friction).

**Acceptance**: purchase-sheet A/B events in place; no store copy contradicts
granted amounts (S0.3 pattern test).

---

## Sequencing & effort

| Order | Work | Fleet size | Depends on |
|---|---|---|---|
| 0 | Sprint 0 fixes | 2 chips + 3 small PRs + 1 audit agent | — |
| 1 | A: anchor-chain decisions (Mac) + simulator | ~8 agents | Sprint 0 |
| 2 | B: cosmetic standard draft → audit fleet | ~12 agents | standard approval |
| 3 | C: level verification batches | ~10/batch ×5 | none (parallel OK) |
| 4 | D: AI calibration | ~8 agents | telemetry or harness |
| 5 | E: QA fleet → CI | ~6 agents | A's constants landing |
| 6 | F: store polish | ~4 agents | A + B policies |

Workstreams B/C/D are independent of A and can run in parallel once Sprint 0
lands. E runs last-but-permanent. Total ≈ 60–70 agent-runs across ~6 workflow
invocations — comfortably a week of sessions at current cadence.

## Standing decisions needed from Mac

**All five DECIDED 2026-07-01 — rulings, implications, and what shipped
against them are in [07-decisions.md](07-decisions.md).**

1. **Track farm** — DECIDED: **blessed everywhere**; the track farm stays and
   the climb gets replay parity (ruling 1).
2. **Target minutes per tier** — DECIDED: **30/40/50/60 min**
   (Standard/Rare/Epic/Legendary) of typical play (ruling 2). Price table
   derivation is in 07, awaiting approval.
3. **Daily soft cap** — DECIDED: **no cap, monitor only** via
   `minigame_result` telemetry (ruling 3).
4. **Bundle discount + sell-back pairing** — DECIDED: **Sell Back refunds
   50% of the *current* individual cosmetic cost** (live `coinCost`);
   prices drift up over time, refunds drift with them (ruling 4).
5. **Difficulty spread** — DECIDED: **compress and reword to 1x/1.5x/2x**
   (Easy/Normal/Hard); Easy is knowingly EV-optimal per attempt — see the
   honest EV note in 07 (ruling 5).
