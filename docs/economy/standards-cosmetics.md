# Cosmetic quality standard — per-tier visual bar + rung policy

**Status: DRAFT for Mac's review.** This is the Workstream B standard from
[06-sprint-plan.md](06-sprint-plan.md) — the written answer to "what does a
1,500-coin item have to *look like*?" Every bar below is grounded in the
actual renderers (BallSkinView.swift, BallGameView.swift, Cosmetics.swift,
BallSkin.swift), not aspiration: the tiers already encode implicit rules in
their switch comments; this doc makes them explicit, fills the gaps, and
hands the audit fleet a rubric. **Nothing re-tiers with this doc** — the
census graders propose moves, Mac approves them.

## 1. The promise being defended

The reprice ([08-reprice.md](08-reprice.md)) set time-to-afford targets per
tier. The visual bar is the other half of that contract: a player who saves
60 minutes for a Legendary must get something a 30-minute Standard player
visibly cannot have.

| Tier (label) | Price | Minutes @ 25/min | The promise |
|---|---:|---:|---|
| starter (Free) | 0 | — | complete, respectable defaults — never "sad versions" |
| standard (Standard) | 750 | 30 | a real choice: new palette, stock rendering |
| rare (Rare) | 1,000 | 40 | a distinctive twist: texture or feature, still static |
| premium (Epic) | 1,250 | 50 | custom art: multi-hue and/or animated with restraint |
| exclusive (Legendary) | 1,500 | 60 | bespoke: animated, layered, one-of-a-kind rendering |

Two invariants that already hold and must keep holding:

1. **Tier is set by rendering reality, not theme.** A pumpkin recolor is not
   Legendary because Halloween; the Snowglobe is Legendary because it has an
   animated TimelineView Canvas (BallSkinView.swift:36-39).
2. **Rendering class is auditable from source.** Every category has an
   exhaustive switch; every item's renderer is findable at a file:line. No
   bar below depends on taste alone.

## 2. Rendering classes (the shared vocabulary)

The graders classify every item's renderer first, then map class → minimum
tier using the per-category tables in §3. Classes, cheapest to richest:

| Class | Definition | Example evidence |
|---|---|---|
| **R0 — recolor** | stock renderer, new palette; one color family | plainMarble balls (BallSkinView.swift:207-208), Boundary base colors (Cosmetics.swift:1322-1343) |
| **R1 — custom gradient** | stock renderer, multi-hue palette that reads as 2+ colors | pastel/neon/dune 4-stop gradients (BallSkin.swift:6, Cosmetics.swift:232-238) |
| **R2 — static bespoke** | its own Canvas/view; drawn art, no animation clock | basketball seams, paper folds, doodleGoal (BallGameView.swift:2552) |
| **R3 — animated** | TimelineView/time-parameter drives the art; single effect | goal particle portals (rainbowHole with holeStyle, BallGameView.swift:3139), Floor `hasAnimatedOverlay` (Cosmetics.swift:1106-1111) |
| **R4 — bespoke animated, multi-layer** | its own renderer *and* an animation clock *and* layered effects (MeshGradient + Canvas overlays, particle lifecycles, additive glow) | Aurora ball's dual MeshGradient (BallSkinView.swift:1342-1398), lavaLamp (2298-2329), tractorBeamGoal (BallGameView.swift:2351), trailAurora (Cosmetics.swift:3147) |

The Epic/Legendary boundary in every visual category is the same test:
**does it have both a bespoke identity and richness beyond one effect?**
R3 alone is Epic territory; R4 is Legendary. A flat 4-stop gradient (R1) is
**never** Legendary, no matter the theme.

## 3. The visual bar, per category per tier

### Balls (BallSkinView.swift exhaustive switch; palettes in BallSkin.swift)

The identity item — deepest catalogue (45 legendaries, ~48% of catalogue
value per [02-spending.md](02-spending.md)) and the strictest bars.

| Tier | Bar | Precedent |
|---|---|---|
| Standard | R0 — mono-shaded marble: one color family, light→dark stops, stock plain/metal/gem marble renderer. Reads as "a color". | blue…ruby (Cosmetics.swift:229-231) |
| Rare *(new rung — see §4)* | R1 minimum: two-hue gradient, **or** R0 + one distinctive static accent over a stock renderer. Above a recolor, below a bespoke Canvas. | none yet — the rung is currently empty |
| Epic | R1 **plus** ≥1 distinctive feature, or R2: bespoke static Canvas with real drawn art. Sports seam-art is the calibration point. | sports balls = Epic (Cosmetics.swift:234); geode, cathedral |
| Legendary | R3/R4 only: animated Canvas (TimelineView), MeshGradient, or multi-layer static bespoke with unique silhouette/behavior (Saturn's unclipped rings, Pluto's half radius). **Never a flat gradient.** | planets = Legendary (Cosmetics.swift:256-257); aurora, snowglobe, disco, hologram |

Known tension for the graders: galaxy/nebula/opal are commented
"multi-colour gradient (kept here for parity)" at Legendary
(BallSkin.swift:35-37) but render via bespoke canvases
(BallSkinView.swift:197-199) — grade the *renderer*, not the old comment.

### Goals (three render paths + bespoke views, BallGameView.swift:611-651)

| Tier | Bar | Precedent |
|---|---|---|
| Standard | fully static: banded targets or static ring-portals — no particles, no animation clock (the switch comment's own rule, Cosmetics.swift:810-824). | frost…slate bands; vortex/wormhole ring-portals |
| Rare *(new rung)* | static art + one subtle motion accent (a breathing scale, a slow rotation) **or** a distinct drawn silhouette beyond concentric rings. | none yet |
| Epic | R3: animated particle portal, tight/mono palette — "animated but visually focused" (Cosmetics.swift:813-814). | galaxy, crystal, flame, ripple, obsidian |
| Legendary | R3 full-spectrum palette, **or** R4 bespoke one-off view with its own scene logic. Every bespoke goal already meets this. | holeInOne, tractorBeam, inferno, halo, doodle, soccerNet, aurora (BallGameView.swift:2171-2704); rainbow/quasar full-spectrum |

Note doodle is R2 (static pencil bullseye) sitting at Legendary — a
deliberate "bespoke one-off = Legendary" call. The rubric keeps that rule:
**a fully bespoke goal view qualifies for Legendary even if static**,
because the render surface (a hole in the floor) rewards identity over
motion. Graders flag it only if Mac rejects this clause.

### Trails (drawRichTrail dispatch, Cosmetics.swift:3084-3107)

The only category already using Rare — its ladder is the template.

| Tier | Bar | Precedent |
|---|---|---|
| Standard | solid mono color through the shared `trailTapered` renderer; no glow, no bespoke function. | ink, ember, sky, forest, bubblegum (Cosmetics.swift:903-904) |
| Rare | distinctive texture or glow, still palette-static: its own `trail*` function **or** the tapered renderer's glow path. | snake scales, graphite pencil, rose petals, raybeam/gilded glow (Cosmetics.swift:905-906) |
| Epic *(new rung)* | multi-hue motion — per-segment hue cycling or a two-layer body+core treatment — without a full element lifecycle. | none yet; `.rainbow` is the closest existing fit (grading call, §5) |
| Legendary | R4: real-time element lifecycle — marks laid in the world that age on their own clock via `trailAge` (fire→smoke, ice trench, stardust twinkle, aurora ribbon with additive glow + hue flow) or a mechanic (snake growth is Rare-textured; coin-reactive behavior would be Legendary). | fire, ice, cometTrail, stardust, air, aurora (Cosmetics.swift:907-909) |

### Floors & Pits (base color + optional overlay; BallGameView draws overlays)

Today these are binary: flat `color` = Standard, `hasAnimatedOverlay` =
Legendary (Floor: Cosmetics.swift:1034-1048, 1106-1111; Pit: 1194-1207,
1249-1254). Nothing exists between. The bars open the middle rungs without
requiring them to be filled (§4):

| Tier | Bar | Precedent |
|---|---|---|
| Standard | flat base color. Passive mechanics that came with the theme (paperTrailEnabled floors, Cosmetics.swift:1096-1101) do **not** raise tier. | the 21 standard floors / 22 standard pits |
| Rare *(new rung)* | static texture drawn once over the base — pattern, grain, print — no animation clock. | none yet (would need a static-overlay render path) |
| Epic *(new rung)* | animated overlay, one effect layer, tight palette — e.g. a single drifting element. | none yet |
| Legendary | animated overlay with multiple elements or a full-scene treatment: aurora shimmer, disco color-cycling squares, moon craters + regolith, evil flames, pond ripples + lily pad. | every `hasAnimatedOverlay == true` floor/pit |

Grading note: gridCity and brass are commented "textured overlays"
(Cosmetics.swift:989-991) but live in `hasAnimatedOverlay` at Legendary —
graders verify the actual overlay draws animate; if one is effectively a
static texture it is evidence for the Rare/Epic rungs, not a silent pass.

### Boundaries (flat colors at every tier — the honest outlier)

Reality check: **every boundary at every tier is a flat hue** plus two
derived brightness shades (`deepColor`/`edgeColor` via `boundaryShaded`,
Cosmetics.swift:1341-1355), and the render sites consume only those colors
(BallGameView.swift:474-476). Today's ladder is hue desirability, not
rendering class. The bar going forward:

| Tier | Bar | Precedent |
|---|---|---|
| Standard | muted solid hue. | slate, ember, mint, sky, orchid, sand |
| Rare | vivid, saturated, or metallic-reading hue — the "wow color". | neon, gold, ice (Cosmetics.swift:1314-1315) |
| Epic *(new rung)* | gradient or edge-glow treatment along the wall run — needs renderer work (a shader ramp or lit-edge pass). | none yet |
| Legendary | texture or animation the wall visibly *does*: circuit traces that pulse, candy stripes, obsidian sheen. | **none currently meet this** |

**Flag, not a stealth re-tier**: obsidian/candy/circuit sit at Legendary
(1,500 coins) while rendering identically to a 750 Standard. Options for
Mac's ruling: (a) fund the Legendary boundary renderer (circuit pulse etc.)
and keep the tier, or (b) re-tier them to Rare until the art exists. The
audit fleet files these as OVER-TIER with this paragraph as context.

### Music (identifiers today; .m4a assets land in V1.1 — Cosmetics.swift:1358-1431)

Bars are compositional, enforceable only once audio ships; until then the
graders grade the spec, and every commissioned track cites its target tier.

| Tier | Bar |
|---|---|
| Standard | a competent loop: ≥60s before repeat, genre-generic instrumentation, consistent energy. The 8 genre names (piano…synthwave) are this. |
| Rare *(new rung)* | ≥90s loop with one distinguishing element — a signature instrument, a hook motif — still a single-section loop. |
| Epic | ≥2 min or a layered arrangement with real development (distinct A/B sections, dynamic build); identity you can name blind. lofi…dreamscape target this. |
| Legendary | a bespoke signature piece: ≥3 min, or evolving/layered structure that never reads as a loop; a unique motif owned by the track (aurora's drifting pads should be recognizably *the Aurora sound*). |

Loudness/mix consistency across tiers is a QA gate, not a tier
discriminator — a Standard track is quieter in ambition, never in mastering
quality.

## 4. Rung policy — one rule everywhere

Current usage (from the seven `tier` switches):

| Category | Free | Standard 750 | Rare 1,000 | Epic 1,250 | Legendary 1,500 |
|---|:-:|:-:|:-:|:-:|:-:|
| Balls | ✓ | ✓ | — | ✓ | ✓ |
| Goals | ✓ | ✓ | — | ✓ | ✓ |
| Trails | ✓ | ✓ | ✓ | — | ✓ |
| Floors | ✓ | ✓ | — | — | ✓ |
| Pits | ✓ | ✓ | — | — | ✓ |
| Boundaries | ✓ | ✓ | ✓ | — | ✓ |
| Music | ✓ | ✓ | — | ✓ | ✓ |

Five different ladders — the [02-spending.md](02-spending.md) equity gap: a
trail chaser sees a 1,000-coin mid-rung a ball chaser never does, and a
floor chaser jumps straight from 750 to 1,500.

**Proposed policy: every category may use every rung.** No structural
skips. An *empty* rung is fine — it is backlog, not policy — but no
category's `tier` switch may be written so a rung is unreachable by rule.

- **Why not "every category must fill every rung"**: floors/pits have no
  static-texture render path yet and boundaries have no texture path at
  all; forcing items into those rungs today means shipping art that
  violates §3. Open-but-empty is honest; filled-with-misfits is not.
- **Deliberate documented exceptions** (the only sanctioned skips):
  - *Floors/Pits* stay effectively two-pole (750/1,500) until a
    static-overlay render path exists. Rare/Epic are open and awaiting
    renderer work.
  - *Boundaries* keep Rare as their mid-rung; Epic/Legendary await the
    gradient/animated wall treatments (§3) — resolved by Mac's
    obsidian/candy/circuit ruling.
- **What this unlocks**: a Rare rung for balls/goals/music gives bundle
  composition a 1,000-coin step (helps the fullPrice-measures-item-count
  problem flagged in [08-reprice.md](08-reprice.md)) and smooths the
  tutorial-gift and shop-rotation pools, which already special-case
  "Standard vs better" (Cosmetics.swift:1592-1597).

New-item rule (add to the cosmetic-wiring checklist): every PR adding a
cosmetic states the target tier and quotes the §3 checklist lines it meets.
An item that cannot quote its lines does not merge at that tier.

## 5. Grading rubric — what the audit agents apply

One pass per category (7 graders), each item graded independently, then a
2-agent adversarial re-grade of a sample, per the sprint plan.

**Procedure per item:**

1. **Locate the renderer.** Follow the exhaustive switch
   (BallSkinView.swift body; BallGameView.swift:623-651 for goals;
   drawRichTrail Cosmetics.swift:3089-3106 for trails;
   `hasAnimatedOverlay` + overlay draws for floors/pits; `color` triplet
   for boundaries). Cite file:line.
2. **Classify R0–R4** (§2). The animation test is mechanical: is there a
   TimelineView, a time parameter, or a `trailAge`-style clock in the draw
   path? Comments lie (galaxy, §3-balls); code doesn't.
3. **Map class → minimum tier** with the category table in §3, including
   the category-specific clauses (bespoke goal views auto-qualify
   Legendary; paper-trail mechanics don't raise floors; boundary hues cap
   at Rare until texture renderers exist).
4. **Verdict**: `MATCH`, `UNDER-TIER` (art exceeds price — a candidate to
   promote or a bar to tighten), or `OVER-TIER` (price exceeds art — the
   player-trust problem; these go first in the worklist).
5. **Evidence**: one row — item, category, current tier, rendering class,
   verdict, file:line, one-sentence justification.

**Tie-breakers, in order:**

- Animation clock present → at least Epic (balls/goals/floors/pits).
- Bespoke one-off renderer + animation + layered effects (R4) → Legendary.
- Palette breadth splits Epic vs Legendary for goals (tight vs
  full-spectrum) and trails (hue-cycle vs element lifecycle).
- Seasonal/bundle-exclusive/IAP-secret status changes *availability*,
  never the visual grade — Diamond, Money cosmetics, and
  seasonal-exclusives are graded on their renderers like everything else.
- Reduce Motion: animated items must freeze gracefully
  (`accessibilityReduceMotion` is already threaded through BallSkinView) —
  a pass/fail QA checkbox on every Epic+ item, not a tier input.

**Per-tier checklists (the box an item must tick, cumulative upward):**

- **Standard** ☐ renders correctly at all surface sizes ☐ stock render
  path ☐ single color family (or flat base for surfaces) ☐ readable
  against both light and dark floors (balls/trails).
- **Rare** ☐ everything above ☐ a nameable distinguishing trait (texture,
  glow, vivid hue, silhouette) a player could describe without naming the
  color.
- **Epic** ☐ everything above ☐ multi-hue or animated (category §3 rule)
  ☐ distinct at gameplay scale, not just in the shop preview.
- **Legendary** ☐ everything above ☐ bespoke renderer (own case, own
  function/view) ☐ animated or layered per §3 ☐ not a flat gradient
  ☐ recognizable in a screenshot with the HUD cropped out — the "would a
  stranger ask what that is?" test.

**What the audit does not do:** no price changes, no code edits, no
re-tiering in place. Output is the misfit worklist ([06-sprint-plan.md](06-sprint-plan.md)
acceptance: ≤10% of catalogue or re-tiering PRs filed), each row carrying
its evidence line for Mac's approval.

## 6. Open rulings for Mac

1. **Adopt the all-rungs policy** (§4) with the two documented floor/pit +
   boundary exceptions?
2. **Boundary Legendary trio** (obsidian/candy/circuit): fund the texture
   renderer, or re-tier to Rare until it exists?
3. **Bespoke-static goals at Legendary** (the doodle clause, §3): keep
   "bespoke one-off view auto-qualifies", or require animation everywhere?
4. **Trail Epic rung**: open it and consider `.rainbow` (hue-cycle, no
   lifecycle) as its anchor, or leave rainbow Legendary as the historical
   flagship?
5. **Music bars** (§3): confirm the composition targets now so V1.1 track
   commissions can cite them, or defer until the first .m4a lands?
