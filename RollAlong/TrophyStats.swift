//
//  TrophyStats.swift
//  RollAlong
//
//  S0-T2 — Stat instrumentation layer (docs/trophies/sprint-plan.md §2
//  S0-T2; trophy-catalog.md §6 items 4–6 and 15 — the GameState-funnel
//  subset; view-layer hooks are S1-T7, social latches are S1-T6).
//
//  The store holds exactly the NEW counters the v1 trophy catalog needs
//  and nothing else. Every counter here maps 1:1 to a trophy-catalog.md
//  §6 item (test-enumerated in TrophyStatsTests):
//
//  • §6 item 4 → `coinsEarnedFromPlay` (`ra_trophyCoinsEarnedFromPlay`)
//    — source-tagged lifetime coins earned FROM PLAY, bumped by
//    `GameState.addCoins`. The exclusions are load-bearing: IAP grants,
//    Sell Back refunds, and `grantBundleFree` bundle-gift compensation
//    (PR #114 mints refund-shaped credits through `addCoins`) never
//    count — refunds are recycled capital, not play income
//    (research/internal-economy.md §5b). Feeds `econ_working_capital`.
//  • §6 item 5 → `dailyRewardClaims` (`ra_trophyDailyRewardClaims`)
//    — lifetime daily-reward claim count, bumped in
//    `GameState.claimDailyReward`. Counts claims, not streaks. Feeds
//    `econ_punch_card`.
//  • §6 item 6 → `noFallClearStreak` + `bestNoFallClearStreak`
//    (`ra_trophyNoFallClearStreak` / `ra_trophyNoFallClearStreakBest`)
//    — consecutive no-fall climb-clear streak. The working value
//    increments on climb clears (`recordResult`) and resets on climb
//    falls (`consumeLife`, mode-gated on
//    `progression.recordsClimbResult`); the BEST value is the monotonic
//    ratchet trophies read (`no_fall_clear_streak_best`). Tutorial falls
//    (L1–10) never reach `consumeLife` — that reset arrives with
//    S1-T7's direct fall funnel. Feeds `skill_clean_sheet_10/25`.
//  • §6 item 15 → `longestConsecutiveDailyClearRun(in:)` — a PURE
//    derivation over the EXISTING `dailyChallengeCompletions` date set.
//    Deliberately no storage (the date set is already on disk). Feeds
//    `daily_week_streak` via the `daily_clear_streak_best` metric.
//  • §6 item 14 → `livesSent` (`ra_trophyLivesSent`) + `clanRequestsFulfilled`
//    (`ra_trophyClanRequestsFulfilled`) — the two lifetime go-forward social
//    counters (S1-T6). `livesSent` counts every gifted life (friend gifts AND
//    clan fulfillments) and feeds `social_send_life`/`social_lives_sent_25`;
//    `clanRequestsFulfilled` counts only lives sent to a clanmate who was
//    asking, and feeds `clan_fulfill`. Both are bumped from GameState social
//    funnels driven by the SwiftUI Friends/Clans views on a SUCCESSFUL
//    `SocialClient` call. The three other social latches (`signed_in`,
//    `friends_accepted_peak`, `clan_joined`) need NO counter: sign-in and
//    clan-join are one-shot value-1 latches, and the friend high-water is the
//    live accepted-friend count the engine already latches — so no persisted
//    key backs them. Social metrics are go-forward only (deliberately absent
//    from `TrophyBackfill.snapshot` — no local pre-trophy state to
//    grandfather; TrophyEngine.swift documents the omission).
//
//  DELIBERATELY ABSENT (trophy-catalog.md §6 "deliberately absent" list;
//  sprint-plan.md S0-T2 prohibitions — all test-enforced):
//  • NO coins-spent counter — Sell Back refunds min(cost/2, paid); a
//    spend counter is churnable at a 50% loss per cycle.
//  • NO falls/failure counter — nothing rewards losing (principle 6).
//    The streak RESET is not a count; `whimsy_gravity_check` is a
//    one-shot S1-T7 latch, not a counter.
//  • NO speculative counters (results-shared, session count, lives
//    received, climb attempts): no v1 trophy consumes them.
//
//  Ratchet rules (sprint-plan.md §4 addenda): counters are monotonic —
//  `resetProgress()` and `liquidateCoinCosmetics()` never touch them,
//  and nothing here exposes a decreasing path (the streak's documented
//  working-value reset is the single, catalog-specified exception; its
//  ratchet is `bestNoFallClearStreak`). Unlock latching itself is the
//  engine's job (S0-T3) — this store is counters only.
//

import Foundation

/// Latched trophy stat counters, persisted write-through as `ra_trophy*`
/// UserDefaults keys (the GameState `didSet` pattern) and bumped ONLY from
/// GameState funnels. Plain reference type — deliberately NOT observable:
/// trophy stat writes must never re-render gameplay views observing
/// `GameState` (sprint-plan.md S0-T3 rationale; UI reads arrive with the
/// engine's own ObservableObject in S0-T3).
final class TrophyStats {

    // MARK: - Coin source tagging (§6 item 4)

    /// Where an `addCoins` award came from. The default everywhere is
    /// `.play`; only the excluded sources are explicitly tagged at their
    /// call sites (GameState.liquidateCoinCosmetics → `.refund`,
    /// GameState.grantBundleFree → `.giftCompensation`,
    /// StoreKitManager.deliverReward → `.iap`,
    /// GameState.claimDailyReward → `.daily`).
    enum CoinSource {
        /// Gameplay income: climb/track clears, pickups, minigame payouts,
        /// PB bonuses, Coin Pit catches, CotD rewards. Counts.
        case play
        /// The daily login-reward ladder (`claimDailyReward`). Counts —
        /// only the three refund/purchase-shaped sources below are
        /// excluded (trophy-catalog.md §6 item 4).
        case daily
        /// IAP coin-pack / Starter Pack grants (StoreKitManager). Never
        /// counts: purchased, not earned.
        case iap
        /// Sell Back liquidation refunds. Never counts: recycled capital.
        case refund
        /// `grantBundleFree` compensation for already-coin-bought items
        /// (PR #114's refund-shaped credit). Never counts.
        case giftCompensation

        /// Whether this source counts toward lifetime play-earned coins.
        /// Exactly the three excluded sources return false — the
        /// exclusions are load-bearing (§6 item 4).
        var countsAsPlayEarned: Bool {
            switch self {
            case .play, .daily:                     return true
            case .iap, .refund, .giftCompensation:  return false
            }
        }
    }

    // MARK: - Persisted keys

    /// Every UserDefaults key this store may ever write — the complete
    /// `ra_trophy*` counter inventory for S0-T2. TrophyStatsTests asserts
    /// this list maps 1:1 onto trophy-catalog.md §6 items {4, 5, 6} (item
    /// 15 is a pure derivation with NO key) and that no other trophy-stat
    /// key is ever written: the no-spend-counter / no-falls-counter /
    /// no-speculative-counters prohibitions, enforced as set equality.
    /// (S0-T3's engine adds its own separate ledger keys —
    /// `ra_trophyUnlocks`/`ra_trophyUnlockDates` — which are not counters
    /// and not written by this store.)
    static let allPersistedKeys: Set<String> = [
        coinsEarnedFromPlayKey,
        dailyRewardClaimsKey,
        noFallClearStreakKey,
        noFallClearStreakBestKey,
        livesSentKey,
        clanRequestsFulfilledKey,
    ]

    static let coinsEarnedFromPlayKey    = "ra_trophyCoinsEarnedFromPlay"
    static let dailyRewardClaimsKey      = "ra_trophyDailyRewardClaims"
    static let noFallClearStreakKey      = "ra_trophyNoFallClearStreak"
    static let noFallClearStreakBestKey  = "ra_trophyNoFallClearStreakBest"
    static let livesSentKey              = "ra_trophyLivesSent"
    static let clanRequestsFulfilledKey  = "ra_trophyClanRequestsFulfilled"

    /// The persistence store. Production uses `.standard` (injected by
    /// GameState with its own defaults); tests inject a throwaway suite.
    private let defaults: UserDefaults

    // MARK: - Counters (read-only outside; bump via the record funnels)

    /// §6 item 4 — lifetime coins earned from play (source-tagged;
    /// monotonic). Feeds `econ_working_capital`.
    private(set) var coinsEarnedFromPlay: Int {
        didSet { defaults.set(coinsEarnedFromPlay, forKey: Self.coinsEarnedFromPlayKey) }
    }

    /// §6 item 5 — lifetime daily-reward claims (monotonic). Feeds
    /// `econ_punch_card`.
    private(set) var dailyRewardClaims: Int {
        didSet { defaults.set(dailyRewardClaims, forKey: Self.dailyRewardClaimsKey) }
    }

    /// §6 item 6 — the WORKING consecutive no-fall climb-clear streak.
    /// Increments on climb clears; resets to 0 on climb falls (the one
    /// catalog-specified regression — persisted so the streak survives
    /// sessions, per the `skill_clean_sheet_10` row note). Trophies never
    /// read this directly; they read `bestNoFallClearStreak`.
    private(set) var noFallClearStreak: Int {
        didSet { defaults.set(noFallClearStreak, forKey: Self.noFallClearStreakKey) }
    }

    /// §6 item 6 — the monotonic high-water of `noFallClearStreak`: the
    /// ratchet the `no_fall_clear_streak_best` metric reads. Never
    /// decreases (never derive unlocks live from the regressable working
    /// value — sprint-plan.md §4 addenda).
    private(set) var bestNoFallClearStreak: Int {
        didSet { defaults.set(bestNoFallClearStreak, forKey: Self.noFallClearStreakBestKey) }
    }

    /// §6 item 14 — lifetime lives sent (monotonic): every gifted life,
    /// whether a friend gift or a clan fulfillment. Feeds `social_send_life`
    /// (≥1) and `social_lives_sent_25` (≥25). Go-forward only — never
    /// grandfathered (no local pre-trophy record of lives given).
    private(set) var livesSent: Int {
        didSet { defaults.set(livesSent, forKey: Self.livesSentKey) }
    }

    /// §6 item 14 — lifetime clan life-requests fulfilled (monotonic): a life
    /// sent to a clanmate who was asking for one. Feeds `clan_fulfill` (≥1).
    /// A subset of `livesSent` (every fulfillment is also a life sent), but a
    /// distinct counter — friend gifts and clan gifts to non-asking members
    /// never bump it. Go-forward only.
    private(set) var clanRequestsFulfilled: Int {
        didSet { defaults.set(clanRequestsFulfilled, forKey: Self.clanRequestsFulfilledKey) }
    }

    // MARK: - Init

    /// Defensive loads, GameState-style: missing keys read as 0; corrupt
    /// negatives clamp to 0; a best below the working streak self-heals
    /// upward (the ratchet can only have been at least the working value).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        coinsEarnedFromPlay = max(0, defaults.integer(forKey: Self.coinsEarnedFromPlayKey))
        dailyRewardClaims   = max(0, defaults.integer(forKey: Self.dailyRewardClaimsKey))
        let streak = max(0, defaults.integer(forKey: Self.noFallClearStreakKey))
        noFallClearStreak = streak
        bestNoFallClearStreak = max(
            streak, max(0, defaults.integer(forKey: Self.noFallClearStreakBestKey)))
        livesSent             = max(0, defaults.integer(forKey: Self.livesSentKey))
        clanRequestsFulfilled = max(0, defaults.integer(forKey: Self.clanRequestsFulfilledKey))
    }

    // MARK: - Record funnels (called from GameState only)

    /// §6 item 4 — record a coin award. Only play-earned sources count;
    /// the amount is the actually-granted (post-clamp) award from
    /// `GameState.addCoins`. Non-positive amounts are ignored — the
    /// counter is monotonic.
    func recordCoins(_ amount: Int, source: CoinSource) {
        guard amount > 0, source.countsAsPlayEarned else { return }
        coinsEarnedFromPlay += amount
    }

    /// §6 item 5 — record one successful daily-reward claim.
    func recordDailyRewardClaim() {
        dailyRewardClaims += 1
    }

    /// §6 item 6 — record a fall-free climb clear: the working streak
    /// grows and the best-ratchet latches. Callers gate on climb mode
    /// (`progression.recordsClimbResult`) — this store stays mode-blind.
    func recordNoFallClimbClear() {
        noFallClearStreak += 1
        if noFallClearStreak > bestNoFallClearStreak {
            bestNoFallClearStreak = noFallClearStreak
        }
    }

    /// §6 item 6 — a climb fall breaks the working streak. The best
    /// ratchet is untouched, forever. Callers gate on climb mode: Roll
    /// Out / Roll Up / track falls must never reach this (S1-T1
    /// acceptance); tutorial falls join via S1-T7's fall funnel.
    func resetNoFallClearStreak() {
        guard noFallClearStreak != 0 else { return }
        noFallClearStreak = 0
    }

    /// §6 item 14 — record one gifted life (friend gift OR clan fulfillment).
    /// Monotonic; called from GameState's `recordLifeSent()` funnel on a
    /// successful `SocialClient.sendLife`. Never regresses.
    func recordLifeSent() {
        livesSent += 1
    }

    /// §6 item 14 — record one fulfilled clan life-request (a life sent to a
    /// clanmate who was asking). Monotonic; called from GameState's
    /// `recordClanRequestFulfilled()` funnel IN ADDITION to `recordLifeSent()`
    /// (a fulfillment is also a life sent). Never regresses.
    func recordClanRequestFulfilled() {
        clanRequestsFulfilled += 1
    }

    // MARK: - Derivations (no storage — §6 item 15)

    /// §6 item 15 — the longest run of consecutive calendar dates in a
    /// Challenge-of-the-Day completions date set ("YYYY-MM-DD" keys, the
    /// `DailyChallenge.key()` format). Pure derivation over the EXISTING
    /// `GameState.dailyChallengeCompletions` set — deliberately no new
    /// storage. The completions set is append-only, so this derivation is
    /// itself monotonic over a live save. Feeds `daily_week_streak`
    /// (`daily_clear_streak_best` ≥ 7).
    ///
    /// Malformed keys are skipped (defensive — the game only ever inserts
    /// `DailyChallenge.key()` values).
    static func longestConsecutiveDailyClearRun(in completions: Set<String>) -> Int {
        var ordinals = Set<Int>()
        ordinals.reserveCapacity(completions.count)
        for key in completions {
            if let ordinal = dayOrdinal(forDateKey: key) { ordinals.insert(ordinal) }
        }
        guard !ordinals.isEmpty else { return 0 }
        let sorted = ordinals.sorted()
        var best = 1
        var run = 1
        for i in 1..<sorted.count {
            if sorted[i] == sorted[i - 1] + 1 {
                run += 1
                if run > best { best = run }
            } else {
                run = 1
            }
        }
        return best
    }

    /// Fixed Gregorian-UTC calendar for date-key arithmetic: date-only
    /// keys have no timezone, and UTC has no DST, so every day is exactly
    /// 86 400 s and "consecutive calendar dates" is exact integer math.
    private static let utcGregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// "YYYY-MM-DD" → a day ordinal where consecutive calendar dates
    /// differ by exactly 1 (across month and year boundaries). Returns
    /// nil for anything that isn't a well-formed date key.
    private static func dayOrdinal(forDateKey key: String) -> Int? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              year > 0, (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = utcGregorian.date(from: components) else { return nil }
        return Int(floor(date.timeIntervalSince1970 / 86_400))
    }
}
