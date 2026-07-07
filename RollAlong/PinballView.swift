//  PinballView.swift
//  Roll Along — Pinball minigame.
//
//  Physics: Chipmunk 7.0.3 (the `Chipmunk` SPM package) — the SAME engine the
//  Python tuning harness (tools/pinball) uses, so constants transfer 1:1.
//  Chipmunk drives the simulation; SpriteKit only renders (its own physics is
//  unused). The table is the clean COMPOSED layout (tools/pinball/gen_clean.py),
//  embedded + decoded at runtime.
//
//  FOUNDATION PASS: walls + a gravity-driven ball, to verify the Chipmunk C API
//  links + runs on device. Flippers / bumpers / launch / scoring come next once
//  this is confirmed.

import SwiftUI
import SpriteKit
import Chipmunk

// MARK: - Decoded table data

struct CleanTable: Codable {
    struct Bumper: Codable { let x, y, r: Double }
    struct Flip: Codable { let pivot: [Double]; let tip: [Double]; let side: String }
    struct P: Codable { let x, y: Double }
    struct Drain: Codable { let x, y, w, h: Double }
    struct Physics: Codable {
        let gravityFrac, launchFrac, ballRadiusFrac, ballMass, wallRestitution, wallFriction, ballRestitution: Double
        static let `default` = Physics(gravityFrac: 0.60, launchFrac: 2.07, ballRadiusFrac: 0.018,
                                       ballMass: 1.0, wallRestitution: 0.30, wallFriction: 0.20, ballRestitution: 0.35)
    }

    let aspect: Double
    let physics: Physics?          // absent in the embedded default → Physics.default
    let walls: [[[Double]]]
    let bumpers: [Bumper]
    let slings: [[[Double]]]
    let flippers: [Flip]
    let ballStart: P
    let drain: Drain

    static let shared: CleanTable = {
        try! JSONDecoder().decode(CleanTable.self, from: Data(json.utf8))
    }()
    /// A Marble Mapper export (Bundle `pinball-table.json`) if present, else the embedded default.
    static let resolved: CleanTable = {
        if let url = Bundle.main.url(forResource: "pinball-table", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let table = try? JSONDecoder().decode(CleanTable.self, from: data) {
            return table
        }
        return shared
    }()
    static let json = #"""
{"aspect":1.9,"walls":[[[0.4,0.95],[0.4,0.95],[0.3754,0.948],[0.3517,0.9455],[0.3289,0.9423],[0.3069,0.9386],[0.2859,0.9343],[0.2656,0.9294],[0.2463,0.9239],[0.2278,0.9178],[0.2102,0.9111],[0.1934,0.9038],[0.1775,0.896],[0.1625,0.8875],[0.1484,0.8785],[0.1351,0.8688],[0.1227,0.8586],[0.1111,0.8478],[0.1004,0.8364],[0.0906,0.8244],[0.0817,0.8118],[0.0736,0.7986],[0.0664,0.7848],[0.0601,0.7705],[0.0546,0.7555],[0.05,0.74],[0.05,0.16],[0.05,0.16],[0.0504,0.1498],[0.0515,0.1399],[0.0533,0.1305],[0.0558,0.1214],[0.0591,0.1128],[0.0631,0.1045],[0.0679,0.0966],[0.0733,0.0891],[0.0795,0.082],[0.0865,0.0753],[0.0941,0.0689],[0.1025,0.063],[0.1116,0.0574],[0.1215,0.0523],[0.132,0.0475],[0.1433,0.0431],[0.1554,0.0391],[0.1681,0.0355],[0.1816,0.0323],[0.1958,0.0294],[0.2108,0.027],[0.2265,0.0249],[0.2429,0.0233],[0.26,0.022],[0.26,0.022],[0.28,0.0206],[0.3,0.0192],[0.32,0.0181],[0.34,0.017],[0.36,0.0161],[0.38,0.0152],[0.4,0.0146],[0.42,0.014],[0.44,0.0136],[0.46,0.0132],[0.48,0.0131],[0.5,0.013],[0.52,0.0131],[0.54,0.0132],[0.56,0.0136],[0.58,0.014],[0.6,0.0146],[0.62,0.0152],[0.64,0.0161],[0.66,0.017],[0.68,0.0181],[0.7,0.0192],[0.72,0.0206],[0.74,0.022],[0.74,0.022],[0.7555,0.0254],[0.7703,0.0292],[0.7845,0.0334],[0.7981,0.0381],[0.8109,0.0431],[0.8231,0.0486],[0.8347,0.0545],[0.8456,0.0609],[0.8558,0.0677],[0.8653,0.0748],[0.8743,0.0825],[0.8825,0.0905],[0.8901,0.099],[0.897,0.1078],[0.9033,0.1172],[0.9089,0.1269],[0.9138,0.137],[0.9181,0.1476],[0.9218,0.1586],[0.9247,0.1701],[0.927,0.1819],[0.9287,0.1942],[0.9297,0.2069],[0.93,0.22],[0.93,0.95],[0.84,0.95]],[[0.84,0.95],[0.84,0.25]],[[0.5,0.95],[0.5,0.95],[0.5245,0.9488],[0.5482,0.9469],[0.5709,0.9442],[0.5928,0.9408],[0.6137,0.9367],[0.6338,0.9319],[0.6529,0.9263],[0.6711,0.92],[0.6884,0.913],[0.7049,0.9052],[0.7204,0.8967],[0.735,0.8875],[0.7487,0.8776],[0.7615,0.8669],[0.7734,0.8555],[0.7844,0.8433],[0.7945,0.8305],[0.8037,0.8169],[0.812,0.8026],[0.8194,0.7875],[0.8259,0.7717],[0.8315,0.7552],[0.8362,0.738],[0.84,0.72]]],"bumpers":[{"x":0.3,"y":0.3,"r":0.046},{"x":0.57,"y":0.3,"r":0.046},{"x":0.435,"y":0.22,"r":0.046}],"slings":[[[0.2,0.78],[0.3,0.83],[0.2,0.85]],[[0.64,0.78],[0.54,0.83],[0.64,0.85]]],"flippers":[{"pivot":[0.27,0.865],"tip":[0.42,0.915],"side":"L"},{"pivot":[0.61,0.865],"tip":[0.45,0.915],"side":"R"}],"ballStart":{"x":0.885,"y":0.92},"drain":{"x":0.45,"y":0.965,"w":0.12,"h":0.02}}
"""#
}

// MARK: - HUD model

final class PinballModel: ObservableObject {
    @Published var score = 0
    @Published var ballsLeft = 3
    @Published var awaitingLaunch = true
    @Published var isOver = false
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
            Color(white: 0.04).ignoresSafeArea()
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button { nav.goHome() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(Circle().fill(.black.opacity(0.45)))
                    }
                    Spacer()
                    VStack(spacing: 0) {
                        Text("\(model.score)")
                            .font(.system(.title2, design: .rounded).weight(.heavy)).monospacedDigit().foregroundStyle(.white)
                        Text("SCORE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(Color(white: 0.6))
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle().fill(i < model.ballsLeft ? Color.white : Color(white: 0.3)).frame(width: 9, height: 9)
                        }
                    }.frame(width: 34)
                }
                .padding(.horizontal, 16).padding(.top, 8)
                Spacer()
                if model.awaitingLaunch && !model.isOver {
                    Text("Tap to launch")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Capsule().fill(.black.opacity(0.5)))
                        .padding(.bottom, 54)
                }
            }

            if model.isOver { gameOverOverlay }

            // S2-T2: trophy-unlock banner host — inert until the game-over
            // overlay drains the queue (never mid-game; §6).
            TrophyToastHost(queue: gameState.trophyToasts,
                            hapticsEnabled: gameState.hapticsEnabled,
                            soundEnabled: gameState.soundEnabled)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            scene.scaleMode = .resizeFill; scene.model = model
            // S2-T2: a game begins — arm the toast queue so any trophy earned
            // this game coalesces and surfaces only at the game-over overlay.
            gameState.beginTrophyRun()
        }
        .onChange(of: model.isOver) { _, over in if over { submitScore() } }
    }

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("Game Over").font(.system(.largeTitle, design: .rounded).weight(.heavy)).foregroundStyle(.white)
                VStack(spacing: 2) {
                    Text("\(model.score)").font(.system(size: 52, design: .rounded).weight(.black)).monospacedDigit()
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.30))
                    Text("FINAL SCORE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(Color(white: 0.6))
                }
                HStack(spacing: 14) {
                    Button { playAgain() } label: {
                        Text("Play again").font(.system(.body, design: .rounded).weight(.bold)).foregroundStyle(.black)
                            .padding(.horizontal, 22).padding(.vertical, 12).background(Capsule().fill(.white))
                    }
                    Button { nav.goHome() } label: {
                        Text("Home").font(.system(.body, design: .rounded).weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 22).padding(.vertical, 12).background(Capsule().fill(Color(white: 0.22)))
                    }
                }
            }
        }
        // S2-T2: game ended — drain this game's trophies at the result screen,
        // coalesced (design.md §6).
        .onAppear { gameState.endTrophyRun() }
    }

    private func submitScore() {
        guard !didSubmit else { return }
        didSubmit = true
        let s = model.score
        if s / 125 > 0 { gameState.addCoins(s / 125) }
        gameState.recordPinballScore(s)
        if gameState.hapticsEnabled { Haptics.success() }
    }

    private func playAgain() { didSubmit = false; scene.resetGame(); gameState.beginTrophyRun() }
}

// MARK: - Chipmunk-driven scene

final class PinballScene: SKScene {

    // Tuning as fractions of the field (resolution-independent; matches harness).
    // Feel constants come from the resolved table's physics block (mapper-authored
    // or the embedded default), so tuning in Marble Mapper ships straight through.
    private var phys: CleanTable.Physics { CleanTable.resolved.physics ?? .default }
    private var gravFrac:    CGFloat { CGFloat(phys.gravityFrac) }
    private var ballRadFrac: CGFloat { CGFloat(phys.ballRadiusFrac) }
    private var launchFrac:  CGFloat { CGFloat(phys.launchFrac) }
    private var wallElast:   Double { phys.wallRestitution }
    private var wallFric:    Double { phys.wallFriction }

    private var space: OpaquePointer?
    private var ballBody: OpaquePointer?
    private var ballNode: SKShapeNode?
    private struct Flipper { let body: OpaquePointer; let motor: OpaquePointer; let node: SKShapeNode; let flipRate: Double; let holdRate: Double; let side: String }
    private var flippers: [Flipper] = []
    private final class Scorer {
        let center: CGPoint; let hitR: CGFloat; let node: SKShapeNode; let points: Int; var cd = 0
        init(_ center: CGPoint, _ hitR: CGFloat, _ node: SKShapeNode, _ points: Int) {
            self.center = center; self.hitR = hitR; self.node = node; self.points = points
        }
    }
    private var scorers: [Scorer] = []
    weak var model: PinballModel?
    private var score = 0
    private var ballsLeft = 3
    private var isOver = false
    private var awaitingLaunch = true
    private var lastTime: TimeInterval = 0
    private var stepAcc: TimeInterval = 0
    private var field = CGRect.zero
    private var built = false

    private var fw: CGFloat { field.width }
    private var ballRadius: CGFloat { fw * ballRadFrac }

    /// fx,fy in 0..1 of the playfield (fy top→bottom) → scene point (y up).
    private func pt(_ fx: Double, _ fy: Double) -> CGPoint {
        CGPoint(x: field.minX + CGFloat(fx) * field.width,
                y: field.maxY - CGFloat(fy) * field.height)
    }
    private func v(_ p: CGPoint) -> cpVect { cpVect(x: Double(p.x), y: Double(p.y)) }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.07, green: 0.07, blue: 0.10, alpha: 1)
    }

    override func update(_ currentTime: TimeInterval) {
        if !built && size.width > 4 {
            built = true
            computeField()
            buildSpace()
        }
        guard built, !isOver, let space = space, let ballBody = ballBody else { return }
        // step real elapsed time in fixed 1/240 substeps — framerate-independent,
        // matches the harness, so 120Hz devices don't run the sim 2× fast
        let dt = lastTime == 0 ? 1.0 / 120.0 : min(currentTime - lastTime, 1.0 / 20.0)
        lastTime = currentTime
        stepAcc += dt
        while stepAcc >= 1.0 / 240.0 { cpSpaceStep(space, 1.0 / 240.0); stepAcc -= 1.0 / 240.0 }
        let p = cpBodyGetPosition(ballBody)
        let bx = CGFloat(p.x), by = CGFloat(p.y)
        ballNode?.position = CGPoint(x: bx, y: by)
        for f in flippers { f.node.zRotation = CGFloat(cpBodyGetAngle(f.body)) }

        // proximity scoring (physics already handles the bounce)
        for s in scorers {
            if s.cd > 0 { s.cd -= 1; continue }
            let dx = bx - s.center.x, dy = by - s.center.y
            if dx * dx + dy * dy < s.hitR * s.hitR {
                score += s.points; model?.score = score
                s.cd = 20
                s.node.run(.sequence([.scale(to: 1.15, duration: 0.05), .scale(to: 1.0, duration: 0.08)]))
            }
        }

        // drain → lose a ball
        if by < field.minY - ballRadius * 2 {
            ballsLeft -= 1
            model?.ballsLeft = max(0, ballsLeft)
            if ballsLeft <= 0 {
                isOver = true; model?.isOver = true
                ballNode?.isHidden = true
            } else {
                resetBall()
            }
        }
    }

    private func computeField() {
        let a = CGFloat(CleanTable.resolved.aspect)     // height / width
        var w = size.width, h = w * a
        if h > size.height { h = size.height; w = h / a }
        field = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func buildSpace() {
        let space = cpSpaceNew()
        self.space = space
        cpSpaceSetGravity(space, cpVect(x: 0, y: Double(-field.height * gravFrac)))
        let sb = cpSpaceGetStaticBody(space)

        for wall in CleanTable.resolved.walls where wall.count >= 2 {
            // physics segments
            for i in 0..<(wall.count - 1) {
                let a = pt(wall[i][0], wall[i][1])
                let b = pt(wall[i + 1][0], wall[i + 1][1])
                let seg = cpSegmentShapeNew(sb, v(a), v(b), 2.0)
                cpShapeSetElasticity(seg, wallElast)
                cpShapeSetFriction(seg, wallFric)
                cpSpaceAddShape(space, seg)
            }
            // visible wall
            let path = CGMutablePath()
            path.addLines(between: wall.map { pt($0[0], $0[1]) })
            let node = SKShapeNode(path: path)
            node.strokeColor = SKColor(white: 0.62, alpha: 1); node.lineWidth = 2; node.lineJoin = .round
            addChild(node)
        }

        buildBumpers()
        buildSlings()
        spawnBall()
        buildFlippers()
    }

    private func spawnBall() {
        guard let space = space else { return }
        let r = Double(ballRadius)
        let m = phys.ballMass
        let body = cpBodyNew(m, cpMomentForCircle(m, 0, r, cpVect(x: 0, y: 0)))
        cpSpaceAddBody(space, body)
        let shape = cpCircleShapeNew(body, r, cpVect(x: 0, y: 0))
        cpShapeSetElasticity(shape, phys.ballRestitution); cpShapeSetFriction(shape, 0.2)
        cpSpaceAddShape(space, shape)
        ballBody = body

        let node = SKShapeNode(circleOfRadius: ballRadius)
        node.fillColor = .white; node.strokeColor = SKColor(white: 0.65, alpha: 1); node.lineWidth = 1
        node.zPosition = 5
        ballNode = node
        addChild(node)

        resetBall()
    }

    private func resetBall() {
        guard let ballBody = ballBody else { return }
        let s = CleanTable.resolved.ballStart
        cpBodySetPosition(ballBody, v(pt(s.x, s.y)))         // rest in the shooter lane
        cpBodySetVelocity(ballBody, cpVect(x: 0, y: 0))
        awaitingLaunch = true
        model?.awaitingLaunch = true
    }

    private func launch() {
        guard awaitingLaunch, let ballBody = ballBody else { return }
        awaitingLaunch = false
        model?.awaitingLaunch = false
        cpBodySetVelocity(ballBody, cpVect(x: 0, y: Double(field.height * launchFrac)))   // up the lane, around the orbit
    }

    private func buildFlippers() {
        guard let space = space else { return }
        let sb = cpSpaceGetStaticBody(space)
        let swing = 0.95, mass = 0.5, thick = Double(ballRadius * 1.3)
        for f in CleanTable.resolved.flippers {
            let pivot = pt(f.pivot[0], f.pivot[1]), tip = pt(f.tip[0], f.tip[1])
            let len = Double(max(hypot(tip.x - pivot.x, tip.y - pivot.y), 1))
            let rest = atan2(Double(tip.y - pivot.y), Double(tip.x - pivot.x))
            guard let body = cpBodyNew(mass, cpMomentForSegment(mass, cpVect(x: 0, y: 0), cpVect(x: len, y: 0), thick)) else { continue }
            cpBodySetPosition(body, v(pivot)); cpBodySetAngle(body, rest)
            cpSpaceAddBody(space, body)
            let shape = cpSegmentShapeNew(body, cpVect(x: 0, y: 0), cpVect(x: len, y: 0), thick)
            cpShapeSetElasticity(shape, 0.0); cpShapeSetFriction(shape, 0.5)
            cpSpaceAddShape(space, shape)
            cpSpaceAddConstraint(space, cpPivotJointNew(sb, body, v(pivot)))
            let lo: Double, hi: Double, flipRate: Double, holdRate: Double
            if f.side == "L" { lo = rest - swing; hi = rest;        flipRate = -28; holdRate =  18 }
            else             { lo = rest;         hi = rest + swing; flipRate =  28; holdRate = -18 }
            cpSpaceAddConstraint(space, cpRotaryLimitJointNew(sb, body, lo, hi))
            guard let motor = cpSimpleMotorNew(sb, body, holdRate) else { continue }
            cpConstraintSetMaxForce(motor, 8_000_000.0)
            cpSpaceAddConstraint(space, motor)
            let node = SKShapeNode(rect: CGRect(x: 0, y: -CGFloat(thick) / 2, width: CGFloat(len), height: CGFloat(thick)), cornerRadius: CGFloat(thick) / 2)
            node.fillColor = SKColor(red: 0.25, green: 0.55, blue: 1.0, alpha: 1); node.strokeColor = .white; node.lineWidth = 1
            node.position = pivot; node.zRotation = CGFloat(rest); node.zPosition = 4
            addChild(node)
            flippers.append(Flipper(body: body, motor: motor, node: node, flipRate: flipRate, holdRate: holdRate, side: f.side))
        }
    }

    private func buildBumpers() {
        guard let space = space else { return }
        let sb = cpSpaceGetStaticBody(space)
        for b in CleanTable.resolved.bumpers {
            let c = pt(b.x, b.y), r = CGFloat(b.r) * fw
            let shape = cpCircleShapeNew(sb, Double(r), v(c))
            cpShapeSetElasticity(shape, 1.05); cpShapeSetFriction(shape, 0.2)
            cpSpaceAddShape(space, shape)
            let node = SKShapeNode(circleOfRadius: r)
            node.fillColor = SKColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1); node.strokeColor = .white; node.lineWidth = 2
            node.position = c; node.zPosition = 3
            let cap = SKShapeNode(circleOfRadius: r * 0.42); cap.fillColor = SKColor(white: 0.1, alpha: 1); cap.strokeColor = .clear
            node.addChild(cap)
            addChild(node)
            scorers.append(Scorer(c, r + ballRadius + 4, node, 100))
        }
    }

    private func buildSlings() {
        guard let space = space else { return }
        let sb = cpSpaceGetStaticBody(space)
        for tri in CleanTable.resolved.slings where tri.count == 3 {
            let pts = tri.map { pt($0[0], $0[1]) }
            for i in 0..<3 {
                let a = pts[i], b = pts[(i + 1) % 3]
                let seg = cpSegmentShapeNew(sb, v(a), v(b), 2.0)
                cpShapeSetElasticity(seg, 0.85); cpShapeSetFriction(seg, 0.2)
                cpSpaceAddShape(space, seg)
            }
            let path = CGMutablePath(); path.addLines(between: pts); path.closeSubpath()
            let node = SKShapeNode(path: path)
            node.fillColor = SKColor(red: 0.90, green: 0.28, blue: 0.34, alpha: 1); node.strokeColor = .white; node.lineWidth = 1; node.zPosition = 3
            addChild(node)
            let cx = (pts[0].x + pts[1].x + pts[2].x) / 3, cy = (pts[0].y + pts[1].y + pts[2].y) / 3
            scorers.append(Scorer(CGPoint(x: cx, y: cy), ballRadius + fw * 0.05, node, 10))
        }
    }

    func resetGame() {
        score = 0; ballsLeft = 3; isOver = false
        model?.score = 0; model?.ballsLeft = 3; model?.isOver = false
        for s in scorers { s.cd = 0 }
        ballNode?.isHidden = false
        resetBall()
    }

    private func flip(left: Bool, up: Bool) {
        for f in flippers where (f.side == "L") == left {
            cpSimpleMotorSetRate(f.motor, up ? f.flipRate : f.holdRate)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if awaitingLaunch { launch(); continue }
            flip(left: t.location(in: self).x < size.width / 2, up: true)
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { flip(left: t.location(in: self).x < size.width / 2, up: false) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        flip(left: true, up: false); flip(left: false, up: false)
    }
}
