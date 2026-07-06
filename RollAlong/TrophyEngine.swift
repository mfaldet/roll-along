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

    /// Set to `true` the first time `backfill(from:)` completes, so the
    /// retro-evaluation never runs twice (idempotent across relaunches —
    /// S0-T4 acceptance). It also gates the flag S2-T6 consumes for a
    /// single coalesced "Trophy Room opens" reveal instead of a toast
    /// storm (design.md §6 anti-spam batching): the reveal is owed exactly
    /// when this key flips from unset to set with a non-empty grant.
    static let backfillDoneKey = "ra_trophyBackfillDone"

    /// The count of trophies the one-time backfill granted, persisted so
    /// S2-T6 can render "you've already earned N" after the flag flips.
    /// Absent/`0` when no backfill ran or it granted nothing.
    static let backfillGrantCountKey = "ra_trophyBackfillGrantCount"

    /// The single, fixed timestamp every grandfathered unlock carries — a
    /// clearly-legacy marker, distinct from any real play instant, and
    /// always in the past so it can never violate the never-in-the-future
    /// invariant. It is 2000-01-01 UTC (`Date(timeIntervalSinceReferenceDate: 0)`):
    /// well before Roll Along shipped, so a stamp equal to it unambiguously
    /// reads "earned before trophies existed."
    ///
    /// Kept deliberately separable (D5 is still open — design.md §11 #12,
    /// "Mac may veto"): if Mac vetoes grant-from-existing-stats in favour
    /// of earn-fresh-from-zero, the ONLY change is not calling `backfill`
    /// at wiring time (S1) — no latch, cascade, or persistence code depends
    /// on this constant, and live unlocks never use it.
    static let legacyUnlockDate = Date(timeIntervalSinceReferenceDate: 0)

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

    /// Whether the one-time first-launch backfill has already run. Loaded
    /// from `backfillDoneKey`; `backfill(from:)` short-circuits when set,
    /// so the retro-evaluation is idempotent across relaunches.
    @Published private(set) var didBackfill: Bool

    /// How many trophies the backfill granted (0 if it ran on a fresh
    /// install or has not run). S2-T6 reads this for its one coalesced
    /// reveal; nothing on the hot path touches it.
    @Published private(set) var backfillGrantCount: Int

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

        self.didBackfill = defaults.bool(forKey: Self.backfillDoneKey)
        self.backfillGrantCount = max(0, defaults.integer(forKey: Self.backfillGrantCountKey))
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

    // MARK: - First-launch backfill / migration (S0-T4)

    /// A snapshot of every trophy metric's CURRENT value, derived once at
    /// first launch with trophies from a player's existing save. Only
    /// metrics with a real historical source appear; metrics that begin
    /// life at zero the day trophies ship (the NEW counters — daily-reward
    /// claims, play-earned coins, no-fall streak — and the run/event
    /// metrics — first-try aces, spotless runs, night-Zen sessions, social
    /// latches, …) are deliberately ABSENT, so backfill can never
    /// grandfather a deed the save carries no proof of.
    ///
    /// See `TrophyBackfill.snapshot(from:)` for the derivation from the
    /// authoritative `GameState` decode.
    typealias MetricSnapshot = [TrophyMetric: Double]

    /// One-time retroactive grant (design.md §11 #12 default: "grant from
    /// existing stats"; sprint-plan.md §2 S0-T4). Evaluates the full
    /// catalog against `snapshot` and latches every satisfied trophy with
    /// the `legacyUnlockDate` marker, then records that the backfill ran.
    ///
    /// Idempotent across relaunches: the first completed run sets
    /// `backfillDoneKey`, and every later call short-circuits to `[]` — a
    /// veteran's second launch re-grants nothing, and a fresh install whose
    /// snapshot satisfied nothing still marks itself done (so the empty
    /// grant is never re-attempted).
    ///
    /// The returned set is the newly-backfilled trophies (capstone included
    /// if the grandfathered base completes it) — S2-T6's coalesced reveal
    /// consumes `backfillGrantCount`; the return value is for callers/tests
    /// that want the exact list. Live `record` unlocks are unaffected: they
    /// keep stamping `now()`.
    @discardableResult
    func backfill(from snapshot: MetricSnapshot) -> [TrophyDefinition] {
        guard !didBackfill else { return [] }

        // Seed the progress high-water from the snapshot so post-backfill
        // `progressFraction` is correct for a still-locked trophy on a
        // metric the veteran already has history on (e.g. 30/40 balls).
        for (metric, value) in snapshot { latchBestObserved(metric, value: value) }

        // Collect every locked trophy the snapshot satisfies. Iterate the
        // catalog (this is the one-time cold path — O(catalog) is fine and
        // deterministic in catalog order), consulting only base-metric
        // criteria; the capstone (ledger provenance) is left to `commit`'s
        // cascade so a grandfathered base can complete it.
        var granted: [TrophyDefinition] = []
        for (metric, trophies) in trophiesByMetric {
            guard let value = snapshot[metric] else { continue }
            for trophy in trophies where !unlockedIDs.contains(trophy.id) {
                if trophy.criteria.comparison.isSatisfied(
                    value: value, threshold: trophy.criteria.threshold) {
                    granted.append(trophy)
                }
            }
        }

        var all: [TrophyDefinition] = []
        if !granted.isEmpty {
            all = commit(granted, stamp: Self.legacyUnlockDate)
        }

        // Mark done exactly once, even on a nothing-to-grant fresh install,
        // so the retro-evaluation never re-runs. Written last: a crash
        // before this leaves the flag unset and the (already-persisted,
        // idempotent) grants simply re-evaluate to the same set next launch.
        didBackfill = true
        backfillGrantCount = all.count
        defaults.set(true, forKey: Self.backfillDoneKey)
        defaults.set(all.count, forKey: Self.backfillGrantCountKey)
        return all
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
    ///
    /// `stamp` is the first-unlock date to record. The live hot path passes
    /// `now()` (its default); S0-T4's backfill passes the `legacyUnlockDate`
    /// sentinel so grandfathered unlocks carry a clearly-legacy marker
    /// instead of the update-install instant. Either way the stamp is
    /// clamped to `<= now()` — no unlock timestamp may be in the future
    /// (S0-T4 acceptance).
    @discardableResult
    private func commit(_ base: [TrophyDefinition],
                        stamp rawStamp: Date? = nil) -> [TrophyDefinition] {
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
        // Never-in-the-future is invariant: clamp the requested stamp to
        // now(). The legacy sentinel is already in the past, so backfill
        // only ever stamps backwards; the clamp is defense for a pinned or
        // skewed clock.
        let stamp = min(rawStamp ?? now(), now())
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

// MARK: - Backfill snapshot derivation (S0-T4)

/// Derives the one-time backfill snapshot — every trophy metric's CURRENT
/// value — from a player's existing save. The derivation reads GameState's
/// AUTHORITATIVE decode (a `GameState(defaults:)` built from the real `ra_*`
/// dump), never re-parsing raw plist/JSON blobs, so it can never drift from
/// how the game itself interprets a save.
///
/// It maps ONLY metrics with a genuine historical source (design.md §11 #12
/// "grant from existing stats"; trophy-catalog.md §6 item 2 "retro-evaluation
/// of all *derivable* triggers"). A metric that begins at zero the day
/// trophies ship is deliberately OMITTED — a missing key means "no proof in
/// this save," so `backfill` never grandfathers it:
///
/// • NEW S0-T2 counters that start empty: `daily_reward_claims`,
///   `coins_earned_from_play`, `no_fall_clear_streak_best`.
/// • Run/event metrics with no historical record: `first_try_aces`,
///   `spotless_runs`, `night_zen_sessions`, `level_one_falls`,
///   `starter_loadout_flexes`, `coinpit_round_stake_best`, `daily_played`.
/// • Social latches (all `socialAction` metrics) — no local pre-trophy state.
/// • `pinball_roll_lane_sweeps` — the ROLL lanes don't exist yet (§7).
/// • The capstone metric `base_trophies_unlocked` — engine-derived; the
///   cascade in `commit` completes it if the grandfathered base qualifies.
///
/// Cosmetics-OWNERSHIP counts (`balls_owned`, `cosmetics_owned`,
/// `evergreen_cosmetics_owned`, `full_nonstarter_loadouts`) ARE included
/// (added by S1-T5): they derive from the SAME `GameState` computed
/// properties the live `grant`/equip funnels record, so a grandfather and a
/// live grant can't drift. The IAP-secret exclusion constant and the
/// 207-item evergreen arithmetic live in `TrophyCosmeticExclusions` + those
/// GameState helpers. `bundles_completed` and `packs_owned` are likewise
/// exclusion-free (bundles are kept IAP-secret-free by guardrail;
/// `ownedPacks` has no IAP-secret members).
enum TrophyBackfill {

    /// Build the metric snapshot from an already-loaded `GameState`. Reads
    /// only public read accessors — no mutation, no persistence.
    static func snapshot(from state: GameState) -> TrophyEngine.MetricSnapshot {
        var snap: TrophyEngine.MetricSnapshot = [:]

        // — Climb (existing stats) —
        snap[.climbHighestUnlocked] = Double(state.highestUnlocked)
        snap[.climbTotalStars]      = Double(state.totalStars)
        snap[.climbPickupCoins]     = Double(state.totalCoins)
        snap[.climbPerfectWorlds]   = Double(perfectWorldCount(bestStars: state.bestStars))

        // — Challenge Tracks (existing) —
        let bestTrack = state.trackProgress.values.max() ?? 0
        snap[.trackBestProgress]      = Double(bestTrack)
        snap[.tracksCompleted]        = Double(state.completedTracks.count)
        if state.completedTracks.contains("golden-gauntlet") {
            snap[.goldenGauntletCompleted] = 1
        }

        // — Daily Challenge & Streaks —
        snap[.dailyClears]           = Double(state.dailyChallengeCompletions.count)
        // Backfill proxy for the reward-streak high-water: the live streak
        // the save carries (catalog §3.3 `daily_login_7/30` → EXISTING
        // `dailyStreak`). S1-T2's own latch takes over for live play.
        snap[.dailyRewardStreakBest] = Double(state.dailyStreak)
        snap[.dailyClearStreakBest]  = Double(
            TrophyStats.longestConsecutiveDailyClearRun(
                in: state.dailyChallengeCompletions))

        // — Minigames — arcade-wide —
        let played = state.playedModeIDs
        let minigamesPlayed = TrophyMetric.minigameModeIDs.filter { played.contains($0) }.count
        snap[.minigamesPlayed] = Double(minigamesPlayed)

        let wins = state.minigameWins
        var competitiveWins = 0
        var competitiveModesWon = 0
        for id in TrophyMetric.competitiveModeIDs {
            let w = wins[id, default: 0]
            competitiveWins += w
            if w >= 1 { competitiveModesWon += 1 }
        }
        snap[.competitiveWins]     = Double(competitiveWins)
        snap[.competitiveModesWon] = Double(competitiveModesWon)

        let hardWins = state.minigameDifficultyWins
        var competitiveModesWonHard = 0
        for id in TrophyMetric.competitiveModeIDs where hardWins["\(id)|hard", default: 0] >= 1 {
            competitiveModesWonHard += 1
        }
        snap[.competitiveModesWonHard] = Double(competitiveModesWonHard)

        // — Minigames — per game (existing wins/bests) —
        snap[.snakeWins]     = Double(wins["snake", default: 0])
        snap[.sumoWins]      = Double(wins["sumo", default: 0])
        snap[.paintballWins] = Double(wins["paintball", default: 0])
        snap[.goldrushWins]  = Double(wins["goldrush", default: 0])
        snap[.marblecupWins] = Double(wins["marblecup", default: 0])
        snap[.kothWins]      = Double(wins["koth", default: 0])

        let bests = state.minigameBests
        snap[.paintballBestCoverage] = Double(bests["paintball", default: 0])
        snap[.kothBestHoldSeconds]   = Double(bests["koth", default: 0])
        snap[.pinballBestScore]      = Double(state.pinballBest)
        snap[.rolloutBestMaze]       = Double(bests["rollout", default: 0])
        snap[.rollupBestHeight]      = Double(bests["rollup", default: 0])

        // Disco crossings: best across all three difficulty keys (catalog
        // §3.5 `disco_cross_25`); the hard-only variant reads discohard.
        let discoBest = max(bests["discoeasy", default: 0],
                            bests["disco", default: 0],
                            bests["discohard", default: 0])
        snap[.discoBestCrossings]     = Double(discoBest)
        snap[.discoHardBestCrossings] = Double(bests["discohard", default: 0])

        snap[.zenSeconds] = Double(state.zenSeconds)
        if played.contains("coinpit") { snap[.coinpitPlayed] = 1 }
        snap[.coinpitBestCatch]  = Double(state.goldrushBest)
        snap[.coinpitCoinsTotal] = Double(state.goldrushCoinsTotal)

        // — Cosmetics & Collection —
        // Ownership counts derive from the SAME GameState computed properties
        // the live `grant` funnel records (S1-T5), so a first-launch
        // grandfather and a live grant can never disagree. The IAP-secret
        // exclusion and the 207-item evergreen arithmetic live in
        // `TrophyCosmeticExclusions` + those GameState helpers — never
        // re-implemented here.
        snap[.bundlesCompleted]         = Double(state.completedBundleIDs.count)
        snap[.packsOwned]               = Double(state.ownedPacks.count)
        snap[.ballsOwned]               = Double(state.trophyBallsOwnedCount)
        snap[.cosmeticsOwned]           = Double(state.trophyCosmeticsOwnedCount)
        snap[.evergreenCosmeticsOwned]  = Double(state.trophyEvergreenCosmeticsOwnedCount)
        // cosmetic_full_kit — whether the currently-equipped loadout is
        // fully non-starter in the veteran save being grandfathered.
        snap[.fullNonstarterLoadouts]   = state.trophyLoadoutIsFullyNonStarter ? 1 : 0

        // — Economy (existing high-water; play-earned/claim COUNTERS omitted) —
        snap[.coinBalancePeak] = Double(state.coinBalance)

        // — Skill & Style (existing star/time scans) —
        snap[.veryhardAceLevels] = Double(veryHardAceCount(bestStars: state.bestStars))
        // Fastest clear is the sole `lte` metric — only present when the
        // save actually has a cleared level (an absent key means "no clear
        // time yet," never a spurious 0-second grant).
        if let fastest = state.bestTime.values.min() {
            snap[.fastestClearSeconds] = fastest
        }

        return snap
    }

    /// Count of worlds whose every level (all 100 in `World.levelRange`)
    /// holds 3 stars — keyed to the star dict + number ranges, never to
    /// layouts (catalog §3.1 `climb_perfect_world`).
    static func perfectWorldCount(bestStars: [Int: Int]) -> Int {
        var count = 0
        for world in World.all {
            var allThree = true
            for level in world.levelRange where bestStars[level, default: 0] < 3 {
                allThree = false
                break
            }
            if allThree { count += 1 }
        }
        return count
    }

    /// Count of veryHard levels (number ending in 0 or 5, above level 10)
    /// aced at 3 stars — the digit rule is the stable difficulty vocabulary
    /// (catalog §3.9 `skill_ace_veryhard`).
    static func veryHardAceCount(bestStars: [Int: Int]) -> Int {
        var count = 0
        for (level, stars) in bestStars where level > 10 && level % 5 == 0 && stars >= 3 {
            count += 1
        }
        return count
    }
}
