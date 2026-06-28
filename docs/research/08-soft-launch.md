# 08 — Soft-Launch Plan

_The validation gate the red team (`07`) put in front of everything. Phase 1 is built
(keystone cosmetics, shareable result card, rarity-as-status, profile drip) and analytics
is fixed + verified. This doc is the go/no-go: **is the core fun and retentive enough to
justify building the expensive Phase 2/3 scaffolding?** Lightweight by design — Mac runs
this solo, around a day job and a July-2026 wedding._

---

## 1. Purpose — this is a gate, not a launch

`07` RT-1 (the strongest critique in the chain): we optimized meta/social/monetization for
a game with **no retention data**. The fix is to **measure before we scaffold**. This
soft-launch answers one question:

> Do real players come back and have fun — enough that ghost racing, seasons, and a pass
> are worth building?

If yes → proceed to **Phase 0 (remote config)** then **Phase 2/3**. If no → fix the core
(controls, onboarding, fun) **first**. The cheap keystone + result card ride along in the
test build (they make the test representative and are low-regret either way — RT-1).

## 2. What's in the test build

- The climb (5,000+ levels) + all competitive modes (Smash and Grab, Gold Rush, KOTH, Sumo,
  Marble Cup, Paint Ball, Comet Clash).
- **Keystone live everywhere:** opponents wear real ball skins + trails, name tags, the
  leader crown.
- **Shareable result card** on every round-over (fires `result_shared`).
- **Rarity-as-status** (shop + profile) and the **My Loadout** drip showcase.
- **Analytics verified** (events table deployed; 201 inserts confirmed, anon read blocked).

## 3. Cohort

- **Target: 50–200 testers** (RT-1). Recruit **organically only** (brief guardrail: no paid
  UA): friends/family, the wedding network, indie-dev / marble-game / r/iosgaming-type
  communities.
- **TestFlight path:** Internal testers (up to 100, no review, instant) for the first pass;
  then External (up to 10,000, needs a one-time Beta App Review) to reach the full cohort.
- **Caveat that shapes everything:** a friends-and-family cohort is **biased kind**.
  Retention numbers will be **inflated**; treat them as a *ceiling*, and weight the
  **qualitative** signal (watch + interview) heavily.

## 4. KPIs & how each is measured

All queries live in [`docs/soft-launch-metrics.sql`](../soft-launch-metrics.sql) — run in
the Supabase SQL Editor with the **service_role** key (anon can't read events).

| KPI | Question | Event basis |
|---|---|---|
| **D1 / D7 retention** ⭐ | Do they come back? (the core gate) | `app_launch` per `user_id` per day |
| Sessions / user / day | How sticky per day? | distinct `session_id` |
| Session length | How long per sit? | min→max `created_at` per `session_id` |
| **Mode popularity** | What do they actually play? | `*_round_started` / `minigame_entered` |
| **Core funnel** | Is the climb tuned? | `level_complete` vs `level_fail` |
| Round completion | Do competitive rounds finish? | `*_round_started` vs `*_round_over` |
| **Share-rate** ⭐ | Are wins share-worthy? (the experiment) | `result_shared` / round-ends |
| Cosmetic pull | Does the catalogue create desire? | `cosmetic_equipped` / `cosmetic_purchased` |
| Monetization | Directional only (tiny cohort) | `iap_purchased`, `*_purchased`, buy-sheet opens |

## 5. Kill-gates / success bars (honest, RT-2-recalibrated)

Targets are **Smash-Karts scale, not Brawl** — a competent, fair niche game is the prize.
Numbers are caveated by the friendly-cohort bias; the **interview signal can override the
numbers in either direction.**

| Gate | Pass bar | If it fails |
|---|---|---|
| **Core / retention** ⭐ | D1 ≳ 35% **and** D7 ≳ 10% **and** interviews show genuine (not polite) fun | **Stop.** Fix fun/onboarding before any scaffolding. |
| **Tilt controls** (RT-5) | Tilt is *not* the #1 friction for a majority of testers | Prototype a touch/drag control (Pinball already has alt controls) before scaling. |
| **Share-worthiness** (RT-4) | share-rate materially > 0 (≈ ≥3% of round-ends) **or** "I'd share this" in interviews | **Don't** build ReplayKit clip capture — the moments aren't compelling yet. |
| **Identity / positioning** (RT-6) | ≥ half of testers describe it in ~5 words ≈ "a competitive marble battler" | Sharpen onboarding to lead with the race, not the climb. |

## 6. Qualitative loop (do not skip — RT-1)

Numbers from 50–200 friendly users are noisy; **watching 5–8 people play is worth more.**
For each: screen-record or sit beside them, then a 5-minute interview:

1. First 60 seconds — what did they think it *was*? Where did they fumble?
2. Did they notice opponents' skins / the result card / their own cosmetics?
3. Tilt: natural or annoying? One-handed? Lying down?
4. Unprompted: would they play again? Would they share? With whom?
5. Describe the game to a friend in one sentence. _(the identity gate)_

## 7. TestFlight operational checklist (Mac)

Current version is `1.0` / build `1`. Steps:

1. **Bump build number** each upload (`CURRENT_PROJECT_VERSION`); keep `MARKETING_VERSION`
   at `1.0` for the beta.
2. Confirm a **release** archive (`Product → Archive`) builds clean (this is the local
   compile gate for the whole session's unverified changes — fix anything that surfaces).
3. **Upload** via Xcode Organizer or Transporter to App Store Connect.
4. App Store Connect → **TestFlight**: add the build, fill **Test Information** (what to try,
   how to give feedback), enable **Internal** testers first.
5. For the full cohort, create an **External** group → submit for **Beta App Review** (one-
   time, ~a day) → share the public TestFlight link.
6. **Test Info prompt for testers:** "Play a few rounds + a few climb levels. Try the
   competitive modes. Tap Share on a win. Tell me: was it fun, was tilt comfortable, and
   would you come back?"
7. Verify events are flowing: run the **DAU** query a day in — if it's empty, analytics
   isn't reaching real devices (debug before relying on any of this).

## 8. Timeline (keep it light)

- **Week 0:** archive + internal TestFlight (you + a few). Smoke-test the session's changes
  on device; confirm events flow.
- **Weeks 1–2:** external cohort live; collect data; run 5–8 watch+interview sessions.
- **Week 3:** read the gates → decide.

## 9. Decision framework

- **All core gates pass** → build **Phase 0 (remote config)**, then Phase 2 (challenge
  deep-links, monthly season, weekly missions) on a **solo-sustainable, remote-config,
  autopilot** cadence (RT-3). Greenlight clip capture only if the share gate passed.
- **Core/retention fails** → do **not** scaffold. Triage from interviews: most likely
  fixes are **touch controls** (RT-5) and **race-first onboarding** (Phase 4 item, pulled
  forward) — then re-test.
- **Mixed** → ship the cheap fixes the interviews surfaced, re-run a 1-week mini-cohort,
  re-decide.

## Scorecard at the gate

| Axis | Built (P1) | Validated by soft-launch? |
|---|---|---|
| Core | 4 | ← **the gate** (retention + tilt) |
| Onboarding | 3 | ← identity/positioning interview |
| Meta | 4 | shipped |
| Monetization | 3 | directional only |
| Virality | 3 | ← **share-rate experiment** |
| Social | 3 | shipped (backend live) |
| Retention | 2 | ← **D1/D7 — the headline number** |
| LiveOps | 1 | gated on this passing |

The honest prize (RT-2): a board of mostly 3s with a few 4s — a fair, competitive,
self-sufficient niche game. This soft-launch tells us whether the foundation holds before
we spend weeks building on it.
