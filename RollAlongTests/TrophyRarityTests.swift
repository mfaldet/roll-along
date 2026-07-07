//
//  TrophyRarityTests.swift
//  RollAlongTests
//
//  S3-T4 acceptance (headless, NO live Supabase — the S3 hard rule): the
//  rarity DISPLAY logic is proven as pure functions + a mock-backed provider,
//  so the pct→band map, the cold-start gate, the is_paused kill-switch, the
//  fetch/parse, and the Trophy Room wiring are all unit-tested with ZERO
//  network calls (docs/trophies/sprint-plan.md §2 S3-T4; design.md §3/§9).
//
//  Verified here:
//  • band mapping at EVERY cutoff boundary (49.9/50, 14.9/15, 4.9/5) + clamps;
//  • cold-start suppression flips EXACTLY at the 500-install threshold and
//    honors the server `rarity_ready` gate (the 30-day half the client can't
//    see) — below either, the display suppresses, NEVER 0 %/100 %;
//  • is_paused hides a row's rarity slot;
//  • a fetched `[TrophyStatRow]` resolves through the index into gated
//    displays, and the Trophy Room row shows the band label (ready) or the
//    placeholder (suppressed);
//  • the provider degrades to an empty index on a backend failure (rarity is
//    a garnish — never an error).
//
//  The mapping/index are value types; the provider is @MainActor.
//

import XCTest
@testable import RollAlong

final class TrophyRarityTests: XCTestCase {

    // MARK: - (1) pct → band at the cutoff boundaries (design.md §3)

    /// `band(forFraction:)` takes a 0…1 fraction (the `trophy_stats.pct`
    /// column). Boundaries land on PERCENT: the cutoff value itself belongs to
    /// the LESS-rare band (≥ 50 Common, exactly 15 Rare, exactly 5 Very Rare).
    func testBandCommonBoundaryAt50() {
        XCTAssertEqual(TrophyRarityBand.band(forFraction: 0.50), .common,
                       "Exactly 50% is Common (≥ 50).")
        XCTAssertEqual(TrophyRarityBand.band(forFraction: 0.501), .common)
        XCTAssertEqual(TrophyRarityBand.band(forFraction: 1.0), .common)
    }

    func testBandRareJustUnder50() {
        XCTAssertEqual(TrophyRarityBand.band(forFraction: 0.499), .rare,
                       "49.9% is Rare (< 50).")
        XCTAssertEqual(TrophyRarityBand.band(forFraction: 0.30), .rare)
    }

    func testBandRareBoundaryAt15() {
        XCTAssertEqual(TrophyRarityBand.band(forFraction: 0.15), .rare,
                       "Exactly 15% is Rare, not Very Rare (< 15 is the cutoff).")
        XCTAssertEqual(TrophyRarityBand.band(forFraction: 0.1501), .rare)
    }

    func testBandVeryRareJustUnder15() {
        XCTAssertEqual(TrophyRarityBand.band(forFraction: 0.149), .veryRare,
                       "14.9% is Very Rare (< 15).")
        XCTAssertEqual(TrophyRarityBand.band(forFraction: 0.10), .veryRare)
    }

    func testBandVeryRareBoundaryAt5() {
        XCTAssertEqual(TrophyRarityBand.band(forFraction: 0.05), .veryRare,
                       "Exactly 5% is Very Rare, not Ultra Rare (< 5 is the cutoff).")
        XCTAssertEqual(TrophyRarityBand.band(forFraction: 0.0501), .veryRare)
    }

    func testBandUltraRareJustUnder5() {
        XCTAssertEqual(TrophyRarityBand.band(forFraction: 0.049), .ultraRare,
                       "4.9% is Ultra Rare (< 5).")
        XCTAssertEqual(TrophyRarityBand.band(forFraction: 0.009), .ultraRare)
        XCTAssertEqual(TrophyRarityBand.band(forFraction: 0.0), .ultraRare,
                       "0% (a just-launched trophy that passed the gate) is Ultra Rare.")
    }

    func testBandClampsOutOfRangeFractions() {
        // The schema guarantees pct ∈ [0,1]; the clamp is defensive.
        XCTAssertEqual(TrophyRarityBand.band(forFraction: 1.5), .common)
        XCTAssertEqual(TrophyRarityBand.band(forFraction: -0.2), .ultraRare)
    }

    func testBandDisplayNamesAreThePSNVocabulary() {
        XCTAssertEqual(TrophyRarityBand.common.displayName, "Common")
        XCTAssertEqual(TrophyRarityBand.rare.displayName, "Rare")
        XCTAssertEqual(TrophyRarityBand.veryRare.displayName, "Very Rare")
        XCTAssertEqual(TrophyRarityBand.ultraRare.displayName, "Ultra Rare")
    }

    func testPercentStringTrimsWholeNumbersAndKeepsOneDecimal() {
        XCTAssertEqual(TrophyRarityIndex.percentString(0.62), "62%")
        XCTAssertEqual(TrophyRarityIndex.percentString(0.009), "0.9%")
        XCTAssertEqual(TrophyRarityIndex.percentString(0.153), "15.3%")
        XCTAssertEqual(TrophyRarityIndex.percentString(1.0), "100%")
    }

    // MARK: - Row builder

    /// A `trophy_stats` row with sensible defaults, overridable per test.
    private func statRow(id: String = "t1",
                         earned: Int = 300,
                         denominator: Int = 1000,
                         pct: Double = 0.30,
                         paused: Bool = false,
                         ready: Bool = true) -> TrophyStatRow {
        TrophyStatRow(trophy_id: id,
                      earned_count: earned,
                      denominator: denominator,
                      pct: pct,
                      is_paused: paused,
                      rarity_ready: ready)
    }

    // MARK: - (2) Cold-start suppression flips at the 500-install threshold

    func testColdStartSuppressesBelow500Installs() {
        // Server said ready, but the client floor (500) is not met → suppress.
        let idx = TrophyRarityIndex(rows: [statRow(denominator: 499, ready: true)])
        let d = idx.display(for: "t1")
        XCTAssertNil(d.band, "Below 500 installs → no band, never a fabricated 0%.")
        XCTAssertNil(d.detailPercent)
    }

    func testColdStartGateOpensExactlyAt500Installs() {
        // Exactly at the floor AND server-ready → a band appears.
        let idx = TrophyRarityIndex(rows: [statRow(denominator: 500, pct: 0.30, ready: true)])
        let d = idx.display(for: "t1")
        XCTAssertEqual(d.band, .rare, "At exactly 500 installs the gate opens.")
        XCTAssertEqual(d.detailPercent, "30%")
    }

    func testColdStartHonorsServerReadyGate() {
        // Enough installs client-side, but the server's 30-day half is still
        // closed (rarity_ready = false) → suppress. The server flag is
        // authoritative for the half the client can't compute.
        let idx = TrophyRarityIndex(rows: [statRow(denominator: 100_000, ready: false)])
        XCTAssertNil(idx.display(for: "t1").band,
                     "rarity_ready = false suppresses even over a huge population.")
    }

    func testReadyAndAbove500RendersTheBand() {
        let idx = TrophyRarityIndex(rows: [
            statRow(id: "u", denominator: 5000, pct: 0.02, ready: true)
        ])
        let d = idx.display(for: "u")
        XCTAssertEqual(d.band, .ultraRare)
        XCTAssertEqual(d.detailPercent, "2%")
    }

    // MARK: - (3) is_paused hides the rarity slot

    func testPausedTrophySuppressesRarity() {
        // Fully past the cold-start gate, but paused → the display kill-switch
        // hides the slot (design.md §9).
        let idx = TrophyRarityIndex(rows: [
            statRow(denominator: 10_000, pct: 0.30, paused: true, ready: true)
        ])
        let d = idx.display(for: "t1")
        XCTAssertNil(d.band, "A paused trophy hides its rarity slot.")
        XCTAssertNil(d.detailPercent)
    }

    // MARK: - Unknown trophy → suppressed (never a fabricated 0%)

    func testUnknownTrophyIsSuppressed() {
        let idx = TrophyRarityIndex(rows: [statRow(id: "known", ready: true)])
        XCTAssertEqual(idx.display(for: "not_in_stats"), .suppressed,
                       "A trophy with no stats row shows the placeholder, not 0%.")
    }

    func testEmptyIndexSuppressesEverything() {
        XCTAssertEqual(TrophyRarityIndex.empty.display(for: "anything"), .suppressed)
    }

    // MARK: - (4) Fetch/parse via a mock backend (NO live Supabase)

    private struct MockStatsBackend: TrophyStatsBackend {
        let rows: [TrophyStatRow]
        let fail: Bool
        struct Boom: Error {}
        func fetchStats() async throws -> [TrophyStatRow] {
            if fail { throw Boom() }
            return rows
        }
    }

    @MainActor
    func testProviderLoadsAndGatesFetchedRows() async {
        let backend = MockStatsBackend(rows: [
            statRow(id: "a", denominator: 1000, pct: 0.60, ready: true),   // Common
            statRow(id: "b", denominator: 1000, pct: 0.03, ready: true),   // Ultra Rare
            statRow(id: "c", denominator: 499,  pct: 0.03, ready: true),   // below floor → suppressed
            statRow(id: "d", denominator: 1000, pct: 0.30, paused: true, ready: true), // paused
        ], fail: false)
        let provider = TrophyRarityProvider(backend: backend)

        await provider.loadIfNeeded()

        XCTAssertEqual(provider.index.display(for: "a").band, .common)
        XCTAssertEqual(provider.index.display(for: "b").band, .ultraRare)
        XCTAssertNil(provider.index.display(for: "c").band, "below-floor suppressed")
        XCTAssertNil(provider.index.display(for: "d").band, "paused suppressed")
    }

    @MainActor
    func testProviderDegradesToEmptyOnFailure() async {
        let provider = TrophyRarityProvider(backend: MockStatsBackend(rows: [], fail: true))
        await provider.loadIfNeeded()
        // A failed fetch keeps the empty index — no crash, no error surface.
        XCTAssertEqual(provider.index.display(for: "x"), .suppressed)
    }

    @MainActor
    func testProviderLoadIsIdempotentUntilForced() async {
        final class CountingBackend: TrophyStatsBackend, @unchecked Sendable {
            private(set) var calls = 0
            func fetchStats() async throws -> [TrophyStatRow] { calls += 1; return [] }
        }
        let backend = CountingBackend()
        let provider = TrophyRarityProvider(backend: backend)

        await provider.loadIfNeeded()
        await provider.loadIfNeeded()   // cached → no second fetch
        XCTAssertEqual(backend.calls, 1, "loadIfNeeded caches after the first success.")

        await provider.loadIfNeeded(force: true)
        XCTAssertEqual(backend.calls, 2, "force re-fetches.")
    }

    func testStatRowDecodesFromServerJSON() throws {
        // The exact column shape the anon GET returns (trophy-schema.sql +
        // the rollup's rarity_ready).
        let json = """
        [{"trophy_id":"climb_first_clear","earned_count":812,"denominator":1000,
          "pct":0.812,"is_paused":false,"rarity_ready":true}]
        """.data(using: .utf8)!
        let rows = try JSONDecoder().decode([TrophyStatRow].self, from: json)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].trophy_id, "climb_first_clear")
        XCTAssertEqual(rows[0].pct, 0.812, accuracy: 1e-9)
        XCTAssertTrue(rows[0].rarity_ready)
        XCTAssertFalse(rows[0].is_paused)
    }

    // MARK: - (5) Trophy Room wiring: band on rows, placeholder when suppressed

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TrophyRarityTests.\(UUID().uuidString)"
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

    private func row(_ model: TrophyRoomModel, id: String) -> TrophyRoomRow? {
        model.sections.flatMap(\.rows).first { $0.id == id }
    }

    func testRoomShowsPlaceholderWithEmptyRarityIndex() throws {
        // Default (.empty) index → every row keeps the "—" placeholder.
        let engine = try makeEngine()
        let model = TrophyRoomModel(engine: engine)
        let r = try XCTUnwrap(row(model, id: "climb_first_clear"))
        XCTAssertEqual(r.rarityLabel, TrophyRoomModel.rarityPlaceholder)
        XCTAssertNil(r.rarityBand)
        XCTAssertNil(r.rarityDetailPercent)
    }

    func testRoomShowsBandLabelWhenGateOpen() throws {
        let engine = try makeEngine()
        let idx = TrophyRarityIndex(rows: [
            TrophyStatRow(trophy_id: "climb_first_clear", earned_count: 120,
                          denominator: 1000, pct: 0.12, is_paused: false, rarity_ready: true)
        ])
        let model = TrophyRoomModel(engine: engine, rarity: idx)
        let r = try XCTUnwrap(row(model, id: "climb_first_clear"))
        XCTAssertEqual(r.rarityBand, .veryRare)
        XCTAssertEqual(r.rarityLabel, "Very Rare", "The row draws the band LABEL, not a percent.")
        XCTAssertEqual(r.rarityDetailPercent, "12%", "Raw percent is carried for the detail view only.")
        // The a11y label speaks the band.
        XCTAssertTrue(r.accessibilityLabel.contains("Very Rare rarity"))
    }

    func testRoomSuppressesPausedTrophyToPlaceholder() throws {
        let engine = try makeEngine()
        let idx = TrophyRarityIndex(rows: [
            TrophyStatRow(trophy_id: "climb_first_clear", earned_count: 120,
                          denominator: 1000, pct: 0.12, is_paused: true, rarity_ready: true)
        ])
        let model = TrophyRoomModel(engine: engine, rarity: idx)
        let r = try XCTUnwrap(row(model, id: "climb_first_clear"))
        XCTAssertNil(r.rarityBand)
        XCTAssertEqual(r.rarityLabel, TrophyRoomModel.rarityPlaceholder)
        XCTAssertFalse(r.accessibilityLabel.contains("rarity"),
                       "A suppressed row never speaks a rarity band.")
    }

    func testRoomSuppressesColdStartToPlaceholder() throws {
        let engine = try makeEngine()
        let idx = TrophyRarityIndex(rows: [
            TrophyStatRow(trophy_id: "climb_first_clear", earned_count: 5,
                          denominator: 100, pct: 0.05, is_paused: false, rarity_ready: false)
        ])
        let model = TrophyRoomModel(engine: engine, rarity: idx)
        let r = try XCTUnwrap(row(model, id: "climb_first_clear"))
        XCTAssertNil(r.rarityBand, "Cold-start suppresses — never a 5% day-1 band.")
        XCTAssertEqual(r.rarityLabel, TrophyRoomModel.rarityPlaceholder)
    }
}
