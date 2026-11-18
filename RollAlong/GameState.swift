import StoreKit
import SwiftUI

// ---------------------------------------------------------------------------
// UserDefaults audit (QE2 §7) — all ra_* keys are non-sensitive game state.
//
// Keys written: ra_level, ra_skin, ra_name, ra_haptics, ra_sound,
//   ra_introEnabled,
//   ra_startAtTop, ra_minigameDifficulty, ra_seenOnboarding, ra_seenWelcomeMoment,
//   ra_seenTutorialReward,
//   ra_bestStars, ra_bestTime, ra_collectedCoins, ra_highestUnlocked,
//   ra_lives, ra_purchasedLives, ra_lastLifeLostAt, ra_unlimitedLives, ra_dailyStreak,
//   ra_lastDailyClaim, ra_starterPackShownAt, ra_starterPackClaimed,
//   ra_starterPackDismissed,
//   ra_lastReviewPromptDate, ra_coinBalance, ra_tickets, ra_ownedBallSkins, ra_ownedGoals,
//   ra_ownedTrails, ra_ownedFloors, ra_ownedPits, ra_ownedBoundaries,
//   ra_ownedBundles, ra_ownedPacks, ra_freeGrantedItems, ra_paidPrices,
//   ra_ownedMusic, ra_trackProgress, ra_completedTracks, ra_equippedGoal,
//   ra_equippedTrail, ra_equippedFloor, ra_equippedPit, ra_equippedBoundary,
//   ra_equippedMusic, ra_equippedPack.
//
// TrophyStats adds (bumped only from GameState funnels — S0-T2):
//   ra_trophyCoinsEarnedFromPlay, ra_trophyDailyRewardClaims,
//   ra_trophyNoFallClearStreak, ra_trophyNoFallClearStreakBest.
//   Latched trophy counters — monotonic ratchets, untouched by
//   resetProgress() / liquidateCoinCosmetics().
//
// TrophyEngine adds (written only by the engine at unlock time — S0-T3):
//   ra_trophyUnlocks, ra_trophyUnlockDates.
//   The latched unlock ledger — a pure ratchet: never revoked, untouched
//   by resetProgress() / liquidateCoinCosmetics().
//   ra_trophySyncDirty (S1-T8) — a Bool armed synchronously on every
//   unlock (live + backfill) and cleared by S3-T3's TrophySyncService once
//   a full-snapshot upsert succeeds; survives relaunch so an offline unlock
//   still syncs next online launch. No PII.
//   ra_trophyCapstonePresented (S2-T5) — a Bool latching the Platinum
//   capstone's full-screen celebration to a once-ever event; set when the
//   blowout has played, survives relaunch so it never replays. No PII.
//   ra_trophyRevealPresented (S2-T6) — a Bool latching the one-time
//   retroactive-grant "you've already earned N" reveal to a once-ever event;
//   set when the summary has been offered (or when a fresh install had nothing
//   to reveal), survives relaunch so it never re-offers. No PII.
//   ra_trophyPins (S2-T7) — an ordered plist string array of up to 3 pinned
//   trophy ids driving the "what am I chasing?" chips; player-chosen, capped,
//   survives relaunch. Display state only, no PII.
//
// AnalyticsClient adds: ra_analytics_user_id — anonymous per-install UUID,
//   not linked to real-world identity, declared in PrivacyInfo.xcprivacy.
//
// Verdict: no auth tokens, no IDFA/IDFV, no payment data.  All values are
//   gameplay state or UI settings.  UserDefaults is the appropriate store.
//   No iCloud KV sync in use.  Keychain migration: not required.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Trophy collection-criterion exclusions (S1-T5)
//
// The collection/ownership trophies (`balls_own_10/40`, `items_own_50`,
// `collection_complete`) must never become a hidden pay-gate or a
// time-limited (eventually-dead) criterion.  Two disjoint exclusion sets,
// defined here as the SINGLE source of truth so live wiring and the
// first-launch backfill agree and a unit test can pin them exactly:
//
//   • `iapSecret*` — the 4 secret-drop IAP cosmetics {Diamond ball, Money
//     Ball, Money Roll, Money Full}.  Excluded from EVERY collection
//     criterion (counting them would create a ~$150 pay-gated trophy and
//     leak the secret).  These are NOT the `isIconic`/`iconicBalls` set —
//     Iconic also contains the earned Trophy ball and starter looks, which
//     DO count toward collection criteria.
//   • `seasonalExclusiveBalls` — the 7 `isBundleExclusive` seasonal balls
//     whose bundle windows are hard-coded one-shot 2026–27 ranges.  Excluded
//     from `collection_complete` ONLY (scoping it to the 242-item evergreen
//     set), so the trophy never becomes permanently unearnable once a window
//     lapses.  (NOT excluded from `balls_own_*`/`items_own_50`, which count
//     seasonal balls per catalog §3.6.)  BallSkin.isBundleExclusive is a
//     SUPERSET of this (it also flags Pluto/Trophy/Diamond/Money) — so this
//     list is enumerated explicitly, never derived from that flag.
//
// Note: `moneyRoll` is a TrailColor and `moneyFull` a Floor, so only two of
// the four IAP secrets are balls.  See trophy-catalog.md §3.6 / open Q10.
// ---------------------------------------------------------------------------
enum TrophyCosmeticExclusions {
    /// The two IAP-secret BALL skins (Diamond, Money Ball).
    static let iapSecretBalls: Set<BallSkin> = [.diamond, .moneyBall]
    /// The IAP-secret TRAIL (Money Roll).
    static let iapSecretTrails: Set<TrailColor> = [.moneyRoll]
    /// The IAP-secret FLOOR (Money Full).
    static let iapSecretFloors: Set<Floor> = [.moneyFull]

    /// Exactly the 4 IAP secrets as persisted rawValues, for the exclusion
    /// unit test and rawValue-set membership checks against the owned sets.
    static let iapSecretRawValues: Set<String> =
        Set(iapSecretBalls.map { $0.rawValue })
            .union(iapSecretTrails.map { $0.rawValue })
            .union(iapSecretFloors.map { $0.rawValue })

    /// The 7 seasonal `isBundleExclusive` balls (each in a one-shot 2026–27
    /// window) — excluded from `collection_complete` only.
    static let seasonalExclusiveBalls: Set<BallSkin> =
        [.beachBall, .pumpkin, .ornament, .heartstone,
         .shamrock, .confetti, .speckledEgg]

    static let seasonalExclusiveBallRawValues: Set<String> =
        Set(seasonalExclusiveBalls.map { $0.rawValue })
}

final class GameState: ObservableObject {

    // MARK: - Published state

    @Published var currentLevel: Int {
        didSet { defaults.set(currentLevel, forKey: "ra_level") }
    }
    @Published var activeSkin: BallSkin {
        didSet {
            defaults.set(activeSkin.rawValue, forKey: "ra_skin")
            if activeSkin != oldValue { syncMyLook() }
        }
    }
    @Published var playerName: String {
        didSet { defaults.set(playerName, forKey: "ra_name") }
    }
    /// Player-chosen accent colour (persisted as "#RRGGBB").  Used for niche
    /// personalisation — e.g. the rim around their nickname in competitive games.
    @Published var primaryColorHex: String {
        didSet {
            defaults.set(primaryColorHex, forKey: "ra_primaryColorHex")
            if primaryColorHex != oldValue { syncMyLook() }
        }
    }

    /// Send the accent color and equipped ball to the server (signed in only),
    /// so other players see them.  Called when either changes and on sign-in.
    func syncMyLook() {
        guard SocialClient.shared.isSignedIn else { return }
        // Wait until the player stops changing it (dragging the color picker
        // fires many changes), then send only the latest.
        lookSyncTask?.cancel()
        lookSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, !Task.isCancelled else { return }
            let hex = self.primaryColorHex, ball = self.activeSkin.rawValue
            await SocialClient.shared.syncMyLook(accentHex: hex, ballSkin: ball)
        }
    }
    private var lookSyncTask: Task<Void, Never>?
    static let defaultPrimaryHex = "#48D188"   // the scoreboard green
    static let defaultPrimaryColor = Color(red: 0.28, green: 0.82, blue: 0.52)
    /// `primaryColorHex` as a SwiftUI Color (for binding to a ColorPicker).
    var primaryColor: Color {
        get { Color(hexRGB: primaryColorHex) ?? Self.defaultPrimaryColor }
        set { primaryColorHex = newValue.hexRGB }
    }
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: "ra_haptics") }
    }
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: "ra_sound") }
    }
    /// Local-notification opt-ins (Settings → Notifications).  Default OFF;
    /// enabling one requests system permission.  Scheduling lives in
    /// `recordShopViewed()` / `reconcileLivesNotification()` → NotificationManager.
    @Published var shopFreshNotifEnabled: Bool {
        didSet { defaults.set(shopFreshNotifEnabled, forKey: "ra_notifShopFresh") }
    }
    @Published var livesFullNotifEnabled: Bool {
        didSet { defaults.set(livesFullNotifEnabled, forKey: "ra_notifLivesFull") }
    }
    /// Whether the signed-in player's CURATED public trophy showcase is shared
    /// on their public profile (S3-T9; design.md §7 / decision #10, D6).
    /// Defaults ON — the design ruling is "on for signed-in players" (sign-in is
    /// already the opt-in gate for public profiles). Toggling it OFF in Settings
    /// deletes the showcase server-side via `TrophySyncService.syncShowcase`.
    @Published var trophyShowcaseEnabled: Bool {
        didSet { defaults.set(trophyShowcaseEnabled, forKey: "ra_trophyShowcaseEnabled") }
    }
    /// Plays the cinematic opening-credits intro on cold launch.  Defaults
    /// OFF — pre-launch feature flag, flipped on from Settings once vetted
    /// on-device.  See IntroView / ContentView.
    @Published var introEnabled: Bool {
        didSet { defaults.set(introEnabled, forKey: "ra_introEnabled") }
    }
    /// Transient UI signal (not persisted): bumped when the opening intro hands
    /// off, so HomeView re-centres its roaming ball to line up with the intro's
    /// settled ball. See IntroView / ContentView.
    @Published var homeBallRecenterSignal: Int = 0
    @Published var ballStartsAtTop: Bool {
        didSet { defaults.set(ballStartsAtTop, forKey: "ra_startAtTop") }
    }
    /// Clanmates' open life requests this player has not given to yet — the
    /// red badge on Home's Clans button.  Not saved; refreshed from the server
    /// (see `refreshClanRequestBadge`).
    @Published var clanRequestBadge: Int = 0

    /// Re-count the badge from the server.  Called when Home comes to the
    /// front, once a minute while it stays there, and by the clan page.
    func refreshClanRequestBadge() {
        guard SocialClient.shared.isSignedIn else {
            if clanRequestBadge != 0 { clanRequestBadge = 0 }
            return
        }
        Task { @MainActor [weak self] in
            let n = await SocialClient.shared.countOpenClanRequests()
            if self?.clanRequestBadge != n { self?.clanRequestBadge = n }
        }
    }

    /// How a level starts.  true = "Tap to Start": the level loads paused and
    /// begins when the player taps.  false = "Auto Start": it begins by itself
    /// after a short beat.  Default is Tap to Start.  Applies to Adventure
    /// and Challenge Tracks (see `startSettingApplies` in BallGameView).
    @Published var tapToStart: Bool {
        didSet { defaults.set(tapToStart, forKey: "ra_tapToStart") }
    }
    /// How hard the competitive-minigame AI plays (see MinigameDifficulty).
    @Published var minigameDifficulty: MinigameDifficulty {
        didSet { defaults.set(minigameDifficulty.rawValue, forKey: "ra_minigameDifficulty") }
    }

    // One-time UX moments — survive resetProgress() so a returning player
    // who resets level progress isn't shown the intro/welcome again.
    @Published var seenOnboarding: Bool {
        didSet { defaults.set(seenOnboarding, forKey: "ra_seenOnboarding") }
    }
    @Published var seenWelcomeMoment: Bool {
        didSet { defaults.set(seenWelcomeMoment, forKey: "ra_seenWelcomeMoment") }
    }
    @Published var seenTutorialReward: Bool {
        didSet { defaults.set(seenTutorialReward, forKey: "ra_seenTutorialReward") }
    }
    // (`seenTutorialL1` removed — the L1 phased intro is now keyed
    //  off `time(for: 1) == nil`, so it correctly re-runs after
    //  "Reset level progress" without needing a separate flag.)

    // ── Per-level progress (persisted via JSON-encoded dictionaries) ───────
    // bestStars[level]    : 0…3, only ever increases
    // bestTime[level]     : seconds, only ever decreases
    // collectedCoins[level]: Set of coin indices (0…2) the player has banked
    // highestUnlocked     : highest level the player has unlocked (>= 1)
    @Published var bestStars: [Int: Int] {
        didSet { save(bestStars, intValueDict: "ra_bestStars") }
    }
    @Published var bestTime: [Int: TimeInterval] {
        didSet { save(bestTime, doubleValueDict: "ra_bestTime") }
    }
    @Published var collectedCoins: [Int: Set<Int>] {
        didSet { save(collectedCoins, setDict: "ra_collectedCoins") }
    }
    @Published var highestUnlocked: Int {
        didSet { defaults.set(highestUnlocked, forKey: "ra_highestUnlocked") }
    }

    // ── Lives system (Sprint 4c) ───────────────────────────────────────────
    // lives             : regenerative lives, 0…10.  May be stale w.r.t.
    //                     regen — use displayedLives for the live value.
    // purchasedLives    : reserve queue of granted lives (IAP packs, rewarded
    //                     ads, friend gifts).  Unbounded, never regenerates,
    //                     and only drains once the regen bar is empty.
    // lastLifeLostAt    : timestamp of the most recent life consumption.
    //                     Drives regen.  nil when lives == max.
    // unlimitedLives    : true once the one-time Diamond Balls purchase
    //                     ($49.99, unlimited lives) is owned.  Set by StoreKit.
    // ECONOMY: flipped 2026-06-11 from 1-per-10-min / cap 6 to a friendlier
    // 1-per-6-min / cap 10 — faster comebacks, bigger passive bank.
    static let livesMax: Int = 10
    static let livesRegenInterval: TimeInterval = 360   // 6 minutes
    static let tutorialLevelCount: Int = 10             // L1-10 don't consume lives

    @Published var lives: Int {
        didSet { defaults.set(lives, forKey: "ra_lives") }
    }
    @Published var purchasedLives: Int {
        didSet { defaults.set(purchasedLives, forKey: "ra_purchasedLives") }
    }
    @Published var lastLifeLostAt: Date? {
        didSet {
            if let d = lastLifeLostAt {
                defaults.set(d, forKey: "ra_lastLifeLostAt")
            } else {
                defaults.removeObject(forKey: "ra_lastLifeLostAt")
            }
        }
    }
    @Published var unlimitedLives: Bool {
        didSet { defaults.set(unlimitedLives, forKey: "ra_unlimitedLives") }
    }

    // ── Daily reward / login streak ────────────────────────────────────────
    // dailyStreak    : consecutive days claimed, as of the last claim.  Climbs
    //                  forever; the coin ladder cycles every 7 days but the
    //                  counter keeps going, so a long streak reads big.
    // lastDailyClaim : timestamp of the most recent claim.  nil until the first
    //                  claim.  Drives both "is a reward available today" and
    //                  whether the streak is still alive (claimed yesterday).
    @Published var dailyStreak: Int {
        didSet { defaults.set(dailyStreak, forKey: "ra_dailyStreak") }
    }
    @Published var lastDailyClaim: Date? {
        didSet {
            if let d = lastDailyClaim {
                defaults.set(d, forKey: "ra_lastDailyClaim")
            } else {
                defaults.removeObject(forKey: "ra_lastDailyClaim")
            }
        }
    }

    // ── Starter Pack one-time offer ─────────────────────────────────────────
    // starterPackShownAt   : timestamp when the offer sheet was first presented.
    //                        nil until the trigger fires (first time coinBalance
    //                        reaches `starterPackTriggerCoins`).  Drives the
    //                        48-hour countdown.
    // starterPackClaimed   : true once the pack's rewards have been DELIVERED
    //                        (purchase or restore).  Gates the once-only coins
    //                        in StoreKitManager — deliberately NOT set by
    //                        "No thanks", or an Ask-to-Buy purchase approved
    //                        after a dismissal would silently lose its coins.
    // starterPackDismissed : true after the player taps "No thanks" —
    //                        permanent opt-out of the offer UI only; a pending
    //                        or restored purchase still delivers in full.
    @Published var starterPackShownAt: Date? {
        didSet {
            if let d = starterPackShownAt {
                defaults.set(d, forKey: "ra_starterPackShownAt")
            } else {
                defaults.removeObject(forKey: "ra_starterPackShownAt")
            }
        }
    }
    @Published var starterPackClaimed: Bool {
        didSet { defaults.set(starterPackClaimed, forKey: "ra_starterPackClaimed") }
    }
    @Published var starterPackDismissed: Bool {
        didSet { defaults.set(starterPackDismissed, forKey: "ra_starterPackDismissed") }
    }

    // ── Ratings prompt ────────────────────────────────────────────────────
    // Timestamp of the last time SKStoreReviewController.requestReview was
    // called.  nil until the first time the conditions are met.  Used to
    // enforce the 30-day minimum between prompts (Apple allows at most 3
    // per 365 days regardless, but we gate more tightly).
    @Published var lastReviewPromptDate: Date? {
        didSet {
            if let d = lastReviewPromptDate {
                defaults.set(d, forKey: "ra_lastReviewPromptDate")
            } else {
                defaults.removeObject(forKey: "ra_lastReviewPromptDate")
            }
        }
    }

    // ── Cosmetic economy (Sprint 4d) ──────────────────────────────────────
    // Coins are the in-app currency.  Earned from gameplay; spent in the
    // shop to unlock cosmetic items.  Also purchasable in coin packs via
    // StoreKit (PR 4h).  No cap on balance.
    @Published var coinBalance: Int {
        didSet { defaults.set(coinBalance, forKey: "ra_coinBalance") }
    }

    /// Compact coin-pill text: balances of 10,000+ abbreviate to one decimal
    /// place, ALWAYS rounded DOWN (truncated) — 10_000 → "10.0K",
    /// 134_678 → "134.6K".  Anything below 10,000 renders in full.
    static func coinPillText(_ n: Int) -> String {
        guard n >= 10_000 else { return "\(n)" }
        return "\(n / 1000).\((n % 1000) / 100)K"
    }

    // ── Minigame personal bests (drive the per-game leaderboards) ──────────
    // pinballBest  — best single Pinball score.
    // zenSeconds   — total seconds spent in Zen Garden (accumulates).
    // goldrushBest — most coins caught in one Gold Rush match.
    @Published var pinballBest: Int {
        didSet { defaults.set(pinballBest, forKey: "ra_pinballBest") }
    }
    @Published var zenSeconds: Int {
        didSet { defaults.set(zenSeconds, forKey: "ra_zenSeconds") }
    }
    @Published var goldrushBest: Int {
        didSet { defaults.set(goldrushBest, forKey: "ra_goldrushBest") }
    }
    // rollupBestSeconds — duration (seconds) of the best-height Roll Up run.
    // (The best height itself lives in minigameBests["rollup"].)
    @Published var rollupBestSeconds: Int {
        didSet { defaults.set(rollupBestSeconds, forKey: "ra_rollupBestSeconds") }
    }
    /// Best Roll Up height in meters (mirrors minigameBests["rollup"]).
    var rollupBest: Int { minigameBests["rollup", default: 0] }
    /// Disco Ball leaderboards are kept PER DIFFICULTY (Easy / Normal /
    /// Hardcore).  The best crossings for each live in `minigameBests` under
    /// "discoeasy" / "disco" / "discohard"; this holds the average time per
    /// crossing (milliseconds, only the rolling counts) of each difficulty's
    /// best run, keyed "easy" / "normal" / "hard".  0 or missing = unknown
    /// (a best set before the time was recorded).
    @Published var discoBestAvgMs: [String: Int] {
        didSet { save(discoBestAvgMs, trackProgressKey: "ra_discoBestAvgMs") }
    }
    /// The Disco Ball best-crossings key in `minigameBests` for a difficulty.
    static func discoBestKey(_ difficulty: MinigameDifficulty) -> String {
        switch difficulty {
        case .easy:   return "discoeasy"
        case .normal: return "disco"
        case .hard:   return "discohard"
        }
    }
    /// The difficulty a Disco Ball best key belongs to.
    static func discoDifficulty(forBestKey key: String) -> MinigameDifficulty {
        switch key {
        case "discoeasy": return .easy
        case "discohard": return .hard
        default:          return .normal
        }
    }
    /// Most crossings in one Disco Ball run on any difficulty (the profile's
    /// summary line and the leaderboard picker's "most played" order).
    var discoBoardBest: Int {
        MinigameDifficulty.allCases.map { minigameBests[Self.discoBestKey($0), default: 0] }.max() ?? 0
    }
    /// The average time per crossing of the run behind `discoBoardBest`
    /// (the fastest among difficulties tied on crossings); 0 when unknown.
    var discoBoardAvgMs: Int {
        let best = discoBoardBest
        guard best > 0 else { return 0 }
        let times = MinigameDifficulty.allCases
            .filter { minigameBests[Self.discoBestKey($0), default: 0] == best }
            .compactMap { discoBestAvgMs[$0.rawValue] }
            .filter { $0 > 0 }
        return times.min() ?? 0
    }
    /// Per-difficulty leaderboard rows are uploaded once per launch from what
    /// this device already knows (see `backfillDifficultyScores`).
    private var didBackfillDifficultyScores = false
    // goldrushCoinsTotal — lifetime coins caught across all Gold Rush runs
    // (accumulates; powers the home "coins earned" readout).
    @Published var goldrushCoinsTotal: Int {
        didSet { defaults.set(goldrushCoinsTotal, forKey: "ra_goldrushCoinsTotal") }
    }

    /// Gold Rush tickets — earned one per competitive-minigame win, staked
    /// up front to buy a Gold Rush round (every time-ticket = 30 s on the
    /// clock; every coin-ticket adds +1x to the coins dropped).
    @Published var tickets: Int {
        didSet { defaults.set(tickets, forKey: "ra_tickets") }
    }

    // Owned cosmetic items per category, stored as sets of raw strings so
    // JSON round-trip is trivial.  Default ("starter") items are always
    // implicitly owned via `isOwned(_:)`, regardless of set membership.
    @Published var ownedBallSkins:   Set<String> {
        didSet { saveStringSet(ownedBallSkins, forKey: "ra_ownedBallSkins") }
    }
    @Published var ownedGoals:       Set<String> {
        didSet { saveStringSet(ownedGoals, forKey: "ra_ownedGoals") }
    }
    @Published var ownedTrails:      Set<String> {
        didSet { saveStringSet(ownedTrails, forKey: "ra_ownedTrails") }
    }
    /// Owned Floor cosmetics (the surface the ball rolls on).
    @Published var ownedFloors: Set<String> {
        didSet { saveStringSet(ownedFloors, forKey: "ra_ownedFloors") }
    }
    /// Owned Pit cosmetics (the holes the ball falls into).
    @Published var ownedPits: Set<String> {
        didSet { saveStringSet(ownedPits, forKey: "ra_ownedPits") }
    }
    /// Owned Boundary cosmetics (walls / platforms / perimeter).
    @Published var ownedBoundaries: Set<String> {
        didSet { saveStringSet(ownedBoundaries, forKey: "ra_ownedBoundaries") }
    }
    /// Owned bundle IDs (for the shop's "OWNED" badge — items inside
    /// each bundle are also added to their individual owned sets at
    /// purchase time, so this is purely for UI state).
    @Published var ownedBundles: Set<String> {
        didSet { saveStringSet(ownedBundles, forKey: "ra_ownedBundles") }
    }
    /// Cosmetics that were GIFTED (e.g. the post-tutorial Standard bundle, the
    /// Starter Pack) rather than bought with coins.  Sell Back keeps these and
    /// never refunds them — they're un-redeemable.  Keyed by each item's unique
    /// id, `cosmeticKey` ("<Type>:<rawValue>"), so a gift can never be confused
    /// with a same-named item in another slot (the Aurora ball, goal, trail,
    /// floor, pit and boundary all share the name "aurora").  Saves from before
    /// this change held bare rawValues; init qualifies them once
    /// (`qualifyFreeGrants`).  Persisted.
    @Published var freeGrantedItems: Set<String> {
        didSet { saveStringSet(freeGrantedItems, forKey: "ra_freeGrantedItems") }
    }
    /// Coins actually PAID for cosmetics bought below their full `coinCost`
    /// (the Shop's featured-bundle discount, Ball Packs' 66% pricing).  Sell
    /// Back refunds this recorded price instead of `coinCost` — otherwise a
    /// discounted purchase + immediate Sell Back mints the difference, forever.
    /// Keyed by `paidPriceKey` ("<Type>:<rawValue>" — bare rawValues collide
    /// across categories, e.g. five different "aurora" items).  No entry means
    /// full price was paid.  Persisted.
    @Published var paidPrices: [String: Int] {
        didSet { save(paidPrices, trackProgressKey: "ra_paidPrices") }
    }
    /// Owned Ball-Pack IDs.  Buying a Pack also adds its member skins to
    /// `ownedBallSkins` (so they're individually equippable); this set
    /// is for the shop's "OWNED" state + the equip-the-whole-Pack flow.
    @Published var ownedPacks: Set<String> {
        didSet { saveStringSet(ownedPacks, forKey: "ra_ownedPacks") }
    }
    @Published var ownedMusic:       Set<String> {
        didSet { saveStringSet(ownedMusic, forKey: "ra_ownedMusic") }
    }

    // ── Challenge Track progress ─────────────────────────────────────────
    //
    // Each Challenge Track is a 100-level themed side quest.  Beating level
    // 100 delivers the track's paired cosmetic bundle for free (earned, not
    // purchased).  Progress survives app restarts via UserDefaults.

    /// Highest level cleared per Challenge Track: [trackID: level (1…100)].
    /// Missing key = track not yet started.  Level 100 = track complete.
    @Published var trackProgress: [String: Int] {
        didSet { save(trackProgress, trackProgressKey: "ra_trackProgress") }
    }

    /// Lifetime competitive-minigame wins per mode id: [modeID: wins].
    /// Powers the home "N wins" readout when a competitive mode is armed.
    @Published var minigameWins: [String: Int] {
        didSet { save(minigameWins, trackProgressKey: "ra_minigameWins") }
    }

    /// Personal-best score per competitive mode id: [modeID: best].  Units are
    /// mode-specific (Snacky orbs, Sumo points, Paint Ball coverage %,
    /// Marble Cup goals, KotH hold-seconds).  Gold Rush keeps its own flat
    /// `goldrushBest` above; this dict covers the other competitive modes and
    /// feeds the per-mode leaderboards' "Best" column alongside the win tally.
    @Published var minigameBests: [String: Int] {
        didSet { save(minigameBests, trackProgressKey: "ra_minigameBests") }
    }

    /// Per game+difficulty attempt counts, keyed "modeID|difficulty"
    /// (e.g. "snake|hard").  Paired with `minigameDifficultyWins` to derive the
    /// success rate that calibrates the difficulty/payout tables.  See
    /// docs/minigame-difficulty.md.
    @Published var minigameDifficultyPlays: [String: Int] {
        didSet { save(minigameDifficultyPlays, trackProgressKey: "ra_minigameDiffPlays") }
    }
    /// Per game+difficulty win counts, keyed "modeID|difficulty".
    @Published var minigameDifficultyWins: [String: Int] {
        didSet { save(minigameDifficultyWins, trackProgressKey: "ra_minigameDiffWins") }
    }
    /// Per game+difficulty BEST score (snake power, sumo points, paintball
    /// coverage, …), keyed "modeID|difficulty".  Feeds the per-difficulty
    /// leaderboard (synced to `minigame_scores` via recordMinigameResult).
    @Published var minigameDifficultyBests: [String: Int] {
        didSet { save(minigameDifficultyBests, trackProgressKey: "ra_minigameDiffBests") }
    }

    /// Set of Challenge Track IDs fully completed (level 100 cleared).
    /// The reward bundle is granted exactly once when a track enters this set.
    @Published var completedTracks: Set<String> {
        didSet { saveStringSet(completedTracks, forKey: "ra_completedTracks") }
    }
    /// Mode ids the player has launched at least once — drives the one-time
    /// "how to play" tutorial shown the first time each mode is opened.
    @Published var playedModeIDs: Set<String> {
        didSet { saveStringSet(playedModeIDs, forKey: "ra_playedModeIDs") }
    }
    /// The mode the home "Play" button launches — the last mode the player
    /// entered (climb by default).  Persisted across launches; the home screen's
    /// aesthetic can later theme off it.
    @Published var currentModeID: String {
        didSet { defaults.set(currentModeID, forKey: "ra_currentModeID") }
    }
    /// Dates ("YYYY-MM-DD") whose Challenge of the Day the player has cleared.
    @Published var dailyChallengeCompletions: Set<String> {
        didSet { saveStringSet(dailyChallengeCompletions, forKey: "ra_dailyChallengeDone") }
    }
    /// Dates ("YYYY-MM-DD") whose Challenge of the Day the player has *failed*
    /// (ran out of attempts).  Like completions, this locks the day — there's
    /// one shot at the CotD per calendar day, win or lose.
    @Published var dailyChallengeFailures: Set<String> {
        didSet { saveStringSet(dailyChallengeFailures, forKey: "ra_dailyChallengeFailed") }
    }
    /// Which sub-level (0-based) of today's Challenge the player is on.  Session
    /// state — reset by `startDailyChallenge()` when the challenge is launched.
    @Published var dailyChallengeIndex: Int = 0
    /// Attempts remaining on the current sub-level of today's Challenge.  The
    /// CotD never spends real lives — each sub-level grants a fixed number of
    /// free attempts (`dailyChallengeAttemptsPerLevel`); exhausting them fails
    /// the day.  Session state — reset on launch and on advancing a sub-level.
    @Published var dailyChallengeAttemptsLeft: Int = GameState.dailyChallengeAttemptsPerLevel
    /// Free attempts granted per Challenge-of-the-Day sub-level.
    static let dailyChallengeAttemptsPerLevel = 3
    /// The day-key of a Challenge-of-the-Day run that is currently in progress,
    /// or nil when no run is active.  Persisted so that quitting mid-run — via
    /// the home button or by killing the app — forfeits the day rather than
    /// handing out a fresh set of attempts.  Cleared on completion/failure and
    /// reconciled on the next home appearance (see `forfeitDailyChallengeIfRunning`).
    @Published var dailyChallengeRunStartedKey: String? {
        didSet {
            if let k = dailyChallengeRunStartedKey {
                defaults.set(k, forKey: "ra_dailyChallengeRunStarted")
            } else {
                defaults.removeObject(forKey: "ra_dailyChallengeRunStarted")
            }
        }
    }

    // ── Challenge Track active session (transient — not persisted) ──────────
    //
    // Set by `startTrack(_:)` when the player taps Play on a track level.
    // Read by BallGameView to choose the right LevelLayout and to record
    // progress when a level is cleared.

    /// The track currently being played, or nil when in the main climb.
    @Published var activeTrackID: String? = nil

    /// The level number (1–100) being played within the active track.
    @Published var activeTrackLevel: Int = 1

    /// Configure the active track session and set `activeTrackLevel` to
    /// the next un-cleared level (or 100 if the track is already complete).
    func startTrack(_ trackID: String) {
        activeTrackID    = trackID
        let cleared      = trackProgress[trackID] ?? 0
        activeTrackLevel = min(100, cleared + 1)
    }

    /// Begin playing a specific level within the active track (used by the
    /// level-grid in ChallengeTrackView to let the player replay any level).
    func startTrack(_ trackID: String, atLevel level: Int) {
        activeTrackID    = trackID
        activeTrackLevel = max(1, min(100, level))
    }

    /// Called by BallGameView on a track level clear.  Advances
    /// `activeTrackLevel` to the next level and records progress.
    /// Returns true when the track was just completed (level 100 cleared).
    @discardableResult
    func advanceTrackLevel() -> Bool {
        guard let trackID = activeTrackID else { return false }
        let cleared = activeTrackLevel
        advanceTrackProgress(trackID: trackID, to: cleared)
        let justCompleted = cleared == 100
        if !justCompleted { activeTrackLevel = cleared + 1 }
        return justCompleted
    }

    // Currently-equipped cosmetic per category.  Always defaults to the
    // starter on a fresh install.
    @Published var equippedGoal: GoalSkin {
        didSet {
            defaults.set(equippedGoal.rawValue, forKey: "ra_equippedGoal")
            recordFullKitTrophy()   // cosmetic_full_kit (S1-T5)
        }
    }
    @Published var equippedTrail: TrailColor {
        didSet {
            defaults.set(equippedTrail.rawValue, forKey: "ra_equippedTrail")
            recordFullKitTrophy()
        }
    }
    @Published var equippedFloor: Floor {
        didSet {
            defaults.set(equippedFloor.rawValue, forKey: "ra_equippedFloor")
            recordFullKitTrophy()
        }
    }
    @Published var equippedPit: Pit {
        didSet {
            defaults.set(equippedPit.rawValue, forKey: "ra_equippedPit")
            recordFullKitTrophy()
        }
    }
    @Published var equippedBoundary: Boundary {
        didSet {
            defaults.set(equippedBoundary.rawValue, forKey: "ra_equippedBoundary")
            recordFullKitTrophy()
        }
    }
    @Published var equippedMusic: MusicTrack {
        didSet {
            defaults.set(equippedMusic.rawValue, forKey: "ra_equippedMusic")
            recordFullKitTrophy()
        }
    }
    // equippedBall lives on `activeSkin` — already defined above.  Its
    // cosmetic_full_kit check rides `equipBall`/`equipPack` (real ball-slot
    // equips), NOT the raw `activeSkin` didSet — `advancePackSkin` mutates
    // `activeSkin` every attempt (shuffle), which must stay off the hot path.

    /// The currently-equipped Ball Pack, or nil when an individual ball
    /// skin is equipped.  When non-nil, `activeSkin` is driven by the
    /// pack's shuffle (see `advancePackSkin()`) and is overwritten at the
    /// start of every attempt.
    @Published var equippedPackID: String? {
        didSet {
            if let id = equippedPackID {
                defaults.set(id, forKey: "ra_equippedPack")
            } else {
                defaults.removeObject(forKey: "ra_equippedPack")
            }
        }
    }
    /// In-memory no-repeat shuffle bag for the equipped pack.  Drained one
    /// skin per attempt; refilled (re-shuffled) when empty.  Not persisted
    /// — a fresh launch simply re-shuffles.
    private var packBag: [BallSkin] = []

    // MARK: - Initialisation

    /// Loads all persisted state from UserDefaults.
    ///
    /// **Defensive loads** — every load is guarded so a corrupt or missing
    /// UserDefaults store never crashes the app:
    ///   • `integer(forKey:)` returns 0 for missing/wrong-type keys — clamped to safe ranges.
    ///   • `object(forKey:) as? T` returns nil for wrong-type keys — nil-coalesced to defaults.
    ///   • JSON-backed dicts use `try?` so a bad blob returns `[:]`.
    /// The persistence store.  Production uses `.standard`; tests inject a
    /// throwaway suite so they never read or scribble on the real save.
    private let defaults: UserDefaults

    /// Latched trophy stat counters (S0-T2) — bumped ONLY from this class's
    /// funnels (`addCoins`, `claimDailyReward`, `recordResult`,
    /// `consumeLife`), persisted on the same injected defaults.  A plain
    /// `let` on purpose: trophy stat writes must never publish GameState
    /// changes or re-render gameplay views.
    let trophyStats: TrophyStats

    /// The latched trophy engine (S0-T3), owned here so S1 trigger funnels
    /// can drive `record(_:value:)` from real gameplay hooks (S1-T1 is the
    /// first task to establish this wiring point).  Deliberately its OWN
    /// `ObservableObject` on a plain `let` — NOT `@Published` on GameState —
    /// so gameplay views observing GameState never re-render on a trophy
    /// write (S0-T3 rationale; §5 regression table).  Persists to the same
    /// injected `defaults` as everything else.
    ///
    /// The one-time first-launch backfill (S0-T4) is NOT run in `init` — a
    /// bare `GameState(defaults:)` must never touch the trophy ledger (the
    /// migration tests build one and expect it inert).  Production calls
    /// `activateTrophies()` once at launch; the harness's `backfill:` flag
    /// does the same in tests.
    let trophyEngine: TrophyEngine

    /// The run-aware trophy-toast presentation queue (S2-T1), owned here so
    /// the S1 trigger funnels can feed newly-unlocked trophies into it via
    /// `fireTrophy(_:value:)` and the run-end result surfaces (S2-T2) can
    /// drain it.  Deliberately a plain `let` on its OWN `ObservableObject`
    /// (like `trophyEngine`) so a trophy unlock never re-renders a gameplay
    /// view observing GameState.
    ///
    /// Presentation policy lives entirely in the queue: unlocks recorded
    /// while a run is active only accumulate and coalesce; they surface as
    /// one batched banner the moment a result overlay calls `runDidEnd()`
    /// (design.md §6 "coalesced at run end · never mid-run").  DISPLAY-ONLY:
    /// nothing here grants coins (D1 never-mint).  The one-time retroactive
    /// backfill (`activateTrophies` → `trophyEngine.backfill`) deliberately
    /// does NOT flow through `fireTrophy`, so grandfathered unlocks never
    /// toast — S2-T6 owns that single coalesced "Trophy Room opens" reveal.
    let trophyToasts: TrophyToastQueue

    /// The Platinum capstone's full-screen, one-time celebration state (S2-T5).
    /// Owned here on its OWN `ObservableObject` (like `trophyToasts`) so it
    /// never re-renders a gameplay view.  When a live bump latches the capstone
    /// (`capstone_all`), `fireTrophy` SPLITS it off the small-toast feed and
    /// arms this instead — the capstone escalates to a full-screen blowout
    /// exactly once ever (latched against the engine's unlock state AND a
    /// durable `ra_trophyCapstonePresented` flag), while standard unlocks stay
    /// small (design.md §6; sprint-plan.md §2 S2-T5).  Backfill bypasses this
    /// too: a grandfathered capstone never blows up — S2-T6's reveal owns it.
    let capstoneCelebration: CapstoneCelebrationModel

    /// The one-time retroactive-grant reveal state (S2-T6).  Owned here on its
    /// OWN `ObservableObject` (like `trophyToasts`/`capstoneCelebration`) so it
    /// never re-renders a gameplay view.  A veteran opening the trophy update
    /// qualifies for many trophies at once via the S0-T4 backfill; those
    /// grandfathered unlocks bypass the small-toast feed entirely, and this
    /// model owns the single coalesced "Trophy Room unlocked — you've already
    /// earned N" moment they get instead (design.md §6 anti-spam batching).
    /// Armed from `activateTrophies()` — the same launch call that runs the
    /// backfill — and latched against a durable `ra_trophyRevealPresented` flag
    /// so a relaunch never re-offers it.  DISPLAY-ONLY (D1 never-mint).
    let trophyReveal: TrophyRevealModel

    /// The player's pinned-trophy store (S2-T7).  Owned here on its OWN
    /// `ObservableObject` (like `trophyToasts`) so a pin toggle never
    /// re-renders a gameplay view observing GameState.  It holds an ordered,
    /// de-duplicated list of up to 3 pinned trophy ids in `ra_trophyPins`;
    /// the Trophy Room writes it (`toggle`), and the "what am I chasing?"
    /// chase chips + the Profile showcase READ its `pinnedIDs`.  Structural
    /// rules (cap / order / dedup / persistence) live entirely in the store,
    /// so they are unit-testable without a View.  DISPLAY-ONLY (D1 never-mint).
    let trophyPins: TrophyPinStore

    /// Test-injectable clock so live-unlock timestamps are deterministic
    /// (mirrors the engine's `now`).  Production uses the real wall clock.
    private let now: () -> Date

    init(defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        trophyStats = TrophyStats(defaults: defaults)
        // Load the bundled 90-trophy catalog.  A decode/validation failure is
        // a build-breaking AUTHORING error, never a runtime condition to
        // recover from (TrophyCatalog house rules) — but GameState.init must
        // never trap, so fall back to an empty catalog whose engine simply
        // has nothing to evaluate.  In every shipping build and test host the
        // bundled resource loads, so the fallback is unreachable in practice.
        let catalog = (try? TrophyCatalog.load(bundle: .main))
            ?? TrophyCatalog.empty
        trophyEngine = TrophyEngine(catalog: catalog, defaults: defaults, now: now)
        // The toast queue starts idle (no run active); the first `spawnBall`
        // arms it via `beginTrophyRun()`.  A plain `TrophyToastQueue()` does
        // no main-actor work in its initialiser, so constructing it here is
        // safe from GameState's initialiser.
        trophyToasts = TrophyToastQueue()
        // The capstone moment starts from its persisted "already played" flag,
        // so a relaunch after the blowout never replays it (S2-T5 latch).
        capstoneCelebration = CapstoneCelebrationModel(defaults: defaults)
        // The retro-grant reveal starts from its persisted "already offered"
        // flag, so a relaunch after the veteran summary never re-offers it
        // (S2-T6 latch).  It arms only once `activateTrophies()` runs the
        // backfill and finds it granted trophies.
        trophyReveal = TrophyRevealModel(defaults: defaults)
        // The pin store loads its persisted `ra_trophyPins` list (sanitized
        // to the cap + deduped); a bare GameState(defaults:) constructs it
        // inert, reading only.  Completed/stale pins are pruned later, once
        // `activateTrophies()` has run the ledger (see below).
        trophyPins = TrophyPinStore(defaults: defaults)
        let saved = defaults.integer(forKey: "ra_level")
        let level = max(1, saved)
        currentLevel = level
        activeSkin = BallSkin(rawValue: defaults.string(forKey: "ra_skin") ?? "") ?? .red
        // Nicknames are preset-built only (see `PresetNames`).  A free-text
        // name saved by an earlier build is dropped, so it is never shown or
        // sent; the player picks a new one in Settings.
        let savedName = defaults.string(forKey: "ra_name") ?? ""
        // A name from the earlier format with a number keeps its two words.
        playerName = PresetNames.shownNickname(savedName)
        primaryColorHex = defaults.string(forKey: "ra_primaryColorHex") ?? Self.defaultPrimaryHex
        hapticsEnabled = defaults.object(forKey: "ra_haptics") as? Bool ?? true
        soundEnabled = defaults.object(forKey: "ra_sound") as? Bool ?? true
        introEnabled = defaults.object(forKey: "ra_introEnabled") as? Bool ?? false
        ballStartsAtTop = defaults.object(forKey: "ra_startAtTop") as? Bool ?? true
        tapToStart = defaults.object(forKey: "ra_tapToStart") as? Bool ?? true
        shopFreshNotifEnabled = defaults.object(forKey: "ra_notifShopFresh") as? Bool ?? false
        livesFullNotifEnabled = defaults.object(forKey: "ra_notifLivesFull") as? Bool ?? false
        // Public trophy showcase — DEFAULT ON (design.md §7 / D6).
        trophyShowcaseEnabled = defaults.object(forKey: "ra_trophyShowcaseEnabled") as? Bool ?? true
        minigameDifficulty = MinigameDifficulty(
            rawValue: defaults.string(forKey: "ra_minigameDifficulty") ?? "") ?? .normal
        seenOnboarding = defaults.bool(forKey: "ra_seenOnboarding")
        seenWelcomeMoment = defaults.bool(forKey: "ra_seenWelcomeMoment")
        seenTutorialReward = defaults.bool(forKey: "ra_seenTutorialReward")

        bestStars       = Self.loadIntValueDict(key: "ra_bestStars", defaults)
        bestTime        = Self.loadDoubleValueDict(key: "ra_bestTime", defaults)
        collectedCoins  = Self.loadSetDict(key: "ra_collectedCoins", defaults)
        let unlocked    = defaults.integer(forKey: "ra_highestUnlocked")
        highestUnlocked = max(level, max(1, unlocked))  // never less than currentLevel

        // Lives — default to a full bar.  `as? Int ?? Self.livesMax` covers
        // the case where no key has been written yet (fresh install).
        // `max(0, ...)` guards against a corrupt negative value.
        // Migration: pre-reserve saves stockpiled purchased lives inside
        // `ra_lives` (values above the 10 cap) — move the overflow into the
        // reserve queue.  didSet doesn't fire during init, so persist the
        // split explicitly.
        let storedLives   = max(0, defaults.object(forKey: "ra_lives") as? Int ?? Self.livesMax)
        let storedReserve = max(0, defaults.object(forKey: "ra_purchasedLives") as? Int ?? 0)
        lives          = min(storedLives, Self.livesMax)
        purchasedLives = storedReserve + max(0, storedLives - Self.livesMax)
        if storedLives > Self.livesMax {
            defaults.set(min(storedLives, Self.livesMax), forKey: "ra_lives")
            defaults.set(storedReserve + storedLives - Self.livesMax, forKey: "ra_purchasedLives")
        }
        lastLifeLostAt = defaults.object(forKey: "ra_lastLifeLostAt") as? Date
        unlimitedLives = defaults.bool(forKey: "ra_unlimitedLives")

        // Daily reward / login streak.
        dailyStreak    = defaults.integer(forKey: "ra_dailyStreak")
        lastDailyClaim = defaults.object(forKey: "ra_lastDailyClaim") as? Date

        // Starter Pack offer state.
        starterPackShownAt   = defaults.object(forKey: "ra_starterPackShownAt") as? Date
        starterPackClaimed   = defaults.bool(forKey: "ra_starterPackClaimed")
        starterPackDismissed = defaults.bool(forKey: "ra_starterPackDismissed")

        // Ratings prompt.
        lastReviewPromptDate = defaults.object(forKey: "ra_lastReviewPromptDate") as? Date

        // Cosmetic economy — load owned-sets to local lets first, then
        // assign to the stored properties.  We re-use the locals when
        // computing the equipped cosmetics below; referring to
        // `self.ownedGoals` directly would be a "self used before all
        // stored properties initialised" error here.
        // Clamp both sides: floor of 0, ceiling of maxCoinBalance.
        // A corrupted save with a huge value is silently reset rather than
        // displaying an absurd balance.
        coinBalance = min(max(0, defaults.integer(forKey: "ra_coinBalance")),
                          Self.maxCoinBalance)
        pinballBest  = max(0, defaults.integer(forKey: "ra_pinballBest"))
        zenSeconds   = max(0, defaults.integer(forKey: "ra_zenSeconds"))
        goldrushBest = max(0, defaults.integer(forKey: "ra_goldrushBest"))
        rollupBestSeconds = max(0, defaults.integer(forKey: "ra_rollupBestSeconds"))
        // Per-difficulty Disco Ball average times.  Bests set before times
        // were recorded have none (shown as "—").
        discoBestAvgMs = Self.loadTrackProgress(key: "ra_discoBestAvgMs", defaults)
        goldrushCoinsTotal = max(0, defaults.integer(forKey: "ra_goldrushCoinsTotal"))
        tickets = min(max(0, defaults.integer(forKey: "ra_tickets")),
                      Self.maxTicketBalance)
        let loadedOwnedBalls   = Self.loadStringSet(forKey: "ra_ownedBallSkins", defaults)
        let loadedOwnedGoals   = Self.loadStringSet(forKey: "ra_ownedGoals", defaults)
        let loadedOwnedTrails  = Self.loadStringSet(forKey: "ra_ownedTrails", defaults)
        let loadedOwnedFloors  = Self.loadStringSet(forKey: "ra_ownedFloors", defaults)
        let loadedOwnedPits    = Self.loadStringSet(forKey: "ra_ownedPits", defaults)
        let loadedOwnedBoundaries = Self.loadStringSet(forKey: "ra_ownedBoundaries", defaults)
        let loadedOwnedMusic   = Self.loadStringSet(forKey: "ra_ownedMusic", defaults)
        let loadedOwnedBundles = Self.loadStringSet(forKey: "ra_ownedBundles", defaults)
        let loadedOwnedPacks   = Self.loadStringSet(forKey: "ra_ownedPacks", defaults)
        ownedBallSkins = loadedOwnedBalls
        ownedGoals     = loadedOwnedGoals
        ownedTrails    = loadedOwnedTrails
        ownedFloors    = loadedOwnedFloors
        ownedPits      = loadedOwnedPits
        ownedBoundaries = loadedOwnedBoundaries
        ownedMusic     = loadedOwnedMusic
        ownedBundles   = loadedOwnedBundles
        ownedPacks     = loadedOwnedPacks
        freeGrantedItems = Self.loadStringSet(forKey: "ra_freeGrantedItems", defaults)
        paidPrices = Self.loadTrackProgress(key: "ra_paidPrices", defaults)
        trackProgress  = Self.loadTrackProgress(key: "ra_trackProgress", defaults)
        minigameWins   = Self.loadTrackProgress(key: "ra_minigameWins", defaults)
        minigameBests  = Self.loadTrackProgress(key: "ra_minigameBests", defaults)
        minigameDifficultyPlays = Self.loadTrackProgress(key: "ra_minigameDiffPlays", defaults)
        minigameDifficultyWins  = Self.loadTrackProgress(key: "ra_minigameDiffWins", defaults)
        minigameDifficultyBests = Self.loadTrackProgress(key: "ra_minigameDiffBests", defaults)
        completedTracks = Self.loadStringSet(forKey: "ra_completedTracks", defaults)
        playedModeIDs = Self.loadStringSet(forKey: "ra_playedModeIDs", defaults)
        // A saved "last mode" that no longer exists in this build (e.g. Pinball,
        // held back from v1.0) falls back to the climb.
        let savedModeID = defaults.string(forKey: "ra_currentModeID") ?? "climb"
        currentModeID = GameModeCatalogue.mode(id: savedModeID) != nil ? savedModeID : "climb"
        dailyChallengeCompletions = Self.loadStringSet(forKey: "ra_dailyChallengeDone", defaults)
        dailyChallengeFailures    = Self.loadStringSet(forKey: "ra_dailyChallengeFailed", defaults)
        dailyChallengeRunStartedKey = defaults.string(forKey: "ra_dailyChallengeRunStarted")
        // Equipped cosmetics — load saved raw values, fall back to the
        // category's starter if the loaded item is non-starter and not
        // in the owned set.  Floor + Pit replaced the legacy
        // `BackgroundTheme` (any saved ra_equippedBackground value is
        // simply discarded — Mac requested reset-to-defaults for the
        // single existing tester).
        let savedGoal  = GoalSkin(rawValue:   defaults.string(forKey: "ra_equippedGoal")  ?? "")
        let savedTrail = TrailColor(rawValue: defaults.string(forKey: "ra_equippedTrail") ?? "")
        let savedFloor = Floor(rawValue:      defaults.string(forKey: "ra_equippedFloor") ?? "")
        let savedPit   = Pit(rawValue:        defaults.string(forKey: "ra_equippedPit")   ?? "")
        let savedBoundary = Boundary(rawValue: defaults.string(forKey: "ra_equippedBoundary") ?? "")
        let savedMusic = MusicTrack(rawValue: defaults.string(forKey: "ra_equippedMusic") ?? "")
        equippedGoal  = Self.legitimise(savedGoal,  owned: loadedOwnedGoals,  starter: GoalSkin.starter)
        equippedTrail = Self.legitimise(savedTrail, owned: loadedOwnedTrails, starter: TrailColor.starter)
        equippedFloor = Self.legitimise(savedFloor, owned: loadedOwnedFloors, starter: Floor.starter)
        equippedPit   = Self.legitimise(savedPit,   owned: loadedOwnedPits,   starter: Pit.starter)
        equippedBoundary = Self.legitimise(savedBoundary, owned: loadedOwnedBoundaries, starter: Boundary.starter)
        equippedMusic = Self.legitimise(savedMusic, owned: loadedOwnedMusic,  starter: MusicTrack.starter)

        // Restore the equipped Ball Pack only if it's still owned;
        // otherwise leave it nil so the individual `activeSkin` (loaded
        // above) stays in effect.
        let savedPack  = defaults.string(forKey: "ra_equippedPack")
        equippedPackID = savedPack.flatMap { loadedOwnedPacks.contains($0) ? $0 : nil }

        // Comet Clash became Snacky under the same id ("snake").  This runs
        // LAST in init, after every stored property has a value (it reads and
        // writes `minigameBests` / `minigameDifficultyBests`).  Its old bests
        // measured something else (sparks and knockouts, not orbs eaten), so
        // they are cleared once; wins are kept (a win still means last one
        // left).  Not through didSet (init), so save explicitly.
        if !defaults.bool(forKey: "ra_snackyBestsReset_v1") {
            minigameBests["snake"] = nil
            for key in minigameDifficultyBests.keys where key.hasPrefix("snake|") {
                minigameDifficultyBests[key] = nil
            }
            defaults.set(try? JSONEncoder().encode(minigameBests), forKey: "ra_minigameBests")
            defaults.set(try? JSONEncoder().encode(minigameDifficultyBests), forKey: "ra_minigameDiffBests")
            defaults.set(true, forKey: "ra_snackyBestsReset_v1")
        }

        // Free gifts used to be keyed by bare rawValue, which confused
        // same-named items in different slots.  Qualify old entries once to
        // unique ids (see `qualifyFreeGrants`).  Runs after every stored
        // property is set; not through didSet (init), so save explicitly.
        if freeGrantedItems.contains(where: { !$0.contains(":") }) {
            freeGrantedItems = Self.qualifyFreeGrants(
                freeGrantedItems,
                balls: ownedBallSkins, goals: ownedGoals, trails: ownedTrails,
                floors: ownedFloors, pits: ownedPits, boundaries: ownedBoundaries,
                music: ownedMusic)
            defaults.set(Array(freeGrantedItems), forKey: "ra_freeGrantedItems")
        }
    }

    // MARK: - Trophy activation (first-launch backfill)

    /// Run the one-time first-launch trophy backfill (S0-T4): evaluate the
    /// full catalog against this save's existing stats and grant every
    /// derivable trophy with a legacy timestamp.  Idempotent across
    /// relaunches — the engine short-circuits once its backfill-done flag is
    /// set, so calling this on every launch is safe (and cheap after the
    /// first).  Call once at app startup, BEFORE live play, so a veteran's
    /// history is grandfathered rather than live-unlocked one clear at a time.
    ///
    /// Deliberately NOT called from `init` — a bare `GameState(defaults:)`
    /// must leave the trophy ledger untouched (the migration/engine unit
    /// tests build one and assert inertness).  Returns the trophies newly
    /// granted by this call (empty after the first run).
    ///
    /// After the backfill, arm the S2-T6 retro-grant reveal: if this save's
    /// history grandfathered any trophies, the `TrophyRevealModel` offers ONE
    /// coalesced "Trophy Room unlocked — you've already earned N" banner on the
    /// Home surface — never a toast cascade (design.md §6).  The reveal is
    /// latched once-ever against its own durable flag, so calling this on every
    /// launch (as production does) re-checks harmlessly: after the first offer
    /// it never re-arms, and a relaunch — where `didBackfill`/`backfillGrantCount`
    /// still read true/N (the historical fact) — shows nothing.  The grandfathered
    /// unlocks themselves never flow through `fireTrophy`, so they never toast.
    @discardableResult
    func activateTrophies() -> [TrophyDefinition] {
        let granted = trophyEngine.backfill(from: TrophyBackfill.snapshot(from: self))
        // Reads the engine's persisted backfill counters — safe on every launch,
        // even the ones where `backfill` short-circuited (didBackfill already
        // set): the reveal's own latch decides whether anything is owed.
        trophyReveal.revealIfOwed(engine: trophyEngine)
        // Drop any pin that is now earned or no longer in the catalog (S2-T7):
        // a backfill may have grandfathered a chased trophy, and the ledger is
        // authoritative at launch.  Cheap and order-preserving; persists only
        // on an actual change.
        trophyPins.pruneCompleted(using: trophyEngine)
        return granted
    }

    // MARK: - Trophy toast feed + run lifecycle (S2-T2)

    /// The single funnel every LIVE trophy trigger routes through: records
    /// `metric`'s current value on the engine and hands any newly-unlocked
    /// trophies to the toast queue.  The queue itself decides WHEN they
    /// surface — held + coalesced while a run is active, presented at run end
    /// (design.md §6).  A no-unlock bump (the overwhelmingly common path)
    /// adds only an empty-array guard over the bare `record` call.
    ///
    /// NEVER-MINT (D1): this only reads the ledger and enqueues a banner; it
    /// grants nothing.  Backfill (`activateTrophies`) bypasses this on
    /// purpose so grandfathered unlocks don't toast (S2-T6 owns their
    /// reveal).
    @discardableResult
    private func fireTrophy(_ metric: TrophyMetric, value: Int) -> [TrophyDefinition] {
        let unlocked = trophyEngine.record(metric, value: value)
        routeUnlockedToPresentation(unlocked)
        return unlocked
    }

    /// Double overload — a handful of metrics record fractional bests.
    @discardableResult
    private func fireTrophy(_ metric: TrophyMetric, value: Double) -> [TrophyDefinition] {
        let unlocked = trophyEngine.record(metric, value: value)
        routeUnlockedToPresentation(unlocked)
        return unlocked
    }

    /// Route a bump's newly-unlocked trophies to the right presentation
    /// surface: the Platinum capstone (`capstone_all`) escalates to its
    /// full-screen ONE-TIME blowout (`capstoneCelebration`), every other grade
    /// coalesces into the small run-end banner (`trophyToasts`).  "Escalate
    /// exactly once — standard unlocks stay small" is enforced here by SPLITTING
    /// the capstone out of the banner feed, and again in the model's latch
    /// (S2-T5; design.md §6).  Display-only — grants nothing (D1 never-mint).
    private func routeUnlockedToPresentation(_ unlocked: [TrophyDefinition]) {
        guard !unlocked.isEmpty else { return }
        // Beta-hunter funnel telemetry (S4-T4): emit one fire-and-forget
        // `trophy_unlocked` analytics event per LIVE unlock so a TestFlight beta
        // yields an unlock funnel (which tiers land, which never do).  Observer
        // ONLY — this reads the just-latched ledger and is downstream of the
        // engine, so it can NEVER be a trigger source (§4 addenda: analytics is
        // fire-and-forget, never the source of truth for an unlock).  Fires here,
        // not in the engine, so it stays off the hot path and out of the pure
        // ledger; backfill's grandfathered grants bypass this funnel by design,
        // so they never inflate the live-unlock funnel.
        emitTrophyUnlockAnalytics(unlocked)
        let capstoneID = CapstoneCelebrationModel.capstoneID
        let standard = unlocked.filter { $0.id != capstoneID }
        if !standard.isEmpty { trophyToasts.enqueue(standard) }
        if unlocked.contains(where: { $0.id == capstoneID }) {
            // Latched twice over: only arms if the engine truly holds the
            // capstone AND the once-ever flag is unset.
            capstoneCelebration.celebrateIfEarned(engine: trophyEngine)
        }
        // A pinned trophy that just unlocked is no longer a chase — drop it so
        // its chip retires (S2-T7).  No-op unless a pin was among the unlocks.
        if unlocked.contains(where: { trophyPins.isPinned($0.id) }) {
            trophyPins.pruneCompleted(using: trophyEngine)
        }
    }

    /// Fire one `trophy_unlocked` analytics event per newly-latched trophy
    /// (S4-T4 beta funnel).  Carries the stable trophy `id` + `tier` grade only
    /// — NO PII, no coin/stat payload — so the beta funnel can segment unlock
    /// volume by grade without leaking anything the not-linked analytics envelope
    /// doesn't already carry (`AnalyticsClient` is anonymous per-install).  Pure
    /// side effect: buffered, batched, best-effort; a failed POST is silently
    /// dropped and NEVER blocks or gates the unlock (which already latched
    /// durably in the engine before this runs).
    private func emitTrophyUnlockAnalytics(_ unlocked: [TrophyDefinition]) {
        for trophy in unlocked {
            let event = Self.trophyUnlockEvent(for: trophy)
            AnalyticsClient.shared.track(event.name, properties: event.properties)
        }
    }

    /// Pure builder for the `trophy_unlocked` event — event name + the exact
    /// property payload (`trophy_id` + `tier`, and nothing else).  Split out so
    /// the funnel's wire shape (name, keys, NO-PII contract) is unit-testable
    /// without the `AnalyticsClient` singleton or the network.  `payload` returns
    /// plain strings for assertion; the `properties` accessor wraps them for the
    /// tracker.
    static func trophyUnlockEvent(
        for trophy: TrophyDefinition
    ) -> (name: String, payload: [String: String], properties: [String: AnyEncodable]) {
        let payload: [String: String] = [
            "trophy_id": trophy.id,
            "tier":      trophy.tier.rawValue,
        ]
        let properties = payload.mapValues { AnyEncodable.string($0) }
        return ("trophy_unlocked", payload, properties)
    }

    /// Mark the start of a tilt run.  From here until `endTrophyRun()` the
    /// toast queue only accumulates — it never presents mid-run (design.md
    /// §6; a banner over a live tilt run is a death sentence, f2p §7.10).
    /// Idempotent — a Replay/respawn re-arms without double-counting.
    func beginTrophyRun() {
        trophyToasts.runDidStart()
    }

    /// Mark the end of a tilt run.  Called from every terminal result
    /// overlay's appearance (climb win / oops / out-of-lives, each minigame
    /// game-over, the Coin Pit payout) and on GameMenuView return — it flushes
    /// everything the run accumulated as ONE coalesced banner.  Safe to call
    /// when no run was active (it simply presents anything already pending).
    func endTrophyRun() {
        trophyToasts.runDidEnd()
    }

    /// Returns `item` if the player actually owns it (starter tier or
    /// present in the owned-set), otherwise the category's starter.
    /// Used at init time to recover from tier shuffles that would
    /// otherwise leave a previously-equipped item in a "not owned"
    /// state.
    private static func legitimise<Item: CosmeticItem>(
        _ item: Item?, owned: Set<String>, starter: Item
    ) -> Item {
        guard let item else { return starter }
        if item.tier == .starter { return item }
        return owned.contains(item.rawValue) ? item : starter
    }

    // MARK: - Level progression

    func advanceLevel() {
        currentLevel += 1
        if currentLevel > highestUnlocked {
            highestUnlocked = currentLevel
        }
        syncSocialProgress()
        // Climb level trophies key on `highestUnlocked` (S1-T1;
        // climb_first_clear … climb_summit).  Mode-gated: only the main
        // climb advances its unlock ladder — CotD and tracks never reach
        // this funnel (advanceFromLevelClear routes them away), and the
        // guard is defense-in-depth against a future mode that does.
        if playedMode.progression.recordsClimbResult {
            fireTrophy(.climbHighestUnlocked, value: highestUnlocked)
        }
    }

    /// Push the player's headline progression to the social backend, if and
    /// only if they're signed in.  Fire-and-forget: a failed/paused server
    /// must never block or slow local gameplay.  `climb_level` — the number
    /// shown next to the player's name on leaderboards/clans — is the highest
    /// level reached (`highestUnlocked`).  No-op when signed out, so this is
    /// inert until the Sign-in-with-Apple flow installs a session.
    private func syncSocialProgress() {
        guard SocialClient.shared.isSignedIn else { return }
        let climb = highestUnlocked
        let unlocked = highestUnlocked
        let stars = totalStars
        let coins = totalCoins
        Task {
            try? await SocialClient.shared.syncProgress(
                climbLevel: climb,
                highestUnlocked: unlocked,
                totalStars: stars,
                coinsCollected: coins
            )
        }
    }

    /// Reset level-progress only — clears stars/coins/times/unlocks.  Skin,
    /// name, settings, and one-time moments (onboarding/welcome) are kept.
    func resetProgress() {
        currentLevel    = 1
        bestStars       = [:]
        bestTime        = [:]
        collectedCoins  = [:]
        highestUnlocked = 1
    }

    // MARK: - Cosmetic liquidation ("Reset Cosmetics")

    /// Namespaced `paidPrices` key — bare rawValues collide across cosmetic
    /// categories (five different items are named "aurora").
    static func paidPriceKey<Item: CosmeticItem>(_ item: Item) -> String {
        "\(Item.self):\(item.rawValue)"
    }

    /// A cosmetic's unique id across every slot ("<Type>:<rawValue>") — the
    /// key for `freeGrantedItems` (and, as `paidPriceKey`, for `paidPrices`).
    static func cosmeticKey<Item: CosmeticItem>(_ item: Item) -> String {
        paidPriceKey(item)
    }

    /// True if `item` was a free gift (never refunded by Sell Back).
    func isFreeGranted<Item: CosmeticItem>(_ item: Item) -> Bool {
        freeGrantedItems.contains(Self.cosmeticKey(item))
    }

    /// Mark `items` as free gifts, each by its unique id.
    func markFreeGranted<Item: CosmeticItem>(_ items: [Item]) {
        freeGrantedItems.formUnion(items.map { Self.cosmeticKey($0) })
    }

    /// One-time upgrade of a save's free-gift set from bare rawValues (the old
    /// format) to unique ids.  A bare name can't say which slot it meant, so it
    /// is expanded CONSERVATIVELY to every slot whose item has that name AND is
    /// owned: a same-named item the player had paid for may become unsellable,
    /// but a gift can never become sellable (which would mint coins).  Bare
    /// names that match nothing owned are dropped (nothing left to protect).
    /// Entries already in the new format pass through unchanged.
    static func qualifyFreeGrants(_ old: Set<String>,
                                  balls: Set<String>, goals: Set<String>,
                                  trails: Set<String>, floors: Set<String>,
                                  pits: Set<String>, boundaries: Set<String>,
                                  music: Set<String>) -> Set<String> {
        var out = old.filter { $0.contains(":") }
        let bare = old.filter { !$0.contains(":") }
        guard !bare.isEmpty else { return out }
        func expand<Item: CosmeticItem>(_ type: Item.Type, _ owned: Set<String>) {
            for item in Item.allCases where bare.contains(item.rawValue) && owned.contains(item.rawValue) {
                out.insert(cosmeticKey(item))
            }
        }
        expand(BallSkin.self, balls);    expand(GoalSkin.self, goals)
        expand(TrailColor.self, trails); expand(Floor.self, floors)
        expand(Pit.self, pits);          expand(Boundary.self, boundaries)
        expand(MusicTrack.self, music)
        return out
    }

    /// What Sell Back pays for `item`: HALF its CURRENT `coinCost` (all tier
    /// prices are even, so the halving is exact — and the refund deliberately
    /// reads the live price, per Mac's calibration ruling), capped at the
    /// recorded price when the item was bought below cost (discounted featured
    /// bundle, Ball Pack).  The cap keeps discounts and future price bumps
    /// from becoming a mint: a refund can never exceed what was paid.
    func sellBackValue<Item: CosmeticItem>(_ item: Item) -> Int {
        min(item.coinCost / 2, paidPrices[Self.paidPriceKey(item)] ?? item.coinCost)
    }

    /// Dry run: how many owned cosmetics are sellable (coin-bought plus seasonal
    /// / limited-time specials), and the coins they'd refund — `sellBackValue`
    /// each: 50% of the CURRENT `coinCost`, capped at what was paid for
    /// below-cost buys.  Powers the Danger-Zone button label + confirm dialog.
    func coinLiquidationPreview() -> (count: Int, coins: Int) {
        var count = 0, coins = 0
        func tally<Item: CosmeticItem>(_ owned: Set<String>, _ type: Item.Type) {
            for item in Item.allCases where item.isSellable && !isFreeGranted(item) && owned.contains(item.rawValue) {
                count += 1; coins += sellBackValue(item)
            }
        }
        tally(ownedBallSkins, BallSkin.self); tally(ownedGoals, GoalSkin.self)
        tally(ownedTrails, TrailColor.self);  tally(ownedFloors, Floor.self)
        tally(ownedPits, Pit.self);           tally(ownedMusic, MusicTrack.self)
        tally(ownedBoundaries, Boundary.self)
        return (count, coins)
    }

    /// Relock every SELLABLE cosmetic and refund its `sellBackValue` (half the
    /// live price at sell time, never more than was paid) — coin-bought items
    /// plus seasonal / limited-time specials — KEEPING the starter look, the
    /// permanent Iconic specials (Trophy, Diamond, Money), and free-granted
    /// gifts (the tutorial bundle, the Starter Pack's Aurora items).
    /// Re-equips the starter for any slot whose item was liquidated.  Returns
    /// what was liquidated.  Level progress is untouched.
    @discardableResult
    func liquidateCoinCosmetics() -> (count: Int, coins: Int) {
        var count = 0, coins = 0
        func strip<Item: CosmeticItem>(_ owned: inout Set<String>, _ type: Item.Type) {
            for item in Item.allCases where item.isSellable && !isFreeGranted(item) && owned.contains(item.rawValue) {
                count += 1; coins += sellBackValue(item)
                owned.remove(item.rawValue)
                // Relocked — a future re-purchase pays its own price fresh.
                paidPrices.removeValue(forKey: Self.paidPriceKey(item))
            }
            owned.insert(Item.starter.rawValue)   // the starter is always owned
        }
        var balls = ownedBallSkins, goals = ownedGoals, trails = ownedTrails
        var floors = ownedFloors, pits = ownedPits, music = ownedMusic
        var boundaries = ownedBoundaries
        strip(&balls, BallSkin.self); strip(&goals, GoalSkin.self); strip(&trails, TrailColor.self)
        strip(&floors, Floor.self);   strip(&pits, Pit.self);       strip(&music, MusicTrack.self)
        strip(&boundaries, Boundary.self)
        ownedBallSkins = balls; ownedGoals = goals; ownedTrails = trails
        ownedFloors = floors; ownedPits = pits; ownedMusic = music
        ownedBoundaries = boundaries
        // Bundle/pack ownership is a UI badge only (items were owned individually
        // and handled above) — clear it and drop any equipped pack.
        ownedBundles = []; ownedPacks = []; equippedPackID = nil
        // Reset the WHOLE equipped loadout to the default starters — red ball, no
        // trail, etc. — regardless of whether each item was liquidated. Kept
        // items (Iconic specials, free-granted gifts, earned exclusives) stay
        // owned and can be re-equipped.
        activeSkin    = .starter
        equippedGoal  = .starter
        equippedTrail = .starter
        equippedFloor = .starter
        equippedPit   = .starter
        equippedBoundary = .starter
        equippedMusic = .starter
        // Refund, not income — Sell Back credits are recycled capital and
        // never count toward the play-earned trophy counter (§6 item 4).
        addCoins(coins, source: .refund)
        return (count, coins)
    }

    /// True when the equipped loadout is already the all-default starters (used
    /// to enable "Reset Cosmetics" whenever there's a look to reset, even if
    /// there are no coin cosmetics to refund).
    var isLoadoutDefault: Bool {
        activeSkin == .starter && equippedGoal == .starter && equippedTrail == .starter
            && equippedFloor == .starter && equippedPit == .starter
            && equippedBoundary == .starter
            && equippedMusic == .starter && equippedPackID == nil
    }

    // MARK: - Result recording

    /// Call when the player completes a level.  Stars only ever increase,
    /// times only ever decrease, collected coins never un-collect.
    ///
    /// The two S1-T7 run-lifecycle flags are facts only the run's owner
    /// (BallGameView) can supply — a run either kept a clean first attempt
    /// or picked up every coin, and neither survives into persisted state.
    /// The TROPHY decision stays here (in the funnel, never the view): both
    /// are climb-mode-gated below and combined with `noPriorClear`, which
    /// this funnel captures BEFORE the `bestTime` stamp so "first attempt"
    /// reads the pre-clear world (BallGameView no longer computes it post-#118).
    ///  • `firstAttemptClean` — this was the level's very first attempt with
    ///    no fall/restart before the goal (the view's transient armed flag).
    ///  • `pickupsThisRun` — currency coins banked in THIS run (already-banked
    ///    coins can't be re-picked, so this is the fresh-run pickup count).
    /// Default false/0 so the many non-view callers (tests) are unaffected;
    /// they simply never satisfy the run-flag trophies.
    func recordResult(level: Int, stars: Int, time: TimeInterval,
                      coinIndices: Set<Int>,
                      firstAttemptClean: Bool = false,
                      pickupsThisRun: Int = 0) {
        // Capture "no prior clear" BEFORE the bestTime stamp below — this is
        // the `time(for: level) == nil` derivation the catalog specifies for
        // `skill_first_try` (§6 item 7).  Once stamped it would always read
        // "cleared," so it must be read here first.
        let noPriorClear = bestTime[level] == nil
        var starsImproved = false
        if stars > (bestStars[level] ?? 0) {
            bestStars[level] = stars
            starsImproved = true
        }
        if let existing = bestTime[level] {
            if time < existing { bestTime[level] = time }
        } else {
            bestTime[level] = time
        }
        if !coinIndices.isEmpty {
            var set = collectedCoins[level] ?? []
            set.formUnion(coinIndices)
            collectedCoins[level] = set
        }
        if level >= highestUnlocked {
            highestUnlocked = level + 1
        }
        // Send the new star total right away (not only on the next level
        // advance), so stars earned by replaying a level reach the
        // leaderboards and clan totals promptly.  After the level and coin
        // updates above, so one message carries all three.
        if starsImproved { syncSocialProgress() }
        // Consecutive no-fall clear streak (§6 item 6): a goal-reached run
        // in this game either cleared or fell, so every recorded clear is a
        // fall-free run — the fall side already reset the streak at
        // `consumeLife`.  Mode-gated defense-in-depth: only the main climb
        // may grow the streak (the CotD `.oneShot` fast-path returns before
        // ever reaching this funnel; tracks never call it).
        if playedMode.progression.recordsClimbResult {
            trophyStats.recordNoFallClimbClear()
            recordClimbTrophies()
            recordRunLifecycleTrophies(stars: stars,
                                       noPriorClear: noPriorClear,
                                       firstAttemptClean: firstAttemptClean,
                                       pickupsThisRun: pickupsThisRun)
        }
    }

    /// Push the S1-T7 run-lifecycle Skill trophies (`skill_first_try`,
    /// `skill_spotless`) from a just-recorded climb clear.  Called ONLY inside
    /// `recordResult`'s `recordsClimbResult` gate, so CotD / Roll Out / Roll Up
    /// / track clears (which never reach this funnel) can't pollute them.  The
    /// engine latches once and never revokes, so a transient `1` on the run
    /// that qualifies is all that's needed — nothing is persisted here (no
    /// falls/failure counter; `firstTryAces` / `spotlessRuns` deliberately
    /// carry NO backfill source, so a live latch and a first-launch grandfather
    /// trivially agree — the grandfather grants neither, §7 backfill omit-list).
    private func recordRunLifecycleTrophies(stars: Int,
                                            noPriorClear: Bool,
                                            firstAttemptClean: Bool,
                                            pickupsThisRun: Int) {
        // skill_first_try — 3 stars on a level's very first attempt (no prior
        // clear AND no fall/restart before the goal, §6 item 7).
        if stars == 3, noPriorClear, firstAttemptClean {
            fireTrophy(.firstTryAces, value: 1)
        }
        // skill_spotless — 3 stars AND all 3 pickup coins banked in this one
        // run (§6 item 8).  Requires the full three: fewer-coin levels and
        // partial hauls never qualify.
        if stars == 3, pickupsThisRun >= 3 {
            fireTrophy(.spotlessRuns, value: 1)
        }
    }

    /// A climb pit-fall that never reaches `consumeLife` (S1-T7).  The view's
    /// fall path (`fireFell`) funnels every climb fall here so the two effects
    /// that `consumeLife` can't cover for tutorial levels (L1–10, which are
    /// lives-exempt and so never call `consumeLife`) are handled:
    ///  • `whimsy_gravity_check` — the one-shot latch for falling into the pit
    ///    on climb level 1 (§6 item 9; costs nothing, tutorial-exempt).
    ///  • the no-fall clear-streak reset — S1-T1 left the tutorial-fall reset
    ///    for this funnel (tutorial falls skip `consumeLife`).  `resetNoFall…`
    ///    is idempotent, so a non-tutorial fall (whose `consumeLife` already
    ///    reset the streak) makes this a harmless no-op.
    /// Mode-gated on `recordsClimbResult`: Roll Out / Roll Up / Coin Pit / Zen
    /// / CotD falls never reset the climb streak or fire the whimsy latch.
    func recordClimbFall(level: Int) {
        guard playedMode.progression.recordsClimbResult else { return }
        trophyStats.resetNoFallClearStreak()
        // whimsy_gravity_check keys to climb LEVEL 1 (a number, never a
        // layout) — level 1 is a fixed rung, not swappable content.
        if level == 1 {
            fireTrophy(.levelOneFalls, value: 1)
        }
    }

    /// A Coin Pit round has just been staked (S1-T7).  `tickets` is the count
    /// of time-tickets committed at round START — the view calls this only
    /// after `spendTickets` succeeds, so it never fires on a mid-round refund
    /// or an aborted stake.  `tickets` is the number of TICKETS staked on the
    /// round so far: 5 per 30-second block, plus 10 for the ×2 boost when it is
    /// bought.  `whimsy_high_roller` latches at ≥25 — five rounds' worth, the
    /// same as its original 5 tickets when a round cost 1.
    /// The engine keeps the best observed, so a later smaller stake never
    /// revokes.  Not mode-gated on `recordsClimbResult` (Coin Pit is a `.solo`
    /// unlimited mode); the funnel simply never fires outside the Coin Pit
    /// stake overlay that is its only caller.
    func recordCoinPitRoundStaked(tickets: Int) {
        guard tickets > 0 else { return }
        fireTrophy(.coinpitRoundStakeBest, value: tickets)
    }

    /// Push every climb-category trophy metric's CURRENT value into the
    /// trophy engine (S1-T1).  Callers gate on
    /// `currentMode.progression.recordsClimbResult` so CotD / Roll Out /
    /// Roll Up / track results never pollute the climb ladder — climb
    /// trophies are keyed to lifetime stats and level NUMBERS, never to a
    /// specific level layout (levels are swappable `LevelOverrides.json`
    /// content).  Cheap on the hot path: each `record` is one index lookup +
    /// O(interested trophies) and writes nothing unless a trophy latches.
    private func recordClimbTrophies() {
        // Level ladder — climb_first_clear (≥2) … climb_summit (≥5001).
        fireTrophy(.climbHighestUnlocked, value: highestUnlocked)
        // Total climb stars — climb_stars_25 / climb_stars_150 (latched
        // ratchet: resetProgress can shrink the live sum, never the unlock).
        fireTrophy(.climbTotalStars, value: totalStars)
        // Lifetime banked pickup coins — climb_pickups_100 (NOT the coin
        // balance; `totalCoins` counts pickups found).
        fireTrophy(.climbPickupCoins, value: totalCoins)
        // Perfect-world scan — climb_perfect_world (3 stars on all 100
        // levels of some world; keyed to the star dict + world number
        // ranges, never to layouts).
        fireTrophy(.climbPerfectWorlds,
                            value: TrophyBackfill.perfectWorldCount(bestStars: bestStars))
        // No-fall clear streak ratchet — skill_clean_sheet_10 / _25.  The
        // working streak was just grown by `recordNoFallClimbClear()`; its
        // monotonic best is what the trophy reads.
        fireTrophy(.noFallClearStreakBest,
                            value: trophyStats.bestNoFallClearStreak)
    }

    /// Push the Challenge-Track trophy metrics' current values (S1-T2).
    /// Called from `advanceTrackProgress` — the single funnel that mutates
    /// `trackProgress` / `completedTracks`.  Derivations mirror
    /// `TrophyBackfill.snapshot` exactly so a live update and a first-launch
    /// grandfather agree.  Keyed to progress NUMBERS and completion COUNTS,
    /// never to a specific track's layout.
    private func recordTrackTrophies() {
        // Best progress reached on any single track — track_first_level (≥1)
        // / track_halfway (≥50).
        fireTrophy(.trackBestProgress, value: trackProgress.values.max() ?? 0)
        // Tracks fully completed — track_first_complete / track_triple /
        // track_all_eight.
        fireTrophy(.tracksCompleted, value: completedTracks.count)
        // The prestige Golden Gauntlet — track_gauntlet (1 once
        // "golden-gauntlet" ∈ completedTracks).
        fireTrophy(.goldenGauntletCompleted,
                            value: completedTracks.contains("golden-gauntlet") ? 1 : 0)
    }

    /// Push the Challenge-of-the-Day clear trophy metrics (S1-T2).  Called
    /// from `completeTodaysDailyChallenge`, the sole funnel that inserts
    /// into `dailyChallengeCompletions`.  Both metrics derive from that
    /// append-only date set (mirrors `TrophyBackfill.snapshot`).
    private func recordDailyChallengeTrophies() {
        // Lifetime CotD clears — daily_first_clear / daily_clears_10 / _50.
        fireTrophy(.dailyClears, value: dailyChallengeCompletions.count)
        // Longest consecutive-day clear run — daily_week_streak (≥7).  The
        // engine latches the best observed, so a broken run never revokes.
        fireTrophy(.dailyClearStreakBest,
                            value: TrophyStats.longestConsecutiveDailyClearRun(
                                in: dailyChallengeCompletions))
    }

    /// Push the daily login-reward trophy metrics (S1-T2).  Called from
    /// `claimDailyReward` after the claim counter is bumped.  The claim
    /// count is a monotonic counter; the reward streak can regress on a
    /// missed day, but the engine latches the best observed — so recording
    /// the CURRENT `dailyStreak` correctly unlocks daily_login_7/30 and
    /// never revokes (this live latch supersedes the snapshot's proxy).
    private func recordDailyRewardTrophies() {
        // Lifetime claims — econ_punch_card (≥30).
        fireTrophy(.dailyRewardClaims, value: trophyStats.dailyRewardClaims)
        // Reward-streak high-water — daily_login_7 / daily_login_30.
        fireTrophy(.dailyRewardStreakBest, value: dailyStreak)
    }

    // MARK: - Minigame trophy funnels (S1-T3)

    /// Push the competitive-win trophy metrics (S1-T3).  Called from
    /// `recordCompetitiveWin` — the single win choke point (it bumps
    /// `minigameWins` and mints the ticket), so ticket-earn trophies fire
    /// here and ONLY here.  When reached via `recordMinigameResult`, that
    /// funnel has already bumped `minigameDifficultyWins[…|hard]` before
    /// calling us, so the Hard high-waters read the freshly-updated dict.
    /// Every derivation mirrors `TrophyBackfill.snapshot` exactly so a live
    /// win and a first-launch grandfather agree.
    private func recordCompetitiveWinTrophies() {
        // Arcade-wide win totals over the 6 competitive modes.
        var competitiveWins = 0
        var competitiveModesWon = 0
        for id in TrophyMetric.competitiveModeIDs {
            let w = minigameWins[id, default: 0]
            competitiveWins += w
            if w >= 1 { competitiveModesWon += 1 }
        }
        // arcade_first_win (≥1) / arcade_wins_100 (≥100).
        fireTrophy(.competitiveWins, value: competitiveWins)
        // arcade_all_six (all 6 modes have ≥1 win → count ≥6).
        fireTrophy(.competitiveModesWon, value: competitiveModesWon)

        // arcade_hard_once (≥1) / arcade_hard_all (≥6): count of the 6 modes
        // with a Hard win, from the per-difficulty dict.
        var competitiveModesWonHard = 0
        for id in TrophyMetric.competitiveModeIDs
        where minigameDifficultyWins["\(id)|hard", default: 0] >= 1 {
            competitiveModesWonHard += 1
        }
        fireTrophy(.competitiveModesWonHard, value: competitiveModesWonHard)

        // arcade_normal_once (≥1): count of the 6 modes with a win on Normal
        // or harder, from the same per-difficulty dict.
        var competitiveModesWonNormal = 0
        for id in TrophyMetric.competitiveModeIDs
        where minigameDifficultyWins["\(id)|normal", default: 0] >= 1
            || minigameDifficultyWins["\(id)|hard", default: 0] >= 1 {
            competitiveModesWonNormal += 1
        }
        fireTrophy(.competitiveModesWonNormal, value: competitiveModesWonNormal)

        // Per-game lifetime win tallies — <mode>_first_win / <mode>_wins_10.
        fireTrophy(.snakeWins,     value: minigameWins["snake", default: 0])
        fireTrophy(.sumoWins,      value: minigameWins["sumo", default: 0])
        fireTrophy(.paintballWins, value: minigameWins["paintball", default: 0])
        fireTrophy(.goldrushWins,  value: minigameWins["goldrush", default: 0])
        fireTrophy(.marblecupWins, value: minigameWins["marblecup", default: 0])
        fireTrophy(.kothWins,      value: minigameWins["koth", default: 0])
    }

    /// Push the "minigames played" discovery trophy metrics (S1-T3).  Called
    /// from `markModePlayed`, the funnel that grows `playedModeIDs`.  Mirrors
    /// `TrophyBackfill.snapshot`: `minigames_played` counts the intersection
    /// with the 12 minigame ids, and `coinpit_played` flips once "coinpit" is
    /// in the set.  Recording unconditionally is safe — a non-minigame id
    /// simply leaves both derivations unchanged.
    private func recordMinigamePlayedTrophies() {
        // arcade_sampler (≥5) / arcade_grand_tour (all 10).
        let played = TrophyMetric.minigameModeIDs.filter { playedModeIDs.contains($0) }.count
        fireTrophy(.minigamesPlayed, value: played)
        // coinpit_first_round (≥1 once "coinpit" has been played).
        fireTrophy(.coinpitPlayed, value: playedModeIDs.contains("coinpit") ? 1 : 0)
    }

    /// Push the per-game best-score trophy metrics reachable from a GameState
    /// funnel (S1-T3).  Each reads the SAME stored unit `TrophyBackfill`
    /// derives from — coverage % (`minigameBests["paintball"]`), hold-seconds
    /// (`minigameBests["koth"]`), the raw pinball score (`pinballBest`), and
    /// Roll Up height (`minigameBests["rollup"]`).  Roll Out and Disco bests
    /// are written in-view and are rerouted in S1-T4, so their trophies are
    /// deliberately NOT recorded here.  `metric` selects which one to push so
    /// the funnel call sites stay minimal.
    private func recordMinigameBestTrophy(_ metric: TrophyMetric) {
        switch metric {
        case .paintballBestCoverage:
            // paintball_coverage_60 (≥60).
            fireTrophy(.paintballBestCoverage, value: minigameBests["paintball", default: 0])
        case .kothBestHoldSeconds:
            // koth_hold_45 (≥45 hold-seconds in one round).
            fireTrophy(.kothBestHoldSeconds, value: minigameBests["koth", default: 0])
        case .pinballBestScore:
            // pinball_score_10k / _50k / _150k.
            fireTrophy(.pinballBestScore, value: pinballBest)
        case .rollupBestHeight:
            // rollup_100m (≥100) / rollup_500m (≥500).
            fireTrophy(.rollupBestHeight, value: minigameBests["rollup", default: 0])
        default:
            break
        }
    }

    /// Push the Zen-time trophy metric (S1-T3).  Called from `addZenSeconds`
    /// after the cumulative tally grows.  zen_hour (≥3,600) / zen_10_hours
    /// (≥36,000); the AFK-farmable ceiling stays silver by catalog design.
    private func recordZenTrophies() {
        fireTrophy(.zenSeconds, value: zenSeconds)
    }

    /// Push the Coin Pit reward-run trophy metrics (S1-T3).  Called from
    /// `recordGoldRushCoins` — the naming trap (trophy-catalog.md §3.5):
    /// `goldrushBest`/`goldrushCoinsTotal` are the ticket-staked COIN PIT
    /// reward run, NOT the "goldrush" (Smash and Grab) competitive mode.
    /// Mirrors `TrophyBackfill.snapshot`.
    private func recordCoinPitTrophies() {
        // coinpit_catch_90 (≥90 caught in one round).
        fireTrophy(.coinpitBestCatch, value: goldrushBest)
        // econ_pit_boss (≥2,500 lifetime Coin Pit coins).
        fireTrophy(.coinpitCoinsTotal, value: goldrushCoinsTotal)
    }

    /// Push the Disco Ball best-crossings trophy metrics (S1-T4).  Called from
    /// `recordDiscoResult` after the just-finished run's difficulty-scoped best
    /// is written.  Mirrors `TrophyBackfill.snapshot` EXACTLY: `disco_cross_25`
    /// rides the MAX over all three difficulty keys, `disco_hard_10` rides the
    /// `"discohard"` slot only.
    private func recordDiscoTrophies() {
        // disco_cross_25 (≥25 crossings in one run, any difficulty).
        let discoBest = max(minigameBests["discoeasy", default: 0],
                            minigameBests["disco", default: 0],
                            minigameBests["discohard", default: 0])
        fireTrophy(.discoBestCrossings, value: discoBest)
        // disco_hard_10 (≥10 crossings in one Hard run).
        fireTrophy(.discoHardBestCrossings,
                            value: minigameBests["discohard", default: 0])
    }

    /// Push the Roll Out furthest-maze trophy metric (S1-T4).  Called from
    /// `recordRollOutResult` after the highest-maze-reached best is written.
    /// (Roll Out is held back from v1.0 and its trophies are out of the
    /// catalog, so this fires a metric no shipping trophy reads; kept so the
    /// trophies work again when the mode returns.)  Mirrors
    /// `TrophyBackfill.snapshot`: both `rollout_first_maze` (≥1) and
    /// `rollout_maze_10` (≥10) ride `minigameBests["rollout"]`.
    private func recordRollOutTrophies() {
        fireTrophy(.rolloutBestMaze, value: minigameBests["rollout", default: 0])
    }

    // MARK: - Cosmetic & economy trophy funnels (S1-T5)

    /// Owned BALL skins, IAP secrets excluded — the `balls_own_10/40`
    /// metric.  `ownedBallSkins` holds rawValues; the starter (`.red`) is
    /// the free default and never counts toward "own N ball skins" (the
    /// catalogue's 74-ball framing prices it out).  It is normally absent
    /// from the set, but `liquidateCoinCosmetics` re-inserts every slot's
    /// starter, so it's subtracted explicitly to keep the count stable
    /// across a liquidation.  Seasonal balls DO count here (catalog §3.6) —
    /// only the 2 IAP-secret balls and the starter are removed.
    var trophyBallsOwnedCount: Int {
        ownedBallSkins
            .subtracting(TrophyCosmeticExclusions.iapSecretBalls.map { $0.rawValue })
            .subtracting([BallSkin.starter.rawValue])
            .count
    }

    /// Total owned cosmetics across all 7 slots, IAP secrets + starters
    /// excluded — the `items_own_50` metric.  Sums the owned rawValue sets;
    /// each slot's free starter is subtracted (normally absent, but
    /// re-inserted by `liquidateCoinCosmetics`) and the 4 IAP secrets are
    /// removed from their slots.  Seasonal balls count (catalog §3.6).
    var trophyCosmeticsOwnedCount: Int {
        // Slots with no IAP-secret members: subtract only the free starter.
        func owned<Item: CosmeticItem>(_ set: Set<String>, _ type: Item.Type) -> Int {
            set.subtracting([Item.starter.rawValue]).count
        }
        let balls = ownedBallSkins
            .subtracting(TrophyCosmeticExclusions.iapSecretBalls.map { $0.rawValue })
            .subtracting([BallSkin.starter.rawValue]).count
        let trails = ownedTrails
            .subtracting(TrophyCosmeticExclusions.iapSecretTrails.map { $0.rawValue })
            .subtracting([TrailColor.starter.rawValue]).count
        let floors = ownedFloors
            .subtracting(TrophyCosmeticExclusions.iapSecretFloors.map { $0.rawValue })
            .subtracting([Floor.starter.rawValue]).count
        // Goals / Pits / Boundaries / Music have no IAP-secret members.
        return balls + trails + floors
            + owned(ownedGoals, GoalSkin.self)
            + owned(ownedPits, Pit.self)
            + owned(ownedBoundaries, Boundary.self)
            + (CosmeticFeatures.musicEnabled ? owned(ownedMusic, MusicTrack.self) : 0)
    }

    /// Count of owned EVERGREEN cosmetics — the `collection_complete`
    /// metric, capped at the 242-item evergreen set (253 total − 4 IAP
    /// secrets − 7 seasonal balls).  Iterates every case per slot, keeps the
    /// evergreen ones (not an IAP secret, not a seasonal-exclusive ball —
    /// starters ARE evergreen and always owned), and counts those `isOwned`.
    /// Reaches exactly 242 iff every evergreen cosmetic is owned; owning a
    /// seasonal or IAP-secret item can never push it past 242.  While music
    /// is off (1.0) the 19 music tracks don't count, so the set is 223.
    var trophyEvergreenCosmeticsOwnedCount: Int {
        var count = 0
        for b in BallSkin.allCases
        where !TrophyCosmeticExclusions.iapSecretBalls.contains(b)
            && !TrophyCosmeticExclusions.seasonalExclusiveBalls.contains(b)
            && isOwned(b) { count += 1 }
        for g in GoalSkin.allCases where isOwned(g) { count += 1 }
        for t in TrailColor.allCases
        where !TrophyCosmeticExclusions.iapSecretTrails.contains(t)
            && isOwned(t) { count += 1 }
        for f in Floor.allCases
        where !TrophyCosmeticExclusions.iapSecretFloors.contains(f)
            && isOwned(f) { count += 1 }
        for p in Pit.allCases where isOwned(p) { count += 1 }
        for bnd in Boundary.allCases where isOwned(bnd) { count += 1 }
        // Music is not offered in 1.0 and doesn't count toward the set then.
        if CosmeticFeatures.musicEnabled {
            for m in MusicTrack.allCases where isOwned(m) { count += 1 }
        }
        return count
    }

    /// True when a non-starter cosmetic is equipped in EVERY offered loadout
    /// slot (Ball/Goal/Trail/Floor/Pit/Boundary, plus Music only when
    /// `CosmeticFeatures.musicEnabled` — six slots in 1.0) at once — the
    /// `cosmetic_full_kit` metric.  The Ball slot counts as non-starter when
    /// either a non-starter individual skin OR any equipped Pack is worn.
    /// Exact inverse of `isLoadoutDefault`, per slot.
    var trophyLoadoutIsFullyNonStarter: Bool {
        let ballNonStarter = equippedPackID != nil || activeSkin != .starter
        return ballNonStarter
            && equippedGoal    != GoalSkin.starter
            && equippedTrail   != TrailColor.starter
            && equippedFloor   != Floor.starter
            && equippedPit     != Pit.starter
            && equippedBoundary != Boundary.starter
            // Music is not offered in 1.0, so the kit is six slots then.
            && (!CosmeticFeatures.musicEnabled || equippedMusic != MusicTrack.starter)
    }

    /// Push the ownership-based cosmetic trophy metrics (S1-T5).  Called
    /// from `grant` — the single choke point every acquisition (coin buy,
    /// bundle, pack, tutorial gift, track reward, IAP unlock) routes
    /// through — plus `purchasePack` for the pack-count metric (a Pack is
    /// only ever bought, never free-granted, so `ownedPacks` isn't touched
    /// by `grant`).  Every derivation mirrors `TrophyBackfill.snapshot`
    /// exactly so a live grant and a first-launch grandfather agree.  The
    /// engine latches, so a later Sell Back / liquidation that shrinks a
    /// count never revokes an earned trophy.
    private func recordCosmeticOwnershipTrophies() {
        // balls_own_10 / balls_own_40 — owned balls minus the 2 IAP secrets.
        fireTrophy(.ballsOwned, value: trophyBallsOwnedCount)
        // items_own_50 — total owned across 7 slots minus the 4 IAP secrets.
        fireTrophy(.cosmeticsOwned, value: trophyCosmeticsOwnedCount)
        // collection_complete — owned evergreen items toward the 242 set.
        fireTrophy(.evergreenCosmeticsOwned,
                            value: trophyEvergreenCosmeticsOwnedCount)
        // bundle_first / bundle_5 — completed bundles (IAP-secret-free by
        // guardrail).
        fireTrophy(.bundlesCompleted, value: completedBundleIDs.count)
        // pack_first — owned Ball Packs.
        fireTrophy(.packsOwned, value: ownedPacks.count)
    }

    /// Push the "cosmetic equipped in all 7 slots" metric (S1-T5).  Called
    /// from every equipped-slot mutation (the six `equipped*` setters, the
    /// ball equip funnels, and Pack equip) so `cosmetic_full_kit` latches
    /// the instant a full non-starter loadout is worn.  A monotonic latch:
    /// value is 1 only while fully non-starter, but the engine never revokes
    /// once unlocked.
    func recordFullKitTrophy() {
        fireTrophy(.fullNonstarterLoadouts,
                            value: trophyLoadoutIsFullyNonStarter ? 1 : 0)
    }

    /// Push the first-coin-purchase latch (S1-T5) — `cosmetic_first_buy`.
    /// Called only from the three COIN-spend funnels (`purchase`,
    /// `purchaseBundle`, `purchasePack`) on success, so free grants
    /// (tutorial gift, track rewards, IAP unlocks) never trip it.  A pure
    /// latch: any successful coin spend records value 1 (threshold 1).
    private func recordCosmeticFirstBuyTrophy() {
        fireTrophy(.cosmeticCoinBuys, value: 1)
    }

    /// Push the lifetime play-earned coins metric (S1-T5) —
    /// `econ_working_capital`.  Called from `addCoins` after the S0-T2
    /// source-tagged counter (`coinsEarnedFromPlay`, which already excludes
    /// IAP grants, Sell Back refunds, and grantBundleFree compensation) is
    /// bumped; also latches `econ_nest_egg` off the current balance
    /// high-water (the engine keeps the best, so spending later never
    /// revokes).
    private func recordEconomyTrophies() {
        // econ_working_capital — 2,500 lifetime coins earned from play.
        fireTrophy(.coinsEarnedFromPlay, value: trophyStats.coinsEarnedFromPlay)
        // econ_nest_egg — hold 1,000 coins at once (latched high-water).
        fireTrophy(.coinBalancePeak, value: coinBalance)
    }

    // MARK: - Social trophy funnels (S1-T6)
    //
    // The trophy DECISION lives here (never in a view), driven by the SwiftUI
    // Friends/Clans/sign-in views AFTER a `SocialClient` call SUCCEEDS —
    // SocialClient is a stateless singleton with no reference to GameState or
    // the engine, so the established view→funnel pattern (S1-T7) is the only
    // route. Signed-out players never reach these funnels, so their social
    // trophies simply stay locked — no error paths. All five social metrics
    // are go-forward (absent from `TrophyBackfill.snapshot`); no social trophy
    // requires another player to exist beyond one friend/clan action.

    /// `social_sign_in` — latched the first time a Sign-in-with-Apple session
    /// becomes active (fresh sign-in OR a restored session — either proves the
    /// player has signed in). Called from ContentView's `auth.isSignedIn`
    /// change hook. A pure value-1 latch; the engine unlocks once, forever.
    func recordSocialSignIn() {
        fireTrophy(.signedIn, value: 1)
    }

    /// Restore this player's trophies from the server on sign-in, then push the
    /// unioned local snapshot back up (S3-T5; design.md §4 "Supabase restore for
    /// signed-in players"). The app's FIRST server→local hydrate, safe ONLY
    /// because the trophy ledger is a pure ratchet: `TrophySyncService`
    /// hydrates via `TrophyEngine.mergeUnlocks` (server ∪ local, never
    /// subtraction), so a restore can only ADD unlocks and can never clobber a
    /// local unlock or any other save state.
    ///
    /// Fire-and-forget, off the main path: called from ContentView alongside
    /// `recordSocialSignIn()` on every transition into a signed-in session
    /// (fresh sign-in OR a restored launch session). Signed-out → the hydrate is
    /// an internal no-op. The follow-up `sync` pushes the unioned set (server ∪
    /// local, incl. any local-only unlocks the hydrate armed) to BOTH rails.
    /// Newly-restored unlocks are NOT toasted — S2-T6's coalesced reveal already
    /// owns the "you've already earned N" moment; a silent ratchet restore never
    /// interrupts play (design.md §6). Grants nothing (D1 never-mint).
    func hydrateTrophiesOnSignIn() {
        Task {
            await TrophySyncService.shared.hydrateOnSignIn(engine: trophyEngine)
            // Push the unioned snapshot (server ∪ local) back up: the hydrate
            // arms the dirty flag when it introduced a server-only id, and any
            // local-only unlocks still need to reach player_trophies now that a
            // session exists. A no-op when nothing changed (clean flag).
            await TrophySyncService.shared.sync(engine: trophyEngine)
        }
    }

    /// `social_first_friend` (≥1) / `social_friends_5` (≥5) — the accepted-
    /// friend high-water. Called from FriendsView after an accept succeeds and
    /// the friend list reloads; `peak` is the CURRENT accepted-friend count.
    /// The engine keeps the best observed, so removing a friend later never
    /// revokes (latched high-water — sprint-plan.md §4 addenda).
    func recordFriendAccepted(peak: Int) {
        fireTrophy(.friendsAcceptedPeak, value: peak)
    }

    /// `social_send_life` (≥1) / `social_lives_sent_25` (≥25) — lifetime lives
    /// gifted (friend gifts AND clan fulfillments both count, per the catalog).
    /// Called from Friends/Clans views after `SocialClient.sendLife` succeeds;
    /// bumps the persisted go-forward counter, then records its current value.
    func recordLifeSent() {
        trophyStats.recordLifeSent()
        fireTrophy(.livesSent, value: trophyStats.livesSent)
    }

    /// `clan_join` — latched on joining OR creating a clan. Called from
    /// ClansView after `SocialClient.joinClan`/`createClan` succeeds. A pure
    /// value-1 latch.
    func recordClanJoined() {
        fireTrophy(.clanJoined, value: 1)
    }

    /// `clan_fulfill` (≥1) — a life sent to a clanmate who was asking for one.
    /// Called from ClansView IN ADDITION to `recordLifeSent()` (a fulfillment
    /// is also a life sent) when the send target had an outstanding request.
    /// Bumps its own persisted go-forward counter, then records its value.
    func recordClanRequestFulfilled() {
        trophyStats.recordClanRequestFulfilled()
        fireTrophy(.clanRequestsFulfilled, value: trophyStats.clanRequestsFulfilled)
    }

    // MARK: - Queries

    func stars(for level: Int) -> Int           { bestStars[level] ?? 0 }
    func coinsCollected(for level: Int) -> Set<Int> { collectedCoins[level] ?? [] }
    func time(for level: Int) -> TimeInterval?  { bestTime[level] }

    /// Surgical coin-banking: merges `indices` into the level's banked
    /// coin set WITHOUT touching bestStars / bestTime / highestUnlocked.
    /// Used by the L1 phased tutorial when the player picks up all
    /// three coins (we bank them at that moment so a subsequent fall
    /// doesn't make them re-appear as pickable).
    func bankCoins(for level: Int, indices: Set<Int>) {
        guard !indices.isEmpty else { return }
        var set = collectedCoins[level] ?? []
        set.formUnion(indices)
        collectedCoins[level] = set
    }

    /// Wipe any banked coins for a single level.  Used by the L1
    /// tutorial entry path so a player who bailed mid-tutorial after
    /// the Phase-2 coin bank doesn't return to find the coins already
    /// banked (which would make them un-pickable on the re-run).
    func clearCollectedCoins(for level: Int) {
        collectedCoins.removeValue(forKey: level)
    }
    func isUnlocked(_ level: Int) -> Bool       { level <= highestUnlocked }
    var totalStars: Int                          { bestStars.values.reduce(0, +) }
    var totalCoins: Int                          { collectedCoins.values.reduce(0) { $0 + $1.count } }

    // MARK: - Lives system

    /// True iff this level number consumes a life on failure.  Tutorial
    /// (L1-10) is exempt so new players can learn without pressure.
    func isTutorialLevel(_ level: Int) -> Bool { level <= Self.tutorialLevelCount }

    /// Has this game mode been launched before?  (Drives the first-play tutorial.)
    func hasPlayedMode(_ id: String) -> Bool { playedModeIDs.contains(id) }

    /// Record that a mode has been launched so its tutorial won't show again.
    func markModePlayed(_ id: String) {
        if !playedModeIDs.contains(id) { playedModeIDs.insert(id) }
        // Discovery trophies (arcade_sampler / arcade_grand_tour /
        // coinpit_first_round) ride the played-mode set (S1-T3).
        recordMinigamePlayedTrophies()
    }

    /// The currently-selected GameMode (resolves `currentModeID`; climb fallback).
    var currentMode: GameMode {
        GameModeCatalogue.mode(id: currentModeID) ?? GameModeCatalogue.climb
    }

    /// The mode actually being PLAYED, even if it is held back from this
    /// release.  Trophy counters and Adventure-only progress must ask this,
    /// not `currentMode`: a held-back mode is not Adventure, and treating it
    /// as Adventure would let it reset or feed Adventure counters.  An
    /// unknown id still means Adventure.
    var playedMode: GameMode {
        GameModeCatalogue.registeredMode(id: currentModeID) ?? GameModeCatalogue.climb
    }

    // MARK: - Challenge of the Day

    /// Today's deterministic challenge.
    var todaysDailyChallenge: DailyChallenge { DailyChallenge.current() }

    /// Has the player already cleared today's challenge?
    var dailyChallengeDoneToday: Bool {
        dailyChallengeCompletions.contains(DailyChallenge.key())
    }

    /// Has the player already failed (used up all attempts on) today's challenge?
    var dailyChallengeFailedToday: Bool {
        dailyChallengeFailures.contains(DailyChallenge.key())
    }

    /// Today's challenge is settled (cleared or failed) — no more plays today.
    var dailyChallengeSettledToday: Bool {
        dailyChallengeDoneToday || dailyChallengeFailedToday
    }

    /// The brutal-layout seed for the current sub-level of the run.
    var dailyChallengeLayoutSeed: Int {
        todaysDailyChallenge.layoutSeed(for: dailyChallengeIndex)
    }

    /// Begin a fresh run of today's challenge (called when it's launched).
    /// Stamps the day as "in progress" so that abandoning the run (home button
    /// or app kill) forfeits it.
    func startDailyChallenge() {
        dailyChallengeIndex = 0
        dailyChallengeAttemptsLeft = Self.dailyChallengeAttemptsPerLevel
        dailyChallengeRunStartedKey = DailyChallenge.key()
        // Mark the "daily" mode played (§6 item 18 — nothing else writes it)
        // and fire daily_first_start (S1-T2).  A NEW go-forward metric: not
        // backfilled, so it credits the first daily STARTED after trophies
        // ship, not a veteran's past runs.
        if !playedModeIDs.contains("daily") { playedModeIDs.insert("daily") }
        fireTrophy(.dailyPlayed, value: 1)
    }

    /// Forfeit an in-progress Challenge-of-the-Day run.  Quitting mid-run — via
    /// the home button or by killing the app — counts as failing the day.  A
    /// no-op when no run is active; a stale key (a run started on an earlier
    /// day) is simply cleared without penalising today.
    func forfeitDailyChallengeIfRunning() {
        guard let key = dailyChallengeRunStartedKey else { return }
        if key == DailyChallenge.key() && !dailyChallengeCompletions.contains(key) {
            failTodaysDailyChallenge()        // also clears the in-progress key
        } else {
            dailyChallengeRunStartedKey = nil // stale or already cleared
        }
    }

    /// Advance to the next sub-level; returns true when the gauntlet is cleared.
    /// Each new sub-level refreshes the free-attempt allowance.
    func advanceDailyChallenge() -> Bool {
        dailyChallengeIndex += 1
        if dailyChallengeIndex >= todaysDailyChallenge.levelCount { return true }
        dailyChallengeAttemptsLeft = Self.dailyChallengeAttemptsPerLevel
        return false
    }

    /// Spend one attempt on the current sub-level after a fall.  Returns true
    /// when the player has now exhausted their attempts and the day is lost.
    func recordDailyAttemptFailure() -> Bool {
        dailyChallengeAttemptsLeft = max(0, dailyChallengeAttemptsLeft - 1)
        return dailyChallengeAttemptsLeft <= 0
    }

    /// Mark today's challenge failed (once) — locks it until tomorrow, no reward.
    func failTodaysDailyChallenge() {
        dailyChallengeFailures.insert(DailyChallenge.key())
        dailyChallengeRunStartedKey = nil   // the run is settled
    }

    /// Mark today's challenge done (once) and grant its coin reward.
    func completeTodaysDailyChallenge() {
        dailyChallengeRunStartedKey = nil   // the run is settled
        let key = DailyChallenge.key()
        guard !dailyChallengeCompletions.contains(key) else { return }
        dailyChallengeCompletions.insert(key)
        addCoins(todaysDailyChallenge.rewardCoins)
        // A genuinely-new CotD clear just landed — fire the daily-clear
        // trophy metrics (S1-T2; the guard above makes this once-per-day).
        recordDailyChallengeTrophies()
    }

    /// Current regenerative life count (0…livesMax) including any regen that
    /// has accumulated since `lastLifeLostAt`.  Purchased reserve lives are
    /// NOT included — read `totalLives` for gating and the HUD pill count.
    /// Stored `lives` only updates when `commitRegen()` or `consumeLife()`
    /// is called.
    var displayedLives: Int {
        if unlimitedLives { return Self.livesMax }
        guard lives < Self.livesMax, let last = lastLifeLostAt else { return lives }
        let elapsed = Date.now.timeIntervalSince(last)
        let regenCount = Int(elapsed / Self.livesRegenInterval)
        return min(Self.livesMax, lives + regenCount)
    }

    /// Everything the player can spend: the regenerative bar plus the
    /// purchased reserve queue.  This is the number the lives pill shows.
    var totalLives: Int { displayedLives + purchasedLives }

    /// Seconds until the next regen tick, or nil if not regenerating.
    func timeToNextLife() -> TimeInterval? {
        if unlimitedLives { return nil }
        guard displayedLives < Self.livesMax, let last = lastLifeLostAt else { return nil }
        let elapsed = Date.now.timeIntervalSince(last)
        let untilNext = Self.livesRegenInterval - elapsed.truncatingRemainder(dividingBy: Self.livesRegenInterval)
        return untilNext
    }

    /// Fraction (0…1) of the way through the current regen cycle.  Used by
    /// the home HUD to render the next-empty marble as a partial-fill —
    /// e.g. 0.8 = the bottom 4/5 of the marble is coloured, top 1/5 hollow.
    /// Returns nil when no regen is active (full bar, no last-loss
    /// timestamp, or unlimited-lives subscription).
    func regenProgress() -> Double? {
        if unlimitedLives { return nil }
        guard displayedLives < Self.livesMax, let last = lastLifeLostAt else { return nil }
        let elapsed = Date.now.timeIntervalSince(last)
        let intoCurrentCycle = elapsed.truncatingRemainder(dividingBy: Self.livesRegenInterval)
        return min(1.0, max(0.0, intoCurrentCycle / Self.livesRegenInterval))
    }

    /// Promote any accumulated regen ticks into the stored `lives` counter
    /// and advance `lastLifeLostAt` to the most recent tick boundary.
    /// Idempotent — call any time you want to snapshot the regen state
    /// (e.g. before consuming a life so we don't double-count).
    func commitRegen() {
        if unlimitedLives {
            lives = Self.livesMax
            lastLifeLostAt = nil
            return
        }
        guard lives < Self.livesMax, let last = lastLifeLostAt else { return }
        let elapsed = Date.now.timeIntervalSince(last)
        let regenCount = Int(elapsed / Self.livesRegenInterval)
        guard regenCount > 0 else { return }
        lives = min(Self.livesMax, lives + regenCount)
        if lives >= Self.livesMax {
            lastLifeLostAt = nil
        } else {
            lastLifeLostAt = last.addingTimeInterval(TimeInterval(regenCount) * Self.livesRegenInterval)
        }
    }

    /// Decrement lives by 1 — the regenerative bar drains first, then the
    /// purchased reserve queue.  Returns true if a life was consumed, false
    /// if the player was already at zero everywhere.  Unlimited-lives
    /// subscribers always return true without decrementing.
    ///
    /// Draining regen first is deliberate: the bar starts refilling on the
    /// 6-minute timer immediately, so reserve lives stretch further.
    @discardableResult
    func consumeLife() -> Bool {
        // A climb fall breaks the no-fall clear streak (§6 item 6) — gated
        // on the shipped mode vocabulary so Roll Out / Roll Up / track life
        // consumption never resets it (S1-T1 acceptance).  BEFORE the
        // unlimited-lives early-out: a subscriber's fall is still a fall,
        // or unlimited lives would farm `skill_clean_sheet_*`.  Tutorial
        // falls (L1–10) never reach consumeLife — their reset rides
        // S1-T7's direct fall funnel.
        if playedMode.progression.recordsClimbResult {
            trophyStats.resetNoFallClearStreak()
        }
        if unlimitedLives { return true }
        commitRegen()
        if lives > 0 {
            lives -= 1
            if lives < Self.livesMax && lastLifeLostAt == nil {
                lastLifeLostAt = .now
            }
        } else if purchasedLives > 0 {
            purchasedLives -= 1
        } else {
            return false
        }
        reconcileLivesNotification()
        return true
    }

    /// Award lives (rewarded ad, friend gift, or IAP grant).  Granted lives
    /// go to the purchased reserve queue — the regen bar only ever fills on
    /// the 6-minute timer, so a grant never pauses or resets regen (and the
    /// lives-full notification schedule is unaffected).
    func addLives(_ count: Int) {
        guard count > 0 else { return }
        if unlimitedLives { return }
        purchasedLives += count
    }

    // MARK: - Notifications (lives-full / shop-fresh)

    /// The deterministic Date at which free 6-minute regen brings lives back to
    /// the cap, or nil when not regenerating (full or unlimited).
    /// "Had fallen below 10" is implicit: this is non-nil only while lives are
    /// actively regenerating.  Invariant under `commitRegen()` — stale stored
    /// `lives` + `lastLifeLostAt` still yield the same absolute restock instant.
    var livesRestockDate: Date? {
        guard !unlimitedLives, lives < Self.livesMax, let last = lastLifeLostAt else { return nil }
        return last.addingTimeInterval(Double(Self.livesMax - lives) * Self.livesRegenInterval)
    }

    /// Re-schedule (or cancel) the "lives full" local notification from the
    /// current lives state.  Called after every lives change and on app
    /// foreground.  Earning a life to the cap, an IAP top-up, or the unlimited
    /// unlock all leave `livesRestockDate == nil`, which cancels the alert.
    func reconcileLivesNotification() {
        commitRegen()   // snapshot any accrued regen so the math is current
        guard livesFullNotifEnabled, let restock = livesRestockDate else {
            NotificationManager.shared.cancelLivesFull()
            return
        }
        NotificationManager.shared.scheduleLivesFull(at: restock)
    }

    /// The player is viewing the shop — arm ONE "fresh items" notification for
    /// the next rotation boundary (replacing any prior request).  Re-viewing
    /// re-arms it; once it fires there's nothing more until they view again.
    func recordShopViewed() {
        guard shopFreshNotifEnabled else {
            NotificationManager.shared.cancelShopFresh()
            return
        }
        NotificationManager.shared.scheduleShopFresh(at: ShopRotation.refreshDate(at: .now))
    }

    // MARK: - Cosmetic economy

    /// Per-pickup coin award on first-time collection.  Each level has
    /// up to 3 currency-coins on the floor → 0…3 coins per first clear
    /// from pickups alone.
    static let coinPerPickup: Int = 1
    /// Base flat coin award on EVERY climb clear — first time or replay.  The
    /// grind is blessed (2026-07-01 economy calibration): replaying a level
    /// pays this bonus again, exactly like the Challenge Tracks, whether the
    /// player pushes to level 10,000 or replays level 1 ten thousand times.
    /// Stacks with pickups, so a perfect first clear yields `clearCoins(for:)
    /// + 3` coins; pickup coins stay sticky and pay only once per level.
    /// The climb scales this by tier via `clearCoins(for:)` — this constant
    /// is the easy-tier base (and the flat track-level bonus).
    static let coinPerClear:  Int = 2

    /// Climb clear bonus scaled by the level's difficulty tier (the
    /// last-digit rule — `DifficultyTier.tier(for:)`): easy 2 · hard 3 ·
    /// veryHard 4.  Harder never pays less per clear.
    static func clearCoins(for level: Int) -> Int {
        switch DifficultyTier.tier(for: level) {
        case .easy:     return 2
        case .hard:     return 3
        case .veryHard: return 4
        }
    }

    /// Maximum coins grantable in a single `addCoins` call.
    /// The biggest coin-pack grant is 10,000 (the $49.99 top pack, since the
    /// 2026-11 return to App Store Connect amounts).  The cap stays at 60,000
    /// as headroom for large refunds (Sell Back, collection gift
    /// compensation).  It MUST stay at or above the biggest `rewardCoins`
    /// grant or a purchase would be silently clamped and short-deliver.
    /// Values exceeding this are clamped and printed in DEBUG so any
    /// runaway-reward bug surfaces during development.
    private static let maxSingleAward: Int = 60_000

    /// Hard ceiling on the stored coin balance — prevents overflows and
    /// absurd displays from a corrupted save or a future bug.
    static let maxCoinBalance: Int = 999_999

    /// Award coins to the player's balance.  Use this everywhere — never
    /// mutate `coinBalance` directly.
    ///
    /// - Asserts `amount >= 0` in debug builds; negative amounts are a
    ///   programming error (use `spendCoins(_:)` for deductions).
    /// - Clamps `amount` to `[0, maxSingleAward]`; excess is logged.
    /// - Clamps the resulting balance to `[0, maxCoinBalance]`.
    ///
    /// `source` tags the award for the lifetime play-earned trophy counter
    /// (trophy-catalog.md §6 item 4).  The default is `.play` — only the
    /// non-play call sites tag themselves, and the exclusions are
    /// load-bearing: IAP grants (StoreKitManager → `.iap`), Sell Back
    /// refunds (`liquidateCoinCosmetics` → `.refund`), and bundle-gift
    /// compensation (`grantBundleFree` → `.giftCompensation`) must never
    /// count as play income.  The counter records the actually-granted
    /// (post-`maxSingleAward`-clamp) award; the balance cap is a wallet
    /// limit, not an earn limit, so a full wallet still earns.
    func addCoins(_ amount: Int, source: TrophyStats.CoinSource = .play) {
        assert(amount >= 0, "addCoins: negative amount — use spendCoins(_:) for deductions")
        guard amount > 0 else { return }
        let clamped: Int
        if amount > Self.maxSingleAward {
            #if DEBUG
            print("[GameState] addCoins: \(amount) exceeds maxSingleAward \(Self.maxSingleAward); clamping")
            #endif
            clamped = Self.maxSingleAward
        } else {
            clamped = amount
        }
        coinBalance = min(coinBalance + clamped, Self.maxCoinBalance)
        trophyStats.recordCoins(clamped, source: source)
        // Economy trophies (S1-T5): econ_working_capital reads the just-bumped
        // play-earned counter (source-filtered), econ_nest_egg the balance
        // high-water.  The engine latches, so a later spend never revokes.
        recordEconomyTrophies()
    }

    // MARK: - Minigame results (leaderboards + rewards)

    /// Coin bonus paid for a new personal best on a minigame — now 0 (see
    /// `CoinPayouts.personalBestBonus`).
    static let minigameBestBonus = CoinPayouts.personalBestBonus

    /// A snapshot of local stats as a `PlayerProfile`, used by the profile
    /// "Player Ranks" section to render the player's own stats (the global rank
    /// for each board is fetched from the server separately).
    var localLeaderboardProfile: PlayerProfile {
        PlayerProfile(
            id: SocialClient.shared.currentUserId ?? UUID(),
            displayName: playerName,
            climbLevel: currentLevel,
            highestUnlocked: highestUnlocked,
            totalStars: totalStars,
            coinsCollected: totalCoins,
            pinballBest: pinballBest,
            zenSeconds: zenSeconds,
            goldrushBest: minigameBests["goldrush"],   // Smash and Grab best (see syncMinigameStats)
            snakeBest: minigameBests["snake"],
            sumoBest: minigameBests["sumo"],
            paintballBest: minigameBests["paintball"],
            marblecupBest: minigameBests["marblecup"],
            kothBest: minigameBests["koth"],
            snakeWins: minigameWins["snake"],
            sumoWins: minigameWins["sumo"],
            paintballWins: minigameWins["paintball"],
            marblecupWins: minigameWins["marblecup"],
            kothWins: minigameWins["koth"],
            goldrushWins: minigameWins["goldrush"],
            rollupBest: minigameBests["rollup"],
            rollupBestSeconds: rollupBestSeconds > 0 ? rollupBestSeconds : nil,
            // Best of the three Disco Ball difficulties (the profile summary);
            // the leaderboards themselves are per difficulty.
            discoballBest: discoBoardBest > 0 ? discoBoardBest : nil,
            discoballBestAvgMs: discoBoardAvgMs > 0 ? discoBoardAvgMs : nil
        )
    }

    /// Publish one difficulty's Disco Ball best to its leaderboard
    /// (`minigame_scores`, game "disco").  Best-effort; a no-op signed out.
    /// Fails harmlessly until docs/leaderboard-discoball.sql is run.
    func syncDiscoScore(_ difficulty: MinigameDifficulty) {
        guard SocialClient.shared.isSignedIn else { return }
        let best = minigameBests[Self.discoBestKey(difficulty), default: 0]
        guard best > 0 else { return }
        let avg = discoBestAvgMs[difficulty.rawValue, default: 0]
        Task {
            try? await SocialClient.shared.syncMinigameScore(
                game: "disco", difficulty: difficulty.rawValue,
                wins: 0, best: best, bestAvgMs: avg > 0 ? avg : nil)
        }
    }

    /// Once per launch, upload every per-difficulty leaderboard row this
    /// device already knows: the six competitive games' wins and bests for
    /// each difficulty played, and each Disco Ball difficulty's best.  The
    /// device has always kept these per difficulty, so nothing is guessed;
    /// this fills the per-difficulty boards for players whose rows were never
    /// sent (Disco Ball, and competitive games played before the
    /// per-difficulty boards existed).
    private func backfillDifficultyScores() {
        guard SocialClient.shared.isSignedIn, !didBackfillDifficultyScores else { return }
        didBackfillDifficultyScores = true
        var rows: [(game: String, difficulty: String, wins: Int, best: Int, avg: Int?)] = []
        for mode in Self.competitiveDifficultyModeIDs {
            for d in MinigameDifficulty.allCases {
                let key = Self.minigameDifficultyKey(mode, d)
                let wins = minigameDifficultyWins[key, default: 0]
                let best = minigameDifficultyBests[key, default: 0]
                let plays = minigameDifficultyPlays[key, default: 0]
                if wins > 0 || best > 0 || plays > 0 {
                    rows.append((game: mode, difficulty: d.rawValue, wins: wins, best: best, avg: nil))
                }
            }
        }
        for d in MinigameDifficulty.allCases {
            let best = minigameBests[Self.discoBestKey(d), default: 0]
            let avg = discoBestAvgMs[d.rawValue, default: 0]
            if best > 0 {
                rows.append((game: "disco", difficulty: d.rawValue, wins: 0, best: best,
                             avg: avg > 0 ? avg : nil))
            }
        }
        guard !rows.isEmpty else { return }
        Task {
            for r in rows {
                try? await SocialClient.shared.syncMinigameScore(
                    game: r.game, difficulty: r.difficulty,
                    wins: r.wins, best: r.best, bestAvgMs: r.avg)
            }
        }
    }

    /// The competitive games with per-difficulty leaderboards (mode ids, as
    /// stored in `minigame_scores.game`).
    static let competitiveDifficultyModeIDs = ["snake", "sumo", "paintball", "goldrush", "marblecup", "koth"]

    /// Publish the minigame + competitive personal bests/wins to the leaderboard
    /// (no-op signed out).
    func syncMinigameStats() {
        guard SocialClient.shared.isSignedIn else { return }
        // The server's `goldrush_best` column backs the SMASH AND GRAB board
        // (mode id "goldrush"), so it carries that mode's best — NOT the
        // local `goldrushBest`, which is the Gold Rush (coin pit) reward run.
        let p = pinballBest, z = zenSeconds, g = minigameBests["goldrush", default: 0]
        let gw = minigameWins["goldrush", default: 0]
        let snB = minigameBests["snake", default: 0],     snW = minigameWins["snake", default: 0]
        let suB = minigameBests["sumo", default: 0],      suW = minigameWins["sumo", default: 0]
        let pbB = minigameBests["paintball", default: 0], pbW = minigameWins["paintball", default: 0]
        let mcB = minigameBests["marblecup", default: 0], mcW = minigameWins["marblecup", default: 0]
        let koB = minigameBests["koth", default: 0],      koW = minigameWins["koth", default: 0]
        let ruB = minigameBests["rollup", default: 0],    ruS = rollupBestSeconds
        backfillDifficultyScores()
        Task {
            try? await SocialClient.shared.syncMinigameStats(
                pinballBest: p, zenSeconds: z,
                goldrushBest: g, goldrushWins: gw,
                snakeBest: snB, snakeWins: snW,
                sumoBest: suB, sumoWins: suW,
                paintballBest: pbB, paintballWins: pbW,
                marblecupBest: mcB, marblecupWins: mcW,
                kothBest: koB, kothWins: koW,
                rollupBest: ruB, rollupBestSeconds: ruS)
        }
    }

    /// Record a competitive-mode result's score (units are mode-specific). Keeps
    /// only the personal best and publishes it.  Called from every competitive
    /// view's finish path, win or lose, so the "Best" column reflects skill even
    /// without a win.  (The Gold Rush coin-pit reward run is separate: it uses
    /// `recordGoldRushCoins` and has no leaderboard.)
    @discardableResult
    func recordCompetitiveScore(_ modeID: String, _ score: Int) -> Bool {
        guard score > 0 else { return false }
        let isBest = score > minigameBests[modeID, default: 0]
        if isBest { minigameBests[modeID] = score }
        syncMinigameStats()
        // Two competitive bests carry a trophy — Paint Ball coverage % and
        // King of the Hill hold-seconds (their score arg IS the stored best
        // unit, matching TrophyBackfill).  Other modes' bests have no trophy
        // (their trophies are win-count based) so recording is a no-op switch
        // default (S1-T3).
        switch modeID {
        case "paintball": recordMinigameBestTrophy(.paintballBestCoverage)
        case "koth":      recordMinigameBestTrophy(.kothBestHoldSeconds)
        default: break
        }
        return isBest
    }

    /// Record a finished Pinball game — updates the best + pays a new-best bonus.
    @discardableResult
    func recordPinballScore(_ s: Int) -> Bool {
        guard s > 0 else { return false }
        let isBest = s > pinballBest
        if isBest { pinballBest = s; addCoins(Self.minigameBestBonus) }
        syncMinigameStats()
        // pinball_score_10k / _50k / _150k ride pinballBest (S1-T3).
        recordMinigameBestTrophy(.pinballBestScore)
        return isBest
    }

    /// Record a Gold Rush haul — updates the best + pays a new-best bonus.
    @discardableResult
    func recordGoldRushCoins(_ c: Int) -> Bool {
        guard c > 0 else { return false }
        goldrushCoinsTotal += c   // lifetime tally (called once per run; tick guards re-entry)
        let isBest = c > goldrushBest
        if isBest { goldrushBest = c; addCoins(Self.minigameBestBonus) }
        syncMinigameStats()
        // Naming trap: goldrushBest/goldrushCoinsTotal are the Coin Pit
        // reward run — coinpit_catch_90 / econ_pit_boss ride them (S1-T3).
        recordCoinPitTrophies()
        return isBest
    }

    /// Record a finished Roll Up run — keeps the best height (meters) and the
    /// duration (seconds) of that best run.  Height is primary; on a tie a
    /// LONGER run wins (the leaderboard's Time board ranks by endurance).
    /// Returns whether the height was a new personal best.  The caller owns the
    /// coin payout; this just keeps the record and publishes it.
    @discardableResult
    func recordRollUpRun(height: Int, seconds: Int) -> Bool {
        guard height > 0 else { return false }
        let prevBest = minigameBests["rollup", default: 0]
        let isBest = height > prevBest
        if isBest {
            minigameBests["rollup"] = height
            rollupBestSeconds = max(0, seconds)
        } else if height == prevBest && seconds > rollupBestSeconds {
            rollupBestSeconds = max(0, seconds)   // same height, longer run → keep it
        }
        syncMinigameStats()
        // rollup_100m / rollup_500m ride minigameBests["rollup"] (S1-T3).
        recordMinigameBestTrophy(.rollupBestHeight)
        return isBest
    }

    /// Record a finished Disco Ball run — keeps the per-difficulty crossings
    /// best and pays a new-best bonus (S1-T4 reroute of DiscoBallView's former
    /// in-view `minigameBests` write).  `bestKey` is the difficulty-scoped slot
    /// the view already computes ("discoeasy" / "disco" / "discohard"); it is
    /// the sole source of truth for which slot is written, exactly matching the
    /// keys `TrophyBackfill.snapshot` derives from.  The view still owns the
    /// per-crossing coin payout; this keeps the record, pays the new-best
    /// bonus, publishes it, and fires the Disco trophies.  Returns whether this
    /// run set a new best for its difficulty.
    @discardableResult
    func recordDiscoResult(bestKey: String, crossings: Int,
                           crossingSeconds: Double? = nil) -> Bool {
        guard crossings > 0 else { return false }
        // Leaderboards are per difficulty: this run only competes with the
        // best for ITS difficulty.  More crossings wins; the same number in
        // less time per crossing keeps the time.  A run recorded without a
        // time counts as slowest, so it never replaces a timed tie.
        let difficulty = Self.discoDifficulty(forBestKey: bestKey)
        let avgMs = crossingSeconds.map { max(1, Int(($0 / Double(crossings) * 1000).rounded())) } ?? 0
        let previousBest = minigameBests[bestKey, default: 0]
        let previousAvg = discoBestAvgMs[difficulty.rawValue, default: 0]
        let fasterTie = crossings == previousBest && avgMs > 0
            && (previousAvg == 0 || avgMs < previousAvg)
        if crossings > previousBest || fasterTie {
            discoBestAvgMs[difficulty.rawValue] = avgMs
        }
        let isBest = crossings > minigameBests[bestKey, default: 0]
        if isBest {
            minigameBests[bestKey] = crossings
            addCoins(Self.minigameBestBonus)
        }
        syncMinigameStats()
        // This difficulty's leaderboard row (best crossings + its time).
        syncDiscoScore(difficulty)
        // disco_cross_25 (max over all 3 difficulty keys) / disco_hard_10
        // (discohard only) ride the just-written bests (S1-T4).
        recordDiscoTrophies()
        return isBest
    }

    /// Record a cleared Roll Out maze — keeps the furthest-maze-reached best
    /// (1-based) and pays a new-best bonus (S1-T4 reroute of RollOutView's
    /// former in-view `minigameBests["rollout"]` write).  The view still owns
    /// the flat per-clear coin payout; this keeps the record, pays the new-best
    /// bonus, publishes it, and fires the Roll Out trophies.  Returns whether
    /// this clear set a new best.
    @discardableResult
    func recordRollOutResult(reached: Int) -> Bool {
        guard reached > 0 else { return false }
        let isBest = reached > minigameBests["rollout", default: 0]
        if isBest {
            minigameBests["rollout"] = reached
            addCoins(Self.minigameBestBonus)
        }
        syncMinigameStats()
        // rollout_first_maze (≥1) / rollout_maze_10 (≥10) ride
        // minigameBests["rollout"] (S1-T4).
        recordRollOutTrophies()
        return isBest
    }

    /// Add seconds spent in Zen Garden, pay a small capped time reward, and
    /// publish the total to the leaderboard.
    func addZenSeconds(_ s: Int) {
        guard s > 0 else { return }
        zenSeconds += s
        let reward = CoinPayouts.zen(seconds: s)   // solo: no coins
        if reward > 0 { addCoins(reward) }
        syncMinigameStats()
        // zen_hour / zen_10_hours ride the cumulative zenSeconds tally (S1-T3).
        recordZenTrophies()
    }

    /// Spend coins.  Returns false (no-op) if balance is insufficient.
    @discardableResult
    func spendCoins(_ amount: Int) -> Bool {
        guard amount >= 0 else { return false }
        guard coinBalance >= amount else { return false }
        coinBalance -= amount
        return true
    }

    // ── Gold Rush tickets ───────────────────────────────────────────────
    /// ECONOMY: one ticket per competitive-minigame win.  A Gold Rush round
    /// is bought up front on the stake overlay: each 30-second block costs
    /// `CoinPayouts.goldRushTicketCost` (5) tickets, and you can buy as many
    /// blocks as you can afford.  The only in-round upsell is the ×2-coins
    /// boost — `CoinPayouts.goldRushBoostTicketCost` (10), once per round —
    /// which doubles the PAYOUT per catch (and back-pays the haul so far).
    /// Quitting early refunds the tickets of every FULL un-played 30 s block;
    /// boost tickets never refund.  See docs/gold-rush-economy.md.
    static let maxTicketBalance = 999
    static let goldRushSecondsPerTicket: TimeInterval = 30

    /// Award tickets (competitive win; future promos).  Mirrors addCoins'
    /// guardrails — negative amounts are a programming error.
    func addTickets(_ amount: Int) {
        assert(amount >= 0, "addTickets: negative amount — use spendTickets(_:)")
        guard amount > 0 else { return }
        tickets = min(tickets + amount, Self.maxTicketBalance)
    }

    /// Record a competitive-minigame win: bump that mode's lifetime win tally
    /// and award the customary Gold Rush ticket.  Called from each competitive
    /// view's win path (replaces a bare ticket award).
    func recordCompetitiveWin(_ modeID: String) {
        minigameWins[modeID, default: 0] += 1
        addTickets(CoinPayouts.ticketsPerWin)
        syncMinigameStats()   // publish the bumped win tally to the leaderboard
        // The single win choke point — arcade + per-game win trophies (and
        // the Hard high-waters, which read the just-bumped per-difficulty
        // dict when reached via recordMinigameResult) fire here only (S1-T3).
        recordCompetitiveWinTrophies()
    }


    /// Record one finished competitive match: count the attempt (always) and the
    /// win (if won) per game+difficulty for success-rate tracking, award the
    /// difficulty-scaled payout, and on a win bump the lifetime tally + ticket.
    /// Returns the scaled payout actually banked.  See docs/minigame-difficulty.md.
    @discardableResult
    func recordMinigameResult(modeID: String,
                              difficulty: MinigameDifficulty,
                              won: Bool,
                              score: Int,
                              basePayout: Int = 0,
                              draw: Bool = false,
                              placement: Int? = nil,
                              bestRivalScore: Int? = nil,
                              durationSeconds: Int? = nil) -> Int {
        let key = Self.minigameDifficultyKey(modeID, difficulty)
        // A draw is not a win and not a loss: it is left out of the attempt
        // count, so it does not pull the win rate down.
        if !draw { minigameDifficultyPlays[key, default: 0] += 1 }
        if won {
            minigameDifficultyWins[key, default: 0] += 1
            recordCompetitiveWin(modeID)
        }
        if score > minigameDifficultyBests[key, default: 0] {
            minigameDifficultyBests[key] = score
        }
        // Publish this game+difficulty's wins/best to the per-difficulty
        // leaderboard (best-effort; a no-op when signed out).
        let rowWins = minigameDifficultyWins[key, default: 0]
        let rowBest = minigameDifficultyBests[key, default: 0]
        Task {
            try? await SocialClient.shared.syncMinigameScore(
                game: modeID, difficulty: difficulty.rawValue,
                wins: rowWins, best: rowBest)
        }
        // Coins come from the one payout table (1–3 a game); `basePayout` is
        // no longer used for coins and is kept only so older callers compile.
        let payout = CoinPayouts.competitive(modeID: modeID, won: won, draw: draw,
                                             placement: placement, difficulty: difficulty)
        if payout > 0 { addCoins(payout) }
        var properties: [String: AnyEncodable] = [
            "game":        .string(modeID),
            "difficulty":  .string(difficulty.rawValue),
            "won":         .bool(won),
            "draw":        .bool(draw),
            "payout":      .int(payout),
            "score":       .int(score),
            "ai_version":  .int(OpponentTuning.version),
        ]
        if let placement       { properties["placement"]        = .int(placement) }
        if let bestRivalScore  { properties["best_rival_score"] = .int(bestRivalScore) }
        if let durationSeconds { properties["duration_s"]       = .int(durationSeconds) }
        AnalyticsClient.shared.track("minigame_result", properties: properties)
        return payout
    }

    /// Observed win-rate for a game+difficulty (wins / attempts), or nil if it's
    /// never been played.  Drives manual calibration of the difficulty/payout
    /// tables against `MinigameDifficulty.targetWinRate`.
    func minigameSuccessRate(_ modeID: String, _ difficulty: MinigameDifficulty) -> Double? {
        let key = Self.minigameDifficultyKey(modeID, difficulty)
        let plays = minigameDifficultyPlays[key, default: 0]
        guard plays > 0 else { return nil }
        return Double(minigameDifficultyWins[key, default: 0]) / Double(plays)
    }

    /// Composite key for the per game+difficulty tracking dictionaries.
    static func minigameDifficultyKey(_ modeID: String, _ difficulty: MinigameDifficulty) -> String {
        "\(modeID)|\(difficulty.rawValue)"
    }

    /// Spend tickets.  Returns false (no-op) if the balance is short.
    @discardableResult
    func spendTickets(_ amount: Int) -> Bool {
        guard amount >= 0 else { return false }
        guard tickets >= amount else { return false }
        tickets -= amount
        return true
    }

    // MARK: - Daily reward / login streak

    /// Coins granted on each day of the 7-day cycle (day 1 … day 7).  After
    /// day 7 the ladder repeats from the top, but `dailyStreak` keeps climbing
    /// so an unbroken streak still reads as a big number in the HUD.
    ///
    /// ECONOMY: a perfect week pays 105 — a top-up, not a wage: ~14% of a
    /// Standard-tier (750) skin under the 2026-07 reprice.  Tuned down
    /// 2026-06-11 from [25,40,60,80,100,150,300] (= 755/week).
    static let dailyRewardLadder: [Int] = [5, 8, 10, 12, 15, 20, 35]

    /// True when the player hasn't yet claimed today's reward.
    var dailyRewardAvailable: Bool {
        guard let last = lastDailyClaim else { return true }
        return !Calendar.current.isDateInToday(last)
    }

    /// The streak the player is *currently* riding, accounting for a missed
    /// day: 0 before the first claim or once a day has been skipped; equal to
    /// `dailyStreak` while still alive (claimed today or yesterday).  This is
    /// the value the HUD should display.
    var liveStreak: Int {
        guard let last = lastDailyClaim else { return 0 }
        let cal = Calendar.current
        if cal.isDateInToday(last) || cal.isDateInYesterday(last) { return dailyStreak }
        return 0                                   // a day was skipped — streak broken
    }

    /// What `dailyStreak` becomes on the next claim: extend a live streak, else
    /// restart at day 1.
    private var nextDailyStreak: Int { liveStreak + 1 }

    /// 1-based day in the 7-day cycle the *next* claim will land on.
    var nextDailyRewardDay: Int { ((nextDailyStreak - 1) % Self.dailyRewardLadder.count) + 1 }

    /// Coins the *next* claim will grant.
    var nextDailyRewardAmount: Int {
        Self.dailyRewardLadder[(nextDailyStreak - 1) % Self.dailyRewardLadder.count]
    }

    /// Coins granted on a given 1-based cycle day — for rendering the ladder.
    func dailyReward(forDay day: Int) -> Int {
        Self.dailyRewardLadder[(max(1, day) - 1) % Self.dailyRewardLadder.count]
    }

    /// Claim today's reward.  No-op (returns nil) if already claimed today.
    /// On success: advances the streak, banks the coins via `addCoins`, stamps
    /// the claim time, and returns the amount granted.
    @discardableResult
    func claimDailyReward() -> Int? {
        guard dailyRewardAvailable else { return nil }
        let newStreak = nextDailyStreak
        let amount = Self.dailyRewardLadder[(newStreak - 1) % Self.dailyRewardLadder.count]
        dailyStreak = newStreak
        lastDailyClaim = Date()
        // `.daily` counts toward play-earned coins (§6 item 4 excludes only
        // IAP / refund / gift-compensation); the claim itself feeds the
        // lifetime claim counter (§6 item 5 → `econ_punch_card`).
        addCoins(amount, source: .daily)
        trophyStats.recordDailyRewardClaim()
        // Fire the daily login-reward trophy metrics (S1-T2), after the
        // claim counter and streak are both updated above.
        recordDailyRewardTrophies()
        return amount
    }

    // MARK: - Starter Pack offer

    // The one-time $1.99 welcome offer: 500 coins + the Aurora ball, trail
    // and boundary (`starterPackContents`, free-granted so Sell Back keeps
    // but never refunds them).  `starterPackClaimed` = rewards delivered
    // (gates the once-only coins in StoreKitManager); `starterPackDismissed`
    // = "No thanks" opt-out of the offer UI.  Past buyers are re-granted the
    // items (never the coins) on restore.  The Aurora collection itself
    // remains a coin-buyable bundle.

    /// Coin balance that first arms the welcome offer.  Set past the tutorial's
    /// natural take (~30–50 coins from L1–10 clears) plus a chunk of free play
    /// — a few minigame wins or ~45 min of climb at current earn rates — so the
    /// offer lands once the player is invested and has glimpsed the shop, not in
    /// the first thirty seconds.  Still reachable within a session, so the
    /// 48-hour window stays meaningful.
    static let starterPackTriggerCoins = 250

    /// What the Starter Pack grants besides its 500 coins: the Aurora ball,
    /// trail and boundary.  Not a catalogue collection (the full Aurora
    /// collection stays on sale for coins); granted free via
    /// `grantBundleFree(_:recordAsOwnedBundle: false)`.
    static let starterPackContents = CosmeticBundle(
        id:             "starterpack-aurora",
        displayName:    "Aurora",
        tagline:        "Starter Pack",
        contentSummary: "Aurora ball · Aurora trail · Aurora boundary",
        balls:  [.aurora],
        goals:  [],
        trails: [.aurora],
        floors: [],
        pits:   [],
        music:  [],
        boundaries: [.aurora]
    )

    /// True when the player already owns every Starter Pack item — the
    /// offer is then suppressed (nothing left to give but coins).
    var ownsStarterPackItems: Bool {
        let p = Self.starterPackContents
        return p.balls.allSatisfy { isOwned($0) }
            && p.trails.allSatisfy { isOwned($0) }
            && p.boundaries.allSatisfy { isOwned($0) }
    }

    /// Fires once: true the first time `coinBalance` reaches
    /// `starterPackTriggerCoins` AND the player hasn't claimed or permanently
    /// dismissed the offer yet.  HomeView observes `coinBalance` and checks
    /// this to auto-present the sheet.  Suppressed when the player already owns
    /// all three Starter Pack items (Aurora ball, trail and boundary).
    var shouldTriggerStarterPack: Bool {
        !starterPackClaimed && !starterPackDismissed
            && starterPackShownAt == nil && coinBalance >= Self.starterPackTriggerCoins
            && !ownsStarterPackItems
    }

    /// True while the 48-hour countdown is still ticking — the offer sheet
    /// is still worth showing (e.g., player re-opens the app mid-window).
    /// Goes false early if the player coin-buys all three Starter Pack items
    /// mid-window.
    var starterPackOfferActive: Bool {
        guard !starterPackClaimed, !starterPackDismissed,
              let shownAt = starterPackShownAt else { return false }
        return Date().timeIntervalSince(shownAt) < 48 * 3_600
            && !ownsStarterPackItems
    }

    /// Seconds remaining in the 48-hour offer window (0 when expired/unclaimed).
    var starterPackSecondsRemaining: TimeInterval {
        guard let shownAt = starterPackShownAt else { return 0 }
        return max(0, 48 * 3_600 - Date().timeIntervalSince(shownAt))
    }

    // MARK: - Ratings prompt

    /// Request an App Store review if all three conditions are met:
    ///   1. `win` is true — only prompt on a positive emotional moment.
    ///   2. Player has cleared at least level 5 on the main climb.
    ///   3. We haven't prompted in the last 30 days.
    ///
    /// Apple enforces a hard cap of 3 prompts per 365 days per app; this gate
    /// is stricter so we use those slots on genuinely engaged players.
    func maybeRequestReview(after win: Bool) {
        guard win,
              highestUnlocked >= 5,
              Date().timeIntervalSince(lastReviewPromptDate ?? .distantPast) > Timing.reviewCooldownSecs
        else { return }
        lastReviewPromptDate = Date()
        Task { @MainActor in
            if let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                AppStore.requestReview(in: scene)   // iOS 16+ replacement for SKStoreReviewController
            }
        }
    }

    // MARK: - Challenge Track progression

    /// Record that the player cleared `level` in the given Challenge Track.
    /// • Advances `trackProgress[trackID]` only when the new level beats the
    ///   stored high-water mark (safe to call on every completion event).
    /// • When level 100 is cleared for the first time the paired reward
    ///   bundle is granted and the track is marked complete.
    func advanceTrackProgress(trackID: String, to level: Int) {
        let previous = trackProgress[trackID] ?? 0
        guard level > previous else { return }
        trackProgress[trackID] = level
        if level >= 100, !completedTracks.contains(trackID) {
            completedTracks.insert(trackID)
            deliverTrackReward(for: trackID)
        }
        // A genuine progress advance (and possibly a completion just above) —
        // fire the track trophy metrics once (S1-T2).
        recordTrackTrophies()
    }

    /// Grant the cosmetic bundle paired with a completed Challenge Track.
    /// Uses the mapping defined in `ChallengeTrackMode.rewardBundleID(for:)`.
    /// Idempotent — no-op when the bundle is already owned or the track
    /// has no paired bundle yet (future tracks may be planned but not built).
    func deliverTrackReward(for trackID: String) {
        guard let bundleID = ChallengeTrackMode.rewardBundleID(for: trackID),
              let bundle   = CosmeticBundle.catalogue.first(where: { $0.id == bundleID }),
              !ownedBundles.contains(bundleID)
        else { return }
        bundle.grantContents(to: self)
        ownedBundles.insert(bundleID)
    }

    /// Gift an entire bundle for free (the post-tutorial Standard-bundle reward,
    /// the Starter Pack's three Aurora items).  Grants every item, marks them all
    /// as `freeGrantedItems` so Sell Back keeps them and never refunds them
    /// (un-redeemable), and records the bundle as owned.  Does NOT charge coins.
    ///
    /// Items the player already coin-bought are compensated at `sellBackValue`
    /// — exactly what Sell Back would have paid (half the current `coinCost`,
    /// capped at the recorded paid price) — up front, then free-marked with the
    /// rest: the gift must never confiscate Sell Back value the player paid
    /// for, and must never pay MORE than Sell Back would (else gifting becomes
    /// its own mint).  Refunding (rather than leaving paid items unmarked) is
    /// deliberate: a gift must never leave a player poorer than Sell Back
    /// would have.  (`freeGrantedItems` is keyed by each item's unique id, so
    /// marking one item never touches a same-named item in another slot.)
    func grantBundleFree(_ bundle: CosmeticBundle, recordAsOwnedBundle: Bool = true) {
        var compensation = 0
        func compensate<Item: CosmeticItem>(_ items: [Item]) {
            for item in items
            where isOwned(item) && item.isSellable && !isFreeGranted(item) {
                compensation += sellBackValue(item)
                // Compensated + about to be free-marked — the item can never
                // be sold again, so its paid-price record is done.
                paidPrices.removeValue(forKey: Self.paidPriceKey(item))
            }
        }
        compensate(bundle.balls); compensate(bundle.goals); compensate(bundle.trails)
        compensate(bundle.floors); compensate(bundle.pits); compensate(bundle.offeredMusic)
        compensate(bundle.boundaries)
        // Refund-shaped credit (PR #114), not income — gift compensation
        // never counts toward the play-earned trophy counter (§6 item 4).
        if compensation > 0 { addCoins(compensation, source: .giftCompensation) }
        bundle.grantContents(to: self)
        markFreeGranted(bundle.balls);  markFreeGranted(bundle.goals)
        markFreeGranted(bundle.trails); markFreeGranted(bundle.floors)
        markFreeGranted(bundle.pits);   markFreeGranted(bundle.offeredMusic)
        markFreeGranted(bundle.boundaries)
        // A partial grant (the Starter Pack's three Aurora items) is not a
        // catalogue bundle, so it must not be recorded as an owned bundle —
        // that would count toward "collections completed".
        if recordAsOwnedBundle { ownedBundles.insert(bundle.id) }
    }

    // MARK: - Completionist tracking

    /// Set of bundle IDs where the player owns every item in the bundle.
    /// Includes bundles explicitly purchased as a unit (`ownedBundles`) AND
    /// any bundle where all individual items are independently owned.  Empty
    /// arrays in a bundle (e.g. no music track) count as satisfied — vacuous
    /// truth via `allSatisfy`.
    ///
    /// Used by HomeView to render the completionist aura ring behind the live
    /// ball, and by CosmeticShopView to fire the collection-complete toast.
    var completedBundleIDs: Set<String> {
        var completed = ownedBundles   // bought-as-a-unit bundles are always complete
        for bundle in CosmeticBundle.catalogue {
            guard !completed.contains(bundle.id) else { continue }
            let allOwned =
                bundle.balls.allSatisfy  { isOwned($0) } &&
                bundle.goals.allSatisfy  { isOwned($0) } &&
                bundle.trails.allSatisfy { isOwned($0) } &&
                bundle.floors.allSatisfy { isOwned($0) } &&
                bundle.pits.allSatisfy   { isOwned($0) } &&
                bundle.offeredMusic.allSatisfy  { isOwned($0) } &&
                bundle.boundaries.allSatisfy { isOwned($0) }
            if allOwned { completed.insert(bundle.id) }
        }
        return completed
    }

    /// True if the player owns this cosmetic item.  Starter items are
    /// implicitly owned regardless of set membership.
    func isOwned<Item: CosmeticItem>(_ item: Item) -> Bool {
        if item.tier == .starter { return true }
        switch item {
        case let s as BallSkin:    return s == BallSkin.starter    || ownedBallSkins.contains(s.rawValue)
        case let g as GoalSkin:    return g == GoalSkin.starter    || ownedGoals.contains(g.rawValue)
        case let t as TrailColor:  return t == TrailColor.starter  || ownedTrails.contains(t.rawValue)
        case let f as Floor:       return f == Floor.starter       || ownedFloors.contains(f.rawValue)
        case let p as Pit:         return p == Pit.starter         || ownedPits.contains(p.rawValue)
        case let b as Boundary:    return b == Boundary.starter    || ownedBoundaries.contains(b.rawValue)
        case let m as MusicTrack:  return m == MusicTrack.starter  || ownedMusic.contains(m.rawValue)
        default: return false
        }
    }

    /// Grant ownership of a cosmetic without charging coins (tutorial
    /// reward, IAP unlock, bundle purchase, etc.).
    func grant<Item: CosmeticItem>(_ item: Item) {
        switch item {
        case let s as BallSkin:    ownedBallSkins.insert(s.rawValue)
        case let g as GoalSkin:    ownedGoals.insert(g.rawValue)
        case let t as TrailColor:  ownedTrails.insert(t.rawValue)
        case let f as Floor:       ownedFloors.insert(f.rawValue)
        case let p as Pit:         ownedPits.insert(p.rawValue)
        case let b as Boundary:    ownedBoundaries.insert(b.rawValue)
        case let m as MusicTrack:  ownedMusic.insert(m.rawValue)
        default: break
        }
        // The single "cosmetic acquired" choke point — every ownership
        // trophy (balls/items/collection/bundle counts) fires here (S1-T5).
        // Bundle/Pack grants route each member through here too, so a bundle
        // completing (or its final member landing) re-evaluates counts.
        recordCosmeticOwnershipTrophies()
    }

    /// Attempt to purchase a cosmetic with coins.  Returns true on
    /// success, false if already owned or insufficient balance.
    @discardableResult
    func purchase<Item: CosmeticItem>(_ item: Item) -> Bool {
        if isOwned(item) { return false }
        guard spendCoins(item.coinCost) else { return false }
        // Full price paid — clear any stale discounted-price record so Sell
        // Back refunds the full cost.
        paidPrices.removeValue(forKey: Self.paidPriceKey(item))
        grant(item)   // records ownership-count trophies
        // First coin spend on a cosmetic — cosmetic_first_buy (S1-T5).
        recordCosmeticFirstBuyTrophy()
        return true
    }

    /// Record what was actually paid for each just-purchased item when the
    /// total paid is below the items' combined `coinCost`.  The discount is
    /// prorated across the items; each share is floored so the recorded sum
    /// (= a later Sell Back refund) never exceeds what was paid.
    private func recordPaidPrices<Item: CosmeticItem>(_ items: [Item], ratio: Double) {
        for item in items where item.isSellable {
            let key = Self.paidPriceKey(item)
            if ratio < 1.0 {
                paidPrices[key] = Int(Double(item.coinCost) * ratio)
            } else {
                paidPrices.removeValue(forKey: key)
            }
        }
    }

    /// Buy `bundle` for `price` coins (the Shop's discounted price or the
    /// Catalog's prorated price).  Grants every yet-unowned item and records
    /// the bundle owned.  When `price` is below the granted items' combined
    /// `coinCost`, each item's paid share is recorded so Sell Back refunds
    /// what was paid — otherwise the featured-bundle discount is a coin mint
    /// (buy at 50% off, liquidate at 100%, repeat every rotation window).
    @discardableResult
    func purchaseBundle(_ bundle: CosmeticBundle, price: Int) -> Bool {
        guard !ownedBundles.contains(bundle.id) else { return false }
        let base = bundle.proratedPrice(in: self)   // BEFORE granting
        guard spendCoins(price) else { return false }
        if base > 0 {
            let ratio = Double(price) / Double(base)
            recordPaidPrices(bundle.balls.filter  { !isOwned($0) }, ratio: ratio)
            recordPaidPrices(bundle.goals.filter  { !isOwned($0) }, ratio: ratio)
            recordPaidPrices(bundle.trails.filter { !isOwned($0) }, ratio: ratio)
            recordPaidPrices(bundle.floors.filter { !isOwned($0) }, ratio: ratio)
            recordPaidPrices(bundle.pits.filter   { !isOwned($0) }, ratio: ratio)
            recordPaidPrices(bundle.offeredMusic.filter  { !isOwned($0) }, ratio: ratio)
            recordPaidPrices(bundle.boundaries.filter { !isOwned($0) }, ratio: ratio)
        }
        bundle.grantContents(to: self)   // each member's grant records ownership
        ownedBundles.insert(bundle.id)
        // `ownedBundles` just changed → re-evaluate bundle-completion counts
        // (a bought-as-a-unit bundle is complete the instant it's owned, and
        // its members may not all pass through `grant` if already owned).
        recordCosmeticOwnershipTrophies()
        // First coin spend on a cosmetic — cosmetic_first_buy (S1-T5).
        recordCosmeticFirstBuyTrophy()
        return true
    }

    // MARK: - Ball Packs

    /// True if the player owns this Pack.
    func ownsPack(_ pack: BallPack) -> Bool { ownedPacks.contains(pack.id) }

    /// True if this Pack is the currently-equipped cosmetic.
    func isPackEquipped(_ pack: BallPack) -> Bool { equippedPackID == pack.id }

    /// Buy a Pack with coins.  Grants every member skin individually AND
    /// records Pack ownership.  Returns false if already owned or the
    /// balance is insufficient.
    @discardableResult
    func purchasePack(_ pack: BallPack) -> Bool {
        if ownedPacks.contains(pack.id) { return false }
        let price = pack.price(in: self)
        // Packs charge 66% of the member-skin sum — record each granted
        // skin's paid share so Sell Back refunds what was paid, not the
        // full coinCost (the 34% gap was a repeatable coin mint).
        let unowned = pack.skins.filter { !isOwned($0) }
        let base = unowned.reduce(0) { $0 + $1.coinCost }
        guard spendCoins(price) else { return false }
        if base > 0 {
            recordPaidPrices(unowned, ratio: Double(price) / Double(base))
        }
        pack.grantContents(to: self)   // each member's grant records ownership
        ownedPacks.insert(pack.id)
        // `ownedPacks` just changed → re-evaluate pack_first (grant() fired
        // before the pack id was recorded, so re-run the ownership funnel).
        recordCosmeticOwnershipTrophies()
        // First coin spend on a cosmetic — cosmetic_first_buy (S1-T5).
        recordCosmeticFirstBuyTrophy()
        return true
    }

    /// Equip a whole Pack: remember it, reset the shuffle bag, and apply
    /// the first shuffled member so menus/previews immediately show a
    /// pack ball.
    func equipPack(_ pack: BallPack) {
        equippedPackID = pack.id
        packBag = []
        advancePackSkin()
        // Ball-slot equip → re-check cosmetic_full_kit (S1-T5).
        recordFullKitTrophy()
    }

    /// Equip an individual ball skin — clears any equipped Pack so the
    /// shuffle stops and this exact skin stays put.
    func equipBall(_ skin: BallSkin) {
        equippedPackID = nil
        packBag = []
        activeSkin = skin
        // Ball-slot equip → re-check cosmetic_full_kit (S1-T5).
        recordFullKitTrophy()
    }

    /// If a Pack is equipped, advance `activeSkin` to the next member via
    /// a no-repeat shuffle bag (every member appears once before any
    /// repeat).  No-op when an individual skin is equipped.  Called at
    /// the start of each attempt from `spawnBall`.
    func advancePackSkin() {
        guard let id = equippedPackID,
              let pack = BallPack.catalogue.first(where: { $0.id == id }),
              !pack.skins.isEmpty else { return }
        if packBag.isEmpty {
            packBag = pack.skins.shuffled()
            // Avoid showing the same skin twice across a bag refill.
            if pack.skins.count > 1, packBag.first == activeSkin {
                packBag.append(packBag.removeFirst())
            }
        }
        activeSkin = packBag.removeFirst()
    }

    // MARK: - Persistence helpers (UserDefaults can't store [Int: T] directly)

    private func saveStringSet(_ set: Set<String>, forKey key: String) {
        defaults.set(Array(set), forKey: key)
    }

    private static func loadStringSet(forKey key: String, _ defaults: UserDefaults) -> Set<String> {
        guard let arr = defaults.array(forKey: key) as? [String] else {
            return []
        }
        return Set(arr)
    }

    private func save(_ dict: [Int: Int], intValueDict key: String) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: dict.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            defaults.set(data, forKey: key)
        }
    }

    private func save(_ dict: [Int: Double], doubleValueDict key: String) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: dict.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            defaults.set(data, forKey: key)
        }
    }

    private func save(_ dict: [Int: Set<Int>], setDict key: String) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: dict.map { (String($0.key), Array($0.value)) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadIntValueDict(key: String, _ defaults: UserDefaults) -> [Int: Int] {
        guard let data = defaults.data(forKey: key),
              let stringKeyed = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { entry in
            Int(entry.key).map { k in (k, entry.value) }
        })
    }

    private static func loadDoubleValueDict(key: String, _ defaults: UserDefaults) -> [Int: Double] {
        guard let data = defaults.data(forKey: key),
              let stringKeyed = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { entry in
            Int(entry.key).map { k in (k, entry.value) }
        })
    }

    private static func loadSetDict(key: String, _ defaults: UserDefaults) -> [Int: Set<Int>] {
        guard let data = defaults.data(forKey: key),
              let stringKeyed = try? JSONDecoder().decode([String: [Int]].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { entry in
            Int(entry.key).map { k in (k, Set(entry.value)) }
        })
    }

    /// Persist a [String: Int] dictionary (e.g. trackProgress) to UserDefaults.
    /// Keys are already strings so no conversion is needed.
    private func save(_ dict: [String: Int], trackProgressKey key: String) {
        if let data = try? JSONEncoder().encode(dict) {
            defaults.set(data, forKey: key)
        }
    }

    /// Load a [String: Int] dictionary from UserDefaults.
    private static func loadTrackProgress(key: String, _ defaults: UserDefaults) -> [String: Int] {
        guard let data = defaults.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return dict
    }
}

// ---------------------------------------------------------------------------
// MinigameDifficulty — how hard the competitive-minigame AI plays.
//
// The engines (GoldRushEngine today; others as they adopt the engine pattern)
// take raw multipliers rather than this enum, so they stay preference-free and
// headless-testable.  Their default of 1.0 equals .hard — also what the QE3 §7
// performance baseline measures (the busiest AI).
//
// FEEL IS TUNABLE: the two scale tables below are the only knobs.  .hard is
// the original pre-difficulty AI; .normal is the default.
// ---------------------------------------------------------------------------
// ===========================================================================
// CoinPayouts — EVERY minigame coin payout, in one place (2026-11 rebalance).
//
// The rule (round 3): solo minigames pay no coins; a competitive game pays
// 1 / 2 / 3 coins on Easy / Normal / Hard, whatever the result.  A
// competitive WIN also earns 1 ticket (a loss or draw earns none), and 5
// tickets buy a Gold Rush round — the one place to earn a large amount
// (about 100 coins a round).  Cosmetics cost 750–1,500 coins and are
// unchanged.
//
// To retune: change a number here and rebuild.  Nothing else in the app
// computes a minigame coin amount.
// ===========================================================================
enum CoinPayouts {

    // Solo minigames pay NO coins.  Competitive minigames pay a small fixed
    // amount by DIFFICULTY, whatever the result; a win also earns a ticket.
    // Gold Rush (paid for with tickets) is the one place to earn more.
    // Change a number here and rebuild; nothing else computes a minigame
    // payout.

    /// The most any one minigame game pays.
    static let minigameMax = 3

    // ---- Competitive minigames (Sumo Survival, Paint Ball, Smash and Grab,
    //      Marble Cup, King of the Hill, and Snacky's Easy/Normal/Hard) -----
    //      The same for a win, a loss, a draw or any placement.

    static let competitiveEasy   = 1
    static let competitiveNormal = 2
    static let competitiveHard   = 3
    /// Tickets for a competitive WIN.  A loss or a draw earns none.
    static let ticketsPerWin = 1

    /// Coins for one competitive game at `difficulty`.
    static func competitiveCoins(_ difficulty: MinigameDifficulty) -> Int {
        switch difficulty {
        case .easy:   return competitiveEasy
        case .normal: return competitiveNormal
        case .hard:   return competitiveHard
        }
    }

    /// Coins for one competitive game.  The result (`won`, `draw`,
    /// `placement`) no longer changes the amount; the parameters are kept so
    /// callers need not change.
    static func competitive(modeID: String, won: Bool, draw: Bool = false,
                            placement: Int?, difficulty: MinigameDifficulty) -> Int {
        competitiveCoins(difficulty)
    }

    // ---- Solo minigames (Roll Up, Disco Ball, Zen Garden, Snacky Solo) ----
    //      No coins.  The functions stay so callers need not change.

    /// What every solo minigame pays.
    static let solo = 0
    static func rollUp(meters: Int) -> Int { solo }
    static func disco(crossings: Int) -> Int { solo }
    static func zen(seconds: Int) -> Int { solo }

    /// Roll Out (held back from 1.0) is a solo game too.
    static let rollOutClear = solo

    /// A new personal best in a minigame no longer pays a bonus.  The best is
    /// still recorded and shown.
    static let personalBestBonus = 0

    // ---- Gold Rush (paid for with tickets) ------------------------------

    /// Tickets for one Gold Rush round (30 seconds of falling coins).  Five
    /// competitive wins buy one round.  Each extra 30 seconds costs the same.
    static let goldRushTicketCost = 5
    /// Tickets for the in-round ×2-coins boost: two rounds' worth, as before
    /// (it was 2 tickets when a round cost 1).
    static let goldRushBoostTicketCost = 2 * goldRushTicketCost
    /// Each coin caught is worth this much (×2 after the boost).  One round
    /// drops 100 coins over 30 seconds, so a strong round catches 80–100 and
    /// an average round about 50–70.  (BallGameView's `coinPitPayoutPerCoin`.)
    static let goldRushPerCoin = 1
}

enum MinigameDifficulty: String, CaseIterable, Identifiable {
    case easy, normal, hard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .easy:   return "Easy"
        case .normal: return "Normal"
        case .hard:   return "Hard"
        }
    }

    // Opponent strength per difficulty lives in `OpponentTuning` (below) —
    // one table for all six competitive minigames.

    // Coin payouts per difficulty live in `CoinPayouts` (above).


    /// The win rate each difficulty is designed to land near for an average
    /// player.  Documentation and test-report target only; nothing in the game
    /// reads it.  Retune `OpponentTuning` when real results drift from these.
    var targetWinRate: Double {
        switch self {
        case .easy:   return 0.70
        case .normal: return 0.50
        case .hard:   return 0.30
        }
    }
}

// ===========================================================================
// OpponentTuning — EVERY opponent tuning number, in one place.
//
// To retune: change a value here, raise `version` by one, rebuild.  All six
// competitive minigames (Snacky, Sumo Survival, Paint Ball, Smash and
// Grab, Marble Cup, King of the Hill) read these and nothing else.
// ===========================================================================
enum OpponentTuning {

    /// Tuning-version number.  Sent with every finished round as `ai_version`
    /// so results before and after a change can be told apart.  RAISE IT BY
    /// ONE whenever any number in this table changes.
    static let version = 4

    /// The human limits of one opponent.
    struct Limits {
        /// Seconds between something happening and the opponent acting on it.
        let reactionDelaySeconds: Double
        /// It aims off-target by up to this many degrees either way.
        let aimErrorDegrees: Double
        /// A visible mistake happens about this often (seconds)…
        let mistakeEverySeconds: Double
        /// …and lasts this long (seconds).
        let mistakeLengthSeconds: Double
        /// Share of the game's full opponent push it uses (1.0 = everything).
        let effort: Double
        /// Smash and Grab only: share of top speed it may reach.
        let smashGrabTopSpeed: Double
        /// Sumo Survival only: how hard it leans into a shove (a firm player
        /// tilt is about 0.8 to 1.0).
        let sumoShove: Double
        /// King of the Hill only: how many opponents go for the zone at once.
        /// The rest stay close and harass.  Same for every opponent in a round.
        let kothContenders: Int
    }

    /// One difficulty is a RANGE, not a single opponent.  At the start of a
    /// round every opponent draws its own skill inside the range (see
    /// `dealSkills`), so a round has one clumsy opponent, one average and one
    /// sharp.  `clumsy` is the weakest an opponent of this difficulty can be,
    /// `sharp` the strongest.
    struct Band {
        let clumsy: Limits
        let sharp: Limits
    }

    // EASY — clumsy, slow to react, often wrong.  Visible errors, including
    // getting itself knocked out.
    static let easyBand = Band(
        clumsy: Limits(reactionDelaySeconds: 0.75, aimErrorDegrees: 48,
                       mistakeEverySeconds: 2.5,   mistakeLengthSeconds: 1.3,
                       effort: 0.28, smashGrabTopSpeed: 0.55, sumoShove: 0.20,
                       kothContenders: 1),
        sharp:  Limits(reactionDelaySeconds: 0.50, aimErrorDegrees: 30,
                       mistakeEverySeconds: 4.5,   mistakeLengthSeconds: 0.9,
                       effort: 0.42, smashGrabTopSpeed: 0.70, sumoShove: 0.32,
                       kothContenders: 1))

    // NORMAL — a fair match for a typical player.
    static let normalBand = Band(
        clumsy: Limits(reactionDelaySeconds: 0.42, aimErrorDegrees: 22,
                       mistakeEverySeconds: 6,     mistakeLengthSeconds: 0.7,
                       effort: 0.50, smashGrabTopSpeed: 0.78, sumoShove: 0.42,
                       kothContenders: 2),
        sharp:  Limits(reactionDelaySeconds: 0.26, aimErrorDegrees: 12,
                       mistakeEverySeconds: 10,    mistakeLengthSeconds: 0.5,
                       effort: 0.66, smashGrabTopSpeed: 0.90, sumoShove: 0.56,
                       kothContenders: 2))

    // HARD — quick, accurate, rarely wrong, pushing nearly flat out.
    static let hardBand = Band(
        clumsy: Limits(reactionDelaySeconds: 0.20, aimErrorDegrees: 8,
                       mistakeEverySeconds: 14,    mistakeLengthSeconds: 0.35,
                       effort: 0.80, smashGrabTopSpeed: 0.94, sumoShove: 0.68,
                       kothContenders: 3),
        sharp:  Limits(reactionDelaySeconds: 0.10, aimErrorDegrees: 3,
                       mistakeEverySeconds: 26,    mistakeLengthSeconds: 0.25,
                       effort: 1.00, smashGrabTopSpeed: 1.00, sumoShove: 0.88,
                       kothContenders: 3))

    static func band(for difficulty: MinigameDifficulty) -> Band {
        switch difficulty {
        case .easy:   return easyBand
        case .normal: return normalBand
        case .hard:   return hardBand
        }
    }

    /// The limits of one opponent: `skill` 0 is the clumsy end of the
    /// difficulty's range, 1 the sharp end.
    static func limits(for difficulty: MinigameDifficulty, skill: Double = 0.5) -> Limits {
        let b = band(for: difficulty)
        let t = min(1, max(0, skill))
        func mix(_ a: Double, _ z: Double) -> Double { a + (z - a) * t }
        return Limits(
            reactionDelaySeconds: mix(b.clumsy.reactionDelaySeconds, b.sharp.reactionDelaySeconds),
            aimErrorDegrees:      mix(b.clumsy.aimErrorDegrees,      b.sharp.aimErrorDegrees),
            mistakeEverySeconds:  mix(b.clumsy.mistakeEverySeconds,  b.sharp.mistakeEverySeconds),
            mistakeLengthSeconds: mix(b.clumsy.mistakeLengthSeconds, b.sharp.mistakeLengthSeconds),
            effort:               mix(b.clumsy.effort,               b.sharp.effort),
            smashGrabTopSpeed:    mix(b.clumsy.smashGrabTopSpeed,    b.sharp.smashGrabTopSpeed),
            sumoShove:            mix(b.clumsy.sumoShove,            b.sharp.sumoShove),
            kothContenders:       b.clumsy.kothContenders)
    }

    /// The middle opponent of each difficulty (skill 0.5).
    static var easy:   Limits { limits(for: .easy) }
    static var normal: Limits { limits(for: .normal) }
    static var hard:   Limits { limits(for: .hard) }

    /// One skill (0…1) per opponent for a round.  The range is cut into
    /// `count` equal slices, one value is drawn from each, and they are handed
    /// out in random order — so three opponents are always one clumsy, one
    /// average and one sharp, and which is which changes every round.
    /// Pass a seed for a repeatable deal (the headless simulation).
    static func dealSkills(_ count: Int, seed: UInt64? = nil) -> [Double] {
        guard count > 0 else { return [] }
        var state = seed ?? UInt64.random(in: 1...UInt64.max)
        func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / 9_007_199_254_740_992.0
        }
        var skills: [Double] = []
        for slice in 0..<count {
            skills.append((Double(slice) + next()) / Double(count))
        }
        // Fisher–Yates shuffle with the same source.
        var i = skills.count - 1
        while i > 0 {
            let j = Int(next() * Double(i + 1))
            skills.swapAt(i, min(i, j))
            i -= 1
        }
        return skills
    }

    // ---- Shared by every difficulty --------------------------------------

    /// An aiming error is held this long (seconds) before a new one is picked,
    /// so the opponent really misses instead of wobbling around the target.
    static let aimErrorHoldSeconds: Double = 0.5
    /// Mistakes are not on a clock: each gap is the difficulty's
    /// `mistakeEverySeconds` stretched or shrunk by up to this share.
    static let mistakeTimingSpread: Double = 0.4

    // ======================================================================
    // Per-game numbers.  Each game has its own block below; keep a game's
    // numbers inside its block.
    // ======================================================================


    // ---- SNACKY ----------------------------------------------------------
    // Snacky (mode id "snake") replaced Comet Clash in version 1.0.

    // The balls.
    /// Snacky: radius (points) of every ball — heads and chain balls alike.
    static let snackyBallRadius: Double = 11
    /// Snacky: distance (points) along the path between two balls in a chain.
    /// A little less than a ball's width, so a chain reads as one line.
    static let snackySegmentSpacing: Double = 19
    /// Snacky: two balls touch (a hit) when their centers are closer than
    /// this share of a ball's width.  Under 1 forgives grazes.
    static let snackyHitShare: Double = 0.8
    /// Snacky: a chain never gets longer than this many balls (it still
    /// counts every orb eaten).
    static let snackyMaxSegments: Int = 150

    // Speed and steering.
    /// Snacky: the player's ball always rolls at this speed (points per second).
    static let snackyPlayerSpeed: Double = 125
    /// Snacky: how fast the player's ball can turn (degrees per second).
    static let snackyPlayerTurnDegrees: Double = 330
    /// Snacky: tilt smaller than this (share of full tilt) does not steer.
    static let snackyTiltDeadZone: Double = 0.10

    // Edges and grace.
    /// Snacky: after an edge bounce a ball cannot hit its own chain for this
    /// long (seconds), so a bounce is always survivable.
    static let snackyEdgeGraceSeconds: Double = 0.6
    /// Snacky: a head can never hit this many of its own nearest chain balls.
    static let snackyOwnSkipSegments: Int = 2

    // Orbs.
    /// Snacky: orb radius (points).
    static let snackyOrbRadius: Double = 9
    /// Snacky: orbs on the board at once in Solo.
    static let snackyOrbsSolo: Int = 1
    /// Snacky: orbs on the board at once in Easy, Normal and Hard.
    static let snackyOrbsVersus: Int = 5

    // Opponents.  They avoid chains and edges first and go for orbs second;
    // reaction delay, aim error and mistakes come from their OpponentBrain.
    /// Snacky: an opponent's speed is this share of the player's at zero
    /// effort, rising to the player's speed at full effort.
    static let snackyOpponentSpeedFloor: Double = 0.82
    /// Snacky: how fast an opponent can turn (degrees per second) at zero
    /// effort and at full effort.  Clumsy opponents turn wide.
    static let snackyTurnSlowDegrees: Double = 140
    static let snackyTurnFastDegrees: Double = 300
    /// Snacky: how far ahead an opponent looks (seconds × its speed) at zero
    /// effort and at full effort…
    static let snackyLookAheadSlowSeconds: Double = 0.45
    static let snackyLookAheadFastSeconds: Double = 1.0
    /// …but never less than this many points.
    static let snackyLookAheadMin: Double = 40
    /// Snacky: an opponent re-decides where to steer once per this share of
    /// its reaction delay (never more often than every other tick).
    static let snackyReplanDelayShare: Double = 0.33
    /// Snacky: during a mistake an opponent only looks this share of its
    /// normal distance ahead, so it reacts late and may clip a chain.
    static let snackyMistakeLookShare: Double = 0.3
    /// Snacky: no opponent makes a mistake in the first seconds of a round.
    static let snackyGraceSeconds: Double = 6
    /// Snacky: an opponent treats this many points inside an edge as blocked.
    static let snackyEdgeAvoidMargin: Double = 18
    /// Snacky: an opponent weighs headings up to this many degrees either side
    /// of where it is going…
    static let snackyCandidateSpreadDegrees: Double = 120
    /// …in this many evenly spaced headings.
    static let snackyCandidateCount: Int = 7

    // After the player is out.
    /// Snacky: the rest of the round runs this many times faster.
    static let snackySpectateSpeed: Int = 3
    /// Snacky: "Skip to result" plays at most this many seconds of the round;
    /// if opponents are still going after that, the round ends there.
    static let snackySkipMaxSeconds: Double = 60
    // (end Snacky)


    // ---- SUMO SURVIVAL ---------------------------------------------------

    /// Sumo Survival: all four marbles start on a ring this share of the way
    /// out from the center, evenly spaced.  Nobody starts in the middle.
    /// (The ring is turned as needed so no one starts on a pillar.)
    static let sumoStartRing: Double = 0.50
    /// Sumo Survival: each opponent's first target is another OPPONENT, picked
    /// at random, held this long (seconds) before it goes for whoever is nearest.
    static let sumoFirstTargetSeconds: Double = 4

    /// Sumo Survival: how well one opponent looks after itself near the rim.
    struct SumoRim {
        /// It starts pulling back once it is this share of the way out to
        /// the rim (0.55 = early and safe, 0.90 = only at the very edge).
        let startShare: Double
        /// How hard it steers back toward the center (0.3 = barely, 1.2 =
        /// drops the charge and retreats).
        let pull: Double
        /// It judges the rim from where its speed will carry it this many
        /// seconds from now.  0 = it only notices when it is already there,
        /// so a fast charge slides off.
        let lookAheadSeconds: Double
        /// During a mistake it forgets the rim and pushes this many times
        /// harder than usual — the blind charge that carries it off the edge.
        let mistakePush: Double
    }
    /// Rim sense per difficulty: the clumsy end and the sharp end of the
    /// range (each opponent sits somewhere between, by its skill).
    /// Easy opponents notice the rim late and brake weakly, so they fall off
    /// without help.  Hard opponents retreat early and anticipate their slide.
    static let sumoRimEasy   = (clumsy: SumoRim(startShare: 0.92, pull: 0.35, lookAheadSeconds: 0.00, mistakePush: 1.8),
                                sharp:  SumoRim(startShare: 0.82, pull: 0.60, lookAheadSeconds: 0.05, mistakePush: 1.5))
    static let sumoRimNormal = (clumsy: SumoRim(startShare: 0.76, pull: 0.80, lookAheadSeconds: 0.10, mistakePush: 1.3),
                                sharp:  SumoRim(startShare: 0.68, pull: 1.00, lookAheadSeconds: 0.20, mistakePush: 1.15))
    static let sumoRimHard   = (clumsy: SumoRim(startShare: 0.62, pull: 1.10, lookAheadSeconds: 0.28, mistakePush: 1.0),
                                sharp:  SumoRim(startShare: 0.55, pull: 1.30, lookAheadSeconds: 0.40, mistakePush: 1.0))

    /// One opponent's rim sense: `skill` 0 is the clumsy end, 1 the sharp end.
    static func sumoRim(for difficulty: MinigameDifficulty, skill: Double) -> SumoRim {
        let band: (clumsy: SumoRim, sharp: SumoRim)
        switch difficulty {
        case .easy:   band = sumoRimEasy
        case .normal: band = sumoRimNormal
        case .hard:   band = sumoRimHard
        }
        let t = min(1, max(0, skill))
        func mix(_ a: Double, _ z: Double) -> Double { a + (z - a) * t }
        return SumoRim(startShare:       mix(band.clumsy.startShare, band.sharp.startShare),
                       pull:             mix(band.clumsy.pull, band.sharp.pull),
                       lookAheadSeconds: mix(band.clumsy.lookAheadSeconds, band.sharp.lookAheadSeconds),
                       mistakePush:      mix(band.clumsy.mistakePush, band.sharp.mistakePush))
    }

    /// Sumo Survival: how much leaning into a hit adds to a marble's weight
    /// in a collision (both the player's tilt and an opponent's `sumoShove`).
    static let sumoPushGain: Double = 2.4
    /// Sumo Survival: every hit is this many times stronger than a plain
    /// bounce, so collisions visibly move marbles.
    static let sumoHitBoost: Double = 1.35
    /// Sumo Survival: even a slow touch throws the two marbles apart at
    /// least this fast (points per second).
    static let sumoMinKick: Double = 140
    /// Sumo Survival: the ring closes to `sumoShrinkTo` of its full size over
    /// this many seconds…
    static let sumoShrinkSeconds: Double = 24
    static let sumoShrinkTo: Double = 0.50
    /// …slowly at first and faster as the round goes on (1 = steady; higher
    /// = later and sharper).
    static let sumoShrinkCurve: Double = 1.7
    /// Sumo Survival: if the round is still going after that, the ring keeps
    /// squeezing to `sumoSqueezeTo` over this many more seconds, which ends
    /// any stand-off.
    static let sumoSqueezeSeconds: Double = 12
    static let sumoSqueezeTo: Double = 0.34
    /// Sumo Survival: after the squeeze the ring still loses this share of its
    /// full size every second, down to `sumoSmallestRing`, so two careful
    /// marbles cannot circle forever.
    static let sumoLastStandPerSecond: Double = 0.02
    static let sumoSmallestRing: Double = 0.14
    /// Sumo Survival: once the player is out, the rest of the round plays at
    /// this many times normal speed.
    static let sumoSpectateSpeed: Int = 3
    /// Sumo Survival: "Skip to result" plays at most this many seconds of the
    /// round at once; anything still standing after that goes out in order,
    /// nearest the rim first.
    static let sumoSkipMaxSeconds: Double = 60
    // (end Sumo Survival)


    // ---- KING OF THE HILL ------------------------------------------------

    /// King of the Hill: all four marbles start this share of the smaller
    /// field side away from the first zone, evenly spaced.
    static let kothStartRing: Double = 0.30
    /// King of the Hill: the opponents allowed to go for the zone change this
    /// often (seconds).
    static let kothRotateSeconds: Double = 6
    /// King of the Hill: radius of the zone (points).  A marble is 17.
    static let kothZoneRadius: Double = 36
    /// King of the Hill: opponents waiting their turn stay this far (points)
    /// from the zone's center — right beside it, not off to the side.
    static let kothWaitDistance: Double = 78
    /// King of the Hill: once the same marble has held the zone alone for this
    /// long (seconds), the waiting opponents stop waiting and go and bump it
    /// out.  Shorter = the holder is contested sooner.
    static func kothPressAfterSeconds(_ difficulty: MinigameDifficulty) -> Double {
        switch difficulty {
        case .easy:   return 3.5
        case .normal: return 1.8
        case .hard:   return 0.6
        }
    }
    /// King of the Hill: an opponent's top speed is this share of full speed
    /// at zero push, rising to full speed at full push.  Without it every
    /// opponent reaches the same top speed whatever its push share.
    static let kothTopSpeedAtZeroEffort: Double = 0.45
    /// King of the Hill: during a mistake an opponent rolls on this far
    /// (points) past the zone.
    static let kothOvershootDistance: Double = 120

    /// King of the Hill: how an opponent moves — the human clumsiness that
    /// stops it speeding up and stopping with machine precision.
    struct KothMotion {
        /// Share of its normal push it actually uses (lower = slower to get
        /// going and a lower top speed).
        let pushScale: Double
        /// Seconds for its push to build from nothing to full after it picks a
        /// new direction (no instant full-power starts).
        let rampSeconds: Double
        /// Seconds it pauses — drifting, no push — before turning when the
        /// way it wants to go swings by more than `kothTurnAngleDegrees`.
        let hesitationSeconds: Double
        /// It never brakes; it stops pushing and coasts.  It judges its
        /// coasting distance as this share of the real one, so it lets go
        /// too late and rolls past the target (1.0 = perfect, lower = bigger
        /// overshoot).
        let stopJudge: Double
    }

    /// A swing in wanted direction bigger than this (degrees) makes an
    /// opponent hesitate before turning.  Smaller corrections are followed at
    /// once.
    static let kothTurnAngleDegrees: Double = 60

    /// Per difficulty, clumsy → sharp opponent.
    static let kothMotionEasy   = (clumsy: KothMotion(pushScale: 0.42, rampSeconds: 0.65, hesitationSeconds: 0.60, stopJudge: 0.15),
                                   sharp:  KothMotion(pushScale: 0.52, rampSeconds: 0.55, hesitationSeconds: 0.45, stopJudge: 0.22))
    static let kothMotionNormal = (clumsy: KothMotion(pushScale: 0.58, rampSeconds: 0.50, hesitationSeconds: 0.40, stopJudge: 0.28),
                                   sharp:  KothMotion(pushScale: 0.68, rampSeconds: 0.42, hesitationSeconds: 0.30, stopJudge: 0.38))
    static let kothMotionHard   = (clumsy: KothMotion(pushScale: 0.74, rampSeconds: 0.38, hesitationSeconds: 0.26, stopJudge: 0.45),
                                   sharp:  KothMotion(pushScale: 0.84, rampSeconds: 0.30, hesitationSeconds: 0.16, stopJudge: 0.58))

    static func kothMotion(for difficulty: MinigameDifficulty, skill: Double) -> KothMotion {
        let band: (clumsy: KothMotion, sharp: KothMotion)
        switch difficulty {
        case .easy:   band = kothMotionEasy
        case .normal: band = kothMotionNormal
        case .hard:   band = kothMotionHard
        }
        let t = min(1, max(0, skill))
        func mix(_ a: Double, _ z: Double) -> Double { a + (z - a) * t }
        return KothMotion(pushScale:         mix(band.clumsy.pushScale, band.sharp.pushScale),
                          rampSeconds:       mix(band.clumsy.rampSeconds, band.sharp.rampSeconds),
                          hesitationSeconds: mix(band.clumsy.hesitationSeconds, band.sharp.hesitationSeconds),
                          stopJudge:         mix(band.clumsy.stopJudge, band.sharp.stopJudge))
    }
    // (end King of the Hill)


    // ---- SMASH AND GRAB --------------------------------------------------

    /// Smash and Grab: each opponent prefers a coin no other opponent is
    /// closer to, so the three do not all chase the same one.
    static let smashGrabSpreadOut = true

    /// A value for the clumsy end and the sharp end of one difficulty; each
    /// opponent gets the value at its own skill (see `dealSkills`).
    struct SmashGrabRange {
        let clumsy: Double
        let sharp: Double
        func value(skill: Double) -> Double {
            clumsy + (sharp - clumsy) * min(1, max(0, skill))
        }
    }

    /// Seconds a coin lies on the board before an opponent NOTICES it.  Until
    /// then the opponent does not go for it, so the player gets first try at
    /// fresh coins.  The strongest single lever on how many coins opponents
    /// take.
    static func smashGrabNoticeSeconds(_ d: MinigameDifficulty) -> SmashGrabRange {
        switch d {
        case .easy:   return SmashGrabRange(clumsy: 2.6,  sharp: 1.6)
        case .normal: return SmashGrabRange(clumsy: 0.9,  sharp: 0.5)
        case .hard:   return SmashGrabRange(clumsy: 0.15, sharp: 0.0)
        }
    }

    /// How far (points) an opponent can see a coin.  Beyond this it wanders
    /// until one comes into view.  A phone screen is about 390 points wide.
    /// Hard sees the whole board.
    static func smashGrabSightDistance(_ d: MinigameDifficulty) -> SmashGrabRange {
        switch d {
        case .easy:   return SmashGrabRange(clumsy: 150,     sharp: 200)
        case .normal: return SmashGrabRange(clumsy: 280,     sharp: 380)
        case .hard:   return SmashGrabRange(clumsy: 100_000, sharp: 100_000)
        }
    }

    /// Seconds an opponent coasts, not pushing, after picking up a coin.
    static func smashGrabPauseAfterCoinSeconds(_ d: MinigameDifficulty) -> SmashGrabRange {
        switch d {
        case .easy:   return SmashGrabRange(clumsy: 2.4,  sharp: 1.6)
        case .normal: return SmashGrabRange(clumsy: 1.2,  sharp: 0.8)
        case .hard:   return SmashGrabRange(clumsy: 0.15, sharp: 0.0)
        }
    }

    /// Seconds between dashes for the one opponent that dashes at the leader.
    /// (The player's own dash recharges in 1.5 seconds.)
    static func smashGrabDashEverySeconds(_ d: MinigameDifficulty) -> SmashGrabRange {
        switch d {
        case .easy:   return SmashGrabRange(clumsy: 7.0, sharp: 5.0)
        case .normal: return SmashGrabRange(clumsy: 3.5, sharp: 2.5)
        case .hard:   return SmashGrabRange(clumsy: 2.0, sharp: 1.5)
        }
    }

    /// Whether opponents take walls into account when choosing a coin.  Easy
    /// opponents do not: they head straight for a coin behind a wall and bump
    /// into it.
    static func smashGrabAvoidsWalls(_ d: MinigameDifficulty) -> Bool {
        switch d {
        case .easy:           return false
        case .normal, .hard:  return true
        }
    }
    /// A coin with a wall in the way counts as this many times farther off
    /// (for opponents that take walls into account).
    static let smashGrabBlockedCoinPenalty: Double = 3
    /// Share of its push an opponent uses while wandering with no coin in view.
    static let smashGrabWanderPush: Double = 0.6
    /// During a mistake an opponent also stops steering away from the edges,
    /// so it runs into the border.
    static let smashGrabMistakeHitsEdges = true

    // Coins knocked loose by a hit.  The faster the hit, the more drop.
    /// A DASH that connects drops this many coins at the slowest hit that
    /// counts…
    static let smashGrabDashDropMin = 3
    /// …rising to this many at `smashGrabDashFullSpeed`.
    static let smashGrabDashDropMax = 6
    /// Closing speed (points per second) at which a dash drops the most.  A
    /// dash launches at 760.
    static let smashGrabDashFullSpeed: Double = 760
    /// An ordinary bump (nobody dashing) drops coins only at or above this
    /// closing speed (points per second)…
    static let smashGrabBumpDropSpeed: Double = 360
    /// …this many coins (set to 0 for "only a dash knocks coins loose")…
    static let smashGrabBumpDropCoins = 1
    /// …and this many at or above the hard-bump speed.
    static let smashGrabHardBumpDropSpeed: Double = 560
    static let smashGrabHardBumpDropCoins = 2
    /// In a bump the faster marble is the hitter.  Their speeds into the hit
    /// must differ by at least this share of the closing speed, or nobody
    /// drops anything (an even head-on bump).
    static let smashGrabBumpHitterShare: Double = 0.3
    /// After dropping coins a marble cannot be made to drop more for this
    /// long (seconds).
    static let smashGrabDropImmunitySeconds: Double = 1.0
    // (end Smash and Grab)


    // ---- MARBLE CUP ------------------------------------------------------

    /// Marble Cup: a level score at full time goes to sudden death (next goal
    /// wins) for at most this long (seconds).  Still level after that is a
    /// draw: not a win and not a loss.
    static let marbleCupSuddenDeathSeconds = 30
    /// Marble Cup: length of a match (seconds).
    static let marbleCupMatchSeconds = 60
    /// Marble Cup: radius of the ball (points).  The marbles are 18.
    static let marbleCupBallRadius: Double = 17
    // (end Marble Cup)


    // ---- PAINT BALL ------------------------------------------------------

    /// Paint Ball: an opponent's top speed is this share of full speed at
    /// zero push, rising to full speed at full push.  Without it every
    /// opponent reaches the same top speed whatever its push share.
    static let paintBallTopSpeedAtZeroEffort: Double = 0.45
    /// Paint Ball: how many spots an opponent weighs up when choosing where
    /// to paint next — this many at zero push share…
    static let paintBallSpotsAtZeroEffort: Double = 3
    /// …plus this many more at full push share.  More spots = better choices.
    static let paintBallSpotsPerEffort: Double = 15
    /// Paint Ball: when a mistake begins, the chance the opponent heads
    /// straight for a puddle (otherwise it heads for floor it already painted).
    static let paintBallMistakePuddleChance: Double = 0.5
    /// Paint Ball: a marble climbing out of a puddle after its penalty leaves
    /// at this speed (points per second) in the direction it is going — the
    /// player's tilt, an opponent's steering.
    static let paintBallExitSpeed: Double = 170
    /// Paint Ball: a tilt weaker than this (0…1 of a full tilt) counts as "not
    /// tilting"; the last real tilt direction is used instead.
    static let paintBallExitTiltThreshold: Double = 0.12
    /// Paint Ball: if the spot just outside the puddle in that direction is
    /// off the floor or in another puddle, the direction is turned by this
    /// many degrees at a time (both ways) until a clear spot is found.
    static let paintBallExitTurnStepDegrees: Double = 20
    // (end Paint Ball)
}

// ---------------------------------------------------------------------------
// OpponentBrain — one opponent's human limits, tick by tick.  Each opponent in
// each competitive minigame owns one.  It gives the steering code four things:
//   • `perceive(_:)`   — where the target WAS one reaction delay ago;
//   • `push(...)`      — a push toward a point, aimed off by the held aiming
//                        error and scaled by effort;
//   • `isMistaking`    — true during a visible mistake (each game decides
//                        what the mistake looks like);
//   • `effort`         — the share of full push to use.
// Call `advance()` exactly once per 60 Hz tick.  All numbers come from
// `OpponentTuning`.  The random source is seedable so a headless simulation
// can be repeated.
// ---------------------------------------------------------------------------
struct OpponentBrain {

    let limits: OpponentTuning.Limits

    /// Share of full push this opponent uses.
    var effort: CGFloat { CGFloat(limits.effort) }
    /// True while the opponent is in the middle of a visible mistake.
    var isMistaking: Bool { mistakeTicksLeft > 0 }
    /// The aiming error (radians) currently being held.
    private(set) var aimError: CGFloat = 0

    private var rngState: UInt64
    private var seen: [CGPoint] = []
    private var aimHoldTicksLeft = 0
    private var mistakeTicksLeft = 0
    private var ticksUntilMistake = 0

    /// This opponent's place in its difficulty's range: 0 clumsy … 1 sharp.
    let skill: Double

    /// `skill` comes from `OpponentTuning.dealSkills` (one per opponent per
    /// round); 0.5 is the middle of the range.
    init(difficulty: MinigameDifficulty, skill: Double = 0.5, seed: UInt64? = nil) {
        self.skill = min(1, max(0, skill))
        limits = OpponentTuning.limits(for: difficulty, skill: skill)
        rngState = seed ?? UInt64.random(in: 1...UInt64.max)
        ticksUntilMistake = nextMistakeGap()
    }

    /// Ticks of reaction delay.
    var delayTicks: Int { max(0, Int((limits.reactionDelaySeconds * 60).rounded())) }

    /// Step the timers one tick.  Returns true on the tick a mistake BEGINS.
    @discardableResult
    mutating func advance() -> Bool {
        if aimHoldTicksLeft <= 0 {
            let maxError = limits.aimErrorDegrees * Double.pi / 180
            aimError = CGFloat((unitRandom() * 2 - 1) * maxError)
            aimHoldTicksLeft = max(1, Int((OpponentTuning.aimErrorHoldSeconds * 60).rounded()))
        }
        aimHoldTicksLeft -= 1

        if mistakeTicksLeft > 0 {
            mistakeTicksLeft -= 1
            return false
        }
        ticksUntilMistake -= 1
        if ticksUntilMistake <= 0 {
            mistakeTicksLeft = max(1, Int((limits.mistakeLengthSeconds * 60).rounded()))
            ticksUntilMistake = nextMistakeGap()
            return true
        }
        return false
    }

    /// Feed the true target position for this tick; get back where it was one
    /// reaction delay ago.  (Early in a round, before a full delay has passed,
    /// this is the first position it ever saw.)
    mutating func perceive(_ current: CGPoint) -> CGPoint {
        seen.append(current)
        let keep = delayTicks + 1
        if seen.count > keep { seen.removeFirst(seen.count - keep) }
        return seen[0]
    }

    /// Forget what was seen (new round, new kickoff).
    mutating func forget() { seen.removeAll(keepingCapacity: true) }

    /// A unit direction turned by the held aiming error.
    func aimed(dx: CGFloat, dy: CGFloat) -> CGVector {
        let m = hypot(dx, dy)
        guard m > 0 else { return .zero }
        let angle = atan2(dy, dx) + aimError
        return CGVector(dx: cos(angle), dy: sin(angle))
    }

    /// A push from `from` toward `target`: aimed off by the held error, at
    /// `fullPush` × effort.
    func push(from: CGPoint, toward target: CGPoint, fullPush: CGFloat) -> CGVector {
        let d = aimed(dx: target.x - from.x, dy: target.y - from.y)
        let strength = fullPush * effort
        return CGVector(dx: d.dx * strength, dy: d.dy * strength)
    }

    /// A random number in 0..<1 from this brain's own seedable source.
    mutating func unitRandom() -> Double {
        // SplitMix64.
        rngState &+= 0x9E37_79B9_7F4A_7C15
        var z = rngState
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / 9_007_199_254_740_992.0
    }

    private mutating func nextMistakeGap() -> Int {
        let spread = OpponentTuning.mistakeTimingSpread
        let factor = 1 + (unitRandom() * 2 - 1) * spread
        return max(1, Int((limits.mistakeEverySeconds * factor * 60).rounded()))
    }
}
