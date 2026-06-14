# 07 — Red Team

_Adversarial pass on my own `00`–`06`. Each critique is steelmanned, then a verdict —
**Survives** (changes the plan) / **Partial** / **Rebutted** — and what it changes. The goal is
to find the real weaknesses before a line is built, not to perform skepticism._

---

## RT-1 — Cart before horse: zero core-loop validation 🔴 **SURVIVES (the big one)**

**The case against me:** The entire chain optimizes meta, social, and monetization for a game
with **no users and no retention data** — the analytics endpoint is literally returning **400s**,
so measurement is *broken*. If the core (tilt-roll a marble) isn't fun and retentive, a battle
pass and ghost races are lipstick on a game nobody opens twice. Stumble and Brawl had *proven
cores* before they built LiveOps. Roll Along has a hypothesis dressed as a foundation.

**Verdict:** Survives — strongest critique in the set. It reorders everything.

**Change:** Insert **Phase −1: Validate** *before* the expensive scaffolding:
1. **Fix the analytics 400s first.** Your measurement instrument is broken; that is the single
   most urgent item in this whole plan and it's nobody's idea of glamorous.
2. **TestFlight / soft-launch to 50–200 real players;** measure **D1/D7** and *watch + interview*
   a handful.
3. **Gate** the costly systems (ghost racing, seasons, pass, tournaments) on the core clearing a
   retention bar. The **cheap keystone + result card ride along in the test build** — they make
   the test representative and are low-regret either way.

---

## RT-2 — Survivorship bias: you benchmarked billion-dollar outliers 🔴 **SURVIVES (recalibrate)**

**The case against me:** Brawl / Fortnite / Subway are the 0.01%, run by hundreds of people.
Copying their *systems* at solo scale risks a hollow imitation. The one **true comparable** —
Smash Karts, a *small team* — scored mostly **3s, not 5s.** That is the realistic ceiling: a
good, fair, *modestly* successful niche game. The 8.8× Brawl figure must not set expectations.

**Verdict:** Survives.

**Change:** **Recalibrate the target scorecard down** (below). The Brawl/Subway *mechanisms* are
sound to borrow; the *outcomes* at solo scale look like Smash Karts. Reframe success as **"a fair
competitive roller that pays for itself and delights a dedicated community"** — which is exactly
the brief's self-sufficiency goal. Stop implying a board of 4-5s is on the table.

---

## RT-3 — The LiveOps treadmill is a solo burnout machine 🔴 **SURVIVES (right-size)**

**The case against me:** I prescribed monthly seasons + weekly missions + tournaments + a pass —
a **forever** content commitment, the *opposite* of a low-maintenance, self-sufficient passion
project. Mac has a day job (Focal Dataworks) and a **wedding in July 2026.** Stumble Guys
*declined* with a whole studio feeding the treadmill; a solo dev sustaining it invites burnout and
a half-dead game. The plan imported a studio operating model and called it a roadmap.

**Verdict:** Survives — and it contradicts the brief's own framing.

**Change:** Make **burnout-resistance a design requirement.** Right-size LiveOps to
**solo-sustainable autopilot**: evergreen-first; **quarterly** seasons, not monthly; missions that
**auto-rotate from a pool** (author once, cycle forever); a pass that can run **long / auto-extend**;
everything **remote-config-driven** so "a new season" is a *data change*, not a release + review.
Design every live system to run untouched for months.

---

## RT-4 — A share button doesn't create virality 🟠 **PARTIAL (reframe as experiment)**

**The case against me:** Clips go viral because the *content* is compelling, not because a button
exists. You can ship a flawless share flow and get zero shares. Building share infra ≠ building
virality.

**Verdict:** Partial — true, but the button is the *cheapest possible test* of share-worthiness.

**Change:** Frame the **result card as a share-worthiness experiment with a kill-gate:** if
share-rate is near-zero in the soft launch, the moments aren't compelling — learn that **before**
building the expensive ReplayKit clip capture (already sequenced later — good). Add the metric +
kill criterion explicitly. Don't *assume* virality; *probe* for it cheaply.

---

## RT-5 — Nobody questioned the tilt controls 🟠 **PARTIAL (cheap experiment)**

**The case against me:** Accelerometer tilt is **divisive and niche** — bad one-handed, bad lying
down, accessibility-hostile, not how most casual players want to play (the top casual games are
tap/swipe). The control scheme may be the real ceiling on popularity, and **seven documents never
once questioned it.**

**Verdict:** Partial — a real, unexamined risk; not a plan-killer (tilt is also the distinctive,
clip-able thing, and Pinball already ships a no-tilt control in-codebase).

**Change:** Keep tilt, but (a) flag it as an **untested core assumption** to watch in the soft
launch, and (b) prototype a **touch/drag control option** (cheap — alternate controls already
exist for Pinball) for accessibility + reach. Let players choose.

---

## RT-6 — The "assets" may be liabilities; the identity is diffuse 🟠 **PARTIAL (focus)**

**The case against me:** 9 modes + 5,800 levels reads as **"master of none."** Can you say what
Roll Along *is* in five words? A diffuse identity kills ASO, word-of-mouth, and virality — people
share games they can *describe.* The grab-bag may be a weakness dressed as richness.

**Verdict:** Partial — the content is cheap to keep (one shared engine), but the *positioning* is
genuinely unfocused.

**Change:** Make an **identity decision.** The whole strategy points at competition → **lead with
"a fair, competitive cosmetic marble battler"** and let the 5,000-level climb be the deep B-side.
Market and onboard as ONE thing. This *strengthens* race-first onboarding and ASO. (Fix is focus,
not deletion.)

---

## What I defend (doesn't change)

- **The keystone thesis — visible identity in competition — stands.** All six competitors
  validate the *mechanism*; it's cheap; it's the right first build. (Its *payoff* is gated on
  RT-1's core validation, but the work is low-regret regardless.)
- **The guardrails stand** — the red team only reinforces them.

**One concession on my own pitch:** I **oversold "fairness as marketing."** Brawl's fairness
pivot worked because it had ~100M lapsed players to win back with goodwill PR. A no-name indie's
"no loot boxes" is **not a user-acquisition lever** — nobody chooses between Roll Along and a
gacha game on ethics. Fairness is a **values + retention/goodwill** win, not a *growth* one. I'll
stop pitching it as growth.

---

## Recalibrated scorecard — optimistic vs. honest solo-scale target

| Axis | Now | Doc-06 target | **Honest target** |
|---|---|---|---|
| Core | 4 | 5 | **4–5** _(gated on tilt — RT-5)_ |
| Onboarding | 3 | 4 | **4** |
| Retention | 2 | 4 | **3** _(gated on RT-1)_ |
| Meta | 3 | 4 | **4** |
| Economy | 3 | 4 | **3–4** |
| Monetization | 2 | 5 | **3–4** _(fair pass ≠ Brawl 5)_ |
| Virality | 1 | 4 | **3** _(button ≠ virality — RT-4)_ |
| Social | 1 | 4 | **3–4** _(backend exists — achievable)_ |
| LiveOps | 1 | 4 | **3** _(solo-sustainable, not Brawl/Subway)_ |

A board of **mostly 3s with a few 4s = a competent, fair, self-sufficient niche game.** That's the
honest prize — and it's exactly what the brief asked for. Doc-06's 4-5s were aspirational.

---

## Revised "build next" (survives scrutiny)

The plan **mostly holds**, but the order of operations changes:

1. **Fix the analytics 400s.** Highest urgency, lowest glamour. You can't validate or gate
   anything while measurement is broken.
2. **Build the keystone (show opponents' cosmetics) + the result card.** Cheap, low-regret, and
   they make a soft-launch build more compelling and testable. ← *what Mac wants to build next; it
   survives.*
3. **Soft-launch to a small audience; measure D1/D7 + share-rate** with explicit kill-gates.
4. **Only then** commit to the expensive scaffolding (ghost racing → seasons → pass), built on a
   **solo-sustainable, autopilot, remote-config** cadence — and with **expectations set to
   Smash-Karts-scale, not Brawl.**

Net: the keystone is still the right thing to build next. The red team didn't kill the plan — it
added a **validation gate in front of it, a burnout-proof shape to the LiveOps, an honest
expectation reset, and three cheap experiments (share-worthiness, tilt, identity) that could each
save weeks of building the wrong thing.**
