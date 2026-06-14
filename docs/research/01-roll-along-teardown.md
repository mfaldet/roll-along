# 01 — Roll Along Internal Teardown

_Artifact 1. Honest, code-grounded audit of what's wired today, across nine axes._
_Reads: `00-brief.md`. Caveat: maturity tags are **design** maturity (no live data yet)._

**Maturity scale:** 🟢 Strong · 🟡 Solid · 🟠 Partial · 🔴 Thin · ⚫ Absent

| Axis | Maturity | One-line verdict |
|---|---|---|
| 1 Core loop | 🟢 | Distinctive, clip-able tilt physics + a content spine most indies can't match. |
| 2 Onboarding / D1 | 🟡 | Overlay + phased L1 tutorial + 10 life-free levels. Teaches the climb, not the meta. |
| 3 Retention loops | 🟠 | Energy + daily reward + gifting exist; "why open it tomorrow" is weak post-nerf. |
| 4 Meta-progression | 🟡 | Enormous but mostly linear; collection is the richest layer, under-leveraged. |
| 5 Economy | 🟡 | Three currencies, fair + guard-railed; shallow sinks/faucets; nerf may starve cosmetics. |
| 6 Monetization | 🟠 | Lots of IAP SKUs, but leans on *lives/friction*; cosmetics-led model is **not yet built**. |
| 7 Virality | 🔴 | One static profile share card. No gameplay capture/clip/referral. The growth engine is missing. |
| 8 Social | 🟡 | **Real Supabase backend** (friends/clans/leaderboards/gifting) — rare asset — but no *stakes*. |
| 9 LiveOps / events | ⚫ | No event/season cadence, no remote config in use. The structural gap. |

---

## 1. Core loop — 🟢

**Wired:** Tilt-accelerometer marble physics (`BallMotion` + `PhysicsClock`). Spine = the 5,000-level **Adventure** climb (`ClimbMode`, consumes lives, stars). Around it: **9 minigames** (Zen Garden, the two coin rounds, Comet Clash, Sumo Survival, Paint Ball, Marble Cup, King of the Hill, Pinball) reached via the Games hub. Home screen is now a free-roaming physics **playground** (the ball caroms off the UI) — strong idle juice.

**Weak spots:** The value prop is **spread thin** — Adventure vs. competitive vs. solo-zen are three different games sharing a control scheme. No single "this is the 10-second hook" that a new player or a TikTok viewer instantly gets. Distinctiveness is high; **focus/identity is the open question.**

## 2. Onboarding / D1 — 🟡

**Wired:** First-launch `onboardingOverlay` (HomeView); a **phased L1 tutorial** (`TutorialPhase`); levels **1–10 don't consume lives** (`tutorialLevelCount`), a generous ramp. ATT prompt correctly deferred to post-onboarding.

**Weak spots:** Onboarding teaches **the climb only**. It never introduces the cosmetics shop, competitive modes, tickets, or the social layer — i.e., none of the *retention or monetization* hooks. First session sells the least monetizable mode.

## 3. Retention loops — 🟠

**Wired:** Lives/energy with **6-min regen, cap 10** (a soft session-pacing pull-back); **daily reward** 7-day ladder; **life-gifting** between friends (`sendLife`/`claimGift` — a real ask-friends loop); **Challenge Tracks** as evergreen goals; **Starter Pack** 48h window.

**Weak spots:** The **"open it tomorrow" reason is thin**: daily reward was just nerfed to [5,8,10,12,15,20,35] and energy regen is gentle, so neither creates much pull. **No daily/weekly missions or quests. No streak rewards beyond the ladder. No battle-pass grind. No event countdown.** Retention rests on evergreen content + a weak daily — fine for a few sessions, weak for D7/D30.

## 4. Meta-progression — 🟡

**Wired:** Headline `currentLevel`/`highestUnlocked` (climb); **8 Challenge Tracks × 100 levels** with bundle rewards on completion (some gated, e.g. Golden Gauntlet ≥3 completions); a **deep cosmetics collection** (skins, trails, goals, floors, pits, music + bundles/packs) across tiers; per-track high-water marks.

**Weak spots:** Progression is mostly **"number goes up" + "collect skins."** No power/mastery progression, no seasonal track, no prestige. The **collection is the richest meta layer and the most under-leveraged** — there's no *set completion* celebration, no *showcase*, no reason others ever see what you own. (Critical thread → axis 7/8.)

## 5. Economy — 🟡

**Wired (3 currencies):**
- **Coins** — soft currency; faucets = level clears, daily reward, coin-round payouts, IAP packs (100/600/1300/3000); **single sink = cosmetics shop.** Integrity-guarded (`addCoins` clamps, ceilings).
- **Lives** — energy gate; faucets = regen, gifts, IAP/ads; sinks = climb/track attempts.
- **Tickets** — faucet = **+1 per competitive win**; sink = **staking a Gold Rush round** (30s + coin-multiplier).

**Weak spots:** Sinks/faucets are **narrow** — coins have one sink, tickets have exactly one faucet and one sink. **No coin chase beyond cosmetics**, and tickets are a clever but **isolated** loop bolted to one mode. _(The recent daily-reward nerf is a deliberate, retained decision — revisit only if post-launch analytics show coin starvation throttling cosmetic engagement.)_

## 6. Monetization surfaces — 🟠

**Wired:**
- **IAP (16 SKUs):** coin packs ×4 ($0.99–), life packs ×3 ($0.99/$4.99/$9.99), **Unlimited Lives** (non-consumable), **Starter Pack $1.99**, **7 seasonal bundles $2.99** (summer→spring, cosmetic contents).
- **Ads:** **rewarded only, ONE placement** (`BallGameView` out-of-lives continue). No interstitials (✅ matches guardrail), no banners.
- **Sub:** Unlimited Lives (one-time non-consumable, not recurring).

**Weak spots (vs. the chosen cosmetics-led model):**
- ❌ **No battle/season pass** — the brief's headline allowed mechanic, entirely missing.
- ✅ **A cosmetics storefront already exists and is reasonably deep** (`CosmeticShopView` — buy skins/trails/goals/floors/pits/music with coins; real money buys coins or the 7 fixed seasonal bundles). _(Correction: an earlier draft wrongly implied this was missing.)_ So the store isn't the gap — the **pass** is, and far more than the store, the **desire/visibility layer** that makes players *want* the skins (axes 7/8).
- 🔴 **Rewarded video almost untapped** — one placement; the fairest lever (watch→double coins, free daily skin trial, +1 ticket) is unused.
- ⚠️ **Monetization centre of gravity is lives/energy (friction)**, not cosmetics/identity (desire) — a **misalignment** with the stated stance. Today the game mostly earns by selling relief from a gate; the brief says it should earn by selling self-expression.

## 7. Virality / shareability — 🔴

**Wired:** A single **`ShareLink` profile card** in `ProfileView`. That's it.

**Weak spots:** **No gameplay capture, no replay/clip export, no "watch my run," no challenge-a-friend, no referral/invite, no shareable win moment.** The tilt-physics fails and cosmetic flair are *inherently* the most clip-able thing in the app, and for an **organic-growth-only** game this is **the single most important missing system.** Growth currently has no engine.

## 8. Social — 🟡 (the sleeper asset)

**Wired:** A **genuine Supabase/PostgREST backend** (`SocialClient`) — Sign in with Apple → Supabase Auth, plus: profiles + progress sync, **leaderboard** fetch, **friends** (request/accept/remove/search), **clans** (create/join/leave/disband/roster/search), and **life-gifting**. This is real, working infrastructure most solo casual games never build.

**Weak spots:** It's **plumbing without stakes.** Leaderboards rank but reward nothing; clans exist but *do nothing together* (no clan goals, chat, or events); friends can gift lives but can't **compete head-to-head**; nobody sees anyone's cosmetics. The hardest part (the backend) is done; the **meaning** is missing — and it's the natural home for both the multiplayer ambition and cosmetic visibility.

## 9. LiveOps / events — ⚫

**Wired:** Nothing recurring. Challenge Tracks are static evergreen content; the daily reward is the only time-gated element. Remote config (allowed by the brief) **is not in use** — every tunable is a constant in the binary, so any balance change needs an App Store release.

**Weak spots:** **No event engine, no seasons, no limited-time modes, no leaderboard tournaments, no remote tuning.** This is the structural foundation that the fair battle pass, the retention cadence, and live competition would all sit on — and it's the deepest hole. Every retention/monetization exemplar (Subway Surfers, Brawl Stars) is *built around* this.

---

## Synthesis

### Genuine assets — lean in
1. **Distinctive, clip-able tilt physics** + a polished playground home screen.
2. **An unusually deep cosmetics catalogue** — the monetization engine is already content-rich (rare; usually the bottleneck).
3. **A real social backend already built** — friends/clans/leaderboards/gifting. Most indies never get here.
4. **Massive content longevity** — 5,000 climb + 800 track levels + 9 minigames.
5. **A clean, fair, guard-railed economy** and a **maintainable architecture** (engine pattern, test suite) sized for one dev.

### The structural through-line (the strategic insight)
In fair, cosmetics-led games (Brawl Stars, Fortnite, Stumble Guys) the **entire monetization engine runs on *other players seeing your cosmetics*.** Roll Along's cosmetics are today almost entirely **self-visible** (your own ball, alone). The three deepest holes — **virality (7)**, **social-with-stakes (8)**, and **events/competition (9)** — are the **same hole** viewed three ways: *there is no surface on which one player's identity/skill is seen by others.* Close that one surface and cosmetics gain a reason to exist, social gains stakes, and clips gain a reason to be shared. **That linkage is the spine of the whole opportunity** — and it'll drive the gap analysis (Prompt 4) and roadmap (Prompt 6).

> **Confirmed direction (Mac, calibration):** the fix starts in the competitive modes — **render each opponent's *own* equipped ball skin + trail** (so players see each other's drip, and yours is seen), while the **floor/background and goal always render the *viewer's own* cosmetic** (your world stays yours). This cleanly splits cosmetics into **PvP-visible identity** (ball + trail → status/desire drivers) and **personal-world** (floor/goal → private expression). First concrete brick of the "make identity visible to others" spine; carried forward into the roadmap.

### Biggest internal holes (preview of the gap analysis)
1. **No virality/clip-share surface** — fatal for organic growth (axis 7).
2. **No events/season/LiveOps cadence or remote config** — the missing engine room (axis 9).
3. **No battle pass** — the chosen monetization headline, absent (axis 6).
4. **Social infra without stakes** — built but inert (axis 8).
5. **Cosmetics are private** — deep catalogue, no expression/visibility/desire mechanics (axes 4/7/8).
6. **Thin "tomorrow" hooks** beyond a nerfed daily (axis 3).
