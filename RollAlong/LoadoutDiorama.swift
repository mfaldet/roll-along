import SwiftUI
import UIKit

// ===========================================================================
// Loadout — a value-typed bundle of the cosmetics a preview draws "in action".
// Music is carried for labelling/completeness but is heard, not drawn.  Value
// semantics mean a preview renders identically wherever it's reused: the
// profile's "My Loadout", the catalog collection popup, and the challenge-pack
// showcase all feed the same LoadoutDiorama a Loadout.
// ===========================================================================
struct Loadout: Equatable {
    var ball:     BallSkin
    var trail:    TrailColor
    var goal:     GoalSkin
    var floor:    Floor
    var pit:      Pit
    var boundary: Boundary

    init(ball: BallSkin, trail: TrailColor, goal: GoalSkin,
         floor: Floor, pit: Pit, boundary: Boundary) {
        self.ball = ball; self.trail = trail; self.goal = goal
        self.floor = floor; self.pit = pit; self.boundary = boundary
    }
}

extension Loadout {
    /// Build a preview Loadout from a CosmeticBundle: the first cosmetic in each
    /// slot the bundle defines, falling back to the starter/classic look for any
    /// slot it omits (e.g. Planets carries only balls).  Bundles carry no
    /// boundary, so the boundary is always the classic wall.
    init(bundle: CosmeticBundle) {
        self.init(
            ball:     bundle.balls.first  ?? .red,
            trail:    bundle.trails.first ?? .graphite,
            goal:     bundle.goals.first  ?? .target,
            floor:    bundle.floors.first ?? .classic,
            pit:      bundle.pits.first   ?? .classic,
            boundary: .classic
        )
    }
}

// ===========================================================================
// RunReplay — a recorded stretch of real Adventure play.
//
// No video: the ball's position every frame, the moments a coin, the goal or
// a pit happened, and the level layout needed to draw it.  Previews play it
// back with the viewer's own cosmetics (LoadoutDiorama below); no physics runs.
//
// Positions are normalized to the play area (0…1 across, 0…1 down), so a
// recording made on any iPhone plays back at any preview size.  Sizes (ball,
// goal, coins) are stored in points together with the play-area size they
// were recorded at.
//
// The bundled recording is RollAlong/PreviewReplay.json.  How to record and
// swap in a new one: docs/replay-previews.md.
// ===========================================================================
struct RunReplay: Codable {
    struct Rect:  Codable { var x: Double; var y: Double; var w: Double; var h: Double }
    struct Point: Codable { var x: Double; var y: Double }
    struct Event: Codable {
        enum Kind: String, Codable { case coin, goal, pit }
        /// Seconds since the first frame.
        var t: Double
        var kind: Kind
        /// For a coin: its index in `coins`.
        var index: Int?
    }

    /// File format version.
    var version: Int
    /// Frames per second the run was recorded at (informational; every frame
    /// carries its own time).
    var fps: Double
    /// Play-area size in points when recorded.
    var arenaWidth: Double
    var arenaHeight: Double
    /// Ball radius in points when recorded, before the skin's size scale.
    var ballRadius: Double
    /// Coin radius in points when recorded.
    var coinRadius: Double
    /// The Adventure level it was recorded on (informational).
    var level: Int?
    /// Pits, as normalized rectangles.
    var holes: [Rect]
    /// Goal center, normalized.
    var goal: Point
    /// Coins, normalized.
    var coins: [Point]
    /// One entry per frame: [seconds, x, y, roll].  x and y are normalized.
    /// `roll` is the angle (radians) a rolling ball would have turned by,
    /// from distance travelled ÷ radius.  The game draws the ball without
    /// rotation, so playback does not use it; it is kept for later.
    var frames: [[Double]]
    var events: [Event]

    /// Enough well-formed data to play back.  A file that fails this is
    /// ignored and the preview shows a still picture instead.
    var isUsable: Bool {
        guard version >= 1, arenaWidth > 1, arenaHeight > 1,
              ballRadius > 0, ballRadius.isFinite, frames.count >= 2 else { return false }
        var last = -Double.infinity
        for f in frames {
            guard f.count >= 3, f[0].isFinite, f[1].isFinite, f[2].isFinite, f[0] >= last else { return false }
            last = f[0]
        }
        return goal.x.isFinite && goal.y.isFinite
    }

    var duration: Double { frames.last?[0] ?? 0 }

    /// Time of the first goal or pit event (where the run ends), if any.
    var endEventTime: Double? {
        events.first { $0.kind == .goal || $0.kind == .pit }?.t
    }
    var endKind: Event.Kind? {
        events.first { $0.kind == .goal || $0.kind == .pit }?.kind
    }

    /// Ball position (points, recorded play-area space) at time `t`,
    /// interpolated between frames; clamped to the first/last frame.
    func position(at t: Double) -> CGPoint {
        guard let first = frames.first, let last = frames.last else { return .zero }
        if t <= first[0] { return point(first) }
        if t >= last[0] { return point(last) }
        var lo = 0, hi = frames.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if frames[mid][0] <= t { lo = mid } else { hi = mid }
        }
        let a = frames[lo], b = frames[hi]
        let span = b[0] - a[0]
        let u = span > 0 ? (t - a[0]) / span : 0
        return CGPoint(x: CGFloat((a[1] + (b[1] - a[1]) * u) * arenaWidth),
                       y: CGFloat((a[2] + (b[2] - a[2]) * u) * arenaHeight))
    }

    /// Frame positions (points) with their times between `from` and `to`,
    /// oldest first.
    func samples(from: Double, to: Double) -> [(t: Double, p: CGPoint)] {
        var out: [(t: Double, p: CGPoint)] = []
        for f in frames where f[0] >= from && f[0] <= to {
            out.append((t: f[0], p: point(f)))
        }
        return out
    }

    private func point(_ f: [Double]) -> CGPoint {
        CGPoint(x: CGFloat(f[1] * arenaWidth), y: CGFloat(f[2] * arenaHeight))
    }
}

// ===========================================================================
// ReplayStore — which recording previews play.
//
// Order: the player's own recording on this phone (only when they chose "Use
// my recording on this phone", which only TestFlight/debug builds offer), then
// the bundled PreviewReplay.json, then nothing (still picture).
// ===========================================================================
enum ReplayStore {
    static let bundledName = "PreviewReplay"
    /// UserDefaults: file name (in Documents) of the recording to use instead
    /// of the bundled one on this phone.
    static let localUseKey = "ra_previewReplayUseLocal"

    private static var cached: RunReplay?
    private static var loaded = false

    static var current: RunReplay? {
        if !loaded { cached = load(); loaded = true }
        return cached
    }

    static func reload() { loaded = false }

    static func decode(_ data: Data) -> RunReplay? {
        guard let r = try? JSONDecoder().decode(RunReplay.self, from: data), r.isUsable else { return nil }
        return r
    }

    private static func load() -> RunReplay? {
        if let name = UserDefaults.standard.string(forKey: localUseKey),
           let url = ReplayRecorder.documentsURL(name),
           let data = try? Data(contentsOf: url),
           let local = decode(data) {
            return local
        }
        guard let url = Bundle.main.url(forResource: bundledName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }
}

// ===========================================================================
// ReplayRecorder — records one stretch of real Adventure play.
//
// Only in debug and TestFlight builds (`isAvailable`); an App Store build can
// never arm it.  Arming: long-press any loadout preview → "Record next
// Adventure run".  The next Adventure level played is then recorded from the
// moment play starts until the goal, a fall, or `maxSeconds`, and saved as a
// JSON file in the app's Documents folder.  The same long-press menu shares
// the file (AirDrop / Save to Files) and can use it on this phone.
//
// BallGameView calls `beginIfArmed`, `frame`, `event` and `finish`; each is a
// single Bool check when not recording, so the cost when off is nothing.
// ===========================================================================
final class ReplayRecorder: ObservableObject {
    static let shared = ReplayRecorder()

    /// True in debug builds and TestFlight builds; false in App Store builds.
    static var isAvailable: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    /// The longest run kept, in seconds.
    static let maxSeconds: Double = 20
    private static let lastFileKey = "ra_previewReplayLastFile"

    /// Waiting for the next Adventure level to start.
    @Published private(set) var armed = false
    /// The most recent recording on this phone.
    @Published private(set) var lastRecordingURL: URL?
    /// Bumped whenever the recording previews play changes.
    @Published private(set) var revision = 0

    private var recording = false
    private var startTime: Double?
    private var frames: [[Double]] = []
    private var events: [RunReplay.Event] = []
    private var snapshot: (holes: [RunReplay.Rect], goal: RunReplay.Point,
                           coins: [RunReplay.Point], level: Int)?
    private var arena: CGSize = .zero
    private var radius: CGFloat = 18
    private var coinRadius: CGFloat = 9
    private var roll: Double = 0
    private var lastPoint: CGPoint?

    private init() {
        if let name = UserDefaults.standard.string(forKey: Self.lastFileKey),
           let url = Self.documentsURL(name),
           FileManager.default.fileExists(atPath: url.path) {
            lastRecordingURL = url
        }
    }

    static func documentsURL(_ name: String) -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(name)
    }

    /// Whether previews on this phone play the player's own recording.
    var usingLocalRecording: Bool {
        UserDefaults.standard.string(forKey: ReplayStore.localUseKey) != nil
    }

    func arm() {
        guard Self.isAvailable else { return }
        armed = true
    }

    func disarm() {
        armed = false
        recording = false
    }

    /// Use the latest recording in previews on this phone (`true`), or go
    /// back to the bundled one (`false`).
    func useLatestOnThisPhone(_ on: Bool) {
        if on, let url = lastRecordingURL {
            UserDefaults.standard.set(url.lastPathComponent, forKey: ReplayStore.localUseKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ReplayStore.localUseKey)
        }
        ReplayStore.reload()
        revision += 1
    }

    // ── Hooks called by BallGameView ─────────────────────────────────────

    /// An Adventure level was spawned.  Starts a recording if armed.
    func beginIfArmed(layout: LevelLayout, arena: CGSize, ballRadius: CGFloat,
                      coinRadius: CGFloat, level: Int) {
        guard armed, arena.width > 0, arena.height > 0 else { return }
        self.arena = arena
        self.radius = ballRadius
        self.coinRadius = coinRadius
        snapshot = (
            holes: layout.holeRects.map {
                RunReplay.Rect(x: Double($0.origin.x), y: Double($0.origin.y),
                               w: Double($0.width), h: Double($0.height))
            },
            goal: RunReplay.Point(x: Double(layout.goal.x), y: Double(layout.goal.y)),
            coins: layout.coins.map { RunReplay.Point(x: Double($0.x), y: Double($0.y)) },
            level: level)
        frames = []
        events = []
        startTime = nil
        roll = 0
        lastPoint = nil
        recording = true
    }

    /// A level that is not Adventure was spawned: drop any half-made run.
    func cancelRun() {
        guard recording else { return }
        recording = false
    }

    /// One physics frame: the ball's position in play-area points.
    func frame(_ p: CGPoint) {
        guard recording else { return }
        let now = Date().timeIntervalSinceReferenceDate
        if startTime == nil { startTime = now }
        let t = now - (startTime ?? now)
        if let last = lastPoint, radius > 0 {
            roll += Double(hypot(p.x - last.x, p.y - last.y) / radius)
        }
        lastPoint = p
        frames.append([Self.round(t, 1_000),
                       Self.round(Double(p.x / arena.width), 10_000),
                       Self.round(Double(p.y / arena.height), 10_000),
                       Self.round(roll, 100)])
        if t >= Self.maxSeconds { finish(nil) }
    }

    /// A coin was picked up (index into the level's coins).
    func coin(_ index: Int) {
        guard recording else { return }
        events.append(RunReplay.Event(t: currentTime, kind: .coin, index: index))
    }

    /// The run ended: the goal, a pit, or nil for the time limit.
    func finish(_ kind: RunReplay.Event.Kind?) {
        guard recording else { return }
        if let kind { events.append(RunReplay.Event(t: currentTime, kind: kind, index: nil)) }
        recording = false
        armed = false
        save()
    }

    private var currentTime: Double {
        guard let s = startTime else { return 0 }
        return Self.round(Date().timeIntervalSinceReferenceDate - s, 1_000)
    }

    private static func round(_ v: Double, _ scale: Double) -> Double {
        (v * scale).rounded() / scale
    }

    private func save() {
        guard let snap = snapshot, frames.count >= 2 else { return }
        let replay = RunReplay(
            version: 1, fps: 60,
            arenaWidth: Self.round(Double(arena.width), 10),
            arenaHeight: Self.round(Double(arena.height), 10),
            ballRadius: Double(radius), coinRadius: Double(coinRadius),
            level: snap.level, holes: snap.holes, goal: snap.goal, coins: snap.coins,
            frames: frames, events: events)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(replay) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let name = "PreviewReplay-\(stamp).json"
        guard let url = Self.documentsURL(name) else { return }
        do {
            try data.write(to: url, options: .atomic)
            UserDefaults.standard.set(name, forKey: Self.lastFileKey)
            lastRecordingURL = url
        } catch {
            // Nothing to do: the recording is simply not kept.
        }
    }
}

// ===========================================================================
// LoadoutDiorama — a loadout "in action": a recorded run of real Adventure
// play (RunReplay) looping in the preview, drawn with the given cosmetics.
//
// Every layer reuses the game's own renderer, so the preview matches play:
//   floor   — Floor.color + FloorOverlayView + PaperFloorOverlayView
//   pits    — Pit.color + PitOverlayView + PitDepthShade
//   goal    — GoalSkinView (and GoalBurstView when the run reaches it)
//   coins   — SpinningCoinView
//   trail   — drawRichTrail (the same function the game calls)
//   ball    — BallSkinView, at the skin's real size scale
//   border  — the boundary stroke + BoundaryOverlayView
//   falls   — PitLandingView when the run ends in a pit
// The world (floor, pits, goal, coins, trail, ball) is drawn at the game's
// scale and fitted to the preview by a fixed camera framed on the stretch of
// play; the boundary hugs the preview's own edge, as it hugs the screen.
//
// Reduce Motion: a still frame just before the end of the run, with the
// trail behind the ball.  No recording available: a still picture of the
// floor, goal and ball.
// ===========================================================================
struct LoadoutDiorama: View {
    let loadout: Loadout
    /// Corner treatment.  Default rounds + hairlines the preview itself; pass
    /// `nil` when an outer container already clips (e.g. the challenge-pack
    /// showcase card, radius 18) so the two clips don't fight.
    var cornerRadius: CGFloat? = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var recorder = ReplayRecorder.shared

    /// Seconds kept after the goal or fall so the ending reads.
    private let endHold = 0.7
    /// The longest stretch played, in seconds (the end of the run).
    private let maxClip = 6.5

    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            let scene = ZStack {
                if let replay = ReplayStore.current, s.width > 1, s.height > 1 {
                    replayScene(replay, size: s)
                } else {
                    stillScene(s)
                }
                boundaryRing
            }
            .id(recorder.revision)
            if let r = cornerRadius {
                scene
                    .clipShape(RoundedRectangle(cornerRadius: r))
                    .overlay(RoundedRectangle(cornerRadius: r)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8))
            } else {
                scene.clipShape(Rectangle())
            }
        }
        .modifier(ReplayRecorderMenu(recorder: recorder))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of a run with this ball, trail, floor, goal, pit and boundary")
    }

    // ── The clip and the camera ──────────────────────────────────────────

    /// The stretch of the run that loops: the last `maxClip` seconds before
    /// the goal or fall, plus `endHold`.
    private struct Clip {
        let start: Double
        let end: Double          // end of the run (goal / fall / last frame)
        let loopEnd: Double      // end + hold
        var length: Double { max(0.5, loopEnd - start) }
    }

    private func clip(_ r: RunReplay) -> Clip {
        let first = r.frames.first?[0] ?? 0
        let end = r.endEventTime ?? r.duration
        let start = max(first, end - maxClip)
        return Clip(start: start, end: end, loopEnd: end + endHold)
    }

    /// A fixed view onto the recorded play area: `origin` and `scale` map a
    /// recorded point to the preview (`(p - origin) * scale`).
    private struct Camera {
        let origin: CGPoint
        let scale: CGFloat
        let region: CGSize
        func view(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - origin.x) * scale, y: (p.y - origin.y) * scale)
        }
    }

    /// Frame the clip's path (plus the goal) with some room around it, at
    /// the preview's aspect ratio, inside the play area where possible.
    private func camera(_ r: RunReplay, clip c: Clip, size s: CGSize) -> Camera {
        let aw = CGFloat(r.arenaWidth), ah = CGFloat(r.arenaHeight)
        let br = CGFloat(r.ballRadius)
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        func include(_ p: CGPoint) {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        for sample in r.samples(from: c.start, to: c.end) { include(sample.p) }
        if r.endKind == .goal {
            include(CGPoint(x: CGFloat(r.goal.x) * aw, y: CGFloat(r.goal.y) * ah))
        }
        if !minX.isFinite { include(r.position(at: 0)) }
        let pad = br * 2.5
        var w = max(maxX - minX + pad * 2, br * 8)
        var h = max(maxY - minY + pad * 2, br * 8)
        let aspect = s.width / s.height
        if w / h < aspect { w = h * aspect } else { h = w / aspect }
        var ox = (minX + maxX) / 2 - w / 2
        var oy = (minY + maxY) / 2 - h / 2
        ox = w <= aw ? min(max(ox, 0), aw - w) : (aw - w) / 2
        oy = h <= ah ? min(max(oy, 0), ah - h) : (ah - h) / 2
        return Camera(origin: CGPoint(x: ox, y: oy), scale: s.width / w,
                      region: CGSize(width: w, height: h))
    }

    // ── The replay ───────────────────────────────────────────────────────

    @ViewBuilder
    private func replayScene(_ r: RunReplay, size s: CGSize) -> some View {
        let c = clip(r)
        let cam = camera(r, clip: c, size: s)
        ZStack {
            floorLayer(cam, size: s)
            pitsLayer(r, cam)
            goalLayer(r, cam)
            if reduceMotion {
                movingLayer(r, cam, clip: c, size: s, t: max(c.start, c.end - 0.35),
                            alpha: 1, wallNow: 0)
            } else {
                TimelineView(.animation) { tl in
                    let now = tl.date.timeIntervalSinceReferenceDate
                    let raw = now.truncatingRemainder(dividingBy: c.length)
                    let alpha: Double = raw < 0.15 ? raw / 0.15
                        : (raw > c.length - 0.25 ? max(0, (c.length - raw) / 0.25) : 1)
                    movingLayer(r, cam, clip: c, size: s, t: c.start + raw,
                                alpha: alpha, wallNow: now)
                }
            }
        }
        .frame(width: s.width, height: s.height)
    }

    /// The floor, drawn at the game's scale over the camera's region.
    private func floorLayer(_ cam: Camera, size s: CGSize) -> some View {
        let showOverlay = !(reduceMotion && FloorOverlayView.hiddenUnderReduceMotion(loadout.floor))
        return ZStack {
            loadout.floor.color
            if showOverlay { FloorOverlayView(floor: loadout.floor) }
            PaperFloorOverlayView(floor: loadout.floor)
        }
        .frame(width: cam.region.width, height: cam.region.height)
        .scaleEffect(cam.scale, anchor: .topLeading)
        .frame(width: s.width, height: s.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// Pits, as the game draws them (base color, animated overlay, depth).
    private func pitsLayer(_ r: RunReplay, _ cam: Camera) -> some View {
        let aw = CGFloat(r.arenaWidth), ah = CGFloat(r.arenaHeight)
        return ForEach(Array(r.holes.enumerated()), id: \.offset) { _, h in
            let w = CGFloat(h.w) * aw * cam.scale
            let ht = CGFloat(h.h) * ah * cam.scale
            let center = cam.view(CGPoint(x: (CGFloat(h.x) + CGFloat(h.w) / 2) * aw,
                                          y: (CGFloat(h.y) + CGFloat(h.h) / 2) * ah))
            ZStack {
                Rectangle().fill(loadout.pit.color)
                if !reduceMotion { PitOverlayView(pit: loadout.pit) }
                PitDepthShade(width: w, height: ht)
            }
            .frame(width: max(1, w), height: max(1, ht))
            .clipped()
            .position(center)
        }
    }

    /// The goal, the game's size (2.8 × the ball radius).
    private func goalLayer(_ r: RunReplay, _ cam: Camera) -> some View {
        let d = CGFloat(r.ballRadius) * 2.8 * cam.scale
        let p = cam.view(CGPoint(x: CGFloat(r.goal.x * r.arenaWidth),
                                 y: CGFloat(r.goal.y * r.arenaHeight)))
        return GoalSkinView(goal: loadout.goal)
            .frame(width: d, height: d)
            .position(p)
    }

    /// Coins, trail, ball and the end-of-run flourish at run time `t`.
    @ViewBuilder
    private func movingLayer(_ r: RunReplay, _ cam: Camera, clip c: Clip, size s: CGSize,
                             t: Double, alpha: Double, wallNow: Double) -> some View {
        let aw = CGFloat(r.arenaWidth), ah = CGFloat(r.arenaHeight)
        let coinD = CGFloat(r.coinRadius) * 2 * cam.scale
        // Coins still on the floor at time t.
        ForEach(Array(r.coins.enumerated()), id: \.offset) { idx, coin in
            let takenAt = r.events.first { $0.kind == .coin && $0.index == idx }?.t
            if takenAt.map({ t < $0 }) ?? true {
                SpinningCoinView(size: max(4, coinD), phase: Double(idx) * 1.7)
                    .position(cam.view(CGPoint(x: CGFloat(coin.x) * aw, y: CGFloat(coin.y) * ah)))
            }
        }

        // Trail: the last 1.5 s of path (the game keeps ~90 frames), oldest
        // first, through the game's own trail renderer.
        if loadout.trail != .none {
            let tail = r.samples(from: max(c.start, t - 1.5), to: min(t, c.end))
            Canvas { ctx, _ in
                guard tail.count >= 2 else { return }
                let pts = tail.map { cam.view($0.p) }
                let times: [Double]? = wallNow > 0 ? tail.map { wallNow - (t - $0.t) } : nil
                drawRichTrail(ctx, points: pts, trail: loadout.trail,
                              t: wallNow > 0 ? wallNow : 0,
                              baseWidth: max(2, 6 * cam.scale), times: times)
            }
            .opacity(alpha)
            .allowsHitTesting(false)
        }

        // Ball — the real skin at its real size; shrinks into the goal or
        // sinks into the pit at the end, as in play.
        let endFade = t > c.end ? min(1, (t - c.end) / 0.28) : 0
        let shrinkTo: Double = r.endKind == .pit ? 0.12 : 0.05
        let ballD = CGFloat(r.ballRadius) * 2 * loadout.ball.radiusScale * cam.scale
        BallSkinView(skin: loadout.ball, diameter: ballD)
            .frame(width: ballD, height: ballD)
            .shadow(color: .black.opacity(0.55), radius: 4 * cam.scale,
                    x: 2 * cam.scale, y: 5 * cam.scale)
            .scaleEffect(CGFloat(1 - (1 - shrinkTo) * endFade))
            .position(cam.view(r.position(at: min(t, c.end))))
            .opacity(alpha * (1 - endFade))

        // End-of-run flourish, on its own clock from the moment it happened.
        if wallNow > 0, t >= c.end, t - c.end < 0.75, let kind = r.endKind {
            let at = cam.view(r.position(at: c.end))
            let start = Date(timeIntervalSinceReferenceDate: wallNow - (t - c.end))
            if kind == .goal {
                GoalBurstView(event: GoalBurstEvent(center: at, start: start),
                              accent: loadout.goal.accentColor)
                    .allowsHitTesting(false)
            } else if kind == .pit {
                PitLandingView(event: PitLandingEvent(center: at, start: start, pit: loadout.pit))
                    .allowsHitTesting(false)
            }
        }
    }

    // ── Fallback and border ──────────────────────────────────────────────

    /// No usable recording: a still picture of the floor, goal and ball.
    private func stillScene(_ s: CGSize) -> some View {
        let ballD = min(38, max(18, min(s.width, s.height) * 0.17)) * loadout.ball.radiusScale
        let goalD = min(50, max(24, min(s.width, s.height) * 0.26))
        return ZStack {
            loadout.floor.color
            GoalSkinView(goal: loadout.goal)
                .frame(width: goalD, height: goalD)
                .position(x: s.width * 0.72, y: s.height * 0.42)
            BallSkinView(skin: loadout.ball, diameter: ballD)
                .frame(width: ballD, height: ballD)
                .shadow(color: .black.opacity(0.55), radius: 4, x: 2, y: 5)
                .position(x: s.width * 0.30, y: s.height * 0.62)
        }
    }

    /// The boundary, hugging the preview's edge as it hugs the screen in
    /// play: the base stroke plus the Legendary texture.
    private var boundaryRing: some View {
        let radius = cornerRadius ?? 18
        let base: Color = loadout.boundary == .classic ? Color(white: 0.68) : loadout.boundary.color
        return ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(base, lineWidth: 4)
            if !reduceMotion {
                BoundaryOverlayView(boundary: loadout.boundary, cornerRadius: radius)
            }
        }
        .allowsHitTesting(false)
    }
}

// ===========================================================================
// ReplayRecorderMenu — the long-press menu on a loadout preview that drives
// the recorder.  Attached only in debug and TestFlight builds; in an App Store
// build it changes nothing.
// ===========================================================================
private struct ReplayRecorderMenu: ViewModifier {
    @ObservedObject var recorder: ReplayRecorder

    @ViewBuilder
    func body(content: Content) -> some View {
        if ReplayRecorder.isAvailable {
            content.contextMenu {
                if recorder.armed {
                    Button(role: .destructive) { recorder.disarm() } label: {
                        Label("Cancel recording", systemImage: "stop.circle")
                    }
                } else {
                    Button { recorder.arm() } label: {
                        Label("Record next Adventure run", systemImage: "record.circle")
                    }
                }
                if let url = recorder.lastRecordingURL {
                    ShareLink(item: url) {
                        Label("Share last recording", systemImage: "square.and.arrow.up")
                    }
                    if recorder.usingLocalRecording {
                        Button { recorder.useLatestOnThisPhone(false) } label: {
                            Label("Use the built-in recording", systemImage: "arrow.uturn.backward")
                        }
                    } else {
                        Button { recorder.useLatestOnThisPhone(true) } label: {
                            Label("Use my recording on this phone", systemImage: "play.rectangle")
                        }
                    }
                }
            }
        } else {
            content
        }
    }
}
