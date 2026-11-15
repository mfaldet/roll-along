//
//  TrophyRoomView.swift
//  RollAlong
//
//  S2-T3 — the Trophy Room screen + its testable data model
//  (docs/trophies/sprint-plan.md §2 S2-T3; design.md §7).
//
//  What ships here:
//
//  • `TrophyRoomModel` — a PURE, View-free data model that turns the
//    bundled `TrophyCatalog` + a `TrophyEngine`'s latched ledger into
//    render-ready rows grouped by content area, plus a header summary
//    (overall completion % + per-grade counts). It reads the ENGINE ONLY
//    (never GameState), so every rule below is unit-testable headlessly
//    (S2-T3 acceptance):
//      – locked / unlocked / progress state per trophy, from the engine;
//      – SECRET masking: a locked secret trophy leaks NO title /
//        description / criteria — it renders as "???" with a generic
//        "Hidden trophy" subtitle and progress is suppressed;
//      – overall completion % and per-grade counts;
//      – grouping + play-path section order (design.md §7).
//
//  • `TrophyRoomView` — the SwiftUI surface reading the model. Grouped,
//    scrollable, accessible (Dynamic-Type scalable fonts, per-row
//    `accessibilityLabel`, `@Environment(\.accessibilityReduceMotion)`
//    honored). Rarity is a SLOT rendering "—" until S3 feeds it (S3-T4).
//
//  BINDING Diamond riders (design.md §2 R2, RULED 2026-07-02): the Diamond
//  trophy GRADE's glyph/color come from `TrophyGradeStyle.forTier` (the
//  violet `laurel.leading` wreath) — NEVER the cyan `diamond.fill` gem the
//  Diamond BALL / Iconic cosmetic tier uses. This view reuses that single
//  source of truth so the disambiguation cannot drift; copy is grade-side
//  only ("Diamond", never "Diamond cosmetic").
//
//  NEVER-MINT (D1, 2026-07-02): nothing here grants coins. The Trophy Room
//  is display-only; it reads the trophy ledger and never writes the economy.
//
//  Points are explicitly NOT v1 (design.md §2 ships grades + capstone only):
//  the header shows grade counts + completion %, never a points level.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Section ordering (design.md §7 play-path)

extension TrophyCategory {

    /// Trophy Room section order along the common play path (design.md §7:
    /// The Climb → Challenge Tracks → Daily → Minigames → Collections →
    /// Economy → Social → Skill → Secret → Capstone). Lower sorts first.
    /// The catalog's own enum order already matches this, but pinning it
    /// here makes the room's grouping independent of enum edits and
    /// unit-testable.
    var roomSortOrder: Int {
        switch self {
        case .climb:            return 0
        case .challengeTracks:  return 1
        case .daily:            return 2
        case .minigamesArcade:  return 3
        case .minigamesPerGame: return 4
        case .cosmetics:        return 5
        case .economy:          return 6
        case .social:           return 7
        case .skillStyle:       return 8
        case .secretWhimsy:     return 9
        case .capstone:         return 10
        }
    }
}

// MARK: - Render-ready row + section

/// One trophy as the Trophy Room should draw it — already resolved for
/// lock state, progress, and secret masking, so the View draws data and
/// makes no policy decision. Value type: cheap to diff, trivial to assert.
struct TrophyRoomRow: Identifiable, Equatable {

    /// The trophy's frozen id (also the SwiftUI identity).
    let id: String
    let tier: TrophyTier
    let category: TrophyCategory

    /// Whether this trophy is latched in the engine's ledger.
    let isUnlocked: Bool

    /// Whether the trophy is a hidden/secret one AND still locked — i.e.
    /// its real copy must be withheld. Once unlocked, a secret trophy
    /// reveals fully and this is `false`.
    let isMasked: Bool

    /// Title to draw: the real title when visible, `"???"` when masked.
    let displayTitle: String

    /// Subtitle/description to draw: the locked objective (or unlocked
    /// celebration) when visible, a generic "Hidden trophy" line when
    /// masked — the real criteria text is NEVER placed here while masked.
    let displayDescription: String

    /// Fraction toward the threshold, 0…1, or nil when progress is not
    /// shown (unlocked → no bar; masked secret → suppressed so the bar
    /// can't leak "you're close"). The engine computes the number; the
    /// model decides whether to surface it.
    let progress: Double?

    /// First-unlock timestamp, or nil when locked / un-stamped.
    let unlockDate: Date?

    /// Rarity label slot AS DRAWN ON THE ROW: the PSN band label ("Common" …
    /// "Ultra Rare") once S3-T4's stats feed lands and the cold-start gate is
    /// open, otherwise the "—" placeholder. Suppressed to the placeholder
    /// whenever rarity is cold-started or the trophy is paused (design.md
    /// §3/§9). Text only — NEVER diamond iconography at any band (§2 R2).
    let rarityLabel: String

    /// The resolved band, or nil when rarity is suppressed (cold-start /
    /// paused / no stats row yet). The View draws `rarityLabel`; this is the
    /// structured value tests and a future detail view read.
    let rarityBand: TrophyRarityBand?

    /// The raw percentage string for a DETAIL view only ("0.9%"), or nil when
    /// suppressed. Deliberately NOT drawn on the list row — the label is the
    /// row's rarity, the percentage is a detail garnish (design.md §3).
    let rarityDetailPercent: String?

    /// Grade glyph (SF Symbol) — from the single `TrophyGradeStyle` source
    /// so the Diamond grade never borrows the cosmetic gem (design.md §2 R2).
    var gradeGlyph: String { TrophyGradeStyle.forTier(tier).glyph }
    /// Grade accent color — same single source of truth.
    var gradeAccent: Color { TrophyGradeStyle.forTier(tier).accent }

    /// The SF Symbol of the tile this trophy is drawn on (its own icon), or
    /// the grade glyph when the catalog has no tile layout.
    var tileIcon: String { TrophyIcon.name(forTrophyID: id) ?? gradeGlyph }

    /// Player-facing grade name ("Bronze" … "Platinum").
    var gradeName: String { tier.displayName }

    /// Whether this trophy can be PINNED as a chase target (S2-T7). Only a
    /// still-locked, non-masked trophy is a chase: an unlocked trophy has
    /// nothing left to chase, and a masked secret must never be surfaced as a
    /// pinnable objective (it would leak that it exists as a goal). The
    /// Trophy Room offers the pin control only when this is true.
    var isPinnable: Bool { !isUnlocked && !isMasked }

    /// One-line VoiceOver label: name, grade, and state. Never speaks the
    /// hidden title of a masked trophy (it uses `displayTitle` = "???").
    var accessibilityLabel: String {
        var parts: [String] = [displayTitle, "\(gradeName) grade"]
        if isUnlocked {
            parts.append("unlocked")
        } else if let progress, !isMasked {
            parts.append("\(Int((progress * 100).rounded())) percent complete")
        } else {
            parts.append("locked")
        }
        // Speak the rarity band when one is shown (suppressed → nothing to say,
        // and never the raw percent — that's a detail-view garnish).
        if let rarityBand {
            parts.append("\(rarityBand.displayName) rarity")
        }
        return parts.joined(separator: ", ")
    }
}

/// One category section of the room: its header title + the rows in it.
struct TrophyRoomSection: Identifiable, Equatable {
    let category: TrophyCategory
    let rows: [TrophyRoomRow]

    var id: String { category.rawValue }
    var title: String { category.displayName }

    /// Earned / total for the section's little "3/12" progress caption.
    var unlockedCount: Int { rows.filter(\.isUnlocked).count }
    var total: Int { rows.count }
}

// MARK: - Tiles (stacks and feats)

/// One tile as the Trophy Room draws it: a STACK (steps of one measure shown
/// as a single evolving tile) or a FEAT (a one-off trophy).  Display only —
/// each step is still its own trophy row with its own id, rarity and date.
struct TrophyRoomTile: Identifiable, Equatable {
    let id: String
    let kind: TrophyTile.Kind
    /// Stack name or feat title, already masked for a locked secret.
    let displayTitle: String
    let icon: String
    let fallbackIcon: String
    /// The tile's trophies, lowest step first (one for a feat).
    let steps: [TrophyRoomRow]
    /// Step names, index-for-index with `steps` ("Bronze I", "Silver II").
    let stepLabels: [String]

    var earnedCount: Int { steps.filter(\.isUnlocked).count }
    var isEarned: Bool { earnedCount > 0 }
    var isComplete: Bool { earnedCount == steps.count }
    /// A locked secret: title, icon and criteria all stay hidden.
    var isMasked: Bool { !steps.isEmpty && steps.allSatisfy(\.isMasked) }

    /// Index of the highest step earned, or nil when none is.
    var highestEarnedIndex: Int? { steps.lastIndex(where: \.isUnlocked) }

    /// The tier the tile wears: the highest step earned, else the first step.
    var displayTier: TrophyTier {
        if let i = highestEarnedIndex { return steps[i].tier }
        return steps.first?.tier ?? .bronze
    }

    /// The line under the title: the highest step earned for a stack
    /// ("Silver II"), the tier for a feat, "Locked" when nothing is earned.
    var caption: String {
        if isMasked { return "Secret" }
        switch kind {
        case .stack:
            guard let i = highestEarnedIndex else { return "Locked" }
            return stepLabels[i]
        case .feat:
            return steps.first?.gradeName ?? ""
        }
    }

    var accessibilityLabel: String {
        if isMasked { return "Hidden trophy, locked" }
        switch kind {
        case .stack:
            let state = highestEarnedIndex.map { "\(stepLabels[$0]) earned" } ?? "not started"
            return "\(displayTitle), \(state), \(earnedCount) of \(steps.count) steps"
        case .feat:
            return "\(displayTitle), \(caption) trophy, \(isEarned ? "earned" : "locked")"
        }
    }
}

/// A sub-heading inside a section ("Comet Clash") with its tiles — stacks
/// first, then feats.
struct TrophyRoomSubsection: Identifiable, Equatable {
    let id: String
    /// "" when the section has no sub-headings.
    let title: String
    let tiles: [TrophyRoomTile]
}

/// One of the four Trophy Room sections.
struct TrophyRoomTileSection: Identifiable, Equatable {
    let section: TrophyTileSection
    let subsections: [TrophyRoomSubsection]

    var id: String { section.rawValue }
    var title: String { section.displayName }
    var unlockedCount: Int {
        subsections.reduce(0) { $0 + $1.tiles.reduce(0) { $0 + $1.earnedCount } }
    }
    var total: Int {
        subsections.reduce(0) { $0 + $1.tiles.reduce(0) { $0 + $1.steps.count } }
    }
}

/// The Platinum badge in the header: the capstone's own row plus how many of
/// its required trophies are earned.
struct TrophyRoomPlatinum: Equatable {
    let row: TrophyRoomRow
    let icon: String
    let fallbackIcon: String
    let earnedCount: Int
    let requiredCount: Int

    var fraction: Double { requiredCount > 0 ? Double(earnedCount) / Double(requiredCount) : 0 }
}

/// The room's header summary — overall completion % + per-grade counts.
/// Explicitly NO points level (design.md §2: grades + capstone only).
struct TrophyRoomSummary: Equatable {

    /// Total trophies in the catalog.
    let total: Int
    /// Total latched (across every grade).
    let unlocked: Int

    /// Earned / total per grade, in ladder order (Bronze…Platinum). Every
    /// grade appears even at 0 earned so the header layout is stable.
    let gradeCounts: [GradeCount]

    struct GradeCount: Equatable, Identifiable {
        let tier: TrophyTier
        let earned: Int
        let total: Int
        var id: String { tier.rawValue }
        var gradeName: String { tier.displayName }
    }

    /// Completion as a 0…1 fraction (0 when the catalog is empty).
    var completionFraction: Double {
        total > 0 ? Double(unlocked) / Double(total) : 0
    }

    /// Completion as a whole-number percent, 0…100 (rounded).
    var completionPercent: Int {
        Int((completionFraction * 100).rounded())
    }

    /// Whether the platinum capstone is earned — a header highlight.
    let capstoneUnlocked: Bool
}

// MARK: - The testable model

/// Turns the catalog + a `TrophyEngine`'s ledger into grouped, render-ready
/// rows and a header summary. A plain struct built from a snapshot of the
/// engine's public reads — no `@Published`, no View, no GameState — so the
/// View re-derives it whenever the engine publishes, and tests build it
/// directly against a seeded engine (S2-T3 acceptance).
struct TrophyRoomModel: Equatable {

    /// Section list in play-path order, each already row-resolved.
    let sections: [TrophyRoomSection]

    /// Header summary (completion % + per-grade counts).
    let summary: TrophyRoomSummary

    /// The four tile sections the screen draws (Climb, Challenges, Minigames,
    /// Personal).  Empty when the catalog has no tile layout.
    let tileSections: [TrophyRoomTileSection]

    /// The Platinum header badge, or nil when the catalog has no tile layout.
    let platinum: TrophyRoomPlatinum?

    /// Look a tile up by id (the detail sheet re-reads it so it stays live).
    func tile(withID id: String) -> TrophyRoomTile? {
        for section in tileSections {
            for sub in section.subsections {
                if let tile = sub.tiles.first(where: { $0.id == id }) { return tile }
            }
        }
        return nil
    }

    /// The rarity slot's placeholder — the label a row shows whenever rarity
    /// is suppressed: before the stats feed lands, during cold-start, for a
    /// paused trophy, or for a trophy with no stats row yet (design.md §3/§9).
    /// Centralized so the suppression path is one constant.
    static let rarityPlaceholder = "—"

    /// The subtitle shown for a masked (locked secret) trophy — a generic
    /// line that reveals nothing (design.md §7 "??? — Hidden trophy").
    static let maskedSubtitle = "Hidden trophy — earn it to reveal."

    /// The masked title shown in place of a secret trophy's real name.
    static let maskedTitle = "???"

    /// Build the model from the engine + the resolved rarity index. Reads ONLY
    /// the engine's public API (`catalog`, `isUnlocked`, `unlockDate(for:)`,
    /// `progressFraction`) — never GameState — and the already-GATED
    /// `TrophyRarityIndex` (S3-T4), which owns all cold-start / is_paused
    /// suppression so this model draws its verdict, never re-decides it.
    /// `rarity` defaults to `.empty` (every row shows the placeholder) so a
    /// caller with no stats feed — previews, tests, the room's first render —
    /// keeps the pre-S3 behavior. Rows within a section keep catalog (authored)
    /// order; sections sort by `roomSortOrder`.
    init(engine: TrophyEngine, rarity: TrophyRarityIndex = .empty) {
        let catalog = engine.catalog

        // Resolve every trophy to a row, honoring the secret-masking policy.
        var rowsByCategory: [TrophyCategory: [TrophyRoomRow]] = [:]
        var rowByID: [String: TrophyRoomRow] = [:]
        var unlocked = 0
        // Per-grade tallies, seeded at 0 for every rung so the header is
        // stable even with an empty ledger.
        var earnedByTier: [TrophyTier: Int] = [:]
        var totalByTier: [TrophyTier: Int] = [:]
        for tier in TrophyTier.allCases {
            earnedByTier[tier] = 0
            totalByTier[tier] = 0
        }

        for trophy in catalog.trophies {
            let isUnlocked = engine.isUnlocked(trophy.id)
            // Mask iff the trophy is secret AND still locked. An unlocked
            // secret trophy reveals fully.
            let isMasked = trophy.isSecret && !isUnlocked

            let title = isMasked ? Self.maskedTitle : trophy.title
            let description: String
            if isMasked {
                description = Self.maskedSubtitle
            } else if isUnlocked {
                description = trophy.unlockedDescription
            } else {
                description = trophy.lockedDescription
            }

            // Progress: none for unlocked (bar is full/irrelevant) and none
            // for a masked secret (a bar would leak "how close"). Otherwise
            // the engine's monotonic fraction.
            let progress: Double?
            if isUnlocked || isMasked {
                progress = nil
            } else {
                progress = engine.progressFraction(for: trophy.id)
            }

            // Rarity: the index has already applied the cold-start + is_paused
            // gates (design.md §3/§9). A suppressed display (nil band) renders
            // the placeholder — NEVER a fabricated 0 %/100 %. The band label
            // rides the row; the raw percent rides the (future) detail view.
            let rarityDisplay = rarity.display(for: trophy.id)
            let rarityLabel = rarityDisplay.band?.displayName ?? Self.rarityPlaceholder

            let row = TrophyRoomRow(
                id: trophy.id,
                tier: trophy.tier,
                category: trophy.category,
                isUnlocked: isUnlocked,
                isMasked: isMasked,
                displayTitle: title,
                displayDescription: description,
                progress: progress,
                unlockDate: isUnlocked ? engine.unlockDate(for: trophy.id) : nil,
                rarityLabel: rarityLabel,
                rarityBand: rarityDisplay.band,
                rarityDetailPercent: rarityDisplay.detailPercent)

            rowsByCategory[trophy.category, default: []].append(row)
            rowByID[trophy.id] = row

            totalByTier[trophy.tier, default: 0] += 1
            if isUnlocked {
                unlocked += 1
                earnedByTier[trophy.tier, default: 0] += 1
            }
        }

        // Sections in play-path order; drop empties so an unused category
        // never shows an empty header.
        self.sections = rowsByCategory
            .map { TrophyRoomSection(category: $0.key, rows: $0.value) }
            .filter { !$0.rows.isEmpty }
            .sorted { $0.category.roomSortOrder < $1.category.roomSortOrder }

        let gradeCounts = TrophyTier.allCases
            .sorted()
            .map { tier in
                TrophyRoomSummary.GradeCount(
                    tier: tier,
                    earned: earnedByTier[tier] ?? 0,
                    total: totalByTier[tier] ?? 0)
            }

        self.summary = TrophyRoomSummary(
            total: catalog.trophies.count,
            unlocked: unlocked,
            gradeCounts: gradeCounts,
            capstoneUnlocked: catalog.trophies.contains {
                $0.tier.isCapstone && engine.isUnlocked($0.id)
            })

        // ---- Tiles: the catalog's display layout over the rows above. ----
        var roomTiles: [TrophyRoomTile] = []
        var sectionOfTile: [String: TrophyTileSection] = [:]
        var subsectionOfTile: [String: String] = [:]
        var platinumBadge: TrophyRoomPlatinum? = nil
        for tile in catalog.tiles {
            let steps = tile.trophies.compactMap { rowByID[$0] }
            guard !steps.isEmpty else { continue }
            if tile.section == .platinum {
                let requiredIDs = catalog.capstone.criteria.requiredTrophyIDs ?? []
                platinumBadge = TrophyRoomPlatinum(
                    row: steps[0],
                    icon: tile.icon,
                    fallbackIcon: tile.fallbackIcon,
                    earnedCount: requiredIDs.filter { engine.isUnlocked($0) }.count,
                    requiredCount: requiredIDs.count)
                continue
            }
            let masked = steps.allSatisfy(\.isMasked)
            // A feat shows its trophy's (possibly masked) title; a stack shows
            // the stack's name.
            let title = tile.kind == .feat ? steps[0].displayTitle
                                           : (masked ? Self.maskedTitle : tile.title)
            roomTiles.append(TrophyRoomTile(
                id: tile.id,
                kind: tile.kind,
                displayTitle: title,
                icon: tile.icon,
                fallbackIcon: tile.fallbackIcon,
                steps: steps,
                stepLabels: steps.map { catalog.stepLabel(forTrophyID: $0.id) ?? $0.gradeName }))
            sectionOfTile[tile.id] = tile.section
            subsectionOfTile[tile.id] = tile.subsection
        }

        var builtSections: [TrophyRoomTileSection] = []
        for section in TrophyTileSection.allCases where section != .platinum {
            let inSection = roomTiles.filter { sectionOfTile[$0.id] == section }
            guard !inSection.isEmpty else { continue }
            // Sub-headings in first-appearance (authored) order.
            var order: [String] = []
            for tile in inSection {
                let name = subsectionOfTile[tile.id] ?? ""
                if !order.contains(name) { order.append(name) }
            }
            let subsections = order.map { name -> TrophyRoomSubsection in
                let tiles = inSection.filter { (subsectionOfTile[$0.id] ?? "") == name }
                // Stacks first, then feats; authored order within each.
                let ordered = tiles.filter { $0.kind == .stack } + tiles.filter { $0.kind == .feat }
                return TrophyRoomSubsection(id: "\(section.rawValue)|\(name)", title: name, tiles: ordered)
            }
            builtSections.append(TrophyRoomTileSection(section: section, subsections: subsections))
        }
        self.tileSections = builtSections
        self.platinum = platinumBadge
    }
}

// MARK: - Icon resolution

/// Resolves a tile's SF Symbol, falling back to the tile's second choice when
/// the first does not exist on this iOS version.
enum TrophyIcon {
    static func resolved(icon: String, fallback: String) -> String {
        #if canImport(UIKit)
        return UIImage(systemName: icon) != nil ? icon : fallback
        #else
        return icon
        #endif
    }

    /// The icon of the tile a trophy is drawn on, from the bundled catalog.
    static func name(forTrophyID id: String) -> String? {
        guard let tile = TrophyCatalog.bundled.tile(forTrophyID: id) else { return nil }
        return resolved(icon: tile.icon, fallback: tile.fallbackIcon)
    }

    /// "Levels passed · Silver II" for a step of a multi-step stack, or nil
    /// for a feat or a one-step stack (their title already says it all).
    static func stackStepLine(forTrophyID id: String) -> String? {
        let catalog = TrophyCatalog.bundled
        guard let tile = catalog.tile(forTrophyID: id), tile.kind == .stack,
              tile.trophies.count > 1,
              let step = catalog.stepLabel(forTrophyID: id) else { return nil }
        return "\(tile.title) · \(step)"
    }
}

// MARK: - Trophy Room screen

/// The Trophy Room. Observes the `TrophyEngine` (its single source), rebuilds
/// `TrophyRoomModel` on every publish, and renders grouped sections with a
/// completion header. Display-only — reads the engine, writes nothing.
struct TrophyRoomView: View {

    @ObservedObject var engine: TrophyEngine

    /// The pin store (S2-T7). Observed so the pin controls + the "N of 3
    /// pinned" caption refresh the instant a pin toggles. Optional so the
    /// screen still renders in previews/tests without a store — pin controls
    /// simply don't appear.
    @ObservedObject var pins: TrophyPinStore

    /// The rarity feed (S3-T4). Owned by the view so a `trophy_stats` fetch
    /// never re-renders gameplay; observed so real bands appear the instant the
    /// fetch lands. A garnish — an empty index (fetch pending / failed) simply
    /// shows the placeholder on every row.
    @StateObject private var rarity: TrophyRarityProvider

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(engine: TrophyEngine,
         pins: TrophyPinStore = TrophyPinStore(),
         rarityProvider: TrophyRarityProvider = TrophyRarityProvider()) {
        self.engine = engine
        self.pins = pins
        _rarity = StateObject(wrappedValue: rarityProvider)
    }

    /// Recomputed each render from the current engine snapshot + the latest
    /// rarity index. Cheap: one pass over 92 rows of value types.
    private var model: TrophyRoomModel {
        TrophyRoomModel(engine: engine, rarity: rarity.index)
    }

    /// The tile whose detail sheet is open.
    @State private var selection: TileSelection?
    private struct TileSelection: Identifiable { let id: String }

    private static let tileColumns = [GridItem(.flexible(), spacing: 12, alignment: .top),
                                      GridItem(.flexible(), spacing: 12, alignment: .top),
                                      GridItem(.flexible(), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                if let platinum = model.platinum {
                    platinumBadge(platinum)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                header(model.summary)
                    .padding(.horizontal, 16)

                pinCaption
                    .padding(.horizontal, 16)

                // Four sections of tiles.  In every sub-heading, stacks come
                // first and feats after (the model orders them).
                ForEach(model.tileSections) { section in
                    Section {
                        ForEach(section.subsections) { sub in
                            VStack(alignment: .leading, spacing: 10) {
                                if !sub.title.isEmpty {
                                    Text(sub.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .accessibilityAddTraits(.isHeader)
                                }
                                LazyVGrid(columns: Self.tileColumns, alignment: .center, spacing: 16) {
                                    ForEach(sub.tiles) { tile in
                                        Button {
                                            selection = TileSelection(id: tile.id)
                                        } label: {
                                            TrophyTileView(tile: tile)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(tile.accessibilityLabel)
                                        .accessibilityHint("Shows details")
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle("Trophies")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Fetch trophy_stats once when the room opens (idempotent — a re-open
        // reuses the cache). Fire-and-forget: rarity is a garnish, so a failed
        // or slow fetch just leaves the placeholders in place.
        .task { await rarity.loadIfNeeded() }
        .sheet(item: $selection) { selected in
            // Re-read the tile from the live model so pins and unlocks made
            // while the sheet is open show immediately.
            if let tile = self.model.tile(withID: selected.id) {
                TrophyTileDetailSheet(tile: tile, pins: pins)
            }
        }
    }

    // MARK: Platinum badge (header)

    /// One large badge for the Platinum trophy with its progress.  Tapping is
    /// not needed: everything about it is shown here.
    @ViewBuilder
    private func platinumBadge(_ platinum: TrophyRoomPlatinum) -> some View {
        let style = TrophyGradeStyle.forTier(.platinum)
        let earned = platinum.row.isUnlocked
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(style.accent.opacity(earned ? 0.25 : 0.10))
                Circle().stroke(style.accent.opacity(earned ? 1 : 0.45), lineWidth: 4)
                Image(systemName: TrophyIcon.resolved(icon: platinum.icon, fallback: platinum.fallbackIcon))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(earned ? style.accent : Color.secondary.opacity(0.7))
            }
            .frame(width: 84, height: 84)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(platinum.row.displayTitle)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text(platinum.row.displayDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: platinum.fraction)
                    .tint(style.accent)
                Text(earned ? "Earned" : "\(platinum.earnedCount) of \(platinum.requiredCount)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(earned
            ? "Platinum trophy, earned"
            : "Platinum trophy, \(platinum.earnedCount) of \(platinum.requiredCount) required trophies earned")
    }

    /// A quiet caption stating how many chase pins are set, so the pin cap is
    /// discoverable ("Pin up to 3 to track them on the game menu").
    @ViewBuilder
    private var pinCaption: some View {
        let n = pins.pinnedIDs.count
        HStack(spacing: 6) {
            Image(systemName: "pin.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(n == 0
                 ? "Pin up to \(TrophyPinStore.maxPins) trophies to track them on the game menu."
                 : "\(n) of \(TrophyPinStore.maxPins) pinned — tracked on the game menu.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(n == 0
            ? "Pin up to \(TrophyPinStore.maxPins) trophies to track your chase on the game menu."
            : "\(n) of \(TrophyPinStore.maxPins) trophies pinned, tracked on the game menu.")
    }

    // MARK: Header (completion % + per-grade counts — NO points level)

    @ViewBuilder
    private func header(_ summary: TrophyRoomSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(summary.completionPercent)%")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text("complete")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(summary.unlocked)/\(summary.total)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(value: summary.completionFraction)
                .tint(TrophyGradeStyle.forTier(.gold).accent)
                .accessibilityHidden(true)

            // Per-grade counts — every rung, ladder order. No points.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(summary.gradeCounts) { g in
                    gradeChip(g)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headerAccessibilityLabel(summary))
    }

    private func headerAccessibilityLabel(_ summary: TrophyRoomSummary) -> String {
        var parts = ["\(summary.completionPercent) percent complete",
                     "\(summary.unlocked) of \(summary.total) trophies"]
        for g in summary.gradeCounts {
            parts.append("\(g.gradeName): \(g.earned) of \(g.total)")
        }
        if summary.capstoneUnlocked {
            parts.append("Platinum capstone earned")
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func gradeChip(_ g: TrophyRoomSummary.GradeCount) -> some View {
        let style = TrophyGradeStyle.forTier(g.tier)
        HStack(spacing: 6) {
            Image(systemName: style.glyph)
                .font(.footnote.weight(.bold))
                .foregroundStyle(style.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(g.gradeName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(g.earned)/\(g.total)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(style.accent.opacity(g.earned > 0 ? 0.6 : 0.15), lineWidth: 1)
        )
    }

    // MARK: Section header

    @ViewBuilder
    private func sectionHeader(_ section: TrophyRoomTileSection) -> some View {
        HStack {
            Text(section.title)
                .font(.headline)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Text("\(section.unlockedCount)/\(section.total)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title), \(section.unlockedCount) of \(section.total) earned")
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - One trophy row

/// A single trophy row: grade glyph, name, description/objective, a rarity
/// slot ("—" in S2), a progress bar for locked cumulative trophies, and the
/// unlock timestamp when earned. Draws the resolved `TrophyRoomRow` — it
/// makes no masking decision itself.
struct TrophyRoomRowView: View {

    let row: TrophyRoomRow

    /// Whether this row's trophy is currently pinned (S2-T7).
    var isPinned: Bool = false
    /// Whether another pin slot is free — governs whether an UNpinned,
    /// pinnable row can still be pinned (the cap of 3).
    var canPinMore: Bool = true
    /// Toggle the pin. `nil` when no pin store is wired (previews/tests) —
    /// the control then never appears.
    var onTogglePin: (() -> Void)? = nil

    /// Show the pin control iff a handler is wired AND the trophy is a valid
    /// chase (locked + non-masked). An already-pinned row always shows the
    /// control (so it can be unpinned); an unpinned pinnable row shows it too
    /// but disables it when the cap is full.
    private var showsPinControl: Bool {
        onTogglePin != nil && row.isPinnable
    }
    private var pinDisabled: Bool { !isPinned && !canPinMore }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.isMasked ? "questionmark.circle" : row.tileIcon)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(row.isUnlocked ? row.gradeAccent : row.gradeAccent.opacity(0.4))
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.displayTitle)
                        .font(.headline)
                        .minimumScaleFactor(0.7)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    // Rarity slot — "—" until S3-T4. NEVER diamond
                    // iconography at any band (design.md §2 R2 / §3).
                    Text(row.rarityLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityHidden(true)
                }

                Text(row.displayDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)

                // Progress bar for locked cumulative trophies only.
                if let progress = row.progress, !row.isUnlocked {
                    ProgressView(value: progress)
                        .tint(row.gradeAccent)
                        .accessibilityHidden(true)
                }

                // Unlock timestamp when earned.
                if row.isUnlocked, let date = row.unlockDate {
                    Text(unlockCaption(date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Pin toggle for a chaseable trophy (S2-T7). Its own a11y element
            // (the row itself ignores children), so VoiceOver reaches it.
            if showsPinControl {
                pinButton
            }
        }
        .padding(.vertical, 10)
        .opacity(row.isUnlocked ? 1 : 0.78)
        // The row text is one combined a11y element; the pin button stays a
        // separate, focusable control alongside it.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel)
    }

    /// The pin/unpin control — a filled pin when pinned, an outline when not,
    /// dimmed + disabled when the cap blocks a new pin.
    @ViewBuilder
    private var pinButton: some View {
        Button {
            onTogglePin?()
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isPinned ? row.gradeAccent
                                          : (pinDisabled ? Color.secondary.opacity(0.4)
                                                         : Color.secondary))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(pinDisabled)
        .accessibilityLabel(isPinned
            ? "Unpin \(row.displayTitle) from your chase"
            : "Pin \(row.displayTitle) to your chase")
        .accessibilityHint(pinDisabled
            ? "Pin limit reached. Unpin a trophy first."
            : (isPinned ? "Removes it from the game-menu chase chips."
                        : "Tracks it on the game-menu chase chips."))
    }

    /// "Earned Jan 3, 2026" — or a legacy note for grandfathered unlocks
    /// stamped at the `legacyUnlockDate` sentinel (pre-trophies).
    private func unlockCaption(_ date: Date) -> String {
        if date == TrophyEngine.legacyUnlockDate {
            return "Earned before trophies launched"
        }
        return "Earned \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

// MARK: - Tile shapes

/// The feat tile's shape: a pointed-top hexagon (stacks use a circle).
struct TrophyHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + w, y: rect.minY + h * 0.25))
        path.addLine(to: CGPoint(x: rect.minX + w, y: rect.minY + h * 0.75))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY + h))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.75))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.25))
        path.closeSubpath()
        return path
    }
}

// MARK: - One tile

/// A Trophy Room tile.
/// • Stack: a ROUND badge in the tier color of the highest step earned, the
///   step name underneath ("Silver II") and one small marker per step.
/// • Feat: a HEXAGON badge in its tier color, no markers.
/// Locked tiles are dimmed; a locked secret shows a question mark.
struct TrophyTileView: View {

    let tile: TrophyRoomTile

    private var accent: Color { TrophyGradeStyle.forTier(tile.displayTier).accent }

    var body: some View {
        VStack(spacing: 6) {
            badge
                .frame(width: 70, height: 70)

            Text(tile.displayTitle)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            Text(tile.caption)
                .font(.caption2)
                .foregroundStyle(tile.isEarned ? accent : Color.secondary)
                .lineLimit(1)

            if tile.kind == .stack && tile.steps.count > 1 {
                stepMarkers
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }

    @ViewBuilder
    private var badge: some View {
        let fill = accent.opacity(tile.isEarned ? 0.20 : 0.07)
        let line = accent.opacity(tile.isEarned ? 1.0 : 0.35)
        ZStack {
            if tile.kind == .stack {
                Circle().fill(fill)
                Circle().stroke(line, lineWidth: 3)
            } else {
                TrophyHexagon().fill(fill)
                TrophyHexagon().stroke(line, lineWidth: 3)
            }
            Image(systemName: tile.isMasked
                  ? "questionmark"
                  : TrophyIcon.resolved(icon: tile.icon, fallback: tile.fallbackIcon))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(tile.isEarned ? accent : Color.secondary.opacity(0.65))
        }
    }

    /// One small marker per step: filled in that step's tier color when
    /// earned, faint when not.
    private var stepMarkers: some View {
        HStack(spacing: 3) {
            ForEach(tile.steps) { step in
                Capsule()
                    .fill(step.isUnlocked ? step.gradeAccent : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 4)
            }
        }
    }
}

// MARK: - Tile detail sheet

/// Everything about one tile: each step (or the single feat) with its step
/// name, title, description, progress, rarity, date earned, and the pin
/// control for a step that can still be chased.
struct TrophyTileDetailSheet: View {

    let tile: TrophyRoomTile
    @ObservedObject var pins: TrophyPinStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Spacer()
                        TrophyTileView(tile: tile)
                            .frame(width: 140)
                        Spacer()
                    }
                    .padding(.bottom, 8)

                    ForEach(Array(tile.steps.enumerated()), id: \.element.id) { index, row in
                        VStack(alignment: .leading, spacing: 2) {
                            if tile.kind == .stack && !row.isMasked {
                                Text(tile.stepLabels[index].uppercased())
                                    .font(.caption2.weight(.bold))
                                    .kerning(0.8)
                                    .foregroundStyle(row.isUnlocked ? row.gradeAccent : Color.secondary)
                            }
                            TrophyRoomRowView(
                                row: row,
                                isPinned: pins.isPinned(row.id),
                                canPinMore: pins.canPinMore,
                                onTogglePin: { pins.toggle(row.id) })
                        }
                        if index < tile.steps.count - 1 { Divider() }
                    }
                }
                .padding(16)
            }
            .navigationTitle(tile.displayTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents(tile.steps.count > 2 ? [.large] : [.medium, .large])
    }
}
