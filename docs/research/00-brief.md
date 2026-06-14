# 00 — Strategy Brief & Guardrails

_Roll Along competitive teardown & monetization / virality analysis._
_Artifact 0 of the research chain. Every downstream prompt reads this file first._

---

## Status & honest caveat

Roll Along is **effectively pre-launch**: the analytics endpoint returns HTTP 400s
and the app is being tested on-device only. **We have no real retention or
revenue data.** Therefore this whole effort is a **design / mechanic teardown and
gap analysis**, not data-driven optimization. Every recommendation we produce is a
**hypothesis** with a named metric to validate once the (already-instrumented)
analytics go live. Treat all competitor revenue/scale figures as **directional and
cited** — the precise Sensor-Tower-grade numbers are paywalled.

---

## 1. The goal

Understand how Roll Along differs from the most popular / best-monetized comparable
apps, and produce a prioritized, guardrail-respecting roadmap to make it **more
popular, more viral, and more monetizable** — without betraying its identity.

---

## 2. Locked guardrails (from calibration — these are firm)

| Axis | Decision |
|---|---|
| **Monetization stance** | **Player-friendly, cosmetics-led.** The deep cosmetics catalogue is the *primary* spend engine. A **seasonal/battle pass is allowed** — as a one-time per-season purchase, **not** an auto-renew subscription. **No** interstitials, **no** FOMO pressure. Lower revenue ceiling, maximum goodwill — accepted on purpose. |
| **Infrastructure** | **Full backend, incl. multiplayer.** Async or real-time competitive multiplayer + a full LiveOps event engine are in scope. Live leaderboards, remote config, and timed events are all on the table. (Biggest build + ops cost of the options — accepted.) |
| **Growth** | **Organic + ASO + viral clips only.** No paid UA budget. Success hinges on store optimization and shareable, TikTok-able moments. → **Shareability and ASO are first-class, heavily-weighted evaluation axes.** |
| **Ethics — all four firm** | • **No pay-to-win in competitive** (cosmetics/convenience only). • **No loot-box / gambling** (no randomized paid pulls / gacha). • **No forced interstitials** (rewarded/opt-in ads only). • **No predatory FOMO** (timers framed as opportunity, never punishment/guilt). |

### Decision rules for every downstream prompt (apply mechanically)

- ❌ **Reject** any idea requiring forced interstitials, randomized paid pulls, pay-to-win in competitive modes, or guilt/countdown-pressure FOMO.
- ✅ **Battle pass = allowed** as a one-time seasonal purchase with a free + premium track; cosmetic-heavy rewards. Auto-renew subscriptions are **out** (the existing unlimited-lives sub is grandfathered but not a model to expand).
- ⭐ **Cosmetics are the monetization engine** → favor ideas that deepen cosmetic *desire*, *expression*, *acquisition*, and *visibility to others*.
- 🌐 **Backend + multiplayer in scope** → live competition, events, leaderboards, remote config are allowed (score them high-effort, not out-of-scope).
- 📣 **Organic growth** → weight virality/shareability/ASO heavily; a capture-and-share feature is a probable headline recommendation.

---

## 3. Positioning (proposed — confirmed in Prompt 2)

**Hybrid-casual physics roller with a competitive/social spine and a deep cosmetic
meta.** Casual, skill-expressive tilt core (hyper-casual roller DNA) + long
meta-progression (5,000-level climb + Challenge Tracks) + a suite of competitive
minigames + a broad cosmetics economy + nascent social (friends/clans/leaderboards).
The chosen guardrails push it toward a **"fair, social, cosmetic-led competitive
marble platform"** — closest in spirit to Brawl Stars / Stumble Guys' *monetization
philosophy*, on a roller core.

---

## 4. Competitor set (proposed — finalized/trimmed in Prompt 2)

Tuned to the chosen profile (cosmetic-led + competitive multiplayer + fair):

- **Tier 1 — Direct rollers** (core-loop juice & roller virality): Going Balls, Rolling Sky, Helix Jump _(alt: Ball Run 2048)_.
- **Tier 2 — Cosmetic-led competitive multiplayer** (the aspirational profile): **Brawl Stars** (the gold standard for *fair* monetization — dropped loot boxes, cosmetics + battle pass, no P2W), **Stumble Guys**, **Smash Karts** (.io competitive).
- **Tier 3 — Retention / LiveOps systems to learn from** (not the monetization tone, but the engine): Subway Surfers (seasons & LiveOps cadence), Candy Crush (lives/energy + episodic).

_Likely trimmed to ~6–7 in Prompt 2 to keep the research budget tractable._

---

## 5. Constraints & assumptions

- **Team:** **solo, no employees** (Mac), with occasional spun-off worktree agents. SwiftUI + StoreKit + Google Mobile Ads/UMP; Supabase scaffolding partially built for social.
- **Revenue goal: self-sufficient, not maximizing.** It does **not** need to make hundreds of thousands of dollars. Target = cover its (modest, indie) costs and reward the work — a passion project that pays its own way. This is a deliberate, freeing constraint: it means **time/ops bandwidth is the scarce resource, not dollars**, and it tilts every weighting toward *joy, fairness, longevity, and reach* over revenue extraction.
- **Capacity / timeline:** assumed part-time, pre-launch (timeline still TBD — confirm). Effort scoring assumes one developer's bandwidth is the bottleneck.
- **Platform:** iOS first.

---

## 6. What "better" means here (success definition)

Because there's no live data yet, we define success as **moving the right design
levers** and **wiring the analytics to prove it post-launch**. Given the
self-sufficiency goal, the **weighting is: popularity/retention/joy first,
self-sustaining monetization second** (money follows users — get the players and
the joy right, and a fair cosmetics + pass economy covers the modest costs):

- **Popular / viral (primary):** organic install velocity → proxied pre-launch by *shareability surface area* (capture/share, social hooks, ASO assets) and D1/D7 *design* hooks.
- **Retention / joy (primary):** depth of the reasons to come back tomorrow and the moment-to-moment delight — the actual engine of an organic, fair game.
- **Self-sufficient (secondary):** clears its modest costs *within* the cosmetics + pass model — proxied by *desire depth*, *expression visibility*, and *fair acquisition friction*. Not ARPDAU-maximization.
- Every roadmap item names the **single metric it should move** and **how the existing analytics events would measure it** once live.

---

## 7. Key tensions & risks (on the record)

1. **The real constraints are your time and player density — NOT money.** _(Corrected after calibration — Mac's call, and the right one.)_ Brawl Stars and Fortnite prove fair, cosmetics-led monetization funds even real-time multiplayer **at scale**: fairness isn't a revenue ceiling, it's a scale problem, and money follows users. With a solo dev and a **self-sufficiency, not maximization** goal, the dollar bar is low and easily cleared by a fair cosmetics + pass economy once users exist. The binding constraints are instead:
   - **(a) Solo build/ops bandwidth.** Real-time multiplayer means matchmaking, latency, state authority, anti-cheat, and on-call reliability — a large, permanent ops burden for one person (Brawl Stars has a team for exactly this).
   - **(b) Population density.** Real-time MP simply doesn't function with empty lobbies; it *needs* concurrent players to exist before it's worth building.

   Both point the same way: **async / ghost competition first** — leaderboards, a shared daily-challenge seed everyone races, beat-this-replay, async tournaments. It works at *any* population, is cheap to run, ships far sooner, and *builds toward* real-time MP as a later bet once there's a live base to fill matches. **This is smart sequencing, not a ceiling on ambition** — real-time multiplayer stays firmly on the table as a bigger bet.
2. **Organic-only growth raises the bar on virality.** With no paid UA, the game must be *inherently* shareable; a clip/share feature and ASO are not nice-to-haves — they're the growth engine.
3. **Cosmetics-led requires *desire*, not volume.** The catalogue is already deep; the lever is making players *want* to acquire, *express*, and *show off* looks (visibility to others is what converts in fair games). That's exactly what Brawl Stars / Stumble Guys / Fortnite teach.

---

## 8. Pipeline & artifact index

| # | Prompt | Output artifact | Checkpoint |
|---|---|---|---|
| 0 | Calibration | `00-brief.md` (this) | ✅ done |
| 1 | Internal teardown | `01-roll-along-teardown.md` | |
| 2 | Market frame + rubric | `02-market-frame.md` | 🔲 you confirm set |
| 3 | Competitor teardowns | `03-competitors/<app>.md` (×N) | |
| 4 | Gap matrix | `04-gap-analysis.md` | 🔲 you confirm gaps |
| 5 | Opportunity backlog | `05-opportunities.md` | |
| 6 | Prioritized roadmap | `06-roadmap.md` | 🔲 final approval |
| ↺ | Refinement loop | per-opportunity design spikes + red-team | on demand |

_Recursion model: artifacts persist context across prompts; checkpoints let you
steer before the chain compounds; any node can be recursed into for depth._
