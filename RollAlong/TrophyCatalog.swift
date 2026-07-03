//
//  TrophyCatalog.swift
//  RollAlong
//
//  S0-T1 — Trophy catalog data model, bundled-JSON loader, and guardrail
//  validation (docs/trophies/sprint-plan.md §2 S0-T1; design.md §9;
//  trophy-catalog.md §3).
//
//  The catalog is DATA: the 89 v1 trophies ship as `TrophyCatalog.json`
//  (the LevelOverrides pattern) and this file defines the vocabulary the
//  trophy engine evaluates against. House rules enforced here:
//
//  • IDs are forever — snake_case, Game Center-legal (lowercase
//    alphanumeric + underscore, ≤100 chars), unique, immutable after
//    publish (trophy-catalog.md principle 13).
//  • Criteria = one metric key + threshold (+ comparison where needed).
//    Every metric key must resolve to a `TrophyMetric` case; unknown keys
//    fail decode. No criterion may reference IAP products, purchases, or
//    specific level layouts (design.md §9 guardrail; sprint-plan.md §4).
//  • Ruled ladder (2026-07-02): Bronze → Silver → Gold → Diamond →
//    Platinum. "Platinum" is the capstone rung's display name; the
//    capstone id stays `capstone_all`. The Diamond *grade* is distinct
//    from the Diamond *ball* cosmetic everywhere (design.md §2 R2 riders).
//  • Rewards are prestige + earned-only regalia. Trophies NEVER mint
//    coins — no trophy code path may ever call `addCoins` to grant
//    (D1 ruling, 2026-07-02; docs/economy/07-decisions.md addendum).
//  • Collection metrics exclude the 4 IAP secrets — BallSkin.diamond,
//    BallSkin.moneyBall, TrailColor.moneyRoll, Floor.moneyFull — from all
//    ownership math (trophy-catalog.md §3.6; the unit-tested exclusion
//    constant is wired at S1-T5).
//  • Trophy state is a ratchet: the engine latches unlocks once, forever;
//    nothing here is ever re-derived from regressable live stats.
//

import Foundation

// MARK: - Tier ladder

/// The ruled five-rung ladder (design.md §11 #1/#2, RULED 2026-07-02):
/// Bronze → Silver → Gold → Diamond → Platinum. `platinum` is the single
/// capstone rung — its display name is literally "Platinum".
///
/// Binding Diamond riders (design.md §2 R2): the Diamond trophy *grade*
/// never borrows the Diamond *ball* cosmetic's glyph/color/copy. Enforced
/// in S2-T1/S3-T4; recorded here because this enum is the grade's source.
enum TrophyTier: String, Codable, CaseIterable, Comparable {
    case bronze
    case silver
    case gold
    case diamond
    case platinum

    /// Player-facing grade name.
    var displayName: String {
        switch self {
        case .bronze:   return "Bronze"
        case .silver:   return "Silver"
        case .gold:     return "Gold"
        case .diamond:  return "Diamond"
        case .platinum: return "Platinum"
        }
    }

    /// The capstone rung ("Platinum"), of which the catalog has exactly one.
    var isCapstone: Bool { self == .platinum }

    /// Ladder position, low → high.
    var rank: Int {
        switch self {
        case .bronze:   return 0
        case .silver:   return 1
        case .gold:     return 2
        case .diamond:  return 3
        case .platinum: return 4
        }
    }

    static func < (lhs: TrophyTier, rhs: TrophyTier) -> Bool { lhs.rank < rhs.rank }
}

// MARK: - Categories

/// Catalog categories, mirroring trophy-catalog.md §3.1–§3.11.
enum TrophyCategory: String, Codable, CaseIterable {
    case climb              = "climb"
    case challengeTracks    = "challenge_tracks"
    case daily              = "daily"
    case minigamesArcade    = "minigames_arcade"
    case minigamesPerGame   = "minigames_per_game"
    case cosmetics          = "cosmetics_collection"
    case economy            = "economy_shop"
    case social             = "social"
    case skillStyle         = "skill_style"
    case secretWhimsy       = "secret_whimsy"
    case capstone           = "capstone"

    /// Player-facing section header (Trophy Room grouping, S2-T3).
    var displayName: String {
        switch self {
        case .climb:            return "Climb"
        case .challengeTracks:  return "Challenge Tracks"
        case .daily:            return "Daily Challenge & Streaks"
        case .minigamesArcade:  return "Minigames — Arcade-Wide"
        case .minigamesPerGame: return "Minigames — Per Game"
        case .cosmetics:        return "Cosmetics & Collection"
        case .economy:          return "Economy & Shop"
        case .social:           return "Social — Friends & Clans"
        case .skillStyle:       return "Skill & Style"
        case .secretWhimsy:     return "Secret & Whimsy"
        case .capstone:         return "Capstone"
        }
    }

    /// Whether trophies in this category can gate the capstone.
    /// Social, Secret & Whimsy, and the capstone itself are quarantined off
    /// the capstone path (trophy-catalog.md §3.11; Sony house rule) — the
    /// Diamond-tier quarantine is applied separately by tier.
    var countsTowardCapstone: Bool {
        switch self {
        case .social, .secretWhimsy, .capstone: return false
        case .climb, .challengeTracks, .daily, .minigamesArcade,
             .minigamesPerGame, .cosmetics, .economy, .skillStyle:
            return true
        }
    }
}

// MARK: - Metric vocabulary

/// Every measurable a trophy criterion may reference — the complete
/// vocabulary for the v1 catalog: existing GameState stats
/// (research/internal-features.md §2) plus the NEW instrumentation items
/// (trophy-catalog.md §6). This enum is the vocabulary only; the stat
/// bumps land in S0-T2 (TrophyStats) and S1 (trigger wiring).
///
/// Rules the vocabulary itself encodes (trophy-catalog.md "deliberately
/// absent" list + sprint-plan.md §4 addenda):
/// • No IAP/purchase-count, coins-spent, ads-watched, out-of-lives, or
///   failure-count metric exists — the banned criteria are inexpressible.
/// • No metric names a specific level layout; climb metrics use lifetime
///   stats and level *numbers/ranges* only (levels are swappable content).
/// • Analytics events are never trigger sources; every metric maps to a
///   GameState funnel, a latched TrophyStats counter, or the trophy ledger.
/// • The engine must tolerate metrics that never fire —
///   `pinballRollLaneSweeps` stays silent until the pinball ROLL lanes
///   ship (external blocker, sprint-plan.md §7).
enum TrophyMetric: String, Codable, CaseIterable {

    // Climb (existing GameState stats)
    /// `highestUnlocked` — clearing level N sets this to N+1.
    case climbHighestUnlocked   = "climb_highest_unlocked"
    /// `totalStars`, latched (resetProgress can shrink the live sum).
    case climbTotalStars        = "climb_total_stars"
    /// Count of worlds with 3 stars on every level of the world's 100-level
    /// range (`bestStars` scan over `World.levelRange` — never layouts).
    case climbPerfectWorlds     = "climb_perfect_worlds"
    /// `totalCoins` — lifetime banked level-pickup coins, latched.
    /// NOT the spendable coin balance (the old Coin Hoarder trap).
    case climbPickupCoins       = "climb_pickup_coins"

    // Challenge Tracks (existing)
    /// Max over `trackProgress` values (1–100 high-water per track).
    case trackBestProgress      = "track_best_progress"
    /// `completedTracks.count` (8 tracks total).
    case tracksCompleted        = "tracks_completed"
    /// 1 once `"golden-gauntlet"` ∈ `completedTracks`.
    case goldenGauntletCompleted = "golden_gauntlet_completed"

    // Daily Challenge & Streaks
    /// 1 once `"daily"` ∈ `playedModeIDs` (NEW latch at
    /// `startDailyChallenge()` — trophy-catalog.md §6 item 18).
    case dailyPlayed            = "daily_played"
    /// `dailyChallengeCompletions.count` (persisted date set).
    case dailyClears            = "daily_clears"
    /// Latched high-water of `dailyStreak` at claim time (NEW latch —
    /// never the broken computed `liveStreak`).
    case dailyRewardStreakBest  = "daily_reward_streak_best"
    /// Best run of consecutive calendar dates in the completions date set
    /// (derivation helper, no new storage — §6 item 15).
    case dailyClearStreakBest   = "daily_clear_streak_best"

    // Minigames — arcade-wide (existing)
    /// `playedModeIDs` ∩ the 12 minigame ids, counted.
    case minigamesPlayed        = "minigames_played"
    /// Sum of `minigameWins` over the 6 competitive mode ids.
    case competitiveWins        = "competitive_wins"
    /// Count of the 6 competitive modes with ≥1 win.
    case competitiveModesWon    = "competitive_modes_won"
    /// Count of the 6 competitive modes with ≥1 win on Hard
    /// (`minigameDifficultyWins["<id>|hard"]`).
    case competitiveModesWonHard = "competitive_modes_won_hard"

    // Minigames — per game (existing; mode-id naming trap documented in
    // trophy-catalog.md §3.5: `goldrush` = Smash and Grab; the Coin Pit
    // reward run lives in `goldrushBest`/`goldrushCoinsTotal`).
    case snakeWins              = "snake_wins"
    case sumoWins               = "sumo_wins"
    case paintballWins          = "paintball_wins"
    case goldrushWins           = "goldrush_wins"
    case marblecupWins          = "marblecup_wins"
    case kothWins               = "koth_wins"
    /// `minigameBests["paintball"]` — best floor-coverage %.
    case paintballBestCoverage  = "paintball_best_coverage"
    /// `minigameBests["koth"]` — best hill-hold seconds in one round.
    case kothBestHoldSeconds    = "koth_best_hold_seconds"
    /// `pinballBest` — single-game score PB.
    case pinballBestScore       = "pinball_best_score"
    /// `minigameBests["rollout"]` — highest maze reached.
    case rolloutBestMaze        = "rollout_best_maze"
    /// `minigameBests["rollup"]` — best height (m).
    case rollupBestHeight       = "rollup_best_height"
    /// Max over `minigameBests["discoeasy"/"disco"/"discohard"]`.
    case discoBestCrossings     = "disco_best_crossings"
    /// `minigameBests["discohard"]` only.
    case discoHardBestCrossings = "disco_hard_best_crossings"
    /// `zenSeconds` — cumulative Zen Garden time.
    case zenSeconds             = "zen_seconds"
    /// 1 once `"coinpit"` ∈ `playedModeIDs`.
    case coinpitPlayed          = "coinpit_played"
    /// `goldrushBest` — best single Coin Pit round haul.
    case coinpitBestCatch       = "coinpit_best_catch"
    /// `goldrushCoinsTotal` — lifetime coins caught in Coin Pit rounds.
    case coinpitCoinsTotal      = "coinpit_coins_total"
    /// High-water of tickets staked on a single Coin Pit round (NEW hook
    /// at round start — §6 item 13; never fires on refund).
    case coinpitRoundStakeBest  = "coinpit_round_stake_best"

    // Cosmetics & Collection (ownership counts EXCLUDE the 4 IAP secrets:
    // BallSkin.diamond, BallSkin.moneyBall, TrailColor.moneyRoll,
    // Floor.moneyFull — trophy-catalog.md §3.6; constant wired S1-T5).
    /// Lifetime count of successful COIN purchases via the
    /// `purchase`/`purchaseBundle`/`purchasePack` funnels (NEW latch,
    /// S1-T5). Coin spends only — free grants and IAP never count.
    case cosmeticCoinBuys       = "cosmetic_coin_buys"
    /// 1 once a non-starter cosmetic is equipped in all 7 slots
    /// (Ball/Goal/Trail/Floor/Pit/Boundary/Music) simultaneously.
    case fullNonstarterLoadouts = "full_nonstarter_loadouts"
    /// `completedBundleIDs.count`.
    case bundlesCompleted       = "bundles_completed"
    /// `ownedBallSkins.count`, IAP secrets excluded.
    case ballsOwned             = "balls_owned"
    /// Sum of owned cosmetics across all 7 slots, IAP secrets excluded.
    case cosmeticsOwned         = "cosmetics_owned"
    /// `ownedPacks.count` (Planets / Sports / Vintage Glass).
    case packsOwned             = "packs_owned"
    /// Owned count within the evergreen coin-or-skill-reachable set:
    /// full catalogue − 4 IAP secrets − 7 seasonal bundle-exclusive balls
    /// (207 at v1 — re-derived at §6 item 16, pending open Q10).
    case evergreenCosmeticsOwned = "evergreen_cosmetics_owned"

    // Economy (play-sourced only — no coins-spent metric exists, ever)
    /// Latched high-water of `coinBalance` (flagged borderline, open Q3 —
    /// ships per catalog; money may accelerate, never be required).
    case coinBalancePeak        = "coin_balance_peak"
    /// Lifetime daily-reward claims (NEW counter in `claimDailyReward`,
    /// §6 item 5). Counts claims, not streaks.
    case dailyRewardClaims      = "daily_reward_claims"
    /// Source-tagged lifetime coins earned FROM PLAY (NEW counter in
    /// `addCoins`, §6 item 4). Excludes IAP grants, Sell Back refunds,
    /// and `grantBundleFree` gift compensation — the exclusions are
    /// load-bearing.
    case coinsEarnedFromPlay    = "coins_earned_from_play"

    // Social — Friends & Clans (NEW client-side latches, §6 item 14;
    // off the capstone path; signed-out players simply stay locked)
    /// 1 once `SocialClient.setSession` succeeds.
    case signedIn               = "signed_in"
    /// High-water count of accepted friendships.
    case friendsAcceptedPeak    = "friends_accepted_peak"
    /// Lifetime lives sent (friend gifts + clan fulfillments).
    case livesSent              = "lives_sent"
    /// 1 once a clan is joined or created.
    case clanJoined             = "clan_joined"
    /// Lifetime clan life-requests fulfilled.
    case clanRequestsFulfilled  = "clan_requests_fulfilled"

    // Skill & Style (climb-mode-gated; run events per §6 items 6–8)
    /// Count of veryHard levels (number % 5 == 0) above level 10 holding
    /// 3 stars — the digit rule is the stable difficulty vocabulary.
    case veryhardAceLevels      = "veryhard_ace_levels"
    /// Min over `bestTime` values — fastest single-level clear, seconds.
    /// The one criterion that compares with `lte`.
    case fastestClearSeconds    = "fastest_clear_seconds"
    /// Latched best consecutive no-fall climb-clear streak (NEW counter,
    /// §6 item 6; resets only on a CLIMB fall — mode-gated).
    case noFallClearStreakBest  = "no_fall_clear_streak_best"
    /// Count of 3-star clears on a first-ever attempt (NEW run flag,
    /// §6 item 7).
    case firstTryAces           = "first_try_aces"
    /// Count of runs with 3 stars AND all 3 pickups in the same run
    /// (NEW composite at `recordResult`, §6 item 8).
    case spotlessRuns           = "spotless_runs"

    // Secret & Whimsy events
    /// Falls into the pit on climb level 1 (tutorial-exempt fall funnel,
    /// §6 item 9 — `consumeLife` never fires ≤L10).
    case levelOneFalls          = "level_one_falls"
    /// Zen Garden sessions touched between 00:00 and 04:00 local
    /// (wall-clock check in `addZenSeconds`, §6 item 10).
    case nightZenSessions       = "night_zen_sessions"
    /// All four ROLL rollover lanes completed within a single pinball
    /// ball (§6 item 11). NEVER FIRES in v1 — the shipped table has no
    /// ROLL lanes (external blocker); the engine must tolerate this.
    case pinballRollLaneSweeps  = "pinball_roll_lane_sweeps"
    /// Times the full all-starter loadout was equipped while owning 20+
    /// cosmetics (checked on equip).
    case starterLoadoutFlexes   = "starter_loadout_flexes"

    // Capstone
    /// Count of unlocked trophies among the capstone's required id list —
    /// derived from the trophy ledger itself, zero extra bookkeeping.
    /// Only `capstone_all` may use this metric.
    case baseTrophiesUnlocked   = "base_trophies_unlocked"

    /// Where a metric's value comes from — the guardrail's compile-time
    /// classification. Exhaustive on purpose (no `default`): adding a
    /// metric forces a conscious provenance declaration here, and the
    /// catalog tests assert no provenance is IAP-, purchase-, or
    /// layout-shaped (no such case exists to declare).
    enum Provenance {
        /// Climb / track / daily / minigame / skill play stats — existing
        /// GameState properties or new latched TrophyStats counters.
        case gameplayProgress
        /// Cosmetics ownership / completion counts (IAP secrets excluded
        /// by definition).
        case cosmeticsOwnership
        /// Play-sourced economy counters (never spend-, IAP-, or
        /// refund-sourced).
        case economyPlay
        /// Client-side social action latches (sign-in, friends, lives,
        /// clans).
        case socialAction
        /// The trophy ledger itself (capstone only).
        case trophyLedger
    }

    var provenance: Provenance {
        switch self {
        case .climbHighestUnlocked, .climbTotalStars, .climbPerfectWorlds,
             .climbPickupCoins,
             .trackBestProgress, .tracksCompleted, .goldenGauntletCompleted,
             .dailyPlayed, .dailyClears, .dailyRewardStreakBest,
             .dailyClearStreakBest,
             .minigamesPlayed, .competitiveWins, .competitiveModesWon,
             .competitiveModesWonHard,
             .snakeWins, .sumoWins, .paintballWins, .goldrushWins,
             .marblecupWins, .kothWins,
             .paintballBestCoverage, .kothBestHoldSeconds, .pinballBestScore,
             .rolloutBestMaze, .rollupBestHeight,
             .discoBestCrossings, .discoHardBestCrossings,
             .zenSeconds, .coinpitPlayed, .coinpitBestCatch,
             .coinpitCoinsTotal, .coinpitRoundStakeBest,
             .veryhardAceLevels, .fastestClearSeconds,
             .noFallClearStreakBest, .firstTryAces, .spotlessRuns,
             .levelOneFalls, .nightZenSessions, .pinballRollLaneSweeps,
             .starterLoadoutFlexes:
            return .gameplayProgress
        case .cosmeticCoinBuys, .fullNonstarterLoadouts, .bundlesCompleted,
             .ballsOwned, .cosmeticsOwned, .packsOwned,
             .evergreenCosmeticsOwned:
            return .cosmeticsOwnership
        case .coinBalancePeak, .dailyRewardClaims, .coinsEarnedFromPlay:
            return .economyPlay
        case .signedIn, .friendsAcceptedPeak, .livesSent, .clanJoined,
             .clanRequestsFulfilled:
            return .socialAction
        case .baseTrophiesUnlocked:
            return .trophyLedger
        }
    }

    /// The 6 competitive minigame mode ids (a winner is declared; wins
    /// mint tickets). Shared vocabulary for S0-T2/S1 wiring.
    static let competitiveModeIDs: [String] = [
        "snake", "sumo", "paintball", "goldrush", "marblecup", "koth",
    ]

    /// All 12 minigame mode ids (`minigames_played` counts against these).
    static let minigameModeIDs: [String] = [
        "zen", "coinpit", "snake", "sumo", "paintball", "goldrush",
        "marblecup", "koth", "pinball", "rollout", "rollup", "disco",
    ]
}

// MARK: - Criteria

/// How a criterion compares the metric value against its threshold.
/// Omitted in JSON for the default (`gte`); only `fastest_clear_seconds`
/// uses `lte` in v1.
enum TrophyComparison: String, Codable {
    case greaterOrEqual = "gte"
    case lessOrEqual    = "lte"

    func isSatisfied(value: Double, threshold: Double) -> Bool {
        switch self {
        case .greaterOrEqual: return value >= threshold
        case .lessOrEqual:    return value <= threshold
        }
    }
}

/// One objectively testable unlock rule: metric + threshold (+ comparison).
/// The capstone additionally carries `requiredTrophyIDs` — the FROZEN
/// launch base list (design.md §9: post-launch additive trophies never
/// join the capstone, so the list is explicit data, not a live derivation).
struct TrophyCriteria: Codable, Equatable {
    let metric: TrophyMetric
    let threshold: Double
    let comparison: TrophyComparison
    /// Capstone only: the exact ids whose unlocks feed
    /// `base_trophies_unlocked`. `nil` for every other trophy.
    let requiredTrophyIDs: [String]?

    init(metric: TrophyMetric,
         threshold: Double,
         comparison: TrophyComparison = .greaterOrEqual,
         requiredTrophyIDs: [String]? = nil) {
        self.metric = metric
        self.threshold = threshold
        self.comparison = comparison
        self.requiredTrophyIDs = requiredTrophyIDs
    }

    private enum CodingKeys: String, CodingKey {
        case metric, threshold, comparison, requiredTrophyIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metric = try container.decode(TrophyMetric.self, forKey: .metric)
        threshold = try container.decode(Double.self, forKey: .threshold)
        comparison = try container.decodeIfPresent(TrophyComparison.self,
                                                   forKey: .comparison) ?? .greaterOrEqual
        requiredTrophyIDs = try container.decodeIfPresent([String].self,
                                                          forKey: .requiredTrophyIDs)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metric, forKey: .metric)
        try container.encode(threshold, forKey: .threshold)
        if comparison != .greaterOrEqual {
            try container.encode(comparison, forKey: .comparison)
        }
        try container.encodeIfPresent(requiredTrophyIDs, forKey: .requiredTrophyIDs)
    }
}

// MARK: - Definition

/// One trophy, exactly as authored in `TrophyCatalog.json`
/// (fields per design.md §9; **no points field in v1** — point weights are
/// deferred to the Game Center phase per trophy-catalog.md open Q6).
struct TrophyDefinition: Codable, Equatable, Identifiable {
    /// Frozen-forever snake_case id (GC-legal). Never reused, never renamed.
    let id: String
    /// Display name (draft copy pending Mac's pass; text may be polished,
    /// semantics may not).
    let title: String
    let tier: TrophyTier
    let category: TrophyCategory
    /// Objective shown before unlock (secret trophies are masked by the
    /// UI as "???" rows — the data still carries the real text).
    let lockedDescription: String
    /// Celebration copy shown after unlock.
    let unlockedDescription: String
    /// Hidden until earned — exactly the 5 Secret & Whimsy trophies in v1.
    let isSecret: Bool
    let criteria: TrophyCriteria
    /// Optional earned-regalia reward reference. All `nil` in v1: the
    /// capstone regalia item is approved in principle (D1/P2) but the
    /// mint-new vs reuse detail is still open (D8) — never a coin grant.
    let rewardID: String?
    /// Catalog version that introduced this trophy ("1.0" for launch).
    let addedInVersion: String

    private enum CodingKeys: String, CodingKey {
        case id, title, tier, category
        case lockedDescription, unlockedDescription
        case isSecret = "secret"
        case criteria
        case rewardID = "reward"
        case addedInVersion
    }
}

// MARK: - Catalog

/// Validation failures the loader can raise. The bundled catalog failing
/// ANY of these is a build-breaking authoring error, never a runtime
/// condition to recover from.
enum TrophyCatalogError: Error, Equatable {
    case bundledResourceMissing
    case duplicateID(String)
    case illegalID(String)
    case emptyText(id: String, field: String)
    case invalidThreshold(id: String)
    case forbiddenMetricKey(id: String, metric: String)
    case secretOutsideSecretWhimsy(id: String)
    case capstoneCountInvalid(found: Int)
    case capstoneShapeInvalid(reason: String)
    case requiredIDsOnNonCapstone(id: String)
    case unknownRequiredID(String)
    case capstoneListMismatch(missing: [String], extra: [String])
    case ledgerMetricOutsideCapstone(id: String)
}

/// The loaded, validated v1 trophy catalog.
///
/// Load once (launch or first use), keep immutable. The engine (S0-T3)
/// builds its metric-keyed index from `trophies`; UI reads definitions
/// through `trophy(withID:)`.
struct TrophyCatalog {
    /// Monotically bumped when the FILE format changes (not per content
    /// edit — content is additive-only per design.md §9).
    let catalogVersion: Int
    /// All trophies in catalog (play-path) order.
    let trophies: [TrophyDefinition]
    /// Definition lookup by frozen id.
    private let byID: [String: TrophyDefinition]

    /// The launch content version — the capstone's frozen base list is
    /// exactly the visible bronze/silver/gold trophies added in this
    /// version (post-launch additions never gate the capstone).
    static let launchVersion = "1.0"

    /// Resource name of the bundled catalog (`TrophyCatalog.json`) — the
    /// LevelOverrides pattern.
    static let bundledResource = "TrophyCatalog"

    var count: Int { trophies.count }

    /// The single capstone ("Platinum") definition.
    var capstone: TrophyDefinition {
        // Validated at load: exactly one platinum-tier trophy exists.
        trophies.first(where: { $0.tier.isCapstone })!
    }

    func trophy(withID id: String) -> TrophyDefinition? { byID[id] }

    // MARK: Loading

    /// Decodes and validates the bundled `TrophyCatalog.json`.
    /// Unit tests run hosted in RollAlong.app, so `.main` resolves the
    /// app bundle there too.
    static func load(bundle: Bundle = .main) throws -> TrophyCatalog {
        guard let url = bundle.url(forResource: bundledResource,
                                   withExtension: "json") else {
            throw TrophyCatalogError.bundledResourceMissing
        }
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }

    /// Decodes and validates catalog JSON data (test seam).
    static func load(from data: Data) throws -> TrophyCatalog {
        let file = try JSONDecoder().decode(CatalogFile.self, from: data)
        try validate(file.trophies)
        var index: [String: TrophyDefinition] = [:]
        index.reserveCapacity(file.trophies.count)
        for trophy in file.trophies { index[trophy.id] = trophy }
        return TrophyCatalog(catalogVersion: file.catalogVersion,
                             trophies: file.trophies,
                             byID: index)
    }

    /// On-disk shape of `TrophyCatalog.json`.
    struct CatalogFile: Codable {
        let catalogVersion: Int
        let trophies: [TrophyDefinition]
    }

    private init(catalogVersion: Int,
                 trophies: [TrophyDefinition],
                 byID: [String: TrophyDefinition]) {
        self.catalogVersion = catalogVersion
        self.trophies = trophies
        self.byID = byID
    }

    // MARK: Guardrail validation

    /// Full guardrail pass (design.md §9). Throws the first violation.
    static func validate(_ trophies: [TrophyDefinition]) throws {
        var seen = Set<String>()
        for trophy in trophies {
            guard isGameCenterLegalID(trophy.id) else {
                throw TrophyCatalogError.illegalID(trophy.id)
            }
            guard seen.insert(trophy.id).inserted else {
                throw TrophyCatalogError.duplicateID(trophy.id)
            }
            for (field, text) in [("title", trophy.title),
                                  ("lockedDescription", trophy.lockedDescription),
                                  ("unlockedDescription", trophy.unlockedDescription),
                                  ("addedInVersion", trophy.addedInVersion)]
            where text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw TrophyCatalogError.emptyText(id: trophy.id, field: field)
            }
            guard trophy.criteria.threshold > 0,
                  trophy.criteria.threshold.isFinite else {
                throw TrophyCatalogError.invalidThreshold(id: trophy.id)
            }
            // No criterion may reference IAP products, purchases, or
            // specific level layouts. The TrophyMetric vocabulary cannot
            // express those today; this raw-key scan is defense-in-depth
            // against a future metric case that tries.
            if isForbiddenCriteriaKey(trophy.criteria.metric.rawValue) {
                throw TrophyCatalogError.forbiddenMetricKey(
                    id: trophy.id, metric: trophy.criteria.metric.rawValue)
            }
            if trophy.isSecret && trophy.category != .secretWhimsy {
                throw TrophyCatalogError.secretOutsideSecretWhimsy(id: trophy.id)
            }
            if trophy.criteria.requiredTrophyIDs != nil && !trophy.tier.isCapstone {
                throw TrophyCatalogError.requiredIDsOnNonCapstone(id: trophy.id)
            }
            if trophy.criteria.metric == .baseTrophiesUnlocked && !trophy.tier.isCapstone {
                throw TrophyCatalogError.ledgerMetricOutsideCapstone(id: trophy.id)
            }
        }
        try validateCapstone(in: trophies, allIDs: seen)
    }

    /// The capstone must exist exactly once and require exactly the launch
    /// base list: every visible bronze/silver/gold trophy added in
    /// `launchVersion`, with Social, Secret & Whimsy, and the Diamond tier
    /// quarantined off the path (trophy-catalog.md §3.11).
    private static func validateCapstone(in trophies: [TrophyDefinition],
                                         allIDs: Set<String>) throws {
        let capstones = trophies.filter { $0.tier.isCapstone }
        guard capstones.count == 1 else {
            throw TrophyCatalogError.capstoneCountInvalid(found: capstones.count)
        }
        let capstone = capstones[0]
        guard capstone.category == .capstone else {
            throw TrophyCatalogError.capstoneShapeInvalid(
                reason: "capstone tier requires capstone category")
        }
        guard trophies.filter({ $0.category == .capstone }).count == 1 else {
            throw TrophyCatalogError.capstoneShapeInvalid(
                reason: "capstone category must contain exactly the capstone")
        }
        guard !capstone.isSecret else {
            throw TrophyCatalogError.capstoneShapeInvalid(reason: "capstone cannot be secret")
        }
        guard capstone.criteria.metric == .baseTrophiesUnlocked,
              capstone.criteria.comparison == .greaterOrEqual else {
            throw TrophyCatalogError.capstoneShapeInvalid(
                reason: "capstone must count the trophy ledger with gte")
        }
        guard let required = capstone.criteria.requiredTrophyIDs,
              !required.isEmpty else {
            throw TrophyCatalogError.capstoneShapeInvalid(
                reason: "capstone requires an explicit trophy id list")
        }
        let requiredSet = Set(required)
        guard requiredSet.count == required.count else {
            throw TrophyCatalogError.capstoneShapeInvalid(
                reason: "capstone id list contains duplicates")
        }
        if let unknown = required.first(where: { !allIDs.contains($0) }) {
            throw TrophyCatalogError.unknownRequiredID(unknown)
        }
        let expected = expectedCapstoneRequirement(in: trophies)
        guard requiredSet == expected else {
            throw TrophyCatalogError.capstoneListMismatch(
                missing: expected.subtracting(requiredSet).sorted(),
                extra: requiredSet.subtracting(expected).sorted())
        }
        guard capstone.criteria.threshold == Double(required.count) else {
            throw TrophyCatalogError.capstoneShapeInvalid(
                reason: "capstone threshold must equal its required id count")
        }
    }

    /// The launch base list the capstone must require: visible
    /// bronze/silver/gold, capstone-eligible category, added at launch.
    static func expectedCapstoneRequirement(in trophies: [TrophyDefinition]) -> Set<String> {
        Set(trophies.compactMap { trophy in
            guard trophy.tier == .bronze || trophy.tier == .silver || trophy.tier == .gold,
                  !trophy.isSecret,
                  trophy.category.countsTowardCapstone,
                  trophy.addedInVersion == launchVersion else { return nil }
            return trophy.id
        })
    }

    /// Game Center-legal, frozen-forever id: lowercase snake_case
    /// (alphanumeric + underscore), starts with a letter, ≤100 chars.
    static func isGameCenterLegalID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 100,
              let first = id.unicodeScalars.first,
              ("a"..."z").contains(Character(first)) else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            let c = Character(scalar)
            return ("a"..."z").contains(c) || ("0"..."9").contains(c) || c == "_"
        }
    }

    /// Vocabulary tokens no criterion metric key may ever contain —
    /// IAP/purchase/monetization criteria and layout-keyed criteria are
    /// banned outright (sprint-plan.md §4 addenda; trophy-catalog.md
    /// "deliberately absent" list). Note "coin buys" (the coin shop) is
    /// legal vocabulary; "purchase"/IAP language is not.
    static func isForbiddenCriteriaKey(_ rawKey: String) -> Bool {
        let key = rawKey.lowercased()
        let bannedTokens = [
            "iap", "purchase", "storekit", "transaction", "product",
            "receipt", "price", "revenue", "spent", "spend",
            "ads_watched", "ad_watch",
            "out_of_lives", "lives_lost", "failure",
            "layout",
        ]
        return bannedTokens.contains { key.contains($0) }
    }
}
