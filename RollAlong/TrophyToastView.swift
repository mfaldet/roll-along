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
///
/// NOT `@MainActor`: it mirrors `TrophyEngine`, this codebase's established
/// pattern for a trophy `ObservableObject` — GameState owns it as a plain
/// `let` and drives it (via `fireTrophy` / `beginTrophyRun` / `endTrophyRun`)
/// from its gameplay funnels, which all run on the main thread already (the
/// SwiftUI view event handlers + the `@MainActor` StoreKit/Ad managers).  Its
/// `@Published` mutations therefore land on main in practice, exactly as the
/// engine's do; keeping it off the global actor lets GameState's non-isolated
/// funnels call it without an actor hop (S2-T2).
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

// MARK: - Capstone celebration (S2-T5)

//  ---------------------------------------------------------------------------
//  The Platinum capstone (`capstone_all`, display name "Platinum") is the ONE
//  trophy that escalates past the small banner: a full-screen, one-time moment
//  with a unique fanfare + heavy haptics + a confetti burst, auto-offering a
//  `ResultShareCard` share (design.md §6 "capstone blowout"; sprint-plan.md §2
//  S2-T5). "Escalate exactly once — standard unlocks stay small" (PS research:
//  single escalation) is enforced two ways, belt-and-suspenders:
//
//    (1) the capstone is SPLIT OFF the small-toast feed in GameState.fireTrophy
//        so it never shows as a Diamond-style banner; and
//    (2) `CapstoneCelebrationModel` latches the full-screen moment against BOTH
//        the engine's unlock state AND a durable `ra_trophyCapstonePresented`
//        flag, so the blowout fires exactly once ever and never again — a
//        relaunch, a replay, or a stray re-record can't re-trigger it.
//
//  Reduce Motion is honored: the confetti/scale burst is swapped for a static
//  crossfade treatment (design.md §6 accessibility; §11 acceptance).
//
//  NEVER-MINT (D1): the celebration is display-only. It reads the ledger + the
//  equipped cosmetics and shares an image; it grants no coins and no cosmetics
//  (the capstone's regalia reward is D8, unbuilt — `rewardID` is nil in v1).
//  ---------------------------------------------------------------------------

/// The one-time, latched-forever celebration state for the Platinum capstone.
///
/// Deliberately a plain `ObservableObject` with NO View dependency, so its
/// fire-exactly-once policy is unit-testable in isolation (S2-T5 acceptance).
/// It mirrors `TrophyToastQueue`: GameState owns it as a plain `let` and drives
/// it from the same main-thread funnels, so its `@Published` mutations land on
/// main in practice without pinning it to the global actor.
final class CapstoneCelebrationModel: ObservableObject {

    /// Durable "the full-screen moment has already played" flag. Survives
    /// relaunch so the blowout is a true once-ever event (S2-T5: "fires exactly
    /// once ever"). Documented in the GameState.swift `ra_*` audit header.
    static let presentedKey = "ra_trophyCapstonePresented"

    /// The capstone id is frozen forever (design.md §11 #14 / §2 ruling); the
    /// display name is "Platinum" but the id is unchanged.
    static let capstoneID = "capstone_all"

    /// The capstone definition to celebrate, or nil when nothing is pending.
    /// A non-nil value is the single signal the host view renders the
    /// full-screen moment for. Cleared the instant `markPresented()` runs.
    @Published private(set) var pending: TrophyDefinition?

    /// Whether the once-ever moment has already played (loaded from
    /// `presentedKey`; set permanently by `markPresented()`). Once true,
    /// `celebrateIfEarned` can never arm the moment again.
    @Published private(set) var hasPresented: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasPresented = defaults.bool(forKey: Self.presentedKey)
    }

    /// Arm the full-screen moment IFF the capstone is genuinely earned on the
    /// engine AND the moment has never played. Idempotent and latched: a second
    /// call (double-fire, replay, relaunch) with the flag already set is a
    /// no-op, so the blowout escalates exactly once ever (S2-T5 acceptance).
    ///
    /// Pass the LIVE-unlocked ids of the current bump (from `TrophyEngine.record`)
    /// so the moment only arms on the bump that actually latches the capstone —
    /// but the engine unlock-state gate below is the real guard, so passing the
    /// engine alone (e.g. on a launch re-check) also works and stays latched.
    ///
    /// Returns true iff this call armed the moment (for the caller/test).
    @discardableResult
    func celebrateIfEarned(engine: TrophyEngine) -> Bool {
        guard !hasPresented else { return false }
        guard engine.isUnlocked(Self.capstoneID) else { return false }
        guard let def = engine.catalog.trophy(withID: Self.capstoneID) else { return false }
        // Already armed and waiting to show — don't re-arm (idempotent).
        guard pending == nil else { return false }
        pending = def
        return true
    }

    /// Mark the moment as played, forever. Persists the flag synchronously and
    /// clears the pending signal so the host dismisses. After this, no code
    /// path can re-arm the celebration (the ratchet on the presentation itself,
    /// on top of the trophy ledger's own ratchet).
    func markPresented() {
        pending = nil
        guard !hasPresented else { return }
        hasPresented = true
        defaults.set(true, forKey: Self.presentedKey)
    }

    // MARK: Test-only introspection

    #if DEBUG
    /// Whether a full-screen moment is currently armed (test assertions).
    var isArmed: Bool { pending != nil }
    #endif
}

/// The full-screen capstone blowout. Reads the pending capstone definition +
/// the player's equipped cosmetics (for the share card) and renders the big
/// trophy, a unique fanfare + heavy haptics, a confetti burst (Reduce Motion →
/// static), and a `ResultShareCard`-based share. Auto-dismiss is a tap / the
/// Done button — a once-ever moment does not time out under the player.
struct CapstoneCelebrationView: View {

    /// The capstone being celebrated (its title/description drive the copy).
    let trophy: TrophyDefinition
    /// The player's equipped ball skin — their identity on the share card.
    let skin: BallSkin
    /// The player's equipped trail.
    let trail: TrailColor
    var hapticsEnabled: Bool = true
    var soundEnabled: Bool = true
    /// Called when the player dismisses the moment (Done / tap-through). The
    /// host uses this to `markPresented()` so it never shows again.
    var onDismiss: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the entrance scale/pop of the trophy (skipped under Reduce Motion).
    @State private var appeared = false

    /// The share payload — the capstone rendered on the existing share card
    /// grammar. `won: true` tints it gold, matching the regalia framing.
    private var shareResult: ShareableResult {
        ShareableResult(mode: "Platinum",
                        headline: trophy.title,
                        subtitle: "Capstone earned",
                        skin: skin,
                        trail: trail,
                        won: true)
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop — the moment owns the whole screen.
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            // Confetti burst BEHIND the trophy card — swapped for a calm
            // static shimmer under Reduce Motion (design.md §6 accessibility).
            if reduceMotion {
                CapstoneStaticTreatment()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            } else {
                CapstoneConfettiBurst()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            VStack(spacing: 22) {
                Text("PLATINUM")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.85))

                // The trophy, rendered big. The capstone grade glyph — NOT the
                // Diamond-ball cosmetic gem (design.md §2 R2): the rosette is
                // the capstone's own mark.
                Image(systemName: "rosette")
                    .font(.system(size: 96, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [Color(hexRGB: "#EAF0FA") ?? .white,
                                                Color(hexRGB: "#AFC0DA") ?? .gray],
                                       startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
                    .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.6))
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text(trophy.title)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                    // Grade-side copy only — never "cosmetic" (§2 R2 copy rider).
                    Text(trophy.unlockedDescription)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 8)
                }

                // Auto-offered share (design.md §6 "auto-composed share card").
                ResultShareButton(result: shareResult)
                    .frame(maxWidth: 320)

                Button {
                    onDismiss?()
                } label: {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: 320)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.25), lineWidth: 1))
                }
                .accessibilityLabel("Dismiss the Platinum capstone celebration")
            }
            .padding(28)
        }
        // One a11y grouping speaking the capstone win; grade named, never
        // color-only (design.md §6). VoiceOver hears it as one announcement.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Platinum capstone unlocked: \(trophy.title).")
        .transition(reduceMotion ? .opacity
                    : .scale(scale: 0.9).combined(with: .opacity))
        .onAppear {
            fireFanfare()
            if !reduceMotion {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    appeared = true
                }
            }
        }
    }

    /// The capstone's UNIQUE fanfare + heavy haptics — deliberately bigger than
    /// the standard unlock chime (design.md §6 "unique fanfare distinct from the
    /// standard chime"). Respects the player's sound/haptics settings.
    private func fireFanfare() {
        #if canImport(UIKit)
        if hapticsEnabled {
            // A success notification + a heavy impact — heavier than any
            // standard-grade banner haptic (design.md §6).
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        #endif
        // A distinct fanfare, layered so it reads as bigger than the standard
        // win chime that every grade banner uses. Respects the sound setting.
        AudioManager.shared.playCapstoneFanfare(enabled: soundEnabled)
    }
}

/// The animated confetti burst behind the capstone trophy. A lightweight
/// timeline of drifting rounded rectangles — the celebratory motion the
/// Reduce-Motion branch replaces with `CapstoneStaticTreatment`.
private struct CapstoneConfettiBurst: View {
    private let pieces = 42
    private let colors: [Color] = [
        Color(hexRGB: "#E7B93B") ?? .yellow,
        Color(hexRGB: "#8A5CF6") ?? .purple,
        Color(hexRGB: "#4FC3F7") ?? .cyan,
        Color(hexRGB: "#FF6B6B") ?? .red,
        Color(hexRGB: "#EAF0FA") ?? .white
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                Canvas { ctx, size in
                    for i in 0..<pieces {
                        let seed = Double(i) * 0.6180339887
                        let x = (seed.truncatingRemainder(dividingBy: 1)) * size.width
                        // Fall loops every ~3.5s, offset per piece.
                        let phase = (t / 3.5 + seed).truncatingRemainder(dividingBy: 1)
                        let y = phase * (size.height + 40) - 40
                        let sway = sin(t * 1.8 + seed * 6.28) * 14
                        let rot = Angle(radians: t * 2 + seed * 6.28)
                        let color = colors[i % colors.count]
                        var rect = Path(roundedRect:
                            CGRect(x: -4, y: -6, width: 8, height: 12),
                            cornerRadius: 2)
                        rect = rect.applying(
                            CGAffineTransform(translationX: x + sway, y: y)
                                .rotated(by: rot.radians))
                        ctx.fill(rect, with: .color(color.opacity(0.9)))
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
}

/// The Reduce-Motion-safe replacement for the confetti: a still, gentle
/// radial glow with no animation (design.md §6 "swaps confetti for a static
/// treatment"; S2-T5 acceptance requires this branch to exist in code).
private struct CapstoneStaticTreatment: View {
    var body: some View {
        RadialGradient(
            colors: [Color(hexRGB: "#8A5CF6")?.opacity(0.28) ?? .clear, .clear],
            center: .center, startRadius: 20, endRadius: 420)
        .ignoresSafeArea()
    }
}

/// Drops the capstone full-screen moment over any surface. Observes the model,
/// renders the moment while `pending` is non-nil, and calls `markPresented()`
/// on dismiss so it never shows again. Surface wiring (which overlays adopt
/// this) rides the same result surfaces the toast host does.
struct CapstoneCelebrationHost: View {

    @ObservedObject var model: CapstoneCelebrationModel
    /// The player's equipped cosmetics for the share card.
    let skin: BallSkin
    let trail: TrailColor
    var hapticsEnabled: Bool = true
    var soundEnabled: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let trophy = model.pending {
                CapstoneCelebrationView(
                    trophy: trophy,
                    skin: skin,
                    trail: trail,
                    hapticsEnabled: hapticsEnabled,
                    soundEnabled: soundEnabled,
                    onDismiss: { model.markPresented() })
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35),
                   value: model.pending?.id)
        .allowsHitTesting(model.pending != nil)
    }
}

// MARK: - Retroactive-grant reveal (S2-T6)

//  ---------------------------------------------------------------------------
//  The one-time "Trophy Room unlocked — you've already earned N" reveal
//  (sprint-plan.md §2 S2-T6; design.md §6 "Anti-spam batching: retroactive
//  grants at launch get a SINGLE one-time summary — never a toast cascade").
//
//  A veteran opening the trophy update qualifies for many trophies instantly
//  (the S0-T4 backfill grants them all at once with a `legacyUnlockDate`
//  stamp). Those grandfathered unlocks deliberately BYPASS the small-toast
//  feed (`GameState.activateTrophies` never routes through `fireTrophy`), so
//  they never storm the banner. This model owns the ONE coalesced moment they
//  get instead: a single banner announcing how many were earned, offered on
//  the first open after the update and NEVER again.
//
//  "Exactly once" is latched two ways, belt-and-suspenders (the capstone
//  pattern):
//    (1) it arms only when the engine's own `didBackfill` flag is set AND the
//        backfill granted ≥ 1 trophy (`backfillGrantCount`); and
//    (2) `TrophyRevealModel` latches the reveal against a durable
//        `ra_trophyRevealPresented` flag, so a relaunch — where `didBackfill`
//        and `backfillGrantCount` still read true/N forever (they are the
//        historical fact, a ratchet) — never re-offers it.
//
//  NEVER-MINT (D1): the reveal is display-only. It reads the engine's backfill
//  counters and grants nothing.
//  ---------------------------------------------------------------------------

/// The one-time, latched-forever state for the retroactive-grant reveal.
///
/// Deliberately a plain `ObservableObject` with NO View dependency, so its
/// offer-exactly-once policy is unit-testable in isolation (S2-T6 acceptance).
/// It mirrors `CapstoneCelebrationModel`: GameState owns it as a plain `let`
/// and arms it from `activateTrophies()` (the same launch call that runs the
/// backfill), so its `@Published` mutations land on main in practice without
/// pinning it to the global actor.
final class TrophyRevealModel: ObservableObject {

    /// Durable "the retro-grant reveal has already been offered" flag. Survives
    /// relaunch so the summary is a true once-ever event (S2-T6: "flag clears
    /// after presentation"). Documented in the GameState.swift `ra_*` audit
    /// header alongside the other trophy keys.
    static let presentedKey = "ra_trophyRevealPresented"

    /// The number of trophies the one-time backfill granted, or nil when no
    /// reveal is pending. A non-nil value is the single signal the host view
    /// renders the banner for. Cleared the instant `markPresented()` runs.
    @Published private(set) var pendingCount: Int?

    /// Whether the once-ever reveal has already been offered (loaded from
    /// `presentedKey`; set permanently by `markPresented()`). Once true,
    /// `revealIfOwed` can never arm the reveal again.
    @Published private(set) var hasPresented: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasPresented = defaults.bool(forKey: Self.presentedKey)
    }

    /// Arm the reveal IFF the first-launch backfill has run, granted at least
    /// one trophy, AND the reveal has never been offered. Idempotent and
    /// latched: a second call (a relaunch, a re-check) with the flag already
    /// set — or while a reveal is already armed — is a no-op, so the summary is
    /// offered exactly once ever (S2-T6 acceptance).
    ///
    /// A fresh install (backfill ran but granted 0) never arms — there is
    /// nothing to reveal, so the reveal is silently retired the same way
    /// (`markPresented` on the empty path keeps the flag honest without a
    /// banner). Reads the engine's public backfill counters only; it never
    /// mutates the ledger or the economy (D1 never-mint).
    ///
    /// Returns true iff this call armed the reveal (for the caller/test).
    @discardableResult
    func revealIfOwed(engine: TrophyEngine) -> Bool {
        guard !hasPresented else { return false }
        // The backfill hasn't run yet (activateTrophies not called): don't
        // decide anything — a later call after backfill will.
        guard engine.didBackfill else { return false }
        // Backfill ran but granted nothing (a fresh install / a save already
        // at zero derivable trophies): there is nothing to reveal. Retire the
        // reveal permanently so it never considers this save again, and show
        // no banner.
        guard engine.backfillGrantCount > 0 else {
            markPresented()
            return false
        }
        // Already armed and waiting to show — don't re-arm (idempotent).
        guard pendingCount == nil else { return false }
        pendingCount = engine.backfillGrantCount
        return true
    }

    /// Mark the reveal as offered, forever. Persists the flag synchronously and
    /// clears the pending signal so the host dismisses. After this, no code
    /// path can re-arm the reveal (a ratchet on the presentation itself, on top
    /// of the backfill flag's own once-ever guarantee).
    func markPresented() {
        pendingCount = nil
        guard !hasPresented else { return }
        hasPresented = true
        defaults.set(true, forKey: Self.presentedKey)
    }

    // MARK: Test-only introspection

    #if DEBUG
    /// Whether a reveal is currently armed (test assertions).
    var isArmed: Bool { pendingCount != nil }
    #endif
}

/// The single coalesced retro-grant banner. Reads the granted count and
/// renders a one-line "Trophy Room unlocked — you've already earned N" card in
/// the toast grammar, tappable to open the Trophy Room. Accessible: a
/// VoiceOver announcement + `accessibilityLabel`, Dynamic-Type scalable fonts,
/// and `@Environment(\.accessibilityReduceMotion)` honored. Display-only.
struct TrophyRevealBanner: View {

    /// How many trophies the backfill granted (the "N").
    let grantedCount: Int
    /// Honored from GameState by the host; defaulted so the view previews.
    var hapticsEnabled: Bool = true
    /// Tapping the banner deep-links into the Trophy Room. Optional so the
    /// banner renders standalone in tests/previews.
    var onOpen: (() -> Void)? = nil
    /// Dismiss without opening the room (the close affordance).
    var onDismiss: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The reveal wears the gold medal mark — a celebratory, grade-neutral
    /// summary glyph (NOT a specific rung's, and NEVER the Diamond-ball gem —
    /// §2 R2). One source of truth for the accent: the gold grade style.
    private var accent: Color { TrophyGradeStyle.forTier(.gold).accent }

    /// "…you've already earned 12" / "…you've already earned 1 trophy" — the
    /// count-correct headline (design.md §6 summary copy).
    private var headline: String { "Trophy Room unlocked" }
    private var subline: String {
        let noun = grantedCount == 1 ? "trophy" : "trophies"
        return "You've already earned \(grantedCount) \(noun) — tap to see them."
    }

    var announcement: String {
        let noun = grantedCount == 1 ? "trophy" : "trophies"
        return "Trophy Room unlocked. You've already earned \(grantedCount) \(noun). Tap to open the Trophy Room."
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)

            Button {
                onDismiss?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.85), lineWidth: 2)
        )
        .overlay(alignment: .leading) {
            // Accent rail — the trophy glyph above is the second, non-color
            // cue, so the moment is never conveyed by color alone.
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 4)
                .padding(.vertical, 8)
                .padding(.leading, 2)
                .accessibilityHidden(true)
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
        // One a11y element for the tappable card (the close button stays its
        // own element). Speaks the summary; opens the room on activation.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(announcement)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the Trophy Room.")
        .transition(reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity))
        .onAppear {
            postAnnouncement(announcement)
            fireFeedback()
        }
    }

    /// Posts the VoiceOver announcement (design.md §6). No-op off-UIKit.
    private func postAnnouncement(_ text: String) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: text)
        #endif
    }

    /// A single soft haptic when the summary appears — respects the player's
    /// haptics setting. NEVER grants anything (feedback only).
    private func fireFeedback() {
        #if canImport(UIKit)
        if hapticsEnabled {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        #endif
    }
}

/// Drops the retro-grant reveal over the Home surface. Observes the model,
/// renders the single banner while `pendingCount` is non-nil, and calls
/// `markPresented()` on open OR dismiss so it never shows again. Surface
/// wiring (Home adopts this) rides `activateTrophies()` at launch.
struct TrophyRevealHost: View {

    @ObservedObject var model: TrophyRevealModel
    var hapticsEnabled: Bool = true
    /// Called when the player taps the banner to open the Trophy Room. The
    /// host marks the reveal presented, then routes.
    var onOpenTrophyRoom: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if let count = model.pendingCount {
                TrophyRevealBanner(
                    grantedCount: count,
                    hapticsEnabled: hapticsEnabled,
                    onOpen: {
                        model.markPresented()
                        onOpenTrophyRoom?()
                    },
                    onDismiss: { model.markPresented() })
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8),
                   value: model.pendingCount)
        .allowsHitTesting(model.pendingCount != nil)
    }
}
