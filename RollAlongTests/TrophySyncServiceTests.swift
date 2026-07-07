//
//  TrophySyncServiceTests.swift
//  RollAlongTests
//
//  S3-T3 acceptance (headless, NO live Supabase — the S3 hard rule): the
//  client trophy-sync logic is proven against a mock `TrophyBackend`, so
//  queue / idempotency / dirty-flag / signed-in fan-out are unit-tested with
//  ZERO network calls (docs/trophies/sprint-plan.md §2 S3-T3).
//
//  Verified here:
//  • an offline unlock, synced online, produces exactly one anon-rail push of
//    each unlocked id, and replay is a no-op (idempotent snapshot);
//  • a SIGNED-OUT player still pushes `trophy_unlocks` (rarity counts) and does
//    NOT push `player_trophies`;
//  • a SIGNED-IN player pushes BOTH rails;
//  • a clean flag is a no-op (no network);
//  • the dirty flag clears ONLY on full success and stays ARMED on a partial
//    failure (either rail throwing);
//  • the anon install id resolves to (and shares) the analytics UUID rail.
//
//  TrophyEngine is not @MainActor; the service is a plain class — no case here
//  is @MainActor.
//

import XCTest
@testable import RollAlong

final class TrophySyncServiceTests: XCTestCase {

    // MARK: - Mock backend (the network seam — the ONLY thing stubbed)

    /// Captures every push and can be armed to throw on either rail, so the
    /// dirty-flag contract is provable without a live server.
    private final class MockBackend: TrophyBackend, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var anonPushes: [(installID: UUID, ids: [String])] = []
        private(set) var playerPushes: [(playerID: UUID, ids: [String])] = []
        var failAnon = false
        var failPlayer = false

        struct Boom: Error {}

        func upsertAnonUnlocks(installID: UUID, trophyIDs: [String]) async throws {
            if failAnon { throw Boom() }
            recordAnon(installID, trophyIDs)
        }

        func upsertPlayerTrophies(playerID: UUID, trophyIDs: [String]) async throws {
            if failPlayer { throw Boom() }
            recordPlayer(playerID, trophyIDs)
        }

        // S3-T5 hydrate read — unused by the push-path tests here (returns []);
        // exercised in TrophyHydrateTests. Present so the mock conforms.
        func fetchPlayerTrophies(playerID: UUID) async throws -> [String] { [] }

        // Synchronous, so the lock is never held across an await.
        private func recordAnon(_ id: UUID, _ ids: [String]) {
            lock.lock(); anonPushes.append((id, ids)); lock.unlock()
        }
        private func recordPlayer(_ id: UUID, _ ids: [String]) {
            lock.lock(); playerPushes.append((id, ids)); lock.unlock()
        }

        var anonPushCount: Int { lock.lock(); defer { lock.unlock() }; return anonPushes.count }
        var playerPushCount: Int { lock.lock(); defer { lock.unlock() }; return playerPushes.count }
    }

    // MARK: - Fixtures

    private var suiteName: String!
    private var defaults: UserDefaults!
    private let installID = UUID()

    override func setUp() {
        super.setUp()
        suiteName = "TrophySyncServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// A real engine over the bundled catalog, backed by a throwaway suite.
    private func makeEngine() throws -> TrophyEngine {
        TrophyEngine(catalog: try TrophyCatalog.load(bundle: .main),
                     defaults: defaults,
                     now: { Date(timeIntervalSinceReferenceDate: 800_000_000) })
    }

    /// A service wired to the mock, with a fixed install id and a supplied
    /// signed-in player id (nil = signed out).
    private func makeService(backend: TrophyBackend, signedInAs playerID: UUID?) -> TrophySyncService {
        TrophySyncService(backend: backend,
                          installID: { self.installID },
                          currentPlayerID: { playerID })
    }

    /// Unlocks two known snake trophies and returns the expected sorted id set.
    /// Arms `ra_trophySyncDirty` as a side effect (every unlock arms it).
    @discardableResult
    private func unlockSnake(_ engine: TrophyEngine) -> [String] {
        let unlocked = engine.record(.snakeWins, value: 1_000_000)
        XCTAssertFalse(unlocked.isEmpty, "fixture must actually unlock trophies")
        XCTAssertTrue(engine.isSyncDirty, "an unlock must arm the dirty flag")
        return engine.unlockedIDs.sorted()
    }

    // MARK: - Signed-out: anon rail only

    func testSignedOutUnlockPushesAnonRailOnly() async throws {
        let engine = try makeEngine()
        let ids = unlockSnake(engine)

        let mock = MockBackend()
        let svc = makeService(backend: mock, signedInAs: nil)

        let didSync = await svc.sync(engine: engine)

        XCTAssertTrue(didSync)
        XCTAssertEqual(mock.anonPushes.count, 1, "exactly one anon push")
        XCTAssertEqual(mock.anonPushes.first?.installID, installID)
        XCTAssertEqual(mock.anonPushes.first?.ids, ids, "full snapshot of every unlocked id")
        XCTAssertEqual(mock.playerPushCount, 0, "signed-out never touches player_trophies")
        XCTAssertFalse(engine.isSyncDirty, "full success drains the flag")
    }

    // MARK: - Signed-in: both rails

    func testSignedInUnlockPushesBothRails() async throws {
        let engine = try makeEngine()
        let ids = unlockSnake(engine)

        let player = UUID()
        let mock = MockBackend()
        let svc = makeService(backend: mock, signedInAs: player)

        let didSync = await svc.sync(engine: engine)

        XCTAssertTrue(didSync)
        XCTAssertEqual(mock.anonPushes.first?.ids, ids)
        XCTAssertEqual(mock.playerPushes.count, 1, "signed-in also pushes player_trophies")
        XCTAssertEqual(mock.playerPushes.first?.playerID, player)
        XCTAssertEqual(mock.playerPushes.first?.ids, ids, "same full snapshot on both rails")
        XCTAssertFalse(engine.isSyncDirty)
    }

    // MARK: - Idempotency: replay is a no-op

    func testReplayAfterDrainIsNoOp() async throws {
        let engine = try makeEngine()
        unlockSnake(engine)

        let mock = MockBackend()
        let svc = makeService(backend: mock, signedInAs: nil)

        _ = await svc.sync(engine: engine)
        XCTAssertEqual(mock.anonPushCount, 1)
        XCTAssertFalse(engine.isSyncDirty)

        // Second sync with a clean flag: no network at all.
        let didSyncAgain = await svc.sync(engine: engine)
        XCTAssertFalse(didSyncAgain, "clean flag → no-op")
        XCTAssertEqual(mock.anonPushCount, 1, "no second push")
    }

    /// Re-arming the flag (a NEW unlock) and re-syncing pushes the FULL current
    /// set again — one row per id, replay-safe by the server's on_conflict, so
    /// each id ends up exactly once server-side (the mock records the snapshot).
    func testNewUnlockResyncsFullSnapshot() async throws {
        let engine = try makeEngine()
        unlockSnake(engine)
        let mock = MockBackend()
        let svc = makeService(backend: mock, signedInAs: nil)
        _ = await svc.sync(engine: engine)
        XCTAssertFalse(engine.isSyncDirty)

        // A different unlock re-arms the flag.
        let more = engine.record(.climbTotalStars, value: 25)
        XCTAssertFalse(more.isEmpty)
        XCTAssertTrue(engine.isSyncDirty)

        _ = await svc.sync(engine: engine)
        XCTAssertEqual(mock.anonPushCount, 2)
        XCTAssertEqual(mock.anonPushes.last?.ids, engine.unlockedIDs.sorted(),
                       "snapshot includes the earlier unlocks too — full set, not a delta")
    }

    // MARK: - Clean flag never syncs

    func testCleanFlagIsNoOp() async throws {
        let engine = try makeEngine()
        XCTAssertFalse(engine.isSyncDirty, "fresh engine has nothing to sync")
        let mock = MockBackend()
        let svc = makeService(backend: mock, signedInAs: UUID())

        let didSync = await svc.sync(engine: engine)
        XCTAssertFalse(didSync)
        XCTAssertEqual(mock.anonPushCount, 0)
        XCTAssertEqual(mock.playerPushCount, 0)
    }

    // MARK: - Partial failure keeps the flag armed

    func testAnonFailureKeepsFlagArmed() async throws {
        let engine = try makeEngine()
        unlockSnake(engine)
        let mock = MockBackend()
        mock.failAnon = true
        let svc = makeService(backend: mock, signedInAs: UUID())

        let didSync = await svc.sync(engine: engine)
        XCTAssertFalse(didSync, "anon push failed → not a full sync")
        XCTAssertTrue(engine.isSyncDirty, "flag stays armed for the next retry")
        XCTAssertEqual(mock.playerPushCount, 0, "player rail not reached after anon throw")
    }

    func testPlayerFailureKeepsFlagArmed() async throws {
        let engine = try makeEngine()
        let ids = unlockSnake(engine)
        let mock = MockBackend()
        mock.failPlayer = true
        let svc = makeService(backend: mock, signedInAs: UUID())

        let didSync = await svc.sync(engine: engine)
        XCTAssertFalse(didSync, "player push failed → not a full sync")
        XCTAssertTrue(engine.isSyncDirty, "a partial (anon-only) success must NOT drain the flag")
        // The anon rail DID succeed before the player rail threw — that push
        // is harmless (idempotent) and rarity still counts.
        XCTAssertEqual(mock.anonPushes.first?.ids, ids)
    }

    /// The flag re-arms across a failure: a failed sync leaves it dirty, and a
    /// later successful sync drains it — deliver-at-least-once.
    func testRetryAfterFailureDrains() async throws {
        let engine = try makeEngine()
        unlockSnake(engine)
        let mock = MockBackend()
        mock.failAnon = true
        let svc = makeService(backend: mock, signedInAs: nil)

        _ = await svc.sync(engine: engine)
        XCTAssertTrue(engine.isSyncDirty)

        mock.failAnon = false
        let didSync = await svc.sync(engine: engine)
        XCTAssertTrue(didSync)
        XCTAssertFalse(engine.isSyncDirty, "retry succeeds → flag drains")
        XCTAssertEqual(mock.anonPushCount, 1, "only the successful attempt recorded a push")
    }

    // MARK: - Install-id rail sharing

    func testResolveInstallIDReusesAnalyticsUUID() {
        // Pre-seed the analytics key the way AnalyticsClient would.
        let existing = UUID()
        defaults.set(existing.uuidString, forKey: "ra_analytics_user_id")
        XCTAssertEqual(TrophySyncService.resolveInstallID(defaults), existing,
                       "trophy install id must reuse the analytics rail UUID")
    }

    func testResolveInstallIDGeneratesAndPersistsWhenAbsent() {
        let first = TrophySyncService.resolveInstallID(defaults)
        let second = TrophySyncService.resolveInstallID(defaults)
        XCTAssertEqual(first, second, "generated install id must persist across reads")
        XCTAssertEqual(defaults.string(forKey: "ra_analytics_user_id"), first.uuidString)
    }
}
