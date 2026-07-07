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
// Reference environment: iPhone 17 Pro (see SmokeTests).
// ---------------------------------------------------------------------------

final class PerformanceTests: XCTestCase {

    // Fixed reference arena (iPhone-class portrait points).  Deliberately
    // pinned — resizing it would change the measured workload and quietly
    // shift the established performance baseline.
    private let arena = CGSize(width: 390, height: 844)

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

// ---------------------------------------------------------------------------
// TrophyPerformanceTests — S4-T2 (docs/trophies/sprint-plan.md §2 S4-T2;
// §5 regression table "Hot-path cost in consumeLife/recordResult").
//
// The trophy hot path is TrophyEngine.record(_:value:), reached mid-run from
// GameState's climb funnels (recordResult at run end; the no-fall streak reset
// on consumeLife touches only a guarded scalar and is measured indirectly by
// the "no-unlock" guard below).  The engine's contract (TrophyEngine.swift
// header) is: one dictionary lookup + O(interested trophies), NO JSON encode
// anywhere, and ZERO UserDefaults writes / objectWillChange emissions unless an
// unlock actually lands.  These `measure` blocks are RELATIVE regression guards
// on the reference sim (iPhone 17 Pro) — the authoritative <0.5 ms p99 budget
// on the OLDEST supported device is Mac's on-device Instruments pass (mac_items).
//
// Each block runs `record` thousands of times so the per-call cost rises above
// `measure`'s timing floor; divide the reported mean by the loop count for the
// per-call figure.  The engine is driven headless — no view, no run loop, a
// throwaway UserDefaults suite (the GameStateTests injected-defaults pattern).
// ---------------------------------------------------------------------------

final class TrophyPerformanceTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "trophy.perf.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeEngine() throws -> TrophyEngine {
        TrophyEngine(catalog: try TrophyCatalog.load(bundle: .main), defaults: defaults)
    }

    /// The overwhelmingly common mid-run path: a `record` bump that unlocks
    /// nothing.  Contract: index lookup + a satisfied-check over the interested
    /// trophies, then early-out — ZERO persistence writes, ZERO publishes.
    /// This is the per-frame-safe guard: `consumeLife`/`recordResult` fire here
    /// mid-run, so this must be a tiny fraction of a 16.6 ms frame.
    ///
    /// Pre-drives the metric to its ceiling so every trophy on it is already
    /// latched — subsequent bumps take the no-new-unlock branch every time,
    /// isolating the pure evaluation cost with no commit/persist noise.
    func testTrophyRecord_noUnlock_hotPath() throws {
        let engine = try makeEngine()
        // Latch everything on the busiest metric (climb_highest_unlocked, 8
        // interested trophies) so further bumps unlock nothing.
        engine.record(.climbHighestUnlocked, value: 100_000)
        measure {
            for _ in 0..<10_000 {
                engine.record(.climbHighestUnlocked, value: 100_000)
            }
        }
    }

    /// A metric with NO interested trophies — the cheapest possible bump (a
    /// single dictionary miss).  Many live `record` call sites push metrics
    /// only a handful of trophies watch; this is the floor the index buys us
    /// over an O(catalog) scan.
    func testTrophyRecord_uninterestedMetric_isANoop() throws {
        let engine = try makeEngine()
        // fastestClearSeconds has few/one watcher; drive it past its threshold
        // once so the remaining bumps in the loop can't unlock.
        engine.record(.fastestClearSeconds, value: 1)
        measure {
            for _ in 0..<10_000 {
                engine.record(.spotlessRuns, value: 0)   // 0 never satisfies gte≥N
            }
        }
    }

    /// The run-end fan-out `recordResult` performs on a climb clear: several
    /// distinct metric bumps in one call (highest-unlocked, stars, pickup
    /// coins, first-try ace, spotless run).  Modeled here as one "clear" and
    /// looped so the aggregate cost is measurable.  Values ratchet upward so
    /// the first pass latches, then every later pass is the no-unlock path —
    /// representative of a veteran replaying cleared levels.
    func testTrophyRecordResult_fanout_perClear() throws {
        let engine = try makeEngine()
        measure {
            for i in 0..<2_000 {
                let v = Double(i % 500)          // ratchets, then plateaus
                engine.record(.climbHighestUnlocked, value: v)
                engine.record(.climbTotalStars, value: v)
                engine.record(.climbPickupCoins, value: v)
                engine.record(.firstTryAces, value: v)
                engine.record(.spotlessRuns, value: v)
            }
        }
    }

    /// Correctness guard behind the perf claim (not timed): a single `record`
    /// evaluates ONLY the trophies interested in that metric — never the whole
    /// catalog.  Proves the O(interested) shape the benchmarks assume, using
    /// the engine's DEBUG evaluation counter.  The busiest v1 metric
    /// (climb_highest_unlocked) has 8 watchers; the whole catalog is 89 — the
    /// per-bump work must track the former, not the latter.
    func testTrophyRecord_evaluatesOnlyInterestedTrophies() throws {
        let engine = try makeEngine()
        let interested = engine.trophies(interestedIn: .climbHighestUnlocked).count
        XCTAssertGreaterThan(interested, 0, "test metric must have watchers")
        XCTAssertLessThan(interested, engine.catalog.trophies.count,
                          "a single metric must not watch the whole catalog")

        engine.record(.climbHighestUnlocked, value: 0)
        XCTAssertEqual(engine.debugLastRecordEvaluationCount, interested,
                       "a bump evaluates exactly its interested trophies — O(interested), not O(catalog)")

        // A metric with zero watchers does zero criteria checks (pure index miss).
        engine.record(.baseTrophiesUnlocked, value: 5)   // ledger-provenance: cascade-only, not indexed
        XCTAssertEqual(engine.debugLastRecordEvaluationCount, 0,
                       "a ledger-provenance / unwatched metric performs no criteria evaluation on the hot path")
    }

    /// The no-unlock bump must perform ZERO persistence side effects — the
    /// contract that keeps the mid-run path free of a synchronous IO storm.
    /// Verified structurally (not timed): after latching everything on a
    /// metric, a further bump writes nothing new to the ledger keys and arms
    /// no sync-dirty transition.
    func testTrophyRecord_noUnlock_writesNothing() throws {
        let engine = try makeEngine()
        engine.record(.climbHighestUnlocked, value: 100_000)   // latch all watchers
        engine.clearSyncDirty()                                // drain the arm from that unlock

        let unlocksBefore = engine.unlockedIDs
        XCTAssertFalse(engine.isSyncDirty, "precondition: clean after drain")

        engine.record(.climbHighestUnlocked, value: 100_001)   // no new unlock

        XCTAssertEqual(engine.unlockedIDs, unlocksBefore, "no-unlock bump must not change the ledger")
        XCTAssertFalse(engine.isSyncDirty, "no-unlock bump must not arm the sync-dirty flag (no write)")
    }
}
