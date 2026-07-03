# Cosmetics catalogue audit — July 2026 misfit worklist

**Status: WORKLIST for Mac's approval — PARTIALLY RESOLVED.** Mac's ruling
1(c) (2026-07-02) approved promoting the UNDER-priced items UP; those 11
rows are marked **RESOLVED** below (re-tiered on branch
`claude/retier-underpriced`): balls galaxy/nebula/lavaLamp → Legendary,
trails ink/roseTrail → Legendary and ember → Rare, floors
notebook/graph/parchment/sketch/origami → Rare (opening the floors Rare
rung). Bundle knock-ons: diamond → Rare; bloom, backtoschool-2026,
lava-lamp, valentines-2027, muertos-2026 → Legendary; the permanent
Standard gift pool now holds exactly 4 (nature, citrus, sketchbook,
midas) — the floor of the 4–8 band. Everything else (OVER-TIER /
fund-program items, bundle copy flags, open rulings) is still pending.

This is the output of the Workstream B census from
[06-sprint-plan.md](06-sprint-plan.md): seven per-category graders applied
the rubric in [standards-cosmetics.md](standards-cosmetics.md) (§5) to every
paid cosmetic, plus a bundle-composition pass over all 66 bundles, plus a
2-agent adversarial verification pass over a 21-item sample. The standard
doc is the companion to this file — every verdict below cites its bars.

> ## ⚠ Re-tiering changes prices
>
> In this catalogue **tier IS price** — `tier.basePrice` is the only price
> an item has (Cosmetics.swift:143-151: Standard 750 / Rare 1,000 /
> Epic 1,250 / Legendary 1,500). Every "re-tier to X" below is therefore a
> **price change**, with knock-on effects on bundle `fullPrice`, bundle
> rarity gems (floors 5,500/6,500, Cosmetics.swift:1653-1654), sell-back
> values, and the tutorial-gift pool. **No change in this document ships
> without Mac's explicit approval**, per the standard's own rule
> ("the census graders propose moves, Mac approves them") and the
> confirm-decisions convention.

## 1. Summary counts

| Category | Graded | MATCH | Misfits | Misfit rate | Over sprint-plan 10% line? |
|---|---:|---:|---:|---:|:-:|
| Balls | 71 | 47 | 24 | 33% | **YES** |
| Goals | 32 | 30 | 2 | 6% | no |
| Trails | 19 | 14 | 5 | 26% | **YES** |
| Floors | 28 | 20 | 8 | 29% | **YES** |
| Pits | 28 | 27 | 1 | 4% | no |
| Boundaries | 12 | 9 | 3 | 25% | **YES** |
| Music | 17 | 14 | 3 | 18% | **YES** |
| **Items total** | **207** | **161** | **46** | **22%** | **YES** |
| Bundles (composition flags) | 66 | 46 | 20 | 30% | **YES** |
| **Grand total** | **273** | **207** | **66** | **24%** | — |

- Exemptions per the rubric: free starters (red ball, target goal, trail
  "none", classic floor/pit/boundary, none+ambient music) and IAP secrets
  (diamond, moneyBall/moneyRoll/moneyFull) were not graded.
- **Verification pass: 21 sampled misfits (≥3 per category), zero
  overturned.** Verified rows are marked ✓ below.
- Verdict convention follows the standard's §5: **OVER-TIER = price
  exceeds art** (the player-trust problem, listed first),
  **UNDER-TIER = art exceeds price** (promotion candidates).
- The catalogue-wide misfit rate blows past the sprint plan's ≤10%
  acceptance line, driven mostly by one pattern: **static seasonal balls
  parked at Legendary**. Per the acceptance criteria, re-tiering PRs are
  the expected follow-up — after Mac rules.

## 2. Balls — 24 misfits (47 clean of 71)

Census: 74 `BallSkin` cases; red (starter) + diamond + moneyBall (IAP
secrets) exempt; 71 graded.

### 2a. OVER-TIER: 19 static Legendaries (1,500 → graded Epic 1,250)

The §3-balls Legendary bar is R3/R4 (animation clock, MeshGradient, or
multi-layer static with unique silhouette/behavior). All 19 below are
static Canvas art (R2 at best) with no TimelineView/clock — the Epic bar.

| Item | Current | Graded | Evidence | Proposed action |
|---|---|---|---|---|
| ornament | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:3064): crimson shaded sphere + oversized specular + gold cap/stripe — no animation clock, thinnest art at Legendary, R2 at best | Re-tier to Epic |
| speckledEgg | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:3409): mono blue sphere + 16 static speckles + crescent — golfBall-dimple class, and golfBall is the Epic calibration | Re-tier to Epic |
| apple | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:4538, comment "Static."): red sphere + leaf + stem + specular — a recolor with two accents, no clock | Re-tier to Epic |
| heartstone | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:3156): fuchsia sphere + one gold Bezier heart + specular — single drawn motif, R2 | Re-tier to Epic |
| ghost ✓ | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:828-876): base gradient + 2 eye ellipses + mouth ellipse — simplest bespoke canvas in the file, no clock | Re-tier to Epic |
| beachBall | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:2844-2918): 6 flat wedges + seams + edge shading — construction identical in class to Epic soccer (soccerCanvas:642) | Re-tier to Epic |
| aquarium | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:699-743): 4-stop base + 5 fixed bubble circles + sheen — no clock, sports-class R2 | Re-tier to Epic |
| shamrock | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:3235): green sphere + white clover + gold stem — single static motif, R2 | Re-tier to Epic |
| confetti | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:3311): gold sphere + 18 static rotated confetti rects — one scattered-texture layer, no clock | Re-tier to Epic |
| storm | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:947-1004): base + 4 puff blobs + one 2-stroke lightning bolt — R2, no clock | Re-tier to Epic |
| candy | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:882-941): base gradient + 6-arm white pinwheel + cap — static peppermint, R2 | Re-tier to Epic |
| marble | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:750-822): base + six static cat's-eye blades + vignette + specular — R2, circle silhouette, no behavior clause | Re-tier to Epic |
| highRoller | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:2016-2073, header says "Static."): roulette wedges + gold rim + pip — flat geometric art, no clock | Re-tier to Epic |
| spectrum | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:4394, "Static."): six rainbow bands + sphere shade + specular — reads as a shaded rainbow gradient; §2: a flat gradient is never Legendary | Re-tier to Epic |
| harvest | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:4105, "Static."): amber gradient + a few leaf silhouettes + mottle patches — gradient-plus-accents, R2-lite | Re-tier to Epic |
| oktoberfest | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:4448, "Static."): blue/white lozenge tile pattern + gold accents + foam highlight — repeated-motif static, R2 | Re-tier to Epic, **or** hold for ruling #3 extension (rich static) |
| mardiGras | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:4309, "Static."): harlequin diamond lattice + bead glints + specular — rich but static R2, no silhouette/behavior | Re-tier to Epic, **or** hold for ruling #3 extension (rich static) |
| pumpkin | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:2926-3053): ribs/face/stem/inner-glow drawn art but no animation clock — R2; §3-balls reserves static Legendary for unique silhouette/behavior (Saturn/Pluto) | Re-tier to Epic, **or** hold for ruling #3 extension (rich static) |
| sugarSkull | Legendary (1,500) | Epic (1,250) | Static Canvas (BallSkinView.swift:3982, header "Static."): ornate calavera (petal eyes, stitched smile, floral forehead) — richest static in the file, still R2 with no clock | Re-tier to Epic, **or** hold for ruling #3 extension (rich static) |

Severity split within the 19: ornament / speckledEgg / apple / heartstone /
ghost / beachBall / aquarium are the clear player-trust problems (accents
over a shaded sphere at 1,500 coins). pumpkin / sugarSkull / mardiGras /
oktoberfest are genuinely rich drawn art, closest to the planets precedent —
**if Mac extends the goals-only doodle clause ("bespoke one-off static
auto-qualifies", ruling #3) to balls, those four flip to MATCH.**

### 2b. OVER-TIER: 2 stock-gradient Epics (1,250 → graded Rare 1,000)

| Item | Current | Graded | Evidence | Proposed action |
|---|---|---|---|---|
| pastel ✓ | Epic (1,250) | Rare (1,000) | No bespoke case: shared stock glossMarble renderer (BallSkinView.swift:205-206, 1590) over a 4-stop multi-pastel palette (BallSkin.swift:568-576) — R1 custom gradient, exactly the Rare bar | Re-tier to Rare — anchors the currently-empty balls Rare rung (§4) — or add a distinctive accent to hold Epic |
| dune | Epic (1,250) | Rare (1,000) | Same shared stock glossMarble path (BallSkinView.swift:205-206) with a 4-stop sand-to-violet palette (BallSkin.swift:616-625) — R1, no distinctive feature beyond the shared gloss | Re-tier to Rare (same rationale as pastel) |

### 2c. UNDER-TIER: 3 R4 renderers at Epic (1,250 → graded Legendary 1,500)

| Item | Current | Graded | Evidence | Proposed action |
|---|---|---|---|---|
| galaxy ✓ | Epic (1,250) | Legendary (1,500) | TimelineView Canvas (BallSkinView.swift:1706-1738): rotating two-arm spiral of 55 stars (ang = f*5.5 + t*0.25, :1719) + per-star twinkle (:1726) + plusLighter core glow — bespoke + clock + layered = R4 | **RESOLVED 2026-07-02** — re-tiered to Legendary per ruling 1(c) |
| nebula | Epic (1,250) | Legendary (1,500) | TimelineView Canvas (BallSkinView.swift:1740-1778): four drifting/breathing nebula blobs (:1758-1760) plus seven twinkling stars (:1769) under plusLighter — two animated effect systems = R4 | **RESOLVED 2026-07-02** — re-tiered to Legendary per ruling 1(c) |
| lavaLamp | Epic (1,250) | Legendary (1,500) | TimelineView + animated MeshGradient fluid (BallSkinView.swift:2320-2329) + rising, pulsing plusLighter wax blobs (:2346-2362) — the standards doc's own §2 R4 example (cited at 2298-2329) sitting at Epic | **RESOLVED 2026-07-02** — re-tiered to Legendary per ruling 1(c) |

### Balls — grader notes

- Planets earth/mars/mercury/jupiter/neptune/venus/uranus graded MATCH
  **solely** on the doc's explicit precedent column ("planets = Legendary");
  mechanically `planet()` (BallSkinView.swift:1501-1572) is the same static
  R2 class as the flagged seasonals — the precedent is doing all the work.
  Worth surfacing to Mac. Saturn (unclipped rings) and Pluto (half radius)
  pass on the named silhouette/behavior clause; snowglobe and ufo pass on
  TimelineView.
- All other Legendary balls confirmed animated (TimelineView): disco, lava,
  trench, trophy, aurora (dual MeshGradient), quicksilver (MeshGradient +
  roving specular), oracle, plasmaGlobe, magmaCore, hologram, clockwork,
  fireworks, lunarDragon (MeshGradient lacquer) — MATCH.
- Epic animated R3 singles graded MATCH per §2 "R3 alone is Epic
  territory": neon (pulse only), opal (one hue-cycling iridescence system),
  geode (static agate + 4 twinkle glints), cathedral (static rosette + one
  shimmer sweep). The R4 line was drawn at two-or-more animated effect
  systems / animated MeshGradient + Canvas layering.
- Stale-comment confirmations of the doc's known tension: BallSkin.swift:35-37
  calls galaxy/nebula/opal "multi-colour gradient" but all three render as
  animated bespoke canvases (BallSkinView.swift:1706/1740/1780) — graded on
  renderer. Likewise the doc's §2 R1 citation "pastel/neon/dune" is
  half-stale: neon has its own animated canvas (:1811) and grades MATCH;
  only pastel/dune remain R1. **Doc fix needed.**
- Standard tier is fully clean: all 13 (blue…ruby) are mono-family 4-stop
  palettes through stock plainMarble/metalMarble/gemMarble paths
  (BallSkinView.swift:207-212).
- Per rubric §5, exclusivity ignored: seasonal- and bundle-exclusive balls
  (incl. gauntlet-exclusive trophy, animated, MATCH) were graded on
  renderers like everything else.

## 3. Goals — 2 misfits (30 clean of 32)

Scope: 33 `GoalSkin` cases (Cosmetics.swift:289-335); `.target` exempt as
starter; no IAP-secret goals exist. 6.25% misfit rate — under the line.

| Item | Current | Graded | Evidence | Proposed action |
|---|---|---|---|---|
| neon ✓ | Legendary (1,500) | Epic (1,250) | OVER-TIER: neonGoal (BallGameView.swift:2937-2957) is four concentric flickering rings in exactly two fixed hues (magenta 1.0/0.15/0.7 + cyan 0.2/0.9/1.0) — a single-effect tight-palette R3, same class as Epic eclipse/ripple; not full-spectrum, and neon is NOT in the doc's Legendary precedent list | Re-tier to Epic, or widen to full-spectrum to hold Legendary |
| quasar ✓ | Legendary (1,500) | Epic (1,250) | OVER-TIER (borderline): quasarGoal (BallGameView.swift:3111-3137) draws two counter-rotating jets stroked with a fixed magenta-to-cyan gradient + static ring + core glow — a single-effect two-hue R3, same class as Epic comet; the standard's "rainbow/quasar full-spectrum" precedent does not match the code (holeStyle hueRange 0.30, Cosmetics.swift:486-491, equals Epic galaxy's 0.30) and §5 says grade the renderer | Re-tier to Epic **and fix the doc's precedent line**, or widen the palette to hold Legendary |

### Goals — grader notes

- **DOC DRIFT, affects ruling #3 wording:** the standard assumes Epic goals
  share rainbowHole via holeStyle, but BallGameView.swift:2704-2705 says
  "Each goal now has its own unique art instead of sharing rainbowHole" —
  all ten Epic goals have bespoke animated views (2708-3108) and
  rainbowHole (:3139) is used only by `.rainbow`. The Legendary
  "bespoke one-off view auto-qualifies" doodle clause is therefore
  non-discriminating as literally worded (every goal has its own view); it
  must be read as R4/full-scene-identity or all ten Epics would grade
  UNDER-TIER. The doc's own Epic precedent column confirms the R4 reading,
  which is what this grade applied. **Doc fix needed.**
- Letter-of-the-law note, graded MATCH: every Standard goal AND the free
  target run a TimelineView keep-alive breathe (±2.5-3%, e.g.
  bandedTargetGoal BallGameView.swift:2136-2139, ringPortalGoal:2248-2251),
  technically a clock the Standard bar forbids; treated as the stock render
  path since the doc names these exact items as Standard precedent. Suggest
  amending the Standard bar to "no animation beyond the shared keep-alive
  breathe" — note the Rare bar's "a breathing scale" example collides.
- Thinnest Epic/Legendary gap: flameGoal (Epic, 2774-2806) vs infernoGoal
  (Legendary, 2447-2492) are near-identical recipes; inferno keeps MATCH via
  its named bespoke-bundle precedent + richer 5-stop molten base + additive
  layer — re-check this pair if ruling #3 tightens.
- mosaic (Legendary) keeps MATCH only via the palette-breadth tie-breaker
  (full hue wheel, BallGameView.swift:2860) but is otherwise single-effect.
- holeInOne/doodle/soccerNet are fully static (no TimelineView; 2283, 2552,
  2590) and MATCH solely via the doodle clause — **all three flip to
  OVER-TIER if ruling #3 requires animation everywhere.**
- Dead-code smell for a follow-up: GoalSkin.holeStyle hue/saturation values
  (Cosmetics.swift:393-493) are consumed only by `.rainbow` now; the tuned
  values for 14 other goals are unused placeholders since the bespoke-view
  migration.
- Goals Rare rung (1,000) is open-but-empty, consistent with §4 policy.

## 4. Trails — 5 misfits (14 clean of 19)

Roster from the tier switch (Cosmetics.swift:899-909). Exempt: "none" (free
starter), moneyRoll (IAP secret; its trailMoney lifecycle renderer would
clear the Legendary bar anyway). Ordered per §5: OVER-TIER first.

| Item | Current | Graded | Evidence | Proposed action |
|---|---|---|---|---|
| smoke ✓ | Legendary (1,500) | Rare (Epic at best) | OVER-TIER: trailMist (Cosmetics.swift:3095 → 3563-3579) has no trailAge/times lifecycle — index-aged mono-grey puffs towed by the FIFO with only a slow t-driven lobe rotation — and smoke is absent from the doc's own Legendary precedent list (fire/ice/comet/stardust/air/aurora) | Re-tier (Rare per grade; Epic defensible) or add a real element lifecycle to hold Legendary |
| rainbow | Legendary (1,500) | Epic (1,250) | OVER-TIER: trailRainbow (Cosmetics.swift:3098 → 3692-3708) is per-segment hue-cycle + glow with no element lifecycle — exactly the doc's Epic bar and its hue-cycle-vs-lifecycle tie-breaker; already named the Epic-rung anchor candidate in open ruling #4 | Ruling #4: demote to Epic as the trail-Epic anchor, or keep Legendary as historical flagship |
| ink ✓ | Standard (750) | Legendary (min Rare) | UNDER-TIER: dispatch routes .ink to bespoke trailInk with a real-time, times-driven dwell/bleed mechanic (Cosmetics.swift:3094 → 3632-3691), grouped with the fire/ice/air "elemental lifecycle" trails in the drawRichTrail header — Standard bar requires stock trailTapered with no bespoke function | **RESOLVED 2026-07-02** — re-tiered to Legendary (the lifecycle bar) per ruling 1(c) |
| roseTrail ✓ | Rare (1,000) | Legendary (1,500) | UNDER-TIER: trailRose (Cosmetics.swift:3100 → 3378-3449) runs a full trailAge element lifecycle (petals pop in, settle/sway/turn, fade in place, lifetime 1.3s) and its own comment says "like the fire/ice trails" — the Legendary bar verbatim, not Rare's "still palette-static texture" | **RESOLVED 2026-07-02** — re-tiered to Legendary per ruling 1(c) |
| ember | Standard (750) | Rare (1,000) | UNDER-TIER: ember rides trailTapered's plusLighter glow path (glow: trail == .raybeam \|\| .gilded \|\| .ember, Cosmetics.swift:3104-3105), the exact treatment the Rare bar cites as raybeam/gilded precedent — Standard bar says "no glow" | **RESOLVED 2026-07-02** — re-tiered to Rare per ruling 1(c) |

### Trails — grader notes

- Clean MATCHes: sky/forest/bubblegum (stock trailTapered, no glow);
  snake/raybeam/gilded/graphite (all named §3 Rare precedents);
  fire/ice/cometTrail/stardust/air/aurora (all named §3 Legendary
  precedents, lifecycle or R4 layered).
- The standard's own §3 precedent line ("ink, ember, sky, forest,
  bubblegum" as Standard trailTapered examples, doc line 94) is stale
  against the code: ink has a bespoke renderer and ember takes the glow
  flag. The doc's "comments lie; code doesn't" rule applies to its own
  example column. **Doc fix needed.**
- snake has a real animation clock (travelling sine slither, t*5.0,
  Cosmetics.swift:3177-3254) plus a drawn head/eyes/tongue, straining the
  Rare bar's "still static" wording — MATCH only because the standard twice
  explicitly anchors snake at Rare. If Mac tightens that carve-out, snake
  becomes an UNDER-TIER candidate.
- aurora, like rainbow, has no trailAge lifecycle (index-aged hue-flow
  ribbon, Cosmetics.swift:3147-3172), but the doc explicitly cites
  trailAurora as its R4 example and it carries 3 additive layers vs
  rainbow's 2 strokes — MATCH per the doc; if ruling #4 demotes rainbow,
  that layer count is the defensible line keeping aurora Legendary.
- Economy oddity for Mac's eye (not a rendering misfit): graphite is priced
  Rare (1,000, isCoinPurchasable) yet is the default-equipped starter
  (static var starter = .graphite, Cosmetics.swift:~893) and implicitly
  owned by every player. See also the paper-world bundle flag in §9.
- 26% misfit rate — trails alone would trigger re-tiering PRs per the
  sprint-plan acceptance line.

## 5. Floors — 8 misfits (20 clean of 28)

Exempt: classic (starter), moneyFull (IAP secret; for the record a bespoke
static full-scene bill tiling, R2, BallGameView.swift:1206-1259).

| Item | Current | Graded | Evidence | Proposed action |
|---|---|---|---|---|
| grass ✓ | Legendary (1,500) | Rare (1,000) | OVER-TIER: static Canvas of seeded grass tufts, no TimelineView/clock — comment says "Static (no animation)" (BallGameView.swift:1012-1046) — R2 static texture = §3 floors Rare bar, not "animated overlay" | Re-tier to Rare, animate to hold Legendary, or adopt a floors doodle clause (ruling needed) |
| moon | Legendary (1,500) | Rare (1,000) | OVER-TIER: static Canvas of seeded craters (SeededRNG, no animation clock), "Static (no animation)" (BallGameView.swift:1053-1090) — R2; the doc's Legendary precedent "moon craters + regolith" trusted the lying Cosmetics.swift:978 "animated floor overlays" comment | Same options as grass; also fix the lying comment + doc precedent line |
| brass ✓ | Legendary (1,500) | Rare (1,000) | OVER-TIER: the doc's pre-flagged suspect confirmed — plain static Canvas (sheen gradient + plates + cog engravings + rivets), no TimelineView anywhere in 1266-1336 — rich R2 texture but fails the animation test the doc's grading note demands | Same options as grass |
| notebook ✓ | Standard (750) | Rare (1,000) | UNDER-TIER: notebookRules draws ruled lines + red margin as a bespoke static texture overlay (BallGameView.swift:1929-1948) — meets the Rare bar ("static texture drawn once over the base") the doc marks "none yet" | **RESOLVED 2026-07-02** — re-tiered to Rare per ruling 1(c); opens the floors Rare rung |
| graph | Standard (750) | Rare (1,000) | UNDER-TIER: graphGrid draws a full pale-green grid texture over the base (BallGameView.swift:1951-1972) — R2 static texture overlay, above "flat base color" | **RESOLVED 2026-07-02** — re-tiered to Rare per ruling 1(c) |
| parchment | Standard (750) | Rare (1,000) | UNDER-TIER: parchmentTexture draws a warm radial vignette + 60 seeded aged-ink specks (BallGameView.swift:1975-2003) — static grain overlay = Rare bar | **RESOLVED 2026-07-02** — re-tiered to Rare per ruling 1(c) |
| sketch | Standard (750) | Rare (1,000) | UNDER-TIER: sketchGrain draws 140 seeded cross-hatch pencil strokes (BallGameView.swift:2006-2027) — static texture overlay = Rare bar | **RESOLVED 2026-07-02** — re-tiered to Rare per ruling 1(c) |
| origami | Standard (750) | Rare (1,000) | UNDER-TIER: origamiFolds draws diagonal fold-shadow gradient stripes + fold lines (BallGameView.swift:2030-2056) — static texture overlay = Rare bar | **RESOLVED 2026-07-02** — re-tiered to Rare per ruling 1(c) |

### Floors — grader notes

- **The doc's factual premise is broken twice** (fixes needed):
  (1) §3 floors Rare precedent says "none yet (would need a static-overlay
  render path)" but paperFloorOverlay (BallGameView.swift:1917-1926) IS
  that path, with five de facto occupants at Standard price — the
  sanctioned two-pole floors exception (§4) is already obsolete;
  (2) the Legendary precedent line "every hasAnimatedOverlay == true floor"
  includes three floors (grass/moon/brass) that never animate.
- If Mac adopts a floors analogue of the goals doodle clause (bespoke
  full-scene static auto-qualifies Legendary), grass/moon/brass re-grade
  MATCH — no such clause exists today, so they are filed per the doc's
  gridCity/brass grading note ("evidence for the Rare/Epic rungs, not a
  silent pass").
- gridCity — the other suspect in the doc's grading note — verified
  genuinely animated: TimelineView scroll at 30Hz with graceful Reduce
  Motion freeze (BallGameView.swift:1136-1201); Legendary MATCH.
- Reduce Motion QA flag (not a tier input): aurora, disco, and eclipse
  overlays are skipped entirely under Reduce Motion
  (BallGameView.swift:492-532), leaving only the flat base color — arguably
  not "freezing gracefully" per §5; gridCity freezes internally and keeps
  its texture, the better pattern.
- paperTrailEnabled mechanics (notebook/graph/parchment/sketch/origami)
  were NOT counted toward tier per the §3 rule — the five UNDER-TIER calls
  rest solely on their drawn texture overlays.
- Clean 20 = 16 flat-color Standards (Cosmetics.swift:1053-1086) + 4
  animated Legendaries (aurora R4, disco R3, eclipse R3, gridCity R3/R4).

## 6. Pits — 1 misfit (27 clean of 28)

Census: 29 pits — classic exempt; 22 Standard @750, 6 Legendary @1,500; no
Rare/Epic pits exist (two-pole ladder, sanctioned §4 exception). No
IAP-secret pits exist.

| Item | Current | Graded | Evidence | Proposed action |
|---|---|---|---|---|
| eclipse ✓ | Legendary (1,500) | Epic (1,250) | eclipsePitOverlay (BallGameView.swift:1709-1735) is a single pulsing-corona effect (one `pulse` sine) over a static ring + static moon disc on a flat void fill, tight gold/black palette — matches the §3 pit Epic bar ("animated overlay, one effect layer, tight palette") verbatim and lacks Legendary's "multiple elements or full-scene treatment"; the eclipse FLOOR overlay (:1666) has the qualifying starfield — the pit version dropped it | Add the floor version's starfield to hold Legendary, **or** accept it as the natural anchor for the currently-empty pit Epic rung (the animated-overlay path already exists) |

### Pits — grader notes

- All 22 Standard pits are R0: identical Rectangle().fill(pit.color) render
  (BallGameView.swift:912, colors Cosmetics.swift:1212-1243) — all MATCH.
- Shared renderers that do NOT affect tier (paper-trail clause):
  pitDepthShade (BallGameView.swift:943) applies to every pit;
  PitLandingView one-shot splash/embers/smoke/void/confetti FX
  (BallGameView.swift:5986-6036) is a stock shared path palette-keyed per pit.
- 5 of 6 Legendary pits verified R4 MATCH: evil (:1343), sky (:1424),
  pond (:1477), space (:1577), nightclub (:1739).
- No UNDER-TIER pits found.

## 7. Boundaries — 3 misfits (9 clean of 12)

13 boundaries; classic exempt. Every boundary is R0 by construction:
Boundary exposes only color/deepColor/edgeColor (Cosmetics.swift:1322-1343)
and deepColor/edgeColor are mechanical brightness derivations via
boundaryShaded (:1349-1355). Every consumer verified (BallGameView.swift:
473-476, RollUpView.swift:153-159, RollOutView.swift:213-228,
GoldRushView.swift:187, SnakeGameView.swift:155, LoadoutDiorama.swift:
186-192, LockerView.swift:306-309, CosmeticShopView.swift:929-934,
ProfileView.swift:201) — all consume the color triplet only; **no per-case
boundary draw path exists anywhere**, so no hidden renderer rescues the
Legendary trio. (Same-named obsidian/candy/circuit cases elsewhere are the
Goal and BallSkin enums, not Boundary.)

These are exactly the doc's pre-flagged ruling #2 trio — this audit
confirms the flag from code.

| Item | Current | Graded | Evidence | Proposed action |
|---|---|---|---|---|
| obsidian ✓ | Legendary (1,500) | Standard (750) | OVER-TIER, R0: flat dark hue Color(0.16, 0.16, 0.22) (Cosmetics.swift:1334) consumed only as flat fills (BallGameView.swift:474-476) — a muted solid hue with zero texture/animation, identical rendering class to 750 slate | Ruling #2: fund the animated/texture wall renderer to hold Legendary, or re-tier (doc option (b) parks all three at Rare; strict hue grade says Standard) |
| candy ✓ | Legendary (1,500) | Rare (1,000) | OVER-TIER, R0: flat pink Color(0.98, 0.46, 0.70) (Cosmetics.swift:1335) — vivid "wow color" at best; the implied candy stripes are never drawn anywhere in the wall render path | Ruling #2: same options; strict grade = Rare (vivid hue meets the Rare bar) |
| circuit ✓ | Legendary (1,500) | Standard (750) | OVER-TIER, R0: flat teal Color(0.20, 0.70, 0.55) (Cosmetics.swift:1336), barely distinguishable from Standard mint (:1327); no circuit-trace or pulse rendering exists in any consumer | Ruling #2: same options; strict grade = Standard |

### Boundaries — grader notes

- ice (Rare) is the weakest MATCH — pale rather than vivid
  (Cosmetics.swift:1333) — but it is the doc's own named Rare precedent
  (standards-cosmetics.md line 129), so not a misfit.
- Clean 9: slate, ember, mint, sky, orchid, sand, neon, gold, ice. No
  IAP-only secret boundaries exist.

## 8. Music — 3 misfits (14 clean of 17)

Rendering reality: ALL 17 paid tracks currently deliver silence —
MusicTrack is pure identifiers (Cosmetics.swift:1358-1362), no audio assets
exist in the repo, and the only audio code is the win-sound arpeggio synth
(BallGameView.swift:6522-6660), unrelated to MusicTrack. Grading strictly by
renderer would file the whole category OVER-TIER; §3 Music's
"grade the spec until audio ships" clause is the sanctioned procedure and
was applied. Exempt: none + ambient (starter tier, Cosmetics.swift:
1365-1366). Aurora music is bundle content but a normal catalog item, so it
was graded normally per the availability tie-breaker.

| Item | Current | Graded | Evidence | Proposed action |
|---|---|---|---|---|
| celestial ✓ | Legendary (1,500) | Ungraded — meets no bar at spec level (Standard-at-best pending a cited spec) | Cosmetics.swift:1386 is a bare `case celestial` with no comment or composition spec — nothing names the "bespoke signature piece / unique motif owned by the track" the Legendary bar requires (contrast aurora's cited "ambient, drifting pads" at :1389); under the §4 new-item rule it could not quote a single §3 checklist line at Legendary | Write a composition spec citing the §3 Legendary bar before the V1.1 commission, or re-tier |
| mysterium ✓ | Legendary (1,500) | Ungraded — meets no bar at spec level | Cosmetics.swift:1387 is a bare `case mysterium` with zero spec; a mood-title identifier indistinguishable from an uncommissioned placeholder, with no signature element stated for the 1,500-coin "recognizably THE sound" bar | Same as celestial |
| opus ✓ | Legendary (1,500) | Ungraded — meets no bar at spec level | Cosmetics.swift:1388 is a bare `case opus` with zero spec; the name gestures at "a signature piece" but states no motif, length, or structure meeting the Legendary bar — spec-class identical to the flagged siblings, not to doc-anchored aurora | Same as celestial |

### Music — grader notes

- Anchored MATCHes not re-litigated: the 8 Standard genre names
  (piano…synthwave, Cosmetics.swift:1369-1376) are cited verbatim in the
  Standard bar, lofi…dreamscape (:1379-1383) are the cited Epic targets,
  and aurora (:1389) is cited inside the Legendary bar text — these define
  the calibration points.
- Watch item for V1.1 commissions (both ends doc-anchored, not a misfit):
  retrowave (Epic 1,250, :1381) vs synthwave (Standard 750, :1376) are
  near-synonymous genre names 500 coins apart — the commissioned tracks
  must audibly justify the spread or players read them as the same item at
  two prices.
- Shop is tier-blind for music: musicPreview (CosmeticShopView.swift:
  1913-1925) and musicSwatch (:1472-1479) render the identical blue
  music.note SF Symbol for every tier — a 1,500-coin Legendary previews
  exactly like a 750 Standard. QA/UX gap to fix alongside V1.1 audio.
- Structural rung note: music skips Rare (Cosmetics.swift:1418-1430) — one
  of the five inconsistent ladders §4 resolves; opening Rare gives V1.1 a
  1,000-coin commission slot.

## 9. Bundles — 20 flags (46 clean of 66)

Method: all 66 CosmeticBundle.catalogue entries (Cosmetics.swift:1857-2737)
audited by deriving every member's tier from the seven tier switches,
summing tier.basePrice for fullPrice, and banding via BundleRarity floors
5,500/6,500 (:1653-1654, :1785-1791). Validation: the derived distribution
exactly matches the checked-in comment (:1642-1652) — 6 STANDARD /
20 RARE / 40 LEGENDARY, six bundles at exactly 5,500.

These are composition findings, not tier grades — per §5, exclusivity and
bundle membership never changed an item's visual grade.

| Bundle | Current | Flag | Evidence | Proposed action |
|---|---|---|---|---|
| aurora ✓ | LEGENDARY 8,250 | THEME-PARITY BREAK | Flagship 1:1 theme set sells six "Aurora" items but Pit.aurora is standard 750 flat with NO animated overlay (tier Cosmetics.swift:1201, hasAnimatedOverlay excludes it :1249-1252) while Floor.aurora is exclusive/animated (:1044, :1108) — five Legendary namesakes plus one 750 flat | Promote/animate Pit.aurora (clears 3 bundle flags at once) or rename the pit out of the set |
| paper-world ✓ | RARE 5,500 | ADVERTISES 6, GRANTS 5 | contentSummary sells "Graphite trail (starter)" but trails: [] (Cosmetics.swift:1901); graphite is implicitly owned by every player (GameState.swift, starter comment) AND is actually rare-tier 1,000 in the switch (:905-906) — the copy is doubly wrong | Fix contentSummary copy (or grant the trail); resolve the graphite starter-vs-rare contradiction |
| backtoschool-2026 | STANDARD 4,500 | STARTER-PADDED SEASONAL, GIFT-POOL EXPOSURE | goals: [.target] is THE free default goal (starter, 0 coins, Cosmetics.swift:819-820, bundle :2473); cheapest bundle in catalogue, and during its Aug 15–Sep 8 window it enters the post-tutorial FREE gift pool (rarity == .standard && isAvailable, BallGameView.swift:4613) carrying a Legendary seasonal ball | Swap the starter for a real goal, or Mac rules the gift-pool exposure acceptable |
| diamond | STANDARD 4,500 | STARTER-PADDED | goals: [.target] free starter default (Cosmetics.swift:2513, tier :819-820) pads a paid sports bundle; **the padding is load-bearing** — it keeps diamond in the guarded 4-bundle permanent tutorial-gift pool (comment :1646-1650) | Needs Mac's ruling, not a silent fix — changing it changes the guarded pool (testTutorialGift_permanentStandardBundlePool_neverEmpty) |
| heavens | LEGENDARY 7,250 | STARTER-PADDED | floors: [.classic] is the free starter floor (0 coins, Cosmetics.swift:1878, tier :1036-1037) — a diamond-gem Legendary bundle filling one of six slots with the default every player already has | Swap in a real floor |
| dune | RARE 5,500 | STARTER-PADDED | music: [.ambient] is a free starter track (0 coins, Cosmetics.swift:2212, tier :1420-1421); also sits exactly ON rareFloor 5,500 (:1653), so any member re-tier flips its gem | Swap in a real track; re-check after item re-tiers |
| earthday-2027 | STANDARD 5,000 | STARTER-PADDED SEASONAL, GIFT-POOL EXPOSURE | music: [.ambient] free starter track (Cosmetics.swift:2463, tier :1420-1421) drags a bundle containing the Legendary Earth ball into the STANDARD band, making it tutorial-gift-eligible during its April window (BallGameView.swift:4613) | Swap the starter for a real track (also lifts it out of the gift pool), or Mac rules the exposure acceptable |
| eclipse | LEGENDARY 7,500 | IDENTITY ITEM OFF-THEME | ball is plain .blue, a standard 750 mono-shaded stock marble (Cosmetics.swift:2133, tier :229-231) — not even eclipse-themed — while goal/floor/pit/music are bespoke Eclipse art (floor+pit exclusive animated overlays :1044, :1204) | Swap in an eclipse-themed ball |
| hellfire | LEGENDARY 6,750 | IDENTITY ITEM UNDER-THEME | "Roll a ruby through the inferno" anchors on ball .ruby, a standard 750 R0 mono recolor via the stock marble renderer (Cosmetics.swift:1863, tier :229-231) beside three Legendary members (inferno/fire/evil) | Upgrade the anchor ball or adjust the tagline |
| midnight-carnival | LEGENDARY 6,500 | IDENTITY UNDER-THEME + AT BOUNDARY | S16 Challenge-Track reward (100 levels) anchored on ball .copper, a standard 750 recolor (Cosmetics.swift:2594, tier :229-231) also sold in the RARE arcade bundle; fullPrice sits exactly ON legendaryFloor 6,500 (:1654) | Upgrade the anchor ball; note the gem flips on any member re-tier |
| pride-2027 | LEGENDARY 7,500 | SEASONAL THEME-PARITY | contentSummary pairs "Aurora floor · Aurora pit" (Cosmetics.swift:2429) but the floor is exclusive/animated (:1044) while the pit is standard 750 flat with no overlay (:1201, :1249-1252) — same-name items, 750-coin quality gap | Resolved by the Pit.aurora fix (see aurora bundle row) |
| crystal-cavern | LEGENDARY 7,250 | THEME-PARITY | "the crystals glow" tagline yet both surfaces are standard flats — midnight floor (:1040) and the flat non-animated aurora pit (:1201, :1249-1252); nothing in the S15 track-reward bundle glows except the goal/trail | Pit.aurora fix helps; or re-theme the tagline/surfaces |
| summer-2026 | LEGENDARY 6,500 | SEASONAL AT RARITY BOUNDARY | fullPrice exactly equals legendaryFloor 6,500 (Cosmetics.swift:1654) — the diamond gem is defended by zero margin; one 250-step member swap demotes it to RARE | Track through any re-tier wave; consider margin above the floor |
| muertos-2026 | LEGENDARY 6,500 | SEASONAL AT RARITY BOUNDARY | exactly at legendaryFloor; composition (1 exclusive + roseTrail rare + 2 standard surfaces) is the weakest possible Legendary — any re-tier of roseTrail or blossom flips the gem | Note: **roseTrail is an UNDER-TIER promotion candidate (§4 trails)** — promoting it to Legendary raises this bundle to 7,000 and secures the gem |
| lunar-2027 | LEGENDARY 6,500 | SEASONAL AT RARITY BOUNDARY | exactly at legendaryFloor with only one exclusive member (lunarDragon ball); velvet floor+pit standard 750 reused from four other bundles | Track through any re-tier wave |
| mardigras-2027 | LEGENDARY 6,500 | SEASONAL AT RARITY BOUNDARY | exactly at legendaryFloor; bubblegum trail standard 750 (Cosmetics.swift:903) is the slot holding it at the floor | Track through any re-tier wave; note mardiGras ball is a §2a re-tier candidate (−250 would demote the gem) |
| harvest-2026 | RARE 6,250 | SEASONAL NEAR BOUNDARY (UNDER) | 250 below legendaryFloor — shows the gold RARE gem while near-identical seasonal siblings at 6,500 show diamond LEGENDARY; ember trail standard 750 vs their rare/exclusive trails is the whole difference | Note: **ember is an UNDER-TIER promotion candidate (§4 trails)** — promoting it to Rare puts this bundle exactly at 6,500 |
| oktoberfest-2026 | RARE 5,750 | SEASONAL NEAR BOUNDARY (LOWER) | 250 above rareFloor 5,500; four of six members standard 750 — one downgrade would drop a seasonal-exclusive-ball bundle into the STANDARD band and hence the free tutorial-gift pool (BallGameView.swift:4613) | Track through any re-tier wave (oktoberfest ball is a §2a re-tier candidate) |
| champion | RARE 6,250 | PRESTIGE-REWARD MISMATCH | Golden Gauntlet's ultimate reward ("No tutorial. No mercy.", Cosmetics.swift:2564) grades only gold-gem RARE — exclusive trophy ball + quasar goal padded by mirage floor/pit + orchestral all standard 750, the exact same three fillers as the buyable midas bundle (:2097-2099) | Upgrade the filler slots so the prestige reward outshines a buyable bundle |
| sketchbook ✓ | STANDARD 5,250 | TAGLINE CONTRADICTS CONTENTS | tagline "Pencil, graphite, and a steady hand" (Cosmetics.swift:2105) but the trail slot ships .smoke, an off-theme grey exclusive 1,500 (:2109, tier :907-909); the actual graphite trail (rare, default-owned) is absent, so the only above-standard member is off-theme | Swap smoke → graphite (also fixes theme), or rewrite the tagline; interacts with the graphite starter contradiction |

### Bundles — grader notes

- **Root-cause leverage:** Pit.aurora being standard/flat (vs Floor.aurora
  exclusive/animated) causes 3 of the 20 flags (aurora, pride-2027,
  crystal-cavern); promoting or renaming that one pit clears three bundles.
  It is the only pit whose floor namesake is Legendary — an artifact of the
  floors/pits two-pole ladder (§4 of the standard).
- **Boundary fragility:** 10 bundles sit at EXACTLY fullPrice 6,500 — 4
  seasonal (flagged above) plus 6 permanent (winter, neon, candyland,
  realistic-marble, midnight-carnival, cathedral). Bundle rarity is derived
  purely from summed member prices, so **any single item re-tier from §2-§8
  silently flips these gems — re-run this bundle audit after item re-tiers
  land.**
- **Sanctioned-tension warning:** the STANDARD band is deliberately tuned
  so the post-tutorial gift pool holds diamond/nature/citrus/sketchbook +
  the backtoschool-2026 and earthday-2027 windows (comment
  Cosmetics.swift:1646-1650, guarded by
  testTutorialGift_permanentStandardBundlePool_neverEmpty). Fixing the
  starter-item padding in diamond or backtoschool changes that guarded
  pool — needs Mac's ruling, not a silent reprice.
- **Item-level bug feeding bundle copy:** TrailColor.starter is .graphite
  (Cosmetics.swift:893) and GameState treats it as implicitly owned, yet
  the tier switch prices graphite at rare/1,000 (:905-906). Any bundle or
  shop surface listing graphite inherits this contradiction — paper-world
  is the first casualty.
- Clean by design: planets (13,500, nine exclusive balls, the catalogue's
  only mono-category bundle) is internally consistent; nature/citrus/
  ocean/noir and the premium-section sets (quicksilver, oracle, neon-city,
  clockwork, magma-core, plasma-globe, cathedral, lava-lamp, geode,
  high-roller) all grade MATCH — mixed tiers there follow the theme rather
  than contradict it.

## 10. Verification pass — 21 sampled, 0 overturned

A 2-agent adversarial re-grade (per the §5 procedure) sampled 3 misfits per
category (all misfits where a category had ≤3) and re-read every cited
renderer against the standard. **All 21 upheld; zero overturns.** Sample:
ghost, pastel, galaxy (balls); neon, quasar (goals); ink, roseTrail, smoke
(trails); grass, brass, notebook (floors); eclipse (pits); obsidian, candy,
circuit (boundaries); celestial, mysterium, opus (music); aurora,
paper-world, sketchbook (bundles). Judgment-call flags (quasar, pit
eclipse) were confirmed as defensible, evidence-backed borderline calls,
not errors. One immaterial citation drift found (graphite implicit-
ownership comment is at GameState.swift:57, not :1530 — substance
identical).

## 11. What Mac needs to rule on (rolled up)

The standard's §6 open rulings, now with audit stakes attached:

1. **All-rungs policy (§4)** — adopting it makes the pastel/dune Rare
   re-tier and the pit-Epic eclipse option legal moves.
2. **Boundary trio (obsidian/candy/circuit)** — fund the wall texture
   renderer or re-tier; the audit confirms no hidden renderer exists.
3. **Doodle clause scope** — extend to balls (rescues pumpkin/sugarSkull/
   mardiGras/oktoberfest) and/or floors (rescues grass/moon/brass), or
   require animation everywhere (which flips goals holeInOne/doodle/
   soccerNet to OVER-TIER). The clause's goals wording also needs the R4
   re-read documented in §3 above.
4. **Trail Epic rung / rainbow** — demote rainbow as the Epic anchor or
   keep it Legendary as flagship.
5. **Music specs** — celestial/mysterium/opus need composition specs
   before V1.1 commissions can cite the bars.
6. **NEW — gift-pool exposure**: backtoschool-2026 and earthday-2027 put
   Legendary seasonal balls in the free tutorial-gift pool during their
   windows; diamond's starter padding is load-bearing for the guarded
   permanent pool.
7. **NEW — graphite contradiction**: starter-owned yet priced Rare;
   decide owned-free (fix the tier switch) or purchasable (fix the
   starter), then fix paper-world/sketchbook copy.
8. **NEW — planets precedent**: mechanically R2-static like the flagged
   seasonals; keep the explicit precedent (status quo, graded MATCH here)
   or fold them into ruling #3's static-Legendary decision.

**Standard-doc fixes to land regardless of rulings** (stale lines this
audit exposed in [standards-cosmetics.md](standards-cosmetics.md)): §2 R1
example "pastel/neon/dune" → "pastel/dune"; goals Epic bar's shared-
rainbowHole premise; "rainbow/quasar full-spectrum" precedent; trails §3
Standard example line (ink/ember); floors Rare "none yet" and the
Legendary hasAnimatedOverlay precedent line.

---

*Audit executed 2026-07-02 against the claude/cosmetic-standards checkout;
companion standard committed as docs/economy/standards-cosmetics.md. Seven
category graders + one bundle grader + one adversarial verifier, per the
06-sprint-plan.md Workstream B procedure.*
