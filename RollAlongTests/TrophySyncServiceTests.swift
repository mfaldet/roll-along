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

        // S3-T9 showcase surface — unused by the push-path tests here; present so
        // the mock conforms. Exercised in TrophyPublicShowcaseTests.
        func upsertShowcase(_ showcase: TrophyPublicShowcase, playerID: UUID) async throws {}
        func deleteShowcase(playerID: UUID) async throws {}
        func fetchShowcase(playerID: UUID) async throws -> TrophyPublicShowcase? { nil }

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
        let ids = unlockSnake(engine)
        let mock = MockBackend()
        mock.failAnon = true
        let svc = makeService(backend: mock, signedInAs: UUID())

        let didSync = await svc.sync(engine: engine)
        XCTAssertFalse(didSync, "anon push failed → not a full sync")
        XCTAssertTrue(engine.isSyncDirty, "flag stays armed for the next retry")
        // The rails are independent: a refused anon push must not stop the
        // signed-in push (it used to, so neither table ever got a row).
        XCTAssertEqual(mock.playerPushes.first?.ids, ids,
                       "player rail still pushed after the anon rail failed")
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

// MARK: - Test runs never touch the live server

/// Proves the shared test-run switch (`RuntimeEnvironment`, AnalyticsClient.swift)
/// is on inside the test host, and that the LIVE clients send nothing while it
/// is: analytics tracks/buffers/sends nothing and the real trophy backend
/// refuses before any request. Mock backends (above) are unaffected.
final class TestRunNetworkIsolationTests: XCTestCase {

    func testTestRunIsDetectedInsideTheTestHost() {
        XCTAssertTrue(RuntimeEnvironment.isRunningTests)
    }

    func testDetectionRules() {
        // A normal launch: none of the signals present.
        XCTAssertFalse(RuntimeEnvironment.detect(environment: [:],
                                                 arguments: ["RollAlong"],
                                                 xcTestLoaded: false))
        // Unit tests: XCTest loaded into the host, or Xcode's env keys.
        XCTAssertTrue(RuntimeEnvironment.detect(environment: [:], arguments: [],
                                                xcTestLoaded: true))
        for key in ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"] {
            XCTAssertTrue(RuntimeEnvironment.detect(environment: [key: "x"], arguments: [],
                                                    xcTestLoaded: false), key)
        }
        // UI tests: the launch argument or the launch-environment key.
        XCTAssertTrue(RuntimeEnvironment.detect(environment: [:], arguments: ["--uitesting"],
                                                xcTestLoaded: false))
        XCTAssertTrue(RuntimeEnvironment.detect(environment: [RuntimeEnvironment.noLiveServerKey: "1"],
                                                arguments: [], xcTestLoaded: false))
    }

    func testAnalyticsSendsNothingDuringTests() async throws {
        let client = AnalyticsClient.shared
        // Well past the 8-event flush threshold, then an explicit flush.
        for i in 0..<25 {
            client.track("test_isolation_probe", properties: ["i": .int(i)], level: i)
        }
        client.flush()
        // Give any (wrongly) started flush task time to reach the network.
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(client.bufferedEventCount, 0, "nothing is even queued during tests")
        XCTAssertEqual(client.requestCount, 0,
                       "analytics must start ZERO requests in a test run (incl. app launch events)")
    }

    func testLiveTrophyBackendRefusesDuringTests() async {
        do {
            try await SocialTrophyBackend().upsertAnonUnlocks(installID: UUID(),
                                                               trophyIDs: ["test_probe"])
            XCTFail("the live trophy backend must refuse during tests")
        } catch {
            // Expected: refused before any request was built or sent.
        }
    }
}

// MARK: - Send Feedback outbox (queue, daily limit, retry rules)

private final class MockFeedbackSender: FeedbackSending, @unchecked Sendable {
    enum Mode { case ok, offline, refused }
    var mode: Mode = .ok
    private(set) var sent: [FeedbackItem] = []
    private(set) var hashes: [String] = []

    func send(_ item: FeedbackItem, installHash: String) async throws {
        switch mode {
        case .ok:
            sent.append(item)
            hashes.append(installHash)
        case .offline:
            throw FeedbackSendError.retryLater("offline")
        case .refused:
            throw FeedbackSendError.permanent(status: 400, body: "bad")
        }
    }
}

final class FeedbackOutboxTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "FeedbackOutboxTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func outbox(_ sender: MockFeedbackSender,
                        clock: @escaping () -> Date = Date.init) -> FeedbackOutbox {
        FeedbackOutbox(defaults: defaults, sender: sender,
                       installID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                       liveAllowed: true, now: clock, autoFlush: false)
    }

    func testEmptyMessageIsNotQueued() {
        let box = outbox(MockFeedbackSender())
        XCTAssertEqual(box.submit(kind: .bug, message: "   \n ", source: "t"), .empty)
        XCTAssertEqual(box.pendingCount, 0)
        XCTAssertEqual(box.usedToday, 0)
    }

    func testMessageIsCappedAt1000AndOnlyAHashIsSent() async {
        let sender = MockFeedbackSender()
        let box = outbox(sender)
        box.submit(kind: .idea, message: String(repeating: "a", count: 1_500), source: "t")
        await box.flush()
        XCTAssertEqual(sender.sent.first?.message.count, 1_000)
        XCTAssertEqual(sender.hashes.first?.count, 64, "a SHA-256 hex hash, never the raw install ID")
        XCTAssertFalse(sender.hashes.first?.contains("00000000-0000") ?? true)
    }

    func testOfflineKeepsTheMessageAndSendsItLater() async {
        let sender = MockFeedbackSender()
        sender.mode = .offline
        let box = outbox(sender)
        XCTAssertEqual(box.submit(kind: .bug, message: "It froze", source: "t"), .queued)
        await box.flush()
        XCTAssertEqual(box.pendingCount, 1)
        XCTAssertTrue(sender.sent.isEmpty)

        sender.mode = .ok
        await box.flush()
        XCTAssertEqual(box.pendingCount, 0)
        XCTAssertEqual(sender.sent.map(\.message), ["It froze"])
    }

    func testRefusedMessageIsDroppedNotRetriedForever() async {
        let sender = MockFeedbackSender()
        sender.mode = .refused
        let box = outbox(sender)
        box.submit(kind: .complaint, message: "x", source: "t")
        await box.flush()
        XCTAssertEqual(box.pendingCount, 0)
    }

    func testFivePerRollingDayThenLimited() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let box = outbox(MockFeedbackSender(), clock: { now })
        for i in 0..<FeedbackOutbox.maxPerDay {
            XCTAssertEqual(box.submit(kind: .bug, message: "m\(i)", source: "t"), .queued)
        }
        XCTAssertEqual(box.submit(kind: .bug, message: "one too many", source: "t"), .limitReached)
        XCTAssertFalse(box.canSubmit)

        now = now.addingTimeInterval(FeedbackOutbox.window + 1)
        XCTAssertTrue(box.canSubmit)
        XCTAssertEqual(box.submit(kind: .bug, message: "next day", source: "t"), .queued)
    }

    func testNothingIsSentDuringTestRuns() async {
        // The shared outbox is built with liveAllowed = !isRunningTests.
        XCTAssertTrue(RuntimeEnvironment.isRunningTests)
        let sender = MockFeedbackSender()
        let box = FeedbackOutbox(defaults: defaults, sender: sender,
                                 installID: UUID(),
                                 liveAllowed: !RuntimeEnvironment.isRunningTests,
                                 autoFlush: false)
        box.submit(kind: .bug, message: "test", source: "t")
        await box.flush()
        XCTAssertTrue(sender.sent.isEmpty)
        XCTAssertEqual(box.pendingCount, 1)
    }
}
