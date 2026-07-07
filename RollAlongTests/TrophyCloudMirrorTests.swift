//
//  TrophyCloudMirrorTests.swift
//  RollAlongTests
//
//  S3-T8 acceptance (headless, NO live iCloud — the S3 hard rule): the iCloud
//  KV ratchet-mirror logic is proven against an in-memory `TrophyKeyValueStore`
//  double, so union / max-merge / delete+reinstall restore / two-store
//  convergence / graceful-no-op are unit-tested with ZERO
//  NSUbiquitousKeyValueStore calls (docs/trophies/sprint-plan.md §2 S3-T8).
//
//  Verified here:
//  • TrophyEngine.mergeUnlocks — union grows the ledger, never subtracts; a
//    stale/subset external set can't un-earn a local trophy; first-stamp-wins
//    (earlier remote first-unlock corrects a later local stamp, never later);
//    incoming timestamps clamp to <= now(); unknown-catalog ids are kept;
//    re-merging is idempotent (no republish); the capstone cascade fires.
//  • TrophyCloudMirror.reconcile — delete+reinstall restores the full set from
//    the cloud; a two-store divergence converges both to the union; a local-only
//    unlock is pushed UP so the other device gets it; steady state is a no-op.
//  • Graceful degradation — an unavailable store makes every path a local-only
//    no-op (no crash, nothing restored, nothing pushed).
//
//  TrophyEngine and TrophyCloudMirror are not @MainActor; no case here is.
//

import XCTest
@testable import RollAlong

final class TrophyCloudMirrorTests: XCTestCase {

    // MARK: - In-memory KV double (the iCloud seam — the ONLY thing stubbed)

    /// A plain dictionary standing in for NSUbiquitousKeyValueStore. `available`
    /// toggles the "no entitlement / signed out of iCloud" case. Shared between
    /// two mirrors it models one cloud store two devices talk to.
    private final class MemoryKVStore: TrophyKeyValueStore {
        var available = true
        private(set) var ids: [String] = []
        private(set) var dateEpochs: [String: Double] = [:]
        private(set) var writeCount = 0
        private(set) var syncCount = 0

        var isAvailable: Bool { available }
        func unlockIDs() -> [String] { available ? ids : [] }
        func unlockDateEpochs() -> [String: Double] { available ? dateEpochs : [:] }

        func writeUnlocks(ids: [String], dateEpochs: [String: Double]) {
            guard available else { return }
            self.ids = ids
            self.dateEpochs = dateEpochs
            writeCount += 1
        }

        func synchronize() { guard available else { return }; syncCount += 1 }

        /// Seed the store as if another device (or a pre-reinstall run) had
        /// pushed this set.
        func seed(ids: [String], dates: [String: Date]) {
            self.ids = ids.sorted()
            self.dateEpochs = dates.mapValues { $0.timeIntervalSince1970 }
        }
    }

    // MARK: - Fixtures

    private var suiteName: String!
    private var defaults: UserDefaults!
    // A pinned clock well after the app shipped, so incoming remote stamps in
    // the past are never clamped by accident and future stamps clamp to this.
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        suiteName = "TrophyCloudMirrorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// A fresh engine over the bundled catalog, backed by a throwaway suite and
    /// the pinned clock.
    private func makeEngine() throws -> TrophyEngine {
        TrophyEngine(catalog: try TrophyCatalog.load(bundle: .main),
                     defaults: defaults,
                     now: { self.fixedNow })
    }

    /// A second engine over an INDEPENDENT throwaway suite — models a second
    /// device (or a clean reinstall) with its own local ledger.
    private func makeSecondEngine() throws -> (TrophyEngine, UserDefaults, String) {
        let name = "TrophyCloudMirrorTests.B.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        let e = TrophyEngine(catalog: try TrophyCatalog.load(bundle: .main),
                             defaults: d,
                             now: { self.fixedNow })
        return (e, d, name)
    }

    // =======================================================================
    // MARK: - TrophyEngine.mergeUnlocks — the union/max-merge core
    // =======================================================================

    func testMergeUnionAddsNewUnlocksAndArmsSync() throws {
        let engine = try makeEngine()
        XCTAssertFalse(engine.isUnlocked("snake_first_win"))

        let newly = engine.mergeUnlocks(ids: ["snake_first_win"],
                                        dates: ["snake_first_win": Date(timeIntervalSince1970: 1_700_000_000)])

        XCTAssertEqual(newly, ["snake_first_win"])
        XCTAssertTrue(engine.isUnlocked("snake_first_win"))
        XCTAssertEqual(engine.unlockDate(for: "snake_first_win"),
                       Date(timeIntervalSince1970: 1_700_000_000),
                       "an id new to this device adopts the incoming first-unlock stamp")
        XCTAssertTrue(engine.isSyncDirty,
                      "a restored unlock must arm the dirty flag so it propagates to Supabase")
    }

    func testMergeNeverSubtractsLocalUnlocks() throws {
        let engine = try makeEngine()
        // A real local unlock.
        XCTAssertFalse(engine.record(.snakeWins, value: 1_000_000).isEmpty)
        let before = engine.unlockedIDs
        XCTAssertTrue(engine.isUnlocked("snake_first_win"))

        // Merge an EMPTY external set (a fresh cloud): the ratchet must not lose
        // a single local unlock.
        let newly = engine.mergeUnlocks(ids: [], dates: [:])
        XCTAssertTrue(newly.isEmpty)
        XCTAssertEqual(engine.unlockedIDs, before, "an empty merge can never un-earn a trophy")
    }

    func testMergeSubsetIsIdempotentNoRepublish() throws {
        let engine = try makeEngine()
        engine.record(.snakeWins, value: 1_000_000)
        engine.clearSyncDirty()               // simulate a completed sync
        XCTAssertFalse(engine.isSyncDirty)
        let snapshot = engine.unlockedIDs

        // Merging a subset of what we already have adds nothing and must NOT
        // re-arm the dirty flag (no phantom re-sync) — the convergent no-op.
        let newly = engine.mergeUnlocks(ids: ["snake_first_win"], dates: [:])
        XCTAssertTrue(newly.isEmpty)
        XCTAssertEqual(engine.unlockedIDs, snapshot)
        XCTAssertFalse(engine.isSyncDirty, "a subset merge is a no-op — no republish")
    }

    func testMergeFirstStampWinsEarlierCorrectsLater() throws {
        let engine = try makeEngine()
        // Local unlock stamps at `fixedNow` (the pinned clock).
        engine.record(.snakeWins, value: 1_000_000)
        XCTAssertEqual(engine.unlockDate(for: "snake_first_win"), fixedNow)

        // An EARLIER remote first-unlock for the SAME id must win (the true
        // first unlock) — max-merge keeps the earliest, never restamps later.
        let earlier = Date(timeIntervalSince1970: 1_600_000_000)
        engine.mergeUnlocks(ids: ["snake_first_win"], dates: ["snake_first_win": earlier])
        XCTAssertEqual(engine.unlockDate(for: "snake_first_win"), earlier,
                       "an earlier remote first-unlock corrects a later local stamp")

        // A LATER remote stamp for an id we already have must be ignored.
        let later = Date(timeIntervalSince1970: 1_650_000_000)
        engine.mergeUnlocks(ids: ["snake_first_win"], dates: ["snake_first_win": later])
        XCTAssertEqual(engine.unlockDate(for: "snake_first_win"), earlier,
                       "a later remote stamp never restamps an existing unlock")
    }

    func testMergeClampsFutureStampToNow() throws {
        let engine = try makeEngine()
        let future = fixedNow.addingTimeInterval(10_000_000)   // remote clock skew
        engine.mergeUnlocks(ids: ["snake_first_win"], dates: ["snake_first_win": future])
        XCTAssertEqual(engine.unlockDate(for: "snake_first_win"), fixedNow,
                       "a future remote stamp clamps to now() — never-in-the-future invariant")
    }

    func testMergeKeepsUnknownCatalogID() throws {
        let engine = try makeEngine()
        // An id from a newer app version this build's catalog doesn't know.
        let newly = engine.mergeUnlocks(ids: ["future_trophy_from_v2"], dates: [:])
        XCTAssertEqual(newly, ["future_trophy_from_v2"])
        XCTAssertTrue(engine.isUnlocked("future_trophy_from_v2"),
                      "the ratchet keeps an unknown-catalog id — it is somebody's real unlock")
    }

    func testMergeIDByDateKeyOnly() throws {
        let engine = try makeEngine()
        // A healed partial cloud write: an id present in the DATE map but not the
        // id array. The union of ids ∪ date-keys must still latch it.
        let newly = engine.mergeUnlocks(ids: [],
                                        dates: ["snake_first_win": Date(timeIntervalSince1970: 1_700_000_000)])
        XCTAssertEqual(newly, ["snake_first_win"])
        XCTAssertTrue(engine.isUnlocked("snake_first_win"))
    }

    func testMergeRunsCapstoneCascade() throws {
        let engine = try makeEngine()
        XCTAssertFalse(engine.isUnlocked("capstone_all"))
        // Merge every base (non-capstone) trophy id — completing the capstone's
        // required set must cascade it open through mergeUnlocks' shared latch
        // core, exactly like a live unlock would.
        let baseIDs = Set(engine.catalog.trophies.map(\.id)).subtracting(["capstone_all"])
        let newly = Set(engine.mergeUnlocks(ids: baseIDs, dates: [:]))
        XCTAssertTrue(newly.contains("capstone_all"),
                      "a merge that completes the required set cascades the capstone open")
        XCTAssertTrue(engine.isUnlocked("capstone_all"))
    }

    // =======================================================================
    // MARK: - TrophyCloudMirror.reconcile — restore / convergence / push
    // =======================================================================

    func testDeleteReinstallRestoresFromCloud() throws {
        // Device 1 earns unlocks and pushes them to the (shared) cloud.
        let store = MemoryKVStore()
        let engine1 = try makeEngine()
        engine1.record(.snakeWins, value: 1_000_000)
        engine1.record(.climbTotalStars, value: 25)
        let earned = engine1.unlockedIDs
        XCTAssertFalse(earned.isEmpty)

        let mirror1 = TrophyCloudMirror(store: store)
        mirror1.reconcile(engine: engine1)
        XCTAssertGreaterThan(store.writeCount, 0, "device 1 pushed its ratchet to the cloud")

        // Simulate delete + reinstall: a BRAND-NEW local engine (empty ledger),
        // same cloud store.
        let (engine2, _, _) = try makeSecondEngine()
        XCTAssertTrue(engine2.unlockedIDs.isEmpty, "reinstalled device starts empty")

        let mirror2 = TrophyCloudMirror(store: store)
        let restored = Set(mirror2.reconcile(engine: engine2))

        XCTAssertEqual(engine2.unlockedIDs, earned,
                       "delete+reinstall restores the full unlock set from the cloud")
        XCTAssertEqual(restored, earned, "reconcile reports exactly the restored ids")
        // Timestamps came across too.
        XCTAssertEqual(engine2.unlockDate(for: "snake_first_win"),
                       engine1.unlockDate(for: "snake_first_win"))
    }

    func testTwoStoreDivergenceConvergesToUnion() throws {
        // One shared cloud, two devices with DISJOINT local unlocks.
        let store = MemoryKVStore()

        let engine1 = try makeEngine()
        engine1.record(.snakeWins, value: 1_000_000)       // device 1: snake_*
        let ids1 = engine1.unlockedIDs

        let (engine2, _, _) = try makeSecondEngine()
        engine2.record(.climbTotalStars, value: 25)        // device 2: climb_stars_25
        let ids2 = engine2.unlockedIDs

        XCTAssertTrue(ids1.isDisjoint(with: ids2), "fixtures must diverge")

        let mirror1 = TrophyCloudMirror(store: store)
        let mirror2 = TrophyCloudMirror(store: store)

        // Interleave reconciles in an arbitrary order; a grow-only set converges
        // regardless. Two rounds guarantee each device both pushes and pulls.
        mirror1.reconcile(engine: engine1)   // pushes ids1
        mirror2.reconcile(engine: engine2)   // pulls ids1, pushes ids1 ∪ ids2
        mirror1.reconcile(engine: engine1)   // pulls ids2

        let union = ids1.union(ids2)
        XCTAssertEqual(engine1.unlockedIDs, union, "device 1 converged to the union")
        XCTAssertEqual(engine2.unlockedIDs, union, "device 2 converged to the union")
        XCTAssertEqual(Set(store.unlockIDs()), union, "the cloud holds the union")
    }

    func testLocalOnlyUnlockIsPushedUp() throws {
        // Cloud already has one unlock (from another device); this device has a
        // DIFFERENT local-only unlock. A reconcile must push the local one up.
        let store = MemoryKVStore()
        store.seed(ids: ["climb_stars_25"],
                   dates: ["climb_stars_25": Date(timeIntervalSince1970: 1_650_000_000)])

        let engine = try makeEngine()
        engine.record(.snakeWins, value: 1_000_000)        // local-only snake_*

        let mirror = TrophyCloudMirror(store: store)
        mirror.reconcile(engine: engine)

        // Local absorbed the cloud id; cloud absorbed the local id → both hold
        // the union.
        XCTAssertTrue(engine.isUnlocked("climb_stars_25"), "pulled the cloud-only id down")
        XCTAssertTrue(Set(store.unlockIDs()).contains("snake_first_win"),
                      "pushed the local-only id up")
    }

    func testConvergedStateIsNoOp() throws {
        // After a first reconcile, a second with no new unlocks must NOT write
        // to the cloud again (steady-state no-op).
        let store = MemoryKVStore()
        let engine = try makeEngine()
        engine.record(.snakeWins, value: 1_000_000)

        let mirror = TrophyCloudMirror(store: store)
        mirror.reconcile(engine: engine)
        let writesAfterFirst = store.writeCount
        XCTAssertGreaterThan(writesAfterFirst, 0)

        mirror.reconcile(engine: engine)
        XCTAssertEqual(store.writeCount, writesAfterFirst,
                       "a fully-converged reconcile writes nothing new")
    }

    // =======================================================================
    // MARK: - Graceful degradation (no entitlement / signed out of iCloud)
    // =======================================================================

    func testUnavailableStoreIsLocalOnlyNoOp() throws {
        let store = MemoryKVStore()
        store.available = false                            // no iCloud KV

        let engine = try makeEngine()
        engine.record(.snakeWins, value: 1_000_000)
        let localBefore = engine.unlockedIDs

        let mirror = TrophyCloudMirror(store: store)
        let restored = mirror.reconcile(engine: engine)

        XCTAssertTrue(restored.isEmpty, "an unavailable store restores nothing")
        XCTAssertEqual(engine.unlockedIDs, localBefore, "local ledger is untouched — app runs as today")
        XCTAssertEqual(store.writeCount, 0, "nothing is written to an unavailable store")
        XCTAssertEqual(store.syncCount, 0)
    }

    func testUnavailableStoreDoesNotRestore() throws {
        // Even with a populated cloud, an unavailable store restores nothing —
        // graceful degradation, not a crash.
        let store = MemoryKVStore()
        store.seed(ids: ["snake_first_win"],
                   dates: ["snake_first_win": Date(timeIntervalSince1970: 1_700_000_000)])
        store.available = false

        let engine = try makeEngine()
        let restored = mirror(store).reconcile(engine: engine)

        XCTAssertTrue(restored.isEmpty)
        XCTAssertFalse(engine.isUnlocked("snake_first_win"),
                       "an unavailable store cannot restore — no crash, no restore")
    }

    private func mirror(_ store: TrophyKeyValueStore) -> TrophyCloudMirror {
        TrophyCloudMirror(store: store)
    }
}
