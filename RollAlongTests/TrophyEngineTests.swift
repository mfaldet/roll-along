//
//  TrophyEngineTests.swift
//  RollAlongTests
//
//  S0-T1 ships the TrophyCatalog acceptance tests below (catalog decode/
//  encode round-trip, GC-legal unique ids, metric resolution, guardrail
//  rejection of IAP-/layout-keyed criteria, capstone scope). The
//  TrophyEngine evaluation tests (double-fire idempotency, ratchet,
//  injected-defaults harness) land in S0-T3/S0-T5 and S1-T9 in this file.
//
//  Tests run hosted in RollAlong.app (TEST_HOST), so `Bundle.main`
//  resolves the app bundle and its TrophyCatalog.json resource.
//

import XCTest
import Combine
@testable import RollAlong

final class TrophyCatalogTests: XCTestCase {

    // MARK: Fixtures

    private func loadCatalog() throws -> TrophyCatalog {
        try TrophyCatalog.load(bundle: .main)
    }

    private func rawCatalogData() throws -> Data {
        let url = try XCTUnwrap(Bundle.main.url(forResource: TrophyCatalog.bundledResource,
                                                withExtension: "json"),
                                "TrophyCatalog.json missing from the app bundle")
        return try Data(contentsOf: url)
    }

    /// Synthetic definition builder for validation tests.
    private func makeDefinition(id: String,
                                tier: TrophyTier = .bronze,
                                category: TrophyCategory = .climb,
                                secret: Bool = false,
                                metric: TrophyMetric = .climbHighestUnlocked,
                                threshold: Double = 1,
                                comparison: TrophyComparison = .greaterOrEqual,
                                requiredTrophyIDs: [String]? = nil,
                                addedInVersion: String = TrophyCatalog.launchVersion) -> TrophyDefinition {
        TrophyDefinition(id: id,
                         title: "Title \(id)",
                         tier: tier,
                         category: category,
                         lockedDescription: "Do the thing.",
                         unlockedDescription: "You did the thing.",
                         isSecret: secret,
                         criteria: TrophyCriteria(metric: metric,
                                                  threshold: threshold,
                                                  comparison: comparison,
                                                  requiredTrophyIDs: requiredTrophyIDs),
                         rewardID: nil,
                         addedInVersion: addedInVersion)
    }

    /// A minimal valid catalog: one base trophy + a well-formed capstone.
    private func makeMiniCatalog(baseIDs: [String] = ["mini_base"],
                                 capstoneRequired: [String]? = nil) -> [TrophyDefinition] {
        var trophies = baseIDs.map { makeDefinition(id: $0) }
        trophies.append(makeDefinition(id: "mini_capstone",
                                       tier: .platinum,
                                       category: .capstone,
                                       metric: .baseTrophiesUnlocked,
                                       threshold: Double((capstoneRequired ?? baseIDs).count),
                                       requiredTrophyIDs: capstoneRequired ?? baseIDs))
        return trophies
    }

    // MARK: Bundled catalog shape

    /// The bundled catalog loads, validates, and has the ruled v1 shape:
    /// 89 trophies — 49 Bronze / 25 Silver / 11 Gold / 3 Diamond /
    /// 1 Platinum capstone (trophy-catalog.md §2, RULED 2026-07-02).
    func testBundledCatalogLoadsWithRuledShape() throws {
        let catalog = try loadCatalog()
        XCTAssertEqual(catalog.count, 89)
        XCTAssertEqual(catalog.catalogVersion, 1)

        var tierCounts: [TrophyTier: Int] = [:]
        for trophy in catalog.trophies { tierCounts[trophy.tier, default: 0] += 1 }
        XCTAssertEqual(tierCounts[.bronze], 49)
        XCTAssertEqual(tierCounts[.silver], 25)
        XCTAssertEqual(tierCounts[.gold], 11)
        XCTAssertEqual(tierCounts[.diamond], 3)
        XCTAssertEqual(tierCounts[.platinum], 1)

        // The three Diamond monuments and the capstone, by id.
        XCTAssertEqual(Set(catalog.trophies.filter { $0.tier == .diamond }.map(\.id)),
                       ["climb_summit", "track_all_eight", "collection_complete"])
        XCTAssertEqual(catalog.capstone.id, "capstone_all")
        XCTAssertEqual(catalog.capstone.title, "Platinum")
        XCTAssertEqual(catalog.capstone.tier.displayName, "Platinum")

        // Every trophy is launch content with no reward ref (D1: prestige +
        // earned-only regalia — the regalia item detail is still open at D8,
        // and trophies never mint coins).
        for trophy in catalog.trophies {
            XCTAssertEqual(trophy.addedInVersion, "1.0", trophy.id)
            XCTAssertNil(trophy.rewardID, trophy.id)
        }
    }

    /// Acceptance: catalog decodes/encodes round-trip losslessly.
    func testCatalogRoundTripsThroughCodable() throws {
        let data = try rawCatalogData()
        let decoded = try JSONDecoder().decode(TrophyCatalog.CatalogFile.self, from: data)
        let reencoded = try JSONEncoder().encode(decoded)
        let redecoded = try JSONDecoder().decode(TrophyCatalog.CatalogFile.self, from: reencoded)
        XCTAssertEqual(decoded.trophies, redecoded.trophies)
        XCTAssertEqual(decoded.catalogVersion, redecoded.catalogVersion)
        // And the re-encoded bytes still pass the full loader + guardrails.
        XCTAssertNoThrow(try TrophyCatalog.load(from: reencoded))
    }

    // MARK: IDs

    /// Acceptance: every id is unique and Game Center-legal (lowercase
    /// snake_case, alphanumeric + underscore, starts with a letter,
    /// ≤100 chars). IDs are frozen forever.
    func testAllIDsAreUniqueAndGameCenterLegal() throws {
        let catalog = try loadCatalog()
        var seen = Set<String>()
        for trophy in catalog.trophies {
            XCTAssertTrue(seen.insert(trophy.id).inserted, "duplicate id \(trophy.id)")
            XCTAssertTrue(TrophyCatalog.isGameCenterLegalID(trophy.id),
                          "id not GC-legal: \(trophy.id)")
        }
    }

    func testGameCenterLegalIDRule() {
        XCTAssertTrue(TrophyCatalog.isGameCenterLegalID("climb_first_clear"))
        XCTAssertTrue(TrophyCatalog.isGameCenterLegalID("rollup_100m"))
        XCTAssertFalse(TrophyCatalog.isGameCenterLegalID(""))
        XCTAssertFalse(TrophyCatalog.isGameCenterLegalID("Climb_First"))     // uppercase
        XCTAssertFalse(TrophyCatalog.isGameCenterLegalID("climb-first"))     // kebab
        XCTAssertFalse(TrophyCatalog.isGameCenterLegalID("1st_clear"))       // leading digit
        XCTAssertFalse(TrophyCatalog.isGameCenterLegalID("climb first"))     // whitespace
        XCTAssertFalse(TrophyCatalog.isGameCenterLegalID(String(repeating: "a", count: 101)))
        XCTAssertTrue(TrophyCatalog.isGameCenterLegalID(String(repeating: "a", count: 100)))
    }

    func testValidateRejectsDuplicateIDs() {
        let trophies = makeMiniCatalog(baseIDs: ["dup_id"]) + [makeDefinition(id: "dup_id")]
        XCTAssertThrowsError(try TrophyCatalog.validate(trophies)) { error in
            XCTAssertEqual(error as? TrophyCatalogError, .duplicateID("dup_id"))
        }
    }

    func testValidateRejectsNonGCLegalIDs() {
        for badID in ["Bad-ID", "UPPER_CASE", "9lives", "spaced out"] {
            let trophies = [makeDefinition(id: badID)]
            XCTAssertThrowsError(try TrophyCatalog.validate(trophies)) { error in
                XCTAssertEqual(error as? TrophyCatalogError, .illegalID(badID))
            }
        }
    }

    // MARK: Metric resolution

    /// Acceptance: every criteria metric key in the bundled JSON resolves
    /// to a known TrophyMetric case (checked against the RAW json so a
    /// typo cannot hide behind Codable), and every case declares a
    /// provenance (the exhaustive switch that forces new metrics to be
    /// classified).
    func testEveryCriteriaMetricResolvesToAKnownMetricCase() throws {
        let raw = try JSONSerialization.jsonObject(with: rawCatalogData()) as? [String: Any]
        let trophies = try XCTUnwrap(raw?["trophies"] as? [[String: Any]])
        XCTAssertEqual(trophies.count, 89)
        for trophy in trophies {
            let id = trophy["id"] as? String ?? "<missing id>"
            let criteria = try XCTUnwrap(trophy["criteria"] as? [String: Any],
                                         "\(id): missing criteria")
            let metricKey = try XCTUnwrap(criteria["metric"] as? String,
                                          "\(id): missing metric key")
            let metric = TrophyMetric(rawValue: metricKey)
            XCTAssertNotNil(metric, "\(id): unknown metric key \(metricKey)")
            // Exhaustive-switch touch: every resolved case classifies.
            _ = metric?.provenance
        }
    }

    /// The engine must tolerate metrics that never fire: whimsy_roll_call
    /// ships in the catalog even though the pinball ROLL lanes are unbuilt
    /// (external blocker, sprint-plan.md §7).
    func testNeverFiringRollCallMetricIsInCatalog() throws {
        let catalog = try loadCatalog()
        let rollCall = try XCTUnwrap(catalog.trophy(withID: "whimsy_roll_call"))
        XCTAssertEqual(rollCall.criteria.metric, .pinballRollLaneSweeps)
        XCTAssertEqual(rollCall.tier, .silver)
        XCTAssertTrue(rollCall.isSecret)
    }

    // MARK: Guardrails — IAP / layout / banned vocabulary

    /// Acceptance: the guardrail rejects IAP-keyed criteria. An unknown
    /// metric key fails decode outright — the banned vocabulary is
    /// inexpressible in the TrophyMetric enum.
    func testDecodeRejectsIAPKeyedCriteria() {
        let json = """
        { "catalogVersion": 1, "trophies": [{
          "id": "own_the_secret", "title": "Nope", "tier": "bronze",
          "category": "cosmetics_collection", "secret": false,
          "lockedDescription": "Buy the thing.", "unlockedDescription": "Bought.",
          "criteria": { "metric": "iap_purchases", "threshold": 1 },
          "addedInVersion": "1.0" }] }
        """
        XCTAssertThrowsError(try TrophyCatalog.load(from: Data(json.utf8)))
    }

    /// Acceptance: the guardrail rejects layout-keyed criteria the same way
    /// (climb levels are swappable content — never a trigger vocabulary).
    func testDecodeRejectsLayoutKeyedCriteria() {
        let json = """
        { "catalogVersion": 1, "trophies": [{
          "id": "memorize_the_map", "title": "Nope", "tier": "bronze",
          "category": "climb", "secret": false,
          "lockedDescription": "Clear the spiral layout.", "unlockedDescription": "Cleared.",
          "criteria": { "metric": "level_42_layout_cleared", "threshold": 1 },
          "addedInVersion": "1.0" }] }
        """
        XCTAssertThrowsError(try TrophyCatalog.load(from: Data(json.utf8)))
    }

    /// Defense-in-depth: the raw-key scan flags IAP/purchase/layout/spend/
    /// failure vocabulary, and no shipping metric trips it.
    func testForbiddenCriteriaKeyScan() {
        for banned in ["iap_purchases", "iap_purchase_count", "storekit_transactions",
                       "product_owned", "purchase_total", "coins_spent",
                       "level_42_layout_cleared", "ads_watched_total",
                       "out_of_lives_count", "failure_streak"] {
            XCTAssertTrue(TrophyCatalog.isForbiddenCriteriaKey(banned), banned)
        }
        for metric in TrophyMetric.allCases {
            XCTAssertFalse(TrophyCatalog.isForbiddenCriteriaKey(metric.rawValue),
                           "shipping metric flagged: \(metric.rawValue)")
        }
    }

    /// The banned criteria dimensions do not exist as metric cases at all:
    /// no IAP/purchase-count, no coins-spent, no ads, no failure counts,
    /// no layout keys (trophy-catalog.md "deliberately absent" list).
    func testMetricVocabularyCannotExpressForbiddenCriteria() {
        for banned in ["iap_purchases", "purchases_total", "coins_spent",
                       "ads_watched", "out_of_lives", "failures",
                       "level_layout", "diamond_ball_owned", "money_ball_owned",
                       "results_shared", "lives_received"] {
            XCTAssertNil(TrophyMetric(rawValue: banned),
                         "banned metric exists: \(banned)")
        }
    }

    /// No trophy references the 4 IAP secrets in any way: collection
    /// metrics are count-based with the secrets excluded by definition
    /// (BallSkin.diamond, BallSkin.moneyBall, TrailColor.moneyRoll,
    /// Floor.moneyFull — trophy-catalog.md §3.6; enforced constant wired
    /// at S1-T5), and no id/copy leaks the secrets' existence.
    func testNoCriterionReferencesIAPSecretCosmetics() throws {
        let catalog = try loadCatalog()
        for trophy in catalog.trophies {
            for leak in ["diamond_ball", "money_ball", "money_roll", "money_full"] {
                XCTAssertFalse(trophy.id.contains(leak), trophy.id)
                XCTAssertFalse(trophy.criteria.metric.rawValue.contains(leak), trophy.id)
            }
            XCTAssertFalse(trophy.lockedDescription.localizedCaseInsensitiveContains("money ball"),
                           trophy.id)
            XCTAssertFalse(trophy.lockedDescription.localizedCaseInsensitiveContains("diamond ball"),
                           trophy.id)
        }
    }

    // MARK: Secrets

    /// Exactly the 5 Secret & Whimsy trophies are hidden (catalog §4,
    /// ratified 2026-07-02), and nothing hidden gates the capstone.
    func testExactlyFiveSecretsAllWhimsyAndOffCapstonePath() throws {
        let catalog = try loadCatalog()
        let secrets = catalog.trophies.filter(\.isSecret)
        XCTAssertEqual(Set(secrets.map(\.id)),
                       ["whimsy_gravity_check", "whimsy_night_bloom", "whimsy_roll_call",
                        "whimsy_high_roller", "whimsy_back_to_basics"])
        XCTAssertTrue(secrets.allSatisfy { $0.category == .secretWhimsy })
        // All whimsy trophies are secret and vice versa in v1.
        XCTAssertEqual(catalog.trophies.filter { $0.category == .secretWhimsy }.count, 5)
        let capstoneIDs = Set(try XCTUnwrap(catalog.capstone.criteria.requiredTrophyIDs))
        XCTAssertTrue(capstoneIDs.isDisjoint(with: secrets.map(\.id)))
    }

    func testValidateRejectsSecretOutsideSecretWhimsy() {
        let trophies = makeMiniCatalog() + [makeDefinition(id: "sneaky_climb", secret: true)]
        XCTAssertThrowsError(try TrophyCatalog.validate(trophies)) { error in
            XCTAssertEqual(error as? TrophyCatalogError,
                           .secretOutsideSecretWhimsy(id: "sneaky_climb"))
        }
    }

    // MARK: Capstone scope

    /// Acceptance: the capstone requires exactly the 73 visible
    /// bronze/silver/gold ids — Social, Secret & Whimsy, and the Diamond
    /// tier quarantined off the capstone path (catalog §3.11).
    func testCapstoneRequiresExactlyThe73VisibleBaseTrophies() throws {
        let catalog = try loadCatalog()
        let capstone = catalog.capstone
        let required = try XCTUnwrap(capstone.criteria.requiredTrophyIDs)
        XCTAssertEqual(required.count, 73)
        XCTAssertEqual(capstone.criteria.threshold, 73)
        XCTAssertEqual(capstone.criteria.metric, .baseTrophiesUnlocked)

        let requiredSet = Set(required)
        XCTAssertEqual(requiredSet.count, 73, "capstone list has duplicates")
        XCTAssertEqual(requiredSet, TrophyCatalog.expectedCapstoneRequirement(in: catalog.trophies))

        for id in required {
            let trophy = try XCTUnwrap(catalog.trophy(withID: id), "unknown capstone id \(id)")
            XCTAssertTrue([.bronze, .silver, .gold].contains(trophy.tier), id)
            XCTAssertFalse(trophy.isSecret, id)
            XCTAssertNotEqual(trophy.category, .social, id)
            XCTAssertNotEqual(trophy.category, .secretWhimsy, id)
        }

        // The quarantined sets, spot-checked by name.
        let quarantined = ["climb_summit", "track_all_eight", "collection_complete",
                           "social_sign_in", "social_first_friend", "social_friends_5",
                           "social_send_life", "social_lives_sent_25", "clan_join",
                           "clan_fulfill",
                           "whimsy_gravity_check", "whimsy_night_bloom", "whimsy_roll_call",
                           "whimsy_high_roller", "whimsy_back_to_basics",
                           "capstone_all"]
        for id in quarantined {
            XCTAssertFalse(requiredSet.contains(id), "\(id) must not gate the capstone")
        }
        // And the hard monuments that DO stay on the path.
        for id in ["daily_week_streak", "arcade_hard_all", "skill_clean_sheet_25",
                   "balls_own_40", "pinball_score_150k"] {
            XCTAssertTrue(requiredSet.contains(id), "\(id) missing from the capstone path")
        }
    }

    func testValidateRejectsCapstoneListMismatch() {
        // Capstone that forgets one visible base trophy.
        let trophies = makeMiniCatalog(baseIDs: ["mini_one", "mini_two"],
                                       capstoneRequired: ["mini_one"])
        XCTAssertThrowsError(try TrophyCatalog.validate(trophies)) { error in
            XCTAssertEqual(error as? TrophyCatalogError,
                           .capstoneListMismatch(missing: ["mini_two"], extra: []))
        }
    }

    func testValidateRejectsRequiredIDsOnNonCapstone() {
        var trophies = makeMiniCatalog()
        trophies.append(makeDefinition(id: "greedy_bronze",
                                       requiredTrophyIDs: ["mini_base"]))
        XCTAssertThrowsError(try TrophyCatalog.validate(trophies)) { error in
            XCTAssertEqual(error as? TrophyCatalogError,
                           .requiredIDsOnNonCapstone(id: "greedy_bronze"))
        }
    }

    func testValidateRejectsLedgerMetricOutsideCapstone() {
        let trophies = makeMiniCatalog() + [makeDefinition(id: "fake_capstone",
                                                           metric: .baseTrophiesUnlocked,
                                                           threshold: 1)]
        XCTAssertThrowsError(try TrophyCatalog.validate(trophies)) { error in
            XCTAssertEqual(error as? TrophyCatalogError,
                           .ledgerMetricOutsideCapstone(id: "fake_capstone"))
        }
    }

    func testValidateRejectsMissingOrDuplicateCapstone() {
        // No capstone at all.
        XCTAssertThrowsError(try TrophyCatalog.validate([makeDefinition(id: "lonely_bronze")])) { error in
            XCTAssertEqual(error as? TrophyCatalogError, .capstoneCountInvalid(found: 0))
        }
        // Two capstones.
        var trophies = makeMiniCatalog()
        trophies.append(makeDefinition(id: "second_capstone",
                                       tier: .platinum,
                                       category: .capstone,
                                       metric: .baseTrophiesUnlocked,
                                       threshold: 1,
                                       requiredTrophyIDs: ["mini_base"]))
        XCTAssertThrowsError(try TrophyCatalog.validate(trophies)) { error in
            XCTAssertEqual(error as? TrophyCatalogError, .capstoneCountInvalid(found: 2))
        }
    }

    // MARK: Criteria hygiene

    /// Thresholds are positive and finite; the only lte criterion is the
    /// speed clear; the mini-catalog validator accepts a well-formed list.
    func testCriteriaHygiene() throws {
        let catalog = try loadCatalog()
        for trophy in catalog.trophies {
            XCTAssertGreaterThan(trophy.criteria.threshold, 0, trophy.id)
            XCTAssertTrue(trophy.criteria.threshold.isFinite, trophy.id)
            if trophy.criteria.comparison == .lessOrEqual {
                XCTAssertEqual(trophy.id, "skill_speed_10s")
                XCTAssertEqual(trophy.criteria.metric, .fastestClearSeconds)
            }
            if trophy.id != "capstone_all" {
                XCTAssertNil(trophy.criteria.requiredTrophyIDs, trophy.id)
                XCTAssertNotEqual(trophy.criteria.metric, .baseTrophiesUnlocked, trophy.id)
            }
        }
        XCTAssertNoThrow(try TrophyCatalog.validate(makeMiniCatalog()))
        // Comparison semantics used by the engine later.
        XCTAssertTrue(TrophyComparison.lessOrEqual.isSatisfied(value: 9.8, threshold: 10.0))
        XCTAssertFalse(TrophyComparison.lessOrEqual.isSatisfied(value: 10.1, threshold: 10.0))
        XCTAssertTrue(TrophyComparison.greaterOrEqual.isSatisfied(value: 73, threshold: 73))
        XCTAssertFalse(TrophyComparison.greaterOrEqual.isSatisfied(value: 72, threshold: 73))
    }

    func testValidateRejectsNonPositiveThresholds() {
        let trophies = makeMiniCatalog() + [makeDefinition(id: "zero_bar", threshold: 0)]
        XCTAssertThrowsError(try TrophyCatalog.validate(trophies)) { error in
            XCTAssertEqual(error as? TrophyCatalogError, .invalidThreshold(id: "zero_bar"))
        }
    }
}

// MARK: - TrophyEngineTests (S0-T3)

/// UserDefaults spy: counts every object write to the suite. The engine
/// persists exclusively through `set(_ value: Any?, forKey:)` (plist array
/// + plist dict), so overriding that one funnel is sufficient to prove the
/// hot-path write discipline. (Typed scalar overloads like `set(Int,...)`
/// don't route through here — the engine never uses them.)
private final class WriteCountingDefaults: UserDefaults {
    private(set) var objectWriteCount = 0
    private(set) var writtenKeys: [String] = []

    override func set(_ value: Any?, forKey defaultName: String) {
        objectWriteCount += 1
        writtenKeys.append(defaultName)
        super.set(value, forKey: defaultName)
    }
}

/// S0-T3 acceptance tests for the TrophyEngine evaluation core:
/// double-fire idempotency (unlock exactly once, timestamp stable);
/// unlocks never revoked when the underlying stat regresses
/// (resetProgress / liquidateCoinCosmetics fixtures); evaluation per bump
/// is O(interested trophies) with zero hot-path persistence; latched
/// ledger in ra_trophyUnlocks / ra_trophyUnlockDates; monotonic progress.
///
/// Pattern for later sessions (S0-T4/S0-T5/S1-T9): every test runs
/// against a throwaway injected UserDefaults suite — the GameStateTests
/// pattern — so nothing touches the real save.
final class TrophyEngineTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "TrophyEngineTests.isolated"
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        cancellables = []
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: Fixtures

    /// Mutable injected clock — proves timestamp stability exactly.
    private final class Clock {
        var current = Date(timeIntervalSince1970: 1_750_000_000)
        func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
    }

    /// Engine over the real bundled 89-trophy catalog and the isolated
    /// suite (or a caller-supplied spy suite).
    private func makeEngine(clock: Clock = Clock(),
                            defaults: UserDefaults? = nil) throws -> TrophyEngine {
        TrophyEngine(catalog: try TrophyCatalog.load(bundle: .main),
                     defaults: defaults ?? self.defaults,
                     now: { clock.current })
    }

    /// GameState on the same isolated suite (regression fixtures).
    private func makeGameState() -> GameState {
        GameState(defaults: defaults)
    }

    private func makeDefinition(id: String,
                                tier: TrophyTier = .bronze,
                                category: TrophyCategory = .climb,
                                metric: TrophyMetric = .climbHighestUnlocked,
                                threshold: Double = 1,
                                requiredTrophyIDs: [String]? = nil) -> TrophyDefinition {
        TrophyDefinition(id: id,
                         title: "Title \(id)",
                         tier: tier,
                         category: category,
                         lockedDescription: "Do the thing.",
                         unlockedDescription: "You did the thing.",
                         isSecret: false,
                         criteria: TrophyCriteria(metric: metric,
                                                  threshold: threshold,
                                                  requiredTrophyIDs: requiredTrophyIDs),
                         rewardID: nil,
                         addedInVersion: TrophyCatalog.launchVersion)
    }

    /// A tiny valid catalog with two independently keyed base trophies and
    /// a capstone requiring both — staged capstone-cascade testing.
    private func makeMiniEngine(clock: Clock = Clock()) throws -> TrophyEngine {
        let trophies = [
            makeDefinition(id: "mini_climb", metric: .climbHighestUnlocked, threshold: 5),
            makeDefinition(id: "mini_snake", metric: .snakeWins, threshold: 3),
            makeDefinition(id: "mini_capstone",
                           tier: .platinum,
                           category: .capstone,
                           metric: .baseTrophiesUnlocked,
                           threshold: 2,
                           requiredTrophyIDs: ["mini_climb", "mini_snake"]),
        ]
        let file = TrophyCatalog.CatalogFile(catalogVersion: 1, trophies: trophies)
        let catalog = try TrophyCatalog.load(from: JSONEncoder().encode(file))
        return TrophyEngine(catalog: catalog, defaults: defaults, now: { clock.current })
    }

    /// Snapshot of the two persisted ledger keys, for before/after compares.
    private func persistedLedgerSnapshot() -> (ids: Set<String>, dates: [String: Date]) {
        let ids = Set((defaults.array(forKey: TrophyEngine.unlocksKey) as? [String]) ?? [])
        let dates = (defaults.dictionary(forKey: TrophyEngine.unlockDatesKey) ?? [:])
            .compactMapValues { $0 as? Date }
        return (ids, dates)
    }

    // MARK: Metric index — O(interested) evaluation shape

    /// The index is built once from the catalog and is exact: every metric
    /// maps to precisely the trophies whose criteria watch it, and the
    /// ledger-provenance capstone is cascade-only (never in the index).
    func testMetricIndexMatchesCatalogExactly() throws {
        let engine = try makeEngine()
        let catalog = engine.catalog
        var indexedTotal = 0
        for metric in TrophyMetric.allCases {
            let expected = Set(catalog.trophies
                .filter { $0.criteria.metric == metric && metric.provenance != .trophyLedger }
                .map(\.id))
            let interested = Set(engine.trophies(interestedIn: metric).map(\.id))
            XCTAssertEqual(interested, expected, "index wrong for \(metric.rawValue)")
            indexedTotal += interested.count
        }
        // Everything is reachable exactly once: 88 metric-indexed + the capstone.
        XCTAssertEqual(indexedTotal, 88)
        XCTAssertTrue(engine.trophies(interestedIn: .baseTrophiesUnlocked).isEmpty,
                      "the capstone must be cascade-only, never bump-evaluated")
    }

    #if DEBUG
    /// Acceptance: a stat bump evaluates ONLY interested trophies —
    /// O(interested), never O(catalog). snake_wins has 2 trophies;
    /// climb_highest_unlocked has the catalog's biggest fan-out (8);
    /// the catalog is 89.
    func testStatBumpEvaluatesOnlyInterestedTrophies() throws {
        let engine = try makeEngine()
        engine.record(.snakeWins, value: 0)
        XCTAssertEqual(engine.debugLastRecordEvaluationCount, 2)
        engine.record(.climbHighestUnlocked, value: 1)
        XCTAssertEqual(engine.debugLastRecordEvaluationCount, 8)
        engine.record(.signedIn, value: 0)
        XCTAssertEqual(engine.debugLastRecordEvaluationCount, 1)
        // Already-latched trophies still cost only the interested set.
        engine.record(.snakeWins, value: 1_000)
        engine.record(.snakeWins, value: 1_001)
        XCTAssertEqual(engine.debugLastRecordEvaluationCount, 2)
    }
    #endif

    /// Behavioral face of the same acceptance: a huge value on one metric
    /// latches exactly that metric's trophies and nothing else.
    func testBumpUnlocksOnlyInterestedTrophies() throws {
        let engine = try makeEngine()
        let unlocked = engine.record(.snakeWins, value: 1_000_000)
        XCTAssertEqual(Set(unlocked.map(\.id)), ["snake_first_win", "snake_wins_10"])
        XCTAssertEqual(engine.unlockedIDs, ["snake_first_win", "snake_wins_10"])
    }

    /// Acceptance: no hot-path persistence — a bump that unlocks nothing
    /// performs ZERO UserDefaults writes and ZERO objectWillChange
    /// emissions; an unlocking bump writes exactly the two ledger keys
    /// (plist-native — no JSON Data blobs) and publishes exactly once.
    func testNoWritesAndNoPublishOnNonUnlockingBumps() throws {
        let spy = WriteCountingDefaults(suiteName: suiteName)!
        let engine = try makeEngine(defaults: spy)
        var publishes = 0
        engine.objectWillChange.sink { _ in publishes += 1 }.store(in: &cancellables)

        for i in 0..<200 {
            engine.record(.climbTotalStars, value: Double(i % 24))   // threshold 25 never met
        }
        XCTAssertEqual(spy.objectWriteCount, 0, "hot path must never touch UserDefaults")
        XCTAssertEqual(publishes, 0, "hot path must never re-render observers")

        let unlocked = engine.record(.climbTotalStars, value: 25)    // climb_stars_25
        XCTAssertEqual(unlocked.map(\.id), ["climb_stars_25"])
        XCTAssertEqual(publishes, 1, "exactly one publish per unlocking bump")
        XCTAssertEqual(spy.objectWriteCount, 2)
        XCTAssertEqual(Set(spy.writtenKeys),
                       [TrophyEngine.unlocksKey, TrophyEngine.unlockDatesKey])

        // Plist-native shapes: a string array + a Date-valued dictionary,
        // and neither key holds a JSON-encoded Data blob.
        XCTAssertEqual(spy.array(forKey: TrophyEngine.unlocksKey) as? [String],
                       ["climb_stars_25"])
        let dates = try XCTUnwrap(spy.dictionary(forKey: TrophyEngine.unlockDatesKey))
        XCTAssertTrue(dates["climb_stars_25"] is Date)
        XCTAssertNil(spy.data(forKey: TrophyEngine.unlocksKey))
        XCTAssertNil(spy.data(forKey: TrophyEngine.unlockDatesKey))
    }

    // MARK: Double-fire idempotency

    /// Acceptance: unlock exactly once, timestamp stable. The second
    /// satisfying bump returns nothing, changes nothing, restamps nothing
    /// — in memory and on disk.
    func testDoubleFireUnlocksExactlyOnceWithStableTimestamp() throws {
        let clock = Clock()
        let engine = try makeEngine(clock: clock)
        let t1 = clock.current

        XCTAssertEqual(engine.record(.climbTotalStars, value: 25).map(\.id), ["climb_stars_25"])
        XCTAssertEqual(engine.unlockDate(for: "climb_stars_25"), t1)
        let firstSnapshot = persistedLedgerSnapshot()

        clock.advance(86_400)
        XCTAssertTrue(engine.record(.climbTotalStars, value: 30).isEmpty, "double fire must be a no-op")
        XCTAssertTrue(engine.record(.climbTotalStars, value: 25).isEmpty)
        XCTAssertEqual(engine.unlockedIDs, ["climb_stars_25"])
        XCTAssertEqual(engine.unlockDate(for: "climb_stars_25"), t1, "timestamp must be stable")

        let secondSnapshot = persistedLedgerSnapshot()
        XCTAssertEqual(secondSnapshot.ids, firstSnapshot.ids)
        XCTAssertEqual(secondSnapshot.dates, firstSnapshot.dates)

        // And across a relaunch: a fresh engine still reports t1.
        let relaunched = try makeEngine(clock: clock)
        XCTAssertTrue(relaunched.isUnlocked("climb_stars_25"))
        XCTAssertEqual(relaunched.unlockDate(for: "climb_stars_25"), t1)
        // Re-push a value that still clears climb_stars_25 (>=25) but stays
        // below the next rung climb_stars_150 (150) — so a genuine re-latch,
        // not a sibling first-unlock, is what this asserts against.
        XCTAssertTrue(relaunched.record(.climbTotalStars, value: 30).isEmpty,
                      "re-satisfying after relaunch must not re-unlock")
    }

    // MARK: Ratchet — regression fixtures

    /// Acceptance: an unlock is NEVER revoked when the underlying stat
    /// regresses. Fixture 1: `resetProgress()` zeroes `totalStars`, the
    /// exact regressable stat behind climb_stars_25 (catalog: "latched —
    /// resetProgress() can shrink the live sum").
    func testUnlockSurvivesResetProgress() throws {
        let gs = makeGameState()
        for level in 1...9 {
            gs.recordResult(level: level, stars: 3, time: 30, coinIndices: [])
        }
        XCTAssertGreaterThanOrEqual(gs.totalStars, 25)

        let clock = Clock()
        let engine = try makeEngine(clock: clock)
        engine.record(.climbTotalStars, value: gs.totalStars)
        XCTAssertTrue(engine.isUnlocked("climb_stars_25"))
        let stamp = engine.unlockDate(for: "climb_stars_25")
        let before = persistedLedgerSnapshot()

        gs.resetProgress()
        XCTAssertEqual(gs.totalStars, 0, "fixture must actually regress the stat")

        // The reset itself must not touch the ledger keys...
        let after = persistedLedgerSnapshot()
        XCTAssertEqual(after.ids, before.ids)
        XCTAssertEqual(after.dates, before.dates)

        // ...and re-recording the regressed value must never revoke.
        clock.advance(3_600)
        XCTAssertTrue(engine.record(.climbTotalStars, value: gs.totalStars).isEmpty)
        XCTAssertTrue(engine.isUnlocked("climb_stars_25"))
        XCTAssertEqual(engine.unlockDate(for: "climb_stars_25"), stamp)

        // A cold engine over the same save agrees.
        let relaunched = try makeEngine(clock: clock)
        XCTAssertTrue(relaunched.isUnlocked("climb_stars_25"))
    }

    /// Fixture 2: `liquidateCoinCosmetics()` (Sell Back) strips sellable
    /// cosmetics — the regressable stat behind balls_own_10.
    func testUnlockSurvivesLiquidateCoinCosmetics() throws {
        let gs = makeGameState()
        let sellable = BallSkin.allCases.filter(\.isSellable).prefix(10)
        XCTAssertEqual(sellable.count, 10, "catalogue must offer 10 sellable skins")
        for skin in sellable { gs.ownedBallSkins.insert(skin.rawValue) }
        let ownedBefore = gs.ownedBallSkins.count
        XCTAssertGreaterThanOrEqual(ownedBefore, 10)

        let clock = Clock()
        let engine = try makeEngine(clock: clock)
        engine.record(.ballsOwned, value: ownedBefore)
        XCTAssertTrue(engine.isUnlocked("balls_own_10"))
        let stamp = engine.unlockDate(for: "balls_own_10")
        let before = persistedLedgerSnapshot()

        gs.liquidateCoinCosmetics()
        XCTAssertLessThan(gs.ownedBallSkins.count, 10,
                          "fixture must actually regress ownership")

        let after = persistedLedgerSnapshot()
        XCTAssertEqual(after.ids, before.ids)
        XCTAssertEqual(after.dates, before.dates)

        clock.advance(60)
        XCTAssertTrue(engine.record(.ballsOwned, value: gs.ownedBallSkins.count).isEmpty)
        XCTAssertTrue(engine.isUnlocked("balls_own_10"))
        XCTAssertEqual(engine.unlockDate(for: "balls_own_10"), stamp)

        let relaunched = try makeEngine(clock: clock)
        XCTAssertTrue(relaunched.isUnlocked("balls_own_10"))
    }

    // MARK: Observable isolation

    /// Acceptance: trophy state lives in its OWN ObservableObject —
    /// engine unlocks must never emit through GameState.objectWillChange,
    /// so gameplay views observing GameState never re-render on trophy
    /// writes.
    func testEngineUnlockNeverEmitsThroughGameState() throws {
        let gs = makeGameState()
        let engine = try makeEngine()

        var gameStateEmissions = 0
        gs.objectWillChange.sink { _ in gameStateEmissions += 1 }.store(in: &cancellables)
        var engineEmissions = 0
        engine.objectWillChange.sink { _ in engineEmissions += 1 }.store(in: &cancellables)

        engine.record(.climbTotalStars, value: 10)          // no unlock
        engine.record(.climbTotalStars, value: 1_000)       // unlocks both star trophies
        XCTAssertEqual(engine.unlockedIDs.count, 2)
        XCTAssertEqual(engineEmissions, 1)
        XCTAssertEqual(gameStateEmissions, 0,
                       "trophy writes must never re-render GameState observers")
    }

    // MARK: Capstone — ledger cascade, never external

    /// The ledger metric is engine-derived: an external push can never
    /// forge the capstone open.
    func testLedgerMetricIgnoresExternalPush() throws {
        let engine = try makeEngine()
        XCTAssertTrue(engine.record(.baseTrophiesUnlocked, value: 1_000).isEmpty)
        XCTAssertFalse(engine.isUnlocked("capstone_all"))
        XCTAssertTrue(engine.unlockedIDs.isEmpty)
    }

    /// The capstone latches by cascade the moment its required set
    /// completes, stamped at the same commit — and never before.
    func testCapstoneCascadesWhenRequiredSetCompletes() throws {
        let clock = Clock()
        let engine = try makeMiniEngine(clock: clock)

        XCTAssertEqual(engine.record(.climbHighestUnlocked, value: 5).map(\.id), ["mini_climb"])
        XCTAssertFalse(engine.isUnlocked("mini_capstone"))
        XCTAssertEqual(engine.progressFraction(for: "mini_capstone"), 0.5)

        clock.advance(120)
        let completing = engine.record(.snakeWins, value: 3)
        XCTAssertEqual(completing.map(\.id), ["mini_snake", "mini_capstone"],
                       "the completing bump must return the cascaded capstone too")
        XCTAssertTrue(engine.isUnlocked("mini_capstone"))
        XCTAssertEqual(engine.unlockDate(for: "mini_capstone"), clock.current)
        XCTAssertEqual(engine.progressFraction(for: "mini_capstone"), 1)

        // Cascade is idempotent like everything else.
        XCTAssertTrue(engine.record(.snakeWins, value: 50).isEmpty)
    }

    /// Real-catalog spot check: one capstone-path unlock moves the
    /// capstone's ledger-derived progress to exactly 1/73.
    func testCapstoneProgressDerivesFromLedgerOnRealCatalog() throws {
        let engine = try makeEngine()
        XCTAssertEqual(engine.progressFraction(for: "capstone_all"), 0)
        engine.record(.climbTotalStars, value: 25)           // climb_stars_25 is on the path
        XCTAssertEqual(engine.progressFraction(for: "capstone_all") ?? 0,
                       1.0 / 73.0, accuracy: 0.000_001)
        XCTAssertFalse(engine.isUnlocked("capstone_all"))
    }

    // MARK: Monotonic progress

    /// Progress rides a high-water latch: regressed values never walk it
    /// back, unlock pins it at 1.0 forever, unknown ids are nil.
    func testProgressFractionIsMonotonic() throws {
        let engine = try makeEngine()
        XCTAssertEqual(engine.progressFraction(for: "climb_stars_25"), 0)

        engine.record(.climbTotalStars, value: 5)
        XCTAssertEqual(engine.progressFraction(for: "climb_stars_25") ?? 0, 0.2, accuracy: 0.000_001)

        engine.record(.climbTotalStars, value: 3)            // regression
        XCTAssertEqual(engine.progressFraction(for: "climb_stars_25") ?? 0, 0.2, accuracy: 0.000_001,
                       "a regressed stat must never walk progress back")

        engine.record(.climbTotalStars, value: 25)
        XCTAssertEqual(engine.progressFraction(for: "climb_stars_25"), 1)

        XCTAssertNil(engine.progressFraction(for: "no_such_trophy"))
    }

    /// The lte criterion (speed clear) is binary 0 → 1, min-latched:
    /// slower times never satisfy, the first fast-enough clear latches.
    func testLessOrEqualCriterionProgressAndUnlock() throws {
        let engine = try makeEngine()
        XCTAssertEqual(engine.progressFraction(for: "skill_speed_10s"), 0)

        engine.record(.fastestClearSeconds, value: 12.0)
        XCTAssertFalse(engine.isUnlocked("skill_speed_10s"))
        XCTAssertEqual(engine.progressFraction(for: "skill_speed_10s"), 0)

        XCTAssertEqual(engine.record(.fastestClearSeconds, value: 9.5).map(\.id),
                       ["skill_speed_10s"])
        XCTAssertEqual(engine.progressFraction(for: "skill_speed_10s"), 1)

        // A later slower time can never revoke (ratchet).
        XCTAssertTrue(engine.record(.fastestClearSeconds, value: 60).isEmpty)
        XCTAssertTrue(engine.isUnlocked("skill_speed_10s"))
    }

    // MARK: Ledger loading — healing + unknown ids

    /// A crash between the two ledger writes heals toward MORE unlocked
    /// (the ratchet direction): ids present in either key survive.
    func testPartialLedgerWritesHealToTheUnion() throws {
        // ids-only (dates write lost).
        defaults.set(["climb_stars_25"], forKey: TrophyEngine.unlocksKey)
        var engine = try makeEngine()
        XCTAssertTrue(engine.isUnlocked("climb_stars_25"))
        XCTAssertNil(engine.unlockDate(for: "climb_stars_25"))
        // >=25 re-satisfies the healed climb_stars_25 but stays under the
        // next rung climb_stars_150 (150), so [] means "no re-latch", not
        // "a higher sibling happened to unlock".
        XCTAssertTrue(engine.record(.climbTotalStars, value: 30).isEmpty,
                      "healed unlock must not re-latch")

        // dates-only (ids write lost) + one corrupt non-Date entry.
        defaults.removePersistentDomain(forName: suiteName)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(["snake_first_win": stamp, "corrupt_entry": "not a date"],
                     forKey: TrophyEngine.unlockDatesKey)
        engine = try makeEngine()
        XCTAssertTrue(engine.isUnlocked("snake_first_win"))
        XCTAssertEqual(engine.unlockDate(for: "snake_first_win"), stamp)
        // A corrupt-VALUED entry still counts as unlock evidence (ratchet
        // direction) — only its bad date is dropped.
        XCTAssertTrue(engine.isUnlocked("corrupt_entry"))
        XCTAssertNil(engine.unlockDate(for: "corrupt_entry"),
                     "a corrupt timestamp entry must not survive as a date")
    }

    /// Ledger ids not in this build's catalog (a save from a newer app
    /// version) are kept and re-persisted, never dropped — the catalog is
    /// additive-only, so they are somebody's real unlocks.
    func testUnknownLedgerIDsAreNeverDropped() throws {
        defaults.set(["trophy_from_the_future"], forKey: TrophyEngine.unlocksKey)
        let engine = try makeEngine()
        XCTAssertTrue(engine.isUnlocked("trophy_from_the_future"))
        XCTAssertNil(engine.progressFraction(for: "trophy_from_the_future"))

        engine.record(.snakeWins, value: 1)                  // forces a re-persist
        let persisted = persistedLedgerSnapshot()
        XCTAssertTrue(persisted.ids.contains("trophy_from_the_future"))
        XCTAssertTrue(persisted.ids.contains("snake_first_win"))
    }
}
