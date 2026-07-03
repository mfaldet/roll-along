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

// MARK: - TrophyEngineTests (S0-T3+)

/// Placeholder — the engine's evaluation/idempotency/ratchet tests land in
/// S0-T3/S0-T4/S0-T5 (shared harness) and the full trigger sweep in S1-T9.
final class TrophyEngineTests: XCTestCase {}
