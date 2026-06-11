import XCTest
@testable import RollAlong

// ---------------------------------------------------------------------------
// PerformanceTests — QE3 §7 performance baseline.
//
// A `measure` block over one second of Gold Rush simulation (60 ticks @ 60 fps)
// guards the per-frame budget: the whole 60-tick loop should complete in well
// under 16 ms on the reference device, leaving each individual tick a tiny
// fraction of its 16.6 ms frame.  `measure` runs the block 10× and reports
// mean ± stddev; the first green run establishes the baseline.  Once the CI /
// local environment is stable, switch to `measureMetrics([.wallClockTime], …)`
// with a `maxStandardDeviations` budget to fail on regressions.
//
// Runs against GoldRushEngine — now GoldRushView's production simulation —
// driven headless here, without a view, accelerometer, or run loop.
// Reference environment: iPhone 16 Pro, iOS 18 (see SmokeTests).
// ---------------------------------------------------------------------------

final class PerformanceTests: XCTestCase {

    private let arena = CGSize(width: 390, height: 844)   // iPhone 16 Pro points

    func testGoldRushTick_performance() {
        let engine = GoldRushEngine(arena: arena)
        engine.loadMap(index: 0)
        engine.startRound()
        measure {
            for _ in 0..<60 { engine.tick() }   // one second at 60 fps
        }
    }

    /// Sanity guard: two seconds of simulation never crashes, keeps the full
    /// racer field, and leaves every marble at a finite, in-arena position —
    /// catches a NaN or runaway-position regression in the tick math.
    func testGoldRushTick_keepsRacersFiniteAndInBounds() {
        let engine = GoldRushEngine(arena: arena)
        engine.loadMap(index: 0)
        engine.startRound()
        for _ in 0..<120 { engine.tick() }

        XCTAssertEqual(engine.racers.count, 4, "1 player + 3 rivals throughout the round")
        for r in engine.racers {
            XCTAssertTrue(r.pos.x.isFinite && r.pos.y.isFinite,
                          "racer position must stay finite (no NaN/inf)")
            // A generous bound — physics clamps to the arena; collision push-out
            // can nudge a marble at most one radius past an edge.
            XCTAssertGreaterThan(r.pos.x, -40)
            XCTAssertLessThan(r.pos.x, arena.width + 40)
            XCTAssertGreaterThan(r.pos.y, -40)
            XCTAssertLessThan(r.pos.y, arena.height + 40)
        }
    }
}
