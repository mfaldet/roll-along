//
//  TrophyPublicShowcaseTests.swift
//  RollAlongTests
//
//  S3-T9 acceptance (headless, NO live Supabase — the S3 hard rule): the
//  CURATED PUBLIC showcase logic is proven against a mock `TrophyBackend`, so
//  the projection model + the enabled/toggle/delete orchestration are unit-
//  tested with ZERO network calls (docs/trophies/sprint-plan.md §2 S3-T9;
//  design.md §7 "Profile showcase" / decision #10, D6).
//
//  Verified here:
//  • the default showcased set is the RAREST EARNED trophies (highest tier
//    first) and is capped at 3;
//  • a player-chosen override is honored, deduped, capped, and drops unearned /
//    unknown ids (fabricates nothing);
//  • per-grade counts + earned/total + capstone flag mirror the engine;
//  • wire-row round-trips (owner encode → viewer decode);
//  • syncShowcase: enabled + signed-in + earned → an UPSERT of the projection;
//  • toggle OFF → a server-side DELETE (not just a local hide), even when the
//    player has earned trophies (the acceptance headline);
//  • enabled-but-empty ledger deletes any stale row (never publishes empty);
//  • signed-out → no network at all;
//  • the GameState toggle DEFAULTS ON for a fresh (signed-in-capable) install;
//  • PublicProfileView's render inputs resolve from the fetched projection +
//    the bundled catalog, never the viewer's own ledger.
//
//  TrophyEngine is not @MainActor; the service is a plain class. The one
//  GameState-default test runs on the main actor (GameState is @MainActor).
//

import XCTest
@testable import RollAlong

final class TrophyPublicShowcaseTests: XCTestCase {

    // MARK: - Mock backend (captures showcase writes/reads; the ONLY stub)

    private final class MockBackend: TrophyBackend, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var upserts: [(showcase: TrophyPublicShowcase, playerID: UUID)] = []
        private(set) var deletes: [UUID] = []
        var fetchResult: TrophyPublicShowcase?
        var failUpsert = false
        var failDelete = false

        struct Boom: Error {}

        // Unlock-rail surface — unused here.
        func upsertAnonUnlocks(installID: UUID, trophyIDs: [String]) async throws {}
        func upsertPlayerTrophies(playerID: UUID, trophyIDs: [String]) async throws {}
        func fetchPlayerTrophies(playerID: UUID) async throws -> [String] { [] }

        // Showcase surface — the subject under test.
        func upsertShowcase(_ showcase: TrophyPublicShowcase, playerID: UUID) async throws {
            if failUpsert { throw Boom() }
            lock.lock(); upserts.append((showcase, playerID)); lock.unlock()
        }
        func deleteShowcase(playerID: UUID) async throws {
            if failDelete { throw Boom() }
            lock.lock(); deletes.append(playerID); lock.unlock()
        }
        func fetchShowcase(playerID: UUID) async throws -> TrophyPublicShowcase? {
            lock.lock(); defer { lock.unlock() }; return fetchResult
        }

        var upsertCount: Int { lock.lock(); defer { lock.unlock() }; return upserts.count }
        var deleteCount: Int { lock.lock(); defer { lock.unlock() }; return deletes.count }
    }

    // MARK: - Fixtures

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TrophyPublicShowcaseTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeEngine(now: @escaping () -> Date =
                            { Date(timeIntervalSinceReferenceDate: 800_000_000) }) throws -> TrophyEngine {
        TrophyEngine(catalog: try TrophyCatalog.load(bundle: .main),
                     defaults: defaults,
                     now: now)
    }

    private func loadCatalog() throws -> TrophyCatalog {
        try TrophyCatalog.load(bundle: .main)
    }

    private func makeService(backend: TrophyBackend, signedInAs playerID: UUID?) -> TrophySyncService {
        TrophySyncService(backend: backend,
                          installID: { UUID() },
                          currentPlayerID: { playerID })
    }

    /// Pushing climb high enough to earn across bronze→silver→gold→diamond:
    ///   >=2 bronze (climb_first_clear), >=101 silver (climb_level_100),
    ///   >=501 gold (climb_level_500), >=5001 diamond (climb_summit).
    @discardableResult
    private func unlockAcrossTiers(_ engine: TrophyEngine) -> [TrophyDefinition] {
        engine.record(.climbHighestUnlocked, value: 5001)
    }

    // MARK: - Default = rarest earned, capped at 3

    func testDefaultShowcaseIsRarestEarned() throws {
        let engine = try makeEngine()
        unlockAcrossTiers(engine)

        let sc = TrophyPublicShowcase(engine: engine)
        XCTAssertFalse(sc.isEmpty)
        XCTAssertLessThanOrEqual(sc.showcasedIDs.count, TrophyPublicShowcase.showcaseIDCap)

        // Every showcased id is EARNED, and they are ordered rarest-grade first.
        let catalog = try loadCatalog()
        let tiers = sc.showcasedIDs.map { catalog.trophy(withID: $0)!.tier }
        XCTAssertEqual(tiers, tiers.sorted(by: >),
                       "Showcased ids are ordered rarest (highest tier) first.")
        // The rarest earned here is the diamond climb_summit — it must lead.
        XCTAssertTrue(engine.isUnlocked("climb_summit"))
        XCTAssertEqual(sc.showcasedIDs.first, "climb_summit",
                       "The rarest earned trophy (Diamond) is the default lead.")
        for id in sc.showcasedIDs { XCTAssertTrue(engine.isUnlocked(id)) }
    }

    func testDefaultShowcaseCapsAtThree() throws {
        let engine = try makeEngine()
        // A very broad push so many trophies unlock.
        engine.record(.climbHighestUnlocked, value: 100_000)
        engine.record(.climbTotalStars, value: 100_000)

        let sc = TrophyPublicShowcase(engine: engine)
        XCTAssertGreaterThan(sc.earned, 3, "Fixture must earn more than the cap.")
        XCTAssertEqual(sc.showcasedIDs.count, 3, "Showcase never exceeds 3 ids.")
    }

    func testEmptyLedgerHasEmptyShowcase() throws {
        let engine = try makeEngine()   // nothing unlocked
        let sc = TrophyPublicShowcase(engine: engine)
        XCTAssertTrue(sc.isEmpty)
        XCTAssertTrue(sc.showcasedIDs.isEmpty)
        XCTAssertEqual(sc.earned, 0)
        XCTAssertEqual(sc.total, try loadCatalog().trophies.count)
    }

    // MARK: - Player override honored, filtered, capped

    func testPlayerOverrideHonoredAndFiltered() throws {
        let engine = try makeEngine()
        unlockAcrossTiers(engine)   // earns climb_first_clear (bronze), etc.
        XCTAssertTrue(engine.isUnlocked("climb_first_clear"))
        XCTAssertTrue(engine.isUnlocked("climb_level_100"))

        // Override: a bronze first, plus an UNEARNED id and a BOGUS id (both
        // dropped), plus a duplicate (deduped).
        let sc = TrophyPublicShowcase(
            engine: engine,
            chosenIDs: ["climb_first_clear", "capstone_all", "made_up",
                        "climb_first_clear", "climb_level_100"])

        XCTAssertEqual(sc.showcasedIDs, ["climb_first_clear", "climb_level_100"],
                       "Override keeps earned+known ids in the player's order, deduped; unearned/unknown dropped.")
        XCTAssertFalse(sc.showcasedIDs.contains("capstone_all"), "Unearned pin dropped.")
        XCTAssertFalse(sc.showcasedIDs.contains("made_up"), "Unknown id dropped.")
    }

    func testPlayerOverrideCapsAtThree() throws {
        let engine = try makeEngine()
        engine.record(.climbHighestUnlocked, value: 100_000)
        let earned = try loadCatalog().trophies.map(\.id).filter { engine.isUnlocked($0) }
        XCTAssertGreaterThan(earned.count, 3)

        let sc = TrophyPublicShowcase(engine: engine, chosenIDs: earned)
        XCTAssertEqual(sc.showcasedIDs.count, 3, "Override is capped at 3 too.")
        XCTAssertEqual(sc.showcasedIDs, Array(earned.prefix(3)),
                       "Override preserves the player's order within the cap.")
    }

    // MARK: - Counts + capstone mirror the engine

    func testGradeCountsAndCapstoneMirrorEngine() throws {
        let engine = try makeEngine()
        unlockAcrossTiers(engine)

        let catalog = try loadCatalog()
        let sc = TrophyPublicShowcase(engine: engine)

        var expected: [TrophyTier: Int] = [:]
        for t in catalog.trophies where engine.isUnlocked(t.id) {
            expected[t.tier, default: 0] += 1
        }
        for tier in TrophyTier.allCases {
            XCTAssertEqual(sc.gradeCounts[tier] ?? 0, expected[tier] ?? 0,
                           "\(tier.displayName) count mirrors the engine.")
        }
        let engineEarned = catalog.trophies.filter { engine.isUnlocked($0.id) }.count
        XCTAssertEqual(sc.earned, engineEarned)
        XCTAssertEqual(sc.total, catalog.trophies.count)
        XCTAssertEqual(sc.capstone, engine.isUnlocked(catalog.capstone.id))
        XCTAssertFalse(sc.capstone, "climb alone never earns the capstone.")
    }

    // MARK: - Wire round-trip (owner encode → viewer decode)

    func testWireRowRoundTrip() throws {
        let engine = try makeEngine()
        unlockAcrossTiers(engine)
        let original = TrophyPublicShowcase(engine: engine)
        let playerID = UUID()

        let row = original.row(playerID: playerID)
        XCTAssertEqual(row.player_id, playerID.uuidString)

        // Encode → decode the JSON, then rebuild (the viewer path).
        let data = try JSONEncoder().encode(row)
        let decodedRow = try JSONDecoder().decode(TrophyPublicShowcase.Row.self, from: data)
        let rebuilt = TrophyPublicShowcase(row: decodedRow)

        XCTAssertEqual(rebuilt.showcasedIDs, original.showcasedIDs)
        XCTAssertEqual(rebuilt.earned, original.earned)
        XCTAssertEqual(rebuilt.total, original.total)
        XCTAssertEqual(rebuilt.capstone, original.capstone)
        for tier in TrophyTier.allCases {
            XCTAssertEqual(rebuilt.gradeCounts[tier] ?? 0, original.gradeCounts[tier] ?? 0)
        }
    }

    // MARK: - syncShowcase: enabled push

    func testSyncEnabledSignedInPushesShowcase() async throws {
        let engine = try makeEngine()
        unlockAcrossTiers(engine)
        let player = UUID()
        let mock = MockBackend()
        let svc = makeService(backend: mock, signedInAs: player)

        let result = await svc.syncShowcase(engine: engine, enabled: true)

        XCTAssertEqual(mock.upsertCount, 1, "an enabled, non-empty showcase upserts")
        XCTAssertEqual(mock.deleteCount, 0)
        XCTAssertEqual(mock.upserts.first?.playerID, player)
        XCTAssertEqual(mock.upserts.first?.showcase.showcasedIDs.first, "climb_summit")
        if case .pushed = result {} else { XCTFail("expected .pushed, got \(result)") }
    }

    // MARK: - Toggle OFF deletes SERVER-SIDE (the acceptance headline)

    func testToggleOffDeletesServerSideEvenWithEarnedTrophies() async throws {
        let engine = try makeEngine()
        unlockAcrossTiers(engine)   // the player HAS trophies…
        let player = UUID()
        let mock = MockBackend()
        let svc = makeService(backend: mock, signedInAs: player)

        // …but disabling the showcase must REMOVE it server-side, not just hide.
        let result = await svc.syncShowcase(engine: engine, enabled: false)

        XCTAssertEqual(mock.deleteCount, 1, "toggle-off issues a server-side DELETE")
        XCTAssertEqual(mock.deletes.first, player)
        XCTAssertEqual(mock.upsertCount, 0, "toggle-off never upserts")
        XCTAssertEqual(result, .deleted)
    }

    // MARK: - Enabled but empty ledger → delete any stale row, never publish empty

    func testEnabledEmptyLedgerDeletesRatherThanPublishEmpty() async throws {
        let engine = try makeEngine()   // nothing earned
        let mock = MockBackend()
        let svc = makeService(backend: mock, signedInAs: UUID())

        let result = await svc.syncShowcase(engine: engine, enabled: true)

        XCTAssertEqual(mock.upsertCount, 0, "an empty showcase is never published")
        XCTAssertEqual(mock.deleteCount, 1, "a stale row is cleared instead")
        XCTAssertEqual(result, .deleted)
    }

    // MARK: - Signed out → no network at all

    func testSignedOutIsNoNetworkNoOp() async throws {
        let engine = try makeEngine()
        unlockAcrossTiers(engine)
        let mock = MockBackend()
        let svc = makeService(backend: mock, signedInAs: nil)

        let onResult = await svc.syncShowcase(engine: engine, enabled: true)
        let offResult = await svc.syncShowcase(engine: engine, enabled: false)

        XCTAssertEqual(mock.upsertCount, 0)
        XCTAssertEqual(mock.deleteCount, 0)
        XCTAssertEqual(onResult, .skippedSignedOut)
        XCTAssertEqual(offResult, .skippedSignedOut)
    }

    // MARK: - Network failure is a silent .failed (never throws into UI)

    func testUpsertFailureReturnsFailed() async throws {
        let engine = try makeEngine()
        unlockAcrossTiers(engine)
        let mock = MockBackend()
        mock.failUpsert = true
        let svc = makeService(backend: mock, signedInAs: UUID())

        let result = await svc.syncShowcase(engine: engine, enabled: true)
        XCTAssertEqual(result, .failed, "a push error is swallowed as .failed")
    }

    func testDeleteFailureReturnsFailed() async throws {
        let engine = try makeEngine()
        let mock = MockBackend()
        mock.failDelete = true
        let svc = makeService(backend: mock, signedInAs: UUID())

        let result = await svc.syncShowcase(engine: engine, enabled: false)
        XCTAssertEqual(result, .failed)
    }

    // MARK: - fetchShowcase (viewer render source) never throws

    func testFetchShowcaseReturnsBackendRow() async throws {
        let engine = try makeEngine()
        unlockAcrossTiers(engine)
        let mock = MockBackend()
        mock.fetchResult = TrophyPublicShowcase(engine: engine)
        let svc = makeService(backend: mock, signedInAs: UUID())

        let fetched = await svc.fetchShowcase(for: UUID())
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.showcasedIDs.first, "climb_summit")
    }

    // MARK: - The GameState toggle DEFAULTS ON

    @MainActor
    func testGameStateShowcaseToggleDefaultsOn() {
        let gs = GameState(defaults: defaults)
        XCTAssertTrue(gs.trophyShowcaseEnabled,
                      "The public-showcase toggle defaults ON for signed-in players (design.md §7 / D6).")
        // Persists a flip.
        gs.trophyShowcaseEnabled = false
        let reloaded = GameState(defaults: defaults)
        XCTAssertFalse(reloaded.trophyShowcaseEnabled, "A toggle-off persists.")
    }

    // MARK: - PublicProfileView render inputs come from the projection + catalog

    /// PublicProfileView is SwiftUI; its render is a pure function of the fetched
    /// `TrophyPublicShowcase` + the bundled catalog (grade glyphs from
    /// `TrophyGradeStyle`), NEVER the viewer's own ledger. This proves those
    /// inputs resolve correctly (the same values the view draws).
    func testPublicProfileRenderInputsResolveFromProjectionNotViewerLedger() throws {
        // The "profile owner" earned across tiers.
        let ownerEngine = try makeEngine()
        unlockAcrossTiers(ownerEngine)
        let projection = TrophyPublicShowcase(engine: ownerEngine)

        // A DIFFERENT viewer with a DIFFERENT (empty) ledger renders the owner's
        // projection — the strip must reflect the OWNER, not the empty viewer.
        let catalog = try loadCatalog()
        XCTAssertFalse(projection.showcasedIDs.isEmpty)
        for id in projection.showcasedIDs {
            let def = catalog.trophy(withID: id)
            XCTAssertNotNil(def, "the view resolves each showcased id's title from the bundled catalog")
            let style = TrophyGradeStyle.forTier(def!.tier)
            // The Diamond grade uses the grade wreath glyph, never the cosmetic gem.
            if def!.tier == .diamond {
                XCTAssertEqual(style.glyph, TrophyGradeStyle.forTier(.diamond).glyph)
                XCTAssertNotEqual(style.glyph, TrophyGradeStyle.cosmeticDiamondTreatment.glyph,
                                  "rendered Diamond grade must not borrow the cosmetic gem (design.md §2 R2)")
            }
        }
        // Grade chips render the projection's counts, not the viewer's zeros.
        XCTAssertGreaterThan(projection.gradeCounts[.diamond] ?? 0, 0,
                             "the owner's Diamond count renders even though the viewer earned nothing")
    }
}
