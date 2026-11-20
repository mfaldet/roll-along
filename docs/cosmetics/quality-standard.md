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

The 50 locked pieces, as of November 20, 2026 (approved in the quality round, plus the three confirmed in the audit correction):

| Collection | Slot | Piece | id | Note |
|---|---|---|---|---|
| Roll Along | Ball | Red | `red` |  |
| Roll Along | Goal | Target | `target` |  |
| Roll Along | Trail | Classic Shadow | `classic` |  |
| Roll Along | Floor | Classic White | `classic` |  |
| Roll Along | Pit | Classic Black | `classic` |  |
| Roll Along | Boundary | Classic Gray | `classic` |  |
| Nature | Ball | Jade | `jade` |  |
| Nature | Trail | Forest | `forest` |  |
| Nature | Floor | Meadow | `meadow` |  |
| Nature | Pit | Meadow | `meadow` |  |
| Nature | Boundary | Mint | `mint` |  |
| Fire | Pit | Crater | `crater` |  |
| Water | Trail | Splash | `splash` |  |
| Sketchbook | Trail | Graphite | `graphite` |  |
| Sketchbook | Pit | Sketch | `sketch` |  |
| Sketchbook | Boundary | Slate | `slate` |  |
| Neon | Ball | Neon | `neon` |  |
| Neon | Trail | Raybeam | `raybeam` |  |
| Neon | Boundary | Neon | `neon` |  |
| Haunted | Trail | Smoke | `smoke` |  |
| Haunted | Boundary | Phantom | `phantom` |  |
| Cosmos | Ball | Nebula | `nebula` |  |
| Cosmos | Goal | Galaxy | `galaxy` |  |
| Cosmos | Trail | Stardust | `stardust` | As adjusted at the owner's direction in the quality round (stars slightly larger and more numerous). |
| Cosmos | Boundary | Starlight | `starlight` |  |
| Aurora | Ball | Aurora | `aurora` |  |
| Aurora | Goal | Aurora | `aurora` |  |
| Aurora | Trail | Aurora | `aurora` |  |
| Aurora | Floor | Aurora | `aurora` | Look swapped with the pit at the owner's direction in the quality round: dark with a few faint ribbons. |
| Aurora | Pit | Aurora | `aurora` | Look swapped with the floor at the owner's direction in the quality round: full of aurora ribbons. |
| Aurora | Boundary | Aurora | `aurora` |  |
| Champion | Floor | Brass Works | `brass` |  |
| Champion | Pit | Sideline | `sideline` |  |
| Champion | Boundary | Brass | `brass` |  |
| Lava Flow | Trail | Fire | `fire` |  |
| Lava Flow | Boundary | Molten | `molten` |  |
| Winter | Ball | Snowglobe | `snowglobe` |  |
| Ancient Temple | Goal | Eclipse | `eclipse` |  |
| Ancient Temple | Pit | Canyon | `canyon` |  |
| Midas | Ball | Fool's Gold | `gold` |  |
| Midas | Trail | Gilded | `gilded` |  |
| Midas | Boundary | Gold | `gold` |  |
| Abyssal Depths | Ball | Trench | `trench` |  |
| Abyssal Depths | Goal | Vortex | `vortex` |  |
| Abyssal Depths | Trail | Ink | `ink` |  |
| Abyssal Depths | Floor | Inverted | `inverted` |  |
| Abyssal Depths | Boundary | Abyss | `abyss` |  |
| Space Traveler | Goal | Quasar | `quasar` | Restored to its pre-audit drawing code after the audit changed it. |
| Space Traveler | Trail | Comet | `cometTrail` | Restored to its pre-audit drawing code after the audit changed it. |
| Space Traveler | Pit | Space | `space` | Restored to its pre-audit drawing code after the audit changed it. |

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
