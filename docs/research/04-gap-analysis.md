# 04 — Gap Analysis (Roll Along vs. the field)

_Artifact 4. Reads `01` (internal) + `03/*` (competitors). The last analysis step before
opportunities (Prompt 5) and roadmap (Prompt 6). Caveat: design comparison, no live data._

---

## The matrix

Roll Along scored on the same 1–5 scale as the competitors (translated from `01`'s maturity
tags). "Field best" = the strongest exemplar on that axis.

| Axis | Roll Along | Field best | Gap | Verdict |
|---|---|---|---|---|
| **Core loop** | 4 ⭐ | 5 (Brawl/Subway) | ⚠️ slight | Distinctive tilt physics — a real edge. Hook is *split* (climb vs. competitive); needs a race-first front door. |
| **Onboarding** | 3 | 5 (Helix/Going) | ⚠️ | Solid, but sells the **5,000-level climb** — the least monetizable, least viral mode. |
| **Retention** | 2 | 5 (Brawl/Subway) | ❌ | Only a (nerfed) daily reward. No weekly missions, no monthly season, no pass grind. **Big gap.** |
| **Meta-progression** | 3 ⭐ | 5 (Brawl) | ⚠️ | Catalogue + content **volume is an edge**; but progression is linear and the collection is **private**. |
| **Economy** | 3 | 4 (Brawl) | ⚠️ | Fair, guard-railed, but **narrow sinks/faucets**. Adequate — not the priority. |
| **Monetization** | 2 | 5 (Brawl) | ❌ | Storefront exists, but **no pass**, and money is pointed at **lives/friction**, not **cosmetics/desire**. **Big gap + a misalignment.** |
| **Virality** | 1 | 5 (Helix) | ❌❌ | One static profile card. **No capture/share.** For an organic-growth game this is the **#1 blocker.** |
| **Social** | infra 4 ⭐ / stakes 1 | 5 (Brawl) | ⚠️→❌ | **The split asset:** a *real Supabase backend* (rare!) with **zero stakes** — leaderboards reward nothing, clans do nothing, friends can't compete. |
| **LiveOps / events** | 1 | 5 (Brawl/Stumble/Subway) | ❌❌ | None, and **no remote config**. The **engine room** that the pass, event skins, and retention all sit on. |

---

## Roll Along's genuine edges — lean in

The reassuring half: Roll Along already owns the **hard-to-build** assets. The gaps are mostly
*connective tissue*, not net-new games.

1. ⭐ **Distinctive, tactile tilt-physics core** + a playground home screen — more expressive and clip-able than tap-runners.
2. ⭐ **The deepest cosmetic catalogue, relative to game size** — the content engine competitors *wish* they had (Going Balls/Smash run on far fewer). The monetizer is already stocked.
3. ⭐ **A real social backend, already built** — friends, **clans**, leaderboards, **life-gifting**. Most rollers and even Stumble/Smash don't have clans + gifting. Rare indie asset, currently inert.
4. ⭐ **Massive evergreen content** — 5,000 climb + 800 track levels + 9 modes. Far more longevity runway than any roller in the set.
5. ⭐ **Fair by conviction, from day one** — no loot boxes, no P2W, no forced ads. **Brawl Stars had to *retrofit* fairness to 8.8× its revenue; Roll Along is already there.** That's a marketable origin story, not just a policy.
6. ⭐ **Solo agility + community-driven potential** — can poll players, ship weekly, build loyalty (Subway's superpower, native to one developer).

---

## The highest-leverage gaps (ranked)

1. **Virality surface — capture & share.** Gates *all* organic growth; nothing else matters if no one sees the game. _(axis 7)_
2. **Public cosmetics in competition.** Mac's directive — opponents render their own ball + trail. Unlocks the *entire* cosmetics-led economy, gives clips a reason to be shared, and gives social its stakes. _(axes 4/7/8)_
3. **LiveOps cadence — events/seasons + remote config.** The retention engine room and the home for the pass + event skins. _(axis 9)_
4. **The "Roll Pass" — a cheap, fair seasonal pass.** The monetization headline; Brawl's proven model; sits on #3. _(axis 6)_
5. **Social stakes.** Turn the built backend into *competition that matters* — ranked, clan goals, friend challenges. _(axis 8)_
6. **Tomorrow-hooks — weekly missions + a monthly season.** Builds the missing D7/D30 ladder. _(axis 3)_
7. **Onboarding sells the hook + meta, not just the climb.** _(axis 2)_
8. **Celebrations / emotes** — a cheap, highly visible, clip-able cosmetic category (bonus borrow, confirmed by all three competitive games). _(axes 4/7)_

---

## The keystone insight (why these gaps are really *one* opportunity)

The top gaps are **interlocking, not independent** — and they share a single keystone:

> **A public competitive surface where one player's identity (cosmetics) and skill are seen by
> others.**

Build that one surface and the rest *gain their value for free*:

```
        ┌─────────────────────────────────────────────┐
        │  KEYSTONE: public cosmetics in competition   │  ← Mac's "show opponent ball+trail"
        └───────────────┬─────────────────────────────-┘
        ┌───────────────┼───────────────┬───────────────┐
        ▼               ▼               ▼               ▼
  cosmetics gain    clips become     social gains    the pass + event
  a reason to       worth sharing    real stakes     skins have a
  exist/desire      (virality)       (leaderboards,  stage to be shown
  (monetization)                     clans, rivals)  off on
```

Without it: cosmetics are private (no desire), clips are solo (no virality), social is inert (no
stakes), and a pass rewards looks no one sees. **With it: every other system switches on.** This
is why the roadmap (Prompt 6) is sequenced around the keystone first, the cadence/pass second,
and polish third — and why the work is mostly *"wire up what you already have,"* not "build a new
game."

### The one rebalance to flag
Roll Along currently earns from **lives/friction** (selling relief from a gate). The brief wants
it to earn from **cosmetics/desire** (selling self-expression). The roadmap should **shift weight
from the lives economy toward the cosmetic + pass economy** — which *also* improves goodwill and
aligns with the fairness positioning. (We are **not** touching the daily-reward nerf — Mac's call.)

---

_Next: Prompt 5 turns these eight gaps + six edges into a scored opportunity backlog
(impact × effort), each tied to the competitor that proves it._
