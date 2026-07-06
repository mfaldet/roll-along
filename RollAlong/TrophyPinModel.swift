//
//  TrophyPinModel.swift
//  RollAlong
//
//  S2-T7 — trophy pinning + chase chips (docs/trophies/sprint-plan.md §2
//  S2-T7; design.md §7 "Pinning" — the standing answer to "what am I
//  chasing?").
//
//  What ships here:
//
//  • `TrophyPinStore` — an `ObservableObject` that owns the player's PINNED
//    trophy ids: an ordered, de-duplicated list capped at `maxPins` (3),
//    persisted to the local `ra_trophyPins` UserDefaults key. It is the
//    single writer of pin state; the Trophy Room drives it (`toggle`), and
//    the chase chips + the Profile showcase READ its `pinnedIDs`. All of its
//    order / cap / dedup / persistence logic is pure model state,
//    unit-tested by TrophyPinModelTests without ever instantiating a View
//    (S2-T7 acceptance):
//      – pins persist across a reload (round-trip `ra_trophyPins`);
//      – the cap of 3 is enforced (a 4th pin is refused, order preserved);
//      – toggle is idempotent + deduped; unpin removes without disturbing
//        the rest of the order.
//
//  • `ChaseChip` — one pinned trophy resolved for the compact progress chip:
//    id, title, grade glyph/accent (from the single `TrophyGradeStyle`
//    source), the engine's `progressFraction`, a progress caption, and a
//    VoiceOver label. A value type: cheap to diff, trivial to assert.
//
//  • `ChaseChipModel` — a PURE, View-free model that turns `TrophyEngine` +
//    the pinned ids into render-ready chips. It reads the ENGINE ONLY (never
//    GameState), and each chip's progress comes from the engine's
//    `progressFraction` API (S2-T7 acceptance: "chips read TrophyEngine's
//    progress API only"). Already-earned pins and unknown ids drop out (a
//    chase you've completed is no longer a chase; a stale id fabricates
//    nothing), and a masked SECRET pin never leaks its objective — it draws
//    a generic "Hidden trophy" chip with its progress suppressed.
//
//  BINDING Diamond riders (design.md §2 R2, RULED 2026-07-02): the Diamond
//  trophy GRADE's glyph/color come from `TrophyGradeStyle.forTier` (the
//  violet `laurel.leading` wreath) — NEVER the cyan `diamond.fill` gem the
//  Diamond BALL / Iconic cosmetic tier uses. Reused here so the two Diamonds
//  cannot blur; copy is grade-side only ("Diamond", never "Diamond cosmetic").
//
//  NEVER-MINT (D1, 2026-07-02): nothing here grants coins. Pinning and the
//  chase chips are display-only; they read the trophy ledger and pin store
//  and never write the economy.
//

import SwiftUI

// MARK: - The pin store (testable ObservableObject)

/// Owns the player's pinned trophy ids — an ordered, de-duplicated list
/// capped at `maxPins`, persisted to the local `ra_trophyPins` key. The
/// single source of truth for pin state, shared by the Trophy Room (which
/// writes it) and the chase chips + Profile showcase (which read it).
///
/// Deliberately an `ObservableObject` with NO View dependency, so its cap /
/// order / dedup / persistence rules are unit-testable in isolation (S2-T7
/// acceptance). It mirrors `TrophyToastQueue` / `CapstoneCelebrationModel`:
/// GameState owns it as a plain `let` on its own object so a pin write never
/// re-renders a gameplay view observing GameState.
final class TrophyPinStore: ObservableObject {

    /// The local pin key. Documented in the GameState.swift `ra_*` audit
    /// header alongside the other trophy keys. Stored as a plist string
    /// array — the pin ORDER is meaningful (it drives showcase/chip order),
    /// so it is an array, not a set.
    static let pinsKey = "ra_trophyPins"

    /// The hard cap on simultaneous pins (design.md §7 "pin up to 3").
    static let maxPins = 3

    /// The pinned trophy ids, in the player's pin order. Never longer than
    /// `maxPins`, never contains a duplicate. `@Published` so the chips + the
    /// Trophy Room's pin controls refresh the moment a pin toggles.
    @Published private(set) var pinnedIDs: [String]

    private let defaults: UserDefaults

    /// Loads the persisted pin list, healing any legacy/corrupt value toward
    /// a valid state: drops duplicates (first occurrence wins, order kept)
    /// and clamps to `maxPins`, so a hand-edited or older-build value can
    /// never exceed the cap or double-list an id.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = (defaults.array(forKey: Self.pinsKey) as? [String]) ?? []
        self.pinnedIDs = Self.sanitize(stored)
    }

    // MARK: - Reads

    /// Whether `trophyID` is currently pinned.
    func isPinned(_ trophyID: String) -> Bool {
        pinnedIDs.contains(trophyID)
    }

    /// The number of free pin slots (0…`maxPins`).
    var freeSlots: Int { max(0, Self.maxPins - pinnedIDs.count) }

    /// Whether another trophy can still be pinned (a free slot remains).
    var canPinMore: Bool { pinnedIDs.count < Self.maxPins }

    // MARK: - Writes (the only mutation surface)

    /// Pin `trophyID` at the end of the order. No-op when it is already
    /// pinned (idempotent) or when the cap is full (a 4th pin is refused,
    /// existing order untouched). Returns true iff the pin landed.
    ///
    /// Whether a given trophy is PINNABLE (e.g. not a masked secret) is the
    /// caller's policy — the Trophy Room only offers the control on eligible
    /// rows. The store enforces the structural rules: cap, order, dedup,
    /// persistence.
    @discardableResult
    func pin(_ trophyID: String) -> Bool {
        guard !pinnedIDs.contains(trophyID) else { return false }
        guard pinnedIDs.count < Self.maxPins else { return false }
        pinnedIDs.append(trophyID)
        persist()
        return true
    }

    /// Unpin `trophyID`, preserving the order of the rest. No-op when it was
    /// not pinned. Returns true iff a pin was removed.
    @discardableResult
    func unpin(_ trophyID: String) -> Bool {
        guard let idx = pinnedIDs.firstIndex(of: trophyID) else { return false }
        pinnedIDs.remove(at: idx)
        persist()
        return true
    }

    /// Toggle `trophyID`'s pinned state. Pins it (if a slot is free) or
    /// unpins it. Returns the resulting pinned state, or the unchanged state
    /// when a pin was refused by the cap — so a caller can surface "pin limit
    /// reached" feedback.
    @discardableResult
    func toggle(_ trophyID: String) -> Bool {
        if pinnedIDs.contains(trophyID) {
            unpin(trophyID)
            return false
        }
        return pin(trophyID)
    }

    /// Prune any pinned id that is no longer relevant (unknown to the catalog
    /// OR already earned) using the engine as the authority. Keeps the pin
    /// list honest so a completed chase doesn't linger as a stale chip and a
    /// removed-from-catalog id never persists forever. Order preserved;
    /// persists only when something actually changed. Safe to call on launch
    /// or whenever the ledger advances.
    func pruneCompleted(using engine: TrophyEngine) {
        let kept = pinnedIDs.filter { id in
            engine.catalog.trophy(withID: id) != nil && !engine.isUnlocked(id)
        }
        guard kept.count != pinnedIDs.count else { return }
        pinnedIDs = kept
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(pinnedIDs, forKey: Self.pinsKey)
    }

    /// De-dupes (first-wins, order kept) and clamps to `maxPins`.
    private static func sanitize(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for id in raw where !seen.contains(id) {
            seen.insert(id)
            out.append(id)
            if out.count == maxPins { break }
        }
        return out
    }
}

// MARK: - One pinned trophy, resolved for a chase chip

/// A single pinned trophy the chase-chip strip can draw — already resolved
/// for progress + secret masking, so the View draws data and makes no policy
/// decision. Value type: cheap to diff, trivial to assert.
struct ChaseChip: Identifiable, Equatable {

    /// The pinned trophy's frozen id (also the SwiftUI identity).
    let id: String
    let tier: TrophyTier

    /// Whether this is a masked (locked secret) pin — its objective is
    /// withheld and it draws a generic "Hidden trophy" label.
    let isMasked: Bool

    /// Title to draw: the real title when visible, `"???"` when masked.
    let title: String

    /// Fraction toward the threshold, 0…1, from the engine's
    /// `progressFraction`. `nil` when progress is suppressed (a masked secret
    /// — a bar would leak "how close").
    let progress: Double?

    /// Grade glyph (SF Symbol) — from the single `TrophyGradeStyle` source so
    /// the Diamond grade never borrows the cosmetic gem (design.md §2 R2).
    var gradeGlyph: String { TrophyGradeStyle.forTier(tier).glyph }
    /// Grade accent color — same single source of truth.
    var gradeAccent: Color { TrophyGradeStyle.forTier(tier).accent }

    /// "0%"…"100%" progress caption for the chip, or an em dash when
    /// suppressed. Never leaks a masked secret's closeness.
    var progressCaption: String {
        guard let progress else { return "—" }
        return "\(Int((progress * 100).rounded()))%"
    }

    /// One-line VoiceOver label: name, grade, and progress. Never speaks the
    /// hidden title of a masked pin (it uses `title` = "???") nor its
    /// closeness.
    var accessibilityLabel: String {
        var parts: [String] = ["Chasing", title, "\(tier.displayName) grade"]
        if let progress, !isMasked {
            parts.append("\(Int((progress * 100).rounded())) percent complete")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - The testable chase-chip model

/// Turns a `TrophyEngine` + the pinned ids into render-ready chase chips.
/// A plain value type built from a snapshot of the engine's public reads —
/// no `@Published`, no View, no GameState — so the View re-derives it
/// whenever the engine or the pin store publishes, and tests build it
/// directly against a seeded engine + pin list (S2-T7 acceptance).
///
/// The chips answer "what am I chasing?", so an already-EARNED pin drops out
/// (it is no longer a chase) and an unknown id fabricates nothing. Each
/// surviving chip's progress is the engine's `progressFraction` — the same
/// monotonic value the Trophy Room shows — read through the engine's API
/// only (S2-T7 acceptance: "chips read TrophyEngine's progress API only").
struct ChaseChipModel: Equatable {

    /// The masked title shown in place of a secret pin's real name — reused
    /// from the Trophy Room's masking vocabulary so the two never drift.
    static let maskedTitle = TrophyRoomModel.maskedTitle

    /// The chips to draw, in the player's pin order. Empty when nothing is
    /// pinned or every pin is already earned.
    let chips: [ChaseChip]

    /// True when there are no chips to show — the strip renders nothing.
    var isEmpty: Bool { chips.isEmpty }

    /// Build the chips from the engine and the pinned ids.
    ///
    /// Reads ONLY the engine's public API (`catalog.trophy(withID:)`,
    /// `isUnlocked`, `progressFraction`) — never GameState. Iterates the pin
    /// ids in order, dropping any that are unknown to the catalog or already
    /// unlocked, and masking a locked secret so it never leaks its objective
    /// or its closeness.
    init(engine: TrophyEngine, pinnedIDs: [String]) {
        var out: [ChaseChip] = []
        for id in pinnedIDs {
            // Unknown id (removed from catalog / hand-edited): fabricate
            // nothing.
            guard let trophy = engine.catalog.trophy(withID: id) else { continue }
            // An earned pin is no longer a chase — drop it from the strip.
            guard !engine.isUnlocked(id) else { continue }

            let isMasked = trophy.isSecret
            out.append(ChaseChip(
                id: id,
                tier: trophy.tier,
                isMasked: isMasked,
                title: isMasked ? Self.maskedTitle : trophy.title,
                // Progress comes from the engine's API; suppressed for a
                // masked secret so a bar can't leak "you're close".
                progress: isMasked ? nil : engine.progressFraction(for: id)))
        }
        self.chips = out
    }
}
