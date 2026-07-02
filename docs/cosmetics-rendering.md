# Cosmetics & Ball-Skin Rendering

How every ball appearance is defined, rendered, priced, and unlocked. This is
the canonical reference for the cosmetics system — read it before adding or
changing a ball skin.

---

## One renderer, everywhere

There is exactly **one** view that draws a ball: **`BallSkinView`**.

```swift
BallSkinView(skin: BallSkin, diameter: CGFloat)
```

Every surface that shows a ball routes through it — the home roaming ball, the
launch animation, the shop grid, the Settings cosmetics picker, the in-game
player marble **and** AI rivals, the mini-ball pills, the result/share card, the
reward preview, Pinball, and the goal/portal previews. This is deliberate: a
skin must look **identical** everywhere (only the `diameter` changes). If you
ever find a ball being drawn another way (a raw `Circle().fill(...)`, a
per-mode marble func), route it back through `BallSkinView`.

`BallSkinView.body` is a single `switch` over `BallSkin`. As of the full skin
audit it is **exhaustive — there is no `default`**. Adding a new skin will fail
to compile here until you give it a case (same as the `colors` and `tier`
switches). That is intentional: no skin should silently fall back to a flat
gradient.

---

## The skin catalogue (52 skins)

`BallSkin` (in `BallSkin.swift`) is a `String`-raw `CaseIterable` enum. The
`rawValue` is both the display name and the persistence key — **never rename or
reorder existing cases** (it breaks saved ownership/equip state).

Each skin also defines a 4-stop `colors` palette (highlight → mid → shadow →
deep). Bespoke renderers may ignore it; the shared marble/metal/gem renderers
build from it. `colors` is `internal` (not `private`) so `BallSkinView` can read
each skin's palette.

### Renderer families

| Family | Skins | Renderer | Animated |
|---|---|---|---|
| **Mono / blend marbles** | red, blue, green, purple, rose, coral, mint, slate, lemon, pastel, dune | `glossMarble(colors)` — lit base + glowing Fresnel rim + soft & sharp speculars | no |
| **Metals** | gold, silver, copper | `metalMarble(colors)` — bright-sky / dark-ground two-tone reflection + specular streak + bright rim | no |
| **Gems** | jade, ruby | `gemMarble(colors)` — translucent body, inner glow, cut-gem facet glints, bright rim | no |
| **Planets** | earth, mars, mercury, jupiter, neptune, venus, uranus | `planet(palette, bands:mottle:spot:poles:)` — lit sphere + latitude bands (gas giants) / surface mottle (rocky) / polar caps (Mars) / storm spot + terminator + specular | no |
| **Cosmic / electric** | galaxy, nebula, opal, neon | bespoke `galaxyCanvas` / `nebulaCanvas` / `opalCanvas` / `neonCanvas` — spiral starfield, drifting gas clouds, shifting iridescence, pulsing neon | **yes** |
| **Diamond (IAP)** | diamond | bespoke `diamondCanvas` — faceted brilliant cut + rotating spectral "fire" + twinkling sparkle flares | **yes** |
| **Sports / seasonal / effects** | basketball, soccer, baseball, 8-ball, golf, beachBall, pumpkin, ornament, heartstone, shamrock, confetti, speckledEgg, lava, trench, trophy, storm, candy, ghost, ufo, marble, aquarium, snowglobe, saturn, pluto | one bespoke Canvas each (e.g. `snowglobeCanvas`, `basketballCanvas`, `stormMarble` …) | mixed |

Notable bespoke renderers:
- **snowglobe** — translucent glass sphere with a *blizzard*: ~22 detailed
  6-armed feathered flakes plus ~52 cheap fine-snow dots, all swirling
  (orbit + fast epicycle).
- **aurora** — flowing vertical Northern-Lights curtains (additive) over a
  starry sphere. Coin-buyable Legendary; anchors the Aurora bundle, which the
  legacy Starter Pack IAP grants in full.
- **diamond** — see below.

### Animation

Animated skins wrap their `Canvas` in `TimelineView(.animation)` and read
`@Environment(\.accessibilityReduceMotion) var reduceMotion` — when Reduce
Motion is on, the time term collapses to `0` so the skin renders as a static
frame. Always honour `reduceMotion` in a new animated renderer.

**Performance:** animated skins (cosmic, diamond, snowglobe) cost more than the
static ones. In competitive modes several rivals can each run an animated
canvas at once — if frame drops appear, add a lightweight static variant for the
small in-game rivals while keeping the full animation on the big home/shop
balls. The diamond is **not** in the rival showcase pool (IAP-exclusive), so in
practice only the player's own ball animates it.

---

## Tiers & pricing

`CosmeticTier` is assigned in `Cosmetics.swift` (`BallSkin.tier`, an exhaustive
switch — add new skins here too):

| Tier | Coin price | Examples |
|---|---|---|
| `.starter` | free | red |
| `.standard` | 50 | the 9 mono marbles, gold/silver/copper/jade/ruby |
| `.premium` (Epic) | 200 | galaxy, nebula, opal, pastel, neon, dune, **sports balls** (basketball/soccer/baseball/8-ball/golf) |
| `.exclusive` (Legendary) | 500 *(or bundle/IAP-only)* | the **8 planets**, animated/special skins + all bundle/seasonal/IAP skins |

---

## Exclusivity & how skins are unlocked

`BallSkin.isBundleExclusive` (in `BallSkin.swift`) returns `true` for skins that
**cannot** be bought with coins and are hidden from the standalone shop's Ball
grid until owned. The shop filters with `!isBundleExclusive || isOwned`.

Exclusive skins and their source:

| Source | Skins |
|---|---|
| **Diamond Balls IAP** (`.unlimitedUnlock`) | **diamond** — granted in `StoreKitManager` on purchase *and* restore |
| Starter Pack IAP (legacy) | the full Aurora collection (ball · goal · trail · floor · pit · music), free-granted on purchase *and* restore — aurora itself stays coin-buyable, so it is NOT `isBundleExclusive` |
| Seasonal bundles | beachBall, pumpkin, ornament, heartstone, shamrock, confetti, speckledEgg |
| Challenge-track completion | trophy (Golden Gauntlet) |
| Bundle-only | pluto |

Everything else is coin-purchasable in the shop.

---

## How to add a new ball skin

The compiler will guide you (three exhaustive switches), but the full checklist:

1. **`BallSkin.swift`** — add the `case` (give it a stable `rawValue`; append, don't reorder).
2. **`BallSkin.swift` → `colors`** — add its 4-stop palette (required even if a bespoke renderer ignores it).
3. **`Cosmetics.swift` → `tier`** — classify it (drives coin price).
4. **`BallSkin.swift` → `isBundleExclusive`** — add it to the `true` list *only* if it's bundle/IAP/challenge-exclusive.
5. **`BallSkinView.swift` → `body`** — add a render case (reuse `glossMarble`/`metalMarble`/`gemMarble`/`planet`, or write a bespoke `Canvas`). The build won't compile until you do.
6. **Grant path** — if exclusive, grant it where its source is delivered (e.g. `StoreKitManager` for IAP/bundles, the challenge-completion path for trophy).
7. **Bundle membership** — if it ships inside a bundle, add it to that bundle's `balls: [...]` in `Cosmetics.swift`.

> Gotcha: a render case that needs a math helper must NOT declare a closure-local
> `func` with `return` inside the `TimelineView`/ViewBuilder closure — hoist it to
> a method on the view (the result builder rejects `return`).
