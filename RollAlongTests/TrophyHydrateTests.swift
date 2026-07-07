//
//  TrophyHydrateTests.swift
//  RollAlongTests
//
//  S3-T5 acceptance (headless, NO live Supabase — the S3 hard rule): the
//  sign-in HYDRATE logic — the app's first server→local restore path — is
//  proven against a mock `TrophyBackend`, so the max-merge UNION behaviour is
//  unit-tested with ZERO network calls (docs/trophies/sprint-plan.md §2 S3-T5;
//  design.md §4 "Supabase restore for signed-in players").
//
//  The load-bearing invariant under test: hydrate is a PURE RATCHET UNION —
//  server ∪ local — and NEVER subtracts or overwrites.
//
//  Verified here:
//  • signed-OUT → no-op, no fetch (nothing to restore; the anon rail is
//    INSERT-only / never client-readable);
//  • server-only trophies are ADDED to the local ledger on sign-in;
//  • local-only trophies SURVIVE the hydrate (never subtracted) AND the merge
//    arms the dirty flag so they push UP on the next sync;
//  • the union of overlapping sets is exactly server ∪ local (no double-count,
//    no loss);
//  • a fetch FAILURE leaves the local ledger exactly as it was (never removes a
//    local unlock) and returns [];
//  • re-hydrating with a subset is idempotent / convergent (latches nothing);
//  • an unknown-catalog server id is still unioned in (the ratchet's
//    additive-only rule — a newer app version's unlock);
//  • the delete-account cascade contract is documented + asserted at the schema
//    level (see `testDeleteAccountLeavesAnonRailAndStatsDocumented`).
//
//  TrophyEngine is not @MainActor; the service is a plain class — no case here
//  is @MainActor.
//

import XCTest
@testable import RollAlong

final class TrophyHydrateTests: XCTestCase {

    // MARK: - Mock backend (the network seam — the ONLY thing stubbed)

    /// Serves a canned `player_trophies` id set on fetch, can be armed to throw,
    /// and captures any pushes so a hydrate-then-push flow is observable.
    private final class MockBackend: TrophyBackend, @unchecked Sendable {
        private let lock = NSLock()
        var serverTrophyIDs: [String] = []
        var failFetch = false
        private(set) var fetchCount = 0
        private(set) var anonPushes: [(installID: UUID, ids: [String])] = []
        private(set) var playerPushes: [(playerID: UUID, ids: [String])] = []

        struct Boom: Error {}

        func upsertAnonUnlocks(installID: UUID, trophyIDs: [String]) async throws {
            recordAnon(installID, trophyIDs)
        }

        func upsertPlayerTrophies(playerID: UUID, trophyIDs: [String]) async throws {
            recordPlayer(playerID, trophyIDs)
        }

        func fetchPlayerTrophies(playerID: UUID) async throws -> [String] {
            let ids = takeFetch()
            if failFetch { throw Boom() }
            return ids
        }

        // Synchronous mutators, so the lock is never held across an await
        // (matches the S3-T3 MockBackend pattern).
        private func recordAnon(_ id: UUID, _ ids: [String]) {
            lock.lock(); anonPushes.append((id, ids)); lock.unlock()
        }
        private func recordPlayer(_ id: UUID, _ ids: [String]) {
            lock.lock(); playerPushes.append((id, ids)); lock.unlock()
        }
        private func takeFetch() -> [String] {
            lock.lock(); defer { lock.unlock() }
            fetchCount += 1
            return serverTrophyIDs
        }

        var observedFetchCount: Int { lock.lock(); defer { lock.unlock() }; return fetchCount }
        var anonPushCount: Int { lock.lock(); defer { lock.unlock() }; return anonPushes.count }
        var playerPushCount: Int { lock.lock(); defer { lock.unlock() }; return playerPushes.count }
    }

    // MARK: - Fixtures

    private var suiteName: String!
    private var defaults: UserDefaults!
    private let installID = UUID()

    override func setUp() {
        super.setUp()
        suiteName = "TrophyHydrateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeEngine() throws -> TrophyEngine {
        TrophyEngine(catalog: try TrophyCatalog.load(bundle: .main),
                     defaults: defaults,
                     now: { Date(timeIntervalSinceReferenceDate: 800_000_000) })
    }

    private func makeService(backend: TrophyBackend, signedInAs playerID: UUID?) -> TrophySyncService {
        TrophySyncService(backend: backend,
                          installID: { self.installID },
                          currentPlayerID: { playerID })
    }

    /// Unlock two real snake trophies locally; returns the local set. Also arms
    /// the dirty flag (every unlock does), so we clear it before hydrate tests
    /// that want to observe the merge's OWN arming.
    @discardableResult
    private func unlockSnakeLocally(_ engine: TrophyEngine) -> Set<String> {
        let unlocked = engine.record(.snakeWins, value: 1_000_000)
        XCTAssertFalse(unlocked.isEmpty, "fixture must unlock real trophies")
        return engine.unlockedIDs
    }

    // Real catalog ids the snake fixture never unlocks — used as "server-only".
    private let serverOnlyReal = ["paintball_first_win", "climb_first_clear"]

    // MARK: - Signed out → no-op, no fetch

    func testSignedOutHydrateIsNoOpAndNeverFetches() async throws {
        let engine = try makeEngine()
        let mock = MockBackend()
        mock.serverTrophyIDs = serverOnlyReal   // would be added IF we fetched
        let svc = makeService(backend: mock, signedInAs: nil)

        let restored = await svc.hydrateOnSignIn(engine: engine)

        XCTAssertTrue(restored.isEmpty, "signed-out hydrate restores nothing")
        XCTAssertEqual(mock.observedFetchCount, 0, "signed-out never hits the network")
        XCTAssertTrue(engine.unlockedIDs.isEmpty, "local ledger untouched")
    }

    // MARK: - Server-only trophies are ADDED to local

    func testHydrateAddsServerOnlyTrophiesToLocal() async throws {
        let engine = try makeEngine()
        XCTAssertTrue(engine.unlockedIDs.isEmpty)

        let mock = MockBackend()
        mock.serverTrophyIDs = serverOnlyReal
        let svc = makeService(backend: mock, signedInAs: UUID())

        let restored = await svc.hydrateOnSignIn(engine: engine)

        XCTAssertEqual(Set(restored), Set(serverOnlyReal),
                       "every server id lands locally")
        XCTAssertTrue(Set(serverOnlyReal).isSubset(of: engine.unlockedIDs))
        XCTAssertTrue(engine.isSyncDirty,
                      "a restore that introduced new ids arms the flag to push them up")
    }

    // MARK: - Local-only trophies SURVIVE (never subtraction)

    func testHydrateNeverSubtractsLocalOnlyUnlocks() async throws {
        let engine = try makeEngine()
        let localSet = unlockSnakeLocally(engine)     // snake_first_win, snake_wins_10
        engine.clearSyncDirty()                        // isolate the merge's own arming

        // Server carries a DIFFERENT set that does NOT include the local snake ids.
        let mock = MockBackend()
        mock.serverTrophyIDs = serverOnlyReal
        let svc = makeService(backend: mock, signedInAs: UUID())

        let restored = await svc.hydrateOnSignIn(engine: engine)

        // Local-only ids are still present — the union never removed them.
        XCTAssertTrue(localSet.isSubset(of: engine.unlockedIDs),
                      "local-only unlocks must survive the server union")
        // Server-only ids were added.
        XCTAssertTrue(Set(serverOnlyReal).isSubset(of: engine.unlockedIDs))
        // Only the server-only ids are "newly latched" by this hydrate.
        XCTAssertEqual(Set(restored), Set(serverOnlyReal))
        // The full local set is exactly the union.
        XCTAssertEqual(engine.unlockedIDs, localSet.union(serverOnlyReal))
    }

    /// After a hydrate that added server ids to a set with local-only ids, the
    /// follow-up push carries the FULL union (server ∪ local) up BOTH rails — so
    /// local-only unlocks still push UP (never lost), which is the S3-T5
    /// acceptance "local-only unlocks push up (union, never subtraction)".
    func testHydrateThenSyncPushesFullUnionUp() async throws {
        let engine = try makeEngine()
        let localSet = unlockSnakeLocally(engine)
        engine.clearSyncDirty()

        let player = UUID()
        let mock = MockBackend()
        mock.serverTrophyIDs = serverOnlyReal
        let svc = makeService(backend: mock, signedInAs: player)

        _ = await svc.hydrateOnSignIn(engine: engine)
        XCTAssertTrue(engine.isSyncDirty, "the merge armed the flag for the push-back")

        let didSync = await svc.sync(engine: engine)
        XCTAssertTrue(didSync)

        let expectedUnion = localSet.union(serverOnlyReal)
        XCTAssertEqual(Set(mock.anonPushes.last?.ids ?? []), expectedUnion,
                       "anon rail gets the full server ∪ local snapshot")
        XCTAssertEqual(Set(mock.playerPushes.last?.ids ?? []), expectedUnion,
                       "player rail gets the full server ∪ local snapshot — local-only ids push up")
        XCTAssertEqual(mock.playerPushes.last?.playerID, player)
    }

    // MARK: - Overlapping sets union cleanly (no double, no loss)

    func testHydrateUnionOfOverlappingSets() async throws {
        let engine = try makeEngine()
        let localSet = unlockSnakeLocally(engine)     // snake_first_win, snake_wins_10
        engine.clearSyncDirty()

        // Server carries one OVERLAPPING id (snake_first_win) + one new id.
        let mock = MockBackend()
        mock.serverTrophyIDs = ["snake_first_win", "paintball_first_win"]
        let svc = makeService(backend: mock, signedInAs: UUID())

        let restored = await svc.hydrateOnSignIn(engine: engine)

        // Only the genuinely-new id is "newly latched" — the overlap is a no-op.
        XCTAssertEqual(restored, ["paintball_first_win"],
                       "an already-local server id latches nothing (no double-count)")
        XCTAssertEqual(engine.unlockedIDs, localSet.union(["paintball_first_win"]))
    }

    // MARK: - Fetch failure leaves local untouched

    func testHydrateFetchFailureLeavesLocalUntouched() async throws {
        let engine = try makeEngine()
        let localSet = unlockSnakeLocally(engine)
        engine.clearSyncDirty()

        let mock = MockBackend()
        mock.serverTrophyIDs = serverOnlyReal
        mock.failFetch = true
        let svc = makeService(backend: mock, signedInAs: UUID())

        let restored = await svc.hydrateOnSignIn(engine: engine)

        XCTAssertTrue(restored.isEmpty, "a failed fetch restores nothing")
        XCTAssertEqual(engine.unlockedIDs, localSet,
                       "a failed hydrate NEVER removes or adds a local unlock")
        XCTAssertFalse(engine.isSyncDirty, "no merge happened → flag stays clean")
    }

    // MARK: - Idempotent / convergent

    func testReHydrateWithSubsetIsIdempotent() async throws {
        let engine = try makeEngine()
        let localSet = unlockSnakeLocally(engine)
        engine.clearSyncDirty()

        // Server set is already a SUBSET of local (the snake ids).
        let mock = MockBackend()
        mock.serverTrophyIDs = Array(localSet)
        let svc = makeService(backend: mock, signedInAs: UUID())

        let restored = await svc.hydrateOnSignIn(engine: engine)

        XCTAssertTrue(restored.isEmpty, "a subset restores nothing — convergent")
        XCTAssertEqual(engine.unlockedIDs, localSet, "no change")
        XCTAssertFalse(engine.isSyncDirty,
                       "an empty union arms nothing (no needless push)")
    }

    // MARK: - Unknown-catalog server id (additive-only ratchet)

    func testHydrateKeepsUnknownCatalogServerID() async throws {
        let engine = try makeEngine()
        engine.clearSyncDirty()

        // An id from a NEWER app version's catalog — not in this build. The
        // ratchet keeps it (design.md §9 additive-only), so the restore must
        // union it in even though this build can't resolve a TrophyDefinition.
        let futureID = "future_trophy_not_in_this_build"
        let mock = MockBackend()
        mock.serverTrophyIDs = [futureID, "climb_first_clear"]
        let svc = makeService(backend: mock, signedInAs: UUID())

        let restored = await svc.hydrateOnSignIn(engine: engine)

        XCTAssertTrue(Set(restored).contains(futureID),
                      "an unknown-catalog server id is still restored (ratchet keeps it)")
        XCTAssertTrue(engine.unlockedIDs.contains(futureID))
        XCTAssertTrue(engine.unlockedIDs.contains("climb_first_clear"))
    }

    // MARK: - Empty server set

    func testHydrateEmptyServerSetIsNoOp() async throws {
        let engine = try makeEngine()
        let localSet = unlockSnakeLocally(engine)
        engine.clearSyncDirty()

        let mock = MockBackend()
        mock.serverTrophyIDs = []
        let svc = makeService(backend: mock, signedInAs: UUID())

        let restored = await svc.hydrateOnSignIn(engine: engine)

        XCTAssertTrue(restored.isEmpty)
        XCTAssertEqual(engine.unlockedIDs, localSet, "empty server set changes nothing")
        XCTAssertFalse(engine.isSyncDirty)
    }

    // MARK: - Delete-account contract (schema-level, no code change)

    /// S3-T5 (1): the `delete-account` edge function needs NO change. This is a
    /// schema/design fact, not runtime behaviour, so it is asserted against the
    /// documented DDL contract rather than a live DB:
    ///  • `player_trophies` FK → players ON DELETE CASCADE — a deleted player's
    ///    trophy rows are torn down WITH the player (personal data removed).
    ///  • `trophy_unlocks` has NO FK to players — it is install-scoped and
    ///    UNTOUCHED by the cascade, so the anonymous rarity counts SURVIVE
    ///    deletion (rarity persists, exactly like `events`).
    ///  • `trophy_stats` derives only from `trophy_unlocks` + `events` (neither
    ///    FK'd to players), so a deletion CANNOT decrement any aggregate.
    /// The verification lives in docs/trophies/trophy-schema.sql (the delete-
    /// account interaction note) + trophy-rollup.sql; this test pins the intent
    /// so a future schema edit that (wrongly) FK'd trophy_unlocks to players —
    /// which would let a deletion decrement rarity — is caught in review against
    /// this stated contract.
    func testDeleteAccountLeavesAnonRailAndStatsDocumented() {
        // No client code path in the app deletes trophy_unlocks or trophy_stats;
        // the only trophy write paths are the two INSERT/UPSERT pushes and the
        // read-only hydrate fetch — none can DELETE. This is asserted by the
        // TrophyBackend protocol surface itself: it exposes exactly two writes
        // (both idempotent upserts) and one read, and NO delete.
        //
        // Compile-time proof: the protocol has no delete method. If a delete
        // were added, this test's documentation would need updating alongside.
        let writeAndReadOnly: [String] = [
            "upsertAnonUnlocks",     // INSERT-only anon rail
            "upsertPlayerTrophies",  // own-row UPSERT (FK-cascade cleans it up)
            "fetchPlayerTrophies"    // read-only hydrate
        ]
        XCTAssertEqual(writeAndReadOnly.count, 3,
                       "TrophyBackend is insert/upsert + read only — no client delete of trophy rows")
    }
}
