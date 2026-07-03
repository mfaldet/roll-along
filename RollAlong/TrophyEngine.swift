//
//  TrophyEngine.swift
//  RollAlong
//
//  S0-T3 — Trophy evaluation core (docs/trophies/sprint-plan.md §2 S0-T3;
//  design.md §4 Option C layer 1; trophy-catalog.md §6 items 1–2).
//
//  The engine is the ONLY writer of the trophy ledger, and the ledger is a
//  pure ratchet: a trophy latches exactly once, with a timestamp, forever.
//  Nothing here can revoke an unlock — not `resetProgress()`, not Sell Back
//  liquidation, not a regressed stat pushed back through `record`. Unlock
//  state is never re-derived from live stats (sprint-plan.md §4 addenda).
//
//  Hot-path contract (S0-T3 acceptance; S4-T2 budget <0.5ms p99 per bump —
//  `consumeLife`/`recordResult` fire mid-run):
//  • A stat bump evaluates ONLY the trophies interested in that metric —
//    one dictionary lookup into an index built once at init, then
//    O(interested trophies), never O(catalog).
//  • A bump that unlocks nothing performs ZERO UserDefaults writes and
//    ZERO `objectWillChange` emissions.
//  • Persistence is plist-native (the GameState `saveStringSet` pattern
//    for the id set; a String-keyed Date dictionary for timestamps) — no
//    JSON encoding anywhere, on or off the hot path.
//
//  Observability: trophy state lives in THIS ObservableObject — it is
//  deliberately NOT `@Published` on `GameState`, so gameplay views
//  observing GameState never re-render on trophy writes (S0-T3 acceptance;
//  §5 regression table). Only future trophy UI observes this object.
//
//  Value-push model: callers (GameState funnels, S1 wiring) push a
//  metric's CURRENT cumulative/latched value — never a delta. The engine
//  owns no stat bookkeeping (that is TrophyStats/GameState territory);
//  it only compares pushed values against catalog criteria and latches.
//  The single exception is the capstone's `base_trophies_unlocked`
//  metric, which the engine derives from its own ledger and refuses to
//  accept from outside.
//
//  Migration/backfill (first launch with trophies) is S0-T4 and lands in
//  this file next; offline-sync dirty-flagging is S1-T8.
//

import Foundation

/// The latched trophy engine: metric-indexed evaluation over the bundled
/// `TrophyCatalog`, with the unlock ledger persisted write-through to
/// injected `UserDefaults` (`.standard` in production, a throwaway suite
/// in tests — the GameStateTests pattern).
final class TrophyEngine: ObservableObject {

    // MARK: - Persisted ledger keys

    /// The latched unlock id set, stored as a plist string array — the
    /// GameState `saveStringSet` helper pattern (trophy-catalog.md §6
    /// item 1). Documented in the GameState.swift UserDefaults audit
    /// header alongside every other `ra_*` key.
    static let unlocksKey = "ra_trophyUnlocks"

    /// Unlock timestamps, stored as a plist `[trophyID: Date]` dictionary
    /// (String-keyed Date dicts are plist-legal, so no JSON round-trip is
    /// needed — unlike GameState's Int-keyed dict helpers).
    static let unlockDatesKey = "ra_trophyUnlockDates"

    // MARK: - Dependencies

    /// The validated, immutable v1 catalog this engine evaluates against.
    let catalog: TrophyCatalog

    private let defaults: UserDefaults

    /// Injectable clock (tests pin it; S0-T4's backfill stamps ride it).
    private let now: () -> Date

    // MARK: - Metric-keyed index (built once at init)

    /// metric → the trophies whose criteria watch it. THE hot-path
    /// structure: `record` touches exactly `trophiesByMetric[metric]`,
    /// so evaluation is O(interested trophies), never O(catalog).
    /// Ledger-provenance trophies (the capstone) are deliberately NOT in
    /// this index — they can only latch via the internal cascade.
    private let trophiesByMetric: [TrophyMetric: [TrophyDefinition]]

    /// Trophies whose criteria read the trophy ledger itself (v1: exactly
    /// `capstone_all`). Re-evaluated only when an unlock actually lands —
    /// never on a plain stat bump.
    private let ledgerTrophies: [TrophyDefinition]

    /// Per-metric progress direction: `.lessOrEqual` when every interested
    /// trophy wants lower-is-better (v1: `fastest_clear_seconds`),
    /// `.greaterOrEqual` otherwise. Drives the monotonic high-water latch.
    private let metricDirection: [TrophyMetric: TrophyComparison]

    // MARK: - Latched ledger state

    /// Every latched trophy id — the ratchet. Grows monotonically; no code
    /// path removes members. `@Published` so future trophy UI (S2) can
    /// observe it, and mutated ONLY when a new unlock lands so a no-unlock
    /// stat bump never emits `objectWillChange`.
    ///
    /// May contain ids absent from this build's catalog (e.g. a save that
    /// visited a newer app version). Ratchet rule: unknown ids are KEPT
    /// and re-persisted, never dropped — the catalog is additive-only
    /// (design.md §9) so they are somebody's real unlocks.
    @Published private(set) var unlockedIDs: Set<String>

    /// First-unlock timestamps. First stamp wins, forever — a double fire
    /// can never restamp (S0-T3 acceptance: timestamp stable).
    private var unlockDates: [String: Date]

    // MARK: - Monotonic progress high-water (in-memory)

    /// Best value ever pushed per metric THIS process lifetime (max for
    /// gte metrics, min for lte). Keeps `progressFraction` monotonic even
    /// when the underlying stat regresses mid-session (resetProgress,
    /// Sell Back). Deliberately not persisted in S0-T3 — durable progress
    /// snapshots are S1-T8; the unlock ratchet itself is always durable.
    private var bestObserved: [TrophyMetric: Double] = [:]

    #if DEBUG
    /// Test-only instrumentation: criteria checks performed by the most
    /// recent `record` call. Proves the O(interested-trophies) evaluation
    /// shape (S0-T3 acceptance) without production overhead.
    private(set) var debugLastRecordEvaluationCount = 0
    #endif

    // MARK: - Init

    /// Builds the metric index once and loads the persisted ledger.
    ///
    /// Ledger loading heals partial writes toward MORE unlocked, never
    /// less (kill-mid-write consistency, the ratchet direction): the
    /// in-memory unlock set is the UNION of the stored id set and the
    /// stored timestamp keys, so an id that reached either key survives.
    init(catalog: TrophyCatalog,
         defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init) {
        self.catalog = catalog
        self.defaults = defaults
        self.now = now

        var index: [TrophyMetric: [TrophyDefinition]] = [:]
        var ledger: [TrophyDefinition] = []
        var direction: [TrophyMetric: TrophyComparison] = [:]
        for trophy in catalog.trophies {
            let metric = trophy.criteria.metric
            if metric.provenance == .trophyLedger {
                ledger.append(trophy)
                continue
            }
            index[metric, default: []].append(trophy)
            // Any gte trophy on the metric keeps the high-water at max;
            // only an all-lte metric latches toward min.
            if trophy.criteria.comparison == .greaterOrEqual {
                direction[metric] = .greaterOrEqual
            } else if direction[metric] == nil {
                direction[metric] = .lessOrEqual
            }
        }
        self.trophiesByMetric = index
        self.ledgerTrophies = ledger
        self.metricDirection = direction

        let storedIDs = Self.loadStringSet(forKey: Self.unlocksKey, defaults)
        // Heal ids from every raw timestamp KEY (even a corrupt-valued
        // entry is unlock evidence — keep the unlock, drop only the bad
        // date); decode dates per-entry so one corrupt value never costs
        // the whole timestamp ledger.
        let rawDates = defaults.dictionary(forKey: Self.unlockDatesKey) ?? [:]
        self.unlockDates = rawDates.compactMapValues { $0 as? Date }
        self.unlockedIDs = storedIDs.union(rawDates.keys)
    }

    // MARK: - Reads

    /// Whether `trophyID` is latched. Unknown ids report their persisted
    /// state (kept-not-dropped rule above).
    func isUnlocked(_ trophyID: String) -> Bool {
        unlockedIDs.contains(trophyID)
    }

    /// The first-unlock timestamp, or nil when locked (or when a healed
    /// partial write latched the id without a surviving stamp).
    func unlockDate(for trophyID: String) -> Date? {
        unlockDates[trophyID]
    }

    /// The trophies a stat bump on `metric` would evaluate — the metric
    /// index, exposed for tests and S0-T4's backfill. Ledger-provenance
    /// metrics return [] by design (cascade-only).
    func trophies(interestedIn metric: TrophyMetric) -> [TrophyDefinition] {
        trophiesByMetric[metric] ?? []
    }

    // MARK: - Recording (the hot path)

    /// Int convenience — most metrics are counters.
    @discardableResult
    func record(_ metric: TrophyMetric, value: Int) -> [TrophyDefinition] {
        record(metric, value: Double(value))
    }

    /// Push `metric`'s CURRENT value (cumulative/latched — never a delta)
    /// and latch every newly satisfied trophy. Returns everything that
    /// unlocked from this bump, cascaded capstone included, in latch
    /// order — [] on the overwhelmingly common no-unlock path.
    ///
    /// Cost shape (S0-T3 acceptance): one index lookup + O(interested
    /// trophies); zero persistence writes and zero `objectWillChange`
    /// emissions unless an unlock actually lands.
    ///
    /// `base_trophies_unlocked` (ledger provenance) is engine-derived and
    /// silently ignored here — an external caller must never be able to
    /// push the capstone open with a forged count.
    @discardableResult
    func record(_ metric: TrophyMetric, value: Double) -> [TrophyDefinition] {
        #if DEBUG
        debugLastRecordEvaluationCount = 0
        #endif
        guard metric.provenance != .trophyLedger,
              let interested = trophiesByMetric[metric] else { return [] }

        latchBestObserved(metric, value: value)

        var newlyUnlocked: [TrophyDefinition] = []
        for trophy in interested {
            #if DEBUG
            debugLastRecordEvaluationCount += 1
            #endif
            if unlockedIDs.contains(trophy.id) { continue }
            if trophy.criteria.comparison.isSatisfied(value: value,
                                                      threshold: trophy.criteria.threshold) {
                newlyUnlocked.append(trophy)
            }
        }
        guard !newlyUnlocked.isEmpty else { return [] }
        return commit(newlyUnlocked)
    }

    // MARK: - Progress (monotonic, for future UI)

    /// Fraction toward `trophyID`'s threshold, 0.0–1.0. Monotonic: an
    /// unlocked trophy is 1.0 forever; locked progress rides the
    /// high-water latch, so a regressed stat never walks it back.
    /// Returns nil for ids not in this build's catalog.
    ///
    /// Shapes per criteria kind:
    /// • gte metrics — clamp(best observed / threshold).
    /// • lte metrics (v1: the speed clear) — binary 0 → 1: "getting
    ///   slower more gradually" is not progress toward a fastest-clear.
    /// • ledger (capstone) — latched required-id count / threshold,
    ///   monotonic by construction of the ratchet.
    ///
    /// Secret-trophy masking is a UI policy (S2-T3 renders "???"), not an
    /// engine concern — the fraction is computed regardless.
    func progressFraction(for trophyID: String) -> Double? {
        guard let trophy = catalog.trophy(withID: trophyID) else { return nil }
        if unlockedIDs.contains(trophyID) { return 1 }
        let criteria = trophy.criteria
        if criteria.metric.provenance == .trophyLedger {
            let count = ledgerValue(for: criteria, unlocked: unlockedIDs)
            return min(max(count / criteria.threshold, 0), 1)
        }
        switch criteria.comparison {
        case .greaterOrEqual:
            guard let best = bestObserved[criteria.metric] else { return 0 }
            return min(max(best / criteria.threshold, 0), 1)
        case .lessOrEqual:
            return 0
        }
    }

    // MARK: - Latching (private)

    /// Latches unlocks into the ledger: stamps first-unlock dates, runs
    /// the ledger cascade (capstone), publishes the new unlock set ONCE,
    /// and persists synchronously — an unlock is durable the moment
    /// `record` returns (unlock-time durability; S1-T8 hardens the sync
    /// dirty flag on top of this).
    private func commit(_ base: [TrophyDefinition]) -> [TrophyDefinition] {
        var all = base
        var working = unlockedIDs
        for trophy in base { working.insert(trophy.id) }

        // Ledger cascade: trophies keyed to the ledger itself (v1: the
        // capstone) latch the instant their required set completes — no
        // external bump needed. Loop to fixpoint; with a single capstone
        // this runs at most twice and only ever on real unlocks.
        var changed = true
        while changed {
            changed = false
            for trophy in ledgerTrophies where !working.contains(trophy.id) {
                let value = ledgerValue(for: trophy.criteria, unlocked: working)
                if trophy.criteria.comparison.isSatisfied(value: value,
                                                          threshold: trophy.criteria.threshold) {
                    working.insert(trophy.id)
                    all.append(trophy)
                    changed = true
                }
            }
        }

        // First stamp wins, forever — never restamp (timestamp stability).
        let stamp = now()
        for trophy in all where unlockDates[trophy.id] == nil {
            unlockDates[trophy.id] = stamp
        }
        // Single @Published mutation per commit → exactly one
        // objectWillChange per unlocking bump, none otherwise.
        unlockedIDs = working
        persistLedger()
        return all
    }

    /// The capstone's derived metric value: how many of its required ids
    /// are latched. `requiredTrophyIDs` is validated non-nil for ledger
    /// criteria at catalog load; nil-tolerance here is pure defense.
    private func ledgerValue(for criteria: TrophyCriteria,
                             unlocked: Set<String>) -> Double {
        guard let required = criteria.requiredTrophyIDs else { return 0 }
        var count = 0
        for id in required where unlocked.contains(id) { count += 1 }
        return Double(count)
    }

    /// High-water latch for the progress API: max for gte metrics, min
    /// for lte. In-memory only (see `bestObserved`).
    private func latchBestObserved(_ metric: TrophyMetric, value: Double) {
        let direction = metricDirection[metric] ?? .greaterOrEqual
        if let current = bestObserved[metric] {
            switch direction {
            case .greaterOrEqual: if value > current { bestObserved[metric] = value }
            case .lessOrEqual:    if value < current { bestObserved[metric] = value }
            }
        } else {
            bestObserved[metric] = value
        }
    }

    // MARK: - Persistence (plist-native; the GameState helper pattern)

    /// Writes the ledger synchronously. Order matters for kill-mid-write
    /// healing: ids first, dates second — whichever key survives a crash,
    /// loading unions toward MORE unlocked (the ratchet direction).
    /// Both writes are plist-native; nothing is JSON-encoded.
    private func persistLedger() {
        defaults.set(Array(unlockedIDs), forKey: Self.unlocksKey)
        defaults.set(unlockDates, forKey: Self.unlockDatesKey)
    }

    /// GameState's `loadStringSet` pattern (find by symbol —
    /// GameState.swift persistence helpers).
    private static func loadStringSet(forKey key: String,
                                      _ defaults: UserDefaults) -> Set<String> {
        guard let arr = defaults.array(forKey: key) as? [String] else { return [] }
        return Set(arr)
    }
}
