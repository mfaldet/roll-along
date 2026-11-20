# Quality audit, November 2026

Every piece of the 22 collections on sale or scheduled, plus the free Roll Along set, judged against `docs/cosmetics/quality-standard.md` (rules R1 to R9) after the quality round. Every fail and borderline piece was fixed.

**How the verdicts were made.** By reading each piece's drawing code, not by looking at it on screen: this work was done without Xcode, so nothing here has been compiled or seen. Treat each verdict as a first pass to confirm in the debug gallery (Settings, Debug, All Collections, in a Debug build).

- **Meets (approved by owner)** means the owner approved the piece in the quality round; it was not changed. Concerns about approved pieces are listed at the end.
- **Verdict before** is the piece as it stood after the quality round, before this audit's fixes.
- Tiers, prices and ids did not change. A replacement took the tier of the piece it replaced.

## Totals

| | Pieces |
|---|---|
| Audited (22 collections x 6) | 132 |
| Met the standard, no change | 76 |
| Borderline, fixed in place | 37 |
| Failed, fixed in place | 11 |
| Wrong theme or failed, replaced by a new piece | 8 |
| **Changed in the audit** | **56** |

Roll Along's six pieces were checked and not changed. Eight pieces left their sets and are now held: Mosaic goal, Rainbow trail, Air trail, Sky trail, Parchment floor, Parchment pit, Blueprint floor, Blueprint pit.

## Launch collections

### Roll Along (Iconic, free)

Audit only. Nothing changed.

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Red | Iconic, free | Meets (approved by owner) | None | — | No |
| Goal | Target | Iconic, free | Meets (approved by owner) | None | — | As before |
| Trail | Classic Shadow | Iconic, free | Meets (approved by owner) | None | — | Fade only |
| Floor | Classic White | Iconic, free | Meets (approved by owner) | None | Flat fill by design | No |
| Pit | Classic Black | Iconic, free | Meets (approved by owner) | None | Flat fill by design | No |
| Boundary | Classic Gray | Iconic, free | Meets (approved by owner) | None | Flat fill by design | No |

### Nature (4,500 coins)

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Jade | Standard, 750 | Meets (approved by owner) | None | — | No |
| Goal | Leaf Wreath | Standard, 750 | Meets | None | Three woven leaf rows, blossoms, berries, dark hollow with a pale rim | No |
| Trail | Forest | Standard, 750 | Meets (approved by owner) | None | — | Fade only |
| Floor | Meadow | Standard, 750 | Meets (approved by owner) | None | — | No |
| Pit | Meadow | Standard, 750 | Meets (approved by owner) | None | — | No |
| Boundary | Mint | Standard, 750 | Meets (approved by owner) | None | A plain color ring (see concerns) | No |

### Fire (4,500 coins)

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Blaze | Standard, 750 | Borderline R6: flames breathed on 2 to 4 s periods with a 40% height change | Motion slowed | Same layered flames; 5 to 8 s periods, about 24% change; sparks rise over 7 s | Yes, slow |
| Goal | Flame Ring | Standard, 750 | Borderline R6: flames changed height by 56% on a 3 s period | Motion slowed | Burning hoop; 5 to 6 s periods, about 22% change; coal bed pulses over 6 s | Yes, slow |
| Trail | Wildfire | Standard, 750 | Borderline R6: one-second flicker, 44% change | Motion slowed | Same tall forked flames; two-second waver, 20% change | In place |
| Floor | Scorched | Standard, 750 | Borderline R5, R7: about 105 embers and 75 ash flecks per screen; seams glowing at 34% | Redrawn (density, light) | About 30 embers and 30 flecks; seam glow at most 16% | No |
| Pit | Crater | Standard, 750 | Meets (approved by owner); reference piece | None | — | No |
| Boundary | Flare | Standard, 750 | Meets | None | Charred rim, glow breathing on 4.8 s, licks creeping at 3.5 to 5 pt/s | Yes, slow |

### Water (4,500 coins)

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Droplet | Standard, 750 | Meets | None | Waves on an 11 s period, bubbles rising over 6 s | Yes, slow |
| Goal | Whirlpool | Standard, 750 | Borderline R6: one turn in 19.6 s, just under the 20 s line | Motion slowed | One turn in about 26 s; foam flecks slower | Yes, slow |
| Trail | Splash | Standard, 750 | Meets (approved by owner) | None | — | As before |
| Floor | Shallows | Standard, 750 | Borderline R7: ripple rings started at 30% strength over a busy bottom | Redrawn (light, density) | Rings fade in and out at 16% at most; fewer pebbles and sand ripples | Yes, 15 fps |
| Pit | Deep End | Standard, 750 | Borderline R7: pale rim on a pale floor | Rim redrawn | Dark line just inside the white waterline; six steps unchanged | No |
| Boundary | Breakers | Standard, 750 | Meets | None | Swells rolling at 6 pt/s with foam crests | Yes, slow |

### Storm (4,500 coins)

Lightning changed for all six: one eased pulse per strike (0.12 s rise, smooth decay), one strike every 7 to 12 s per piece, none under Reduce Motion. The owner asked for driving rain; the standard fails fast motion on large surfaces, so the rain was slowed most on the floor and least in the ball and pit. Each speed is one number if it now reads as drizzle.

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Thundercloud | Standard, 750 | Borderline R6: rain crossed the ball in 0.6 s | Motion slowed | Rain about 2.5 times slower and fainter | Yes |
| Goal | Storm Eye | Standard, 750 | Borderline R6: lightning flashed twice per strike | Flash softened | Bands turn once in 70 s; one soft flash per strike | Yes |
| Trail | Squall | Standard, 750 | Meets | None | Mist, falling streaks, splash rings where laid | In place |
| Floor | Overcast | Standard, 750 | Borderline R6: rain at 150 pt/s across the whole floor, 20 fps | Motion slowed | Faint veil of 30 streaks at 38 pt/s; clouds at 4 pt/s; 15 fps cap | Yes |
| Pit | Maelstrom | Standard, 750 | Borderline R6, R7: rim barely lighter than the dark floor; fast rain | Rim and motion redrawn | Rim is the brightest step, with a pale lip line; rain half as fast | Yes, 20 fps |
| Boundary | Thunderhead | Standard, 750 | Borderline R6: rain line scrolling at 14 pt/s | Motion slowed | Rain line at 4.5 pt/s, fainter | Yes |

### Sketchbook (4,750 coins)

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Pencil | Standard, 750 | Meets | None | Pencil seen from above, eraser end up, six shaded barrel faces | No |
| Goal | Scribble | Standard, 750 | Meets | None | Pencil-drawn target with wobbly double rings and hatching | No |
| Trail | Graphite | Standard, 750 | Meets (approved by owner) | None | — | Fade only |
| Floor | Paper | Rare, 1,000 | Meets | None | Pencil grain with faint doodles at 15% | No |
| Pit | Sketch | Standard, 750 | Meets (approved by owner) | None | — | No |
| Boundary | Slate | Standard, 750 | Meets (approved by owner) | None | A plain color ring (see concerns) | No |

### Midas (5,000 coins)

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Fool's Gold | Standard, 750 | Meets (approved by owner) | None | — | No |
| Goal | Bullion | Standard, 750 | Meets | None | Struck coin with bars and a dark well | No |
| Trail | Gilded | Rare, 1,000 | Meets (approved by owner) | None | — | Fade only |
| Floor | Gold Leaf | Standard, 750 | Borderline R7: mid-bright gold under gold coins and the Vault pit's gold rim | Adjusted | Base darkened to antique gold; two fainter dimples per tile | No |
| Pit | Vault | Standard, 750 | Meets | None | Five gold steps down to a dark floor | No |
| Boundary | Gold | Rare, 1,000 | Meets (approved by owner) | None | — | As before |

### Citrus (5,250 coins)

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Lemon | Standard, 750 | Meets | None | A real lemon shape with a dimpled rind | No |
| Goal | Citrus Slice | Epic, 1,250 | Meets | None | Cut citrus wheel with ten segments and an amber cup | Yes, one turn in 50 s |
| Trail | Zest | Rare, 1,000 | Meets | None | Juice line with peel curls and drops | Fade only |
| Floor | Grove | Standard, 750 | Meets | None | Sunlit sand with leaf shadows and fallen blossoms | No |
| Pit | Tide Pool | Standard, 750 | Borderline R6: water that stood still | Animated in place | Same pool; the foam line breathes and one faint ripple moves inward | Yes, 7 s breath, 9 s ripple, 20 fps |
| Boundary | Citrus | Standard, 750 | Meets | None | Leafy hedge hung with oranges, lemons and limes | No |

### Ancient Temple (6,000 coins)

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Dune | Epic, 1,250 | Meets | None | Dune ridges with sunlit faces and lee shadows | Yes, slow creep |
| Goal | Eclipse | Epic, 1,250 | Meets (approved by owner); reference piece | None | — | As before |
| Trail | Glyphs | Rare, 1,000 | Meets | None | Groove in the sand with carved glyphs either side. Passed under R4 because carved glyphs are the thing it is named after | No |
| Floor | Desert | Standard, 750 | Meets | None | Sand ripples over half-buried paving stones | No |
| Pit | Canyon | Standard, 750 | Meets (approved by owner); reference piece | None | — | No |
| Boundary | Sandstone | Rare, 1,000 | Meets | None | Cut temple blocks with a chiseled key pattern | Slow band of sunlight |

### Winter (6,250 coins)

All six meet. Glints and settles run on 3 to 12 s periods.

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Snowglobe | Legendary, 1,500 | Meets (approved by owner); reference piece | None | — | As before |
| Goal | Frost | Standard, 750 | Meets | None | Frozen pond with a frost crystal and dark open water | Slow glints |
| Trail | Ice | Legendary, 1,500 | Meets | None | Icy track with a skate cut and snow piles | Glints in place |
| Floor | Snowfield | Standard, 750 | Meets | None | Blue-hour snow with drifts and bird tracks | No |
| Pit | Crevasse | Standard, 750 | Meets | None | Snow lip and ice ledges stepping down to black | No |
| Boundary | Ice | Rare, 1,000 | Meets | None | Glacier ice with a snow cap and icicles | Two slow glints |

### Neon (7,000 coins)

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Neon | Epic, 1,250 | Meets (approved by owner); reference piece | None | — | Glow pulse |
| Goal | Neon | Legendary, 1,500 | Borderline R3, R6: hues drifted through the whole spectrum; highlights lapped in 18 s; no clear target | Redrawn | Tubes keep to magenta and cyan; highlights lap in about 26 s; black target disc at 24% of the radius | Yes, slow, 20 fps |
| Trail | Raybeam | Rare, 1,000 | Meets (approved by owner); reference piece | None | — | Fade only |
| Floor | Grid City | Legendary, 1,500 | Borderline R6, R7: one row every 3.5 s; lines drawn at up to 85% strength | Redrawn | Same grid; lines at 10 to 34%; one row about every 12 s | Yes, very slow, 15 fps |
| Pit | Blackout | Standard, 750 | Borderline R5: only two steps | Redrawn | Cyan tube, magenta step, faint violet step, black core | No |
| Boundary | Neon | Rare, 1,000 | Meets (approved by owner) | None | — | As before |

### Haunted (7,000 coins)

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Ghost | Legendary, 1,500 | Borderline R6: blinked every 3.8 s | Adjusted | Blinks about every 8 s | Slow bob and sway |
| Goal | Pentagram | Epic, 1,250 | Borderline R6, R8: flames flickered 45% on a 2.9 s period; its fire ring was the same drawing as Inferno's | Redrawn | Five ritual flames, one at each star point; about 20% change over 5.5 s; target 25% of the radius | Yes, slow, 20 fps |
| Trail | Smoke | Legendary, 1,500 | Meets (approved by owner) | None | — | As before |
| Floor | Fog | Standard, 750 | Borderline R7: fog banks up to 18% strength | Adjusted | Fog at 5 to 10% | Slow drift |
| Pit | Graveyard | Rare, 1,000 | Borderline R7: brown rim dim against the dark Fog floor | Adjusted | Thin pale lip of dry earth around the opening | Smoke rises |
| Boundary | Phantom | Rare, 1,000 | Meets (approved by owner) | None | — | As before |

### Abyssal Depths (7,000 coins)

Audit only. Nothing changed.

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Trench | Legendary, 1,500 | Meets (approved by owner); reference collection | None | — | As before |
| Goal | Vortex | Standard, 750 | Meets (approved by owner); reference collection | None | — | As before |
| Trail | Ink | Legendary, 1,500 | Meets (approved by owner); reference collection | None | — | As before |
| Floor | Inverted | Standard, 750 | Meets (approved by owner); reference collection | None | Flat near-black fill: the standard's one approved exception to R5 | No |
| Pit | Sea Vent | Legendary, 1,500 | Meets | None | Basalt ledges, glowing vent mouth, rising bubbles | Slow glow pulse |
| Boundary | Abyss | Rare, 1,000 | Meets (approved by owner); reference collection | None | — | As before |

### Cosmos (7,250 coins)

All six meet. Nothing changed.

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Nebula | Legendary, 1,500 | Meets (approved by owner); reference piece | None | — | As before |
| Goal | Galaxy | Epic, 1,250 | Meets (approved by owner); reference piece | None | — | As before |
| Trail | Stardust | Legendary, 1,500 | Meets (approved by owner); reference piece | None | — | As before |
| Floor | Midnight | Standard, 750 | Meets | None | Space black; stars twinkle on 8 to 25 s periods | Yes, 10 fps |
| Pit | Moonlit | Standard, 750 | Meets | None | Five masonry steps, 44% dark core, pale rim | Slow shimmer |
| Boundary | Starlight | Legendary, 1,500 | Meets (approved by owner); reference piece | None | — | As before |

### Champion (7,750 coins)

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Trophy | Legendary; earned, not sold | Fails R4: a cup emblem pictured on a gold sphere | Redrawn | The ball is the trophy: a gold cup seen from above, two handles, a lip engraved with laurel, a bowl stepping down to a dark base | One gleam round the lip in about 26 s; 20 fps |
| Goal | Winner's Circle | Legendary, 1,500 | Meets | None | Gold laurel wreath with a crimson ribbon and center | Slow gleam, 18 s lap |
| Trail | Victory Lap | Legendary, 1,500 | Borderline R6, R7: ribbon up to full base width; confetti spun fast for 0.45 s | Redrawn in place | Ribbon about half the base width; confetti settles over 0.8 s with a slow half-turn | In place |
| Floor | Brass Works | Legendary, 1,500 | Meets (approved by owner) | None | — | Yes |
| Pit | Sideline | Standard, 750 | Meets (approved by owner) | None | — | No |
| Boundary | Brass | Rare, 1,000 | Meets (approved by owner) | None | — | No |

### Lava Flow (8,250 coins)

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Lava | Legendary, 1,500 | Meets | None | Crust plates drift one turn in about 90 s | Slow |
| Goal | Inferno | Legendary, 1,500 | Borderline R6: rim flames flickered 40% on a 2.6 s period; vent breathed 25% | Adjusted | Flames change about 20% over 5 s; vent breathes 16% | Slow, 20 fps |
| Trail | Fire | Legendary, 1,500 | Meets (approved by owner) | None | — | As before |
| Floor | Ember | Standard, 750 | Borderline R5, R7: half of all plate edges were bright fissures at 70%, a glowing net that competed with coins | Redrawn | About one edge in six glows, at 34%; glow spots only where a fissure is, under 10% | Slow pulse |
| Pit | Evil | Legendary, 1,500 | Borderline R6, R7: seams pulsed 33%; bright eyes with halos lit the core; blink every 6 s | Adjusted | Seams pulse about 16%; eyes are dim embers; blink about every 9 s | Slow |
| Boundary | Molten | Legendary, 1,500 | Meets (approved by owner) | None | — | As before |

### Aurora (8,500 coins)

Audit only. Nothing changed and no concerns.

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Aurora | Legendary, 1,500 | Meets (approved by owner); reference collection | None | — | As before |
| Goal | Aurora | Legendary, 1,500 | Meets (approved by owner); reference collection | None | — | As before |
| Trail | Aurora | Legendary, 1,500 | Meets (approved by owner); reference collection | None | — | As before |
| Floor | Aurora | Legendary, 1,500 | Meets (approved by owner); reference collection | None | Dark sky with three faint ribbons | Very slow, 15 fps |
| Pit | Aurora | Rare, 1,000 | Meets (approved by owner); reference collection | None | Full of aurora curtains around a dark middle | Slow sway, 20 fps |
| Boundary | Aurora | Legendary, 1,500 | Meets (approved by owner); reference collection | None | — | As before |

### Space Traveler (9,000 coins)

The owner had not graded this set. The Space pit now stays visible, frozen, under Reduce Motion; it used to disappear.

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | UFO | Legendary, 1,500 | Fails R3, R6: belly lights flickered about once a second; green dome matched nothing in the set | Redrawn | Saucer with a cyan under-glow, lit rim and cyan dome matching the hull lights; lights stay at least 60% lit | One soft swell about every 6 s; 20 fps |
| Goal | Quasar | Legendary, 1,500 | Borderline R6: jets turned in 12.6 s, sparks jittered, core 22% of the radius | Redrawn in place | Same look; core 30% of the radius; shimmer dimmer | Jets turn once in about 26 s; 20 fps |
| Trail | Comet | Legendary, 1,500 | Fails R3, R8: orange fire cooling to gray smoke, a twin of the Fire and Smoke trails and off the set's palette | Redrawn | A cold comet: white to cyan to deep blue line, faint dust haze, short dust streaks | Fade only |
| Floor | Moon | Legendary, 1,500 | Borderline R6, R7: craters up to 56 pt wide could read as pits; 30 fps | Redrawn in place | Smaller, paler craters (under 38 pt), small rocks with shadows, fine cracks | Slow light drift; 12 fps |
| Pit | Space | Legendary, 1,500 | Fails R5, R6, R7: flat starfield with no ledges, stars across the core, a shooting star every 3.5 s | Redrawn | Pale-violet lip, four indigo steps, black core 40% of the width, dim stars on the outer steps only | Slow twinkle; one faint shooting star every 11 s; 20 fps |
| Boundary | Starship Hull | Legendary, 1,500 | Meets | None | Gunmetal plating with slow cyan running lights | Slow lamp pulse, 33 s lap |

## Scheduled collections

The owner had not graded these five, and the quality round did not touch them. Several were assembled from leftover pieces when collections were made unique, so each was rebuilt as one look.

### Candyland (6,000 coins; Feb 11, 2027)

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Candy | Legendary, 1,500 | Meets | None | Peppermint pinwheel | Yes, slow turn |
| Goal | Candy | Standard, 750 | Borderline R5: flat two-color | Redrawn | Shaded stripes, bevel, white well with a red ring, gloss arc | No |
| Trail | Bubblegum | Standard, 750 | Meets | None | — | As before |
| Floor | Sugar | Standard, 750 | Borderline R1, R5: a dense sparkle pattern, not a place | Redrawn | Pale pink icing with sugar drifts, faint knife swirls, sparse sprinkles and sugar pearls | No |
| Pit | Syrup | Standard, 750 | Fails R5, R7: one gradient, drips on the top edge only | Redrawn | Cut-cake steps from a pink frosting rim through caramel, toffee and chocolate to near-black; drips all round | No |
| Boundary | Candy | Legendary, 1,500 | Borderline R6: stripes scrolled at 16 pt/s; glint pulsed twice a second | Redrawn | Same candy cane; stripes creep at 5 pt/s; glint laps in about 35 s | Yes; frozen but striped under Reduce Motion |

### Nightclub (9,000 coins; Feb 11, 2027)

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Disco Ball | Legendary, 1,500 | Borderline R6: whole-ball twinkle over a flat grid | Redrawn | Mirror ball in latitude rows with per-mirror glints and faint magenta and cyan reflections | Yes, one column per 3 s |
| Goal | Vinyl | Legendary, 1,500 | Mosaic failed R2, R6: wrong theme, too many hues | Replaced Mosaic | A record with grooves, a fixed sheen, a magenta label and a spindle hole | Yes, label turns once per 24 s |
| Trail | Dance Steps | Legendary, 1,500 | Rainbow was borderline R2, R6: wrong theme | Replaced Rainbow | Thin dim line; about one mark in three leaves a lit floor tile that dims | Fade only |
| Floor | Disco | Legendary, 1,500 | Fails R6, R7: full-screen spectrum cycle every 3 s | Redrawn | Dark glass panels; about a third glow softly, at most 16%, on 14 to 22 s cycles | Yes, 12 fps; shown still under Reduce Motion |
| Pit | Nightclub | Legendary, 1,500 | Fails R5, R6: big twinkling blobs, no depth | Redrawn | Dark plum steps to a black middle, each step edged with small warm bulbs | Yes, bulbs breathe on 5.5 s |
| Boundary | Marquee | Legendary, 1,500 | Fails R6: bulbs jumped six times a second | Redrawn | Fixed warm bulbs glowing in three groups in turn | Yes, 6 s cycle |

### Golf (8,000 coins; Apr 1, 2027)

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Golf Ball | Epic, 1,250 | Meets | None | — | As before |
| Goal | Hole-in-One | Legendary, 1,500 | Borderline R5: flat | Redrawn | Mowing stripes, collar ring, shaded cup with a white liner, flagstick shadow | As before |
| Trail | Dew Line | Legendary, 1,500 | Air failed R2: wrong theme | Replaced Air | Dark pressed line through dew, with dew drops along both edges | Slow glint on drops |
| Floor | Grass | Legendary, 1,500 | Borderline R1, R6: swaying meadow tufts at 30 fps, not a green | Redrawn | Mown green with slanted stripes, pitch marks, leaves, daisies and a lost tee | No (was animated) |
| Pit | Pond | Legendary, 1,500 | Fails R5, R7: flat gradient, busy caustics, no dark middle | Redrawn | Grass bank, sand shelf, teal steps to near-black, a lily pad by the bank | One dim ripple every 8 s |
| Boundary | Fairway | Standard, 750 | Borderline R1, R5: read as a plain green line | Redrawn | Dark rough with mown stripes and white out-of-bounds stakes with red tops | No |

### Bloom (6,000 coins; Apr 1, 2027)

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Rose | Standard, 750 | Fails R1: plain pink marble | Redrawn | Four rings of petals around a bud spiral | No |
| Goal | Blossom | Epic, 1,250 | Borderline R1, R5 | Redrawn | Sepals, two whorls of notched petals, dark-rose cup, twelve gold-tipped stamens | Yes, turns in 50 s, breathes over 7 s |
| Trail | Rose | Legendary, 1,500 | Meets | None | — | As before |
| Floor | Petal Path | Rare, 1,000 | Parchment failed R2, R5: wrong theme | Replaced Parchment | Pale flagstones with mossy joints and sparse fallen petals in three pinks | No |
| Pit | Deep Rose | Standard, 750 | Parchment failed R2: wrong theme | Replaced Parchment | Rings of petal lobes from a pale pink rim to a near-black maroon heart | No |
| Boundary | Rose | Standard, 750 | Fails R1, R5: flat pink line, no drawing at all | Redrawn | Green briar hedge with leaves, thorns, pink roses and buds | No |

### Ocean (6,000 coins; Jun 3, 2027)

| Slot | Piece | Tier, price | Verdict before | Action | Looks like now | Animates? |
|---|---|---|---|---|---|---|
| Ball | Aquarium | Legendary, 1,500 | Meets | Slowed slightly | Same; fish lap and bob about a third slower | Yes |
| Goal | Ripple | Epic, 1,250 | Borderline R6: a ring every 0.5 s | Redrawn | Three rings with crest and trough around a bright center | Yes, 9 s period |
| Trail | Wake | Standard, 750 | Sky failed R1, R2, R5: a plain line in the wrong theme | Replaced Sky | Pale churned water with a foam line each side that spreads and thins | Edges spread with age |
| Floor | Open Sea | Standard, 750 | Blueprint failed R2: wrong theme | Replaced Blueprint | Deep blue with long swell lines, whitecaps and a small fish school passing | Yes, 12 fps, swell about 4 pt/s |
| Pit | Reef | Standard, 750 | Blueprint failed R2: wrong theme | Replaced Blueprint | Ragged ledges from pale coral sand through orange and pink coral to near-black | No |
| Boundary | Tide | Rare, 1,000 | Borderline R5, R8: thin dashes, close to Breakers | Redrawn | Wet sand inside, teal water outside creeping in and out behind a foam line | Yes, 9 s breath |

## Concerns left for the owner

These pieces were approved in the quality round, so the audit did not change them. Each would draw a question on a fresh grade.

| Piece | Collection | Concern |
|---|---|---|
| Classic White floor, Classic Black pit, Classic Gray boundary | Roll Along | Flat fills by design; R5 would otherwise fail them |
| Mint boundary | Nature | A plain color ring; the weakest piece of the set under R1 and R5 |
| Slate boundary | Sketchbook | A plain color ring, same concern |
| Sideline pit | Champion | A flat dark fill with one white line; no layered depth (R5) |
| Brass Works floor | Champion | Animates at 30 fps; the standard asks 10 to 15 fps for floors |
| Winner's Circle goal | Champion | A ring of leaves, like Nature's Leaf Wreath. Gold metal and a crimson center keep them apart, but they are close (R8) |
| Scribble goal | Sketchbook | The held Doodle goal is also wobbly pencil rings (R8). Fine while Doodle stays held |
| Rose boundary | Bloom | Built like the Holly and Citrus hedges (hedge plus dots), with larger pink blooms; worth a look for R8 |
| Inverted floor | Abyssal Depths | A flat near-black fill; recorded in the standard as the one approved exception to R5 |
| Storm rain | Storm | Slowed to meet R6; may now read as drizzle, not driving rain |

## Side effects to know

- Darker base colors: the Gold Leaf floor is darker, as are the Fog, Midnight and Ember floors from the quality round. Screens that use only the floor color (minigame arenas) are darker too.
- Reduce Motion: the Disco floor, Nightclub pit and Space pit used to disappear under Reduce Motion; they now show, frozen.
- The Grass floor is now still.

## Held pieces

Held pieces were not changed. Each of the 133 has a verdict in `docs/proposals/held-pieces.md`: 46 meet, 48 are borderline and 39 fail.
