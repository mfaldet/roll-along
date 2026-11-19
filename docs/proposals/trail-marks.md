# Trails laid in place

Status: built (not compiled or played yet).

## Why most trails looked towed

Every trail kept a fixed-length list of the ball's recent positions (90 in
play, 120 on Home), trimmed from the tail every frame. Most renderers then
drew each point by its place in that list, counted back from the ball:
"I am the 10th point behind the ball, so I am this wide, this bright, and
my star orbits here." Each frame the list shifted, so every point's look
was recomputed relative to the ball and the whole effect slid along behind
it, like smoke being towed. A trail also never faded while the ball rested,
because nothing was ever removed until new points pushed old ones out.

Forest looked right because its leaves were keyed to where each point was
laid, not to its place in the list.

## The design: one system for every trail

`TrailMarks` (in `RollAlong/Cosmetics.swift`) replaces every trail buffer.

| Rule | Value | Why |
|---|---|---|
| A mark is laid at the ball's position, stamped with when it was laid | | It never moves with the ball afterward |
| Spacing between marks | 4 pt | The same density at any speed; a fast step lays several marks along its path, with interpolated laid times |
| Lifetime of a mark | 1.1 s | About the visible length the old trails had at typical speed (the old lifetimes ranged 0.9 to 1.6 s, and the 90-point list was about 1.5 s) |
| Most marks at once | 128 | A full 1.1 s of path up to about 465 pt/s; above that the oldest drop early |
| Most marks per step | 16 | A respawn jump can't flood the buffer |
| Racer trails in minigames | 0.45 s, 48 marks | Same rule, shorter, so four marbles don't smear the board |

Every renderer draws from the marks alone. A mark's look comes from its own
laid time (a stable seed) and its own age. Effects may change gently in
place while a mark fades (smoke rises and thins, sparks rise, bubbles pop,
flames flicker), but nothing follows the ball. Under Reduce Motion the marks
still appear and fade, with no extra movement.

## Every trail

| Trail | Tier | What it leaves behind | Lasts | Changed? |
|---|---|---|---|---|
| Off | Starter | Nothing | — | No |
| Graphite | Rare | A pencil line broken by short uneven strokes | 1.1 s | Yes: fades from the tail where drawn; strokes no longer shift (they were keyed to list position) |
| Sky | Standard | A plain sky-blue line | 1.1 s | Yes: the line fades from the tail in place instead of a taper dragged behind the ball |
| Forest | Standard | A green line with small leaves | 1.1 s | Slightly: leaves keep one size and fade (they grew with distance from the ball) |
| Bubblegum | Standard | A pink line with small bubbles that pop at the end | 1.1 s | Yes: bubbles fade and pop where laid (they scaled with distance from the ball) |
| Ember | Rare | A glowing orange line with tiny sparks that rise and fade | 1.1 s | Yes: the line fades in place (was dragged); sparks unchanged |
| Gilded | Rare | A glowing gold line | 1.1 s | Yes: fades from the tail in place |
| Raybeam | Rare | A glowing green laser line | 1.1 s | Yes: fades from the tail in place |
| Snake | Rare | A scaled body along the path, head at the ball, shedding from the tail | 1.1 s, +0.5 s per coin | Yes: the body lies where the ball rolled and fades from the tail; the side-to-side slither wave is gone (it moved the body every frame) |
| Ink | Legendary | A pen line with ink blots where the ball lingered | 1.1 s | Yes: fades by age where laid (the tail faded by list position) |
| Fire | Legendary | Small flames that flare, flicker and die down | 1.1 s | Slightly: already in place; now the shared lifetime (was 0.9 s) |
| Ice | Legendary | An icy cut with snow piles that heap, settle and melt | 1.1 s | Slightly: already in place; now the shared lifetime (was 1.4 s) |
| Rose | Legendary | Petals that drop, settle and fade, over a faint stem | 1.1 s | Slightly: already in place; now the shared lifetime (was 1.3 s) |
| Smoke | Legendary | Puffs that swell, curl, rise and thin | 1.1 s | Slightly: already in place; now the shared lifetime (was 1.6 s) |
| Air | Legendary | Soft puffs that billow, lift and fade | 1.1 s | Slightly: already in place; shared lifetime |
| Money Roll | Legendary | A green streak shedding bills that flutter up and fade | 1.1 s | Slightly: already in place; now the shared lifetime (was 1.2 s) |
| Stardust | Legendary | A soft glowing line with stars set beside it that twinkle and fade | 1.1 s | Yes: stars stay beside the mark that laid them (they orbited the trail) |
| Comet | Legendary | Each mark burns white-hot, cools to red, then becomes a rising smoke puff | 1.1 s | Yes: fire and smoke follow each mark's age (fire was always at the ball, smoke always at the tail) |
| Rainbow | Legendary | A spectrum line; each mark keeps its colour, then dissolves into sparkles | 1.1 s | Yes: colours stay where painted (the spectrum rippled along behind the ball) |
| Aurora | Legendary | A teal-to-violet glowing ribbon that shimmers in place | 1.1 s | Yes: each mark's colour shimmers in place (it rippled along the ribbon) |

Every trail now also fades away while the ball rests, and every trail has
the same spacing and lifetime, so they compare fairly in the Shop.

## Where it applies

- Gameplay (`BallGameView`), Home (`HomeView`).
- Replays (`LoadoutDiorama`): the Profile and Game Modes previews, the
  try-on popup, collection popups and the Locker's hold preview. The marks
  are rebuilt from the run's own path and times, fed from the start of the
  clip, so each mark sits exactly where the live game laid it, in world
  space, placed through the camera.
- Shop and Catalog tiles, the Featured Bundle and the Locker grid
  (`ShopTrailCurve`): a ball rolls along the sample curve laying real marks.
  Frozen, it sits near the end with a full fading trail behind it.
- Minigame racer trails (Gold Rush, King of the Hill, Paint Ball, Marble Cup,
  Sumo Survival, Roll Up, and Roll Out, which is hidden): same laying rule and
  fade, drawn as a simple line. Roll Up now stores marks in world space, so
  they scroll with the platforms.

## Performance

- One small buffer per trail, trimmed in place; no per-frame allocation in
  play beyond the two arrays it keeps.
- Marks are capped at 128 in play (a grown Snake gets proportionally more,
  about 300 at its 3-coin maximum), 48 per racer in the minigames.
- Decorations are thinned by each mark's seed (leaves about 1 in 2, sparks
  about 1 in 5, puffs and flames about 7 in 10), so the drawing cost stays
  close to the old trails at typical speed.
- Not measured on a device.
