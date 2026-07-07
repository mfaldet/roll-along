//
//  TrophyShowcaseModel.swift
//  RollAlong
//
//  S2-T4 — the Profile Trophy card's testable data model
//  (docs/trophies/sprint-plan.md §2 S2-T4; design.md §7 "Profile showcase").
//
//  This replaces the retired view-private 11-badge wall on ProfileView
//  (BadgeDef/allBadges) — a hand-rolled list that derived "badges" LIVE from
//  regressable GameState stats (highestUnlocked, totalStars, streaks, coins,
//  bundles) and even pay-gated one badge ("Unlimited Power" → the $-gated
//  `unlimitedLives` IAP, internal-economy.md §4). Those are gone. The Profile
//  card now reflects the LATCHED trophy ledger from `TrophyEngine`, so an
//  earned trophy is a permanent, never-revoked showpiece.
//
//  What ships here:
//
//  • `TrophyShowcaseEntry` — one EARNED trophy resolved for display: id,
//    real title + celebration copy, grade glyph/accent (from the single
//    `TrophyGradeStyle` source of truth), and the engine's unlock timestamp.
//    Only earned trophies ever become entries, so a secret trophy in the
//    showcase is — by construction — already revealed (no masking needed).
//
//  • `TrophyShowcaseModel` — a PURE, View-free value type built from a
//    `TrophyEngine` snapshot (the ENGINE only, never GameState). It computes
//    the profile card's summary (total earned / catalog total, per-grade
//    counts, capstone status) and an ordered `showcase` — the handful of
//    trophies the card puts on stage: PINNED first (the S2-T7 pin seam),
//    then most-recently-earned. Every rule here is unit-testable headlessly
//    (S2-T4 acceptance), with no View instantiated.
//
//  RATCHET (design.md §4 / S0): the engine's ledger is latched — it does not
//  derive from `resetProgress()` / `liquidateCoinCosmetics()` / `liveStreak`.
//  So an entry that appears here STAYS after a progress reset or a cosmetic
//  liquidation. S2-T4's acceptance test drives exactly that.
//
//  BINDING Diamond riders (design.md §2 R2, RULED 2026-07-02): the Diamond
//  trophy GRADE's glyph/color come from `TrophyGradeStyle.forTier` (the
//  violet `laurel.leading` wreath) — NEVER the cyan `diamond.fill` gem the
//  Diamond BALL / Iconic cosmetic tier uses. Reused here so the two Diamonds
//  cannot blur; copy is grade-side only ("Diamond", never "Diamond cosmetic").
//
//  NEVER-MINT (D1, 2026-07-02): nothing here grants coins. The Profile card
//  is display-only; it reads the trophy ledger and never writes the economy.
//
//  Points are explicitly NOT v1 (design.md §2 ships grades + capstone only):
//  the card shows grade counts + completion, never a points level.
//

import SwiftUI

// MARK: - One earned trophy, resolved for the Profile showcase

/// A single EARNED trophy the Profile card can draw. Value type: cheap to
/// diff, trivial to assert. Built only from unlocked trophies, so its copy is
/// always the real (revealed) copy — a masked "???" never reaches the card.
struct TrophyShowcaseEntry: Identifiable, Equatable {

    /// The trophy's frozen id (also the SwiftUI identity).
    let id: String
    let tier: TrophyTier

    /// Real display title (always revealed — entries are earned).
    let title: String
    /// Celebration copy shown under the title.
    let subtitle: String

    /// First-unlock timestamp from the engine's ledger.
    let unlockDate: Date

    /// True when this is a grandfathered backfill unlock stamped at the
    /// `legacyUnlockDate` sentinel (pre-trophies) — the card labels it
    /// distinctly instead of printing the epoch date.
    var isLegacyUnlock: Bool { unlockDate == TrophyEngine.legacyUnlockDate }

    /// Grade glyph (SF Symbol) — from the single `TrophyGradeStyle` source so
    /// the Diamond grade never borrows the cosmetic gem (design.md §2 R2).
    var gradeGlyph: String { TrophyGradeStyle.forTier(tier).glyph }
    /// Grade accent color — same single source of truth.
    var gradeAccent: Color { TrophyGradeStyle.forTier(tier).accent }
    /// Player-facing grade name ("Bronze" … "Platinum").
    var gradeName: String { tier.displayName }

    /// One-line VoiceOver label: name, grade, and when it was earned.
    var accessibilityLabel: String {
        var parts = [title, "\(gradeName) grade"]
        if isLegacyUnlock {
            parts.append("earned before trophies launched")
        } else {
            parts.append("earned \(unlockDate.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - The testable Profile-card model

/// Turns a `TrophyEngine`'s latched ledger into the Profile Trophy card's
/// render-ready state: a summary (counts) + an ordered `showcase`. A plain
/// value type built from a snapshot of the engine's public reads — no
/// `@Published`, no View, no GameState — so the View re-derives it whenever
/// the engine publishes, and tests build it directly against a seeded engine
/// (S2-T4 acceptance).
struct TrophyShowcaseModel: Equatable {

    /// How many trophies the card stages at most. Small on purpose — the card
    /// is a teaser that links through to the full Trophy Room (S2-T3).
    static let showcaseLimit = 6

    /// Total trophies in the catalog.
    let total: Int
    /// Total latched (across every grade).
    let earned: Int

    /// Earned / total per grade, in ladder order (Bronze…Platinum). Every
    /// grade appears even at 0 earned so the card's grade strip is stable.
    let gradeCounts: [GradeCount]

    /// Whether the platinum capstone is earned — the card's crown highlight.
    let capstoneUnlocked: Bool

    /// The trophies the card puts on stage, already ordered: PINNED first (in
    /// the player's pin order — the S2-T7 seam), then the most-recently-earned
    /// of the rest, capped at `showcaseLimit`. Every entry is an EARNED trophy
    /// (so nothing masked ever appears).
    let showcase: [TrophyShowcaseEntry]

    struct GradeCount: Equatable, Identifiable {
        let tier: TrophyTier
        let earned: Int
        let total: Int
        var id: String { tier.rawValue }
        var gradeName: String { tier.displayName }
    }

    /// Completion as a 0…1 fraction (0 when the catalog is empty).
    var completionFraction: Double {
        total > 0 ? Double(earned) / Double(total) : 0
    }

    /// Completion as a whole-number percent, 0…100 (rounded).
    var completionPercent: Int {
        Int((completionFraction * 100).rounded())
    }

    /// True when the player has earned nothing yet — the card shows an
    /// empty-state prompt instead of a showcase strip.
    var isEmpty: Bool { earned == 0 }

    /// Build the model from the engine.
    ///
    /// Reads ONLY the engine's public API (`catalog`, `isUnlocked`,
    /// `unlockDate(for:)`) — never GameState. `pinnedIDs` is the S2-T7 pin
    /// seam: the persisted `ra_trophyPins` order, passed in by the caller.
    /// Until S2-T7 wires the pin UI, callers pass `[]` and the showcase is
    /// purely most-recently-earned. Unknown or unearned pin ids are ignored
    /// (a pin whose trophy was never earned, or was removed from the catalog,
    /// never fabricates an entry).
    init(engine: TrophyEngine, pinnedIDs: [String] = []) {
        let catalog = engine.catalog

        var earnedCount = 0
        var earnedByTier: [TrophyTier: Int] = [:]
        var totalByTier: [TrophyTier: Int] = [:]
        for tier in TrophyTier.allCases {
            earnedByTier[tier] = 0
            totalByTier[tier] = 0
        }

        // Resolve every EARNED trophy to an entry; tally grades over the whole
        // catalog. Keep entries keyed by id so the pin lookup is O(1).
        var entriesByID: [String: TrophyShowcaseEntry] = [:]
        // Catalog (authored) order index, the stable tiebreaker for entries
        // that share an unlock timestamp (esp. the legacy-backfill batch, all
        // stamped identically).
        var catalogIndex: [String: Int] = [:]

        for (idx, trophy) in catalog.trophies.enumerated() {
            catalogIndex[trophy.id] = idx
            totalByTier[trophy.tier, default: 0] += 1

            guard engine.isUnlocked(trophy.id) else { continue }
            earnedCount += 1
            earnedByTier[trophy.tier, default: 0] += 1

            // An earned trophy always carries a stamp (real or the legacy
            // sentinel); fall back to the sentinel defensively so a malformed
            // ledger can't drop an earned entry.
            let stamp = engine.unlockDate(for: trophy.id) ?? TrophyEngine.legacyUnlockDate
            entriesByID[trophy.id] = TrophyShowcaseEntry(
                id: trophy.id,
                tier: trophy.tier,
                title: trophy.title,
                subtitle: trophy.unlockedDescription,
                unlockDate: stamp)
        }

        self.total = catalog.trophies.count
        self.earned = earnedCount
        self.gradeCounts = TrophyTier.allCases
            .sorted()
            .map { tier in
                GradeCount(tier: tier,
                           earned: earnedByTier[tier] ?? 0,
                           total: totalByTier[tier] ?? 0)
            }
        self.capstoneUnlocked = catalog.trophies.contains {
            $0.tier.isCapstone && engine.isUnlocked($0.id)
        }

        // --- Showcase ordering -------------------------------------------
        // 1. Pinned entries first, in the player's pin order. Ignore pins that
        //    aren't earned (or aren't in the catalog) — they fabricate nothing.
        var ordered: [TrophyShowcaseEntry] = []
        var placed: Set<String> = []
        for id in pinnedIDs {
            guard let entry = entriesByID[id], !placed.contains(id) else { continue }
            ordered.append(entry)
            placed.insert(id)
        }

        // 2. Then the rest, most-recently-earned first. The legacy sentinel is
        //    the earliest possible Date, so backfilled unlocks naturally sink
        //    below real unlocks. Ties (same stamp) break by catalog order for
        //    a deterministic, testable result.
        let rest = entriesByID.values
            .filter { !placed.contains($0.id) }
            .sorted { a, b in
                if a.unlockDate != b.unlockDate { return a.unlockDate > b.unlockDate }
                return (catalogIndex[a.id] ?? 0) < (catalogIndex[b.id] ?? 0)
            }
        ordered.append(contentsOf: rest)

        self.showcase = Array(ordered.prefix(Self.showcaseLimit))
    }
}
