//
//  TrophyCohortRarityTests.swift
//  RollAlongTests
//
//  S3-T7 — Synthetic-cohort rarity QA WITHOUT live Supabase
//  (docs/trophies/sprint-plan.md §2 S3-T7; QA plan §5 item 5; design.md §3).
//
//  The live-Supabase half of S3-T7 (seed a dev branch, verify the deployed
//  rollup + RLS end-to-end in-app) is a MAC-GATED post-migration verification —
//  see the note block at the bottom of this file and mac_deploy_steps in the
//  handoff. This suite covers everything that can be proven headlessly with the
//  S3 hard rule (no live Supabase): build in-memory synthetic cohorts, run the
//  rollup SQL's MATH as a faithful Swift reimplementation, and drive the result
//  through the SHIPPED S3-T4 client code (`TrophyRarityIndex`, the band map, the
//  cold-start + is_paused gates, and the Trophy Room wiring). Zero network.
//
//  WHY A DISTINCT SUITE FROM TrophyRarityTests (S3-T4): those tests hand-author
//  single `TrophyStatRow`s to prove the pure display functions. S3-T7 proves the
//  WHOLE PIPELINE over a POPULATION: many installs each with a set of unlocks,
//  where `earned_count`/`denominator`/`pct` are DERIVED (not hand-set) exactly
//  as docs/trophies/trophy-rollup.sql derives them, and the four labels + the
//  suppression flip are verified at the cohort level. It also proves the two
//  properties only a population model can express:
//    • pct = earned_count / denominator counted over DISTINCT installs;
//    • deleting a signed-in player (the player_trophies rail) does NOT change
//      any anon-derived count (trophy_unlocks is a separate rail).
//
//  FAITHFULNESS CONTRACT: `SyntheticRollup` below mirrors the rollup SQL line by
//  line (numerator = count(distinct install_id) from trophy_unlocks; denominator
//  = count(distinct user_id) from app_launch events; pct = least(earned,denom)/
//  denom with the divide guarded; rarity_ready = denom >= min_installs AND now >=
//  launch_at + min_days; is_paused passed through, never written by the rollup).
//  Column names on the emitted `TrophyStatRow` are the SAME the anon GET returns,
//  so the rows flow into TrophyRarityIndex(rows:) with no adapter — the client
//  sees byte-for-byte what a real rollup would hand it.
//
//  NEVER-MINT / PRIVACY: this is a pure-math QA harness; it grants no coins,
//  models no PII (installs are opaque UUID strings), and reads only aggregates.
//

import XCTest
@testable import RollAlong

final class TrophyCohortRarityTests: XCTestCase {

    // =======================================================================
    // MARK: - Synthetic cohort model
    // =======================================================================

    /// One synthetic install on the ANONYMOUS rail. `id` is the install UUID
    /// (== events.user_id == trophy_unlocks.install_id). `booted` models whether
    /// this install has an `app_launch` event row (the denominator rail); an
    /// install that unlocked a trophy offline but whose app_launch row hasn't
    /// landed is `booted = false` — the rollup's race the `least(...)` clamp
    /// exists for. `unlocked` is the set of trophy ids this install pushed to
    /// trophy_unlocks.
    struct Install {
        let id: String
        var booted: Bool
        var unlocked: Set<String>
    }

    /// One synthetic SIGNED-IN player on the identity rail (player_trophies).
    /// Deliberately SEPARATE from `Install`: player_trophies is FK → players
    /// ON DELETE CASCADE, so deleting a player touches ONLY this rail. Its
    /// unlock set never feeds rarity (the rollup reads trophy_unlocks, never
    /// player_trophies). Present here solely to prove the deletion invariant.
    struct Player {
        let id: String
        var trophies: Set<String>
    }

    /// A whole synthetic world: the anon rail (installs), the identity rail
    /// (players), and per-trophy pause flags. `SyntheticRollup` reads it exactly
    /// as the SQL rollup reads the live tables.
    struct Cohort {
        var installs: [Install]
        var players: [Player] = []
        /// trophy ids flagged is_paused (the rollup never writes this; the
        /// display kill-switch is an operator/service-role edit, design.md §9).
        var pausedTrophyIDs: Set<String> = []
    }

    /// A faithful Swift reimplementation of docs/trophies/trophy-rollup.sql's
    /// `rollup_trophy_stats()`. Given a cohort and the cold-start config, it
    /// produces the exact `[TrophyStatRow]` a real rollup pass would upsert into
    /// trophy_stats — the SAME shape the anon GET returns to the client.
    enum SyntheticRollup {

        /// Default cold-start config, mirroring trophy_rollup_config's defaults
        /// (design.md §3 / decision #6): 500 installs AND 30 days post-launch.
        static let defaultMinInstalls = 500
        static let defaultMinDays = 30

        /// Run one rollup pass. `now`/`launchAt` drive the 30-day gate; the SQL
        /// computes `rarity_ready` once per pass (same for every row), so this
        /// does too.
        ///
        /// Trophy universe: the SQL groups trophy_unlocks by trophy_id, so a
        /// trophy nobody unlocked simply has NO row (the client suppresses it —
        /// TrophyRarityTests.testUnknownTrophyIsSuppressed). We therefore emit a
        /// row per trophy id that appears in at least one install's unlock set.
        static func run(_ cohort: Cohort,
                        now: Date,
                        launchAt: Date,
                        minInstalls: Int = defaultMinInstalls,
                        minDays: Int = defaultMinDays) -> [TrophyStatRow] {

            // --- denominator (rollup: count(distinct user_id) from events
            //     where event_name = 'app_launch') ---------------------------
            // Same id rail as the numerator: distinct BOOTED install UUIDs.
            let bootedIDs = Set(cohort.installs.filter(\.booted).map(\.id))
            let denominator = bootedIDs.count

            // --- cold-start gate (rollup: v_denominator >= v_min_installs AND
            //     now() >= v_launch_at + v_min_days) --------------------------
            // Computed ONCE, identical on every row this pass.
            let gateOpensAt = launchAt.addingTimeInterval(Double(minDays) * 86_400)
            let rarityReady = (denominator >= minInstalls) && (now >= gateOpensAt)

            // --- numerator per trophy (rollup: count(distinct install_id) from
            //     trophy_unlocks group by trophy_id) --------------------------
            // count(distinct install_id): an install counts once per trophy no
            // matter how many times it pushed (the UNIQUE (install_id,trophy_id)
            // constraint already collapses re-pushes; distinct is the same
            // belt-and-suspenders the SQL uses).
            var earnedByTrophy: [String: Set<String>] = [:]
            for install in cohort.installs {
                for tid in install.unlocked {
                    earnedByTrophy[tid, default: []].insert(install.id)
                }
            }

            // --- emit one clamped row per trophy (rollup upsert body) --------
            var rows: [TrophyStatRow] = []
            for (tid, earners) in earnedByTrophy {
                // least(c.earned_count, v_denominator): the race clamp — an
                // unlock whose app_launch row hasn't landed can push earned past
                // the denominator for one pass; the clamp keeps the CHECK
                // (earned_count <= denominator) satisfied.
                let clampedEarned = min(earners.count, denominator)
                // pct: guarded divide, clamp to [0,1] — same clamped numerator.
                let pct: Double = denominator == 0
                    ? 0
                    : Double(clampedEarned) / Double(denominator)
                rows.append(TrophyStatRow(
                    trophy_id: tid,
                    earned_count: clampedEarned,
                    denominator: denominator,
                    pct: pct,
                    // is_paused is NOT written by the rollup — it is an operator
                    // edit that survives passes. We carry the cohort's flag so
                    // the emitted row matches what the client would fetch.
                    is_paused: cohort.pausedTrophyIDs.contains(tid),
                    rarity_ready: rarityReady))
            }
            // Deterministic order (dictionary iteration is unordered) so
            // assertions on the row array are stable.
            return rows.sorted { $0.trophy_id < $1.trophy_id }
        }
    }

    // MARK: - Cohort builders

    /// Build `installCount` installs (all booted) where the FIRST `earnerCount`
    /// of them unlocked `trophyID`. Deterministic ids so tests are reproducible.
    private func cohort(installCount: Int,
                        trophyID: String,
                        earnerCount: Int) -> Cohort {
        precondition(earnerCount <= installCount)
        var installs: [Install] = []
        installs.reserveCapacity(installCount)
        for i in 0..<installCount {
            installs.append(Install(id: "install-\(i)",
                                    booted: true,
                                    unlocked: i < earnerCount ? [trophyID] : []))
        }
        return Cohort(installs: installs)
    }

    /// A launch instant far enough in the past that `now` is >= 30 days after —
    /// so the DAY half of the gate is OPEN and only the install-floor half is
    /// under test (and vice-versa where a test overrides these).
    private let launchLongAgo = Date(timeIntervalSinceReferenceDate: 700_000_000)
    /// 60 days after `launchLongAgo` — comfortably past the 30-day gate.
    private var nowPast30Days: Date { launchLongAgo.addingTimeInterval(60 * 86_400) }

    /// Resolve a single trophy's gated display through the SHIPPED S3-T4 index.
    private func display(_ cohort: Cohort,
                         trophyID: String,
                         now: Date? = nil,
                         launchAt: Date? = nil) -> TrophyRarityDisplay {
        let rows = SyntheticRollup.run(cohort,
                                       now: now ?? nowPast30Days,
                                       launchAt: launchAt ?? launchLongAgo)
        return TrophyRarityIndex(rows: rows).display(for: trophyID)
    }

    // =======================================================================
    // MARK: - (A) pct = earned_count / denominator over DISTINCT installs
    // =======================================================================

    /// The headline invariant: the emitted pct equals earned/denom counted over
    /// distinct installs, and the band the client derives matches.
    func testPctIsEarnedOverDenominatorOverDistinctInstalls() {
        // 1000 booted installs, 620 earned this trophy → 62% → Common.
        let c = cohort(installCount: 1000, trophyID: "t", earnerCount: 620)
        let rows = SyntheticRollup.run(c, now: nowPast30Days, launchAt: launchLongAgo)
        let row = try! XCTUnwrap(rows.first { $0.trophy_id == "t" })
        XCTAssertEqual(row.earned_count, 620)
        XCTAssertEqual(row.denominator, 1000)
        XCTAssertEqual(row.pct, 0.62, accuracy: 1e-12,
                       "pct is earned_count / denominator.")
        XCTAssertEqual(TrophyRarityBand.band(forFraction: row.pct), .common)
    }

    /// A duplicate push from the same install must NOT inflate earned_count —
    /// count(distinct install_id) collapses it, exactly like the UNIQUE
    /// constraint on trophy_unlocks. Model it by unlocking the same trophy on an
    /// install that already has it (Set semantics = the DB's UNIQUE).
    func testDuplicateInstallUnlocksCountOnce() {
        var c = cohort(installCount: 100, trophyID: "t", earnerCount: 30)
        // "Re-push" from install-0 (already an earner) + a NON-earner pushing
        // twice: Set insert is idempotent, mirroring ON CONFLICT DO NOTHING.
        c.installs[0].unlocked.insert("t")
        c.installs[50].unlocked.insert("t")
        c.installs[50].unlocked.insert("t") // second push — no-op
        let rows = SyntheticRollup.run(c, now: nowPast30Days, launchAt: launchLongAgo)
        let row = try! XCTUnwrap(rows.first { $0.trophy_id == "t" })
        XCTAssertEqual(row.earned_count, 31,
                       "install-0's re-push counts once; install-50's two pushes count once.")
    }

    /// Denominator is DISTINCT BOOTED installs — an install that unlocked
    /// offline but whose app_launch row hasn't landed is NOT in the denominator,
    /// and the rollup's least(earned, denom) clamp keeps the row consistent.
    func testUnbootedEarnerIsClampedNotOverCounted() {
        // 10 booted installs (denominator 10), plus 3 installs that unlocked "t"
        // but have NOT booted (no app_launch row) — earned would be 13 raw.
        var installs: [Install] = (0..<10).map {
            Install(id: "b\($0)", booted: true, unlocked: ["t"])
        }
        installs += (0..<3).map {
            Install(id: "u\($0)", booted: false, unlocked: ["t"])
        }
        let rows = SyntheticRollup.run(Cohort(installs: installs),
                                       now: nowPast30Days, launchAt: launchLongAgo,
                                       minInstalls: 1) // floor out of the way
        let row = try! XCTUnwrap(rows.first { $0.trophy_id == "t" })
        XCTAssertEqual(row.denominator, 10, "only booted installs count for the denominator.")
        XCTAssertEqual(row.earned_count, 10, "earned is clamped to the denominator (race clamp).")
        XCTAssertLessThanOrEqual(row.earned_count, row.denominator,
                                 "the CHECK (earned_count <= denominator) holds.")
        XCTAssertEqual(row.pct, 1.0, "pct clamps to 1.0, never > 100%.")
    }

    // =======================================================================
    // MARK: - (B) The four labels land at each cutoff — driven by cohort counts
    // =======================================================================

    /// Parameterized sweep across the cutoffs: for each (earners-out-of-1000)
    /// count we assert the client-derived band. Denominator 1000 makes the
    /// count a direct percent. Boundaries prove the design.md §3 rule that the
    /// cutoff value itself belongs to the LESS-rare band.
    func testFourLabelsAtEachCutoffAcrossCohorts() {
        let denom = 1000
        // (earners, expected band, note)
        let cases: [(Int, TrophyRarityBand, String)] = [
            (1000, .common,    "100% → Common"),
            (620,  .common,    "62% → Common"),
            (500,  .common,    "exactly 50% → Common (≥ 50)"),
            (499,  .rare,      "49.9% → Rare (< 50)"),
            (300,  .rare,      "30% → Rare"),
            (150,  .rare,      "exactly 15% → Rare (< 15 is the cutoff)"),
            (149,  .veryRare,  "14.9% → Very Rare (< 15)"),
            (100,  .veryRare,  "10% → Very Rare"),
            (50,   .veryRare,  "exactly 5% → Very Rare (< 5 is the cutoff)"),
            (49,   .ultraRare, "4.9% → Ultra Rare (< 5)"),
            (9,    .ultraRare, "0.9% → Ultra Rare"),
            (1,    .ultraRare, "0.1% (a single earner) → Ultra Rare"),
        ]
        for (earners, expected, note) in cases {
            let c = cohort(installCount: denom, trophyID: "t", earnerCount: earners)
            let d = display(c, trophyID: "t")
            XCTAssertEqual(d.band, expected, "cohort \(earners)/\(denom): \(note)")
        }
    }

    /// A trophy NOBODY unlocked emits NO trophy_stats row (the rollup groups
    /// trophy_unlocks by trophy_id, so a zero-earner trophy never appears). The
    /// client therefore suppresses it — NOT a fabricated 0% Ultra Rare band.
    /// (This is the pipeline-level counterpart to TrophyRarityTests' pure-function
    /// `band(forFraction: 0.0) == .ultraRare`: at 0 earners there is simply no
    /// row to map.) Verified over a well-past-the-gate population.
    func testZeroEarnerTrophyEmitsNoRowAndIsSuppressed() {
        // 1000 booted installs, but trophy "unearned" has 0 earners; trophy "t"
        // has some, so the pass produces rows (and the gate is open).
        let installs: [Install] = (0..<1000).map {
            Install(id: "i\($0)", booted: true, unlocked: $0 < 300 ? ["t"] : [])
        }
        let rows = SyntheticRollup.run(Cohort(installs: installs),
                                       now: nowPast30Days, launchAt: launchLongAgo)
        XCTAssertFalse(rows.contains { $0.trophy_id == "unearned" },
                       "a zero-earner trophy has no stats row.")
        XCTAssertEqual(TrophyRarityIndex(rows: rows).display(for: "unearned"), .suppressed,
                       "no row → suppressed, never a fabricated 0% Ultra Rare band.")
    }

    /// The cutoff EDGE with a non-round percentage, so the boundary is a genuine
    /// fraction (not a clean integer percent) — proves the band comparison is on
    /// the real `earned/denom` fraction, not a rounded display value. Denom 800
    /// keeps the population over the 500 install-floor so the gate is open.
    /// 400/800 = exactly 50.000% → Common; 399/800 = 49.875% → Rare.
    func testCutoffEdgesWithNonRoundPercentage() {
        let common = cohort(installCount: 800, trophyID: "t", earnerCount: 400) // 50.000%
        XCTAssertEqual(display(common, trophyID: "t").band, .common,
                       "400/800 = exactly 50% → Common.")
        let rare = cohort(installCount: 800, trophyID: "t", earnerCount: 399) // 49.875%
        XCTAssertEqual(display(rare, trophyID: "t").band, .rare,
                       "399/800 = 49.875% (a genuine fraction, < 50) → Rare.")
    }

    // =======================================================================
    // MARK: - (C) Suppression flips at EXACTLY 500 installs AND 30 days
    // =======================================================================

    /// The install-floor half of the gate, driven by cohort SIZE. 499 booted
    /// installs → suppressed; 500 → the band appears. (Day half held open.)
    func testSuppressionFlipsAtExactly500Installs() {
        // 499 installs, 200 earners (would be 40% → Rare if the gate were open).
        let below = cohort(installCount: 499, trophyID: "t", earnerCount: 200)
        XCTAssertNil(display(below, trophyID: "t").band,
                     "499 installs → suppressed (never a fabricated band).")

        // 500 installs, 200 earners → 40% → Rare, gate open.
        let at = cohort(installCount: 500, trophyID: "t", earnerCount: 200)
        let d = display(at, trophyID: "t")
        XCTAssertEqual(d.band, .rare, "exactly 500 installs → the gate opens.")
        XCTAssertEqual(d.detailPercent, "40%")
    }

    /// The 30-day half of the gate, driven by `now` vs `launch_at + 30d`. This
    /// is the dimension the single-row S3-T4 tests can't exercise (they take
    /// `rarity_ready` as a server input); here the synthetic rollup COMPUTES it.
    /// A huge, well-over-floor population is still suppressed one second before
    /// day 30, and appears one second after.
    func testSuppressionFlipsAtExactly30Days() {
        let launch = Date(timeIntervalSinceReferenceDate: 600_000_000)
        let day30 = launch.addingTimeInterval(30 * 86_400)
        // 1000 installs (floor easily met), 100 earners → 10% → Very Rare.
        let c = cohort(installCount: 1000, trophyID: "t", earnerCount: 100)

        // One second BEFORE the 30-day mark → suppressed.
        let justBefore = display(c, trophyID: "t",
                                 now: day30.addingTimeInterval(-1), launchAt: launch)
        XCTAssertNil(justBefore.band,
                     "before launch+30d the day-gate is closed → suppressed, even over 1000 installs.")

        // Exactly at the 30-day mark → open (rollup uses now() >= launch+30d).
        let exactly = display(c, trophyID: "t", now: day30, launchAt: launch)
        XCTAssertEqual(exactly.band, .veryRare,
                       "at exactly launch+30d the day-gate opens.")

        // Well after → still open.
        let after = display(c, trophyID: "t",
                            now: day30.addingTimeInterval(86_400), launchAt: launch)
        XCTAssertEqual(after.band, .veryRare)
    }

    /// BOTH halves are required (logical AND). Over-floor-but-too-early and
    /// past-30-days-but-under-floor both suppress; only both-satisfied renders.
    func testGateRequiresBothInstallsAndDays() {
        let launch = Date(timeIntervalSinceReferenceDate: 600_000_000)
        let past30 = launch.addingTimeInterval(45 * 86_400)
        let pre30 = launch.addingTimeInterval(10 * 86_400)

        let bigCohort = cohort(installCount: 1000, trophyID: "t", earnerCount: 100)
        let smallCohort = cohort(installCount: 300, trophyID: "t", earnerCount: 30)

        // installs OK, days NOT → suppressed.
        XCTAssertNil(display(bigCohort, trophyID: "t", now: pre30, launchAt: launch).band,
                     "500+ installs but < 30 days → suppressed.")
        // days OK, installs NOT → suppressed.
        XCTAssertNil(display(smallCohort, trophyID: "t", now: past30, launchAt: launch).band,
                     "> 30 days but < 500 installs → suppressed.")
        // both OK → rendered.
        XCTAssertEqual(display(bigCohort, trophyID: "t", now: past30, launchAt: launch).band,
                       .veryRare, "both halves satisfied → the band renders.")
    }

    /// Parameterized flip table spanning BOTH threshold dimensions at once, so
    /// the AND is exercised at every corner of the (installs × days) grid.
    func testColdStartFlipGrid() {
        let launch = Date(timeIntervalSinceReferenceDate: 600_000_000)
        let dayBefore = launch.addingTimeInterval(30 * 86_400 - 1)
        let dayAt = launch.addingTimeInterval(30 * 86_400)
        // (installs, now, expectRendered)
        let grid: [(Int, Date, Bool)] = [
            (499, dayBefore, false),
            (499, dayAt,     false),
            (500, dayBefore, false),
            (500, dayAt,     true),   // the ONLY corner that renders
        ]
        for (installs, now, expectRendered) in grid {
            // 10% earners so a rendered band is Very Rare (unambiguous vs nil).
            let earners = max(1, installs / 10)
            let c = cohort(installCount: installs, trophyID: "t", earnerCount: earners)
            let d = display(c, trophyID: "t", now: now, launchAt: launch)
            if expectRendered {
                XCTAssertNotNil(d.band, "installs=\(installs), gate-open → rendered")
            } else {
                XCTAssertNil(d.band, "installs=\(installs), now=\(now) → suppressed")
            }
        }
    }

    // =======================================================================
    // MARK: - (D) Deleting a player does NOT change anon-derived counts
    // =======================================================================

    /// The rail-separation invariant. The rollup reads trophy_unlocks (anon)
    /// and events (anon) — NEVER player_trophies. Deleting a signed-in player
    /// cascades away their player_trophies rows but leaves trophy_unlocks and
    /// events untouched, so EVERY trophy_stats value the client would fetch is
    /// byte-identical before and after the deletion.
    func testDeletingPlayerLeavesRarityCountsUnchanged() {
        // 800 booted installs; 240 unlocked "t" (30% → Rare). Some of those
        // installs ALSO correspond to signed-in players (player_trophies), but
        // the player rail is independent data.
        var c = cohort(installCount: 800, trophyID: "t", earnerCount: 240)
        c.players = [
            Player(id: "p-alice", trophies: ["t", "other"]),
            Player(id: "p-bob",   trophies: ["t"]),
            Player(id: "p-carol", trophies: ["other"]),
        ]

        let before = SyntheticRollup.run(c, now: nowPast30Days, launchAt: launchLongAgo)

        // Delete p-alice: ON DELETE CASCADE removes ONLY her player_trophies.
        // The anon rails (installs / events) are untouched — that is the whole
        // point of keeping rarity on trophy_unlocks (design.md §4 / decision
        // #5, internal-data-backend.md §6.3 increment-only).
        c.players.removeAll { $0.id == "p-alice" }

        let after = SyntheticRollup.run(c, now: nowPast30Days, launchAt: launchLongAgo)

        XCTAssertEqual(before, after,
                       "deleting a player changes no trophy_stats row (rarity is anon-derived).")
        // And the client-facing band is likewise unchanged.
        let bandBefore = TrophyRarityIndex(rows: before).display(for: "t").band
        let bandAfter = TrophyRarityIndex(rows: after).display(for: "t").band
        XCTAssertEqual(bandBefore, .rare)
        XCTAssertEqual(bandAfter, .rare)
    }

    /// Even deleting EVERY player leaves rarity intact: the anon rail is the
    /// sole numerator source. (increment-only survivability — the counts can
    /// never dip because a human deleted their account.)
    func testDeletingAllPlayersLeavesRarityIntact() {
        var c = cohort(installCount: 600, trophyID: "t", earnerCount: 60) // 10% → Very Rare
        c.players = (0..<600).map { Player(id: "p\($0)", trophies: ["t"]) }

        let before = SyntheticRollup.run(c, now: nowPast30Days, launchAt: launchLongAgo)
        c.players.removeAll()
        let after = SyntheticRollup.run(c, now: nowPast30Days, launchAt: launchLongAgo)

        XCTAssertEqual(before, after, "wiping the player rail does not decrement any count.")
        XCTAssertEqual(TrophyRarityIndex(rows: after).display(for: "t").band, .veryRare)
    }

    // =======================================================================
    // MARK: - (E) is_paused kill-switch survives a rollup pass
    // =======================================================================

    /// A paused trophy still gets its counts recomputed (the rollup owns
    /// counts/pct/ready) but is_paused is preserved across the pass and the
    /// client suppresses the row (design.md §9). Proves the flag isn't clobbered
    /// by the numerator recompute.
    func testPausedTrophySuppressedThroughRollup() {
        var c = cohort(installCount: 1000, trophyID: "t", earnerCount: 300) // 30% → Rare
        c.pausedTrophyIDs = ["t"]
        let rows = SyntheticRollup.run(c, now: nowPast30Days, launchAt: launchLongAgo)
        let row = try! XCTUnwrap(rows.first { $0.trophy_id == "t" })
        XCTAssertTrue(row.is_paused, "the rollup preserves is_paused across a pass.")
        XCTAssertEqual(row.pct, 0.30, accuracy: 1e-12, "counts are still recomputed while paused.")
        XCTAssertNil(TrophyRarityIndex(rows: rows).display(for: "t").band,
                     "a paused trophy suppresses its rarity slot regardless of the counts.")
    }

    // =======================================================================
    // MARK: - (F) Whole-population multi-trophy pass → Trophy Room end-to-end
    // =======================================================================

    /// A realistic mixed cohort with several trophies at different rarities,
    /// run through the rollup and then into the SHIPPED Trophy Room model — the
    /// end-to-end path the acceptance criterion names. Every band label lands on
    /// the right row; a below-floor world would show placeholders everywhere.
    func testMixedCohortRendersCorrectBandsInTrophyRoom() throws {
        // 1000 booted installs. Assign real catalog ids so the room can match
        // them. Rarity by design: one Common, one Very Rare, one Ultra Rare.
        let common = "climb_first_clear"      // 800/1000 = 80% → Common
        let veryRare = "climb_level_10"       // 120/1000 = 12% → Very Rare
        let ultra = "pinball_score_50k"       // 20/1000 = 2%  → Ultra Rare

        var installs: [Install] = []
        for i in 0..<1000 {
            var set: Set<String> = []
            if i < 800 { set.insert(common) }
            if i < 120 { set.insert(veryRare) }
            if i < 20  { set.insert(ultra) }
            installs.append(Install(id: "i\(i)", booted: true, unlocked: set))
        }
        let rows = SyntheticRollup.run(Cohort(installs: installs),
                                       now: nowPast30Days, launchAt: launchLongAgo)
        let index = TrophyRarityIndex(rows: rows)

        // Drive the SHIPPED Trophy Room model with the derived index.
        let engine = try makeEngine()
        let model = TrophyRoomModel(engine: engine, rarity: index)

        XCTAssertEqual(bandLabel(model, id: common), "Common")
        XCTAssertEqual(bandLabel(model, id: veryRare), "Very Rare")
        XCTAssertEqual(bandLabel(model, id: ultra), "Ultra Rare")
        // Detail percent is carried for the rarest.
        XCTAssertEqual(rarityRow(model, id: ultra)?.rarityDetailPercent, "2%")
    }

    /// The same mixed cohort, but too small to pass the floor → the whole room
    /// shows the placeholder, never a day-1 band on any trophy.
    func testSmallMixedCohortShowsPlaceholdersEverywhere() throws {
        var installs: [Install] = []
        for i in 0..<300 { // < 500 floor
            installs.append(Install(id: "i\(i)", booted: true,
                                    unlocked: i < 100 ? ["climb_first_clear"] : []))
        }
        let rows = SyntheticRollup.run(Cohort(installs: installs),
                                       now: nowPast30Days, launchAt: launchLongAgo)
        let index = TrophyRarityIndex(rows: rows)
        let engine = try makeEngine()
        let model = TrophyRoomModel(engine: engine, rarity: index)

        let r = try XCTUnwrap(rarityRow(model, id: "climb_first_clear"))
        XCTAssertNil(r.rarityBand, "below the 500 floor → no band on any row.")
        XCTAssertEqual(r.rarityLabel, TrophyRoomModel.rarityPlaceholder)
    }

    // MARK: - Trophy Room test scaffolding (mirrors TrophyRarityTests)

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TrophyCohortRarityTests.\(UUID().uuidString)"
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

    private func rarityRow(_ model: TrophyRoomModel, id: String) -> TrophyRoomRow? {
        model.sections.flatMap(\.rows).first { $0.id == id }
    }

    private func bandLabel(_ model: TrophyRoomModel, id: String) -> String? {
        rarityRow(model, id: id)?.rarityBand?.displayName
    }
}

// ===========================================================================
// LIVE-SUPABASE VERIFICATION (Mac-gated post-migration — NOT run here)
// ===========================================================================
//
// S3-T7's acceptance also names a live-Supabase leg that CANNOT run under the
// S3 hard rule (no live project touch, no dev branch from an agent). It is a
// Mac-owned post-migration verification, to run AFTER Mac applies the S3-T1/T2
// migrations to a Supabase dev branch:
//
//   1. On a dev branch, seed public.trophy_unlocks with N synthetic installs
//      spanning the tier cutoffs (e.g. 620/1000 Common, 120/1000 Very Rare,
//      20/1000 Ultra Rare) and seed matching app_launch rows in public.events
//      so the denominator = N.
//   2. Set trophy_rollup_config.launch_at to > 30 days ago (open the day-gate);
//      run select rollup_trophy_stats(); confirm trophy_stats.rarity_ready flips
//      true only at denominator >= 500 AND >= 30 days, and each earned_count /
//      pct matches the seeded cohort (the queries in trophy-rollup.sql's
//      MANUAL-VERIFY block).
//   3. Delete a seeded player row and re-run the rollup: assert every
//      trophy_stats count is unchanged (cascade only touches player_trophies).
//   4. Point a debug build's SocialTrophyStatsBackend at the dev branch and
//      confirm the Trophy Room renders the SAME bands this suite asserts.
//   5. Tear the dev branch down.
//
// The MATH, the label cutoffs, the 500+30d flip, and the deletion invariant are
// all proven headlessly above; step 4 is the only thing the dev branch adds —
// that the deployed rollup's SQL agrees with SyntheticRollup here. Because both
// were authored against the same spec, a divergence there is a schema/rollup
// bug for Mac to catch at seeding time, before public launch.
