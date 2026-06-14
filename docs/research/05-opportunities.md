# 05 — Opportunity Backlog (scored)

_Artifact 5. Reads `04-gap-analysis.md`. Turns gaps + edges into scored opportunities.
**Priority = value ranking.** Dependency *sequencing* is the roadmap's job (Prompt 6) — so a
few lower-priority **enablers** (remote config) get built early there regardless of rank._

**Impact** = effect on the primary goals (popularity / virality / retention) + secondary
(self-sufficient monetization). **Effort** (solo dev, SwiftUI, Supabase): **S** ≈ days · **M** ≈
1–2 wks · **L** ≈ several wks · **XL** ≈ month+. ✅ borrow · ⚠️ adapt · all inside the guardrails.

> **Social Stakes elevated to P3** per Mac — overall social effectiveness is a headline goal,
> not a fast-follow.

---

## P1 — Keystone: Public Identity in Competition  ⭐ the foundation
_Moves scorecard: **Monetization 2→4, Social 1→3 (enabler), Virality (enabler), Meta 3→4.**_

| Opportunity | Impact | Effort | Proof | Notes |
|---|---|---|---|---|
| **Show opponents' real ball skin + trail** (viewer's floor/goal stay own) | **High** | **M** | Brawl/Stumble/Smash | Mac's directive. For AI rivals, assign **varied, desirable** owned-able skins → showcases the catalogue + creates "I want that" moments. The literal keystone. |
| **Win celebrations / emotes** (new cosmetic category, visible to opponents) | High | M | Brawl pins / Stumble emotes / Smash | New, highly visible, clip-able spend category. Confirmed by all 3 competitive games. |
| **Rarity-as-status** (surface common→legendary in shop / profile / in-game) | Med | **S** | Smash Karts | Makes the *existing* catalogue feel deeper; cheap. |
| **Profile "locker" / drip showcase** others can see | Med | S–M | Brawl/Fortnite | Owning cosmetics becomes social capital. |

## P2 — Virality: Capture & Share  📣 the growth engine
_Moves scorecard: **Virality 1→4.**_

| Opportunity | Impact | Effort | Proof | Notes |
|---|---|---|---|---|
| **Shareable result card** (image: your skin + score + placement + deep link) | **High** | **S** | Going Balls/Helix | The quick win — a tappable "share" on every win/round-over. |
| **Challenge deep links** ("beat my run" — shared seed, friend plays same) | High | M | Stumble/Subway | Viral loop + social in one; async. |
| **Clip / replay capture** (ReplayKit or render-to-video, watermarked w/ skin) | High | **L** | Helix (TikTok) | The big virality bet; do *after* the result card validates sharing behavior. |

## P3 — Social Stakes  🤝 _(elevated per Mac)_
_Moves scorecard: **Social 1→4 (activates the built backend), Retention 2→3.**_

| Opportunity | Impact | Effort | Proof | Notes |
|---|---|---|---|---|
| **Make leaderboards matter** — ranked seasons + cosmetic-only rewards + a **visible rank badge** | **High** | M | Brawl ranked | Backend's `fetchLeaderboard` already exists — add seasons, reward grants, a badge shown in competition/profile. |
| **Async ghost racing** — race friends'/global recorded runs | **High** | L | Smash/Going Balls | **The affordable multiplayer-first-step** (brief's async-first). Competition + cosmetic visibility, cheap to run. |
| **Friend challenges / async duels** | High | M | Stumble | Built on the same seed/ghost machinery + the existing friends graph. |
| **Clan goals** — weekly clan challenge + shared cosmetic unlock | High | M–L | Brawl clubs | Clans exist but *do nothing*; give them a reason to act together. |

## P4 — LiveOps Engine  ⚙️ the engine room
_Moves scorecard: **LiveOps 1→4, Retention 2→4, Meta 3→4.**_

| Opportunity | Impact | Effort | Proof | Notes |
|---|---|---|---|---|
| **Remote config** (Supabase-driven) | **High (enabler)** | M | Subway/Brawl | Tune/toggle without an App Store release — the foundation everything LiveOps rides on. **Built early in the roadmap despite P4 rank.** |
| **Monthly themed season + Season Hunt** (collect tokens → limited ball/trail) | High | L | Subway World Tour | The retention cadence + the antidote to Stumble's decline. Rich coin/ticket sink. |
| **Weekly missions / quests** | Med–High | M | Subway tiered events | The missing D7 hook. |
| **Event leaderboard tournaments** (cosmetic-only top-placement rewards) | High | M–L | Stumble Mythic-per-tournament | Overlaps P3 — competition + cosmetic chase, fair. |

## P5 — The Roll Pass  🎟️ the monetization headline
_Moves scorecard: **Monetization 2→5.** Depends on P4 cadence._

| Opportunity | Impact | Effort | Proof | Notes |
|---|---|---|---|---|
| **The "Roll Pass"** — cheap (~$5), fair, cosmetic-heavy seasonal pass (free + premium track) | **High** | L | Brawl (8.8×) | One-time seasonal, **not** auto-renew. Optimize for *many buyers*, not whales. Sits on the monthly season. |

## P6 — Hook & Rebalance  🎯 polish that compounds
_Moves scorecard: **Onboarding 3→4, Core 4→5, Economy 3→4.**_

| Opportunity | Impact | Effort | Proof | Notes |
|---|---|---|---|---|
| **Race-first onboarding** (legible ~30s race/scramble before revealing the climb) | Med–High | M | Going Balls/Helix | Sell the joy + cosmetics in minute one; *then* the depth. |
| **Lives→cosmetics rebalance** (+ rewarded-video "double coins" / daily-skin trial) | Med | S–M | Brawl fairness | Shift weight from friction-monetization toward desire-monetization; rewarded-only. (Daily-reward nerf untouched.) |

---

## Top of the backlog — best impact-to-effort (the shortlist)

If we did only six things, in this order of leverage:

1. **Show opponents' cosmetics** (P1) — High / M — *the keystone; everything else gains value.*
2. **Shareable result card** (P2) — High / **S** — *the cheapest virality unlock in the whole backlog.*
3. **Rarity-as-status** (P1) — Med / **S** — *deepens desire on what you already have, almost free.*
4. **Remote config** (P4) — High-enabler / M — *unlocks all LiveOps; solo-dev superpower.*
5. **Make leaderboards matter** (P3) — High / M — *activates the dormant social backend.*
6. **Async ghost racing** (P3) — High / L — *affordable competition; the multiplayer beachhead.*

## Dependencies (for the roadmap to sequence)

- **Remote config (P4)** is an *early enabler* — built before seasons, pass, and tournaments despite its P4 value-rank.
- **Public cosmetics (P1)** precedes virality clips and ranked badges (there must be drip worth seeing/sharing).
- **The Roll Pass (P5)** requires the **monthly season (P4)** to exist first.
- **Tournaments (P4)** and **ranked seasons (P3)** share the leaderboard backend — build the season/leaderboard service once, use twice.

_Next: Prompt 6 sequences these into a phased, build-ready roadmap — tied to specific files/systems in the repo, each with the metric it should move and how the existing analytics would measure it._
