//  PinballView.swift
//  Roll Along — Pinball minigame.
//
//  REBUILD (Sprint 1–2): scrapped the hand-rolled SwiftUI-Canvas version and
//  rebuilt the table on SpriteKit's real 2D physics engine. The layout is a
//  to-scale reading of the Gottlieb CIRCUS / BIG SHOW electromechanical
//  wedgehead playfield chart: open lower-centre, three pop bumpers up top, a
//  central column of flush rollover buttons, standup targets down the sides,
//  rebound slingshots above two flippers, a shooter lane on the right, and a
//  rounded top arch.
//
//  This file is intentionally self-contained (SwiftUI host + SKScene + model)
//  so it needs no new project files. Physics feel is governed by the clearly
//  marked tuning constants near the top of PinballScene — those want a
//  device playtest pass (can't tune blind).

import SwiftUI
import SpriteKit

// MARK: - Observable bridge (scene → SwiftUI HUD)

final class PinballModel: ObservableObject {
    @Published var score          = 0
    @Published var ballsLeft       = 3
    @Published var awaitingLaunch  = true
    @Published var isOver          = false
}

// MARK: - SwiftUI host

struct PinballView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator

    @StateObject private var model = PinballModel()
    @State private var scene = PinballScene(size: CGSize(width: 393, height: 760))
    @State private var didSubmit = false

    var body: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()

            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if model.awaitingLaunch && !model.isOver {
                    Text("Tap to launch")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Capsule().fill(.black.opacity(0.5)))
                        .padding(.bottom, 60)
                }
            }

            if model.isOver { gameOverOverlay }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            scene.scaleMode = .resizeFill
            scene.model = model
            scene.hapticsEnabled = gameState.hapticsEnabled
        }
        .onChange(of: model.isOver) { _, over in
            if over { submitScore() }
        }
    }

    private var topBar: some View {
        HStack {
            Button { nav.goHome() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
            Spacer()
            VStack(spacing: 0) {
                Text("\(model.score)")
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("SCORE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color(white: 0.6))
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < model.ballsLeft ? Color.white : Color(white: 0.3))
                        .frame(width: 9, height: 9)
                }
            }
            .frame(width: 34)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("Game Over")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                VStack(spacing: 2) {
                    Text("\(model.score)")
                        .font(.system(size: 52, design: .rounded).weight(.black))
                        .monospacedDigit()
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.30))
                    Text("FINAL SCORE")
                        .font(.system(size: 11, weight: .bold)).tracking(2)
                        .foregroundStyle(Color(white: 0.6))
                }
                HStack(spacing: 14) {
                    Button { playAgain() } label: {
                        Text("Play again")
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 22).padding(.vertical, 12)
                            .background(Capsule().fill(.white))
                    }
                    Button { nav.goHome() } label: {
                        Text("Home")
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22).padding(.vertical, 12)
                            .background(Capsule().fill(Color(white: 0.22)))
                    }
                }
            }
        }
    }

    private func submitScore() {
        guard !didSubmit else { return }
        didSubmit = true
        let s = model.score
        let banked = s / 250
        if banked > 0 { gameState.addCoins(banked) }
        gameState.recordPinballScore(s)
        if gameState.hapticsEnabled { Haptics.success() }
    }

    private func playAgain() {
        didSubmit = false
        scene.resetGame()
    }
}

// MARK: - SpriteKit scene (the table + physics)

final class PinballScene: SKScene, SKPhysicsContactDelegate {

    // ── Tuning constants (playtest these) ──────────────────────────────────
    private let ballRadiusFrac:  CGFloat = 0.018   // of width — small ball
    private let gravityY:        CGFloat = -6.0    // table-slope gravity
    private let ballMass:        CGFloat = 0.06
    private let launchSpeedFrac:  CGFloat = 1.25   // launch speed = this × scene height
    private let bumperImpulse:   CGFloat = 4.0     // pop-bumper kick
    private let slingImpulse:    CGFloat = 3.0     // slingshot kick
    private let flipDuration:    Double  = 0.04    // smaller = snappier/stronger
    // Flipper swing angles (radians). Left bat extends +x, right bat extends −x.
    private let leftRest:  CGFloat = -0.50, leftFlip:  CGFloat =  0.34
    private let rightRest: CGFloat =  0.50, rightFlip: CGFloat = -0.34

    // ── Scoring (EM-style) ─────────────────────────────────────────────────
    private let bumperScore   = 100
    private let slingScore    = 10
    private let targetScore   = 500
    private let rolloverScore = 50

    // ── Physics categories ─────────────────────────────────────────────────
    private struct Cat {
        static let ball:     UInt32 = 0x1 << 0
        static let wall:     UInt32 = 0x1 << 1
        static let flipper:  UInt32 = 0x1 << 2
        static let bumper:   UInt32 = 0x1 << 3
        static let sling:    UInt32 = 0x1 << 4
        static let target:   UInt32 = 0x1 << 5
        static let rollover: UInt32 = 0x1 << 6
        static let drain:    UInt32 = 0x1 << 7
    }

    // ── Colours ────────────────────────────────────────────────────────────
    private let cWall     = SKColor(white: 0.55, alpha: 1)
    private let cBumper   = SKColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1)
    private let cSling    = SKColor(red: 0.90, green: 0.28, blue: 0.34, alpha: 1)
    private let cTarget   = SKColor(red: 0.30, green: 0.70, blue: 1.00, alpha: 1)
    private let cRollover = SKColor(white: 0.80, alpha: 1)
    private let cFlipper  = SKColor(red: 0.25, green: 0.55, blue: 1.00, alpha: 1)

    // ── State ──────────────────────────────────────────────────────────────
    weak var model: PinballModel?
    var hapticsEnabled = true

    private var score = 0
    private var ballsLeft = 3
    private var awaitingLaunch = true
    private var isOver = false
    private var built = false

    private var ball: SKShapeNode?
    private var leftFlipper: SKShapeNode?
    private var rightFlipper: SKShapeNode?

    // Normalised → scene point. fx: 0..1 left→right, fy: 0..1 TOP→bottom.
    private func pt(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
        CGPoint(x: size.width * fx, y: size.height * (1 - fy))
    }
    private var ballRadius: CGFloat { size.width * ballRadiusFrac }

    // MARK: Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 1)
        physicsWorld.gravity = CGVector(dx: 0, dy: gravityY)
        physicsWorld.contactDelegate = self
    }

    override func update(_ currentTime: TimeInterval) {
        // Build once the view has given us a real size.
        if !built && size.width > 4 {
            built = true
            buildTable()
            spawnBall()
            pushModel()
        }
    }

    func resetGame() {
        removeAllChildren()
        ball = nil; leftFlipper = nil; rightFlipper = nil
        score = 0; ballsLeft = 3; awaitingLaunch = true; isOver = false
        buildTable()
        spawnBall()
        pushModel()
    }

    // MARK: Build

    private func buildTable() {
        buildWalls()
        buildBumpers()
        buildSlingshots()
        buildTargets()
        buildRollovers()
        buildFlippers()
        buildDrain()
    }

    private func buildWalls() {
        // Curved perimeter traced from the CIRCUS / Big Show outline. The ball is
        // fully enclosed except the centre drain gap (0.40–0.50) and the shooter-
        // lane top exit.

        // P1 — centre-drain-left → curved bottom-left funnel → left rail →
        //       arched top → down to the inside-rail top.
        let p1 = CGMutablePath()
        p1.move(to: pt(0.40, 0.965))
        p1.addQuadCurve(to: pt(0.05, 0.78), control: pt(0.13, 0.95))
        p1.addLine(to: pt(0.05, 0.16))
        p1.addQuadCurve(to: pt(0.28, 0.020), control: pt(0.05, 0.03))
        p1.addQuadCurve(to: pt(0.66, 0.025), control: pt(0.46, 0.004))
        p1.addQuadCurve(to: pt(0.84, 0.160), control: pt(0.83, 0.05))
        addWallPath(p1)

        // P2 — inside rail down + curved bottom-right funnel → centre-drain-right.
        let p2 = CGMutablePath()
        p2.move(to: pt(0.84, 0.16))
        p2.addLine(to: pt(0.84, 0.78))
        p2.addQuadCurve(to: pt(0.50, 0.965), control: pt(0.80, 0.95))
        addWallPath(p2)

        // P3 — shooter lane: lower divider, FLOOR (the backstop the ball rests on),
        //       outer wall, and a curved cap that steers the launched ball left.
        let p3 = CGMutablePath()
        p3.move(to: pt(0.84, 0.78))
        p3.addLine(to: pt(0.84, 0.95))
        p3.addLine(to: pt(0.95, 0.95))
        p3.addLine(to: pt(0.95, 0.13))
        p3.addQuadCurve(to: pt(0.855, 0.045), control: pt(0.95, 0.05))
        addWallPath(p3)
    }

    private func addWallPath(_ path: CGPath) {
        let node = SKShapeNode(path: path)
        node.strokeColor = cWall
        node.lineWidth = 3
        node.lineJoin = .round
        node.lineCap = .round
        let body = SKPhysicsBody(edgeChainFrom: path)
        body.categoryBitMask = Cat.wall
        body.friction = 0.1
        body.restitution = 0.2
        node.physicsBody = body
        addChild(node)
    }

    private func buildBumpers() {
        let r = size.width * 0.05
        for (fx, fy) in [(0.26,0.22),(0.44,0.195),(0.62,0.22)] {
            let node = SKShapeNode(circleOfRadius: r)
            node.fillColor = cBumper
            node.strokeColor = .white
            node.lineWidth = 2
            node.position = pt(fx, fy)
            node.name = "bumper"
            // inner cap
            let cap = SKShapeNode(circleOfRadius: r * 0.42)
            cap.fillColor = SKColor(white: 0.12, alpha: 1)
            cap.strokeColor = .clear
            node.addChild(cap)
            let body = SKPhysicsBody(circleOfRadius: r)
            body.isDynamic = false
            body.restitution = 0.5
            body.categoryBitMask = Cat.bumper
            body.collisionBitMask = Cat.ball
            body.contactTestBitMask = Cat.ball
            node.physicsBody = body
            addChild(node)
        }
    }

    private func buildSlingshots() {
        // Smaller triangles sitting just above each flipper; kicker toward centre.
        addSling([(0.22,0.78),(0.30,0.83),(0.22,0.85)])   // left
        addSling([(0.66,0.78),(0.58,0.83),(0.66,0.85)])   // right
    }

    private func addSling(_ frac: [(CGFloat, CGFloat)]) {
        let pts = frac.map { pt($0.0, $0.1) }
        let path = CGMutablePath()
        path.addLines(between: pts)
        path.closeSubpath()
        let node = SKShapeNode(path: path)
        node.fillColor = cSling
        node.strokeColor = .white
        node.lineWidth = 1
        node.name = "sling"
        let body = SKPhysicsBody(polygonFrom: path)
        body.isDynamic = false
        body.restitution = 0.4
        body.categoryBitMask = Cat.sling
        body.collisionBitMask = Cat.ball
        body.contactTestBitMask = Cat.ball
        node.physicsBody = body
        addChild(node)
    }

    private func buildTargets() {
        let w = size.width * 0.016, h = size.height * 0.035
        for (fx, fy) in [(0.10,0.42),(0.10,0.50),(0.78,0.42),(0.78,0.50)] {
            let node = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 2)
            node.fillColor = cTarget
            node.strokeColor = .white
            node.lineWidth = 1
            node.position = pt(fx, fy)
            node.name = "target"
            let body = SKPhysicsBody(rectangleOf: CGSize(width: w, height: h))
            body.isDynamic = false
            body.restitution = 0.3
            body.categoryBitMask = Cat.target
            body.collisionBitMask = Cat.ball
            body.contactTestBitMask = Cat.ball
            node.physicsBody = body
            addChild(node)
        }
    }

    private func buildRollovers() {
        let r = size.width * 0.018
        // Top rollover lanes + the open central column (flush — ball passes over).
        let fracs: [(CGFloat, CGFloat)] = [
            (0.30,0.09),(0.44,0.075),(0.58,0.09),
            (0.44,0.40),(0.44,0.45),(0.44,0.50),(0.44,0.55),(0.44,0.60),(0.44,0.65),(0.44,0.70)
        ]
        for (fx, fy) in fracs {
            let node = SKShapeNode(circleOfRadius: r)
            node.fillColor = .clear
            node.strokeColor = cRollover
            node.lineWidth = 2
            node.position = pt(fx, fy)
            node.name = "rollover"
            let body = SKPhysicsBody(circleOfRadius: r)
            body.isDynamic = false
            body.categoryBitMask = Cat.rollover
            body.collisionBitMask = 0          // ball rolls over it
            body.contactTestBitMask = Cat.ball
            node.physicsBody = body
            addChild(node)
        }
    }

    private func buildFlippers() {
        leftFlipper  = makeFlipper(pivot: pt(0.28, 0.86), dir:  1, rest: leftRest)
        rightFlipper = makeFlipper(pivot: pt(0.60, 0.86), dir: -1, rest: rightRest)
    }

    /// `dir` = +1 → bat extends right of the pivot; −1 → extends left.
    private func makeFlipper(pivot: CGPoint, dir: CGFloat, rest: CGFloat) -> SKShapeNode {
        let len = size.width * 0.18
        let thick = ballRadius * 1.2
        let rect = CGRect(x: dir > 0 ? 0 : -len, y: -thick / 2, width: len, height: thick)
        let node = SKShapeNode(rect: rect, cornerRadius: thick / 2)
        node.fillColor = cFlipper
        node.strokeColor = .white
        node.lineWidth = 1
        node.position = pivot
        node.zRotation = rest
        let body = SKPhysicsBody(rectangleOf: CGSize(width: len, height: thick),
                                 center: CGPoint(x: dir * len / 2, y: 0))
        body.isDynamic = false            // kinematic: we rotate it, it kicks the ball
        body.categoryBitMask = Cat.flipper
        body.collisionBitMask = Cat.ball
        node.physicsBody = body
        addChild(node)
        return node
    }

    private func buildDrain() {
        // ONLY the centre gap between the flipper tips — not the whole width.
        let node = SKNode()
        node.position = pt(0.45, 0.97)
        let body = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 0.14, height: size.height * 0.015))
        body.isDynamic = false
        body.categoryBitMask = Cat.drain
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.ball
        node.physicsBody = body
        addChild(node)
    }

    // MARK: Ball

    private func spawnBall() {
        ball?.removeFromParent()
        let r = ballRadius
        let node = SKShapeNode(circleOfRadius: r)
        node.fillColor = .white
        node.strokeColor = SKColor(white: 0.65, alpha: 1)
        node.lineWidth = 1
        node.position = pt(0.895, 0.92)        // resting on the lane floor (backstop)
        node.zPosition = 5
        let body = SKPhysicsBody(circleOfRadius: r)
        body.isDynamic = true
        body.mass = ballMass
        body.restitution = 0.18
        body.friction = 0.1
        body.linearDamping = 0.1
        body.usesPreciseCollisionDetection = true   // no tunnelling at launch speed
        body.categoryBitMask = Cat.ball
        body.collisionBitMask = Cat.wall | Cat.flipper | Cat.bumper | Cat.sling | Cat.target
        body.contactTestBitMask = Cat.bumper | Cat.sling | Cat.target | Cat.rollover | Cat.drain
        node.physicsBody = body
        ball = node
        addChild(node)
        awaitingLaunch = true
        pushModel()
    }

    private func launch() {
        guard awaitingLaunch, let b = ball?.physicsBody else { return }
        awaitingLaunch = false
        // Velocity-based launch is predictable regardless of mass/gravity scale.
        b.velocity = CGVector(dx: 0, dy: size.height * launchSpeedFrac)
        pushModel()
    }

    // MARK: Flippers

    private func flip(left: Bool, up: Bool) {
        guard let node = left ? leftFlipper : rightFlipper else { return }
        let rest = left ? leftRest : rightRest
        let flipped = left ? leftFlip : rightFlip
        node.removeAllActions()
        node.run(.rotate(toAngle: up ? flipped : rest, duration: flipDuration, shortestUnitArc: true))
        if up && hapticsEnabled { Haptics.light() }
    }

    // MARK: Touch input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if awaitingLaunch { launch(); continue }
            let x = t.location(in: self).x
            flip(left: x < size.width / 2, up: true)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let x = t.location(in: self).x
            flip(left: x < size.width / 2, up: false)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        flip(left: true, up: false)
        flip(left: false, up: false)
    }

    // MARK: Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        let a = contact.bodyA, b = contact.bodyB
        let other = (a.categoryBitMask == Cat.ball) ? b : a
        switch other.categoryBitMask {
        case Cat.bumper:   hitBumper(other.node)
        case Cat.sling:    hitSling(other.node)
        case Cat.target:   hitScorer(other.node, points: targetScore, cooldown: 0.4)
        case Cat.rollover: hitScorer(other.node, points: rolloverScore, cooldown: 0.4)
        case Cat.drain:    drainBall()
        default: break
        }
    }

    private func hitBumper(_ node: SKNode?) {
        guard let node = node, let bb = ball?.physicsBody, let ballNode = ball else { return }
        kick(from: node.position, to: ballNode.position, body: bb, magnitude: bumperImpulse)
        addScore(bumperScore)
        flash(node)
        if hapticsEnabled { Haptics.light() }
    }

    private func hitSling(_ node: SKNode?) {
        guard let node = node, let bb = ball?.physicsBody, let ballNode = ball else { return }
        kick(from: node.position, to: ballNode.position, body: bb, magnitude: slingImpulse)
        addScore(slingScore)
        flash(node)
    }

    /// Score a standup target / rollover, then briefly disable it so an
    /// overlapping ball doesn't re-trigger every frame.
    private func hitScorer(_ node: SKNode?, points: Int, cooldown: Double) {
        guard let node = node, node.physicsBody?.contactTestBitMask != 0 else { return }
        addScore(points)
        flash(node)
        node.physicsBody?.contactTestBitMask = 0
        node.run(.sequence([.wait(forDuration: cooldown),
                            .run { [weak node] in node?.physicsBody?.contactTestBitMask = Cat.ball }]))
    }

    private func drainBall() {
        guard let b = ball else { return }
        b.removeFromParent()
        ball = nil
        ballsLeft -= 1
        if ballsLeft <= 0 {
            isOver = true
            pushModel()
        } else {
            spawnBall()
        }
    }

    // MARK: Helpers

    private func kick(from origin: CGPoint, to target: CGPoint, body: SKPhysicsBody, magnitude: CGFloat) {
        let dx = target.x - origin.x, dy = target.y - origin.y
        let len = max(hypot(dx, dy), 0.001)
        body.applyImpulse(CGVector(dx: dx / len * magnitude, dy: dy / len * magnitude))
    }

    private func addScore(_ n: Int) {
        score += n
        model?.score = score
    }

    private func flash(_ node: SKNode) {
        node.run(.sequence([.scale(to: 1.18, duration: 0.05),
                            .scale(to: 1.0, duration: 0.09)]))
    }

    private func pushModel() {
        model?.score = score
        model?.ballsLeft = ballsLeft
        model?.awaitingLaunch = awaitingLaunch
        model?.isOver = isOver
    }
}
