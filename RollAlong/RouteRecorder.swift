import Foundation

// ---------------------------------------------------------------------------
// Records the route a marble takes through one Adventure run, to send with
// the run's level_complete or level_fail event.  Plain logic, unit tested.
//
// A point is the marble's position as fractions of the playfield, in
// thousandths: (0, 0) is the top-left corner and (1000, 1000) the
// bottom-right.  These are the level pack's own units times 1000.
//
// Points are taken `samplesPerSecond` times a second of PLAYED time (time the
// physics was running, so a paused game adds nothing).  A run never holds
// more than `maxPoints`: when it would, every second point is dropped and the
// gap between points doubles, so a long run is still covered from start to
// end, only more coarsely.  The event says the gap it ended with.
// ---------------------------------------------------------------------------
struct RouteRecorder {
    /// Sampling rate: points per second of play.
    static let samplesPerSecond: Double = 20
    /// Size limit: the most points one run may hold (about 4.8 KB).  At 20
    /// points a second that is 30 seconds of play before a run is thinned.
    static let maxPoints: Int = 600

    private(set) var xs: [Int] = []
    private(set) var ys: [Int] = []
    /// Seconds of play between two points.  Doubles each time the run is thinned.
    private(set) var step: Double = 1 / RouteRecorder.samplesPerSecond
    private var played: Double = 0
    private var ended = false

    var pointCount: Int { xs.count }

    /// Forget everything: call when a run starts.
    mutating func reset() { self = RouteRecorder() }

    /// Call once per physics tick while the marble is in play.
    /// `x` and `y` are fractions of the playfield; `dt` is the tick's length.
    mutating func tick(x: Double, y: Double, dt: Double) {
        guard !ended else { return }
        // Point number i belongs at played time i × step.
        if played + 1e-9 >= Double(xs.count) * step {
            append(x, y)
            if xs.count > Self.maxPoints { thin() }
        }
        played += dt
    }

    /// The marble's last position (the goal or the place it fell).  Always
    /// kept, so the route ends exactly where the run ended.
    mutating func end(x: Double, y: Double) {
        guard !ended else { return }
        ended = true
        if xs.count >= Self.maxPoints { thin() }
        append(x, y)
    }

    /// The route as text: "x,y;x,y;…" in thousandths.  Empty for no points.
    var encoded: String {
        var out = ""
        out.reserveCapacity(xs.count * 8)
        for i in xs.indices {
            if i > 0 { out.append(";") }
            out.append("\(xs[i]),\(ys[i])")
        }
        return out
    }

    private mutating func append(_ x: Double, _ y: Double) {
        xs.append(Self.thousandths(x))
        ys.append(Self.thousandths(y))
    }

    private mutating func thin() {
        xs = stride(from: 0, to: xs.count, by: 2).map { xs[$0] }
        ys = stride(from: 0, to: ys.count, by: 2).map { ys[$0] }
        step *= 2
    }

    private static func thousandths(_ fraction: Double) -> Int {
        guard fraction.isFinite else { return 0 }
        return Int((min(1, max(0, fraction)) * 1000).rounded())
    }
}

/// Holds one run's `RouteRecorder` by reference, so a view can add a point
/// on every tick without being redrawn.
final class RouteLog {
    var recorder = RouteRecorder()
}
