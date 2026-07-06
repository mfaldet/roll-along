//
//  TrophyToastView.swift
//  RollAlong
//
//  S2-T1 — the tier-differentiated unlock banner + a testable, run-aware
//  toast QUEUE (docs/trophies/sprint-plan.md §2 S2-T1; design.md §6).
//
//  What ships here:
//
//  • `TrophyGradeStyle` — the per-grade glyph / accent / haptic table for
//    Bronze / Silver / Gold / Diamond. (Platinum, the `capstone_all`
//    capstone, hands its full-screen blowout to S2-T5; this file gives it
//    only a safe fallback so a stray platinum id never crashes the banner.)
//
//    BINDING Diamond riders (design.md §2 R2, RULED 2026-07-02): the
//    Diamond trophy *grade* gets its OWN glyph + color, sharing NO
//    iconography with the Diamond *ball* / Iconic cosmetic gating tier
//    (the $19.99 paid exclusive). The cosmetic rarity gem is a cyan-blue
//    `diamond.fill` (Cosmetics.swift `RarityGem`); the Diamond GRADE here
//    is a violet `laurel.leading` wreath — different symbol, different
//    hue. `TrophyGradeStyle.cosmeticDiamondTreatment` records the cosmetic
//    treatment so a unit test can assert the two provably differ. Copy
//    discipline rides along: the banner never says "Diamond cosmetic" of
//    the grade nor "Diamond trophy" of the paid tier.
//
//  • `TrophyToastQueue` — an `ObservableObject` that COALESCES unlocks
//    earned mid-run and presents them as ONE batched card at run end,
//    NEVER during an active tilt run (design.md §6 "never mid-run";
//    f2p research §7.10). All of its coalescing + run-active gating are
//    pure model state, unit-tested by TrophyToastQueueTests without ever
//    instantiating a View.
//
//  • `TrophyToastBanner` / `TrophyToastHost` — the SwiftUI surface reading
//    the queue. Accessible: a VoiceOver announcement + `accessibilityLabel`
//    carrying title + grade, Dynamic-Type scalable fonts, and
//    `@Environment(\.accessibilityReduceMotion)` honored (crossfade in
//    place of the scale/slide). Haptics respect `hapticsEnabled`, the
//    signature sound respects `soundEnabled` (design.md §6).
//
//  NEVER-MINT (D1, 2026-07-02): nothing here grants coins. The banner and
//  queue are display-only; they read the trophy ledger and never write the
//  economy.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Per-grade visual + feedback style

/// The banner styling for one trophy grade: a glyph (SF Symbol), an accent
/// color, and the impact-feedback weight design.md §6 assigns the grade.
///
/// Grades are NEVER conveyed by color alone (design.md §6 accessibility):
/// the `glyph` shape differs per grade too (Diamond's wreath vs the
/// medals), and the VoiceOver label always speaks the grade name.
struct TrophyGradeStyle: Equatable {

    /// SF Symbol for the grade badge.
    let glyph: String
    /// Accent color driving the badge tint + banner rule.
    let accent: Color
    /// Impact-feedback weight for this grade's unlock (design.md §6:
    /// light Bronze/Silver, medium Gold, heavy Diamond).
    let impact: ImpactWeight
    /// Diamond alone gets a second, delayed heavy pulse (design.md §6
    /// "heavy + double-tap").
    let diamondDoubleTap: Bool

    /// Portable impact weights (mirrors UIImpactFeedbackGenerator styles)
    /// so the table is testable with no UIKit dependency.
    enum ImpactWeight: String, Equatable { case light, medium, heavy }

    /// The grade table. `platinum` returns a neutral fallback — the
    /// platinum capstone's real celebration is S2-T5, not a banner.
    static func forTier(_ tier: TrophyTier) -> TrophyGradeStyle {
        switch tier {
        case .bronze:
            return TrophyGradeStyle(glyph: "medal.fill",
                                    accent: Color(hexRGB: "#C77B3B") ?? .brown,
                                    impact: .light,
                                    diamondDoubleTap: false)
        case .silver:
            return TrophyGradeStyle(glyph: "medal.fill",
                                    accent: Color(hexRGB: "#AEB6BD") ?? .gray,
                                    impact: .light,
                                    diamondDoubleTap: false)
        case .gold:
            return TrophyGradeStyle(glyph: "medal.fill",
                                    accent: Color(hexRGB: "#E7B93B") ?? .yellow,
                                    impact: .medium,
                                    diamondDoubleTap: false)
        case .diamond:
            // BINDING §2 R2: the Diamond GRADE is a violet laurel wreath —
            // NOT the cyan-blue `diamond.fill` gem the cosmetic tier uses.
            return TrophyGradeStyle(glyph: "laurel.leading",
                                    accent: Color(hexRGB: "#8A5CF6") ?? .purple,
                                    impact: .heavy,
                                    diamondDoubleTap: true)
        case .platinum:
            // Fallback only. The capstone's full-screen moment is S2-T5.
            return TrophyGradeStyle(glyph: "rosette",
                                    accent: Color(hexRGB: "#D5DCE6") ?? .white,
                                    impact: .heavy,
                                    diamondDoubleTap: false)
        }
    }

    // MARK: Diamond-disambiguation constants (design.md §2 R2 — BINDING)

    /// The Diamond trophy GRADE's treatment, surfaced as a constant so
    /// tests can assert it shares NO iconography with the cosmetic Diamond
    /// treatment below.
    static let diamondGradeTreatment = TrophyGradeStyle.forTier(.diamond)

    /// The Diamond *ball* / Iconic cosmetic tier's rarity treatment — the
    /// cyan-blue `diamond.fill` gem from Cosmetics.swift `RarityGem`
    /// (`Color(red: 0.38, green: 0.80, blue: 0.98)`). Recorded here ONLY so
    /// S2-T1's acceptance test can prove the grade differs from it. NOT
    /// rendered by any trophy surface.
    static let cosmeticDiamondTreatment =
        (glyph: "diamond.fill",
         accent: Color(.sRGB, red: 0.38, green: 0.80, blue: 0.98, opacity: 1))

    /// True iff the Diamond GRADE and the Diamond COSMETIC share neither
    /// glyph nor accent color — the binding §2 R2 invariant, asserted by
    /// the S2-T1 acceptance test.
    static var diamondGradeIsDistinctFromCosmetic: Bool {
        let grade = diamondGradeTreatment
        let cos = cosmeticDiamondTreatment
        return grade.glyph != cos.glyph
            && !colorsApproximatelyEqual(grade.accent, cos.accent)
    }

    /// sRGB component comparison — Color has no cross-platform `==` we can
    /// trust for "visually the same", so compare resolved components.
    static func colorsApproximatelyEqual(_ a: Color, _ b: Color, tolerance: CGFloat = 0.02) -> Bool {
        #if canImport(UIKit)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        UIColor(a).getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        UIColor(b).getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return abs(ar - br) <= tolerance
            && abs(ag - bg) <= tolerance
            && abs(ab - bb) <= tolerance
        #else
        return a == b
        #endif
    }
}

// MARK: - Coalesced presentation payload

/// One batched card the queue hands the view: the trophies to announce,
/// already coalesced, plus derived copy + the top grade earned (which drives
/// the card's accent and haptic escalation) and a stable identity for
/// SwiftUI diffing.
struct TrophyToastBatch: Identifiable, Equatable {

    let id: UUID
    /// The trophies in this batch, in the order they unlocked.
    let trophies: [TrophyDefinition]

    init(id: UUID = UUID(), trophies: [TrophyDefinition]) {
        self.id = id
        self.trophies = trophies
    }

    /// The single highest grade in the batch — the card wears this grade's
    /// glyph/accent/haptic (a mixed batch escalates to its best rung).
    var topTier: TrophyTier {
        trophies.map(\.tier).max() ?? .bronze
    }

    var style: TrophyGradeStyle { TrophyGradeStyle.forTier(topTier) }

    var isEmpty: Bool { trophies.isEmpty }
    var count: Int { trophies.count }

    /// The banner's primary line.
    var headline: String {
        if trophies.count == 1 {
            return trophies[0].title
        }
        return "\(trophies.count) trophies unlocked"
    }

    /// The banner's secondary line — the grade for a single unlock, a short
    /// grade tally for a coalesced batch. Copy is grade-side only; it never
    /// says "cosmetic" (design.md §2 R2 copy discipline).
    var subline: String {
        if trophies.count == 1 {
            return "\(trophies[0].tier.displayName) trophy"
        }
        let tally = TrophyTier.allCases
            .sorted(by: >)
            .compactMap { tier -> String? in
                let n = trophies.filter { $0.tier == tier }.count
                return n > 0 ? "\(n) \(tier.displayName)" : nil
            }
        return tally.joined(separator: " · ")
    }

    /// VoiceOver announcement — speaks title + grade so the grade is never
    /// color-only (design.md §6). "Trophy unlocked: <name>, <Grade>."
    var accessibilityAnnouncement: String {
        if trophies.count == 1 {
            let t = trophies[0]
            return "Trophy unlocked: \(t.title), \(t.tier.displayName)."
        }
        let names = trophies.map(\.title).joined(separator: ", ")
        return "\(trophies.count) trophies unlocked: \(names)."
    }
}

// MARK: - The run-aware toast queue (testable ObservableObject)

/// Owns the trophy-toast presentation policy: unlocks earned while a run is
/// active are HELD and coalesced; they surface as a single batched card the
/// moment the run ends (or immediately, coalesced with anything already
/// pending, when no run is active). At most one batch is presented at a
/// time; anything landing while a card is on screen coalesces into the
/// next batch (design.md §6 "max 1 toast in-flight; overflow coalesces").
///
/// This is deliberately a plain model with no View dependency so its
/// coalescing + gating are unit-testable in isolation (S2-T1 acceptance).
@MainActor
final class TrophyToastQueue: ObservableObject {

    /// The batch currently on screen, or nil when nothing is showing.
    @Published private(set) var presented: TrophyToastBatch?

    /// Whether a tilt run is in progress. While true, `enqueue` NEVER
    /// presents — it only accumulates (design.md §6 "never mid-run").
    @Published private(set) var isRunActive: Bool = false

    /// Trophies unlocked but not yet presented — the coalescing buffer.
    /// Filled by `enqueue` during a run (or while a card is on screen);
    /// drained into one batch by `runDidEnd` / `presentPendingIfIdle`.
    private(set) var pending: [TrophyDefinition] = []

    init() {}

    // MARK: Run lifecycle

    /// Call when a tilt run begins. Suppresses all presentation until
    /// `runDidEnd`. Idempotent.
    func runDidStart() {
        isRunActive = true
    }

    /// Call at run end (any terminal overlay: win / fell / out-of-lives /
    /// minigame result). Clears the run flag and flushes everything the run
    /// accumulated as ONE coalesced batch (design.md §6 "coalesced at run
    /// end").
    func runDidEnd() {
        isRunActive = false
        presentPendingIfIdle()
    }

    // MARK: Enqueue

    /// Record newly-unlocked trophies for presentation. During a run — or
    /// while a card is already on screen — they only accumulate; otherwise
    /// they present immediately (coalesced with anything already pending).
    /// De-duplicates against the current pending buffer AND the on-screen
    /// batch so a double-fire never shows a trophy twice.
    func enqueue(_ trophies: [TrophyDefinition]) {
        guard !trophies.isEmpty else { return }
        let alreadyKnown = Set(pending.map(\.id))
            .union(presented?.trophies.map(\.id) ?? [])
        for t in trophies where !alreadyKnown.contains(t.id) {
            if !pending.contains(where: { $0.id == t.id }) {
                pending.append(t)
            }
        }
        presentPendingIfIdle()
    }

    /// Convenience for the common single-unlock call.
    func enqueue(_ trophy: TrophyDefinition) { enqueue([trophy]) }

    // MARK: Dismissal

    /// Dismiss the on-screen card. If more unlocks coalesced behind it while
    /// it showed, the next batch presents immediately (unless a run is now
    /// active). This is what an auto-dismiss timer or a tap calls.
    func dismissPresented() {
        presented = nil
        presentPendingIfIdle()
    }

    // MARK: Core gating

    /// Present the pending buffer as one batch IFF the gate is open: no run
    /// active AND nothing already on screen AND something to show. This is
    /// the single chokepoint enforcing "never mid-run" + "max 1 in-flight".
    private func presentPendingIfIdle() {
        guard !isRunActive, presented == nil, !pending.isEmpty else { return }
        let batch = TrophyToastBatch(trophies: pending)
        pending.removeAll()
        presented = batch
    }

    // MARK: Test-only introspection

    #if DEBUG
    /// Count of trophies waiting in the coalescing buffer (test assertions).
    var pendingCount: Int { pending.count }
    #endif
}

// MARK: - Banner view

/// The compact unlock banner. Reads a `TrophyToastBatch`; renders the top
/// grade's glyph + accent, the headline/subline, and (on appear) posts a
/// VoiceOver announcement + the grade's haptic + the signature sound.
/// Auto-dismiss + tap-to-open are driven by the host (`TrophyToastHost`) so
/// this view stays a pure presentation of one batch.
struct TrophyToastBanner: View {

    let batch: TrophyToastBatch
    /// Honored from GameState by the host; defaulted so the view previews.
    var hapticsEnabled: Bool = true
    var soundEnabled: Bool = true
    /// Tapping the banner deep-links into the Trophy Room (S2-T2 wires the
    /// destination). Optional so the banner renders standalone in tests.
    var onTap: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let style = batch.style
        HStack(spacing: 12) {
            Image(systemName: style.glyph)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(style.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(batch.headline)
                    // Scalable Dynamic Type — headline, not a fixed size.
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(batch.subline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(style.accent.opacity(0.85), lineWidth: 2)
        )
        .overlay(alignment: .leading) {
            // Grade-colored accent rail — the glyph above is the second,
            // non-color cue, so grade is never conveyed by color alone.
            RoundedRectangle(cornerRadius: 2)
                .fill(style.accent)
                .frame(width: 4)
                .padding(.vertical, 8)
                .padding(.leading, 2)
                .accessibilityHidden(true)
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        // One a11y element speaking title + grade (design.md §6).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(batch.accessibilityAnnouncement)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the Trophy Room.")
        .transition(reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity))
        .onAppear {
            postAnnouncement(batch.accessibilityAnnouncement)
            fireFeedback(style: style)
        }
    }

    /// Posts the VoiceOver announcement (design.md §6). No-op off-UIKit.
    private func postAnnouncement(_ text: String) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: text)
        #endif
    }

    /// Fires the grade's haptic + the one signature unlock sound. Respects
    /// the player's haptics/sound settings (design.md §6). NEVER grants
    /// anything — feedback only.
    private func fireFeedback(style: TrophyGradeStyle) {
        #if canImport(UIKit)
        if hapticsEnabled {
            let generator: UIImpactFeedbackGenerator
            switch style.impact {
            case .light:  generator = UIImpactFeedbackGenerator(style: .light)
            case .medium: generator = UIImpactFeedbackGenerator(style: .medium)
            case .heavy:  generator = UIImpactFeedbackGenerator(style: .heavy)
            }
            generator.impactOccurred()
            if style.diamondDoubleTap {
                // Diamond's signature second pulse (design.md §6).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                }
            }
        }
        #endif
        // One signature unlock sound for every grade (the sound is the
        // brand — design.md §6). Reuse the win chime; respects `sound`.
        AudioManager.shared.playWin(enabled: soundEnabled)
    }
}

// MARK: - Host overlay

/// Drops the toast banner over any result surface. Observes the queue,
/// presents the current batch, and owns the auto-dismiss timer + tap
/// deep-link. Surface wiring (which overlays adopt this) is S2-T2; this is
/// the reusable piece it attaches.
struct TrophyToastHost: View {

    @ObservedObject var queue: TrophyToastQueue
    var hapticsEnabled: Bool = true
    var soundEnabled: Bool = true
    /// Called when the player taps the banner (S2-T2 routes to the room).
    var onOpenTrophyRoom: ((TrophyToastBatch) -> Void)? = nil

    /// Seconds a banner stays before auto-dismiss (design.md §6 ~3s).
    var autoDismissSeconds: Double = 3.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if let batch = queue.presented {
                TrophyToastBanner(batch: batch,
                                  hapticsEnabled: hapticsEnabled,
                                  soundEnabled: soundEnabled,
                                  onTap: { onOpenTrophyRoom?(batch) })
                    .id(batch.id)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .task(id: batch.id) {
                        // Auto-dismiss after the dwell window. Cancels
                        // cleanly if the batch changes (new .task id).
                        let ns = UInt64(autoDismissSeconds * 1_000_000_000)
                        try? await Task.sleep(nanoseconds: ns)
                        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) {
                            queue.dismissPresented()
                        }
                    }
            }
            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8),
                   value: queue.presented?.id)
        .allowsHitTesting(queue.presented != nil)
    }
}
