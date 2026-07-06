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
        // Reconciled to the wired reality (S1-T5): `balls_own_10` is now
        // recorded to GameState's OWN engine by the real `grant` funnel, and
        // `liquidateCoinCosmetics()` regresses ownership (and refunds coins
        // through `addCoins`, which also latches `econ_nest_egg`). The
        // ratchet claim is unchanged: an unlock earned before liquidation
        // survives it and a relaunch.
        let gs = makeGameState()
        let sellable = Array(BallSkin.allCases.filter(\.isSellable).prefix(10))
        XCTAssertEqual(sellable.count, 10, "catalogue must offer 10 sellable skins")
        for skin in sellable { gs.grant(skin) }   // the real ownership funnel
        XCTAssertGreaterThanOrEqual(gs.ownedBallSkins.count, 10)

        let engine = gs.trophyEngine
        XCTAssertTrue(engine.isUnlocked("balls_own_10"),
                      "granting 10 balls latches balls_own_10 through the funnel")
        let stamp = engine.unlockDate(for: "balls_own_10")

        gs.liquidateCoinCosmetics()
        XCTAssertLessThan(gs.trophyBallsOwnedCount, 10,
                          "fixture must actually regress ownership")

        // The ratchet holds: the unlock and its timestamp are untouched by
        // the regression, and a fresh engine over the same suite still sees it.
        XCTAssertTrue(engine.isUnlocked("balls_own_10"))
        XCTAssertEqual(engine.unlockDate(for: "balls_own_10"), stamp)

        let relaunched = try makeEngine()
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

// MARK: - TrophyTestHarness (S0-T5 — shared QA scaffolding)
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │  THE trophy test harness. Copy this pattern in every S1 trigger test.  │
// └──────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ---------------
// S1 wires each catalog trophy to a real GameState/social funnel. Those
// trigger tests must prove a trophy unlocks *through the public API* — never
// by reaching into TrophyEngine internals or hand-poking `ra_trophyUnlocks`.
// This harness is the sanctioned way to do that: it owns an isolated
// UserDefaults suite, a real `GameState`, and a real `TrophyEngine` over the
// bundled 89-trophy catalog, and it drives them exactly the way the shipping
// app will.
//
// THE ONE MOVE THE HARNESS MAKES: re-derive-and-record
// ----------------------------------------------------
// Trophy metrics are cumulative/latched values, not deltas. A player action
// mutates GameState; the engine then wants each affected metric's CURRENT
// value. `TrophyBackfill.snapshot(from:)` is the single authority that derives
// every metric from a GameState decode (it is also what S0-T4 backfill uses),
// so the harness's `sync()` is precisely: snapshot the GameState, `record`
// each metric at its current value, return everything that newly unlocked.
// `record` is a monotonic ratchet and silently ignores the ledger metric, so
// re-syncing after every mutation is always safe and idempotent — which is
// exactly the contract S1's live funnels will honour. (When S1 makes GameState
// funnels call the engine directly, tests can drop the explicit `sync()` and
// assert on the funnel's return; until then `sync()` stands in for that wiring
// and the assertions do not change.)
//
// HOW TO USE IT (the copy-paste shape for S1-T*)
// ----------------------------------------------
//     func testSomeTrophyFiresAtThreshold() {
//         let h = TrophyTestHarness()               // fresh isolated suite
//         // 1. drive the PUBLIC GameState API up to the boundary
//         h.gameState.currentModeID = "climb"
//         for level in 1...9 { h.gameState.recordResult(level: level, stars: 3,
//                                                        time: 30, coinIndices: []) }
//         // 2. re-derive + record, then assert on the unlock SET
//         let unlocked = h.sync()
//         h.assertUnlocked("climb_stars_25", in: unlocked)   // newly this sync
//         h.assertUnlocked("climb_stars_25")                 // latched overall
//         h.assertLocked("climb_stars_150")
//     }
//
// Boundary tests: sync at threshold−1 (assert locked), push to threshold
// (assert it appears in the sync's newly-unlocked set), push past (assert the
// double-fire is a no-op — `h.sync()` returns []). Canned saves: start from a
// mid/veteran dump with `TrophyTestHarness(save:)` to prove backfill + live
// interplay. Everything is on a throwaway suite wiped on `deinit`, so tests
// never touch the real save (the GameStateTests injected-UserDefaults rule).
//
// SCOPE: unit-level only. XCUITest is explicitly out of scope for trigger
// logic (sprint-plan.md §4g) — put trigger/migration/queue behaviour here.
//
final class TrophyTestHarness {

    /// The isolated suite everything is injected with — never "standard".
    let defaults: UserDefaults
    /// A real GameState decode over `defaults` — driven by its PUBLIC API.
    let gameState: GameState
    /// A real engine over the bundled 89-trophy catalog and the same suite.
    let engine: TrophyEngine

    private let suiteName: String
    private let clock: HarnessClock

    /// A mutable injected clock so live-unlock timestamps are deterministic
    /// (backfilled grants still carry `TrophyEngine.legacyUnlockDate`).
    final class HarnessClock {
        var current = Date(timeIntervalSince1970: 1_750_000_000)
        func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
    }

    /// A canned pre-trophy save shape to seed before the GameState decode —
    /// the same dumps the S0-T4 migration fixtures exercise, so trigger tests
    /// can start from a believable veteran/mid save instead of only zero.
    enum CannedSave {
        case fresh          // no `ra_*` keys — a brand-new install
        case midProgress    // ~climb 40, a scatter of stars, one arcade win
        case veteran        // past every derivable catalog threshold
    }

    // MARK: Construction

    /// Fresh isolated suite (optionally seeded from a canned save), the
    /// injected-defaults `makeGameState`/engine pattern from GameStateTests.
    /// Each instance gets a unique suite so parallel tests never collide.
    init(save: CannedSave = .fresh,
         backfill: Bool = false,
         file: StaticString = #fileID,
         line: UInt = #line) {
        self.suiteName = "TrophyTestHarness.\(file).\(line).\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        Self.seed(save, into: defaults)

        let clock = HarnessClock()
        self.clock = clock
        // The authoritative decode, with the injected clock so live-unlock
        // timestamps are deterministic.  Since S1-T1, GameState OWNS its
        // trophy engine and drives it from real gameplay funnels, so the
        // harness observes `gameState.trophyEngine` directly — the same
        // engine the live funnels write.  (Pre-S1-T1 the harness built a
        // separate engine and stood in for the wiring via `sync()`; that
        // stand-in is now the real thing for wired metrics, and `sync()`
        // still covers not-yet-wired metrics idempotently.)
        self.gameState = TrophyTestHarness.makeGameState(defaults: defaults,
                                                         now: { clock.current })
        self.engine = gameState.trophyEngine
        if backfill {
            gameState.activateTrophies()
        }
    }

    deinit { defaults.removePersistentDomain(forName: suiteName) }

    /// The canonical injected-defaults constructor named by S0-T5 — a
    /// GameState backed by a caller-supplied throwaway suite, never the real
    /// "standard" save (GameStateTests pattern). Exposed statically so any
    /// test file can build a bare GameState on its own suite without a harness.
    /// `now` pins the trophy engine's clock for deterministic timestamps.
    static func makeGameState(defaults: UserDefaults,
                              now: @escaping () -> Date = Date.init) -> GameState {
        GameState(defaults: defaults, now: now)
    }

    // MARK: The core move — re-derive + record

    /// Re-derive every metric from the current GameState and push it into the
    /// engine, returning trophies that unlocked ON THIS sync (cascaded
    /// capstone included). Idempotent: an unchanged GameState syncs to [].
    @discardableResult
    func sync() -> [TrophyDefinition] {
        let snapshot = TrophyBackfill.snapshot(from: gameState)
        var unlocked: [TrophyDefinition] = []
        // Deterministic order so a multi-metric bump reads reproducibly.
        for metric in TrophyMetric.allCases {
            guard let value = snapshot[metric] else { continue }
            unlocked.append(contentsOf: engine.record(metric, value: value))
        }
        return unlocked
    }

    /// Drive a single metric directly (for a metric with no GameState funnel
    /// yet, e.g. a social latch or a run-event flag S1 will wire). Returns
    /// what unlocked on this bump.
    @discardableResult
    func record(_ metric: TrophyMetric, value: Double) -> [TrophyDefinition] {
        engine.record(metric, value: value)
    }

    /// Advance the injected clock — new live unlocks stamp the advanced time,
    /// so a test can prove timestamp stability across a double-fire.
    func advanceClock(_ seconds: TimeInterval) { clock.advance(seconds) }
    var now: Date { clock.current }

    // MARK: Unlock-set assertions (public engine API only)

    /// The full latched unlock set — the engine's public view, never the raw
    /// UserDefaults key.
    var unlockedIDs: Set<String> { engine.unlockedIDs }

    func assertUnlocked(_ id: String,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(engine.isUnlocked(id), "expected \(id) unlocked", file: file, line: line)
    }

    func assertLocked(_ id: String,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(engine.isUnlocked(id), "expected \(id) still locked", file: file, line: line)
    }

    /// Assert `id` is among a specific sync/record call's newly-unlocked set
    /// — the "fired on THIS action" boundary check.
    func assertUnlocked(_ id: String, in batch: [TrophyDefinition],
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(batch.contains { $0.id == id },
                      "expected \(id) in this batch, got \(batch.map(\.id))",
                      file: file, line: line)
    }

    /// Assert the exact set of ids that unlocked on a sync/record call.
    func assertNewlyUnlocked(_ ids: Set<String>, in batch: [TrophyDefinition],
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(batch.map(\.id)), ids, file: file, line: line)
    }

    // MARK: Canned-save seeding (reuses S0-T4's real `ra_*` dump shapes)

    /// Seed a suite with a pre-trophy `ra_*` dump in the exact on-disk format
    /// GameState persists — mirrors the S0-T4 migration fixtures so trigger
    /// tests and migration tests exercise the same believable saves.
    private static func seed(_ save: CannedSave, into defaults: UserDefaults) {
        switch save {
        case .fresh:
            break                                   // no keys — a clean install

        case .midProgress:
            defaults.set(41, forKey: "ra_highestUnlocked")      // cleared through ~40
            var stars: [Int: Int] = [:]
            for level in 1...12 { stars[level] = 3 }             // 36 stars
            writeIntDict(stars, key: "ra_bestStars", defaults)
            var pickups: [Int: Set<Int>] = [:]
            for level in 1...20 { pickups[level] = [0, 1, 2] }   // 60 pickups
            writeSetDict(pickups, key: "ra_collectedCoins", defaults)
            writeDoubleDict([3: 8.5, 7: 22.0], key: "ra_bestTime", defaults)   // sub-10s clear
            writeStringDict(["snake": 1], key: "ra_minigameWins", defaults)
            writeStringSet(["snake", "zen"], key: "ra_playedModeIDs", defaults)
            defaults.set(3600, forKey: "ra_zenSeconds")         // exactly 1 hour
            writeStringSet(["standard"], key: "ra_ownedBundles", defaults)
            defaults.set(400, forKey: "ra_coinBalance")

        case .veteran:
            defaults.set(5001, forKey: "ra_highestUnlocked")
            var stars: [Int: Int] = [:]
            for level in 1...100 { stars[level] = 3 }            // world 1 perfect + huge sum
            writeIntDict(stars, key: "ra_bestStars", defaults)
            var pickups: [Int: Set<Int>] = [:]
            for level in 1...60 { pickups[level] = [0, 1, 2] }   // 180 pickups
            writeSetDict(pickups, key: "ra_collectedCoins", defaults)
            writeDoubleDict([2: 6.5, 40: 30.0], key: "ra_bestTime", defaults)
            let allTracks: Set<String> = ["adventure", "expert", "gauntlet", "nightmare",
                                          "speed", "precision", "endurance", "golden-gauntlet"]
            writeStringSet(allTracks, key: "ra_completedTracks", defaults)
            writeStringDict(["adventure": 100, "golden-gauntlet": 100],
                            key: "ra_trackProgress", defaults)
            writeStringSet(consecutiveDailyKeys(count: 60), key: "ra_dailyChallengeDone", defaults)
            defaults.set(45, forKey: "ra_dailyStreak")
            writeStringSet(Set(TrophyMetric.minigameModeIDs), key: "ra_playedModeIDs", defaults)
            writeStringDict(["snake": 20, "sumo": 20, "paintball": 20,
                             "goldrush": 20, "marblecup": 20, "koth": 20],
                            key: "ra_minigameWins", defaults)
            var hard: [String: Int] = [:]
            for id in TrophyMetric.competitiveModeIDs { hard["\(id)|hard"] = 3 }
            writeStringDict(hard, key: "ra_minigameDiffWins", defaults)
            writeStringDict(["paintball": 80, "koth": 55, "rollout": 15,
                             "rollup": 700, "discohard": 15, "discoeasy": 40],
                            key: "ra_minigameBests", defaults)
            defaults.set(200_000, forKey: "ra_pinballBest")
            defaults.set(40_000, forKey: "ra_zenSeconds")
            defaults.set(120, forKey: "ra_goldrushBest")
            defaults.set(5_000, forKey: "ra_goldrushCoinsTotal")
            writeStringSet(Set(CosmeticBundle.catalogue.prefix(6).map(\.id)),
                           key: "ra_ownedBundles", defaults)
            writeStringSet(["planets"], key: "ra_ownedPacks", defaults)
            defaults.set(5_000, forKey: "ra_coinBalance")
        }
    }

    // Fixture writers — the real `ra_*` on-disk formats (S0-T4 shapes).
    private static func writeIntDict(_ dict: [Int: Int], key: String, _ d: UserDefaults) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: dict.map { (String($0.key), $0.value) })
        d.set(try! JSONEncoder().encode(stringKeyed), forKey: key)
    }
    private static func writeDoubleDict(_ dict: [Int: Double], key: String, _ d: UserDefaults) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: dict.map { (String($0.key), $0.value) })
        d.set(try! JSONEncoder().encode(stringKeyed), forKey: key)
    }
    private static func writeSetDict(_ dict: [Int: Set<Int>], key: String, _ d: UserDefaults) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: dict.map { (String($0.key), Array($0.value)) })
        d.set(try! JSONEncoder().encode(stringKeyed), forKey: key)
    }
    private static func writeStringDict(_ dict: [String: Int], key: String, _ d: UserDefaults) {
        d.set(try! JSONEncoder().encode(dict), forKey: key)
    }
    private static func writeStringSet(_ set: Set<String>, key: String, _ d: UserDefaults) {
        d.set(Array(set), forKey: key)
    }

    /// `count` consecutive "YYYY-MM-DD" keys ending today (UTC) — the
    /// `DailyChallenge.key()` format the completions set stores.
    private static func consecutiveDailyKeys(count: Int) -> Set<String> {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        var keys = Set<String>()
        let today = cal.startOfDay(for: Date())
        for offset in 0..<count {
            if let day = cal.date(byAdding: .day, value: -offset, to: today) {
                keys.insert(fmt.string(from: day))
            }
        }
        return keys
    }
}

// MARK: - TrophyTestHarnessTests (S0-T5 acceptance)

/// Proves the shared harness works end-to-end BEFORE S1 leans on it: the
/// harness compiles, the demo drives the PUBLIC GameState API and asserts an
/// unlock (the S0-T5 acceptance criterion), and the canned saves + assertion
/// helpers behave. If any of these break, every S1 trigger test built on the
/// pattern is suspect — so this is the guardrail for the scaffolding itself.
final class TrophyTestHarnessTests: XCTestCase {

    // MARK: The demo — bump a stat through public API → assert unlock

    /// S0-T5 acceptance: end-to-end proof. Nine 3-star climb clears through
    /// the PUBLIC `recordResult` API push totalStars past 25 and latch
    /// `climb_stars_25` — since S1-T1 the LIVE climb funnel drives the engine
    /// directly, so the unlock lands during `recordResult` itself (a
    /// following `sync()` is idempotent). No engine internals touched.
    func testHarnessDemo_publicAPIStatBumpUnlocksTrophy() {
        let h = TrophyTestHarness()
        h.assertLocked("climb_stars_25")

        // Drive only the public GameState API.
        h.gameState.currentModeID = "climb"
        for level in 1...9 {
            h.gameState.recordResult(level: level, stars: 3, time: 30, coinIndices: [])
        }
        XCTAssertGreaterThanOrEqual(h.gameState.totalStars, 25, "fixture must clear the bar")

        // The live funnel already latched it; a re-sync grants nothing new.
        h.assertUnlocked("climb_stars_25")                 // latched via live funnel
        XCTAssertFalse(h.sync().contains { $0.id == "climb_stars_25" },
                       "already latched — re-sync is a no-op for the target")
        h.assertLocked("climb_stars_150")                  // next rung untouched
    }

    // MARK: Boundary + double-fire, the S1 copy-paste shape

    /// The threshold−1 / threshold / threshold+1 + idempotency shape S1
    /// trigger tests follow, exercised through the harness to prove it
    /// supports them.  Since S1-T1 the LIVE climb funnel drives the engine,
    /// so the target latches during the threshold `recordResult` itself; the
    /// following `sync()` is idempotent and a double-fire never restamps.
    func testHarnessSupportsBoundaryAndDoubleFire() {
        let h = TrophyTestHarness()

        // threshold−1: eight 3-star clears = 24 stars, below 25.
        h.gameState.currentModeID = "climb"
        for level in 1...8 { h.gameState.recordResult(level: level, stars: 3, time: 30, coinIndices: []) }
        XCTAssertEqual(h.gameState.totalStars, 24)
        h.assertLocked("climb_stars_25")
        XCTAssertFalse(h.sync().contains { $0.id == "climb_stars_25" },
                       "no star unlock below threshold")

        // threshold: the 25th star latches via the live funnel.
        h.gameState.recordResult(level: 9, stars: 3, time: 30, coinIndices: [])
        h.assertUnlocked("climb_stars_25")
        let stamp = h.engine.unlockDate(for: "climb_stars_25")

        // threshold+1 / double-fire: more stars, later clock — the target
        // never re-unlocks and its timestamp is stable.
        h.advanceClock(3_600)
        h.gameState.recordResult(level: 10, stars: 3, time: 30, coinIndices: [])
        XCTAssertFalse(h.sync().contains { $0.id == "climb_stars_25" },
                       "double fire must not re-unlock the target")
        XCTAssertEqual(h.engine.unlockDate(for: "climb_stars_25"), stamp,
                       "timestamp must be stable across the double-fire")
    }

    // MARK: Direct-metric driving (for funnels S1 hasn't wired yet)

    /// A metric with no GameState funnel yet (a social latch) can be driven
    /// directly — the escape hatch S1-T6/S1-T7 tests use before the funnel
    /// exists.
    func testHarnessDrivesMetricsWithoutAGameStateFunnel() {
        let h = TrophyTestHarness()
        h.assertLocked("social_sign_in")
        let batch = h.record(.signedIn, value: 1)
        h.assertUnlocked("social_sign_in", in: batch)
        h.assertUnlocked("social_sign_in")
    }

    // MARK: Canned saves

    /// A fresh save syncs to nothing (a live install starts at zero unlocks).
    func testCannedFreshSaveIsEmpty() {
        let h = TrophyTestHarness(save: .fresh)
        XCTAssertTrue(h.sync().isEmpty)
        XCTAssertTrue(h.unlockedIDs.isEmpty)
    }

    /// The veteran canned save carries real history: a `sync()` over it
    /// latches the derivable milestones (backfill-equivalent through the
    /// live path), proving trigger tests can start from a believable maxed
    /// save rather than only zero.
    func testCannedVeteranSaveSyncsDerivableMilestones() {
        let h = TrophyTestHarness(save: .veteran)
        h.sync()
        for id in ["climb_first_clear", "climb_summit", "track_all_eight",
                   "snake_wins_10", "pinball_score_150k", "zen_10_hours"] {
            h.assertUnlocked(id)
        }
        // A non-derivable, live-only trophy stays locked even on a maxed save.
        h.assertLocked("social_sign_in")
        h.assertLocked("capstone_all")     // 12 base trophies need live play
    }

    /// `backfill: true` runs the S0-T4 retro-grant path at construction, so a
    /// harness can start already-grandfathered (the state S1 sees post-update)
    /// and grants carry the legacy marker, not the live clock.
    func testCannedSaveWithBackfillGrantsLegacyStamped() {
        let h = TrophyTestHarness(save: .veteran, backfill: true)
        h.assertUnlocked("climb_first_clear")
        XCTAssertTrue(h.engine.didBackfill)
        XCTAssertEqual(h.engine.unlockDate(for: "climb_first_clear"),
                       TrophyEngine.legacyUnlockDate,
                       "backfilled grants carry the legacy marker, not now()")
    }

    // MARK: Isolation

    /// Two harnesses never share a suite: an unlock in one is invisible in
    /// the other (the parallel-safe isolation S1's suite needs).
    func testHarnessesAreIsolated() {
        let a = TrophyTestHarness()
        let b = TrophyTestHarness()
        a.record(.signedIn, value: 1)
        a.assertUnlocked("social_sign_in")
        b.assertLocked("social_sign_in")
    }

    /// The named injected-defaults helper builds a GameState on a supplied
    /// suite and never touches the real save.
    func testMakeGameStateUsesInjectedDefaults() {
        let suite = "TrophyTestHarnessTests.makeGameState.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let gs = TrophyTestHarness.makeGameState(defaults: defaults)
        gs.coinBalance = 4_242
        // The value round-trips through the injected suite, not "standard".
        let reloaded = TrophyTestHarness.makeGameState(defaults: defaults)
        XCTAssertEqual(reloaded.coinBalance, 4_242)
    }
}

// MARK: - S1-T2 — Track + Daily trigger wiring

/// End-to-end wiring tests: drive the PUBLIC GameState funnels (never the
/// engine directly) and assert the 14 Challenge-Track / Challenge-of-the-Day
/// trophies latch through the funnel → `trophyEngine.record` path. Each test
/// runs on its own throwaway UserDefaults suite; the GameState it builds owns
/// the engine those funnels drive, so an unlock here proves the S1-T2 wiring,
/// not just the S0 engine.
final class TrophyTrackDailyWiringTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TrophyTrackDailyWiringTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Fresh GameState on the isolated suite. Its first-launch backfill runs
    /// over an empty save (grants nothing, marks itself done), so every
    /// unlock below comes from the live funnel call, not the grandfather.
    private func makeGameState() -> GameState {
        TrophyTestHarness.makeGameState(defaults: defaults)
    }

    /// `count` distinct "YYYY-MM-DD" completion keys, `strideDays` apart
    /// (stride 1 = consecutive calendar dates; larger = deliberately
    /// non-consecutive so a clears-COUNT test never trips the streak trophy).
    /// Anchored in 2020 so no key can collide with `DailyChallenge.key()`
    /// (today), which `completeTodaysDailyChallenge` inserts.
    private func dateKeys(_ count: Int, strideDays: Int) -> Set<String> {
        let cal = Calendar.current
        let base = cal.date(from: DateComponents(year: 2020, month: 1, day: 1))!
        return Set((0..<count).map { i in
            DailyChallenge.key(cal.date(byAdding: .day, value: i * strideDays, to: base)!)
        })
    }

    private func yesterday() -> Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    }

    // MARK: Challenge Tracks

    /// `track_best_progress` climbs through `advanceTrackProgress`:
    /// track_first_level (≥1) then track_halfway (≥50); a completion (100)
    /// also latches track_first_complete via `tracks_completed`.
    func testTrackProgressTrophiesWireThroughAdvance() {
        let gs = makeGameState()
        XCTAssertFalse(gs.trophyEngine.isUnlocked("track_first_level"))

        gs.advanceTrackProgress(trackID: "alpha", to: 1)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("track_first_level"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("track_halfway"))

        gs.advanceTrackProgress(trackID: "alpha", to: 50)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("track_halfway"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("track_first_complete"))

        gs.advanceTrackProgress(trackID: "alpha", to: 100)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("track_first_complete"))
    }

    /// `tracks_completed` count latches track_triple (3) and track_all_eight
    /// (8) through distinct-track completions; the Golden Gauntlet completion
    /// latches track_gauntlet via `golden_gauntlet_completed`.
    func testTrackCompletionCountAndGauntletWireThroughAdvance() {
        let gs = makeGameState()

        for i in 1...3 { gs.advanceTrackProgress(trackID: "t\(i)", to: 100) }
        XCTAssertTrue(gs.trophyEngine.isUnlocked("track_first_complete"))
        XCTAssertTrue(gs.trophyEngine.isUnlocked("track_triple"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("track_all_eight"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("track_gauntlet"))

        for i in 4...8 { gs.advanceTrackProgress(trackID: "t\(i)", to: 100) }
        XCTAssertTrue(gs.trophyEngine.isUnlocked("track_all_eight"))

        gs.advanceTrackProgress(trackID: "golden-gauntlet", to: 100)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("track_gauntlet"))
    }

    // MARK: Challenge of the Day

    /// `daily_first_start` is a NEW go-forward metric: starting a daily marks
    /// the "daily" mode played (§6 item 18) and latches the trophy.
    func testDailyFirstStartWiresThroughStartDailyChallenge() {
        let gs = makeGameState()
        XCTAssertFalse(gs.playedModeIDs.contains("daily"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("daily_first_start"))

        gs.startDailyChallenge()

        XCTAssertTrue(gs.playedModeIDs.contains("daily"))
        XCTAssertTrue(gs.trophyEngine.isUnlocked("daily_first_start"))
    }

    /// `daily_clears` count latches daily_first_clear (≥1), daily_clears_10
    /// (≥10) and daily_clears_50 (≥50) through `completeTodaysDailyChallenge`.
    /// The set is seeded with non-consecutive historical keys so the clears
    /// COUNT is what fires — never the streak trophy.
    func testDailyClearsWireThroughCompleteFunnel() {
        let gs = makeGameState()

        // 9 prior non-consecutive clears + today's = 10.
        gs.dailyChallengeCompletions = dateKeys(9, strideDays: 10)
        gs.completeTodaysDailyChallenge()
        XCTAssertTrue(gs.trophyEngine.isUnlocked("daily_first_clear"))
        XCTAssertTrue(gs.trophyEngine.isUnlocked("daily_clears_10"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("daily_clears_50"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("daily_week_streak"),
                       "non-consecutive keys must not trip the streak trophy")

        // Reseed to 49 prior + today's = 50.
        gs.dailyChallengeCompletions = dateKeys(49, strideDays: 10)
        gs.completeTodaysDailyChallenge()
        XCTAssertTrue(gs.trophyEngine.isUnlocked("daily_clears_50"))
    }

    /// `daily_clear_streak_best` (the consecutive-date derivation) latches
    /// daily_week_streak (≥7) through the same completion funnel: 7
    /// consecutive historical clears, revealed on the next completion.
    func testDailyWeekStreakWiresThroughCompleteFunnel() {
        let gs = makeGameState()
        gs.dailyChallengeCompletions = dateKeys(7, strideDays: 1)   // 7 consecutive
        XCTAssertFalse(gs.trophyEngine.isUnlocked("daily_week_streak"))

        gs.completeTodaysDailyChallenge()   // fires the derivation over the set
        XCTAssertTrue(gs.trophyEngine.isUnlocked("daily_week_streak"))
    }

    // MARK: Daily login reward

    /// The reward-streak high-water latches daily_login_7 (≥7) via
    /// `claimDailyReward`: a streak of 6 claimed yesterday advances to 7.
    func testDailyLogin7WiresThroughClaim() {
        let gs = makeGameState()
        gs.dailyStreak = 6
        gs.lastDailyClaim = yesterday()      // streak intact, claim available
        XCTAssertFalse(gs.trophyEngine.isUnlocked("daily_login_7"))

        let granted = gs.claimDailyReward()
        XCTAssertNotNil(granted, "the claim must actually land")
        XCTAssertEqual(gs.dailyStreak, 7)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("daily_login_7"))
    }

    /// Repeated claims drive both counter-based reward trophies through the
    /// real funnel: 30 claims latch econ_punch_card (claims ≥30) and, since
    /// the streak climbs in lockstep, daily_login_7 and daily_login_30.
    func testRewardClaimCountAndLongStreakWireThroughRepeatedClaims() {
        let gs = makeGameState()
        for _ in 0..<30 {
            gs.lastDailyClaim = yesterday()   // keep the streak alive + claim open
            _ = gs.claimDailyReward()
        }
        XCTAssertEqual(gs.dailyStreak, 30)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("econ_punch_card"))
        XCTAssertTrue(gs.trophyEngine.isUnlocked("daily_login_7"))
        XCTAssertTrue(gs.trophyEngine.isUnlocked("daily_login_30"))
    }
}

// MARK: - S1-T7 — View-layer event trigger wiring

/// End-to-end wiring for the four view-only event trophies: the two
/// run-lifecycle Skill trophies driven through `recordResult`'s new run flags,
/// and the two secret whimsies driven through the dedicated fall / Coin-Pit
/// stake funnels. (`whimsy_roll_call` is deliberately absent — it is blocked
/// on the unbuilt pinball ROLL lanes and carved out of S1-T7/S1-T9.)
final class TrophyViewEventWiringTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TrophyViewEventWiringTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Fresh GameState on the isolated suite — default mode is the main climb
    /// (`recordsClimbResult == true`), the gate every run-lifecycle / fall
    /// trophy rides (the S1-T1 climb tests rely on the same default).
    private func makeGameState() -> GameState {
        TrophyTestHarness.makeGameState(defaults: defaults)
    }

    // MARK: Skill run-lifecycle (via recordResult)

    /// `skill_first_try`: 3 stars, the level's first-ever attempt (no prior
    /// clear — a fresh level has no `bestTime`), and a clean run (no fall/
    /// restart before the goal). Only all three together qualify.
    func testFirstTryAceWiresThroughRecordResult() {
        let gs = makeGameState()
        XCTAssertFalse(gs.trophyEngine.isUnlocked("skill_first_try"))

        // 3 stars but NOT flagged clean → no unlock.
        gs.recordResult(level: 4, stars: 3, time: 20, coinIndices: [],
                        firstAttemptClean: false, pickupsThisRun: 0)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("skill_first_try"))

        // 3 stars, first attempt, clean → unlock.
        gs.recordResult(level: 7, stars: 3, time: 18, coinIndices: [],
                        firstAttemptClean: true, pickupsThisRun: 0)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("skill_first_try"))
    }

    /// A clean first attempt at only 2 stars must NOT latch skill_first_try.
    func testFirstTryAceRequiresThreeStars() {
        let gs = makeGameState()
        gs.recordResult(level: 3, stars: 2, time: 25, coinIndices: [],
                        firstAttemptClean: true, pickupsThisRun: 0)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("skill_first_try"))
    }

    /// `skill_spotless`: 3 stars AND all three pickup coins banked in one run;
    /// a partial haul (2 of 3) never qualifies.
    func testSpotlessRunWiresThroughRecordResult() {
        let gs = makeGameState()

        // 3 stars but only 2 of 3 coins → no unlock.
        gs.recordResult(level: 5, stars: 3, time: 22, coinIndices: [0, 1],
                        firstAttemptClean: false, pickupsThisRun: 2)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("skill_spotless"))

        // 3 stars + all 3 coins → unlock.
        gs.recordResult(level: 6, stars: 3, time: 21, coinIndices: [0, 1, 2],
                        firstAttemptClean: false, pickupsThisRun: 3)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("skill_spotless"))
    }

    // MARK: Secret whimsies (via dedicated funnels)

    /// `whimsy_gravity_check` (secret): a pit-fall on climb LEVEL 1 latches it
    /// through the dedicated fall funnel — and, per the acceptance criterion,
    /// falling never consumes a life (tutorial L1 is lives-exempt; the funnel
    /// touches no life state).
    func testGravityCheckWiresThroughClimbFallWithoutConsumingALife() {
        let gs = makeGameState()
        let livesBefore = gs.lives
        XCTAssertFalse(gs.trophyEngine.isUnlocked("whimsy_gravity_check"))

        // A fall on level 2 is not the gravity-check level.
        gs.recordClimbFall(level: 2)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("whimsy_gravity_check"))

        gs.recordClimbFall(level: 1)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("whimsy_gravity_check"))
        XCTAssertEqual(gs.lives, livesBefore, "the fall funnel must never consume a life")
    }

    /// `whimsy_high_roller` (secret): staking ≥5 time-tickets on a single Coin
    /// Pit round latches it; a 4-ticket stake does not.
    func testHighRollerWiresThroughCoinPitStake() {
        let gs = makeGameState()
        XCTAssertFalse(gs.trophyEngine.isUnlocked("whimsy_high_roller"))

        gs.recordCoinPitRoundStaked(tickets: 4)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("whimsy_high_roller"))

        gs.recordCoinPitRoundStaked(tickets: 5)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("whimsy_high_roller"))
    }
}

// MARK: - TrophySocialWiringTests (S1-T6 acceptance)

/// End-to-end wiring proof for the 7 Social trophy triggers (S1-T6). Drives
/// the PUBLIC GameState social funnels — `recordSocialSignIn`,
/// `recordFriendAccepted(peak:)`, `recordLifeSent`, `recordClanJoined`,
/// `recordClanRequestFulfilled` — directly on a fresh test GameState (a live
/// `SocialClient` is deliberately NOT needed: the funnels ARE the decision
/// point, the views only call them on a successful `SocialClient` return).
///
/// Each GameState is fresh on an isolated UserDefaults suite; its first-launch
/// backfill runs over an empty save and grandfathers NOTHING social (all
/// `socialAction` metrics are omitted from `TrophyBackfill.snapshot`), so
/// every unlock below is proof the LIVE funnel fired.
final class TrophySocialWiringTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TrophySocialWiringTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeGameState() -> GameState {
        TrophyTestHarness.makeGameState(defaults: defaults)
    }

    // MARK: Sign-in

    /// `social_sign_in`: a pure latch on the first active Apple session.
    func testSignInWiresThroughFunnel() {
        let gs = makeGameState()
        XCTAssertFalse(gs.trophyEngine.isUnlocked("social_sign_in"))

        gs.recordSocialSignIn()
        XCTAssertTrue(gs.trophyEngine.isUnlocked("social_sign_in"))
    }

    // MARK: Friends — accepted-friend high-water

    /// `social_first_friend` (≥1) then `social_friends_5` (≥5) latch as the
    /// accepted-friend count climbs through the funnel.
    func testFriendMilestonesWireThroughAcceptedPeak() {
        let gs = makeGameState()
        XCTAssertFalse(gs.trophyEngine.isUnlocked("social_first_friend"))

        gs.recordFriendAccepted(peak: 1)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("social_first_friend"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("social_friends_5"))

        gs.recordFriendAccepted(peak: 4)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("social_friends_5"))

        gs.recordFriendAccepted(peak: 5)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("social_friends_5"))
    }

    /// The accepted-friend high-water LATCHES: once 5 is observed, dropping
    /// back to 3 (a friend removed) must never revoke `social_friends_5`, and
    /// a later smaller value must never lower what's unlocked.
    func testFriendsPeakLatchesAndNeverRevokes() {
        let gs = makeGameState()

        gs.recordFriendAccepted(peak: 5)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("social_first_friend"))
        XCTAssertTrue(gs.trophyEngine.isUnlocked("social_friends_5"))

        // Two friends removed → live count 3, but the ratchet holds.
        gs.recordFriendAccepted(peak: 3)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("social_friends_5"),
                      "high-water latch must never revoke on a regression")

        // Even a drop to zero keeps both unlocked.
        gs.recordFriendAccepted(peak: 0)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("social_first_friend"))
        XCTAssertTrue(gs.trophyEngine.isUnlocked("social_friends_5"))
    }

    // MARK: Lives sent (friend gifts + clan fulfillments)

    /// `social_send_life` (≥1) latches on the first gift; `social_lives_sent_25`
    /// (≥25) latches on the 25th. The counter is lifetime and persisted.
    func testLivesSentMilestonesWireThroughRepeatedSends() {
        let gs = makeGameState()
        XCTAssertFalse(gs.trophyEngine.isUnlocked("social_send_life"))

        gs.recordLifeSent()
        XCTAssertTrue(gs.trophyEngine.isUnlocked("social_send_life"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("social_lives_sent_25"))
        XCTAssertEqual(gs.trophyStats.livesSent, 1)

        for _ in 2...24 { gs.recordLifeSent() }
        XCTAssertFalse(gs.trophyEngine.isUnlocked("social_lives_sent_25"))
        XCTAssertEqual(gs.trophyStats.livesSent, 24)

        gs.recordLifeSent()   // 25th
        XCTAssertTrue(gs.trophyEngine.isUnlocked("social_lives_sent_25"))
        XCTAssertEqual(gs.trophyStats.livesSent, 25)
    }

    /// The lives-sent counter persists across a relaunch (a fresh GameState on
    /// the same defaults reloads it), so the 25-gift trophy can accrue over
    /// many sessions.
    func testLivesSentCounterPersistsAcrossRelaunch() {
        let gs = makeGameState()
        for _ in 1...24 { gs.recordLifeSent() }
        XCTAssertEqual(gs.trophyStats.livesSent, 24)

        let relaunched = makeGameState()
        XCTAssertEqual(relaunched.trophyStats.livesSent, 24, "counter must survive relaunch")
        relaunched.recordLifeSent()   // 25th, across the session boundary
        XCTAssertTrue(relaunched.trophyEngine.isUnlocked("social_lives_sent_25"))
    }

    // MARK: Clans

    /// `clan_join`: a pure latch on joining OR creating a clan.
    func testClanJoinWiresThroughFunnel() {
        let gs = makeGameState()
        XCTAssertFalse(gs.trophyEngine.isUnlocked("clan_join"))

        gs.recordClanJoined()
        XCTAssertTrue(gs.trophyEngine.isUnlocked("clan_join"))
    }

    /// `clan_fulfill`: a single fulfilled clan life-request latches it.
    func testClanFulfillWiresThroughFunnel() {
        let gs = makeGameState()
        XCTAssertFalse(gs.trophyEngine.isUnlocked("clan_fulfill"))

        gs.recordClanRequestFulfilled()
        XCTAssertTrue(gs.trophyEngine.isUnlocked("clan_fulfill"))
        XCTAssertEqual(gs.trophyStats.clanRequestsFulfilled, 1)
    }

    /// A clan fulfillment is BOTH a life sent and a request fulfilled: the view
    /// calls `recordLifeSent()` on every clan gift and `recordClanRequestFulfilled()`
    /// additionally when the recipient was asking. This mirrors that call
    /// ordering and proves the two counters advance independently — the
    /// `social_lives_sent_25` counter includes clan fulfillments (per catalog).
    func testClanFulfillmentAlsoCountsTowardLivesSent() {
        let gs = makeGameState()

        // A gift to a NON-asking clanmate: life sent, no fulfillment.
        gs.recordLifeSent()
        XCTAssertEqual(gs.trophyStats.livesSent, 1)
        XCTAssertEqual(gs.trophyStats.clanRequestsFulfilled, 0)

        // A gift to an ASKING clanmate: both funnels fire (the view's order).
        gs.recordLifeSent()
        gs.recordClanRequestFulfilled()
        XCTAssertEqual(gs.trophyStats.livesSent, 2, "clan fulfillments count toward lives sent")
        XCTAssertEqual(gs.trophyStats.clanRequestsFulfilled, 1)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("clan_fulfill"))
        XCTAssertTrue(gs.trophyEngine.isUnlocked("social_send_life"))
    }

    // MARK: No population dependence

    /// No social trophy requires more than a single friend/clan action — one
    /// accept, one gift, one join, one fulfillment each unlock their bronze/
    /// first-tier trophy with no other player having to exist. (The higher
    /// tiers, 5 friends / 25 lives, are volume of the SAME single action, not
    /// a dependence on a populated graph.)
    func testFirstTierTrophiesNeedOnlyOneAction() {
        let gs = makeGameState()
        gs.recordSocialSignIn()
        gs.recordFriendAccepted(peak: 1)
        gs.recordLifeSent()
        gs.recordClanJoined()
        gs.recordClanRequestFulfilled()

        for id in ["social_sign_in", "social_first_friend", "social_send_life",
                   "clan_join", "clan_fulfill"] {
            XCTAssertTrue(gs.trophyEngine.isUnlocked(id), "\(id) should latch on one action")
        }
    }
}

// MARK: - TrophyMinigameWiringTests (S1-T3 acceptance)

/// End-to-end wiring proof for the minigame trophy triggers (S1-T3): drive
/// the PUBLIC GameState minigame funnels — `recordMinigameResult`,
/// `recordCompetitiveWin`, `recordPinballScore`, `recordGoldRushCoins`,
/// `recordRollUpRun`, `addZenSeconds`, `recordCompetitiveScore`,
/// `markModePlayed` — and assert the right trophies latch in the engine.
/// Each GameState is fresh on an isolated UserDefaults suite; its
/// first-launch backfill runs over an empty save (grants nothing), so every
/// unlock below is proof the LIVE funnel fired, not the grandfather.
///
/// Disco + Roll Out best-trophies (`rollout_first_maze`, `rollout_maze_10`,
/// `disco_cross_25`, `disco_hard_10`) are deliberately NOT covered here —
/// those two modes write `minigameBests` in-view and are rerouted through a
/// GameState funnel in S1-T4, which owns their trigger tests.
final class TrophyMinigameWiringTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TrophyMinigameWiringTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeGameState() -> GameState {
        TrophyTestHarness.makeGameState(defaults: defaults)
    }

    /// Win one competitive match through `recordMinigameResult` (the shipped
    /// view path), at the given difficulty. Score doubles as the stored-best
    /// unit for koth/paintball.
    @discardableResult
    private func win(_ gs: GameState,
                     _ mode: String,
                     difficulty: MinigameDifficulty = .normal,
                     score: Int = 1) -> Int {
        gs.recordMinigameResult(modeID: mode, difficulty: difficulty,
                                won: true, score: score, basePayout: 0)
    }

    // MARK: Arcade-wide — wins

    /// A single competitive win latches arcade_first_win and the per-mode
    /// first-win trophy, both riding `recordCompetitiveWin` (the ticket-earn
    /// choke point).
    func testFirstCompetitiveWinWiresArcadeAndPerGame() {
        let gs = makeGameState()
        XCTAssertFalse(gs.trophyEngine.isUnlocked("arcade_first_win"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("snake_first_win"))

        win(gs, "snake")

        XCTAssertTrue(gs.trophyEngine.isUnlocked("arcade_first_win"))
        XCTAssertTrue(gs.trophyEngine.isUnlocked("snake_first_win"))
    }

    /// `recordCompetitiveWin` called directly (no difficulty context) is still
    /// the ticket-earn choke point: it must latch the win trophies too.
    func testDirectRecordCompetitiveWinFiresTrophies() {
        let gs = makeGameState()
        gs.recordCompetitiveWin("sumo")
        XCTAssertTrue(gs.trophyEngine.isUnlocked("arcade_first_win"))
        XCTAssertTrue(gs.trophyEngine.isUnlocked("sumo_first_win"))
    }

    /// 10 lifetime wins in one mode latches its <mode>_wins_10 trophy; 9 do
    /// not (boundary).
    func testPerGameTenWinsBoundary() {
        let gs = makeGameState()
        for _ in 0..<9 { win(gs, "goldrush") }
        XCTAssertTrue(gs.trophyEngine.isUnlocked("goldrush_first_win"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("goldrush_wins_10"))

        win(gs, "goldrush")   // 10th
        XCTAssertTrue(gs.trophyEngine.isUnlocked("goldrush_wins_10"))
    }

    /// arcade_all_six needs one win in EACH of the 6 competitive modes; five
    /// modes must NOT satisfy it.
    func testArcadeAllSixNeedsEveryMode() {
        let gs = makeGameState()
        let modes = ["snake", "sumo", "paintball", "goldrush", "marblecup", "koth"]
        for m in modes.dropLast() { win(gs, m) }   // 5 of 6
        XCTAssertFalse(gs.trophyEngine.isUnlocked("arcade_all_six"))

        win(gs, modes.last!)                        // the 6th
        XCTAssertTrue(gs.trophyEngine.isUnlocked("arcade_all_six"))
    }

    /// arcade_wins_100 latches at 100 lifetime competitive wins summed across
    /// modes; 99 does not.
    func testArcadeHundredWinsBoundary() {
        let gs = makeGameState()
        for _ in 0..<99 { win(gs, "snake") }
        XCTAssertFalse(gs.trophyEngine.isUnlocked("arcade_wins_100"))
        win(gs, "sumo")   // 100th, different mode
        XCTAssertTrue(gs.trophyEngine.isUnlocked("arcade_wins_100"))
    }

    // MARK: Arcade-wide — Hard difficulty

    /// arcade_hard_once latches on the FIRST Hard win only; a Normal win of
    /// the same mode must not trip it.
    func testArcadeHardOnceRequiresHardDifficulty() {
        let gs = makeGameState()
        win(gs, "snake", difficulty: .normal)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("arcade_hard_once"),
                       "a Normal win must not satisfy the Hard trophy")

        win(gs, "snake", difficulty: .hard)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("arcade_hard_once"))
    }

    /// arcade_hard_all needs a Hard win in EACH of the 6 modes; five is not
    /// enough. Verifies the per-difficulty dict is read at the win choke
    /// point after `recordMinigameResult` bumps it.
    func testArcadeHardAllNeedsHardWinEveryMode() {
        let gs = makeGameState()
        let modes = ["snake", "sumo", "paintball", "goldrush", "marblecup", "koth"]
        for m in modes.dropLast() { win(gs, m, difficulty: .hard) }
        XCTAssertTrue(gs.trophyEngine.isUnlocked("arcade_hard_once"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("arcade_hard_all"))

        win(gs, modes.last!, difficulty: .hard)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("arcade_hard_all"))
    }

    // MARK: Per-game bests

    /// paintball_coverage_60 rides `minigameBests["paintball"]` (coverage %),
    /// written by `recordCompetitiveScore`. 59 % misses, 60 % latches.
    func testPaintballCoverageBestBoundary() {
        let gs = makeGameState()
        _ = gs.recordCompetitiveScore("paintball", 59)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("paintball_coverage_60"))
        _ = gs.recordCompetitiveScore("paintball", 60)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("paintball_coverage_60"))
    }

    /// koth_hold_45 rides `minigameBests["koth"]` (hold-seconds). 44 misses,
    /// 45 latches. A losing round still records the best (skill without a win).
    func testKothHoldBestBoundary() {
        let gs = makeGameState()
        _ = gs.recordCompetitiveScore("koth", 44)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("koth_hold_45"))
        _ = gs.recordCompetitiveScore("koth", 45)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("koth_hold_45"))
    }

    /// The full koth win path (`recordMinigameResult` with score = holdSec)
    /// does NOT itself write the best — the view calls `recordCompetitiveScore`
    /// for that — so a bare win under 45 s must not latch koth_hold_45, only
    /// koth_first_win.
    func testKothWinAloneDoesNotGrantHoldTrophy() {
        let gs = makeGameState()
        win(gs, "koth", score: 10)   // a short winning round
        XCTAssertTrue(gs.trophyEngine.isUnlocked("koth_first_win"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("koth_hold_45"))
    }

    /// pinball_score_10k / _50k / _150k ride `pinballBest` through
    /// `recordPinballScore`, at their exact thresholds.
    func testPinballScoreTiers() {
        let gs = makeGameState()
        _ = gs.recordPinballScore(9_999)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("pinball_score_10k"))

        _ = gs.recordPinballScore(10_000)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("pinball_score_10k"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("pinball_score_50k"))

        _ = gs.recordPinballScore(50_000)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("pinball_score_50k"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("pinball_score_150k"))

        _ = gs.recordPinballScore(150_000)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("pinball_score_150k"))
    }

    /// A LATER lower pinball score never revokes a higher unlock (latched
    /// ratchet) and the tier already earned stays lit.
    func testPinballBestTrophyIsLatched() {
        let gs = makeGameState()
        _ = gs.recordPinballScore(150_000)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("pinball_score_150k"))
        _ = gs.recordPinballScore(1)   // a bad game later
        XCTAssertTrue(gs.trophyEngine.isUnlocked("pinball_score_150k"),
                      "a latched trophy must never revoke")
    }

    /// rollup_100m / rollup_500m ride `minigameBests["rollup"]` (height, m)
    /// through `recordRollUpRun`, at their thresholds.
    func testRollUpHeightTiers() {
        let gs = makeGameState()
        _ = gs.recordRollUpRun(height: 99, seconds: 30)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("rollup_100m"))

        _ = gs.recordRollUpRun(height: 100, seconds: 40)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("rollup_100m"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("rollup_500m"))

        _ = gs.recordRollUpRun(height: 500, seconds: 90)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("rollup_500m"))
    }

    // MARK: Zen

    /// zen_hour (≥3,600 s) / zen_10_hours (≥36,000 s) accumulate through
    /// `addZenSeconds`. Below an hour: nothing.
    func testZenTimeTiers() {
        let gs = makeGameState()
        gs.addZenSeconds(3_599)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("zen_hour"))

        gs.addZenSeconds(1)   // now 3,600
        XCTAssertTrue(gs.trophyEngine.isUnlocked("zen_hour"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("zen_10_hours"))

        gs.addZenSeconds(36_000 - 3_600)   // now 36,000
        XCTAssertTrue(gs.trophyEngine.isUnlocked("zen_10_hours"))
    }

    // MARK: Coin Pit (goldrushBest / goldrushCoinsTotal — the naming trap)

    /// coinpit_first_round rides the played-mode set through `markModePlayed`.
    func testCoinPitFirstRoundWiresThroughMarkModePlayed() {
        let gs = makeGameState()
        XCTAssertFalse(gs.trophyEngine.isUnlocked("coinpit_first_round"))
        gs.markModePlayed("coinpit")
        XCTAssertTrue(gs.trophyEngine.isUnlocked("coinpit_first_round"))
    }

    /// coinpit_catch_90 rides `goldrushBest` (best single Coin Pit haul) and
    /// econ_pit_boss rides `goldrushCoinsTotal` (lifetime Coin Pit coins) —
    /// both through `recordGoldRushCoins`, NOT the "goldrush" competitive mode.
    func testCoinPitCatchAndLifetimeWireThroughGoldRushCoins() {
        let gs = makeGameState()
        _ = gs.recordGoldRushCoins(89)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("coinpit_catch_90"))

        _ = gs.recordGoldRushCoins(90)     // a 90-coin round: best now 90
        XCTAssertTrue(gs.trophyEngine.isUnlocked("coinpit_catch_90"))

        // Grind the lifetime total to 2,500 for econ_pit_boss (89+90 = 179
        // so far; add 2,321 more across rounds).
        XCTAssertFalse(gs.trophyEngine.isUnlocked("econ_pit_boss"))
        _ = gs.recordGoldRushCoins(2_500 - 179)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("econ_pit_boss"))
    }

    /// Coin Pit reward-run stats must NOT be confused with the "goldrush"
    /// (Smash and Grab) competitive mode: winning goldrush grants goldrush
    /// win trophies but never the Coin Pit best/lifetime trophies, and a Coin
    /// Pit haul never grants goldrush win trophies.
    func testCoinPitAndGoldrushModeAreDisjoint() {
        let gs = makeGameState()
        _ = gs.recordGoldRushCoins(120)               // a Coin Pit round
        XCTAssertTrue(gs.trophyEngine.isUnlocked("coinpit_catch_90"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("goldrush_first_win"),
                       "a Coin Pit haul must not grant a Smash and Grab win trophy")

        win(gs, "goldrush")                           // a Smash and Grab win
        XCTAssertTrue(gs.trophyEngine.isUnlocked("goldrush_first_win"))
    }

    // MARK: Discovery (played-mode set)

    /// arcade_sampler (5 distinct minigames) / arcade_grand_tour (all 12)
    /// accumulate through `markModePlayed`.
    func testArcadeDiscoveryTiers() {
        let gs = makeGameState()
        let all = ["zen", "coinpit", "snake", "sumo", "paintball", "goldrush",
                   "marblecup", "koth", "pinball", "rollout", "rollup", "disco"]
        for m in all.prefix(4) { gs.markModePlayed(m) }
        XCTAssertFalse(gs.trophyEngine.isUnlocked("arcade_sampler"))

        gs.markModePlayed(all[4])   // 5th distinct minigame
        XCTAssertTrue(gs.trophyEngine.isUnlocked("arcade_sampler"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("arcade_grand_tour"))

        for m in all.dropFirst(5) { gs.markModePlayed(m) }   // all 12
        XCTAssertTrue(gs.trophyEngine.isUnlocked("arcade_grand_tour"))
    }

    /// Playing a non-minigame mode id (or re-playing one already counted) does
    /// not inflate `minigames_played` — the derivation intersects with the 12
    /// minigame ids and the set dedupes.
    func testNonMinigameAndRepeatPlaysDoNotInflateDiscovery() {
        let gs = makeGameState()
        gs.markModePlayed("climb")            // not a minigame id
        gs.markModePlayed("snake")
        gs.markModePlayed("snake")            // repeat
        gs.markModePlayed("challenge.alpha")  // not one of the 12
        XCTAssertFalse(gs.trophyEngine.isUnlocked("arcade_sampler"),
                       "only 1 distinct minigame played — must not reach 5")
    }
}

// MARK: - TrophyDiscoRollOutWiringTests (S1-T4)
//
// Disco Ball and Roll Out formerly wrote `minigameBests` directly in-view.
// S1-T4 reroutes both writes through GameState funnels (`recordDiscoResult` /
// `recordRollOutResult`) so the record, the shared new-best bonus, and the
// Disco/Roll Out trophies all live at one choke point.  These tests drive the
// PUBLIC funnels and assert (1) bests + the new-best bonus behave identically
// to the old in-view logic, (2) the Disco/Roll Out trophies fire from the
// funnels, and (3) the live funnel and `TrophyBackfill.snapshot` agree.
final class TrophyDiscoRollOutWiringTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TrophyDiscoRollOutWiringTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeGameState() -> GameState {
        TrophyTestHarness.makeGameState(defaults: defaults)
    }

    // MARK: Regression — bests behave identically pre/post reroute

    /// A new Disco best writes the difficulty-scoped slot and pays exactly the
    /// shared new-best bonus (matching the old in-view `wasBest` branch); the
    /// funnel returns true.  A fresh GameState starts at 0 coins, so the only
    /// coin movement the funnel owns is the 100-coin bonus (the per-crossing
    /// payout stays in the view).
    func testDiscoNewBestWritesSlotAndPaysBonus() {
        let gs = makeGameState()
        XCTAssertEqual(gs.coinBalance, 0)

        let isBest = gs.recordDiscoResult(bestKey: "disco", crossings: 30)

        XCTAssertTrue(isBest)
        XCTAssertEqual(gs.minigameBests["disco", default: 0], 30)
        XCTAssertEqual(gs.coinBalance, GameState.minigameBestBonus,
                       "a new best pays exactly the shared bonus")
    }

    /// A later, lower Disco run is NOT a best: the slot is unchanged, no bonus
    /// is paid, and the funnel returns false — identical to the old in-view
    /// `crossings > best` guard.
    func testDiscoLowerRunDoesNotRegressBestOrPayBonus() {
        let gs = makeGameState()
        _ = gs.recordDiscoResult(bestKey: "disco", crossings: 30)
        let balanceAfterBest = gs.coinBalance

        let isBest = gs.recordDiscoResult(bestKey: "disco", crossings: 12)

        XCTAssertFalse(isBest)
        XCTAssertEqual(gs.minigameBests["disco", default: 0], 30,
                       "a worse run must never lower the stored best")
        XCTAssertEqual(gs.coinBalance, balanceAfterBest,
                       "no new best → no bonus")
    }

    /// Each Disco difficulty writes its OWN slot; the three keys are
    /// independent (the view passes the difficulty-scoped bestKey).
    func testDiscoDifficultySlotsAreIndependent() {
        let gs = makeGameState()
        _ = gs.recordDiscoResult(bestKey: "discoeasy", crossings: 8)
        _ = gs.recordDiscoResult(bestKey: "disco",     crossings: 15)
        _ = gs.recordDiscoResult(bestKey: "discohard", crossings: 5)

        XCTAssertEqual(gs.minigameBests["discoeasy", default: 0], 8)
        XCTAssertEqual(gs.minigameBests["disco", default: 0], 15)
        XCTAssertEqual(gs.minigameBests["discohard", default: 0], 5)
    }

    /// A zero-crossing Disco run records nothing and pays nothing (the old
    /// in-view path only wrote/paid when `crossings > 0`).
    func testDiscoZeroCrossingsIsNoOp() {
        let gs = makeGameState()
        let isBest = gs.recordDiscoResult(bestKey: "disco", crossings: 0)
        XCTAssertFalse(isBest)
        XCTAssertNil(gs.minigameBests["disco"])
        XCTAssertEqual(gs.coinBalance, 0)
    }

    /// A new Roll Out best (furthest maze reached, 1-based) writes the
    /// `"rollout"` slot and pays the shared new-best bonus; the funnel returns
    /// true.
    func testRollOutNewBestWritesSlotAndPaysBonus() {
        let gs = makeGameState()
        XCTAssertEqual(gs.coinBalance, 0)

        let isBest = gs.recordRollOutResult(reached: 3)

        XCTAssertTrue(isBest)
        XCTAssertEqual(gs.minigameBests["rollout", default: 0], 3)
        XCTAssertEqual(gs.coinBalance, GameState.minigameBestBonus)
    }

    /// A later, lower Roll Out clear is not a best: slot unchanged, no bonus,
    /// returns false.
    func testRollOutLowerClearDoesNotRegressBestOrPayBonus() {
        let gs = makeGameState()
        _ = gs.recordRollOutResult(reached: 6)
        let balanceAfterBest = gs.coinBalance

        let isBest = gs.recordRollOutResult(reached: 2)

        XCTAssertFalse(isBest)
        XCTAssertEqual(gs.minigameBests["rollout", default: 0], 6)
        XCTAssertEqual(gs.coinBalance, balanceAfterBest)
    }

    // MARK: Disco trophies fire from the funnel

    /// disco_cross_25 rides the MAX over the three difficulty keys: 24 misses,
    /// 25 (on any difficulty) latches.
    func testDiscoCross25Boundary() {
        let gs = makeGameState()
        _ = gs.recordDiscoResult(bestKey: "disco", crossings: 24)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("disco_cross_25"))

        _ = gs.recordDiscoResult(bestKey: "disco", crossings: 25)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("disco_cross_25"))
    }

    /// disco_cross_25 is the MAX across difficulties: 25 crossings on EASY
    /// satisfies it even though the Normal/Hard slots are lower (mirrors the
    /// backfill's max derivation).
    func testDiscoCross25TakesMaxAcrossDifficulties() {
        let gs = makeGameState()
        _ = gs.recordDiscoResult(bestKey: "disco",     crossings: 10)
        _ = gs.recordDiscoResult(bestKey: "discohard", crossings: 4)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("disco_cross_25"))

        _ = gs.recordDiscoResult(bestKey: "discoeasy", crossings: 25)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("disco_cross_25"),
                      "25 crossings on any single difficulty must satisfy the any-difficulty trophy")
    }

    /// disco_hard_10 rides the "discohard" slot ONLY: 25 crossings on Normal
    /// must not trip it; 10 on Hard latches.
    func testDiscoHard10IsHardSlotOnly() {
        let gs = makeGameState()
        _ = gs.recordDiscoResult(bestKey: "disco", crossings: 25)   // Normal, well past 10
        XCTAssertFalse(gs.trophyEngine.isUnlocked("disco_hard_10"),
                       "a Normal run must never satisfy the Hard-only trophy")

        _ = gs.recordDiscoResult(bestKey: "discohard", crossings: 9)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("disco_hard_10"))
        _ = gs.recordDiscoResult(bestKey: "discohard", crossings: 10)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("disco_hard_10"))
    }

    /// A latched Disco trophy is never revoked by a later, worse run.
    func testDiscoTrophyIsLatched() {
        let gs = makeGameState()
        _ = gs.recordDiscoResult(bestKey: "discohard", crossings: 12)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("disco_hard_10"))
        _ = gs.recordDiscoResult(bestKey: "discohard", crossings: 1)   // a bad run later
        XCTAssertTrue(gs.trophyEngine.isUnlocked("disco_hard_10"),
                      "a latched trophy must never revoke")
    }

    // MARK: Roll Out trophies fire from the funnel

    /// rollout_first_maze (≥1) latches on the first cleared maze; rollout_maze_10
    /// (≥10) at maze 10 and not maze 9.
    func testRollOutMazeTiers() {
        let gs = makeGameState()
        XCTAssertFalse(gs.trophyEngine.isUnlocked("rollout_first_maze"))

        _ = gs.recordRollOutResult(reached: 1)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("rollout_first_maze"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("rollout_maze_10"))

        _ = gs.recordRollOutResult(reached: 9)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("rollout_maze_10"))
        _ = gs.recordRollOutResult(reached: 10)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("rollout_maze_10"))
    }

    /// A latched Roll Out trophy is never revoked by a later, worse clear.
    func testRollOutTrophyIsLatched() {
        let gs = makeGameState()
        _ = gs.recordRollOutResult(reached: 10)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("rollout_maze_10"))
        _ = gs.recordRollOutResult(reached: 1)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("rollout_maze_10"),
                      "a latched trophy must never revoke")
    }

    // MARK: Disco and Roll Out are disjoint

    /// A Disco run never touches Roll Out trophies and vice versa.
    func testDiscoAndRollOutAreDisjoint() {
        let gs = makeGameState()
        _ = gs.recordDiscoResult(bestKey: "disco", crossings: 25)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("disco_cross_25"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("rollout_first_maze"),
                       "a Disco run must not grant a Roll Out trophy")

        _ = gs.recordRollOutResult(reached: 1)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("rollout_first_maze"))
    }

    // MARK: Live funnel ≡ backfill snapshot

    /// The live funnels must derive the SAME metric values `TrophyBackfill`
    /// derives from the stored bests, so a save built by playing agrees with a
    /// save that is grandfathered in.  Drive the funnels, then backfill a fresh
    /// engine from the same GameState and assert identical unlock sets for the
    /// four S1-T4 trophies.
    func testLiveFunnelAgreesWithBackfill() throws {
        let gs = makeGameState()
        _ = gs.recordDiscoResult(bestKey: "discoeasy", crossings: 25)   // disco_cross_25 via max
        _ = gs.recordDiscoResult(bestKey: "discohard", crossings: 10)   // disco_hard_10
        _ = gs.recordRollOutResult(reached: 10)                          // rollout_first_maze + _maze_10

        let live = gs.trophyEngine.unlockedIDs
        for id in ["disco_cross_25", "disco_hard_10",
                   "rollout_first_maze", "rollout_maze_10"] {
            XCTAssertTrue(live.contains(id), "live funnel should unlock \(id)")
        }

        // Backfill a fresh engine from the SAME stored bests.
        let backfilled = TrophyBackfill.snapshot(from: gs)
        let engine = TrophyEngine(catalog: try TrophyCatalog.load(bundle: .main),
                                  defaults: UserDefaults(suiteName: suiteName + ".backfill")!)
        for metric in TrophyMetric.allCases {
            if let value = backfilled[metric] { _ = engine.record(metric, value: value) }
        }
        for id in ["disco_cross_25", "disco_hard_10",
                   "rollout_first_maze", "rollout_maze_10"] {
            XCTAssertTrue(engine.isUnlocked(id),
                          "backfill should also unlock \(id) — live and backfill must agree")
        }
    }
}

// MARK: - TrophyCosmeticEconomyWiringTests (S1-T5 acceptance)

/// End-to-end wiring proof for the cosmetic + economy trophy triggers
/// (S1-T5): drive the PUBLIC GameState funnels — `grant`, `purchase`,
/// `purchaseBundle`, `purchasePack`, `addCoins`, and the equip setters — and
/// assert the right trophies latch on `gs.trophyEngine`.  The load-bearing
/// claims: the 4 IAP secrets are excluded from every collection criterion;
/// the earned Trophy ball / coin-buyable Aurora / free starters DO count;
/// `collection_complete` uses the 207-item evergreen denominator; no trophy
/// keys to a purchase/IAP count.
final class TrophyCosmeticEconomyWiringTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TrophyCosmeticEconomyWiringTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Fresh GameState on the isolated suite. Its first-launch backfill runs
    /// over an empty save (grants nothing, marks itself done), so every
    /// unlock below comes from the live funnel, not the grandfather.
    private func makeGameState() -> GameState {
        TrophyTestHarness.makeGameState(defaults: defaults)
    }

    // MARK: - Exclusion constant (the base pay-gate guard)

    /// The dedicated trophy exclusion constant is EXACTLY the 4 IAP secrets —
    /// {Diamond ball, Money Ball, Money Roll, Money Full} — by rawValue. This
    /// is the single guard that keeps every collection criterion from becoming
    /// a ~$150 pay-gate; pin it hard so no future edit widens or narrows it.
    func testIAPSecretExclusionConstantIsExactlyTheFourSecrets() {
        XCTAssertEqual(
            TrophyCosmeticExclusions.iapSecretRawValues,
            Set([BallSkin.diamond.rawValue, BallSkin.moneyBall.rawValue,
                 TrailColor.moneyRoll.rawValue, Floor.moneyFull.rawValue]),
            "the exclusion constant must be exactly the 4 IAP secrets")
        XCTAssertEqual(TrophyCosmeticExclusions.iapSecretRawValues.count, 4)
        // It must NOT be the iconic set (which also carries Trophy + starters).
        XCTAssertFalse(TrophyCosmeticExclusions.iapSecretBalls.contains(.trophy),
                       "Trophy ball is earned, not an IAP secret — must NOT be excluded")
    }

    /// The seasonal exclusion is exactly the 7 `isBundleExclusive` seasonal
    /// balls — and NOT Pluto/Trophy (also `isBundleExclusive` but evergreen).
    func testSeasonalExclusionConstantIsExactlyTheSevenSeasonalBalls() {
        XCTAssertEqual(
            TrophyCosmeticExclusions.seasonalExclusiveBalls,
            Set([.beachBall, .pumpkin, .ornament, .heartstone,
                 .shamrock, .confetti, .speckledEgg]))
        XCTAssertEqual(TrophyCosmeticExclusions.seasonalExclusiveBalls.count, 7)
        XCTAssertFalse(TrophyCosmeticExclusions.seasonalExclusiveBalls.contains(.pluto),
                       "Pluto is bundle-exclusive but evergreen — must NOT be excluded")
        XCTAssertFalse(TrophyCosmeticExclusions.seasonalExclusiveBalls.contains(.trophy))
    }

    // MARK: - cosmetic_first_buy (coin spend only)

    /// `cosmetic_first_buy` fires on the first COIN purchase — and only a coin
    /// spend, never a free `grant` (tutorial gift, track reward, IAP unlock).
    func testCosmeticFirstBuyFiresOnCoinPurchaseNotFreeGrant() {
        let gs = makeGameState()
        XCTAssertFalse(gs.trophyEngine.isUnlocked("cosmetic_first_buy"))

        // A free grant must NOT trip it.
        gs.grant(BallSkin.blue)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("cosmetic_first_buy"),
                       "free grant is not a coin spend")

        // A real coin purchase does.
        gs.coinBalance = 100_000
        XCTAssertTrue(gs.purchase(BallSkin.green))
        XCTAssertTrue(gs.trophyEngine.isUnlocked("cosmetic_first_buy"))
    }

    /// A pack purchase also latches `cosmetic_first_buy` (a coin spend) and
    /// `pack_first` (owned pack count ≥ 1).
    func testPackPurchaseLatchesFirstBuyAndPackFirst() {
        let gs = makeGameState()
        gs.coinBalance = 100_000
        XCTAssertFalse(gs.trophyEngine.isUnlocked("pack_first"))

        let pack = BallPack.catalogue.first!
        XCTAssertTrue(gs.purchasePack(pack))
        XCTAssertTrue(gs.trophyEngine.isUnlocked("pack_first"))
        XCTAssertTrue(gs.trophyEngine.isUnlocked("cosmetic_first_buy"))
    }

    // MARK: - balls_own_* (IAP secrets excluded, seasonal + Trophy counted)

    /// `balls_own_10` latches at 10 owned non-secret ball skins granted through
    /// the choke point; owning the 2 IAP-secret balls neither helps nor hurts.
    func testBallsOwn10ExcludesIAPSecretsAndCountsRegularGrants() {
        let gs = makeGameState()

        // Grant the 2 IAP secrets first — they must not count.
        gs.grant(BallSkin.diamond)
        gs.grant(BallSkin.moneyBall)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("balls_own_10"),
                       "IAP secrets must not count toward balls_own")

        // 9 regular coin/skill-reachable balls → still locked.
        let regular: [BallSkin] = [.blue, .green, .purple, .rose, .coral,
                                   .mint, .slate, .lemon, .gold]
        regular.forEach { gs.grant($0) }
        XCTAssertFalse(gs.trophyEngine.isUnlocked("balls_own_10"))

        // The Trophy ball is earned-exclusive but DOES count → 10th ball.
        gs.grant(BallSkin.trophy)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("balls_own_10"),
                      "Trophy ball counts toward collection")
    }

    /// A seasonal ball (excluded only from `collection_complete`) DOES count
    /// toward `balls_own_*` / `items_own_50` per catalog §3.6.
    func testSeasonalBallCountsTowardBallsAndItemsOwn() {
        let gs = makeGameState()
        let before = gs.trophyBallsOwnedCount
        gs.grant(BallSkin.pumpkin)
        XCTAssertEqual(gs.trophyBallsOwnedCount, before + 1,
                       "a seasonal ball counts toward balls_own")
    }

    // MARK: - items_own_50

    /// `items_own_50` latches at 50 owned cosmetics across all 7 slots,
    /// IAP secrets excluded; wired through `grant`.
    func testItemsOwn50AcrossSlotsExcludesIAPSecrets() {
        let gs = makeGameState()
        // Grant the 4 IAP secrets — none may count.
        gs.grant(BallSkin.diamond); gs.grant(BallSkin.moneyBall)
        gs.grant(TrailColor.moneyRoll); gs.grant(Floor.moneyFull)

        // Grant 50 non-secret, non-starter items spread across slots.
        var granted = 0
        func fill<Item: CosmeticItem>(_ cases: [Item], _ secrets: Set<String>) {
            for item in cases where granted < 50
                && item.tier != .starter
                && item != Item.starter
                && !secrets.contains(item.rawValue) {
                gs.grant(item); granted += 1
            }
        }
        fill(Array(BallSkin.allCases),
             TrophyCosmeticExclusions.iapSecretRawValues)
        fill(Array(GoalSkin.allCases), [])
        fill(Array(TrailColor.allCases),
             TrophyCosmeticExclusions.iapSecretRawValues)
        fill(Array(Floor.allCases),
             TrophyCosmeticExclusions.iapSecretRawValues)
        fill(Array(Pit.allCases), [])
        fill(Array(Boundary.allCases), [])
        fill(Array(MusicTrack.allCases), [])

        XCTAssertEqual(granted, 50, "test should grant exactly 50 non-secret items")
        XCTAssertTrue(gs.trophyEngine.isUnlocked("items_own_50"))
    }

    // MARK: - collection_complete (207 evergreen denominator)

    /// Grant EVERY evergreen cosmetic (the 207-item set) and prove
    /// `collection_complete` latches — while owning Money/Diamond neither
    /// helps nor is required, and the 7 seasonal balls are NOT required.
    func testCollectionCompleteUsesEvergreenDenominatorAndExcludesSecretsAndSeasonal() {
        let gs = makeGameState()

        // Own the 4 IAP secrets + all 7 seasonal balls — none should be
        // needed, and they must not push the count past 207 either.
        gs.grant(BallSkin.diamond); gs.grant(BallSkin.moneyBall)
        gs.grant(TrailColor.moneyRoll); gs.grant(Floor.moneyFull)
        for b in TrophyCosmeticExclusions.seasonalExclusiveBalls { gs.grant(b) }

        // Not yet complete: evergreen items still missing.
        XCTAssertFalse(gs.trophyEngine.isUnlocked("collection_complete"))

        // Grant every EVERGREEN item (skip IAP secrets + seasonal balls;
        // starters are already implicitly owned).
        for b in BallSkin.allCases
        where !TrophyCosmeticExclusions.iapSecretBalls.contains(b)
            && !TrophyCosmeticExclusions.seasonalExclusiveBalls.contains(b) {
            gs.grant(b)
        }
        for g in GoalSkin.allCases { gs.grant(g) }
        for t in TrailColor.allCases
        where !TrophyCosmeticExclusions.iapSecretTrails.contains(t) { gs.grant(t) }
        for f in Floor.allCases
        where !TrophyCosmeticExclusions.iapSecretFloors.contains(f) { gs.grant(f) }
        for p in Pit.allCases { gs.grant(p) }
        for bnd in Boundary.allCases { gs.grant(bnd) }
        for m in MusicTrack.allCases { gs.grant(m) }

        XCTAssertEqual(gs.trophyEvergreenCosmeticsOwnedCount, 207,
                       "the evergreen denominator must be exactly 207")
        XCTAssertTrue(gs.trophyEngine.isUnlocked("collection_complete"),
                      "owning all 207 evergreen items completes the collection")
    }

    /// The evergreen count NEVER exceeds 207 even when every IAP secret and
    /// seasonal ball is also owned — proving they can't help/pad the metric.
    func testEvergreenCountCannotExceed207() {
        let gs = makeGameState()
        // Own literally everything the game defines.
        for b in BallSkin.allCases  { gs.grant(b) }
        for g in GoalSkin.allCases  { gs.grant(g) }
        for t in TrailColor.allCases { gs.grant(t) }
        for f in Floor.allCases     { gs.grant(f) }
        for p in Pit.allCases       { gs.grant(p) }
        for bnd in Boundary.allCases { gs.grant(bnd) }
        for m in MusicTrack.allCases { gs.grant(m) }
        XCTAssertEqual(gs.trophyEvergreenCosmeticsOwnedCount, 207,
                       "owning secrets + seasonal must not push evergreen past 207")
    }

    /// Coin-buyable Aurora counts toward evergreen (it is NOT iconic-excluded).
    func testAuroraCountsTowardEvergreen() {
        let gs = makeGameState()
        let before = gs.trophyEvergreenCosmeticsOwnedCount
        gs.grant(BallSkin.aurora)
        XCTAssertEqual(gs.trophyEvergreenCosmeticsOwnedCount, before + 1,
                       "Aurora is coin-reachable evergreen and must count")
    }

    // MARK: - bundle_first / bundle_5

    /// `bundle_first` (≥1) and `bundle_5` (≥5) latch off `completedBundleIDs`
    /// as bundles are bought as a unit through `purchaseBundle`.
    func testBundleCompletionTrophiesFireOnCompletedBundleIDs() {
        let gs = makeGameState()
        gs.coinBalance = 10_000_000
        XCTAssertFalse(gs.trophyEngine.isUnlocked("bundle_first"))

        let bundles = Array(CosmeticBundle.catalogue.prefix(5))
        XCTAssertGreaterThanOrEqual(bundles.count, 5, "need ≥5 bundles for this test")

        _ = gs.purchaseBundle(bundles[0], price: bundles[0].proratedPrice(in: gs))
        XCTAssertTrue(gs.trophyEngine.isUnlocked("bundle_first"))
        XCTAssertFalse(gs.trophyEngine.isUnlocked("bundle_5"))

        for b in bundles[1...4] {
            gs.coinBalance = 10_000_000
            _ = gs.purchaseBundle(b, price: b.proratedPrice(in: gs))
        }
        XCTAssertTrue(gs.trophyEngine.isUnlocked("bundle_5"))
    }

    // MARK: - cosmetic_full_kit (equip in all 7 slots)

    /// `cosmetic_full_kit` latches only when a non-starter cosmetic is equipped
    /// in all 7 slots simultaneously; wired through the equip setters.
    func testFullKitLatchesWhenAllSevenSlotsNonStarter() {
        let gs = makeGameState()
        XCTAssertFalse(gs.trophyEngine.isUnlocked("cosmetic_full_kit"))

        // Equip a non-starter in six slots — ball slot still starter.
        gs.equippedGoal = GoalSkin.allCases.first { $0 != .target }!
        gs.equippedTrail = TrailColor.allCases.first { $0 != .graphite && $0 != .moneyRoll }!
        gs.equippedFloor = Floor.allCases.first { $0 != .classic && $0 != .moneyFull }!
        gs.equippedPit = Pit.allCases.first { $0 != .classic }!
        gs.equippedBoundary = Boundary.allCases.first { $0 != .classic }!
        gs.equippedMusic = MusicTrack.allCases.first { $0 != .none }!
        XCTAssertFalse(gs.trophyEngine.isUnlocked("cosmetic_full_kit"),
                       "ball slot still starter → not a full kit")

        // Equip a non-starter ball → all 7 slots non-starter.
        gs.equipBall(BallSkin.blue)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("cosmetic_full_kit"))
    }

    // MARK: - econ_working_capital / econ_nest_egg (source-tagged coins)

    /// `econ_working_capital` (5,000 play-earned) counts .play and .daily
    /// coins but NOT .iap / .refund / .giftCompensation; `econ_nest_egg`
    /// latches off the balance high-water.
    func testEconomyTrophiesRespectCoinSourceAndBalanceHighWater() {
        let gs = makeGameState()

        // Excluded sources must never advance econ_working_capital.
        gs.addCoins(6_000, source: .iap)
        gs.addCoins(6_000, source: .refund)
        gs.addCoins(6_000, source: .giftCompensation)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("econ_working_capital"),
                       "IAP / refund / gift coins are not play income")
        // …but they still count toward the coin BALANCE (nest egg).
        XCTAssertTrue(gs.trophyEngine.isUnlocked("econ_nest_egg"),
                      "any coins held ≥1,000 latch nest egg")

        // Play income advances working capital.
        gs.addCoins(4_000, source: .play)
        XCTAssertFalse(gs.trophyEngine.isUnlocked("econ_working_capital"))
        gs.addCoins(1_000, source: .daily)   // 5,000 play-earned total
        XCTAssertTrue(gs.trophyEngine.isUnlocked("econ_working_capital"))
    }

    // MARK: - No trophy keys to a purchase / IAP count

    /// `cosmetic_first_buy` is a one-shot LATCH (threshold 1), not a
    /// purchase-count trophy: a second, third… purchase changes nothing and no
    /// higher-count purchase trophy exists.
    func testCosmeticFirstBuyIsALatchNotAPurchaseCounter() throws {
        let catalog = try TrophyCatalog.load(bundle: .main)
        // Only one trophy keys to cosmetic_coin_buys, and its threshold is 1.
        let buyTrophies = catalog.trophies.filter {
            $0.criteria.metric == .cosmeticCoinBuys
        }
        XCTAssertEqual(buyTrophies.map(\.id), ["cosmetic_first_buy"])
        XCTAssertEqual(buyTrophies.first?.criteria.threshold, 1,
                       "no purchase-COUNT trophy may exist — first-buy is a latch")
    }

    // MARK: - Live vs backfill agreement

    /// The ownership metrics recorded live through `grant` produce the SAME
    /// unlocks as a first-launch backfill over the same save — the exclusion
    /// arithmetic lives in one place, so they cannot drift.
    func testLiveAndBackfillAgreeOnCosmeticOwnership() throws {
        let gs = makeGameState()
        gs.coinBalance = 100_000

        // Own 40 non-secret balls (past balls_own_40) + a few other slots.
        var granted = 0
        for b in BallSkin.allCases
        where granted < 40
            && b.tier != .starter
            && !TrophyCosmeticExclusions.iapSecretBalls.contains(b) {
            gs.grant(b); granted += 1
        }
        XCTAssertTrue(gs.trophyEngine.isUnlocked("balls_own_10"))
        XCTAssertTrue(gs.trophyEngine.isUnlocked("balls_own_40"))

        // Backfill a fresh engine from the SAME stored save.
        let backfilled = TrophyBackfill.snapshot(from: gs)
        let engine = TrophyEngine(catalog: try TrophyCatalog.load(bundle: .main),
                                  defaults: UserDefaults(suiteName: suiteName + ".backfill")!)
        for metric in TrophyMetric.allCases {
            if let value = backfilled[metric] { _ = engine.record(metric, value: value) }
        }
        for id in ["balls_own_10", "balls_own_40"] {
            XCTAssertTrue(engine.isUnlocked(id),
                          "backfill must also unlock \(id) — live and backfill must agree")
        }
        // The snapshot's evergreen/full-kit values match the live properties.
        XCTAssertEqual(backfilled[.evergreenCosmeticsOwned],
                       Double(gs.trophyEvergreenCosmeticsOwnedCount))
        XCTAssertEqual(backfilled[.ballsOwned],
                       Double(gs.trophyBallsOwnedCount))
    }
}
