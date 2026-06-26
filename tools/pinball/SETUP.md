# Pinball physics — Chipmunk everywhere (zero feel-drift)

Goal: the agent tunes the table in a runtime it can run, and that tuning ships
**exactly**, because both sides use the same physics engine + version.

## Engine parity
- **Harness (Python):** `pip install 'pymunk<7'` → **pymunk 6.11.1**, which wraps
  **Chipmunk 7.0.3**. (pymunk ≥7 switched to the Munk2D fork — do NOT use it here;
  we want vanilla Chipmunk 7.0.3 to match iOS.)
- **iOS (Swift):** add the SPM package
  [`spencerkohan/Chipmunk2D-SPM`](https://github.com/spencerkohan/Chipmunk2D-SPM)
  at **7.0.3+** (Chipmunk **7.0.3**). Import as `import Chipmunk`.
  Xcode: File → Add Package Dependencies → the repo URL → add to the RollAlong target.

Both run Chipmunk 7.0.3, so gravity / elasticity / friction / impulse / joint
constants tuned in `sim.py` carry straight into the Swift build.

## Architecture (iOS)
- **Chipmunk drives physics**, SpriteKit only **renders**. Build a `cpSpace` with
  walls/ball/flippers/bumpers (mirroring `sim.py`); step it in `SKScene.update`;
  sync `SKNode` positions/rotations from the Chipmunk body transforms. SpriteKit's
  own physics is unused.
- Flipper input → set the flipper motor rate on the Chipmunk body.

## Workflow
`sim.py` (run → render trajectory PNG → tune → repeat) is the source of truth for
geometry + constants. When it plays great, port the geometry + the tuned numbers
into the Swift Chipmunk layer.
