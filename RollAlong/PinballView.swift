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

    let aspect: Double
    let walls: [[[Double]]]
    let bumpers: [Bumper]
    let slings: [[[Double]]]
    let flippers: [Flip]
    let ballStart: P
    let drain: Drain

    static let shared: CleanTable = {
        try! JSONDecoder().decode(CleanTable.self, from: Data(json.utf8))
    }()
    static let json = #"""
{"aspect":1.9,"walls":[[[0.4,0.95],[0.4,0.95],[0.3754,0.948],[0.3517,0.9455],[0.3289,0.9423],[0.3069,0.9386],[0.2859,0.9343],[0.2656,0.9294],[0.2463,0.9239],[0.2278,0.9178],[0.2102,0.9111],[0.1934,0.9038],[0.1775,0.896],[0.1625,0.8875],[0.1484,0.8785],[0.1351,0.8688],[0.1227,0.8586],[0.1111,0.8478],[0.1004,0.8364],[0.0906,0.8244],[0.0817,0.8118],[0.0736,0.7986],[0.0664,0.7848],[0.0601,0.7705],[0.0546,0.7555],[0.05,0.74],[0.05,0.16],[0.05,0.16],[0.0504,0.1498],[0.0515,0.14],[0.0533,0.1306],[0.0558,0.1216],[0.0591,0.113],[0.0631,0.1049],[0.0679,0.0971],[0.0733,0.0898],[0.0795,0.0828],[0.0865,0.0763],[0.0941,0.0702],[0.1025,0.0645],[0.1116,0.0592],[0.1215,0.0543],[0.132,0.0498],[0.1433,0.0458],[0.1554,0.0421],[0.1681,0.0389],[0.1816,0.036],[0.1958,0.0336],[0.2108,0.0316],[0.2265,0.03],[0.2429,0.0288],[0.26,0.028],[0.26,0.028],[0.2758,0.0262],[0.2917,0.0245],[0.3075,0.023],[0.3233,0.0217],[0.3392,0.0205],[0.355,0.0195],[0.3708,0.0187],[0.3867,0.018],[0.4025,0.0175],[0.4183,0.0172],[0.4342,0.017],[0.45,0.017],[0.4658,0.0172],[0.4817,0.0175],[0.4975,0.018],[0.5133,0.0187],[0.5292,0.0195],[0.545,0.0205],[0.5608,0.0217],[0.5767,0.023],[0.5925,0.0245],[0.6083,0.0262],[0.6242,0.028],[0.64,0.03],[0.64,0.03],[0.6547,0.0327],[0.6687,0.0356],[0.6822,0.0389],[0.695,0.0425],[0.7072,0.0464],[0.7188,0.0506],[0.7297,0.0552],[0.74,0.06],[0.7497,0.0652],[0.7587,0.0706],[0.7672,0.0764],[0.775,0.0825],[0.7822,0.0889],[0.7888,0.0956],[0.7947,0.1027],[0.8,0.11],[0.8047,0.1177],[0.8087,0.1256],[0.8122,0.1339],[0.815,0.1425],[0.8172,0.1514],[0.8187,0.1606],[0.8197,0.1702],[0.82,0.18],[0.82,0.74],[0.82,0.74],[0.8163,0.7555],[0.8118,0.7705],[0.8066,0.7848],[0.8006,0.7986],[0.7938,0.8118],[0.7862,0.8244],[0.778,0.8364],[0.7689,0.8478],[0.7591,0.8586],[0.7485,0.8688],[0.7371,0.8785],[0.725,0.8875],[0.7121,0.896],[0.6985,0.9038],[0.6841,0.9111],[0.6689,0.9178],[0.653,0.9239],[0.6362,0.9294],[0.6188,0.9343],[0.6006,0.9386],[0.5816,0.9423],[0.5618,0.9455],[0.5413,0.948],[0.52,0.95]],[[0.93,0.95],[0.93,0.13],[0.93,0.13],[0.9298,0.1231],[0.9294,0.1164],[0.9286,0.1101],[0.9275,0.104],[0.9261,0.0983],[0.9244,0.0928],[0.9223,0.0876],[0.92,0.0828],[0.9173,0.0782],[0.9144,0.0739],[0.9111,0.0699],[0.9075,0.0663],[0.9036,0.0629],[0.8994,0.0598],[0.8948,0.057],[0.89,0.0544],[0.8848,0.0522],[0.8794,0.0503],[0.8736,0.0487],[0.8675,0.0474],[0.8611,0.0463],[0.8544,0.0456],[0.8473,0.0451],[0.84,0.045]],[[0.84,0.95],[0.84,0.2]]],"bumpers":[{"x":0.3,"y":0.3,"r":0.046},{"x":0.57,"y":0.3,"r":0.046},{"x":0.435,"y":0.22,"r":0.046}],"slings":[[[0.2,0.78],[0.3,0.83],[0.2,0.85]],[[0.64,0.78],[0.54,0.83],[0.64,0.85]]],"flippers":[{"pivot":[0.27,0.865],"tip":[0.42,0.915],"side":"L"},{"pivot":[0.61,0.865],"tip":[0.45,0.915],"side":"R"}],"ballStart":{"x":0.46,"y":0.12},"drain":{"x":0.45,"y":0.965,"w":0.12,"h":0.02}}
"""#
}

// MARK: - SwiftUI host

struct PinballView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator
    @State private var scene = PinballScene(size: CGSize(width: 393, height: 760))

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
                    Text("Chipmunk physics — tap to nudge")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color(white: 0.55))
                    Spacer()
                    Color.clear.frame(width: 34, height: 34)
                }
                .padding(.horizontal, 16).padding(.top, 8)
                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { scene.scaleMode = .resizeFill }
    }
}

// MARK: - Chipmunk-driven scene

final class PinballScene: SKScene {

    // Tuning as fractions of the field (resolution-independent; matches harness).
    private let gravFrac:    CGFloat = 1500.0 / 1064.0   // harness grav at H=1064
    private let ballRadFrac: CGFloat = 0.018
    private let wallElast:   Double = 0.30
    private let wallFric:    Double = 0.20

    private var space: OpaquePointer?
    private var ballBody: OpaquePointer?
    private var ballNode: SKShapeNode?
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
        guard built, let space = space, let ballBody = ballBody else { return }
        for _ in 0..<2 { cpSpaceStep(space, 1.0 / 120.0) }
        let p = cpBodyGetPosition(ballBody)
        ballNode?.position = CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
        // respawn when it falls past the bottom of the field
        if CGFloat(p.y) < field.minY - ballRadius * 2 { resetBall(launch: false) }
    }

    private func computeField() {
        let a = CGFloat(CleanTable.shared.aspect)     // height / width
        var w = size.width, h = w * a
        if h > size.height { h = size.height; w = h / a }
        field = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func buildSpace() {
        let space = cpSpaceNew()
        self.space = space
        cpSpaceSetGravity(space, cpVect(x: 0, y: Double(-field.height * gravFrac)))
        let sb = cpSpaceGetStaticBody(space)

        for wall in CleanTable.shared.walls where wall.count >= 2 {
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

        spawnBall()
    }

    private func spawnBall() {
        guard let space = space else { return }
        let r = Double(ballRadius)
        let body = cpBodyNew(1.0, cpMomentForCircle(1.0, 0, r, cpVect(x: 0, y: 0)))
        cpSpaceAddBody(space, body)
        let shape = cpCircleShapeNew(body, r, cpVect(x: 0, y: 0))
        cpShapeSetElasticity(shape, 0.35); cpShapeSetFriction(shape, 0.2)
        cpSpaceAddShape(space, shape)
        ballBody = body

        let node = SKShapeNode(circleOfRadius: ballRadius)
        node.fillColor = .white; node.strokeColor = SKColor(white: 0.65, alpha: 1); node.lineWidth = 1
        node.zPosition = 5
        ballNode = node
        addChild(node)

        resetBall(launch: false)
    }

    private func resetBall(launch: Bool) {
        guard let ballBody = ballBody else { return }
        let s = CleanTable.shared.ballStart
        cpBodySetPosition(ballBody, v(pt(s.x, s.y)))
        cpBodySetVelocity(ballBody, cpVect(x: launch ? 220 : 0, y: launch ? -260 : 0))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // nudge the ball back into play so the physics is easy to watch
        resetBall(launch: true)
    }
}
