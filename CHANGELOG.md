# Changelog

Notable changes to Roll Along, newest first. Dates are when the work landed on
`main`.

---

## 2026-06 — Cosmetics, lives, launch & Gold Rush overhaul

A large polish pass ahead of the full App Store release. See
[`docs/cosmetics-rendering.md`](docs/cosmetics-rendering.md) and
[`docs/gold-rush-economy.md`](docs/gold-rush-economy.md) for the systems below.

### Ball cosmetics — full audit, every skin upgraded
- **One renderer everywhere.** Every ball (home, launch, shop, Settings,
  in-game player + rivals, mini-pills, result card, reward preview, Pinball)
  now draws through the single `BallSkinView` — a skin looks identical
  everywhere, only the diameter changes.
- **No skin is a flat gradient anymore.** All 52 skins have bespoke or premium
  renderers:
  - New shared **gloss / metal / gem** renderers for the mono marbles, metals
    (gold/silver/copper) and gems (jade/ruby).
  - The 7 **planets** got a textured sphere renderer (bands / mottle / poles /
    storm spot / terminator) — they were flat 2-colour gradients.
  - **galaxy / nebula / opal / neon** got bespoke *animated* renderers
    (spiral starfield, drifting gas clouds, shifting iridescence, pulsing neon).
  - **aurora** reworked into flowing Northern-Lights curtains; **pluto** given
    its own dwarf-planet renderer.
- **Snow Globe** rebuilt as a translucent glass sphere with crisp snowflakes,
  then dialed up to a **blizzard** (~22 detailed flakes + ~52 fine-snow dots,
  all swirling vigorously).
- The `BallSkinView` switch is now **exhaustive** (no `default`) — a new skin
  must be given a renderer or the build fails.

### Diamond Balls now grants a real cosmetic
- New **`BallSkin.diamond`** — a bespoke *animated* brilliant-cut gem (faceted
  crown shimmer + rotating spectral "fire" + twinkling sparkle flares).
- IAP-exclusive: granted by the **Diamond Balls** unlimited-lives purchase (and
  restore), hidden from the coin shop, equippable once owned.

### Lives
- **In-game lives HUD** is now a single marble + count in a capsule; when you
  drop below 6 lives a live `M:SS` countdown to the next free life appears
  (driven by `GameState.timeToNextLife()`).
- Removed the green/gold **completionist ring** that wrapped the home ball.

### Launch animation → whirlpool
- Tapping **Play** now spins the ball down a vortex: it starts exactly where the
  roaming home ball sits, leaves a fading trail, and accelerates as it spirals
  into the centre (slow at the rim, fast at the drain) before the screen wipes
  to black and the game reveals. Duration tuned to ~2.3 s.
- The launch ball **replaces** the home ball (no more two balls on screen);
  split into `LaunchBall` (ball + trail, in the home ball's coordinate space)
  and `LaunchTransition` (portal glow + black wipe).

### Store sheets — Get Lives / Get Coins
- Get Lives sheet opens taller so the Diamond Balls offer is fully visible; its
  description is two lines; life packs show a green **"+X% lives"** free-bonus
  label mirroring the coin packs.
- Removed the **Restore** and **Done** buttons from both sheets (swipe-to-dismiss;
  Restore Purchases still lives in Settings for App Store compliance).

### Gold Rush economy
- **Time tickets are now unlimited** (stake as many as you hold, +30 s each).
- The coin multiplier no longer floods the field — it doubles **payout**, not
  coin **count** (which had caused severe lag at ×4–×5).
- The only mid-round upsell is a **2-ticket ×2-coins** button. No other
  multipliers.

### Game Modes hub
- Replaced the "Games / Every way to roll." header with a single full-width
  tagline: **"Choose the way you want to roll."**

---

## Earlier

Pre-overhaul history lives in the git log and the `docs/research/` series
(market teardown, roadmap, soft-launch plan).
