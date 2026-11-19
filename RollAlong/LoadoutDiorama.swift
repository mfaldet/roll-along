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
    /// slot it omits.  Every collection now carries a boundary too.
    init(bundle: CosmeticBundle) {
        self.init(
            ball:     bundle.balls.first  ?? .red,
            trail:    bundle.trails.first ?? .graphite,
            goal:     bundle.goals.first  ?? .target,
            floor:    bundle.floors.first ?? .classic,
            pit:      bundle.pits.first   ?? .classic,
            boundary: bundle.boundaries.first ?? .classic
        )
    }

    /// The player's current look: what they have equipped right now.
    init(equippedIn gameState: GameState) {
        self.init(
            ball:     gameState.activeSkin,
            trail:    gameState.equippedTrail,
            goal:     gameState.equippedGoal,
            floor:    gameState.equippedFloor,
            pit:      gameState.equippedPit,
            boundary: gameState.equippedBoundary
        )
    }

    /// "Try it on": this loadout with one cosmetic swapped into its slot.
    /// Music is heard, not drawn, so it changes nothing here.
    func trying<Item: CosmeticItem>(_ item: Item) -> Loadout {
        var l = self
        switch item {
        case let s as BallSkin:   l.ball = s
        case let t as TrailColor: l.trail = t
        case let g as GoalSkin:   l.goal = g
        case let f as Floor:      l.floor = f
        case let p as Pit:        l.pit = p
        case let b as Boundary:   l.boundary = b
        default: break
        }
        return l
    }

    /// "Try it on" for a whole set: every slot the set fills is swapped in
    /// together (its first item per slot, as buying it equips); slots it
    /// leaves empty keep the player's own pieces.
    func trying(bundle: CosmeticBundle) -> Loadout {
        var l = self
        if let x = bundle.balls.first      { l.ball = x }
        if let x = bundle.trails.first     { l.trail = x }
        if let x = bundle.goals.first      { l.goal = x }
        if let x = bundle.floors.first     { l.floor = x }
        if let x = bundle.pits.first       { l.pit = x }
        if let x = bundle.boundaries.first { l.boundary = x }
        return l
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
// my recording on this phone", which only debug builds offer), then
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
// Only in debug builds (`isAvailable`); a release build can
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

    /// Developer tool: debug builds only.  Release builds (TestFlight, App
    /// Review and the App Store) never show the record menu.
    static var isAvailable: Bool {
        #if DEBUG
        return true
        #else
        return false
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
    /// Keep the nearest corner of the play area, and so the boundary, in the
    /// shot: for trying on a boundary or a whole set.  The boundary sits at
    /// the play area's edge and moves with the camera like everything else,
    /// so a close follow shot would otherwise leave it out of view.
    var framesBoundary: Bool = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.cosmeticMotion) private var cosmeticMotion
    /// Still frame under Reduce Motion, and in a grid or list.
    private var reduceMotion: Bool { systemReduceMotion || cosmeticMotion == .still }
    @ObservedObject private var recorder = ReplayRecorder.shared

    /// Seconds kept after the goal or fall so the ending reads.
    private let endHold = 0.7
    /// The longest stretch played, in seconds (the end of the run).
    private let maxClip = 6.5
    /// The ball is never drawn smaller than this share of the preview's
    /// shorter side.  When framing the whole stretch would make it smaller
    /// (a wide, short card and a tall path), the camera zooms in to this size
    /// and follows the ball instead.
    private let minBallShare: CGFloat = 0.12
    /// Seconds either side of "now" the follow camera averages the ball's
    /// position over, so it glides instead of jittering.
    private let followSmoothing = 0.45

    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            let scene = ZStack {
                if let replay = ReplayStore.current, s.width > 1, s.height > 1 {
                    // The replay draws its boundary at the play area's edge,
                    // through the same camera as everything else.
                    replayScene(replay, size: s)
                } else {
                    stillScene(s)
                    boundaryRing
                }
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

    /// THE camera — the single source of truth for where everything is drawn.
    /// Every layer (floor, pits, goal, coins, trail, ball, flourish) maps
    /// recorded points through the camera returned here for the same `t`.
    ///
    /// Framing: fit the stretch's path, the goal, the coins picked up in the
    /// stretch and the pits it passes near, with a margin, at the preview's
    /// aspect ratio.  If that would draw the ball smaller than
    /// `minBallShare` of the preview's shorter side, zoom in to that size and
    /// follow the ball (smoothed) instead, so the action fills the card.
    private func camera(_ r: RunReplay, clip c: Clip, size s: CGSize, at t: Double) -> Camera {
        let aw = CGFloat(r.arenaWidth), ah = CGFloat(r.arenaHeight)
        let br = CGFloat(r.ballRadius)
        let path = r.samples(from: c.start, to: c.end).map { $0.p }
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        func include(_ p: CGPoint) {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        for p in path { include(p) }
        if r.endKind == .goal {
            include(CGPoint(x: CGFloat(r.goal.x) * aw, y: CGFloat(r.goal.y) * ah))
        }
        // Coins picked up during the stretch.
        for (idx, coin) in r.coins.enumerated() {
            if let taken = r.events.first(where: { $0.kind == .coin && $0.index == idx })?.t,
               taken >= c.start, taken <= c.end {
                include(CGPoint(x: CGFloat(coin.x) * aw, y: CGFloat(coin.y) * ah))
            }
        }
        // Pits the ball passes within two ball widths of (their near edge).
        let near = br * 4
        for h in r.holes {
            let rect = CGRect(x: CGFloat(h.x) * aw, y: CGFloat(h.y) * ah,
                              width: CGFloat(h.w) * aw, height: CGFloat(h.h) * ah)
            let grown = rect.insetBy(dx: -near, dy: -near)
            // The part of the pit the ball comes close to: for each nearby
            // path point, the nearest point of the pit.
            for p in path where grown.contains(p) {
                include(CGPoint(x: min(max(p.x, rect.minX), rect.maxX),
                                y: min(max(p.y, rect.minY), rect.maxY)))
            }
        }
        if !minX.isFinite { include(r.position(at: 0)) }
        if framesBoundary {
            // The play-area corner nearest the action, just inside it, so the
            // boundary's stroke and curve show.
            let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
            include(CGPoint(x: cx < aw / 2 ? 0 : aw, y: cy < ah / 2 ? 0 : ah))
        }

        let aspect = s.width / max(1, s.height)
        let pad = br * 2.5
        var w = max(maxX - minX + pad * 2, br * 8)
        var h = max(maxY - minY + pad * 2, br * 8)
        if w / h < aspect { w = h * aspect } else { h = w / aspect }
        let fitScale = s.width / w

        let ballDiameter = br * 2 * loadout.ball.radiusScale
        // When the boundary must stay in the shot, allow a smaller ball
        // before switching to the follow camera.
        let share: CGFloat = framesBoundary ? minBallShare * 0.5 : minBallShare
        let minScale = share * min(s.width, s.height) / max(1, ballDiameter)

        let scale: CGFloat
        let center: CGPoint
        if fitScale >= minScale {
            // Everything fits at a good size: a fixed camera on the stretch.
            scale = fitScale
            center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        } else {
            // Follow the ball, averaged over a short window either side of t.
            scale = minScale
            var sx: CGFloat = 0, sy: CGFloat = 0
            let steps = 8
            for k in -steps...steps {
                let u = min(max(t + followSmoothing * Double(k) / Double(steps), c.start), c.end)
                let p = r.position(at: u)
                sx += p.x; sy += p.y
            }
            let n = CGFloat(steps * 2 + 1)
            center = CGPoint(x: sx / n, y: sy / n)
        }
        let rw = s.width / scale, rh = s.height / scale
        var ox = center.x - rw / 2
        var oy = center.y - rh / 2
        // Stay inside the play area when the view is smaller than it;
        // otherwise center the play area in that direction.
        ox = rw <= aw ? min(max(ox, 0), aw - rw) : (aw - rw) / 2
        oy = rh <= ah ? min(max(oy, 0), ah - rh) : (ah - rh) / 2
        return Camera(origin: CGPoint(x: ox, y: oy), scale: scale,
                      region: CGSize(width: rw, height: rh))
    }

    // ── The replay ───────────────────────────────────────────────────────

    /// The replay.  Each frame is ONE ZStack the size of the preview, with
    /// every layer drawn through ONE camera.  (Before, the coins, trail, ball
    /// and flourish were separate views handed straight to a TimelineView,
    /// which stacks several children instead of overlaying them — so each
    /// landed in its own band of the card and the ball drifted away from its
    /// trail.  Only the Reduce Motion still frame, which sat in a ZStack,
    /// lined up.)
    @ViewBuilder
    private func replayScene(_ r: RunReplay, size s: CGSize) -> some View {
        let c = clip(r)
        if reduceMotion {
            frameScene(r, clip: c, size: s, t: max(c.start, c.end - 0.35),
                       alpha: 1, wallNow: 0)
        } else {
            TimelineView(.animation(minimumInterval: cosmeticMotion.frameInterval(nil),
                                    paused: cosmeticMotion.isPaused(reduceMotion: systemReduceMotion))) { tl in
                let now = tl.date.timeIntervalSinceReferenceDate
                let raw = now.truncatingRemainder(dividingBy: c.length)
                let alpha: Double = raw < 0.15 ? raw / 0.15
                    : (raw > c.length - 0.25 ? max(0, (c.length - raw) / 0.25) : 1)
                frameScene(r, clip: c, size: s, t: c.start + raw,
                           alpha: alpha, wallNow: now)
            }
        }
    }

    /// One frame of the replay at run time `t`.
    private func frameScene(_ r: RunReplay, clip c: Clip, size s: CGSize,
                            t: Double, alpha: Double, wallNow: Double) -> some View {
        let cam = camera(r, clip: c, size: s, at: t)
        return ZStack {
            floorLayer(r, cam, size: s)
            pitsLayer(r, cam)
            goalLayer(r, cam)
            movingLayer(r, cam, clip: c, size: s, t: t, alpha: alpha, wallNow: wallNow)
            boundaryLayer(r, cam, size: s)
        }
        .frame(width: s.width, height: s.height)
    }

    /// Places a view drawn in play-area points (`arena` × `arena`, origin at
    /// the play area's top-left, as the game draws it) into the preview
    /// through the camera: scaled by `cam.scale` and shifted by
    /// `cam.origin`, exactly like `cam.view(_:)` maps a single point.  Any
    /// layer that fills the play area (floor, boundary) must go through
    /// this, so it moves with the camera instead of staying put on screen.
    private func worldLayer<V: View>(_ r: RunReplay, _ cam: Camera, size s: CGSize,
                                     @ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(width: CGFloat(r.arenaWidth), height: CGFloat(r.arenaHeight))
            .scaleEffect(cam.scale, anchor: .topLeading)
            .offset(x: -cam.origin.x * cam.scale, y: -cam.origin.y * cam.scale)
            .frame(width: s.width, height: s.height, alignment: .topLeading)
    }

    /// The floor, drawn over the whole play area at the game's scale and
    /// placed through the camera, so its texture and animation stay fixed
    /// to the ground as the camera moves.  (It used to be drawn the size of
    /// the camera's view and pinned to the preview's top-left corner without
    /// the camera's offset, so when the camera followed the ball everything
    /// else moved and the floor stayed put: it slid under the ball.)  The
    /// plain floor color fills the preview first, for any margin the camera
    /// shows beyond the play area.
    private func floorLayer(_ r: RunReplay, _ cam: Camera, size s: CGSize) -> some View {
        let showOverlay = !(reduceMotion && FloorOverlayView.hiddenUnderReduceMotion(loadout.floor))
        return ZStack {
            loadout.floor.color
            worldLayer(r, cam, size: s) {
                ZStack {
                    loadout.floor.color
                    if showOverlay { FloorOverlayView(floor: loadout.floor) }
                    PaperFloorOverlayView(floor: loadout.floor)
                }
            }
        }
        .frame(width: s.width, height: s.height)
        .allowsHitTesting(false)
    }

    /// The boundary at the play area's edge, as the game draws it around the
    /// screen (base stroke plus the Legendary texture), placed through the
    /// camera like the floor.  Drawn in play-area points, so its width and
    /// corners scale with everything else.
    private func boundaryLayer(_ r: RunReplay, _ cam: Camera, size s: CGSize) -> some View {
        let base: Color = loadout.boundary == .classic ? Color(white: 0.68) : loadout.boundary.color
        let radius = Self.arenaCornerRadius
        return worldLayer(r, cam, size: s) {
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(base, lineWidth: 4)
                if !reduceMotion || loadout.boundary.textureShowsUnderReduceMotion {
                    BoundaryOverlayView(boundary: loadout.boundary, cornerRadius: radius)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Corner radius of the play area's border in the replay, in play-area
    /// points: a typical current iPhone's display corner.
    private static let arenaCornerRadius: CGFloat = 55

    /// Pits, as the game draws them (base color, animated overlay, depth).
    private func pitsLayer(_ r: RunReplay, _ cam: Camera) -> some View {
        let aw = CGFloat(r.arenaWidth), ah = CGFloat(r.arenaHeight)
        // Each pit is drawn at its size in play-area points, as in play, then
        // scaled and placed through the camera, so its texture keeps the
        // game's scale and moves with the floor.
        return ForEach(Array(r.holes.enumerated()), id: \.offset) { _, h in
            let w: CGFloat = max(1, CGFloat(h.w) * aw)
            let ht: CGFloat = max(1, CGFloat(h.h) * ah)
            let center = cam.view(CGPoint(x: (CGFloat(h.x) + CGFloat(h.w) / 2) * aw,
                                          y: (CGFloat(h.y) + CGFloat(h.h) / 2) * ah))
            ZStack {
                Rectangle().fill(loadout.pit.color)
                if !reduceMotion || loadout.pit.hasDrawnArt { PitOverlayView(pit: loadout.pit) }
                PitDepthShade(width: w, height: ht)
            }
            .frame(width: w, height: ht)
            .clipped()
            .scaleEffect(cam.scale)
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

        // Trail: the marks the game would have laid, rebuilt from the run's
        // own path and times (fed from the clip's start, so every mark sits
        // exactly where it was laid, in world space) and placed through the
        // camera like everything else.  Each fades on its own clock.
        if loadout.trail != .none {
            let now = min(t, c.end)
            let path = r.samples(from: c.start, to: now)
            let marks = TrailMarks.laid(along: path, now: t)
            Canvas { ctx, _ in
                guard marks.count >= 2 else { return }
                let pts = marks.points.map { cam.view($0) }
                drawRichTrail(ctx, points: pts, trail: loadout.trail,
                              t: t, baseWidth: max(2, 6 * cam.scale),
                              times: marks.times, reduceMotion: reduceMotion)
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
            if !reduceMotion || loadout.boundary.textureShowsUnderReduceMotion {
                BoundaryOverlayView(boundary: loadout.boundary, cornerRadius: radius)
            }
        }
        .allowsHitTesting(false)
    }
}

// ===========================================================================
// ReplayRecorderMenu — the long-press menu on a loadout preview that drives
// the recorder.  Attached only in debug builds; in a release
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

// ===========================================================================
// CosmeticMotion — where an animated cosmetic is allowed to move.
//
// Every cosmetic renderer (BallSkinView, FloorOverlayView, PitOverlayView,
// GoalSkinView, BoundaryOverlayView, LoadoutDiorama) reads this from the
// environment:
//   • .live    — in play and anywhere not set otherwise.  Each renderer runs
//                at its own rate as before.
//   • .preview — the Shop's Featured Bundle, a tapped cosmetic's detail view
//                and the loadout preview.  Animates at most 30 fps; with
//                Reduce Motion on, nothing moves.
//   • .held    — a preview that is momentarily covered or scrolling: the
//                same views, paused on their current frame.
//   • .still   — never animates; balls show their frozen (Reduce Motion)
//                art and the shop draws its static swatches.
//   • .tile / .tileHeld / .tileFrozen — a Shop, Catalog, collection or
//                Locker tile (see `CosmeticTileMotion`).  Tiles always draw
//                the game's own renderers.  `.tile` animates at
//                `ShopTileMotion.fps`; `.tileHeld` (the list is scrolling or
//                the tile is off screen) keeps its current frame;
//                `.tileFrozen` (Reduce Motion, or tile motion switched off)
//                shows the item's hero frame (`cosmeticHeroTime`).
// ===========================================================================
enum CosmeticMotion: Equatable {
    case live, preview, held, still
    case tile, tileHeld, tileFrozen

    /// Minimum seconds between frames: the renderer's own interval in play,
    /// at most 30 fps in a shop preview.
    func frameInterval(_ liveInterval: Double?) -> Double? {
        switch self {
        case .live, .still: return liveInterval
        case .preview, .held: return max(liveInterval ?? 0, 1.0 / 30.0)
        case .tile, .tileHeld, .tileFrozen:
            return max(liveInterval ?? 0, 1.0 / ShopTileMotion.fps)
        }
    }

    /// Whether a renderer's timeline should stop ticking.  Never in play
    /// (renderers keep their own Reduce Motion handling there).
    func isPaused(reduceMotion: Bool) -> Bool {
        switch self {
        case .live:         return false
        case .preview:      return reduceMotion
        case .held, .still: return true
        case .tile:         return reduceMotion
        case .tileHeld, .tileFrozen: return true
        }
    }

    /// True where the shop may show an animated renderer at all (a preview
    /// that is running or momentarily held); false in grids and lists and
    /// under Reduce Motion.
    func showsAnimatedRenderers(reduceMotion: Bool) -> Bool {
        switch self {
        case .preview, .held:               return !reduceMotion
        case .tile, .tileHeld, .tileFrozen: return true   // frozen when it must be
        case .live, .still:                 return false
        }
    }

    /// True where a paused timeline should hold its current frame instead of
    /// being rebuilt as a fresh still (tiles that may resume animating).
    var holdsFrame: Bool { self == .tile || self == .tileHeld }

    /// True for the three tile states.
    var isTile: Bool { self == .tile || self == .tileHeld || self == .tileFrozen }

    /// True where a ball shows its frozen (Reduce Motion) art.
    var showsBallStillArt: Bool { self == .still || self == .tileFrozen }
}

// ===========================================================================
// Tile motion — the gentle animation of Shop / Catalog / Locker tiles.
// ===========================================================================
enum ShopTileMotion {
    /// The one switch: set to false to keep every tile frozen on its hero
    /// frame (for example if scrolling a full grid stutters on older phones).
    static let animateTiles = true
    /// Frame rate for visible tiles.  15 fps is a quarter of the display rate
    /// on a 60 Hz phone: slow drifts, pulses and sparkles still read as
    /// motion, while a screen of ~12–20 tiles redraws a quarter as often as
    /// the 60 fps the game uses, leaving the main thread free for scrolling.
    static let fps: Double = 15
    /// Default hero instant (seconds on the renderers' clock) for a frozen
    /// tile, used where an item has no hero time of its own: past the first
    /// second, so particle and wave effects have spread out, and not at
    /// t = 0, where many effects sit at their start.
    static let defaultHeroTime: Double = 1.2
}

/// Seconds on the renderers' clock that a frozen tile draws (nil = use the
/// real clock).  Set only by `CosmeticTileMotion`.
private struct CosmeticHeroTimeKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

/// True while the scroll view holding cosmetic tiles is moving.
private struct CosmeticTilesScrollingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var cosmeticHeroTime: Double? {
        get { self[CosmeticHeroTimeKey.self] }
        set { self[CosmeticHeroTimeKey.self] = newValue }
    }
    var cosmeticTilesScrolling: Bool {
        get { self[CosmeticTilesScrollingKey.self] }
        set { self[CosmeticTilesScrollingKey.self] = newValue }
    }
}

/// Puts one tile into the right motion state:
///   • frozen on its hero frame under Reduce Motion or with tile motion off;
///   • held on its current frame while the list scrolls or it is off screen;
///   • animating at `ShopTileMotion.fps` otherwise.
/// Inside a preview (the Featured Bundle, a detail popup) the tile follows
/// the preview's own motion instead.
struct CosmeticTileMotion: ViewModifier {
    let heroTime: Double
    @Environment(\.cosmeticMotion) private var parent
    @Environment(\.cosmeticTilesScrolling) private var scrolling
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true

    private var state: CosmeticMotion {
        if parent == .preview || parent == .held { return parent }
        if !ShopTileMotion.animateTiles || reduceMotion { return .tileFrozen }
        return (scrolling || !visible) ? .tileHeld : .tile
    }

    func body(content: Content) -> some View {
        let s = state
        content
            .environment(\.cosmeticMotion, s)
            .environment(\.cosmeticHeroTime, s == .tileFrozen ? heroTime : nil)
            .onScrollVisibilityChange(threshold: 0.05) { visible = $0 }
    }
}

extension View {
    /// Tile motion for one cosmetic tile (see `CosmeticTileMotion`).
    func cosmeticTileMotion(heroTime: Double = ShopTileMotion.defaultHeroTime) -> some View {
        modifier(CosmeticTileMotion(heroTime: heroTime))
    }

    /// Marks a scroll view of cosmetic tiles: every tile inside holds its
    /// frame while the list moves.
    func cosmeticTileScrollTracking(_ scrolling: Binding<Bool>) -> some View {
        self
            .onScrollPhaseChange { _, phase in
                let moving = phase != .idle
                if moving != scrolling.wrappedValue { scrolling.wrappedValue = moving }
            }
    }
}

private struct CosmeticMotionKey: EnvironmentKey {
    static let defaultValue: CosmeticMotion = .live
}

extension EnvironmentValues {
    var cosmeticMotion: CosmeticMotion {
        get { self[CosmeticMotionKey.self] }
        set { self[CosmeticMotionKey.self] = newValue }
    }
}
