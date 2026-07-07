//
//  TrophyRarity.swift
//  RollAlong
//
//  S3-T4 — Rarity display wiring + cold-start rules
//  (docs/trophies/sprint-plan.md §2 S3-T4; design.md §3/§4). Everything the
//  Trophy Room needs to turn the server's `trophy_stats` aggregate into a
//  render-ready rarity band — as PURE, headlessly-testable logic (the S3 hard
//  rule: no live Supabase in tests, network behind a protocol mocked in tests).
//
//  WHAT LIVES HERE:
//   • `TrophyRarityBand` — the PSN 4-label vocabulary (Common / Rare /
//     Very Rare / Ultra Rare) and the ONE tested pct→band function
//     (`band(forFraction:)`). Cutoffs (design.md §3): Common ≥ 50 %,
//     Rare < 50 %, Very Rare < 15 %, Ultra Rare < 5 %.
//   • `TrophyStatRow` — the parsed `trophy_stats` row (keys match
//     docs/trophies/trophy-schema.sql + the rollup's `rarity_ready`).
//   • `TrophyRarityIndex` — a pure value type: `[TrophyStatRow]` → a
//     per-trophy resolved rarity, applying BOTH suppression rules in one
//     place so the View makes no policy decision:
//       – COLD-START: suppress ALL bands/percentages until the server says
//         the population is meaningful (`rarity_ready`, the rollup's gate =
//         denominator ≥ 500 installs AND ≥ 30 days post-launch — design.md
//         §3 / decision #6). Below the gate → placeholder, never 0 %/100 %.
//         Defensively re-checks the 500-install floor client-side too, so a
//         stale `rarity_ready = true` over a tiny denominator still suppresses.
//       – is_paused: a per-trophy DISPLAY kill-switch (design.md §9) — a
//         paused row hides its rarity slot entirely.
//   • `TrophyStatsBackend` — the network seam (a single anon GET of
//     `trophy_stats`), so the fetch/parse/gate logic is unit-tested against a
//     mock with ZERO live calls. The real `SocialTrophyStatsBackend` mirrors
//     the dependency-free PostgREST shape of SocialClient / SocialTrophyBackend
//     (anon key, no SDK).
//   • `TrophyRarityProvider` — the tiny ObservableObject the Trophy Room
//     observes; fetches once, caches the index, degrades to "no rarity" on any
//     failure (rarity is a garnish — a stale/unreachable stats table is never
//     an error, design.md §3).
//
//  BINDING Diamond rider (design.md §2 R2 / §3, RULED 2026-07-02): rarity NEVER
//  uses diamond iconography at any band — this file emits TEXT LABELS ONLY. The
//  diamond glyph belongs to the Diamond trophy GRADE alone (TrophyGradeStyle),
//  never to a rarity band. There is deliberately no glyph/color on a band here.
//
//  NEVER-MINT / PRIVACY (S3 hard rules): nothing here grants coins; the anon
//  rail carries no PII; `trophy_stats` is aggregates-only (counts / pct /
//  paused / ready), never a window into raw unlock rows.
//

import Foundation
import Combine

// ===========================================================================
// TrophyRarityBand — the PSN 4-label vocabulary + the tested pct→band map.
// ===========================================================================

/// The four community-standard rarity bands (design.md §3). Text labels only —
/// NO diamond iconography, no gem, no color (the binding Diamond rider): the
/// band is a word on the row, the raw percentage is a detail-view garnish.
enum TrophyRarityBand: String, CaseIterable, Equatable {
    case common     // earned by ≥ 50 %
    case rare       // earned by < 50 %
    case veryRare   // earned by < 15 %
    case ultraRare  // earned by < 5 %

    /// Player-facing label drawn on a Trophy Room row.
    var displayName: String {
        switch self {
        case .common:    return "Common"
        case .rare:      return "Rare"
        case .veryRare:  return "Very Rare"
        case .ultraRare: return "Ultra Rare"
        }
    }

    // MARK: - The ONE tested cutoff map

    /// Map an earned-by SHARE to a band. `fraction` is the `trophy_stats.pct`
    /// value — a 0…1 double (earned_count / denominator), NOT a 0…100 percent.
    ///
    /// Cutoffs are on PERCENT (design.md §3) applied to `fraction * 100`, so
    /// the boundaries land exactly where the design table says:
    ///   • ≥ 50 %  → Common
    ///   • < 50 %  → Rare
    ///   • < 15 %  → Very Rare
    ///   • < 5 %   → Ultra Rare
    /// Boundary rule (inclusive lower edge of the RARER-side comparison): the
    /// cutoff value itself belongs to the LESS-rare band — exactly 50 % is
    /// Common, exactly 15 % is Rare, exactly 5 % is Very Rare (a trophy at the
    /// edge is never bumped to the rarer label). Tested at 49.9/50, 14.9/15,
    /// 4.9/5.
    ///
    /// The `fraction` is clamped to 0…1 defensively; the schema already
    /// guarantees `pct ∈ [0,1]`, but a clamp keeps a malformed row from
    /// mislabeling.
    static func band(forFraction fraction: Double) -> TrophyRarityBand {
        let pct = min(max(fraction, 0), 1) * 100
        if pct < 5  { return .ultraRare }
        if pct < 15 { return .veryRare }
        if pct < 50 { return .rare }
        return .common
    }
}

// ===========================================================================
// TrophyStatRow — one parsed `trophy_stats` aggregate row.
// ===========================================================================

/// A single `trophy_stats` row as fetched over the anon rail. Keys match
/// docs/trophies/trophy-schema.sql (trophy_stats) + the rollup's added
/// `rarity_ready` column (docs/trophies/trophy-rollup.sql). Aggregates ONLY —
/// there is deliberately no unlock-row field to decode (the table holds none).
struct TrophyStatRow: Decodable, Equatable {
    let trophy_id: String
    /// Distinct installs that unlocked this trophy (the numerator).
    let earned_count: Int
    /// Distinct install UUIDs at rollup time (the shared-rail denominator).
    let denominator: Int
    /// Precomputed earned_count / denominator, 0…1 (0 when denominator = 0).
    let pct: Double
    /// Per-trophy DISPLAY kill-switch (design.md §9) — hide this row's rarity.
    let is_paused: Bool
    /// Server cold-start gate (design.md §3 / decision #6): true only when the
    /// denominator ≥ min_installs AND ≥ min_days post-launch. The single flag
    /// the client reads to decide whether to render a band at all.
    let rarity_ready: Bool
}

// ===========================================================================
// TrophyRarityIndex — pure resolution of rows → per-trophy display, gated.
// ===========================================================================

/// A per-trophy resolved rarity, already gated for cold-start + is_paused, so
/// the View draws it without any policy. `band == nil` means "suppress the
/// rarity slot" (show the room's placeholder); `band != nil` carries the label
/// to draw on the row and the raw percent string for the detail view.
struct TrophyRarityDisplay: Equatable {
    /// The band to label the row with, or nil when suppressed (cold-start or
    /// paused) — nil renders the room's "—" placeholder, NEVER 0 %/100 %.
    let band: TrophyRarityBand?

    /// The raw percentage string for the DETAIL view only ("0.9%"), or nil
    /// when suppressed. Never drawn on a list row (design.md §3: label on
    /// rows, percentage on detail).
    let detailPercent: String?

    /// A fully-suppressed display (cold-start or paused or unknown trophy).
    static let suppressed = TrophyRarityDisplay(band: nil, detailPercent: nil)
}

/// Turns a fetched `[TrophyStatRow]` into a lookup of gated
/// `TrophyRarityDisplay` per trophy id. A plain value type built once from a
/// snapshot — all the suppression policy lives HERE, unit-tested headlessly.
struct TrophyRarityIndex: Equatable {

    /// The client-side install floor, mirrored from the rollup's
    /// `min_installs` default (design.md §3 / decision #6). Belt-and-suspenders
    /// against a stale `rarity_ready = true` over a tiny denominator: the
    /// server owns the authoritative gate (incl. the 30-day half the client
    /// can't see), but the client still refuses to render a band below this
    /// floor. The 30-day half is enforced by `rarity_ready` alone.
    static let minInstalls = 500

    private let byTrophy: [String: TrophyRarityDisplay]

    /// Empty index — every lookup returns `.suppressed`. The room's default
    /// before a fetch lands (and after any fetch failure).
    static let empty = TrophyRarityIndex(byTrophy: [:])

    private init(byTrophy: [String: TrophyRarityDisplay]) {
        self.byTrophy = byTrophy
    }

    /// Build the index from fetched rows, applying both suppression rules.
    init(rows: [TrophyStatRow]) {
        var map: [String: TrophyRarityDisplay] = [:]
        map.reserveCapacity(rows.count)
        for row in rows {
            map[row.trophy_id] = Self.resolve(row)
        }
        self.byTrophy = map
    }

    /// The gated display for a trophy. A trophy with no stats row yet (or after
    /// a failed fetch) is suppressed — never a fabricated 0 %.
    func display(for trophyID: String) -> TrophyRarityDisplay {
        byTrophy[trophyID] ?? .suppressed
    }

    /// The single place both suppression rules are applied (design.md §3/§9):
    ///   1. is_paused → suppress (per-trophy display kill-switch).
    ///   2. cold-start → suppress unless the server gate is open AND the
    ///      client-side install floor is met.
    /// Only past BOTH gates does a band get computed from `pct`.
    private static func resolve(_ row: TrophyStatRow) -> TrophyRarityDisplay {
        // (1) Paused trophies hide their rarity slot entirely.
        guard !row.is_paused else { return .suppressed }

        // (2) Cold-start: the server's ready flag is authoritative (it alone
        // knows the 30-day half); the client additionally refuses to render
        // below the install floor, so a stale/misconfigured ready-over-tiny-
        // denominator can never leak a noisy day-1 band.
        guard row.rarity_ready, row.denominator >= minInstalls else {
            return .suppressed
        }

        let band = TrophyRarityBand.band(forFraction: row.pct)
        return TrophyRarityDisplay(band: band, detailPercent: Self.percentString(row.pct))
    }

    /// Format a 0…1 fraction as a detail-view percent string, e.g. 0.009 →
    /// "0.9%". One decimal place; trailing ".0" trimmed so common shares read
    /// "62%" not "62.0%".
    static func percentString(_ fraction: Double) -> String {
        let pct = min(max(fraction, 0), 1) * 100
        let rounded = (pct * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))%"
        }
        return String(format: "%.1f%%", rounded)
    }
}

// ===========================================================================
// TrophyStatsBackend — the fetch seam (the ONLY thing that touches network).
// ===========================================================================

/// The single read S3-T4 performs: fetch every `trophy_stats` row over the
/// anon rail. Injected into `TrophyRarityProvider` so the fetch/parse/gate
/// logic is provable against a mock with no live Supabase (the S3 hard rule).
/// The real impl is `SocialTrophyStatsBackend`; tests use an in-memory double.
protocol TrophyStatsBackend: Sendable {
    /// Fetch all `trophy_stats` rows (anon SELECT — the table is the project's
    /// first anon-readable object, aggregates only). Throws on any non-2xx /
    /// transport / decode error so the provider degrades to "no rarity".
    func fetchStats() async throws -> [TrophyStatRow]
}

// ===========================================================================
// TrophyRarityProvider — the ObservableObject the Trophy Room observes.
// ===========================================================================

/// Fetches `trophy_stats` once, holds the gated `TrophyRarityIndex`, and
/// publishes it so the room re-renders with real bands when it lands. Its own
/// type (not on the engine / GameState) so a rarity fetch never re-renders
/// gameplay and the network seam stays injectable. Rarity is a garnish: any
/// failure leaves the index empty (every row shows the placeholder) and is
/// never surfaced as an error (design.md §3).
@MainActor
final class TrophyRarityProvider: ObservableObject {

    /// The current gated index; `.empty` until (and after any failed) fetch.
    @Published private(set) var index: TrophyRarityIndex = .empty

    /// Whether a fetch is in flight — coalesces a re-appear while loading.
    @Published private(set) var isLoading = false

    private let backend: TrophyStatsBackend
    private var hasLoaded = false

    /// `nonisolated` so a SwiftUI View can construct a default provider in a
    /// (nonisolated) `init` default argument. The init only stores a `Sendable`
    /// backend and seeds the `@Published` defaults — no main-actor state is
    /// touched. The actual fetch (`loadIfNeeded`) stays main-actor-isolated.
    nonisolated init(backend: TrophyStatsBackend = SocialTrophyStatsBackend()) {
        self.backend = backend
    }

    /// Fetch once (idempotent): the first call loads; later calls are no-ops
    /// unless `force` is set (a manual pull-to-refresh). Safe to call from
    /// `.task`/`.onAppear` on every room open — the cache is reused.
    func loadIfNeeded(force: Bool = false) async {
        guard force || (!hasLoaded && !isLoading) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let rows = try await backend.fetchStats()
            index = TrophyRarityIndex(rows: rows)
            hasLoaded = true
        } catch {
            // Garnish: a stale/unreachable stats table degrades to "no label",
            // never an error. Keep whatever index we had (empty on first fail).
        }
    }
}

// ===========================================================================
// SocialTrophyStatsBackend — the real PostgREST fetch (anon GET, no SDK).
//
// Mirrors SocialClient / SocialTrophyBackend: talks to PostgREST directly with
// the anon key. `trophy_stats` grants anon SELECT (RLS: read-only aggregate) —
// docs/trophies/trophy-schema.sql. Aggregates only; never a raw unlock row.
// ===========================================================================

struct SocialTrophyStatsBackend: TrophyStatsBackend {

    private static let projectURL = "https://mhwpcwauzvmtmuphtajs.supabase.co"

    /// Anon (public) JWT — safe to embed; RLS grants anon only SELECT on
    /// `trophy_stats` (aggregates only). Identical key to SocialTrophyBackend /
    /// AnalyticsClient (the same anonymous rail).
    private static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
        "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1od3Bjd2F1enZtdG11cGh0YWpzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAwMDI1MzMsImV4cCI6MjA5NTU3ODUzM30." +
        "dKtYkbLF43vLYiCMaxhurBT8rTqAMxuKuJ2z5mkXKsM"

    private let decoder = JSONDecoder()

    func fetchStats() async throws -> [TrophyStatRow] {
        // Select only the columns the client renders (aggregates); never the
        // (nonexistent) raw unlock rows. `updated_at` is intentionally omitted
        // — the client renders from a snapshot and doesn't show staleness.
        let query = "select=trophy_id,earned_count,denominator,pct,is_paused,rarity_ready"
        let urlString = "\(Self.projectURL)/rest/v1/trophy_stats?\(query)"
        guard let url = URL(string: urlString) else { throw SocialError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Self.anonKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SocialError.http(status: -1, body: "no HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw SocialError.http(status: http.statusCode,
                                   body: String(data: data, encoding: .utf8) ?? "")
        }
        do { return try decoder.decode([TrophyStatRow].self, from: data) }
        catch { throw SocialError.decoding(error) }
    }
}
