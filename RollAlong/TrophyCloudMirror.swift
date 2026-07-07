//
//  TrophyCloudMirror.swift
//  RollAlong
//
//  S3-T8 — iCloud KV trophy-ratchet mirror (docs/trophies/sprint-plan.md §2
//  S3-T8; design.md §4 "Reinstall / device-transfer persistence"). Mirrors the
//  trophy ratchet (`ra_trophyUnlocks` id set + `ra_trophyUnlockDates`) to
//  `NSUbiquitousKeyValueStore` so a delete+reinstall with no device backup —
//  and a two-device split — still converges to the UNION of every unlock.
//
//  MERGE RULE (design.md §4 "union, max-merge on timestamps", NEVER
//  subtraction): the mirror only ever GROWS a store. A pull unions the cloud
//  set INTO the engine (via `TrophyEngine.mergeUnlocks`, first-stamp-wins); a
//  push unions the engine's set INTO the cloud (never deleting a cloud id the
//  engine lacks — that id is some other device's real unlock). The ratchet can
//  therefore never lose an unlock in either direction, and two stores that both
//  push-then-pull converge to the same union.
//
//  TINY PAYLOAD: the ratchet is one id array + one [id: epoch] map — far under
//  the NSUbiquitousKeyValueStore 1 MB total / 1024-key caps (the whole thing is
//  a handful of KB). Stored under TWO keys so a partial cloud write heals toward
//  MORE unlocked, exactly like the local UserDefaults ledger.
//
//  GRACEFUL DEGRADATION (S3-T8 acceptance): the iCloud KV *entitlement*
//  (`com.apple.developer.ubiquity-kvstore-identifier`) is a Mac-owned Xcode
//  capability change — today's posture is "no iCloud KV in use". When the store
//  is unavailable (entitlement missing, user signed out of iCloud, iCloud KV
//  disabled) every method is a silent LOCAL-ONLY no-op: no crash, no thrown
//  error into the UI, the app runs exactly as it does today. The mirror is a
//  bonus restore path, never a dependency.
//
//  TESTABILITY (S3 hard rule — no live iCloud in tests): all store access is
//  behind the `TrophyKeyValueStore` protocol, so the union / max-merge /
//  convergence / graceful-no-op logic is proven against an in-memory double
//  with ZERO `NSUbiquitousKeyValueStore` calls. The real
//  `UbiquitousTrophyKVStore` below wraps the system store.
//

import Foundation

// ===========================================================================
// Key-value store abstraction — the ONLY seam that touches iCloud.
// ===========================================================================

/// The minimal slice of `NSUbiquitousKeyValueStore` the mirror needs. Injected
/// into `TrophyCloudMirror` so the merge logic is unit-testable against an
/// in-memory double. `isAvailable == false` models "no entitlement / signed out
/// of iCloud"; the mirror then no-ops locally.
protocol TrophyKeyValueStore: AnyObject {
    /// Whether the backing store is usable right now. `false` → the mirror runs
    /// local-only (graceful degradation); every read returns empty, every write
    /// is dropped. The real store reports `true` once the entitlement is present
    /// AND the device has an iCloud account.
    var isAvailable: Bool { get }

    /// The persisted unlock id array (mirror of `ra_trophyUnlocks`); [] when
    /// absent or unavailable.
    func unlockIDs() -> [String]

    /// The persisted `[trophyID: firstUnlockEpochSeconds]` map (mirror of
    /// `ra_trophyUnlockDates`); [:] when absent or unavailable.
    func unlockDateEpochs() -> [String: Double]

    /// Overwrite both keys with the given union. A no-op when unavailable. The
    /// caller has already unioned cloud ∪ local, so this only ever writes a set
    /// that is a superset of what was there.
    func writeUnlocks(ids: [String], dateEpochs: [String: Double])

    /// Best-effort flush to iCloud (the system store also syncs opportunistically
    /// on its own). A no-op when unavailable.
    func synchronize()

    /// The object `NSUbiquitousKeyValueStore.didChangeExternallyNotification`
    /// is posted from — the value the mirror scopes its external-change observer
    /// to. `nil` when unavailable (no entitlement / signed out of iCloud) OR for
    /// the in-memory test double, so `start(engine:onExternalChange:)` registers
    /// nothing and is a pure no-op off-device. The real store returns the system
    /// `NSUbiquitousKeyValueStore` it wraps.
    var notificationObject: AnyObject? { get }
}

// ===========================================================================
// TrophyCloudMirror — orchestrates pull-merge-push. No iCloud calls of its own.
// ===========================================================================

/// Two-way ratchet mirror between `TrophyEngine` and an iCloud KV store.
///
/// Own type (not on the engine) so the iCloud seam stays injectable and a
/// mirror pass never re-renders gameplay. `@MainActor`-free like the engine and
/// `TrophySyncService` (S2 note): the merge touches the engine's ledger, which
/// is not `@MainActor`; callers invoke it at launch / foreground / on the store's
/// external-change notification.
final class TrophyCloudMirror {

    static let shared = TrophyCloudMirror()

    private let store: TrophyKeyValueStore

    /// The live external-change observer token, retained so a repeat `start`
    /// tears the old one down first (idempotent wiring — no duplicate reconciles
    /// if the app re-registers). `nil` until `start` registers one, and stays
    /// `nil` forever when iCloud KV is unavailable (graceful no-op).
    private var externalChangeObserver: NSObjectProtocol?

    init(store: TrophyKeyValueStore) {
        self.store = store
    }

    private convenience init() {
        self.init(store: UbiquitousTrophyKVStore())
    }

    // MARK: - Reconcile (pull ∪ local, then push the union back)

    /// One full reconciliation pass. Idempotent and convergent:
    ///  1. PULL — union the cloud ratchet INTO the engine
    ///     (`engine.mergeUnlocks`, first-stamp-wins). Restores unlocks after a
    ///     delete+reinstall and absorbs another device's unlocks.
    ///  2. PUSH — union the engine's (now-merged) ratchet BACK to the cloud,
    ///     never removing a cloud id the engine lacks. This publishes THIS
    ///     device's local-only unlocks to the cloud so the other device gets
    ///     them on its next pull.
    ///
    /// Because both steps are unions and neither ever subtracts, two devices
    /// that each run `reconcile()` converge to the same union regardless of
    /// order (the CRDT grow-only-set property). Returns the ids this pass newly
    /// latched locally (from the pull) — [] when the cloud added nothing new
    /// (the steady-state, fully-converged case).
    ///
    /// When the store is unavailable this is a pure local no-op: the pull reads
    /// empty (adds nothing) and the push is dropped. Never throws.
    @discardableResult
    func reconcile(engine: TrophyEngine) -> [String] {
        guard store.isAvailable else { return [] }

        // 1. PULL — cloud → engine (union, first-stamp-wins).
        let cloudIDs = Set(store.unlockIDs())
        let cloudDates = Self.datesFromEpochs(store.unlockDateEpochs())
        // A cloud id may carry a stamp but be absent from the id array (a healed
        // partial cloud write); mergeUnlocks unions ids ∪ date-keys, so the id
        // survives either way.
        let newlyLatched = engine.mergeUnlocks(ids: cloudIDs, dates: cloudDates)

        // 2. PUSH — engine → cloud (union; never delete a cloud-only id).
        pushToCloud(engine: engine, existingCloudIDs: cloudIDs, existingCloudDates: cloudDates)

        return newlyLatched
    }

    /// Push-only: mirror the engine's current ratchet UP to the cloud, unioned
    /// with whatever is already there (never subtractive). Called by `reconcile`
    /// after the pull, and can be called standalone right after a local unlock
    /// so the cloud learns about it promptly (before the next launch's pull).
    ///
    /// `existingCloudIDs` / `existingCloudDates` let `reconcile` reuse the read
    /// it already did; a standalone caller passes nothing and we read the store.
    /// A no-op when unavailable, or when the engine's set is already a subset of
    /// the cloud's (nothing new to write) — the convergent steady state.
    func pushToCloud(engine: TrophyEngine,
                     existingCloudIDs: Set<String>? = nil,
                     existingCloudDates: [String: Date]? = nil) {
        guard store.isAvailable else { return }

        let cloudIDs = existingCloudIDs ?? Set(store.unlockIDs())
        let cloudDates = existingCloudDates ?? Self.datesFromEpochs(store.unlockDateEpochs())

        let localIDs = engine.unlockedIDs
        let localDates = engine.allUnlockDates

        // Union of ids: cloud ∪ local (never drop a cloud-only id — it belongs
        // to another device). Union of dates: first-unlock (earliest) wins, so
        // the cloud keeps the earliest known first-unlock instant for a shared
        // id — the same max-merge rule the pull applies locally, symmetric so
        // both stores converge.
        let unionIDs = cloudIDs.union(localIDs)
        var unionDates = cloudDates
        for (id, localDate) in localDates {
            if let cloudDate = unionDates[id] {
                if localDate < cloudDate { unionDates[id] = localDate }
            } else {
                unionDates[id] = localDate
            }
        }

        // Nothing new to write → skip the round-trip (steady-state no-op). Both
        // the id set and every shared date already match the cloud.
        if unionIDs == cloudIDs && unionDates == cloudDates { return }

        store.writeUnlocks(ids: Array(unionIDs).sorted(),
                           dateEpochs: Self.epochsFromDates(unionDates))
        store.synchronize()
    }

    // MARK: - Live external-change observer (cross-device convergence WHILE OPEN)

    /// Register the `NSUbiquitousKeyValueStore.didChangeExternallyNotification`
    /// observer so a unlock earned on ANOTHER device lands here while THIS app is
    /// open — not just at the next launch/foreground reconcile (RollAlongApp's
    /// existing lifecycle passes). On each external change we `reconcile(engine:)`
    /// (pull the cloud's newer union in, push ours back) and then invoke
    /// `onExternalChange` — the app hands us a closure that flushes the (now
    /// possibly-larger, dirty-flagged) ledger to the Supabase rails, mirroring the
    /// launch/foreground reconcile→sync ordering. The mirror deliberately owns no
    /// `TrophySyncService` dependency; the sync is the caller's concern.
    ///
    /// Graceful degradation (S3-T8 acceptance): when iCloud KV is unavailable
    /// (entitlement missing / signed out of iCloud) `store.notificationObject` is
    /// `nil`, so NOTHING is registered and this is a pure no-op — the app behaves
    /// exactly as today. Idempotent: a second `start` tears the prior observer
    /// down first, so re-wiring never doubles reconciles.
    ///
    /// The callback runs on the notification-delivery queue (`.main`); `reconcile`
    /// is `@MainActor`-free and touches only the engine ledger, so this is safe
    /// off the render hot path exactly like the launch pass.
    func start(engine: TrophyEngine, onExternalChange: @escaping () -> Void) {
        // Idempotent: drop any prior observer before re-registering.
        if let existing = externalChangeObserver {
            NotificationCenter.default.removeObserver(existing)
            externalChangeObserver = nil
        }

        // No entitlement / signed out of iCloud → nothing to observe. Pure no-op.
        guard let object = store.notificationObject else { return }

        // Pull the store into sync on registration so we don't miss a change that
        // landed between the launch reconcile and now (best-effort; the system
        // store also syncs opportunistically).
        store.synchronize()

        externalChangeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: object,
            queue: .main
        ) { [weak self, weak engine] _ in
            guard let self, let engine else { return }
            // Union the cloud's external change INTO the local ledger (and push
            // ours back). Reconcile is a no-op when nothing new arrived.
            _ = self.reconcile(engine: engine)
            // Let the app flush the possibly-grown, dirty-flagged ledger to the
            // backend rails (reconcile arms ra_trophySyncDirty on a new id).
            onExternalChange()
        }
    }

    // MARK: - Epoch <-> Date (iCloud KV stores plist-native scalars)

    /// `NSUbiquitousKeyValueStore` persists numbers, not `Date`s — store each
    /// first-unlock instant as an epoch-seconds `Double` so the payload stays a
    /// plain plist dictionary (no archiving) and cross-version-safe.
    private static func datesFromEpochs(_ epochs: [String: Double]) -> [String: Date] {
        epochs.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private static func epochsFromDates(_ dates: [String: Date]) -> [String: Double] {
        dates.mapValues { $0.timeIntervalSince1970 }
    }
}

// ===========================================================================
// UbiquitousTrophyKVStore — the real NSUbiquitousKeyValueStore wrapper.
//
// Degrades gracefully: `isAvailable` is false whenever the entitlement is
// missing or the device has no iCloud account, and every accessor tolerates the
// unavailable state so the app never crashes on a device without iCloud KV.
// ===========================================================================

final class UbiquitousTrophyKVStore: TrophyKeyValueStore {

    /// Keys inside the ubiquitous store. Namespaced `ra_trophy_*` to match the
    /// local `ra_trophy*` ledger keys; distinct value shapes (id array + epoch
    /// map) so a partial cloud write heals toward MORE unlocked.
    private static let idsKey = "ra_trophy_cloud_unlocks"
    private static let datesKey = "ra_trophy_cloud_unlock_dates"

    /// The system store. `NSUbiquitousKeyValueStore.default` is safe to
    /// reference even without the entitlement (it just never syncs); we gate all
    /// real use behind `isAvailable` so a mis-provisioned build is inert, not
    /// crashing.
    private let store: NSUbiquitousKeyValueStore

    /// Cached availability. iCloud KV is usable when the entitlement is present
    /// AND the device has an iCloud (ubiquity) identity. `ubiquityIdentityToken`
    /// is nil when the user is signed out of iCloud — the cheap, allocation-free
    /// availability probe Apple documents for exactly this.
    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    /// Observe `didChangeExternallyNotification` on the wrapped system store —
    /// but only when iCloud KV is actually usable, so a build without the
    /// entitlement never wires up an observer that can't fire. `nil` here makes
    /// `TrophyCloudMirror.start` a graceful no-op.
    var notificationObject: AnyObject? {
        isAvailable ? store : nil
    }

    func unlockIDs() -> [String] {
        guard isAvailable else { return [] }
        return (store.array(forKey: Self.idsKey) as? [String]) ?? []
    }

    func unlockDateEpochs() -> [String: Double] {
        guard isAvailable else { return [:] }
        guard let raw = store.dictionary(forKey: Self.datesKey) else { return [:] }
        // Tolerate NSNumber-boxed values (plist round-trip) → Double.
        var out: [String: Double] = [:]
        for (k, v) in raw {
            if let n = v as? NSNumber { out[k] = n.doubleValue }
        }
        return out
    }

    func writeUnlocks(ids: [String], dateEpochs: [String: Double]) {
        guard isAvailable else { return }
        store.set(ids, forKey: Self.idsKey)
        store.set(dateEpochs, forKey: Self.datesKey)
    }

    func synchronize() {
        guard isAvailable else { return }
        store.synchronize()
    }
}
