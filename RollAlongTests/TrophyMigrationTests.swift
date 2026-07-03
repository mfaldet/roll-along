//
//  TrophyMigrationTests.swift
//  RollAlongTests
//
//  S0-T4 — first-launch-with-trophies migration/backfill
//  (docs/trophies/sprint-plan.md §2 S0-T4; design.md §11 #12 "grant from
//  existing stats"; trophy-catalog.md §6 item 2 + the §6 badge-migration
//  boundary-parity note).
//
//  These tests drive the real backfill path end-to-end from REAL `ra_*`
//  key dumps: fixtures seed a throwaway UserDefaults suite with keys in the
//  exact on-disk format GameState writes (JSON-blob dicts, `[String]`
//  arrays for sets), build the AUTHORITATIVE decode with
//  `GameState(defaults:)`, derive the snapshot via `TrophyBackfill`, and
//  run `TrophyEngine.backfill`. Three save shapes are covered — fresh
//  install, mid-progress, veteran — plus:
//   • idempotency across relaunches (a second launch grants nothing);
//   • the legacy-timestamp marker on every grandfathered unlock;
//   • no unlock timestamp in the future;
//   • the 11 badge-wall mappings audited at their exact threshold values
//     (the legend-50 off-by-one lives here so no future edit re-breaks it);
//   • non-derivable metrics (NEW counters / run-events / ownership /
//     social / capstone) are never granted from a save alone.
//

import XCTest
@testable import RollAlong

final class TrophyMigrationTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "TrophyMigrationTests.isolated"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Fixture writers (real `ra_*` on-disk formats)

    /// Encode an `[Int: Int]` dict the way GameState persists `ra_bestStars`
    /// (JSON `[String: Int]` blob).
    private func writeIntDict(_ dict: [Int: Int], key: String) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: dict.map { (String($0.key), $0.value) })
        defaults.set(try! JSONEncoder().encode(stringKeyed), forKey: key)
    }

    /// Encode a `[Int: Double]` dict the way GameState persists `ra_bestTime`.
    private func writeDoubleDict(_ dict: [Int: Double], key: String) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: dict.map { (String($0.key), $0.value) })
        defaults.set(try! JSONEncoder().encode(stringKeyed), forKey: key)
    }

    /// Encode an `[Int: Set<Int>]` dict the way GameState persists
    /// `ra_collectedCoins`.
    private func writeSetDict(_ dict: [Int: Set<Int>], key: String) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: dict.map { (String($0.key), Array($0.value)) })
        defaults.set(try! JSONEncoder().encode(stringKeyed), forKey: key)
    }

    /// Encode a `[String: Int]` dict the way GameState persists
    /// `ra_trackProgress`/`ra_minigameWins`/`ra_minigameBests`/`ra_minigameDiffWins`.
    private func writeStringDict(_ dict: [String: Int], key: String) {
        defaults.set(try! JSONEncoder().encode(dict), forKey: key)
    }

    /// Encode a `Set<String>` the way GameState persists its string-set keys.
    private func writeStringSet(_ set: Set<String>, key: String) {
        defaults.set(Array(set), forKey: key)
    }

    /// Build the loaded GameState + engine from the currently-seeded dump,
    /// with a pinned clock so "never in the future" is deterministic.
    private func makeEngine(now: Date = Date()) -> (GameState, TrophyEngine) {
        let state = GameState(defaults: defaults)
        let catalog = try! TrophyCatalog.load()
        let engine = TrophyEngine(catalog: catalog, defaults: defaults, now: { now })
        return (state, engine)
    }

    // MARK: - Fresh install

    /// A save with no `ra_*` keys at all: backfill grants nothing, still
    /// marks itself done so it never re-runs, and no reveal is owed.
    func testFreshInstallGrantsNothingButMarksDone() {
        let (state, engine) = makeEngine()
        let snapshot = TrophyBackfill.snapshot(from: state)

        let granted = engine.backfill(from: snapshot)

        XCTAssertTrue(granted.isEmpty, "a fresh install has nothing to grandfather")
        XCTAssertTrue(engine.unlockedIDs.isEmpty)
        XCTAssertTrue(engine.didBackfill, "the flag must latch even on an empty grant")
        XCTAssertEqual(engine.backfillGrantCount, 0)
        XCTAssertTrue(defaults.bool(forKey: TrophyEngine.backfillDoneKey))
    }

    // MARK: - Mid-progress

    /// A believable early-mid save: cleared through climb level ~40 with a
    /// scatter of stars, one Comet Clash win, one Zen hour, and one
    /// completed bundle. Grants exactly the derivable trophies its stats
    /// prove — and nothing keyed to a NEW counter or a harder threshold.
    func testMidProgressGrantsDerivableSubset() {
        // Climb: highestUnlocked = 41 (cleared 40). Stars: 3 on the first
        // 12 levels = 36 total → clears climb_stars_25, not climb_stars_150.
        defaults.set(41, forKey: "ra_highestUnlocked")
        var stars: [Int: Int] = [:]
        for level in 1...12 { stars[level] = 3 }
        writeIntDict(stars, key: "ra_bestStars")
        // Pickups: 60 banked coins → below climb_pickups_100.
        var pickups: [Int: Set<Int>] = [:]
        for level in 1...20 { pickups[level] = [0, 1, 2] }   // 60 pickups
        writeSetDict(pickups, key: "ra_collectedCoins")
        // One fast clear at 8.5s → clears skill_speed_10s (lte).
        writeDoubleDict([3: 8.5, 7: 22.0], key: "ra_bestTime")

        // Minigames: 1 Comet Clash (snake) win, played snake + zen.
        writeStringDict(["snake": 1], key: "ra_minigameWins")
        writeStringSet(["snake", "zen"], key: "ra_playedModeIDs")
        defaults.set(3600, forKey: "ra_zenSeconds")   // exactly 1 hour → zen_hour

        // One completed bundle (bought as a unit).
        writeStringSet(["standard"], key: "ra_ownedBundles")

        // Coins on hand below the nest-egg bar.
        defaults.set(400, forKey: "ra_coinBalance")

        let (state, engine) = makeEngine()
        let granted = engine.backfill(from: TrophyBackfill.snapshot(from: state))
        let ids = Set(granted.map(\.id))

        // Present:
        for expected in ["climb_first_clear", "climb_level_10", "climb_stars_25",
                         "skill_speed_10s", "snake_first_win", "arcade_first_win",
                         "zen_hour", "bundle_first"] {
            XCTAssertTrue(ids.contains(expected), "mid save should grandfather \(expected)")
        }
        // Absent (threshold not met / not started):
        for absent in ["climb_level_50", "climb_stars_150", "climb_pickups_100",
                       "snake_wins_10", "arcade_all_six", "econ_nest_egg",
                       "bundle_5", "zen_10_hours"] {
            XCTAssertFalse(ids.contains(absent), "mid save should NOT grant \(absent)")
        }
        // Never a NEW-counter / event / social / capstone trophy from a save:
        for never in ["econ_working_capital", "econ_punch_card", "skill_first_try",
                      "skill_spotless", "skill_clean_sheet_10", "daily_first_start",
                      "social_sign_in", "cosmetic_first_buy", "balls_own_10",
                      "capstone_all"] {
            XCTAssertFalse(ids.contains(never),
                           "\(never) has no historical source — never backfilled")
        }
        XCTAssertEqual(engine.backfillGrantCount, granted.count)
    }

    // MARK: - Veteran

    /// A maxed-out save: past every derivable threshold in the catalog.
    /// Backfill must grant every derivable trophy (incl. the derivable
    /// Diamonds) — but NOT the capstone (12 of its 73 base trophies need
    /// live play the save can't prove) and NOT any NEW-counter/event/
    /// ownership/social metric.
    func testVeteranGrantsAllDerivableButNotCapstone() {
        seedVeteranSave()
        let (state, engine) = makeEngine()

        let granted = engine.backfill(from: TrophyBackfill.snapshot(from: state))
        let ids = Set(granted.map(\.id))

        // Every derivable trophy across every category, incl. Diamonds:
        let mustGrant = [
            "climb_first_clear", "climb_level_1000", "climb_summit",
            "climb_stars_150", "climb_perfect_world", "climb_pickups_100",
            "track_all_eight", "track_gauntlet",
            "daily_clears_50", "daily_login_30", "daily_week_streak",
            "arcade_grand_tour", "arcade_all_six", "arcade_wins_100",
            "arcade_hard_all", "snake_wins_10", "koth_hold_45",
            "pinball_score_150k", "rollout_maze_10", "rollup_500m",
            "disco_hard_10", "zen_10_hours", "coinpit_first_round",
            "coinpit_catch_90", "econ_pit_boss", "econ_nest_egg",
            "bundle_5", "pack_first", "skill_ace_veryhard", "skill_speed_10s",
        ]
        for id in mustGrant {
            XCTAssertTrue(ids.contains(id), "veteran must grandfather \(id)")
        }

        // The capstone is NOT grantable from a save: 12 of its base
        // trophies (ownership, NEW counters, run/event flags) have no
        // historical source, so the derived count can never reach 73.
        XCTAssertFalse(ids.contains("capstone_all"),
                       "capstone must not latch from backfill alone")
        XCTAssertFalse(engine.isUnlocked("capstone_all"))

        // Non-derivable base metrics stay locked even on a maxed save.
        for never in ["balls_own_40", "items_own_50", "cosmetic_first_buy",
                      "cosmetic_full_kit", "econ_working_capital",
                      "econ_punch_card", "skill_first_try", "skill_spotless",
                      "skill_clean_sheet_25", "daily_first_start",
                      "social_lives_sent_25", "whimsy_high_roller"] {
            XCTAssertFalse(engine.isUnlocked(never),
                           "\(never) needs live play — never backfilled")
        }

        // Exactly 61 of the 73 capstone-eligible trophies are derivable —
        // sanity-check the veteran actually cleared that many of them.
        let capstoneBase = Set(engine.catalog.capstone.criteria.requiredTrophyIDs ?? [])
        let grantedCapstoneBase = capstoneBase.filter { engine.isUnlocked($0) }
        XCTAssertEqual(grantedCapstoneBase.count, 61,
                       "veteran should hold every derivable capstone-base trophy")
    }

    // MARK: - Legacy timestamp marker

    /// Every grandfathered unlock carries the fixed `legacyUnlockDate`
    /// sentinel, cleanly distinguishable from a live unlock's `now()`.
    func testBackfillStampsLegacyMarker() {
        defaults.set(11, forKey: "ra_highestUnlocked")   // climb_first_clear + climb_level_10
        let (state, engine) = makeEngine()
        let granted = engine.backfill(from: TrophyBackfill.snapshot(from: state))

        XCTAssertFalse(granted.isEmpty)
        for trophy in granted {
            XCTAssertEqual(engine.unlockDate(for: trophy.id),
                           TrophyEngine.legacyUnlockDate,
                           "\(trophy.id) must carry the legacy marker")
        }
    }

    /// The legacy stamp — and therefore every backfilled unlock — is never
    /// in the future relative to the launch clock (S0-T4 acceptance).
    func testNoBackfilledTimestampInTheFuture() {
        seedVeteranSave()
        let launch = Date()
        let (state, engine) = makeEngine(now: launch)
        let granted = engine.backfill(from: TrophyBackfill.snapshot(from: state))

        XCTAssertFalse(granted.isEmpty)
        for trophy in granted {
            let stamp = engine.unlockDate(for: trophy.id)
            XCTAssertNotNil(stamp)
            XCTAssertLessThanOrEqual(stamp!, launch,
                                     "\(trophy.id) stamp must not be in the future")
        }
    }

    // MARK: - Idempotency across relaunches

    /// A second backfill (a later app launch) grants nothing and disturbs
    /// no existing unlock or timestamp.
    func testBackfillIsIdempotentAcrossRelaunches() {
        seedVeteranSave()

        // First launch.
        let (state1, engine1) = makeEngine()
        let first = engine1.backfill(from: TrophyBackfill.snapshot(from: state1))
        XCTAssertFalse(first.isEmpty)
        let firstCount = engine1.unlockedIDs.count

        // Second launch: fresh engine reads the persisted flag → no-op.
        let (state2, engine2) = makeEngine()
        XCTAssertTrue(engine2.didBackfill, "the done-flag must survive relaunch")
        let second = engine2.backfill(from: TrophyBackfill.snapshot(from: state2))

        XCTAssertTrue(second.isEmpty, "backfill must never re-grant on relaunch")
        XCTAssertEqual(engine2.unlockedIDs.count, firstCount,
                       "relaunch must not change the unlock set")
        XCTAssertEqual(engine2.backfillGrantCount, first.count,
                       "the persisted grant count is stable")

        // The legacy stamp on a sampled unlock is unchanged after relaunch.
        XCTAssertEqual(engine2.unlockDate(for: "climb_first_clear"),
                       TrophyEngine.legacyUnlockDate)
    }

    /// Even a fresh-install (empty) backfill is one-shot: seeding real stats
    /// AFTER the empty first launch does not retroactively grant them —
    /// those unlocks are S1's live-`record` job, not a second backfill.
    func testEmptyBackfillIsStillOneShot() {
        let (state0, engine0) = makeEngine()
        _ = engine0.backfill(from: TrophyBackfill.snapshot(from: state0))
        XCTAssertTrue(engine0.unlockedIDs.isEmpty)

        // Player then makes progress; a later launch's backfill must no-op.
        defaults.set(101, forKey: "ra_highestUnlocked")
        let (state1, engine1) = makeEngine()
        let granted = engine1.backfill(from: TrophyBackfill.snapshot(from: state1))
        XCTAssertTrue(granted.isEmpty,
                      "a save that already ran backfill never runs it again")
        XCTAssertFalse(engine1.isUnlocked("climb_first_clear"))
    }

    // MARK: - Badge-wall boundary parity (the 11 ProfileView mappings)

    /// The 11 retired badges map onto catalog trophies at exact thresholds
    /// (trophy-catalog.md §6 badge-migration table). This audits every
    /// derivable mapping at threshold−1 (locked) and threshold (granted) —
    /// the legend-50 off-by-one (`highestUnlocked ≥ 51`, not 50) is pinned
    /// so no future edit silently re-introduces it.
    func testBadgeWallBoundaryParity() {
        // (trophyID, ra_* key, threshold, atThreshold-grants?)
        // Each row is checked in isolation on a clean suite.

        // legend(50) → climb_level_50 at highestUnlocked >= 51 (NOT 50).
        assertHighestUnlockedBoundary(trophyID: "climb_level_50", threshold: 51)
        // first_steps → climb_first_clear at highestUnlocked >= 2.
        assertHighestUnlockedBoundary(trophyID: "climb_first_clear", threshold: 2)

        // star_collector → climb_stars_25 at totalStars >= 25.
        assertTotalStarsBoundary(trophyID: "climb_stars_25", threshold: 25)
        // stellar → climb_stars_150 at totalStars >= 150.
        assertTotalStarsBoundary(trophyID: "climb_stars_150", threshold: 150)

        // on_a_roll → daily_login_7 at dailyStreak >= 7.
        assertDailyStreakBoundary(trophyID: "daily_login_7", threshold: 7)
        // dedicated → daily_login_30 at dailyStreak >= 30.
        assertDailyStreakBoundary(trophyID: "daily_login_30", threshold: 30)

        // coin_hoarder → climb_pickups_100 at totalCoins (pickups) >= 100.
        assertPickupCoinsBoundary(trophyID: "climb_pickups_100", threshold: 100)

        // completionist → bundle_first at completed bundles >= 1.
        assertBundlesBoundary(trophyID: "bundle_first", threshold: 1)
        // bundle_hunter → bundle_5 at completed bundles >= 5.
        assertBundlesBoundary(trophyID: "bundle_5", threshold: 5)

        // hat_trick → superseded by skill_first_try / skill_spotless: both
        // are run-event flags with no historical source, so a save alone
        // can NEVER grandfather them — the correct migration behavior.
        assertNeverBackfilled(trophyID: "skill_first_try")
        assertNeverBackfilled(trophyID: "skill_spotless")
        // "Unlimited Power" is intentionally dropped — no successor trophy.
    }

    // MARK: - Boundary helpers

    private func freshSuite() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func runBackfillIDs() -> Set<String> {
        let (state, engine) = makeEngine()
        return Set(engine.backfill(from: TrophyBackfill.snapshot(from: state)).map(\.id))
    }

    private func assertHighestUnlockedBoundary(trophyID: String, threshold: Int) {
        freshSuite()
        defaults.set(threshold - 1, forKey: "ra_highestUnlocked")
        XCTAssertFalse(runBackfillIDs().contains(trophyID),
                       "\(trophyID) must stay locked at highestUnlocked \(threshold - 1)")
        freshSuite()
        defaults.set(threshold, forKey: "ra_highestUnlocked")
        XCTAssertTrue(runBackfillIDs().contains(trophyID),
                      "\(trophyID) must grant at highestUnlocked \(threshold)")
    }

    private func assertTotalStarsBoundary(trophyID: String, threshold: Int) {
        freshSuite()
        writeIntDict(starsDict(total: threshold - 1), key: "ra_bestStars")
        XCTAssertFalse(runBackfillIDs().contains(trophyID),
                       "\(trophyID) must stay locked at \(threshold - 1) stars")
        freshSuite()
        writeIntDict(starsDict(total: threshold), key: "ra_bestStars")
        XCTAssertTrue(runBackfillIDs().contains(trophyID),
                      "\(trophyID) must grant at \(threshold) stars")
    }

    /// Spread `total` stars across distinct levels (max 3 per level), all
    /// on levels above 10 so they never trip veryHard-ace / perfect-world.
    private func starsDict(total: Int) -> [Int: Int] {
        var dict: [Int: Int] = [:]
        var remaining = total
        var level = 11
        while remaining > 0 {
            let s = min(3, remaining)
            // Avoid multiples of 5 above 10 so no 3-star trips skill_ace_veryhard.
            if level % 5 == 0 { level += 1; continue }
            dict[level] = s
            remaining -= s
            level += 1
        }
        return dict
    }

    private func assertDailyStreakBoundary(trophyID: String, threshold: Int) {
        freshSuite()
        defaults.set(threshold - 1, forKey: "ra_dailyStreak")
        XCTAssertFalse(runBackfillIDs().contains(trophyID),
                       "\(trophyID) must stay locked at streak \(threshold - 1)")
        freshSuite()
        defaults.set(threshold, forKey: "ra_dailyStreak")
        XCTAssertTrue(runBackfillIDs().contains(trophyID),
                      "\(trophyID) must grant at streak \(threshold)")
    }

    private func assertPickupCoinsBoundary(trophyID: String, threshold: Int) {
        freshSuite()
        writeSetDict(pickupsDict(total: threshold - 1), key: "ra_collectedCoins")
        XCTAssertFalse(runBackfillIDs().contains(trophyID),
                       "\(trophyID) must stay locked at \(threshold - 1) pickups")
        freshSuite()
        writeSetDict(pickupsDict(total: threshold), key: "ra_collectedCoins")
        XCTAssertTrue(runBackfillIDs().contains(trophyID),
                      "\(trophyID) must grant at \(threshold) pickups")
    }

    /// `total` banked pickups spread 3-per-level (indices 0,1,2).
    private func pickupsDict(total: Int) -> [Int: Set<Int>] {
        var dict: [Int: Set<Int>] = [:]
        var remaining = total
        var level = 1
        while remaining > 0 {
            let n = min(3, remaining)
            dict[level] = Set(0..<n)
            remaining -= n
            level += 1
        }
        return dict
    }

    private func assertBundlesBoundary(trophyID: String, threshold: Int) {
        freshSuite()
        writeStringSet(bundleIDs(count: threshold - 1), key: "ra_ownedBundles")
        XCTAssertFalse(runBackfillIDs().contains(trophyID),
                       "\(trophyID) must stay locked at \(threshold - 1) bundles")
        freshSuite()
        writeStringSet(bundleIDs(count: threshold), key: "ra_ownedBundles")
        XCTAssertTrue(runBackfillIDs().contains(trophyID),
                      "\(trophyID) must grant at \(threshold) bundles")
    }

    /// `count` distinct completed-bundle ids drawn from the real catalogue
    /// (owned-as-a-unit bundles count as complete — GameState.completedBundleIDs).
    private func bundleIDs(count: Int) -> Set<String> {
        Set(CosmeticBundle.catalogue.prefix(count).map(\.id))
    }

    private func assertNeverBackfilled(trophyID: String) {
        freshSuite()
        seedVeteranSave()   // maxed save — still must not grant it
        XCTAssertFalse(runBackfillIDs().contains(trophyID),
                       "\(trophyID) is a run-event flag — never backfilled")
    }

    // MARK: - Veteran fixture

    /// Seed a maxed-out `ra_*` dump: past every DERIVABLE catalog threshold.
    /// Deliberately writes NO NEW-counter keys (ra_trophy*) so those metrics
    /// read zero — proving the non-derivable trophies stay locked.
    private func seedVeteranSave() {
        // Climb: cleared the whole mountain (past 5,000).
        defaults.set(5001, forKey: "ra_highestUnlocked")
        // Every level 1…100 at 3 stars → one perfect world + huge star sum;
        // plus a veryHard ace (level 15) implicitly included.
        var stars: [Int: Int] = [:]
        for level in 1...100 { stars[level] = 3 }     // 300 stars, world 1 perfect
        writeIntDict(stars, key: "ra_bestStars")
        // Pickups well past 100.
        var pickups: [Int: Set<Int>] = [:]
        for level in 1...60 { pickups[level] = [0, 1, 2] }   // 180 pickups
        writeSetDict(pickups, key: "ra_collectedCoins")
        // A sub-10s clear → skill_speed_10s.
        writeDoubleDict([2: 6.5, 40: 30.0], key: "ra_bestTime")

        // Tracks: all 8 complete, incl. golden-gauntlet; a track at level 100.
        let allTracks: Set<String> = ["adventure", "expert", "gauntlet",
                                      "nightmare", "speed", "precision",
                                      "endurance", "golden-gauntlet"]
        writeStringSet(allTracks, key: "ra_completedTracks")
        writeStringDict(["adventure": 100, "golden-gauntlet": 100], key: "ra_trackProgress")

        // Daily: 50+ completions on consecutive dates (≥7 in a row) + a big
        // reward streak.
        writeStringSet(consecutiveDailyKeys(count: 60), key: "ra_dailyChallengeDone")
        defaults.set(45, forKey: "ra_dailyStreak")

        // Minigames: all 12 played; 100+ competitive wins spread across the
        // 6 modes (≥10 each); Hard wins in all 6; big bests.
        writeStringSet(Set(TrophyMetric.minigameModeIDs), key: "ra_playedModeIDs")
        writeStringDict(["snake": 20, "sumo": 20, "paintball": 20,
                         "goldrush": 20, "marblecup": 20, "koth": 20],
                        key: "ra_minigameWins")
        var hard: [String: Int] = [:]
        for id in TrophyMetric.competitiveModeIDs { hard["\(id)|hard"] = 3 }
        writeStringDict(hard, key: "ra_minigameDiffWins")
        writeStringDict(["paintball": 80, "koth": 55, "rollout": 15,
                         "rollup": 700, "discohard": 15, "discoeasy": 40],
                        key: "ra_minigameBests")
        defaults.set(200_000, forKey: "ra_pinballBest")
        defaults.set(40_000, forKey: "ra_zenSeconds")        // >10h
        defaults.set(120, forKey: "ra_goldrushBest")         // coinpit_catch_90
        defaults.set(5_000, forKey: "ra_goldrushCoinsTotal") // econ_pit_boss

        // Cosmetics: 6 owned-as-a-unit bundles (→ completedBundleIDs ≥ 6,
        // clears bundle_5) + a ball pack (clears pack_first).
        writeStringSet(bundleIDs(count: 6), key: "ra_ownedBundles")
        writeStringSet(["planets"], key: "ra_ownedPacks")

        // Economy: comfortably past the nest-egg bar.
        defaults.set(5_000, forKey: "ra_coinBalance")
    }

    /// `count` consecutive "YYYY-MM-DD" keys ending today (UTC), the
    /// `DailyChallenge.key()` format the completions set stores.
    private func consecutiveDailyKeys(count: Int) -> Set<String> {
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
