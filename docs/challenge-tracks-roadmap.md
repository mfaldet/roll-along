# Challenge Tracks — Design Roadmap

100-level themed side quests, each ending with a free cosmetic bundle reward.

---

## Overview

A **Challenge Track** is a self-contained 100-level journey built around a single visual theme. It plays exactly like the main climb (tilt to roll, reach the goal, avoid holes, earn 1–3 stars) but on its own numbered 1–100 ladder that never interferes with the player's main-climb level.

Completing level 100 on any track delivers the track's paired cosmetic bundle to the player's inventory **for free** — earned, not purchased. This is Roll Along's primary skill-reward loop.

### Why 100 levels

* Long enough to feel epic; short enough to be achievable in a few weeks of casual play.
* 100 is a round number players can celebrate ("I finished it").
* Each tier of 10 (1–10, 11–20, …) provides a natural checkpoint rhythm.

### What makes each track distinct

Beyond the visual theme, each track has:

1. **A curated difficulty arc** (see below) that is tuned specifically to its theme.
2. **Theme-specific obstacle vocabulary** — e.g. Frosty Peaks uses narrow ice-bridge corridors; Neon Arcade uses grid-locked pixel-block layouts.
3. **A unique reward bundle** — cosmetics that match the track's aesthetic, delivered only on completion (not available in the shop for that track's exclusive items).

---

## Difficulty Arc

Every track uses the same 6-phase progression curve. Unlike the main climb's last-digit tier rule, Challenge Tracks use **level range** to set the tier:

| Phase | Levels | Tier | Description |
|---|---|---|---|
| Tutorial | 1–15 | Easy | Open arenas, generous timing, 1–3 holes. Teaches the theme's visual language. |
| Apprentice | 16–35 | Easy → Hard | Introduce 2 theme-specific obstacle types. Star thresholds begin to tighten. |
| Journeyman | 36–60 | Hard | Theme mechanic in full effect. Complex multi-obstacle arrangements. |
| Expert | 61–80 | Very Hard | Dense hole fields, narrow corridors, tight gold-star windows. |
| Master | 81–95 | Very Hard | No redundant space anywhere. Every layout is a precision puzzle. |
| Pinnacle | 96–100 | Extreme¹ | 5 showcase levels. Equivalent difficulty to main-climb ~500+. |

> ¹ Pinnacle levels use Very Hard tier time multipliers but handcrafted layouts at maximum hole density — the engine calls them Very Hard, but they play as the hardest content in the game.

**Implementation note (S18):** The challenge track level generator reads `ChallengeTrackMode.difficultyTier(for:)` instead of `DifficultyTier.tier(for:)`. The level-range table above maps directly to that method.

---

## The 8 Tracks

### Track 1 — Frosty Peaks
**ID:** `frozen-peaks`  
**Sprint:** S19  
**Reward bundle:** `winter` *(existing)*

> "A hundred icy corridors. Every degree colder."

| Category | Item |
|---|---|
| Ball | Snowglobe |
| Goal | Crystal |
| Trail | Ice |
| Floor | Twilight |
| Pit | Twilight |

**Theme vocabulary:** Narrow ice-bridge corridors (single-tile-wide paths over hole fields), symmetric mirrored layouts that punish over-correction, avalanche-style "falling boulder" hole patterns in Pinnacle levels.

**Arc notes:** Tutorial levels use wide open arenas with a single central ice pit. Apprentice introduces the bridge mechanic. By Expert the player is navigating multi-bridge mazes.

---

### Track 2 — Deep Cosmos
**ID:** `deep-cosmos`  
**Sprint:** S19  
**Reward bundle:** `cosmos` *(existing)*

> "Roll through the asteroid belt. The void is patient."

| Category | Item |
|---|---|
| Ball | Nebula |
| Goal | Galaxy |
| Trail | Stardust |
| Floor | Midnight |
| Pit | Midnight |

**Theme vocabulary:** Circular hole clusters (asteroid field rings), expanding-then-contracting ring obstacles, long diagonal runs across near-empty void floors.

**Arc notes:** Tutorial is spacious — the void feels empty and calming. By Journeyman the asteroid rings are dense. Pinnacle levels place the goal at the center of a nested ring gauntlet.

---

### Track 3 — Inferno Run
**ID:** `inferno-run`  
**Sprint:** S19  
**Reward bundle:** `lava-flow` *(added S17)*

> "The floor is lava. Every floor. All one hundred."

| Category | Item |
|---|---|
| Ball | Lava |
| Goal | Eclipse |
| Trail | Fire |
| Floor | Sunset |
| Pit | Evil (animated fire pit) |

**Theme vocabulary:** Maximum hole density from level 36 onward, narrow stepping-stone paths through lava fields, converging "lava river" corridors that funnel the ball into single-tile lanes.

**Arc notes:** Tutorial uses wide fireproof platforms. Apprentice shrinks them. Expert and beyond is almost entirely holes with a path barely wide enough for the ball.

---

### Track 4 — Neon Arcade
**ID:** `neon-arcade`  
**Sprint:** S19  
**Reward bundle:** `neon` *(existing)*

> "Insert coin. Roll perfect. High score awaits."

| Category | Item |
|---|---|
| Ball | Neon |
| Goal | Neon |
| Trail | Bubblegum |
| Floor | Disco |
| Pit | Midnight |

**Theme vocabulary:** Grid-locked pixel-block obstacle arrangements (holes aligned to a 4×4 grid), speed-run emphasis (gold times are tighter than any other track), score-display style checkpoints every 10 levels.

**Arc notes:** Tutorial levels have classic arcade maze shapes. Journeyman introduces the tight-grid patterns. Pinnacle levels are pure execution — no exploration, just flawless routing.

---

### Track 5 — Haunted Manor
**ID:** `haunted-manor`  
**Sprint:** S19  
**Reward bundle:** `haunted` *(existing)*

> "The fog never lifts. The graveyard is the goal."

| Category | Item |
|---|---|
| Ball | Ghost |
| Goal | Obsidian |
| Trail | Smoke |
| Floor | Fog |
| Pit | Graveyard (animated) |

**Theme vocabulary:** Unexpected hole placement ("jump scare" pits where the player least expects them), winding room-to-room corridor layouts, dead-end false paths in Expert levels.

**Arc notes:** Tutorial levels are open but eerie. Apprentice introduces the dead-end corridors. Pinnacle levels use labyrinthine layouts where the correct path is never obvious.

---

### Track 6 — Ancient Temple
**ID:** `ancient-temple`  
**Sprint:** S20  
**Reward bundle:** `ancient-temple` *(new bundle, S20 — all existing cosmetics)*

> "Carved corridors. Gilded traps. The relic waits."

| Category | Item |
|---|---|
| Ball | Dune |
| Goal | Eclipse |
| Trail | Gilded |
| Floor | Desert |
| Pit | Canyon |
| Music | Orchestral |

**Theme vocabulary:** Symmetric temple-room layouts (mirror-image left/right), trap-door hole patterns hidden in decorative floor symmetry, narrow corridor-plus-pit sequences that require committing to a path.

**Arc notes:** Tutorial levels use wide archaeological dig-site arenas. Journeyman introduces the symmetric trap patterns. Pinnacle levels are exact mirror labyrinths where mis-reading the symmetry means falling.

---

### Track 7 — Abyssal Depths
**ID:** `abyssal-depths`  
**Sprint:** S21  
**Reward bundle:** `abyssal-depths` *(new bundle + new ball, S21)*

> "Light doesn't reach here. Roll by feel."

**Planned bundle contents:**

| Category | Item | Status |
|---|---|---|
| Ball | Trench | **NEW** — deep navy sphere, bioluminescent teal spots animation |
| Goal | Comet | Existing |
| Trail | Ice | Existing |
| Floor | Blueprint | Existing |
| Pit | Space | Existing |
| Music | Dreamscape | Existing |

**New cosmetic needed (S21):**
- `BallSkin.trench` — dark navy sphere with 6–8 bioluminescent teal/green dot clusters that pulse slowly (TimelineView + Canvas, similar pattern to lava blobs but upward-drifting soft glows rather than dark blobs). Colors: `[navy highlight → deep navy → abyssal navy → near-black]`.

**Theme vocabulary:** Downward-descent narrative (levels 1–15 feel surface-lit; 96–100 are near-pitch-black floor tones), tight pressure-trench corridors, hole clusters that ring the path like walls of the deep.

---

### Track 8 — Golden Gauntlet *(Prestige)*
**ID:** `golden-gauntlet`  
**Sprint:** S22  
**Reward bundle:** `champion` *(new bundle + new exclusive ball, S22)*

> "No tutorial. No mercy. A hundred flawless rooms."

**Planned bundle contents:**

| Category | Item | Status |
|---|---|---|
| Ball | Trophy | **NEW, pack-exclusive** — polished deep gold with obsidian swirl + mirror specular |
| Goal | Quasar | Existing |
| Trail | Gold | Existing |
| Floor | Mirage | Existing |
| Pit | Mirage | Existing |
| Music | Orchestral | Existing |

**New cosmetic needed (S22):**
- `BallSkin.trophy` — polished gold sphere with an obsidian counter-swirl (like marble glass but metallic), large mirror specular highlight, `isBundleExclusive = true` (only obtainable by completing Golden Gauntlet, never coin-purchasable or sold). Canvas renderer: gold radial gradient + slow rotating obsidian swirl band + bright specular crescent.

**Prestige design:** Golden Gauntlet skips the Tutorial and Apprentice phases. **Every level is Expert or Pinnacle tier.** There is no warm-up. This track is only appropriate for players who have completed at least 2 other tracks. Placement in the UI: unlocked only after earning 3 other track completion badges.

---

## Sprint Plan

| Sprint | Deliverable | Status |
|---|---|---|
| **S18** | Challenge Track Engine | ✅ Complete |
| **S19** | First 5 Tracks (existing bundles) | ✅ Complete |
| **S20** | Ancient Temple Track + Bundle | ✅ Complete |
| **S21** | Abyssal Depths Track + Trench ball | ✅ Complete |
| **S22** | Golden Gauntlet + Trophy ball (exclusive) | ✅ Complete |

### S18 Detail — Challenge Track Engine

*Prerequisite for all other challenge track sprints.*

- `ChallengeTrackView` — main UI: level grid, progress bar, reward preview card, "Play level N" button
- `ChallengeTrackSelectView` — list of all tracks, shows locked/unlocked/completed state
- `HomeRoute.challengeTrack(String)` + `Navigator.goToTrack(_:)` + nav wiring in HomeView
- `ChallengeTrackMode.difficultyTier(for level: Int) -> DifficultyTier` — level-range tier mapping (replaces last-digit rule for track levels)
- `LevelLayout.trackLayout(for level: Int, trackID: String) -> LevelLayout` — per-track level generator (uses theme-specific obstacle vocabulary + the 6-phase difficulty curve)
- Completion flow: clear level 100 → `GameState.advanceTrackProgress(trackID:to:)` → `deliverTrackReward(for:)` → bundle delivery toast (reuses `lastDelivery` from StoreKitManager pattern)
- Analytics: `track_level_cleared`, `track_completed`, `track_bundle_delivered`
- Unlock gate for Golden Gauntlet: `completedTracks.count >= 3`

### S19 Detail — First 5 Tracks

Each of the 5 tracks needs:
- 15 hand-crafted Pinnacle levels (96–100 plus 10 selected Expert landmarks)
- `LevelLayout.trackLayout` generator parameterised with per-track `ObstacleVocabulary` struct (defines hole cluster shapes, path width range, symmetry rules)
- Track entry cards in `ChallengeTrackSelectView` (thumbnail, tagline, reward bundle preview, progress ring)

### S20 Detail — Ancient Temple

- `ancient-temple` bundle already registered in `Cosmetics.swift` (added this session)
- Needs: 15 hand-crafted Pinnacle levels + ObstacleVocabulary (symmetric temple rooms, gilded-trap patterns)
- No new ball skin — Dune ball is already live

### S21 Detail — Abyssal Depths

New code:
- `BallSkin.trench` case + color arm (navy palette)
- `BallSkinView.trenchCanvas` — TimelineView with dark navy radial gradient + 6 bioluminescent dot clusters that pulse (opacity: `0.5 + 0.5 * sin(t * speed + phase)`) + edge vignette
- `abyssal-depths` bundle entry in `Cosmetics.swift`
- `ChallengeTrackMode.rewardBundleID` already maps `"abyssal-depths"` → `"abyssal-depths"` ✓

### S22 Detail — Golden Gauntlet

New code:
- `BallSkin.trophy` case + color arm (deep gold + obsidian) + `isBundleExclusive = true`
- `BallSkinView.trophyCanvas` — gold radial gradient + slow-rotating obsidian swirl band (sin-based angular drift) + large mirror specular crescent
- `champion` bundle entry in `Cosmetics.swift` (trophy is pack-exclusive, never in shop grid)
- Unlock gate wired in `ChallengeTrackSelectView`: golden padlock UI until `completedTracks.count >= 3`
- `ChallengeTrackMode.rewardBundleID` already maps `"golden-gauntlet"` → `"champion"` ✓
- All 100 levels are handcrafted (no generated filler) — this is the prestige content statement

---

## Data Contract (already implemented)

The following fields were added to `GameState` in the same commit as this document:

```swift
// GameState.swift — Challenge Track persistence
var trackProgress:   [String: Int]    // [trackID: highestLevelCleared]
var completedTracks: Set<String>      // trackIDs where level 100 was beaten

func advanceTrackProgress(trackID: String, to level: Int)  // call after each level clear
func deliverTrackReward(for trackID: String)               // called automatically at level 100
```

The `ChallengeTrackMode.rewardBundleID(for:)` static method provides the trackID → bundleID mapping. All 8 mappings are registered now; the `ancient-temple` bundle is live; `abyssal-depths` and `champion` return valid IDs that will resolve once their bundles are added in S21/S22.

---

## Bundle Summary

| Track | Bundle ID | Bundle Status |
|---|---|---|
| Frosty Peaks | `winter` | ✅ Existing |
| Deep Cosmos | `cosmos` | ✅ Existing |
| Inferno Run | `lava-flow` | ✅ Added S17 |
| Neon Arcade | `neon` | ✅ Existing |
| Haunted Manor | `haunted` | ✅ Existing |
| Ancient Temple | `ancient-temple` | ✅ Added this session (S20 stub) |
| Abyssal Depths | `abyssal-depths` | 🔲 S21 (needs Trench ball) |
| Golden Gauntlet | `champion` | 🔲 S22 (needs Trophy ball, exclusive) |
