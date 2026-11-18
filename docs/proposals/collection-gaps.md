# Every collection is a complete set

Every cosmetic collection now carries one of each slot: ball, goal, trail,
floor, pit, boundary and music. This file records what was missing and what
was added. `tools/cosmetic-calendar/bundle_rarity.py` prints the live table
(slots, rarity, full price) straight from `RollAlong/Cosmetics.swift`.

## What counts as a collection

- **Collections:** the 66 entries in `CosmeticBundle.catalogue`. That covers:
  - the permanent collections;
  - the 16 seasonal collections;
  - the launch gift collections;
  - the 8 Challenge Track rewards.
- **Starter Pack:** this in-app purchase grants the Aurora collection, so it
  is complete once Aurora is.
- **Ball packs:** Planets, Sports Balls and Vintage Glass (`BallPack.catalogue`)
  are separate. They hold balls only by design and are not collections, so
  they are unchanged.
- **The Planets collection:** this is a different thing from the Planets ball
  pack. It sits in the collection catalogue and on the release calendar
  (Mar 11, 2027), so it was treated as a collection and completed.

## Before

| Slot | Collections missing it |
|---|---|
| Boundary | **all 66.** `CosmeticBundle` had no boundary field at all. |
| Trail | Paper World. Its Graphite trail, the free default, was left out of the list. |
| Goal, trail, floor, pit, music | Planets, which held only its 9 planet balls. |
| Ball | none |

## Added

**New items: 35 boundaries, and nothing else.** The other gaps were filled
with existing items:
- **Paper World** now lists its Graphite trail. It is the default everyone
  owns, so it costs nothing.
- **Planets** gets the space pieces that already existed: Galaxy goal,
  Stardust trail, Midnight floor, Space pit and Celestial music.

**Music:** no new tracks were needed. Note that music items are names only
today; no audio plays for any track, old or new.

### Boundaries by collection

Boundaries marked "(existing)" were reused. All others are new.

| Collection | Boundary | Look |
|---|---|---|
| Hellfire, Lava Flow, Magma Core | Molten ★ | dark crust, glowing lava seams creeping around, flaring cracks |
| Heavens | Cloud | pale cloud white-blue |
| Nightclub, Arcade, Neon | Neon (existing) | |
| Paper World, Back to School | Notebook | ruled-paper blue |
| Golf, Soccer, Diamond | Fairway | fresh pitch green |
| Planets, Space Travel, Cosmos, Oracle | Starlight ★ | night-blue rim, twinkling stars, a slow shooting star |
| Winter | Ice (existing) | |
| Nature, Earth Day | Mint (existing) | |
| Ocean, Aquarium | Tide | sea teal |
| Velvet Night | Velvet | deep plum |
| Golden Hour | Sunset | warm amber-coral |
| Bloom, Sweetheart | Rose | rose pink |
| Noir | Ink | inky charcoal |
| Aurora (Starter Pack) | Aurora ★ | green and violet curtains drifting both ways |
| Citrus | Citrus | lemon-lime |
| Midas, Champion | Gold (existing) | |
| Sketchbook | Slate (existing) | |
| Zen Garden, Dune | Sand (existing) | |
| Eclipse | Corona ★ | black rim, gold halo, one travelling flare |
| Pastel, Spring Fling | Pastel | soft lilac |
| Realistic Marble | Marble | polished white stone |
| Tempest, Plasma Globe | Storm ★ | rain streaks and sudden lightning flashes |
| Candyland | Candy (existing) | |
| Haunted | Phantom | ghostly pale green |
| Summer Vibes | Sky (existing) | |
| Halloween | Pumpkin | pumpkin orange |
| Winter Wonderland | Holly | holly green |
| St. Patrick's | Shamrock | clover green |
| Countdown (New Year) | Confetti ★ | four-color confetti dashes scrolling |
| Star-Spangled | Star-Spangled ★ | red and white bunting on navy, twinkling star |
| Día de los Muertos | Marigold | marigold orange |
| Harvest Moon, Oktoberfest | Autumn | russet |
| Lunar New Year | Lantern | lacquer red |
| Mardi Gras, Lava Lamp | Orchid (existing) | |
| Pride | Rainbow ★ | the full spectrum rotating around the rim |
| Full Court | Hardwood | court maple |
| Billiards Hall, High Roller | Mahogany | table-rail wood |
| Ancient Temple | Sandstone | carved terracotta |
| Abyssal Depths | Abyss | deep-sea navy |
| Crystal Cavern, Geode | Amethyst | crystal violet |
| Midnight Carnival | Marquee ★ | carnival bulbs chasing around the rim |
| Quicksilver | Chrome | mirror silver |
| Cathedral | Stained Glass ★ | jewel-colored panes glowing in turn |
| Neon City | Circuit (existing) | |
| Clockwork | Brass | polished brass |

★ = animated (Legendary).

**Counts by tier:** 14 Standard, 11 Rare and 10 Legendary.

## Pricing rule

New boundaries follow the existing boundary tiers. The price comes from the
tier, as for every cosmetic:

| Tier | Price | Boundaries |
|---|---|---|
| Standard | 750 coins | solid themed walls |
| Rare | 1,000 coins | richer or material hues (wood, stone, metal, deep sea) |
| Legendary | 1,500 coins | animated border renderer, like Obsidian, Candy and Circuit |

**Rarity bands kept:** animated (Legendary) boundaries only go to collections
that are already Legendary.
- No collection's rarity band changed: there are still 4 Standard, 19 Rare and
  43 Legendary.
- The post-tutorial gift pool (Nature, Citrus, Sketchbook and Midas) stays
  Standard.

**Collection prices** rise by the boundary's price. Planets also rises by its
five new pieces, from 13,500 to 21,500 coins full price. Aurora's full value
is now 9,750 coins.

## Release calendar

- **No change to dates or SQL.** There are no new collection ids, so step 11
  is unchanged.
- **New boundaries follow their collection:** a boundary releases with its
  earliest permanent collection, the same rule as every other slot.
  - Boundaries that are only in seasonal collections release by the
    existing loose-item rule.
  - Players who own an item always keep it.
- **Existing boundaries now follow their collections too:**
  - Slate, Mint and Gold: now available at launch (Sketchbook, Nature and
    Midas). Before, they arrived with the loose drops.
  - Sand: Jan 14 (Zen Garden). Neon: launch (the Neon challenge reward).
  - Candy: Feb 11 (Candyland). Ice: launch (Winter reward).
  - Orchid: May 6 (Lava Lamp).
  - **Circuit moves from launch to Nov 11, 2027 (Neon City).** This is the
    one existing boundary that becomes later.
  - Ember and Obsidian are in no collection and stay available at launch.
