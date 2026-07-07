//
//  TrophyPublicShowcase.swift
//  RollAlong
//
//  S3-T9 — the CURATED PUBLIC trophy showcase
//  (docs/trophies/sprint-plan.md §2 S3-T9; design.md §7 "Profile showcase" /
//  decision #10, D6 ruled 2026-07-07: on for signed-in, Settings toggle).
//
//  This is the small, public-facing projection of a signed-in player's trophy
//  ledger that renders on ANOTHER player's PublicProfileView — filling the
//  S2-T4 seam. It is deliberately NOT the raw unlock set (`player_trophies`):
//  a viewer opening someone else's profile has no business enumerating their
//  dozens of unlock rows. The showcase is a handful of numbers plus up to 3
//  curated ids, stored in the `public.player_showcase` row
//  (docs/trophies/trophy-schema.sql) — a table a signed-out viewer may read but
//  only the owner may write.
//
//  Two directions:
//
//  • BUILD (owner → server): `TrophyPublicShowcase(engine:)` distils the local
//    engine ledger into per-grade counts + earned/total + capstone flag + up to
//    3 showcased ids. The default showcased set is the RAREST EARNED trophies
//    (design.md §7 "default = rarest earned"): grade IS the rarity vocabulary
//    (§2/§6), so rarest = highest tier first (Platinum ▸ Diamond ▸ … ▸ Bronze),
//    ties broken by most-recent unlock then catalog order — fully offline and
//    deterministic (trophy_stats rarity is cold-start-suppressed and not
//    reliable for a personal "my rarest" pick). A player-chosen override is
//    honored when supplied (still capped at 3, unearned/unknown ids dropped).
//
//  • RENDER (server → viewer): `TrophyPublicShowcase` decodes straight from the
//    `player_showcase` row, so PublicProfileView draws grade chips + the
//    showcased-id strip from the fetched projection with no local-ledger read
//    (reading the VIEWER's own engine on someone else's profile would be a
//    fake — the seam's whole point).
//
//  NEVER-MINT / PRIVACY (D1 + S3 privacy posture): a pure display projection —
//  reads the trophy ledger, writes nothing to the economy, carries no PII, and
//  exposes counts + at-most-3 ids, never the full unlock history.
//
//  BINDING Diamond riders (design.md §2 R2): grade glyph/color for any rendered
//  entry come from the single `TrophyGradeStyle.forTier` source (the violet
//  wreath), NEVER the cosmetic gem. The render entry reuses `TrophyShowcaseEntry`
//  so that discipline is inherited, not re-implemented.
//

import Foundation

// MARK: - The curated public showcase (owner build + viewer render)

/// A signed-in player's public trophy showcase: per-grade earned counts, the
/// overall earned/total, the capstone flag, and up to 3 curated trophy ids.
/// Value type — cheap to diff, trivial to assert, and `Codable` against the
/// `public.player_showcase` columns so the same struct is the sync payload and
/// the render model.
struct TrophyPublicShowcase: Equatable {

    /// Hard cap on curated ids (design.md §7 "up to 3 showcased trophy ids").
    static let showcaseIDCap = 3

    /// Up to 3 curated trophy ids, already ordered (rarest first for the
    /// default; the player's order for an override). Never more than
    /// `showcaseIDCap`.
    let showcasedIDs: [String]

    /// Per-grade EARNED counts, keyed by tier.
    let gradeCounts: [TrophyTier: Int]

    /// Overall latched / catalog total.
    let earned: Int
    let total: Int

    /// Whether the Platinum capstone is earned.
    let capstone: Bool

    // MARK: Grade-count accessors (wire columns)

    var bronzeCount:   Int { gradeCounts[.bronze]   ?? 0 }
    var silverCount:   Int { gradeCounts[.silver]   ?? 0 }
    var goldCount:     Int { gradeCounts[.gold]     ?? 0 }
    var diamondCount:  Int { gradeCounts[.diamond]  ?? 0 }
    var platinumCount: Int { gradeCounts[.platinum] ?? 0 }

    /// True when the player has earned nothing — the profile shows an empty
    /// state instead of a strip. A showcase with no earned trophies is never
    /// pushed (the sync service treats it as "nothing to show").
    var isEmpty: Bool { earned == 0 }

    /// Completion as a whole-number percent, 0…100 (rounded); 0 for an empty
    /// catalog.
    var completionPercent: Int {
        total > 0 ? Int((Double(earned) / Double(total) * 100).rounded()) : 0
    }

    // MARK: - Build from the local engine (owner side)

    /// Distil the engine's latched ledger into the public projection.
    ///
    /// - Parameters:
    ///   - engine: the local `TrophyEngine` (the owner's ledger). Read via its
    ///     public API only (`catalog`, `isUnlocked`, `unlockDate(for:)`).
    ///   - chosenIDs: an optional player-curated order. When non-empty it wins
    ///     over the rarest-earned default; either way the result is filtered to
    ///     EARNED, deduped, and capped at `showcaseIDCap` (an unearned or
    ///     unknown id fabricates nothing). When empty (the D6 default), the
    ///     showcase auto-picks the rarest-earned trophies.
    init(engine: TrophyEngine, chosenIDs: [String] = []) {
        let catalog = engine.catalog

        var earnedCount = 0
        var counts: [TrophyTier: Int] = [:]
        for tier in TrophyTier.allCases { counts[tier] = 0 }

        // (tier, unlockDate, catalogIndex, id) for every EARNED trophy — the raw
        // material for both the counts and the rarest-earned default.
        var earnedTrophies: [(tier: TrophyTier, date: Date, index: Int, id: String)] = []

        for (idx, trophy) in catalog.trophies.enumerated() {
            guard engine.isUnlocked(trophy.id) else { continue }
            earnedCount += 1
            counts[trophy.tier, default: 0] += 1
            let stamp = engine.unlockDate(for: trophy.id) ?? TrophyEngine.legacyUnlockDate
            earnedTrophies.append((trophy.tier, stamp, idx, trophy.id))
        }

        self.earned = earnedCount
        self.total = catalog.trophies.count
        self.gradeCounts = counts
        self.capstone = catalog.trophies.contains {
            $0.tier.isCapstone && engine.isUnlocked($0.id)
        }

        // --- Curated ids ---------------------------------------------------
        let earnedIDSet = Set(earnedTrophies.map(\.id))

        // A player override (when supplied): keep only earned+known ids, in the
        // player's order, deduped, capped. Fabricates nothing.
        let override: [String] = {
            guard !chosenIDs.isEmpty else { return [] }
            var seen = Set<String>()
            var out: [String] = []
            for id in chosenIDs where earnedIDSet.contains(id) && !seen.contains(id) {
                out.append(id); seen.insert(id)
                if out.count == Self.showcaseIDCap { break }
            }
            return out
        }()

        if !override.isEmpty {
            self.showcasedIDs = override
        } else {
            // Default = RAREST EARNED (design.md §7). Grade IS the rarity
            // vocabulary, so sort by tier DESC (Platinum ▸ … ▸ Bronze), then by
            // most-recent unlock, then by catalog order for a deterministic,
            // testable pick. Take the top `showcaseIDCap`.
            let ranked = earnedTrophies.sorted { a, b in
                if a.tier != b.tier { return a.tier > b.tier }   // rarer grade first
                if a.date != b.date { return a.date > b.date }   // more recent first
                return a.index < b.index                          // stable tiebreak
            }
            self.showcasedIDs = ranked.prefix(Self.showcaseIDCap).map(\.id)
        }
    }

    /// Direct init (the decode / test path).
    init(showcasedIDs: [String],
         gradeCounts: [TrophyTier: Int],
         earned: Int,
         total: Int,
         capstone: Bool) {
        self.showcasedIDs = Array(showcasedIDs.prefix(Self.showcaseIDCap))
        self.gradeCounts = gradeCounts
        self.earned = earned
        self.total = total
        self.capstone = capstone
    }
}

// MARK: - Wire row (keys match public.player_showcase columns)

extension TrophyPublicShowcase {

    /// The `player_showcase` row shape — one struct for both the upsert body and
    /// the fetch decode. Column names match docs/trophies/trophy-schema.sql.
    /// `player_id` is set on encode (the upsert) and ignored on decode (the
    /// viewer already knows whose profile it is).
    struct Row: Codable, Equatable {
        var player_id: String?
        var showcased_ids: [String]
        var bronze_count: Int
        var silver_count: Int
        var gold_count: Int
        var diamond_count: Int
        var platinum_count: Int
        var earned_count: Int
        var total_count: Int
        var capstone: Bool
    }

    /// Encode to the upsert row for `playerID` (owner → server).
    func row(playerID: UUID) -> Row {
        Row(player_id: playerID.uuidString,
            showcased_ids: showcasedIDs,
            bronze_count: bronzeCount,
            silver_count: silverCount,
            gold_count: goldCount,
            diamond_count: diamondCount,
            platinum_count: platinumCount,
            earned_count: earned,
            total_count: total,
            capstone: capstone)
    }

    /// Rebuild the projection from a fetched row (server → viewer). Grade counts
    /// are non-negative; `total`/`earned` come straight off the row.
    init(row: Row) {
        self.init(
            showcasedIDs: row.showcased_ids,
            gradeCounts: [
                .bronze:   max(0, row.bronze_count),
                .silver:   max(0, row.silver_count),
                .gold:     max(0, row.gold_count),
                .diamond:  max(0, row.diamond_count),
                .platinum: max(0, row.platinum_count),
            ],
            earned: max(0, row.earned_count),
            total: max(0, row.total_count),
            capstone: row.capstone)
    }
}
