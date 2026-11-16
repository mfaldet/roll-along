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
    private let spillImmunityTicks = 45
    private let ramSeekRange: CGFloat = 220
    private let winBonus           = 15
    private let topReserve: CGFloat = Layout.topReserve

    // Charge / ram-spill mechanic.  A tap launches the player's marble a short
    // distance in the tilt direction: its velocity is overridden to `chargeSpeed`
    // and its speed cap is lifted for `chargeBoostTicks`, after which friction
    // blends it back to normal play.  A marble only knocks coins loose from a
    // rival WHILE it is charging — an ordinary bump no longer spills anything.
    // Charge is gated to once per `chargeCooldownTicks` (1.5 s).  The aggro
    // "bully" rival charges too, so it can still threaten the player's hoard.
    private let chargeSpeed:          CGFloat = 760
    private let chargeBoostTicks              = 15
    private let chargeCooldownTicks           = 90    // 1.5 s @ 60 fps
    private let chargeAITriggerRange: CGFloat = 150   // bully commits a charge inside this gap
    private let chargeSpillImpact:    CGFloat = 120   // min closing speed for a charge to spill

    /// Width of the edge band rivals are pushed out of (see `edgeRepulsion`).
    /// Coins never spawn inside it, so every coin is reachable by every ball.
    private var edgeBand: CGFloat { marbleRadius * 4 }

    /// Bottom safe-area clearance (home indicator) — coins keep this far off the
    /// bottom, on top of `edgeBand`, so they never sit in the awkward, hard-to-
    /// reach strip along the bottom border.
    private let bottomReserve: CGFloat = 44
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
        /// Ticks remaining of an active charge dash.  While > 0 the marble's
        /// speed cap is lifted and ramming a rival knocks coins loose.
        var charging: Int = 0
        /// Ticks until this marble may charge again (0 = ready).
        var chargeCD: Int = 0
        /// Until this tick the marble cannot be made to drop more coins.
        var noSpillUntil: Int = 0
    }

    struct Coin: Identifiable {
        let id = UUID()
        var pos: CGPoint
        let value: Int
        var ignoreRacer: UUID? = nil
        var ignoreUntil: Int = 0
        let born: Int
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

    /// The opponents' difficulty.  Every opponent number (reaction delay,
    /// aiming error, mistakes, effort, top speed) comes from `OpponentTuning`
    /// for this difficulty.  Set it BEFORE `resetBoard()` / `startRound()`.
    /// Defaults to `.hard` so headless/test runs measure the busiest opponents.
    var difficulty: MinigameDifficulty = .hard {
        // A changed difficulty gives every opponent a fresh brain with the
        // new limits (made on demand in `botSteer`).
        didSet { if difficulty != oldValue { brains = [:]; restTicks = [:]; wanderPoint = [:] } }
    }
    /// Optional fixed seed for the opponents' random choices (tests).
    var opponentSeed: UInt64? = nil

    /// One brain per opponent, keyed by `colorIndex`.
    private var brains: [Int: OpponentBrain] = [:]
    /// Each opponent's skill for this round (0 clumsy … 1 sharp), dealt in
    /// `resetBoard()` so the three are one clumsy, one average, one sharp.
    private var skills: [Int: Double] = [:]
    /// Ticks an opponent still coasts after picking up a coin.
    private var restTicks: [Int: Int] = [:]
    /// Where an opponent is wandering to while it has no coin in view.
    private var wanderPoint: [Int: CGPoint] = [:]

    // Which parts of the arena can be reached from the middle (walls can
    // close an area off).  Coins only spawn, and marbles only start, where
    // every marble can get to.
    private let reachCell: CGFloat = 20
    private var reachCols = 0
    private var reachRows = 0
    private var reachable: [Bool] = []
    /// The bully's charge aim for this tick (set by `botSteer`): where it
    /// BELIEVES the leader is, with its aiming error.  Nil when not chasing.
    private var bullyChargeAim: [Int: CGVector] = [:]
    /// Ticks the round has been live (for `duration_s` in the result event).
    var roundSecondsPlayed: Int { roundTick / 60 }
    /// Best opponent score (for the result event's margin).
    var bestRivalScore: Int { racers.filter { !$0.isPlayer }.map(\.score).max() ?? 0 }
    /// The player's finishing place, 1 to 4 (ties go to the player).
    var playerPlacement: Int {
        1 + racers.filter { !$0.isPlayer && $0.score > playerScore }.count
    }

    // MARK: - Computed

    var playerScore: Int { racers.first { $0.isPlayer }?.score ?? 0 }
    var maxScore: Int { racers.map(\.score).max() ?? 0 }

    /// True while the player may fire a charge (round live + cooldown elapsed).
    var playerChargeReady: Bool {
        started && !isOver && (racers.first { $0.isPlayer }?.chargeCD ?? 1) == 0
    }
    /// Charge cooldown fill for the HUD, 0…1 (1 = ready to charge).
    var playerChargeProgress: Double {
        let cd = racers.first { $0.isPlayer }?.chargeCD ?? 0
        return chargeCooldownTicks > 0 ? 1 - Double(cd) / Double(chargeCooldownTicks) : 1
    }

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
        buildReachability()
    }

    /// Flood-fill from the arena's middle over a coarse grid, treating every
    /// cell a marble cannot occupy (too near a wall or the border) as closed.
    /// With no walls the whole grid is left empty, meaning "everywhere".
    private func buildReachability() {
        reachable = []
        guard !walls.isEmpty, arena.width > 0, arena.height > 0 else { return }
        reachCols = max(1, Int((arena.width / reachCell).rounded(.up)))
        reachRows = max(1, Int((arena.height / reachCell).rounded(.up)))
        let total = reachCols * reachRows
        var open = [Bool](repeating: false, count: total)
        for row in 0..<reachRows {
            for col in 0..<reachCols {
                let p = CGPoint(x: (CGFloat(col) + 0.5) * reachCell,
                                y: (CGFloat(row) + 0.5) * reachCell)
                if p.x < marbleRadius || p.x > arena.width - marbleRadius { continue }
                if p.y < topReserve + marbleRadius || p.y > arena.height - marbleRadius { continue }
                if distanceToNearestWall(p) < marbleRadius { continue }
                open[row * reachCols + col] = true
            }
        }
        // Start from the open cell nearest the middle.
        var start = -1
        var startD = CGFloat.greatestFiniteMagnitude
        for idx in 0..<total where open[idx] {
            let x = (CGFloat(idx % reachCols) + 0.5) * reachCell
            let y = (CGFloat(idx / reachCols) + 0.5) * reachCell
            let d = hypot(x - center.x, y - center.y)
            if d < startD { startD = d; start = idx }
        }
        guard start >= 0 else { return }
        var seen = [Bool](repeating: false, count: total)
        var queue = [start]
        seen[start] = true
        var head = 0
        while head < queue.count {
            let idx = queue[head]
            head += 1
            let col = idx % reachCols, row = idx / reachCols
            if col > 0             { visit(idx - 1,         open, &seen, &queue) }
            if col < reachCols - 1 { visit(idx + 1,         open, &seen, &queue) }
            if row > 0             { visit(idx - reachCols, open, &seen, &queue) }
            if row < reachRows - 1 { visit(idx + reachCols, open, &seen, &queue) }
        }
        reachable = seen
    }

    private func visit(_ idx: Int, _ open: [Bool], _ seen: inout [Bool], _ queue: inout [Int]) {
        if open[idx] && !seen[idx] {
            seen[idx] = true
            queue.append(idx)
        }
    }

    /// True when a marble starting in the middle can get to `p`.
    private func isReachable(_ p: CGPoint) -> Bool {
        guard !reachable.isEmpty else { return true }
        let col = Int(p.x / reachCell), row = Int(p.y / reachCell)
        guard col >= 0, col < reachCols, row >= 0, row < reachRows else { return false }
        return reachable[row * reachCols + col]
    }

    private func distanceToNearestWall(_ p: CGPoint) -> CGFloat {
        var best = CGFloat.greatestFiniteMagnitude
        for seg in walls {
            let p1 = CGPoint(x: seg.x1 * arena.width, y: seg.y1 * arena.height)
            let p2 = CGPoint(x: seg.x2 * arena.width, y: seg.y2 * arena.height)
            let dx = p2.x - p1.x, dy = p2.y - p1.y
            let lenSq = dx * dx + dy * dy
            guard lenSq > 0 else { continue }
            let t = max(0, min(1, ((p.x - p1.x) * dx + (p.y - p1.y) * dy) / lenSq))
            best = min(best, hypot(p.x - (p1.x + t * dx), p.y - (p1.y + t * dy)))
        }
        return best
    }

    /// True when a wall lies between `a` and `b`.
    private func wallBetween(_ a: CGPoint, _ b: CGPoint) -> Bool {
        func side(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        for seg in walls {
            let p1 = CGPoint(x: seg.x1 * arena.width, y: seg.y1 * arena.height)
            let p2 = CGPoint(x: seg.x2 * arena.width, y: seg.y2 * arena.height)
            let d1 = side(p1, p2, a), d2 = side(p1, p2, b)
            let d3 = side(a, b, p1),  d4 = side(a, b, p2)
            if d1 * d2 < 0 && d3 * d4 < 0 { return true }
        }
        return false
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
        buildReachability()

        var fresh: [Racer] = [Racer(pos: center, colorIndex: 0, isPlayer: true, aggro: false)]
        let ringR = min(arena.width, arena.height) * 0.30
        for i in 0..<rivalCount {
            let angle = (Double(i) / Double(rivalCount)) * 2 * .pi - .pi / 2
            // Pull the start point in toward the middle until it is somewhere
            // every marble can reach (a wall can cut the ring off).
            var p = center
            var shrink: CGFloat = 1.0
            while shrink > 0.15 {
                let candidate = CGPoint(x: center.x + CGFloat(cos(angle)) * ringR * shrink,
                                        y: center.y + CGFloat(sin(angle)) * ringR * shrink)
                if isReachable(candidate) && distanceToNearestWall(candidate) >= marbleRadius * 1.5 {
                    p = candidate
                    break
                }
                shrink -= 0.15
            }
            if p == center {
                p = CGPoint(x: center.x + CGFloat(cos(angle)) * marbleRadius * 2.5,
                            y: center.y + CGFloat(sin(angle)) * marbleRadius * 2.5)
            }
            fresh.append(Racer(pos: p, colorIndex: i + 1, isPlayer: false, aggro: i == 0))
        }
        racers = fresh

        // Each opponent draws its own skill for the round: one clumsy, one
        // average, one sharp, in random order.
        let dealt = OpponentTuning.dealSkills(rivalCount, seed: opponentSeed)
        skills = [:]
        for i in 0..<rivalCount { skills[i + 1] = dealt[i] }
        brains = [:]
        restTicks = [:]
        wanderPoint = [:]
        bullyChargeAim = [:]
        for r in fresh where !r.isPlayer { brains[r.colorIndex] = makeBrain(r.colorIndex) }

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

    /// Launch the player's marble a short distance in the current tilt direction
    /// (a "charge").  Returns `true` only if it actually fired: a round must be
    /// live, the per-marble cooldown elapsed, and there must be a usable tilt.
    /// The host view calls this on a tap inside a live round.
    @discardableResult
    func chargePlayer() -> Bool {
        guard started, !isOver else { return false }
        guard let idx = racers.firstIndex(where: { $0.isPlayer }) else { return false }
        guard racers[idx].chargeCD == 0 else { return false }
        return fireCharge(&racers[idx], aim: playerInput)
    }

    // MARK: - Simulation

    func tick() {
        localTick &+= 1
        prunePoofs()
        guard started, !isOver, arena.width > 0 else { return }
        roundTick += 1

        if coins.count < maxCoins && localTick % spawnEveryTicks == 0 { spawnCoin() }

        // A platinum coin (worth 3) every 10s of the round — at 10/20/30/40/50s.
        if roundTick % (10 * 60) == 0 && roundTick > 0 && roundTick < roundTicks {
            spawnCoin(value: 3)
        }

        let dt: CGFloat = 1.0 / 60.0
        for i in racers.indices {
            // Tick down the charge dash window and the charge cooldown.
            if racers[i].charging > 0 { racers[i].charging -= 1 }
            if racers[i].chargeCD  > 0 { racers[i].chargeCD  -= 1 }

            if racers[i].isPlayer {
                racers[i].vel.dx += playerInput.dx * playerAccel * dt
                racers[i].vel.dy += playerInput.dy * playerAccel * dt
            } else {
                let steer = botSteer(racers[i])   // also advances this opponent's brain
                racers[i].vel.dx += steer.dx * dt
                racers[i].vel.dy += steer.dy * dt
                maybeAICharge(at: i)        // the bully commits a ram when it's bearing down
            }
            racers[i].vel.dx *= friction
            racers[i].vel.dy *= friction
            // Each opponent has its OWN top speed (its difficulty and skill);
            // the player has the full one.  A live charge lifts the cap to
            // `chargeSpeed` so the dash reads.
            let baseCap = racers[i].isPlayer
                ? maxSpeed
                : maxSpeed * CGFloat((brains[racers[i].colorIndex]?.limits
                                        ?? OpponentTuning.limits(for: difficulty)).smashGrabTopSpeed)
            let cap = racers[i].charging > 0 ? max(baseCap, chargeSpeed) : baseCap
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

    private func makeBrain(_ colorIndex: Int) -> OpponentBrain {
        let seed = opponentSeed.map { $0 &+ UInt64(colorIndex) &* 7_919 }
        return OpponentBrain(difficulty: difficulty,
                             skill: skills[colorIndex] ?? 0.5,
                             seed: seed)
    }

    /// One opponent's push for this tick.
    ///
    /// What it wants: a coin it can SEE and has NOTICED (see `canTarget`).
    /// One opponent (the "bully") instead chases the current leader when
    /// they are close, to dash into them.  With no coin in view it wanders.
    ///
    /// Its human limits, all from `OpponentTuning` at this opponent's
    /// difficulty and skill:
    ///   • reaction delay — it acts on where its goal WAS a moment ago;
    ///   • aiming error   — it pushes off-line by a held error;
    ///   • push share     — it uses only part of the full opponent push;
    ///   • mistakes       — for a moment it goes for the FARTHEST coin and
    ///                      stops steering away from the edges;
    ///   • it coasts for a moment after each coin it picks up.
    private func botSteer(_ r: Racer) -> CGVector {
        var brain = brains[r.colorIndex] ?? makeBrain(r.colorIndex)
        brain.advance()
        let accel = aiAccel * brain.effort
        let skill = brain.skill
        let noticeTicks = Int((OpponentTuning.smashGrabNoticeSeconds(difficulty)
                                .value(skill: skill) * 60).rounded())
        let sight = CGFloat(OpponentTuning.smashGrabSightDistance(difficulty).value(skill: skill))

        // Where it would ideally go this tick.
        var goal = center
        var chasing = false
        var pushScale: CGFloat = 1
        if r.aggro, !brain.isMistaking, let leader = leaderToHarass(than: r),
           hypot(leader.pos.x - r.pos.x, leader.pos.y - r.pos.y) < ramSeekRange {
            goal = leader.pos
            chasing = true
            wanderPoint[r.colorIndex] = nil
        } else if brain.isMistaking,
                  let far = farthestCoin(from: r, noticeTicks: noticeTicks, sight: sight) {
            goal = far.pos
            wanderPoint[r.colorIndex] = nil
        } else if let coin = preferredCoin(for: r, noticeTicks: noticeTicks, sight: sight) {
            goal = coin.pos
            wanderPoint[r.colorIndex] = nil
        } else {
            // Nothing in view: wander to a random spot until a coin shows up.
            var spot = wanderPoint[r.colorIndex] ?? r.pos
            if wanderPoint[r.colorIndex] == nil
                || hypot(spot.x - r.pos.x, spot.y - r.pos.y) < marbleRadius * 2.5 {
                spot = randomReachablePoint(using: &brain) ?? center
                wanderPoint[r.colorIndex] = spot
            }
            goal = spot
            pushScale = CGFloat(OpponentTuning.smashGrabWanderPush)
        }

        // What it actually acts on: the goal as it was one reaction delay ago.
        let seen = brain.perceive(goal)
        let dir = brain.aimed(dx: seen.x - r.pos.x, dy: seen.y - r.pos.y)

        // Coasting after a pickup: no push at all.
        let resting = (restTicks[r.colorIndex] ?? 0) > 0
        if resting {
            restTicks[r.colorIndex] = (restTicks[r.colorIndex] ?? 1) - 1
            pushScale = 0
        }
        let base = CGVector(dx: dir.dx * accel * pushScale, dy: dir.dy * accel * pushScale)

        // The bully's dash uses the same late, imperfect picture.
        if chasing && !resting {
            bullyChargeAim[r.colorIndex] = CGVector(dx: seen.x - r.pos.x, dy: seen.y - r.pos.y)
        } else {
            bullyChargeAim[r.colorIndex] = nil
        }
        let mistaking = brain.isMistaking
        brains[r.colorIndex] = brain

        // Layer on a push away from nearby edges.  Without it a strong
        // steering force presses an opponent into the border faster than the
        // bounce recovers.  During a mistake it is left off, so the opponent
        // runs into the edge.
        if mistaking && OpponentTuning.smashGrabMistakeHitsEdges { return base }
        let push = edgeRepulsion(for: r, accel: accel)
        return CGVector(dx: base.dx + push.dx, dy: base.dy + push.dy)
    }

    /// A random point every marble can reach, drawn from the opponent's own
    /// (seedable) random source.
    private func randomReachablePoint(using brain: inout OpponentBrain) -> CGPoint? {
        let margin = edgeBand
        let top = topReserve + edgeBand
        let bottom = arena.height - bottomReserve - edgeBand
        guard arena.width > 2 * margin, bottom > top else { return nil }
        for _ in 0..<8 {
            let x = margin + CGFloat(brain.unitRandom()) * (arena.width - 2 * margin)
            let y = top + CGFloat(brain.unitRandom()) * (bottom - top)
            let p = CGPoint(x: x, y: y)
            if isReachable(p) { return p }
        }
        return nil
    }

    /// Whether opponent `r` may go for coin `c` right now: not one it just
    /// dropped, on the board long enough to have been noticed, and within
    /// sight.
    private func canTarget(_ c: Coin, _ r: Racer, noticeTicks: Int, sight: CGFloat) -> Bool {
        if c.ignoreRacer == r.id && localTick < c.ignoreUntil { return false }
        if localTick - c.born < noticeTicks { return false }
        return hypot(c.pos.x - r.pos.x, c.pos.y - r.pos.y) <= sight
    }

    /// The best coin for `r`: the nearest one no OTHER opponent is closer to,
    /// so the three opponents spread out (`OpponentTuning.smashGrabSpreadOut`).
    /// Opponents that take walls into account treat a coin behind a wall as
    /// much farther away.  Falls back to the plain nearest coin.
    private func preferredCoin(for r: Racer, noticeTicks: Int, sight: CGFloat) -> Coin? {
        let avoidsWalls = OpponentTuning.smashGrabAvoidsWalls(difficulty) && !walls.isEmpty
        let penalty = CGFloat(OpponentTuning.smashGrabBlockedCoinPenalty)
        var best: Coin?
        var bestCost = CGFloat.greatestFiniteMagnitude
        var nearest: Coin?
        var nearestCost = CGFloat.greatestFiniteMagnitude
        for c in coins where canTarget(c, r, noticeTicks: noticeTicks, sight: sight) {
            let d = hypot(c.pos.x - r.pos.x, c.pos.y - r.pos.y)
            let cost = (avoidsWalls && wallBetween(r.pos, c.pos)) ? d * penalty : d
            if cost < nearestCost { nearestCost = cost; nearest = c }
            if cost >= bestCost { continue }
            if OpponentTuning.smashGrabSpreadOut {
                var someoneCloser = false
                for o in racers where !o.isPlayer && o.id != r.id {
                    if hypot(c.pos.x - o.pos.x, c.pos.y - o.pos.y) < d { someoneCloser = true; break }
                }
                if someoneCloser { continue }
            }
            bestCost = cost
            best = c
        }
        return best ?? nearest
    }

    private func farthestCoin(from r: Racer, noticeTicks: Int, sight: CGFloat) -> Coin? {
        var best: Coin?
        var bestD: CGFloat = -1
        for c in coins where canTarget(c, r, noticeTicks: noticeTicks, sight: sight) {
            let d = hypot(c.pos.x - r.pos.x, c.pos.y - r.pos.y)
            if d > bestD { bestD = d; best = c }
        }
        return best
    }

    /// Outward force that ramps from 0 at the band edge to its strongest right
    /// at the wall (and stacks on both axes in a corner), keeping rivals from
    /// pinning themselves against an edge.  Rivals only; the player is immune.
    private func edgeRepulsion(for r: Racer, accel: CGFloat) -> CGVector {
        let margin = edgeBand
        let strength = accel * 1.1            // beats the steering force at the wall
        var fx: CGFloat = 0, fy: CGFloat = 0
        let left = r.pos.x, right = arena.width - r.pos.x
        // The top edge is the playfield top (below the HUD), not y = 0.
        let top  = r.pos.y - topReserve, bottom = arena.height - r.pos.y
        if left   < margin { fx += (1 - left   / margin) * strength }
        if right  < margin { fx -= (1 - right  / margin) * strength }
        if top    < margin { fy += (1 - top    / margin) * strength }
        if bottom < margin { fy -= (1 - bottom / margin) * strength }
        return CGVector(dx: fx, dy: fy)
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
        // Keep balls below the HUD strip — the playfield top is `topReserve`,
        // not y = 0, so they can't wander up where coins never spawn.
        let topLimit = topReserve + marbleRadius
        if r.pos.y < topLimit {
            r.pos.y = topLimit
            r.vel.dy = abs(r.vel.dy) * wallBounce
        }
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

                // Decide the spill from the closing speed, BEFORE the bounce
                // alters it.  The faster the hit, the more coins drop
                // (numbers in `OpponentTuning`):
                //   • exactly one marble dashing → the other drops 3 to 6;
                //   • nobody dashing → a fast bump makes the SLOWER marble
                //     drop 1 or 2; a slow bump drops nothing;
                //   • both dashing → nothing.
                let closing = -relVel
                let iCharging = racers[i].charging > 0
                let jCharging = racers[j].charging > 0
                var rammedVictim: Int? = nil
                var dropCount = 0
                if iCharging != jCharging {
                    if closing > chargeSpillImpact {
                        rammedVictim = iCharging ? j : i
                        dropCount = dashDrop(closing: closing)
                    }
                } else if !iCharging, OpponentTuning.smashGrabBumpDropCoins > 0,
                          closing >= CGFloat(OpponentTuning.smashGrabBumpDropSpeed) {
                    // How fast each marble was moving INTO the other.
                    let iInto = racers[i].vel.dx * nx + racers[i].vel.dy * ny
                    let jInto = -(racers[j].vel.dx * nx + racers[j].vel.dy * ny)
                    if abs(iInto - jInto) >= closing * CGFloat(OpponentTuning.smashGrabBumpHitterShare) {
                        rammedVictim = iInto > jInto ? j : i
                        dropCount = closing >= CGFloat(OpponentTuning.smashGrabHardBumpDropSpeed)
                            ? OpponentTuning.smashGrabHardBumpDropCoins
                            : OpponentTuning.smashGrabBumpDropCoins
                    }
                }
                if let hit = rammedVictim, localTick < racers[hit].noSpillUntil {
                    rammedVictim = nil          // it only just dropped some
                }

                let jImp = -(1 + restitution) * relVel / 2
                racers[i].vel.dx -= jImp * nx
                racers[i].vel.dy -= jImp * ny
                racers[j].vel.dx += jImp * nx
                racers[j].vel.dy += jImp * ny

                if let hit = rammedVictim {
                    let k = min(dropCount, racers[hit].score)
                    if k > 0 {
                        racers[hit].noSpillUntil = localTick
                            + Int((OpponentTuning.smashGrabDropImmunitySeconds * 60).rounded())
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

    /// Coins a connecting dash knocks loose: the minimum at the slowest hit
    /// that counts, rising in a straight line to the maximum at full dash
    /// speed.
    private func dashDrop(closing: CGFloat) -> Int {
        let low = chargeSpillImpact
        let high = max(low + 1, CGFloat(OpponentTuning.smashGrabDashFullSpeed))
        let t = min(1, max(0, (closing - low) / (high - low)))
        let lo = CGFloat(OpponentTuning.smashGrabDashDropMin)
        let hi = CGFloat(OpponentTuning.smashGrabDashDropMax)
        return Int((lo + (hi - lo) * t).rounded())
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
                    // An opponent coasts for a moment after a pickup.
                    if !racers[i].isPlayer {
                        let key = racers[i].colorIndex
                        let pause = OpponentTuning.smashGrabPauseAfterCoinSeconds(difficulty)
                            .value(skill: skills[key] ?? 0.5)
                        restTicks[key] = Int((pause * 60).rounded())
                    }
                    break
                }
            }
            if !taken { remaining.append(c) }
        }
        if remaining.count != coins.count { coins = remaining }
    }

    private func spawnCoin(value: Int = 1) {
        // Spawn only where rivals move freely — outside the edge-repulsion band,
        // below the HUD, and clear of the bottom safe area — so a coin can never
        // sit out of reach (where bots would pile up uselessly trying to grab it).
        let margin = edgeBand
        let topMargin = topReserve + edgeBand
        let bottomMargin = bottomReserve + edgeBand
        guard arena.width > 2 * margin, arena.height > topMargin + bottomMargin else { return }
        for _ in 0..<8 {
            let x = CGFloat.random(in: margin...(arena.width - margin))
            let y = CGFloat.random(in: topMargin...(arena.height - bottomMargin))
            let pt = CGPoint(x: x, y: y)
            if racers.contains(where: { hypot($0.pos.x - x, $0.pos.y - y) < marbleRadius * 2 }) { continue }
            if isNearWall(pt) { continue }
            if !isReachable(pt) { continue }      // never behind a closed-off wall
            coins.append(Coin(pos: pt, value: value, born: localTick))
            return
        }
    }

    private func makeSpill(at pos: CGPoint, by who: UUID) -> Coin {
        let angle = Double.random(in: 0..<(2 * .pi))
        let r = CGFloat.random(in: 18...34)
        var p = CGPoint(x: pos.x + CGFloat(cos(angle)) * r, y: pos.y + CGFloat(sin(angle)) * r)
        p.x = min(max(edgeBand, p.x), arena.width - edgeBand)
        p.y = min(max(topReserve + edgeBand, p.y), arena.height - bottomReserve - edgeBand)
        return Coin(pos: p, value: 1, ignoreRacer: who, ignoreUntil: localTick + spillImmunityTicks, born: localTick)
    }

    /// The "bully" opponent commits a charge when it BELIEVES the leader is
    /// close enough to hit within the dash.  It judges range and direction from
    /// its delayed picture of the leader (`bullyChargeAim`, set in `botSteer`)
    /// and its aiming error applies, so the charge can come late and miss —
    /// the same limits as its steering.
    private func maybeAICharge(at i: Int) {
        guard racers[i].aggro, racers[i].chargeCD == 0 else { return }
        let key = racers[i].colorIndex
        guard let aim = bullyChargeAim[key] else { return }
        guard hypot(aim.dx, aim.dy) < chargeAITriggerRange else { return }
        let dir = brains[key]?.aimed(dx: aim.dx, dy: aim.dy) ?? aim
        if fireCharge(&racers[i], aim: dir) {
            // Opponents wait longer between dashes than the player has to.
            let gap = OpponentTuning.smashGrabDashEverySeconds(difficulty)
                .value(skill: skills[key] ?? 0.5)
            racers[i].chargeCD = max(chargeCooldownTicks, Int((gap * 60).rounded()))
        }
    }

    /// Override the marble's velocity with a short forward dash in `aim`'s
    /// direction and arm its charge window + cooldown.  No-op (cooldown unspent)
    /// when there's no usable direction.
    @discardableResult
    private func fireCharge(_ r: inout Racer, aim: CGVector) -> Bool {
        guard let d = chargeDirection(aim: aim, fallback: r.vel) else { return false }
        r.vel = CGVector(dx: d.dx * chargeSpeed, dy: d.dy * chargeSpeed)
        r.charging = chargeBoostTicks
        r.chargeCD = chargeCooldownTicks
        return true
    }

    /// Unit charge direction: the tilt/aim vector when it's meaningful, else the
    /// marble's current heading, else `nil` (truly stationary, no tilt).
    private func chargeDirection(aim: CGVector, fallback vel: CGVector) -> CGVector? {
        let am = hypot(aim.dx, aim.dy)
        if am > 0.05 { return CGVector(dx: aim.dx / am, dy: aim.dy / am) }
        let vm = hypot(vel.dx, vel.dy)
        if vm > 1 { return CGVector(dx: vel.dx / vm, dy: vel.dy / vm) }
        return nil
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
