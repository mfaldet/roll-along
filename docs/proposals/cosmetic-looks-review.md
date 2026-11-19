# Cosmetic looks vs. names — review for approval

Status: **proposal, nothing built.** Reviewed from the drawing code at commit 503385f
(BallSkinView, GoalSkinView, trail renderer, FloorOverlayView / PaperFloorOverlayView,
PitOverlayView, BoundaryOverlayView, and each slot's color table). Music is skipped (hidden in 1.0).

Rules once approved: drawn in code; only Rare and Legendary animate, subtly; pits stay readable
as pits (dark, clear edge), goals stay readable as goals; nothing animates under Reduce Motion;
a renamed item keeps its internal id. "Standard" items below get **static** detail only.

## Summary

| Slot | Total | Already delivers | Redraw | Rename | Standard | Rare | Epic |
|---|---|---|---|---|---|---|---|
| Balls | 74 | 73 | 1 | 0 | 0 | 0 | 1 |
| Goals | 33 | 25 | 8 | 0 | 8 | 0 | 0 |
| Trails | 20 | 17 | 3 | 0 | 2 | 1 | 0 |
| Floors | 30 | 19 | 11 | 0 | 11 | 0 | 0 |
| Pits | 29 | 10 | 18 | 1 | 19 | 0 | 0 |
| Boundaries | 48 | 25 | 23 | 0 | 9 | 14 | 0 |
| **All** | **234** | **169** | **64** | **1** | **49** | **15** | **1** |

No Legendary item needs work: every one already has its own renderer that matches its name. The gaps
are almost all Standard floors, pits and boundaries, and the Rare boundaries, which are drawn as one
flat color.

## Balls

Delivers: the mono-color balls have plain color names (Ocean Blue, Rose, Lemon…); metals (Fool's Gold,
Silver, Copper) have a metal sheen; gems (Jade, Ruby) have a gem finish; every Epic and Legendary ball
except Dune has its own renderer.

| Name | Id | Tier | Now | Idea |
|---|---|---|---|---|
| Dune | dune | Epic (1,250) | glossy two-tone marble | Static wind-rippled sand bands in warm tans curving across the ball. |

## Goals

Delivers: Target, Archery, Hole-in-One, Tractor Beam, Inferno, Halo, Doodle, Soccer Net, Aurora, Galaxy,
Crystal, Flame, Blossom, Mosaic, Ripple, Comet, Rainbow, Neon, Eclipse, Plasma, Mirage, Prism, Obsidian,
Quasar (all bespoke), and Slate (a slate-gray target is a fair reading of the name).

| Name | Id | Tier | Now | Idea |
|---|---|---|---|---|
| Frost | frost | Standard | pale-blue concentric target bands | Frost-crystal spikes around the rim, icy white center. |
| Ember | ember | Standard | orange/red target bands | Dark ash rings with glowing coal specks and a hot orange core. |
| Meadow | meadow | Standard | green target bands | A ring of small daisies and grass blades around a green hole. |
| Bullion | bullion | Standard | gold target bands | Stamped gold-coin rim with a ring of small gold bars. |
| Amethyst | amethyst | Standard | purple target bands | Faceted purple crystal points around a dark geode center. |
| Candy | candy | Standard | pink target bands | Peppermint swirl: red-and-white spiral stripes. |
| Vortex | vortex | Standard | static colored rings | Static spiral arms curling into the center. |
| Wormhole | wormhole | Standard | static colored rings | Rings drawn in perspective so it reads as a tunnel. |

## Trails

Delivers: Off, Graphite, Ink, Fire, Ice, Sky (plain sky-blue is a fair color name), Rose, Smoke,
Gilded (gold glow), Stardust, Comet, Rainbow, Snake, Air, Raybeam, Money Roll, Aurora.

| Name | Id | Tier | Now | Idea |
|---|---|---|---|---|
| Forest | forest | Standard | plain green line | Small static leaves set along the line in two greens. |
| Bubblegum | bubblegum | Standard | plain pink line | A row of small static pink bubbles with white highlights. |
| Ember | ember | Rare | orange line with glow | A few tiny sparks that drift off the tail and fade (subtle). |

## Floors

**Built (approved 2026-11-19).** All 11 are drawn in `PaperFloorOverlayView` (BallGameView.swift),
the static floor-texture view the game, the replay and the Shop tiles all use. All are Standard, so
all are still: deterministic seeds, no clock, low-contrast detail. In play the view is `Equatable`, so
each texture is drawn once per layout, not every frame.

Delivers: Classic, Inverted; Twilight, Dusk, Midnight (plain color names that match); Felt (plain
pool-table green reads as felt); Notebook, Graph, Parchment, Sketch, Origami (paper textures); Aurora,
Disco, Grass, Moon, Eclipse, Grid City, Brass Works, Money Full (bespoke, animated).

| Name | Id | Tier | Now | Idea |
|---|---|---|---|---|
| Meadow | meadow | Standard | plain light green | Short grass texture with scattered small white and yellow flowers. |
| Ember | ember | Standard | plain beige | Warm gray ash with scattered dim orange coal specks. |
| Blueprint | blueprint | Standard | plain blue | White grid lines plus a few faint drafting marks and dimension lines. |
| Velvet | velvet | Standard | plain purple | Soft diagonal sheen bands, like crushed velvet. |
| Sunset | sunset | Standard | plain orange | Wide soft bands from gold to orange to pink, top to bottom. |
| Mirage | mirage | Standard | plain sand | Faint wavy heat-haze lines across the sand. |
| Desert | desert | Standard | plain sand | Wind ripples in the sand with soft shadowed crests. |
| Stormcloud | stormcloud | Standard | plain slate | Darker and lighter soft cloud shapes over slate. |
| Sugar | sugar | Standard | plain pale pink | Scattered tiny white sugar-crystal sparkles. |
| Fog | fog | Standard | plain gray | Soft lighter patches of mist (static). |
| Court | court | Standard | plain hardwood color | Hardwood planks with grain and a white court-line arc. |

## Pits

Delivers: Classic, Inverted; Twilight, Dusk (plain color names that match); Evil, Sky, Pond, Space,
Eclipse, Nightclub (bespoke, animated). Every other pit is drawn as one flat color today.

| Name | Id | Tier | Now | Idea or rename |
|---|---|---|---|---|
| Meadow | meadow | Standard | plain dark green | Long dense grass blades leaning in over the rim. |
| Graveyard | graveyard | Standard | near-black | Small gravestones on the far rim and a faint ghost in the depth (static; see flag 1). |
| Ember | ember | Standard | plain dark red | Dim glowing coals at the bottom, ash-gray rim. |
| Notebook | notebook | Standard | plain dark brown | Torn-paper edge with blue ruled lines on the rim. |
| Graph | graph | Standard | plain navy | Graph-paper grid lines shrinking into the depth. |
| Blueprint | blueprint | Standard | plain dark blue | Blueprint grid lines shrinking into the depth. |
| Parchment | parchment | Standard | plain dark brown | Burnt, curled parchment edge around the hole. |
| Sketch | sketch | Standard | plain charcoal | Pencil cross-hatching that darkens toward the center. |
| Origami | origami | Standard | plain dark brown | Folded-paper creases forming a stepped funnel. |
| Velvet | velvet | Standard | plain dark purple | Soft velvet sheen on the inner wall. |
| Sunset | sunset | Standard | plain dark red | Dark gradient from deep red to purple toward the center. |
| Mirage | mirage | Standard | plain dark brown | Faint wavy heat-haze rings inside. |
| Aurora | aurora | Standard | plain deep indigo | A static green-and-violet aurora band glowing in the depth (see flag 2). |
| Canyon | canyon | Standard | plain rust | Layered rock strata stepping down. |
| Downpour | downpour | Standard | plain dark blue | Static rain streaks falling into the dark. |
| Syrup | syrup | Standard | plain dark maroon | Glossy highlight and a few drips over the rim. |
| Sideline | sideline | Standard | plain dark gray | A white out-of-bounds line along the rim. |
| Pocket | pocket | Standard | near-black | Leather pocket rim with a hint of net inside. |
| Midnight | midnight | Standard | pale blue-gray (light, not dark) | **Rename to "Moonlit"**: keep the pale look, which contrasts the dark Midnight floor (see flag 3). |

## Boundaries

**Built (approved 2026-11-19).** All 23 are drawn in `BoundaryOverlayView` (BallGameView.swift),
inside the 4-point border band, over the base stroke. Standard ones and the still Rare ones (Velvet,
Marble, Mahogany, Sandstone, Abyss, Brass) have no clock. The moving Rare ones (Neon, Gold, Ice,
Cloud, Tide, Phantom, Amethyst, Chrome) run at most 30 fps and move slowly; under Reduce Motion they
freeze. Unlike the Legendary walls, these textures stay visible under Reduce Motion
(`Boundary.textureShowsUnderReduceMotion`). As before, the texture fades out while the border shows
the arming, fell (red) and won (green) states. No tier or price changed.

Delivers: Classic; Slate, Mint, Sky, Orchid, Sand, Rose, Ink, Citrus, Pumpkin, Shamrock, Marigold (plain
color names that match); Obsidian, Candy, Circuit and the 10 animated Legendaries added last week
(Molten, Starlight, Aurora, Corona, Storm, Confetti, Star-Spangled, Rainbow, Marquee, Stained Glass).

| Name | Id | Tier | Now | Idea |
|---|---|---|---|---|
| Ember | ember | Standard | flat orange-red | Dark ash ring with scattered glowing coal specks. |
| Notebook | notebook | Standard | flat blue | Ruled blue lines along the wall with one red margin line. |
| Fairway | fairway | Standard | flat green | Short-grass texture with lighter mowing stripes. |
| Sunset | sunset | Standard | flat orange | Gradient around the ring from gold to pink to purple. |
| Pastel | pastel | Standard | flat lilac | Alternating soft pastel segments (pink, mint, lilac, lemon). |
| Holly | holly | Standard | flat dark green | Holly leaves with small red berries at intervals. |
| Autumn | autumn | Standard | flat rust | Scattered fallen leaves in red, orange and gold. |
| Lantern | lantern | Standard | flat red | Small red paper lanterns hung at intervals along a dark cord. |
| Hardwood | hardwood | Standard | flat wood color | Wood-grain lines along the wall. |
| Neon | neon | Rare | flat teal | Glowing neon tube with a soft outer glow and a slow, gentle brightness hum. |
| Gold | gold | Rare | flat gold | Polished gold with a highlight that slowly glides around the ring. |
| Ice | ice | Rare | flat pale blue | Frosted ice with small crystal spikes and a faint glint. |
| Cloud | cloud | Rare | flat pale blue-white | Puffy cloud edge that drifts very slowly. |
| Tide | tide | Rare | flat teal | Small wave crests rolling slowly along the wall. |
| Velvet | velvet | Rare | flat plum | Velvet sheen bands (static). |
| Marble | marble | Rare | flat off-white | Gray veining through white stone (static). |
| Phantom | phantom | Rare | flat pale green | Translucent wall with faint ghostly wisps drifting. |
| Mahogany | mahogany | Rare | flat dark red-brown | Polished mahogany grain with a soft shine (static). |
| Sandstone | sandstone | Rare | flat terracotta | Layered sandstone strata (static). |
| Abyss | abyss | Rare | flat dark blue | Inner shadow so the wall looks deep, with a faint edge glow (static). |
| Amethyst | amethyst | Rare | flat purple | Crystal facets that catch light as a glint passes. |
| Chrome | chrome | Rare | flat silver | Mirror chrome gradient with a gliding reflection. |
| Brass | brass | Rare | flat brass | Brass plate with rivets and a soft sheen (static). |

## Flags for your decision

1. **Graveyard pit ghost.** Your example has a drifting ghost, but Graveyard is Standard, which may not
   animate. Options: (a) a static faint ghost, as listed; (b) move Graveyard to Rare (1,000 coins) so the
   ghost can drift. Option (b) raises the Haunted collection's price by 250.
2. **Aurora pit** is Standard inside the Legendary Aurora collection, so it can't animate. The static
   aurora band keeps it consistent with the other Aurora pieces without changing its price.
3. **Midnight pit** is the only rename. It's drawn pale so it contrasts the dark Midnight floor. Renaming it
   "Moonlit" keeps the look; owners keep it (id stays `midnight`).
4. **Rare boundaries** (14) are the biggest group. Eight use the allowed subtle motion (Neon, Gold, Ice,
   Cloud, Tide, Phantom, Amethyst, Chrome); the other six are static textures.
5. **Collection themes.** Every idea matches its collection's theme (Haunted gets gravestones, Dune gets
   rippled sand, Billiards keeps Felt and gets the Pocket rim). No collection changes rarity band, except
   under flag 1 option (b).
6. **Borderline names kept as plain colors** (no change proposed): Twilight and Dusk (floor and pit),
   Midnight floor, Felt floor, Sky trail, Slate goal, and the 11 plain-color boundaries. Tell me if you
   want any of these drawn too.
