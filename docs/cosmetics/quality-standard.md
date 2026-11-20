# Cosmetic quality standard

This standard is **binding for every cosmetic that is drawn or changed from now on**: balls, goals, trails, floors, pits and boundaries, in every collection, on sale or held. A piece that does not meet it is fixed, moved or held. It is not shipped as it is. Two things come before every rule and number here: the owner's own direction, and the owner's approvals (see "The owner's direction comes first" and "Locked pieces").

Audits cite the rules by number (R1 to R9) and give each piece one verdict: **meets**, **borderline** or **fails**.

## The rules

| # | Rule |
|---|---|
| **R1** | **It looks like the real thing it is named after.** Not a colored shape with a name. A lemon is lemon-shaped; a storm is cloud, rain and lightning. |
| **R2** | **It fits its collection's theme.** A good-looking piece in the wrong theme is moved to a collection where it belongs. It is not kept where it is. |
| **R3** | **The six pieces of a collection are designed to be equipped together** and must balance as one look: one palette, one light, one level of detail. |
| **R4** | **No stock symbols or icons placed on a shape.** No bolt on a gray ball, no star on a gold ball. The subject is drawn, not labeled. |
| **R5** | **Pits have layered depth. Floors have small, tasteful details. No flat fills.** |
| **R6** | **Motion is slow and calm.** Fast or disorienting motion fails. A piece whose subject naturally moves (water, fire, fog, cloud, aurora) should move. |
| **R7** | **Every piece stays readable in play**, including pits on levels with many small pits. Coins, the goal and the ball are always easy to see. |
| **R8** | **No two pieces look alike.** Two trails that differ only in color, or two pits that share one drawing, fail. |
| **R9** | **A collection carries its feeling.** A storm is frightening. A haunted set is eerie. Winter is cold and deep. |

## The owner's direction comes first

The rules above say what the owner wants. The design numbers further down are only a way to reach it.

- **Where a design number conflicts with a piece the owner approved, or with a direction the owner gave, the owner's direction wins.** Example: the owner asked for a Storm that feels powerful and frightening, with driving rain. If the motion numbers say rain that fast is too fast, the numbers lose.
- **The numbers are guidance for pieces the owner has not graded.** They are not a test an approved piece must pass.
- **An auditor flags a conflict; an auditor does not resolve it by changing the piece.** Write the concern down, say which number or rule it touches, and leave the piece as it is for the owner to judge on screen.
- The owner judges on screen. A verdict made by reading code is a first pass, never the last word.

## Locked pieces

**A piece the owner has approved is locked.**

- An audit may **report a concern** about a locked piece. It must **never change** the piece's look or motion: no redraw, no recolor, no slower or faster motion, no new frame cap, no change to how it behaves under Reduce Motion.
- Only the owner can unlock a piece, by asking for a change to it. After the change, the piece is locked again in its new form.
- Shared drawing code that a locked piece depends on (the trail mark rules, pit depth shading, the boundary clock) is treated the same way: a change that would alter a locked piece needs the owner's say-so.
- A locked piece stays in the collection the owner approved it in, unless the owner moves it.
- **Guard:** `python3 tools/cosmetic-calendar/locked_pieces_check.py` compares the drawing code of every locked piece with the version recorded in `tools/cosmetic-calendar/locked_pieces.json` and fails if any differs. Run it before committing any cosmetic change. Re-record the hashes (`--update`) only after the owner approves a change, and add each newly approved piece to the list.

The 138 locked pieces, as of November 20, 2026. The owner has seen and approved **every piece of the 22 collections on sale or scheduled, and of Roll Along**. "Quality round" marks the 50 pieces approved first (the quality round, plus the three confirmed in the audit correction); "Full review" marks the 86 approved on November 20, 2026, in the form they had that day (after the quality round and the audit); "Approved 2026-11-20" marks the Tree Stump goal and the redrawn Desert floor, approved and locked last.

| Collection | Slot | Piece | id | Approved in | Note |
|---|---|---|---|---|---|
| Roll Along | Ball | Red | `red` | Quality round |  |
| Roll Along | Goal | Target | `target` | Quality round |  |
| Roll Along | Trail | Classic Shadow | `classic` | Quality round |  |
| Roll Along | Floor | Classic White | `classic` | Quality round |  |
| Roll Along | Pit | Classic Black | `classic` | Quality round |  |
| Roll Along | Boundary | Classic Gray | `classic` | Quality round |  |
| Nightclub | Ball | Disco Ball | `disco` | Full review |  |
| Nightclub | Goal | Vinyl | `vinyl` | Full review |  |
| Nightclub | Trail | Dance Steps | `danceSteps` | Full review |  |
| Nightclub | Floor | Disco | `disco` | Full review |  |
| Nightclub | Pit | Nightclub | `nightclub` | Full review |  |
| Nightclub | Boundary | Marquee | `marquee` | Full review |  |
| Golf | Ball | Golf Ball | `golfBall` | Full review |  |
| Golf | Goal | Hole-in-One | `holeInOne` | Full review |  |
| Golf | Trail | Dew Line | `dewLine` | Full review |  |
| Golf | Floor | Grass | `grass` | Full review |  |
| Golf | Pit | Pond | `pond` | Full review |  |
| Golf | Boundary | Fairway | `fairway` | Full review |  |
| Space Traveler | Ball | UFO | `ufo` | Full review |  |
| Space Traveler | Goal | Quasar | `quasar` | Quality round | Restored to its pre-audit drawing code after the audit changed it. |
| Space Traveler | Trail | Comet | `cometTrail` | Quality round | Restored to its pre-audit drawing code after the audit changed it. |
| Space Traveler | Floor | Moon | `moon` | Full review |  |
| Space Traveler | Pit | Space | `space` | Quality round | Restored to its pre-audit drawing code after the audit changed it. |
| Space Traveler | Boundary | Starship Hull | `hull` | Full review |  |
| Winter | Ball | Snowglobe | `snowglobe` | Quality round |  |
| Winter | Goal | Frost | `frost` | Full review |  |
| Winter | Trail | Ice | `ice` | Full review |  |
| Winter | Floor | Snowfield | `twilight` | Full review |  |
| Winter | Pit | Crevasse | `twilight` | Full review |  |
| Winter | Boundary | Ice | `ice` | Full review |  |
| Cosmos | Ball | Nebula | `nebula` | Quality round |  |
| Cosmos | Goal | Galaxy | `galaxy` | Quality round |  |
| Cosmos | Trail | Stardust | `stardust` | Quality round | As adjusted at the owner's direction in the quality round (stars slightly larger and more numerous). |
| Cosmos | Floor | Midnight | `midnight` | Full review |  |
| Cosmos | Pit | Moonlit | `midnight` | Full review |  |
| Cosmos | Boundary | Starlight | `starlight` | Quality round |  |
| Nature | Ball | Jade | `jade` | Quality round |  |
| Nature | Goal | Tree Stump | `treeStump` | Approved 2026-11-20 |  |
| Nature | Trail | Forest | `forest` | Quality round |  |
| Nature | Floor | Meadow | `meadow` | Quality round |  |
| Nature | Pit | Meadow | `meadow` | Quality round |  |
| Nature | Boundary | Mint | `mint` | Quality round |  |
| Fire | Ball | Blaze | `blaze` | Full review |  |
| Fire | Goal | Flame Ring | `flameRing` | Full review |  |
| Fire | Trail | Wildfire | `wildfire` | Full review |  |
| Fire | Floor | Scorched | `scorched` | Full review |  |
| Fire | Pit | Crater | `crater` | Quality round |  |
| Fire | Boundary | Flare | `flare` | Full review |  |
| Water | Ball | Droplet | `droplet` | Full review |  |
| Water | Goal | Whirlpool | `whirlpool` | Full review |  |
| Water | Trail | Splash | `splash` | Quality round |  |
| Water | Floor | Shallows | `shallows` | Full review |  |
| Water | Pit | Deep End | `deepEnd` | Full review |  |
| Water | Boundary | Breakers | `breakers` | Full review |  |
| Storm | Ball | Thundercloud | `thundercloud` | Full review |  |
| Storm | Goal | Storm Eye | `thunderRing` | Full review |  |
| Storm | Trail | Squall | `squall` | Full review |  |
| Storm | Floor | Overcast | `overcast` | Full review |  |
| Storm | Pit | Maelstrom | `maelstrom` | Full review |  |
| Storm | Boundary | Thunderhead | `thunderbolt` | Full review |  |
| Ocean | Ball | Aquarium | `aquarium` | Full review |  |
| Ocean | Goal | Ripple | `ripple` | Full review |  |
| Ocean | Trail | Wake | `wake` | Full review |  |
| Ocean | Floor | Open Sea | `openSea` | Full review |  |
| Ocean | Pit | Reef | `reef` | Full review |  |
| Ocean | Boundary | Tide | `tide` | Full review |  |
| Bloom | Ball | Rose | `rose` | Full review |  |
| Bloom | Goal | Blossom | `blossom` | Full review |  |
| Bloom | Trail | Rose | `roseTrail` | Full review |  |
| Bloom | Floor | Petal Path | `petalPath` | Full review |  |
| Bloom | Pit | Deep Rose | `deepRose` | Full review |  |
| Bloom | Boundary | Rose | `rose` | Full review |  |
| Aurora | Ball | Aurora | `aurora` | Quality round |  |
| Aurora | Goal | Aurora | `aurora` | Quality round |  |
| Aurora | Trail | Aurora | `aurora` | Quality round |  |
| Aurora | Floor | Aurora | `aurora` | Quality round | Look swapped with the pit at the owner's direction in the quality round: dark with a few faint ribbons. |
| Aurora | Pit | Aurora | `aurora` | Quality round | Look swapped with the floor at the owner's direction in the quality round: full of aurora ribbons. |
| Aurora | Boundary | Aurora | `aurora` | Quality round |  |
| Citrus | Ball | Lemon | `lemon` | Full review |  |
| Citrus | Goal | Citrus Slice | `citrusSlice` | Full review |  |
| Citrus | Trail | Zest | `zest` | Full review |  |
| Citrus | Floor | Grove | `grove` | Full review |  |
| Citrus | Pit | Tide Pool | `tidePool` | Full review |  |
| Citrus | Boundary | Citrus | `citrus` | Full review |  |
| Midas | Ball | Fool's Gold | `gold` | Quality round |  |
| Midas | Goal | Bullion | `bullion` | Full review |  |
| Midas | Trail | Gilded | `gilded` | Quality round |  |
| Midas | Floor | Gold Leaf | `goldLeaf` | Full review |  |
| Midas | Pit | Vault | `vault` | Full review |  |
| Midas | Boundary | Gold | `gold` | Quality round |  |
| Sketchbook | Ball | Pencil | `pencil` | Full review |  |
| Sketchbook | Goal | Scribble | `scribble` | Full review |  |
| Sketchbook | Trail | Graphite | `graphite` | Quality round |  |
| Sketchbook | Floor | Paper | `sketch` | Full review |  |
| Sketchbook | Pit | Sketch | `sketch` | Quality round |  |
| Sketchbook | Boundary | Slate | `slate` | Quality round |  |
| Neon | Ball | Neon | `neon` | Quality round |  |
| Neon | Goal | Neon | `neon` | Full review |  |
| Neon | Trail | Raybeam | `raybeam` | Quality round |  |
| Neon | Floor | Grid City | `gridCity` | Full review |  |
| Neon | Pit | Blackout | `graph` | Full review |  |
| Neon | Boundary | Neon | `neon` | Quality round |  |
| Candyland | Ball | Candy | `candy` | Full review |  |
| Candyland | Goal | Candy | `candy` | Full review |  |
| Candyland | Trail | Bubblegum | `bubblegum` | Full review |  |
| Candyland | Floor | Sugar | `sugar` | Full review |  |
| Candyland | Pit | Syrup | `syrup` | Full review |  |
| Candyland | Boundary | Candy | `candy` | Full review |  |
| Haunted | Ball | Ghost | `ghost` | Full review |  |
| Haunted | Goal | Pentagram | `pentagram` | Full review |  |
| Haunted | Trail | Smoke | `smoke` | Quality round |  |
| Haunted | Floor | Fog | `fog` | Full review |  |
| Haunted | Pit | Graveyard | `graveyard` | Full review |  |
| Haunted | Boundary | Phantom | `phantom` | Quality round |  |
| Ancient Temple | Ball | Dune | `dune` | Full review |  |
| Ancient Temple | Goal | Eclipse | `eclipse` | Quality round |  |
| Ancient Temple | Trail | Glyphs | `glyphs` | Full review |  |
| Ancient Temple | Floor | Desert | `desert` | Approved 2026-11-20 |  |
| Ancient Temple | Pit | Canyon | `canyon` | Quality round |  |
| Ancient Temple | Boundary | Sandstone | `sandstone` | Full review |  |
| Abyssal Depths | Ball | Trench | `trench` | Quality round |  |
| Abyssal Depths | Goal | Vortex | `vortex` | Quality round |  |
| Abyssal Depths | Trail | Ink | `ink` | Quality round |  |
| Abyssal Depths | Floor | Inverted | `inverted` | Quality round |  |
| Abyssal Depths | Pit | Sea Vent | `vent` | Full review |  |
| Abyssal Depths | Boundary | Abyss | `abyss` | Quality round |  |
| Champion | Ball | Trophy | `trophy` | Full review |  |
| Champion | Goal | Winner's Circle | `winnersCircle` | Full review |  |
| Champion | Trail | Victory Lap | `victoryLap` | Full review |  |
| Champion | Floor | Brass Works | `brass` | Quality round |  |
| Champion | Pit | Sideline | `sideline` | Quality round |  |
| Champion | Boundary | Brass | `brass` | Quality round |  |
| Lava Flow | Ball | Lava | `lava` | Full review |  |
| Lava Flow | Goal | Inferno | `inferno` | Full review |  |
| Lava Flow | Trail | Fire | `fire` | Quality round |  |
| Lava Flow | Floor | Ember | `ember` | Full review |  |
| Lava Flow | Pit | Evil | `evil` | Full review |  |
| Lava Flow | Boundary | Molten | `molten` | Quality round |  |

**Pending the owner's approval:** none. Every piece of Roll Along and of the 22 collections is locked (138 pieces).

To lock a pending piece after approval: `python3 tools/cosmetic-calendar/locked_pieces_check.py --lock "Nature:Goal"` (the key is `"<Collection>:<Slot>"`), then add its row to the table above. The check fails if any piece of these collections is neither locked nor pending, so a new or replaced piece cannot ship unreviewed.

Approved names: Roll Along's trail, floor, pit and boundary are named Classic Shadow, Classic White, Classic Black and Classic Gray.

## Standing technical rules

These were agreed earlier and still apply to every piece.

- **Drawn in code**, in the same drawing systems as the existing pieces. No image files.
- **Collision shapes never change.** A ball may look non-round, but it is drawn inside the same circle and plays exactly as before.
- **Reduce Motion freezes everything.** The art stays visible on a clear frame; nothing moves or flashes.
- **No stutter on older iPhones.** Animated pieces use a frame cap and precomputed, seeded geometry. No large arrays built every frame.
- **Internal ids are stable.** A redrawn piece keeps its id, so owners keep it.
- **Pits read as holes** (dark middle, clear rim). **Goals read as goals** (a clear center where the ball finishes).
- **Every piece on sale belongs to one full collection** (all six slots filled). Everything else is held.
- **No piece is in two collections.**
- Marks left by a trail stay where they were laid and fade there. They never follow the ball.

## Reference pieces

These are the pieces rated best in the game. The notes below come from reading their drawing code. Use them as the model.

Period means the time for one full cycle of a motion. "Additive" means the layer adds light to what is under it, so it glows on dark and vanishes where it is transparent.

### Nebula ball (Cosmos)

- **Layers (4):** a dark purple-to-black sphere; four large soft color clouds, added as light; seven tiny white stars; one soft highlight at the top left.
- **Palette:** four related hues (pink, violet, blue, warm orange) on a near-black base. The base never rises above about 20% brightness, so the clouds glow.
- **Depth:** the clouds overlap and blend, which reads as gas at different distances. The highlight is the only hard cue that it is a sphere.
- **Detail:** low. Seven stars, each 2% of the radius.
- **Motion:** each cloud drifts by 6 to 8% of the radius and swells by 10%, on periods of 12 to 21 seconds. Stars twinkle on a 2.5-second period.
- **Why it works:** nothing is a symbol. It is a nebula because of how light is layered, not because of a drawn outline.

### Galaxy goal (Cosmos)

- **Layers (3):** a dark purple-black disc; two spiral arms of 40 dots each, added as light; a bright white core.
- **Palette:** blue to violet only (a narrow hue band), plus white at the center.
- **Depth and target:** dots get larger and brighter toward the middle, and the core is 28% of the radius. The eye is pulled to the exact spot the ball finishes.
- **Motion:** the whole spiral turns once every 21 seconds. The hue shimmer along the arms has a 6-second period.
- **Why it works:** it is the calmest spinning goal in the game, and the brightest point is the target.

### Stardust trail (Cosmos)

- **Layers (2):** a thin pale-violet glowing line (half the base width); small four-point stars beside it, on about 6 marks in 10.
- **Palette:** one pale violet and one warm white.
- **Motion:** stars twinkle in place on a 1.6-second period and shrink as their mark ages. Marks last 1.1 seconds. Nothing travels with the ball.
- **Why it works:** the line shows the path, and the stars are offset to the side, so the ball is never hidden. It matches the Nebula ball's stars and the Starlight boundary's stars.

### Starlight boundary (Cosmos)

- **Layers (2):** 14 small star points spaced unevenly around the rim; one short shooting star.
- **Palette:** one cool white.
- **Motion:** each star brightens and dims on its own 2-to-6-second period. The shooting star takes 14 seconds to go around and is visible only for a short part of that time. Capped at 30 frames per second.
- **Why it works:** most of the rim is dark most of the time. The motion is rare and small, so it never pulls the eye from the ball.

### Crater pit (Fire)

- **Layers (5):** bright orange rim, then red-orange, dark red, deep maroon and a near-black core. Each layer is inset by 7% of the pit's shorter side and has a ragged, rocky edge from a fixed seed.
- **Palette:** one hue (orange to red), stepping from full brightness at the rim to about 14% at the core.
- **Depth:** the steps alone build the depth. The core is about 44% of the pit's width, and the game's own depth shading darkens the middle further.
- **Motion:** none. It does not need any.
- **Why it works:** five clean value steps read as a hole at any size, and the bright rim marks the danger edge. This is the model for every pit.

### Neon ball (Neon)

- **Layers (4):** a magenta-to-violet-to-deep-blue sphere with an off-center light; a magenta inner glow; a thin cyan rim; one white highlight.
- **Palette:** magenta and cyan, the two neon-tube colors, over deep blue.
- **Motion:** the glow and rim brighten and dim together on a 2.6-second period, between 60% and 100%. Nothing changes position.
- **Why it works:** it looks like a lit tube bent into a sphere. The only motion is brightness, so it is lively without moving.

### Raybeam trail (Neon)

- **Layers (2):** a single green line that narrows as it ages; a wide soft glow (2.4 times the line's width, at 16% strength) added as light.
- **Palette:** one green.
- **Motion:** none beyond the age fade.
- **Why it works:** it is a laser, and a laser is one clean bright line. Restraint is the design.

### Eclipse goal (Ancient Temple)

- **Layers (4):** a black disc; a soft gold corona, added as light; a thin bright gold ring at 60% of the radius; a pure black center at 55% of the radius.
- **Palette:** black and one gold.
- **Motion:** the corona swells by 6% on a 4-second period.
- **Why it works:** the black center is the target, and the ring frames it. Two colors, one slow breath.

### Canyon pit (Ancient Temple)

- **Layers (6):** six bands of sandstone, each inset by 7.5% of the shorter side, with ragged edges and a thin dark line under each ledge.
- **Palette:** one hue (red-brown). The third band is lighter than its neighbors, as real rock strata are, so it does not read as a plain gradient.
- **Depth:** the dark line under each ledge is what turns stripes into steps. The core is about 25% of the width and is the darkest value.
- **Motion:** none.
- **Why it works:** same structure as Crater, different material. It proves the layered-ledge approach carries any theme.

### Snowglobe ball (Winter)

- **Layers (5):** see-through glass that is clear in the middle and frosted at the rim; a refraction glow at the bottom right; 22 six-armed snowflakes; 52 fine snow dots; a bright rim line.
- **Palette:** white on cool blue glass. One hue.
- **Depth:** the glass is drawn as glass, so the floor shows through the middle. That is what makes it a globe and not a white ball.
- **Motion:** snow swirls inside, each flake on its own orbit of about 3 to 5 seconds.
- **Why it works:** the motion is the fastest of any reference piece, and it still feels calm because it is small, white on white, and held inside the ball. Motion inside a ball can be livelier than motion on a floor or a boundary.

### Aurora collection

One idea, six times: **green-to-violet light on a dark night**. Every piece uses the same three or four hues, and every piece keeps most of its area dark.

- **Aurora ball.** A dark night-sky sphere; aurora light added over it in patches that fade fully in and out on periods of 19 to 27 seconds, while the curtains sway on 16-to-19-second periods; dark edges so it reads as a sphere; eight small twinkling stars; one small highlight.
- **Aurora goal.** A breathing teal halo (4-second period); a deep night disc at 74% of the radius; four drifting light-clouds inside it (11 to 19 seconds); a bright core at the center; a teal rim with one glint that circles every 7 seconds. The bright core is the target.
- **Aurora trail.** A glowing ribbon whose hue runs from teal-green to violet. Each mark keeps the place it was laid and shimmers slowly (8-second period). A bright core shows only on the freshest part.
- **Aurora floor.** Dark, with dim still stars and three sparse ribbons. Each ribbon is drawn three times (wide at 5% strength, medium at 9%, thin at 16%), so it is faint. The ribbons take about 60 to 80 seconds to cross one wave. Capped at 15 frames per second. Pits, coins and the goal stay far brighter than the floor.
- **Aurora pit.** A near-black depth with a few stars, filled with three to seven tall curtains running green to teal to violet. Curtains sway on 12-to-18-second periods. Capped at 20 frames per second. The middle is kept dark so it still reads as a hole.
- **Aurora boundary.** Three soft, blurred curtains (green, teal, violet). Two travel in opposite directions, taking 29 and 37 seconds to go around, and breathe on a 7-second period.

**What makes the set work:** the busiest pieces (pit, ball) are small, and the largest piece (floor) is the quietest. Nothing in the set is brighter than the ball's own light.

### Abyssal Depths collection

One idea: **black water with a little living light**. Blue-black everywhere, with small points of teal glow.

- **Trench ball.** A deep navy sphere; seven clusters of small teal and green-cyan dots, each with a soft halo, pulsing on 10-to-18-second periods; a dark edge; one faint cyan highlight.
- **Vortex goal.** Still. Four pale-blue spiral arms curl three and a half radians into a bright center that is 24% of the radius. The center is the target.
- **Ink trail.** Near-black ink. The line is thin while the ball moves and swells into a blot (up to about three times the base width) where the ball lingers. It holds full strength, then fades over the last 40% of its life.
- **Inverted floor.** A plain near-black field with no overlay. It is the one flat fill among the references. It works only because the rest of the set supplies the detail and the black makes every glow stronger. **Do not copy this for other sets; R5 still applies.**
- **Sea Vent pit.** Four basalt ledges, each inset by 7.5% of the shorter side, with ragged edges; blue-green glow specks on the upper ledges, pulsing on an 8-second period; a dull orange vent mouth around a black throat, glowing on a 7-second period; six small bubbles that rise over about 6 seconds each. Capped at 20 frames per second.
- **Abyss boundary.** Still. A blurred black shadow that reaches a few points into the play area, plus a one-point blue edge at half strength. The wall looks deep rather than decorated.

**What makes the set work:** one warm accent in the whole set (the vent's orange) against blue-black. The glow is small and slow, like light from living things, which is what gives the set its feeling.

## What the references have in common

1. **Light is built in layers.** Every reference has at least three layers: a dark base, a subject, and a light or glow. None is a single fill with a shape on it.
2. **One hue family, one accent.** Most use one or two hues. The richest (Nebula, Aurora) use four related hues on a near-black base.
3. **Most of the area is quiet.** Detail and motion sit in a small part of the piece. The brightest point of a goal is its target.
4. **Motion is slow, small or contained.** Large surfaces move over tens of seconds. Short periods are used only for tiny things (a star twinkling) or inside a ball.
5. **Pits step down.** Four to six ledges, each a clear value step, ending in a dark core.
6. **The set shares its palette and its light.** A piece is recognizable as part of its collection without its name.

## How to apply

Run this for every piece. Record the verdict and the rule numbers.

**First: is the piece locked?** If it is in the "Locked pieces" list, write down any concern and stop. Do not change it. If a number below conflicts with something the owner asked for, write the conflict down and leave the piece alone.

1. **Name test (R1, R4).** Cover the name. Would a player say what it is? If it only works with the label, or it relies on a symbol, it **fails**.
2. **Theme test (R2, R9).** Does it belong to this collection's subject and feeling? If it is good but belongs elsewhere, mark it **move**.
3. **Set test (R3).** Picture all six equipped. Same palette family? Same light? Is one piece much louder or much plainer than the rest?
4. **Structure test (R5).** Count the layers. A pit needs ledges and a dark core. A floor needs small details. A single flat fill **fails** (the Inverted floor is the one approved exception).
5. **Motion test (R6).** Check the periods against the numbers below. Does a subject that naturally moves stand still? Does anything flash, spin or scroll fast?
6. **Play test (R7).** Picture the pit at 24 to 30 points wide, repeated across a level. Picture coins and the goal on the floor. Still clear?
7. **Twin test (R8).** Is there another piece in the same slot with the same drawing in a different color?

**Verdicts**

- **Meets:** passes all seven tests.
- **Borderline:** passes the name and play tests, but is weak on one of R3, R5, R6 or R8. Fix it.
- **Fails:** breaks R1, R4 or R7, or breaks two or more other rules. Redraw it, move it or hold it.

## Numbers to design to

These come from the reference pieces. They are guidance for pieces the owner has not graded; the owner's direction and approvals override them (see "The owner's direction comes first").

**Motion periods**

| What moves | Target | Fails |
|---|---|---|
| Large drift on a floor (ribbons, fog, water light) | 30 to 80 seconds per cycle, or under about 8 points per second | Visible scrolling; anything a player could track with the eye |
| Drift inside a ball, goal or pit | 10 to 30 seconds | Under 5 seconds |
| A goal turning | One turn in 20 seconds or more | One turn in under 10 seconds |
| Breathing or pulsing glow | 4 to 8 seconds, changing by no more than about 20% | Flicker; changes over 40% |
| Something circling a boundary | 14 to 40 seconds per lap | Under 8 seconds |
| Twinkles and glints | 1.5 to 3 seconds, only on elements under about 2% of the piece | Twinkling across the whole piece |
| Rare events (lightning, a shooting star, a blink) | At most once every 6 to 12 seconds, soft rise and fall | Strobing; hard on-off flashes |

**Frame caps**

| Slot | Cap |
|---|---|
| Floors | 10 to 15 frames per second |
| Pits and goals | 20 |
| Boundaries | 30 |
| Shop tiles | 15 |
| Previews and try-on | 30 |

**Pits**

- 4 to 6 layers, each inset by 6 to 8% of the pit's shorter side.
- Each layer is a clear step darker than the one outside it. A thin dark line under each ledge helps.
- The dark core is at least 20 to 25% of the pit's width, and its brightness is at most about 15%.
- The rim is the brightest part.
- Decoration (glow specks, bubbles, curtains) stays out of the core or stays dim there.

**Floors**

- Details are small and sparse: a few per screen-width, not a pattern that fills the screen.
- Light added over a floor stays at or under about 16% strength at its brightest line, and under about 10% for wide glows.
- The floor's brightest detail is clearly dimmer than a coin and than the pit rim.
- Dark floors need pits with a bright rim. Light floors need pits with a dark rim.

**Goals**

- A clear center at 24 to 55% of the radius: either the brightest point (Galaxy, Vortex, Aurora) or a pure dark disc inside a bright ring (Eclipse).
- No more than two or three hues.

**Trails**

- The line is about half the base width. Decorations sit beside the path, on about half of the marks.
- Marks last 1.1 seconds and fade where they were laid.

**Palette**

- One hue family plus at most one accent per piece.
- Up to four related hues only on a near-black base (under about 20% brightness).
- One warm accent per cool set, or one cool accent per warm set, at most.
