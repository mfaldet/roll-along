import CoreGraphics
import Foundation

// ---------------------------------------------------------------------------
// GoldRushEngine — the headless, view-independent Gold Rush simulation.
//
// This is the single source of truth for the per-frame `tick()`.  `GoldRushView`
// drives it: each frame it feeds `playerInput`, calls `tick()`, and renders the
// engine's `racers`/`coins`/`poofs`.  Because the engine carries no SwiftUI,
// accelerometer, or run-loop dependency, the same `tick()` can also run headless
// — see `RollAlongTests/PerformanceTests.swift` for the 60-tick (1 s @ 60 fps)
// performance baseline (QE3 §7), which now measures the real production tick.
//
// It deliberately reuses the already-shared primitives — `PhysicsHelpers`
// (bounceEdges / resolveWallSegment) and `GoldRushMaps`.  Side effects that
// don't affect the simulation are intentionally left to the host view: the coin
// award (GameState), analytics, and haptics.  The player's accelerometer input
// is supplied via `playerInput` (zero by default, so in headless use the player
// marble is stationary while the AI rivals still exercise steering, collisions,
// and coin logic).
//
// The class is a plain (non-Observable) type with `private(set)` state so the
// performance test measures pure simulation cost; the view schedules its own
// redraws by mirroring the engine's arrays into @State once per tick.  Applying
// the same pattern to de-duplicate SnakeGameView's physics is a future follow-up.
// ---------------------------------------------------------------------------

final class GoldRushEngine {

    // MARK: - Tunables (the gameplay feel knobs)

    private let marbleRadius: CGFloat = 17
    private let playerAccel:  CGFloat = 1_500
    private let aiAccel:      CGFloat = 1_180
    private let friction:     CGFloat = 0.990
    private let maxSpeed:     CGFloat = 640
    private let wallBounce:   CGFloat = 0.70
    private let restitution:  CGFloat = 0.85
    private let rivalCount         = 3
    private let roundSeconds       = 60
    private let initialCoins       = 12
    private let maxCoins           = 18
    private let spawnEveryTicks    = 20
    private let spillImpact:  CGFloat = 360
    private let coinsPerSpill      = 3
    private let spillImmunityTicks = 45
    private let ramSeekRange: CGFloat = 220
    private let winBonus           = 15
    private let topReserve: CGFloat = Layout.topReserve
    private var roundTicks: Int { roundSeconds * 60 }

    // MARK: - Model

    struct Racer: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var vel: CGVector = .zero
        let colorIndex: Int
        let isPlayer: Bool
        let aggro: Bool
        var score: Int = 0
    }

    struct Coin: Identifiable {
        let id = UUID()
        var pos: CGPoint
        let value: Int
        var ignoreRacer: UUID? = nil
        var ignoreUntil: Int = 0
        let born: Int
        var popScale: CGFloat = 0.6
    }

    struct Poof: Identifiable {
        let id = UUID()
        let pos: CGPoint
        let colorIndex: Int       // view maps index → Color; engine stays UI-free
        let born: Int
    }

    // MARK: - State

    private(set) var racers: [Racer] = []
    private(set) var coins:  [Coin]  = []
    private(set) var poofs:  [Poof]  = []

    private(set) var arena:  CGSize
    private(set) var center: CGPoint

    private(set) var started   = false
    private(set) var isOver    = false
    private(set) var playerWon = false
    private(set) var localTick = 0
    private(set) var roundTick = 0
    private(set) var awarded   = false
    private(set) var banked    = 0     // coins owed to the player at round end

    private var mapIndex = 0
    private var walls: [WallSegFrac] = []

    /// Player accelerometer input (gravity vector).  Zero in headless / test
    /// use; a view would set this from `BallMotion.gravity` each frame.
    var playerInput: CGVector = .zero

    /// AI handicap multipliers (1.0 = full strength = the original AI).  The
    /// host view sets these from the player's MinigameDifficulty; headless /
    /// test use keeps the defaults so the performance baseline measures the
    /// busiest AI.  Applied to rival steering acceleration and top speed —
    /// never to the player's marble.
    var aiAccelScale: CGFloat = 1.0
    var aiSpeedScale: CGFloat = 1.0

    // MARK: - Computed

    var playerScore: Int { racers.first { $0.isPlayer }?.score ?? 0 }
    var maxScore: Int { racers.map(\.score).max() ?? 0 }

    // MARK: - Setup

    init(arena: CGSize) {
        self.arena = arena
        self.center = CGPoint(x: arena.width / 2, y: arena.height / 2)
    }

    func loadMap(index: Int) {
        mapIndex = index
        walls = GoldRushMaps.maps[mapIndex % GoldRushMaps.maps.count].walls
    }

    /// Resize the arena (and recompute its centre) when the host view's
    /// geometry changes.  Does not disturb an in-progress round — the next
    /// `tick()` simply clamps marbles to the new bounds.
    func updateArena(_ size: CGSize) {
        arena = size
        center = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// Lay out a fresh board — player in the centre, rivals on a ring, the
    /// opening scatter of coins — but leave the round un-started (`started`
    /// stays false) so a host view can show its "tap to begin" prompt over a
    /// settled arena.  Call `loadMap(index:)` first so coin spawns avoid walls.
    func resetBoard() {
        guard arena.width > 0 else { return }
        started = false
        isOver = false
        playerWon = false
        awarded = false
        banked = 0
        roundTick = 0
        poofs = []
        coins = []

        var fresh: [Racer] = [Racer(pos: center, colorIndex: 0, isPlayer: true, aggro: false)]
        let ringR = min(arena.width, arena.height) * 0.30
        for i in 0..<rivalCount {
            let angle = (Double(i) / Double(rivalCount)) * 2 * .pi - .pi / 2
            let p = CGPoint(x: center.x + CGFloat(cos(angle)) * ringR,
                            y: center.y + CGFloat(sin(angle)) * ringR)
            fresh.append(Racer(pos: p, colorIndex: i + 1, isPlayer: false, aggro: i == 0))
        }
        racers = fresh

        for _ in 0..<initialCoins { spawnCoin() }
    }

    /// Lay out a board and immediately begin play.  Retained as the headless
    /// entry point for tests/benchmarks (see PerformanceTests); a host view
    /// instead pairs `resetBoard()` with `beginPlay()` so it can render the
    /// pre-roll prompt over the settled board.
    func startRound() {
        resetBoard()
        guard arena.width > 0 else { return }
        started = true
    }

    /// Begin a round whose board was already laid out by `resetBoard()`
    /// (the player tapped to start).  No-op once the round is over.
    func beginPlay() {
        guard arena.width > 0, !isOver else { return }
        started = true
    }

    // MARK: - Simulation

    func tick() {
        localTick &+= 1
        prunePoofs()
        guard started, !isOver, arena.width > 0 else { return }
        roundTick += 1

        if coins.count < maxCoins && localTick % spawnEveryTicks == 0 { spawnCoin() }

        for i in coins.indices {
            let age = localTick - coins[i].born
            guard age <= 8 else { continue }
            coins[i].popScale = CGFloat(0.6 + 0.4 * Double(age) / 8.0)
        }

        let dt: CGFloat = 1.0 / 60.0
        for i in racers.indices {
            if racers[i].isPlayer {
                racers[i].vel.dx += playerInput.dx * playerAccel * dt
                racers[i].vel.dy += playerInput.dy * playerAccel * dt
            } else {
                let steer = botSteer(racers[i])
                racers[i].vel.dx += steer.dx * dt
                racers[i].vel.dy += steer.dy * dt
            }
            racers[i].vel.dx *= friction
            racers[i].vel.dy *= friction
            // Rivals get a difficulty-scaled speed cap; the player never does.
            let cap = racers[i].isPlayer ? maxSpeed : maxSpeed * aiSpeedScale
            let s = hypot(racers[i].vel.dx, racers[i].vel.dy)
            if s > cap {
                let k = cap / s
                racers[i].vel.dx *= k
                racers[i].vel.dy *= k
            }
            racers[i].pos.x += racers[i].vel.dx * dt
            racers[i].pos.y += racers[i].vel.dy * dt
            bounceWalls(&racers[i])
            bounceStaticWalls(&racers[i])
        }

        resolveCollisions()
        collectCoins()

        if roundTick >= roundTicks { endRound() }
    }

    /// Head for the nearest grabbable coin.  A "bully" rival instead chases the
    /// current leader when they're close, to bump coins loose.
    private func botSteer(_ r: Racer) -> CGVector {
        let accel = aiAccel * aiAccelScale

        // Primary goal: harass the leader (if aggro + close), else nearest coin,
        // else drift back to center.
        let base: CGVector
        if r.aggro, let leader = leaderToHarass(than: r),
           hypot(leader.pos.x - r.pos.x, leader.pos.y - r.pos.y) < ramSeekRange {
            base = unit(dx: leader.pos.x - r.pos.x, dy: leader.pos.y - r.pos.y, scale: accel)
        } else if let coin = nearestCoin(to: r) {
            base = unit(dx: coin.pos.x - r.pos.x, dy: coin.pos.y - r.pos.y, scale: accel)
        } else {
            base = unit(dx: center.x - r.pos.x, dy: center.y - r.pos.y, scale: accel * 0.5)
        }

        // Always layer on a push away from nearby edges.  Without it a strong
        // steering force (high difficulty) presses a rival into a wall faster
        // than the bounce recovers — two aggro rivals could chase each other
        // into a corner and stay pinned, making Hard play easier than Medium.
        // The push scales WITH `accel`, so it stays ahead of steering at every
        // difficulty.
        let push = edgeRepulsion(for: r, accel: accel)
        return CGVector(dx: base.dx + push.dx, dy: base.dy + push.dy)
    }

    /// Outward force that ramps from 0 at the band edge to its strongest right
    /// at the wall (and stacks on both axes in a corner), keeping rivals from
    /// pinning themselves against an edge.  Rivals only; the player is immune.
    private func edgeRepulsion(for r: Racer, accel: CGFloat) -> CGVector {
        let margin: CGFloat = marbleRadius * 4
        let strength = accel * 1.1            // beats the steering force at the wall
        var fx: CGFloat = 0, fy: CGFloat = 0
        let left = r.pos.x, right = arena.width - r.pos.x
        let top  = r.pos.y, bottom = arena.height - r.pos.y
        if left   < margin { fx += (1 - left   / margin) * strength }
        if right  < margin { fx -= (1 - right  / margin) * strength }
        if top    < margin { fy += (1 - top    / margin) * strength }
        if bottom < margin { fy -= (1 - bottom / margin) * strength }
        return CGVector(dx: fx, dy: fy)
    }

    private func nearestCoin(to r: Racer) -> Coin? {
        var best: Coin?
        var bestD = CGFloat.greatestFiniteMagnitude
        for c in coins {
            if c.ignoreRacer == r.id && localTick < c.ignoreUntil { continue }
            let d = hypot(c.pos.x - r.pos.x, c.pos.y - r.pos.y)
            if d < bestD { bestD = d; best = c }
        }
        return best
    }

    private func leaderToHarass(than r: Racer) -> Racer? {
        var best: Racer?
        for o in racers where o.id != r.id {
            if o.score <= r.score { continue }
            if best == nil || o.score > best!.score { best = o }
        }
        return best
    }

    private func bounceWalls(_ r: inout Racer) {
        bounceEdges(pos: &r.pos, vel: &r.vel,
                    radius: marbleRadius, arena: arena, restitution: wallBounce)
    }

    private func bounceStaticWalls(_ r: inout Racer) {
        for seg in walls {
            let p1 = CGPoint(x: seg.x1 * arena.width, y: seg.y1 * arena.height)
            let p2 = CGPoint(x: seg.x2 * arena.width, y: seg.y2 * arena.height)
            resolveWallSegment(pos: &r.pos, vel: &r.vel,
                               p1: p1, p2: p2,
                               radius: marbleRadius, restitution: wallBounce)
        }
    }

    private func isNearWall(_ p: CGPoint) -> Bool {
        let margin = marbleRadius + 8
        for seg in walls {
            let p1 = CGPoint(x: seg.x1 * arena.width, y: seg.y1 * arena.height)
            let p2 = CGPoint(x: seg.x2 * arena.width, y: seg.y2 * arena.height)
            let dx = p2.x - p1.x, dy = p2.y - p1.y
            let lenSq = dx * dx + dy * dy
            guard lenSq > 0 else { continue }
            let t = max(0, min(1, ((p.x - p1.x) * dx + (p.y - p1.y) * dy) / lenSq))
            if hypot(p.x - (p1.x + t * dx), p.y - (p1.y + t * dy)) < margin { return true }
        }
        return false
    }

    private func resolveCollisions() {
        guard racers.count >= 2 else { return }
        let minDist = marbleRadius * 2
        var spilled: [Coin] = []
        for i in 0..<racers.count {
            for j in (i + 1)..<racers.count {
                let dx = racers[j].pos.x - racers[i].pos.x
                let dy = racers[j].pos.y - racers[i].pos.y
                let dist = hypot(dx, dy)
                guard dist > 0, dist < minDist else { continue }
                let nx = dx / dist, ny = dy / dist
                let overlap = (minDist - dist) / 2
                racers[i].pos.x -= nx * overlap
                racers[i].pos.y -= ny * overlap
                racers[j].pos.x += nx * overlap
                racers[j].pos.y += ny * overlap

                let relVel = (racers[j].vel.dx - racers[i].vel.dx) * nx
                           + (racers[j].vel.dy - racers[i].vel.dy) * ny
                guard relVel < 0 else { continue }

                let si = hypot(racers[i].vel.dx, racers[i].vel.dy)
                let sj = hypot(racers[j].vel.dx, racers[j].vel.dy)

                let jImp = -(1 + restitution) * relVel / 2
                racers[i].vel.dx -= jImp * nx
                racers[i].vel.dy -= jImp * ny
                racers[j].vel.dx += jImp * nx
                racers[j].vel.dy += jImp * ny

                if -relVel > spillImpact {
                    let hit = si <= sj ? i : j
                    let k = min(coinsPerSpill, racers[hit].score)
                    if k > 0 {
                        racers[hit].score -= k
                        for _ in 0..<k { spilled.append(makeSpill(at: racers[hit].pos, by: racers[hit].id)) }
                        poofs.append(Poof(pos: racers[hit].pos,
                                          colorIndex: racers[hit].colorIndex,
                                          born: localTick))
                    }
                }
            }
        }
        if !spilled.isEmpty { coins.append(contentsOf: spilled) }
    }

    private func collectCoins() {
        guard !coins.isEmpty else { return }
        let grab = marbleRadius + 10
        var remaining: [Coin] = []
        for c in coins {
            var taken = false
            for i in racers.indices {
                if c.ignoreRacer == racers[i].id && localTick < c.ignoreUntil { continue }
                if hypot(racers[i].pos.x - c.pos.x, racers[i].pos.y - c.pos.y) < grab {
                    racers[i].score += c.value
                    taken = true
                    break
                }
            }
            if !taken { remaining.append(c) }
        }
        if remaining.count != coins.count { coins = remaining }
    }

    private func spawnCoin() {
        guard arena.width > 0 else { return }
        let margin: CGFloat = 34
        for _ in 0..<8 {
            let x = CGFloat.random(in: margin...(arena.width - margin))
            let y = CGFloat.random(in: topReserve...(arena.height - margin))
            let pt = CGPoint(x: x, y: y)
            if racers.contains(where: { hypot($0.pos.x - x, $0.pos.y - y) < marbleRadius * 2 }) { continue }
            if isNearWall(pt) { continue }
            coins.append(Coin(pos: pt, value: 1, born: localTick))
            return
        }
    }

    private func makeSpill(at pos: CGPoint, by who: UUID) -> Coin {
        let angle = Double.random(in: 0..<(2 * .pi))
        let r = CGFloat.random(in: 18...34)
        var p = CGPoint(x: pos.x + CGFloat(cos(angle)) * r, y: pos.y + CGFloat(sin(angle)) * r)
        p.x = min(max(marbleRadius, p.x), arena.width - marbleRadius)
        p.y = min(max(topReserve, p.y), arena.height - marbleRadius)
        return Coin(pos: p, value: 1, ignoreRacer: who, ignoreUntil: localTick + spillImmunityTicks, born: localTick)
    }

    private func prunePoofs() {
        if !poofs.isEmpty { poofs.removeAll { localTick - $0.born > 24 } }
    }

    private func unit(dx: CGFloat, dy: CGFloat, scale: CGFloat) -> CGVector {
        let m = hypot(dx, dy)
        guard m > 0 else { return CGVector(dx: 0, dy: 0) }
        return CGVector(dx: dx / m * scale, dy: dy / m * scale)
    }

    private func endRound() {
        guard !isOver else { return }
        isOver = true
        playerWon = !racers.contains { !$0.isPlayer && $0.score > playerScore }
        awarded = true
        banked = playerScore + (playerWon ? winBonus : 0)
    }
}
