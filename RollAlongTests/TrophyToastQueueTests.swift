//
//  TrophyToastQueueTests.swift
//  RollAlongTests
//
//  S2-T1 acceptance (headless): the toast QUEUE's coalescing + run-active
//  gating, and the BINDING Diamond-disambiguation invariant, are all pure
//  model logic — proven here without ever instantiating a View
//  (docs/trophies/sprint-plan.md §2 S2-T1; design.md §6 / §2 R2).
//
//  Verified here:
//  • zero presentation while a run is active (never mid-run);
//  • N mid-run unlocks coalesce into ONE batched presentation at run end;
//  • overflow while a card is on screen coalesces into the next batch
//    (max 1 in-flight);
//  • double-fire de-dupe (a trophy never shows twice);
//  • batch copy is grade-side, never "cosmetic" (copy discipline);
//  • the Diamond GRADE glyph+color shares no iconography with the Diamond
//    BALL / Iconic cosmetic treatment.
//
//  The queue is `@MainActor`, so this case is too.
//

import XCTest
import SwiftUI
@testable import RollAlong

@MainActor
final class TrophyToastQueueTests: XCTestCase {

    // MARK: Fixtures

    /// Synthetic trophy definition — copy of the TrophyEngineTests builder
    /// so this case stands alone.
    private func makeTrophy(id: String,
                            tier: TrophyTier = .bronze,
                            title: String? = nil,
                            category: TrophyCategory = .climb) -> TrophyDefinition {
        TrophyDefinition(id: id,
                         title: title ?? "Title \(id)",
                         tier: tier,
                         category: category,
                         lockedDescription: "Do the thing.",
                         unlockedDescription: "You did the thing.",
                         isSecret: false,
                         criteria: TrophyCriteria(metric: .climbHighestUnlocked,
                                                  threshold: 1,
                                                  comparison: .greaterOrEqual,
                                                  requiredTrophyIDs: nil),
                         rewardID: nil,
                         addedInVersion: TrophyCatalog.launchVersion)
    }

    // MARK: - Never mid-run

    func testNoPresentationWhileRunActive() {
        let q = TrophyToastQueue()
        q.runDidStart()

        q.enqueue(makeTrophy(id: "a"))
        q.enqueue(makeTrophy(id: "b"))

        XCTAssertTrue(q.isRunActive)
        XCTAssertNil(q.presented, "A run in progress must never present a toast (design.md §6).")
        XCTAssertEqual(q.pendingCount, 2, "Mid-run unlocks accumulate in the buffer.")
    }

    // MARK: - Coalesced at run end

    func testMidRunUnlocksCoalesceIntoOneBatchAtRunEnd() {
        let q = TrophyToastQueue()
        q.runDidStart()

        q.enqueue(makeTrophy(id: "a", tier: .bronze))
        q.enqueue(makeTrophy(id: "b", tier: .gold))
        q.enqueue(makeTrophy(id: "c", tier: .silver))
        XCTAssertNil(q.presented)

        q.runDidEnd()

        let batch = try? XCTUnwrap(q.presented)
        XCTAssertNotNil(batch, "Run end flushes the buffer.")
        XCTAssertEqual(batch?.count, 3, "Three mid-run unlocks = ONE batch of three.")
        XCTAssertEqual(q.pendingCount, 0, "Buffer drained on flush.")
        // The batch escalates to its best grade (gold here).
        XCTAssertEqual(batch?.topTier, .gold)
    }

    func testSingleMidRunUnlockPresentsAloneAtRunEnd() {
        let q = TrophyToastQueue()
        q.runDidStart()
        q.enqueue(makeTrophy(id: "solo", tier: .diamond))
        q.runDidEnd()

        XCTAssertEqual(q.presented?.count, 1)
        XCTAssertEqual(q.presented?.topTier, .diamond)
    }

    // MARK: - Idle presents immediately

    func testUnlockOutsideRunPresentsImmediately() {
        let q = TrophyToastQueue()
        // No run active.
        q.enqueue(makeTrophy(id: "a"))
        XCTAssertNotNil(q.presented, "Outside a run, an unlock presents at once.")
        XCTAssertEqual(q.presented?.count, 1)
    }

    func testIdleUnlocksCoalesceWhileFirstStillShowing() {
        let q = TrophyToastQueue()
        q.enqueue(makeTrophy(id: "a"))            // presents
        XCTAssertEqual(q.presented?.count, 1)

        // Two more land while the first card is up — max 1 in-flight, so
        // these coalesce behind it.
        q.enqueue(makeTrophy(id: "b"))
        q.enqueue(makeTrophy(id: "c"))
        XCTAssertEqual(q.presented?.trophies.first?.id, "a",
                       "The on-screen batch is unchanged while it shows.")
        XCTAssertEqual(q.pendingCount, 2, "Overflow coalesced into the buffer.")

        // Dismiss the first — the two coalesced ones present as ONE batch.
        q.dismissPresented()
        XCTAssertEqual(q.presented?.count, 2, "Overflow surfaces as one coalesced batch.")
        XCTAssertEqual(q.pendingCount, 0)
    }

    // MARK: - Dismissal drains to empty

    func testDismissWithEmptyBufferClearsToNil() {
        let q = TrophyToastQueue()
        q.enqueue(makeTrophy(id: "a"))
        XCTAssertNotNil(q.presented)
        q.dismissPresented()
        XCTAssertNil(q.presented, "Nothing pending → dismiss clears the card.")
        XCTAssertEqual(q.pendingCount, 0)
    }

    // MARK: - De-dupe (double fire)

    func testDoubleFireNeverShowsTrophyTwice() {
        let q = TrophyToastQueue()
        q.runDidStart()
        q.enqueue(makeTrophy(id: "dupe"))
        q.enqueue(makeTrophy(id: "dupe"))       // same id again
        q.enqueue([makeTrophy(id: "dupe"), makeTrophy(id: "fresh")])
        q.runDidEnd()

        XCTAssertEqual(q.presented?.count, 2, "The duplicate id is collapsed.")
        let ids = Set(q.presented?.trophies.map(\.id) ?? [])
        XCTAssertEqual(ids, ["dupe", "fresh"])
    }

    func testUnlockAlreadyOnScreenIsNotRePresented() {
        let q = TrophyToastQueue()
        q.enqueue(makeTrophy(id: "a"))          // now on screen
        q.enqueue(makeTrophy(id: "a"))          // same trophy fires again
        XCTAssertEqual(q.pendingCount, 0,
                       "An id already showing does not re-queue.")
    }

    // MARK: - Empty enqueue is a no-op

    func testEmptyEnqueueDoesNothing() {
        let q = TrophyToastQueue()
        q.enqueue([])
        XCTAssertNil(q.presented)
        XCTAssertEqual(q.pendingCount, 0)
    }

    // MARK: - runDidEnd with nothing pending

    func testRunEndWithNoUnlocksPresentsNothing() {
        let q = TrophyToastQueue()
        q.runDidStart()
        q.runDidEnd()
        XCTAssertNil(q.presented)
    }

    // MARK: - Batch copy (grade-side, never "cosmetic")

    func testSingleUnlockCopyIsGradeSide() {
        let batch = TrophyToastBatch(trophies: [makeTrophy(id: "x",
                                                           tier: .diamond,
                                                           title: "The Summit")])
        XCTAssertEqual(batch.headline, "The Summit")
        XCTAssertEqual(batch.subline, "Diamond trophy")
        // Copy discipline: the grade banner must never call itself "cosmetic".
        XCTAssertFalse(batch.subline.lowercased().contains("cosmetic"))
        XCTAssertFalse(batch.accessibilityAnnouncement.lowercased().contains("cosmetic"))
        XCTAssertTrue(batch.accessibilityAnnouncement.contains("Diamond"),
                      "VoiceOver announces the grade name (not color-only).")
        XCTAssertTrue(batch.accessibilityAnnouncement.contains("The Summit"),
                      "VoiceOver announces the trophy title.")
    }

    func testCoalescedBatchCopyTalliesGradesHighToLow() {
        let batch = TrophyToastBatch(trophies: [
            makeTrophy(id: "a", tier: .bronze),
            makeTrophy(id: "b", tier: .diamond),
            makeTrophy(id: "c", tier: .bronze)
        ])
        XCTAssertEqual(batch.headline, "3 trophies unlocked")
        // Diamond first (highest), then Bronze; no Silver/Gold entries.
        XCTAssertEqual(batch.subline, "1 Diamond · 2 Bronze")
        XCTAssertFalse(batch.subline.lowercased().contains("cosmetic"))
    }

    // MARK: - Top-tier escalation

    func testTopTierIsHighestGradeInBatch() {
        let batch = TrophyToastBatch(trophies: [
            makeTrophy(id: "a", tier: .silver),
            makeTrophy(id: "b", tier: .gold),
            makeTrophy(id: "c", tier: .bronze)
        ])
        XCTAssertEqual(batch.topTier, .gold)
    }

    // MARK: - BINDING Diamond disambiguation (design.md §2 R2)

    func testDiamondGradeGlyphAndColorDifferFromCosmeticDiamond() {
        let grade = TrophyGradeStyle.diamondGradeTreatment
        let cosmetic = TrophyGradeStyle.cosmeticDiamondTreatment

        // Different SF Symbol — the grade never borrows the cosmetic gem.
        XCTAssertNotEqual(grade.glyph, cosmetic.glyph)
        XCTAssertNotEqual(grade.glyph, "diamond.fill",
                          "The Diamond GRADE must not use diamond-gem iconography.")

        // Different accent color.
        XCTAssertFalse(
            TrophyGradeStyle.colorsApproximatelyEqual(grade.accent, cosmetic.accent),
            "The Diamond grade accent must differ from the cosmetic Diamond cyan.")

        // The convenience invariant used by the acceptance criteria.
        XCTAssertTrue(TrophyGradeStyle.diamondGradeIsDistinctFromCosmetic)
    }

    func testNoGradeUsesDiamondGemGlyph() {
        // No grade — Bronze/Silver/Gold/Diamond/Platinum — may render the
        // cosmetic diamond gem (design.md §2 R2 rider (b)/(a)).
        for tier in TrophyTier.allCases {
            XCTAssertNotEqual(TrophyGradeStyle.forTier(tier).glyph, "diamond.fill",
                              "\(tier.displayName) grade must not use the diamond gem glyph.")
        }
    }

    func testGradeGlyphsAreNotColorOnlyDistinguished() {
        // Grade is never color-only: at least one grade must carry a glyph
        // distinct from the medal set (Diamond's wreath), so the shape
        // differs, not just the hue (design.md §6 accessibility).
        XCTAssertNotEqual(TrophyGradeStyle.forTier(.diamond).glyph,
                          TrophyGradeStyle.forTier(.gold).glyph,
                          "Diamond's glyph shape differs from the medal grades.")
    }
}
