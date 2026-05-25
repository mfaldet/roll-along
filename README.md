# Roll Along

A tilt-driven iOS marble game starter. Tap to spawn a 3D-shaded red marble,
tilt the device to roll it around a flat arena, bounce off the walls.
The whole thing is one SwiftUI view backed by `CoreMotion`.

Originally extracted from [`pourart`](https://github.com/mfaldet/pourart)'s
on-device tilt diagnostic, intended here as the foundation for a tilt-based
game.

## Run it

Open `RollAlong.xcodeproj` in Xcode 15+ and run on a physical device (the
simulator can't report device motion). iOS 17+.

## Project layout

```
RollAlong/
├── RollAlongApp.swift     ← app entry point
├── ContentView.swift      ← intentionally thin — wraps BallGameView
├── BallGameView.swift     ← the game view + BallMotion (CMMotionManager wrapper)
└── Info.plist             ← declares NSMotionUsageDescription
```

## How it works

### Input — `BallMotion`

A small `@MainActor ObservableObject` wraps `CMMotionManager`:

- Pulls `motion.gravity` at 60 Hz
- Flips the Y axis to match SwiftUI's top-down coordinate system
- Applies a ~3° deadband so the ball doesn't drift on a level surface
- Publishes the resulting 2D gravity vector

### Physics — `BallGameView.tick(geoSize:)`

Driven by a SwiftUI `Timer.publish(every: 1/60)` and `onReceive`:

```
acceleration = gravity × 1800 pt/s² (per unit gravity)
velocity     += acceleration × dt
velocity     *= 0.985                          ← rolling friction
position     += velocity × dt
```

Walls are checked individually — when the ball crosses any edge, its
position is clamped and the perpendicular velocity component is negated
with 0.55 elasticity. If gravity is in the deadband AND the ball is moving
slowly (`|v| < 6 pt/s`), the velocity is snapped to zero so the ball can
truly come to rest.

### Rendering — `marble`

A SwiftUI `Circle` filled with a `RadialGradient` centered at the
top-left, plus a drop shadow. The gradient runs:

```
bright pink highlight → red → dark red → near-black
```

…which reads as a glossy 3D sphere lit from above.

## Tuning knobs

All in `BallGameView`:

| Value             | Default | What it controls                               |
| ----------------- | ------- | ---------------------------------------------- |
| `ballRadius`      | 18      | Ball size (points)                             |
| `accelScale`      | 1800    | Acceleration per unit gravity (pt/s²)         |
| `0.985`           |         | Rolling-friction multiplier (per frame)        |
| `0.55`            |         | Wall-bounce elasticity                         |
| `BallMotion.deadband` | 0.05 | Tilt deadband, ≈ 3°                           |

## Where to go from here

- **Goal / target**: place a flagged tile, end the round when the ball
  reaches it
- **Obstacles**: walls drawn from a level definition
- **Levels**: a series of arenas with different layouts
- **Multiple balls**: physics is per-object — add a collection
- **Sound**: AVFoundation tap on wall bounces (volume scaled by impact speed)
- **Score / time**: SwiftUI overlay above the arena
- **Vibrations**: `UIImpactFeedbackGenerator` on bounces

## License

MIT (or whatever Mac decides). For now, treat it as personal-project code.
