import StoreKit
import SwiftUI

final class GameState: ObservableObject {

    // MARK: - Published state

    @Published var currentLevel: Int {
        didSet { UserDefaults.standard.set(currentLevel, forKey: "ra_level") }
    }
    @Published var activeSkin: BallSkin {
        didSet { UserDefaults.standard.set(activeSkin.rawValue, forKey: "ra_skin") }
    }
    @Published var playerName: String {
        didSet { UserDefaults.standard.set(playerName, forKey: "ra_name") }
    }
    @Published var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "ra_haptics") }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "ra_sound") }
    }
    @Published var ballStartsAtTop: Bool {
        didSet { UserDefaults.standard.set(ballStartsAtTop, forKey: "ra_startAtTop") }
    }

    // One-time UX moments — survive resetProgress() so a returning player
    // who resets level progress isn't shown the intro/welcome again.
    @Published var seenOnboarding: Bool {
        didSet { UserDefaults.standard.set(seenOnboarding, forKey: "ra_seenOnboarding") }
    }
    @Published var seenWelcomeMoment: Bool {
        didSet { UserDefaults.standard.set(seenWelcomeMoment, forKey: "ra_seenWelcomeMoment") }
    }
    @Published var seenTutorialReward: Bool {
        didSet { UserDefaults.standard.set(seenTutorialReward, forKey: "ra_seenTutorialReward") }
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
        didSet { Self.save(bestStars, intValueDict: "ra_bestStars") }
    }
    @Published var bestTime: [Int: TimeInterval] {
        didSet { Self.save(bestTime, doubleValueDict: "ra_bestTime") }
    }
    @Published var collectedCoins: [Int: Set<Int>] {
        didSet { Self.save(collectedCoins, setDict: "ra_collectedCoins") }
    }
    @Published var highestUnlocked: Int {
        didSet { UserDefaults.standard.set(highestUnlocked, forKey: "ra_highestUnlocked") }
    }

    // ── Lives system (Sprint 4c) ───────────────────────────────────────────
    // lives             : stored count, 0…6.  May be stale w.r.t. regen —
    //                     use displayedLives for the live value.
    // lastLifeLostAt    : timestamp of the most recent life consumption.
    //                     Drives regen.  nil when lives == max.
    // unlimitedLives    : true if the $20 unlimited subscription is active.
    //                     Set by the StoreKit layer in a later PR.
    static let livesMax: Int = 6
    static let livesRegenInterval: TimeInterval = 600   // 10 minutes
    static let tutorialLevelCount: Int = 10             // L1-10 don't consume lives

    @Published var lives: Int {
        didSet { UserDefaults.standard.set(lives, forKey: "ra_lives") }
    }
    @Published var lastLifeLostAt: Date? {
        didSet {
            if let d = lastLifeLostAt {
                UserDefaults.standard.set(d, forKey: "ra_lastLifeLostAt")
            } else {
                UserDefaults.standard.removeObject(forKey: "ra_lastLifeLostAt")
            }
        }
    }
    @Published var unlimitedLives: Bool {
        didSet { UserDefaults.standard.set(unlimitedLives, forKey: "ra_unlimitedLives") }
    }

    // ── Daily reward / login streak ────────────────────────────────────────
    // dailyStreak    : consecutive days claimed, as of the last claim.  Climbs
    //                  forever; the coin ladder cycles every 7 days but the
    //                  counter keeps going, so a long streak reads big.
    // lastDailyClaim : timestamp of the most recent claim.  nil until the first
    //                  claim.  Drives both "is a reward available today" and
    //                  whether the streak is still alive (claimed yesterday).
    @Published var dailyStreak: Int {
        didSet { UserDefaults.standard.set(dailyStreak, forKey: "ra_dailyStreak") }
    }
    @Published var lastDailyClaim: Date? {
        didSet {
            if let d = lastDailyClaim {
                UserDefaults.standard.set(d, forKey: "ra_lastDailyClaim")
            } else {
                UserDefaults.standard.removeObject(forKey: "ra_lastDailyClaim")
            }
        }
    }

    // ── Starter Pack one-time offer ─────────────────────────────────────────
    // starterPackShownAt : timestamp when the offer sheet was first presented.
    //                      nil until the trigger fires (first time coinBalance
    //                      reaches 50).  Drives the 48-hour countdown.
    // starterPackClaimed : true after the player purchases OR permanently
    //                      dismisses the offer.  Once true the sheet never
    //                      shows again.
    @Published var starterPackShownAt: Date? {
        didSet {
            if let d = starterPackShownAt {
                UserDefaults.standard.set(d, forKey: "ra_starterPackShownAt")
            } else {
                UserDefaults.standard.removeObject(forKey: "ra_starterPackShownAt")
            }
        }
    }
    @Published var starterPackClaimed: Bool {
        didSet { UserDefaults.standard.set(starterPackClaimed, forKey: "ra_starterPackClaimed") }
    }

    // ── Ratings prompt ────────────────────────────────────────────────────
    // Timestamp of the last time SKStoreReviewController.requestReview was
    // called.  nil until the first time the conditions are met.  Used to
    // enforce the 30-day minimum between prompts (Apple allows at most 3
    // per 365 days regardless, but we gate more tightly).
    @Published var lastReviewPromptDate: Date? {
        didSet {
            if let d = lastReviewPromptDate {
                UserDefaults.standard.set(d, forKey: "ra_lastReviewPromptDate")
            } else {
                UserDefaults.standard.removeObject(forKey: "ra_lastReviewPromptDate")
            }
        }
    }

    // ── Cosmetic economy (Sprint 4d) ──────────────────────────────────────
    // Coins are the in-app currency.  Earned from gameplay; spent in the
    // shop to unlock cosmetic items.  Also purchasable in coin packs via
    // StoreKit (PR 4h).  No cap on balance.
    @Published var coinBalance: Int {
        didSet { UserDefaults.standard.set(coinBalance, forKey: "ra_coinBalance") }
    }

    // Owned cosmetic items per category, stored as sets of raw strings so
    // JSON round-trip is trivial.  Default ("starter") items are always
    // implicitly owned via `isOwned(_:)`, regardless of set membership.
    @Published var ownedBallSkins:   Set<String> {
        didSet { Self.saveStringSet(ownedBallSkins, forKey: "ra_ownedBallSkins") }
    }
    @Published var ownedGoals:       Set<String> {
        didSet { Self.saveStringSet(ownedGoals, forKey: "ra_ownedGoals") }
    }
    @Published var ownedTrails:      Set<String> {
        didSet { Self.saveStringSet(ownedTrails, forKey: "ra_ownedTrails") }
    }
    /// Owned Floor cosmetics (the surface the ball rolls on).
    @Published var ownedFloors: Set<String> {
        didSet { Self.saveStringSet(ownedFloors, forKey: "ra_ownedFloors") }
    }
    /// Owned Pit cosmetics (the holes the ball falls into).
    @Published var ownedPits: Set<String> {
        didSet { Self.saveStringSet(ownedPits, forKey: "ra_ownedPits") }
    }
    /// Owned bundle IDs (for the shop's "OWNED" badge — items inside
    /// each bundle are also added to their individual owned sets at
    /// purchase time, so this is purely for UI state).
    @Published var ownedBundles: Set<String> {
        didSet { Self.saveStringSet(ownedBundles, forKey: "ra_ownedBundles") }
    }
    /// Owned Ball-Pack IDs.  Buying a Pack also adds its member skins to
    /// `ownedBallSkins` (so they're individually equippable); this set
    /// is for the shop's "OWNED" state + the equip-the-whole-Pack flow.
    @Published var ownedPacks: Set<String> {
        didSet { Self.saveStringSet(ownedPacks, forKey: "ra_ownedPacks") }
    }
    @Published var ownedMusic:       Set<String> {
        didSet { Self.saveStringSet(ownedMusic, forKey: "ra_ownedMusic") }
    }

    // ── Challenge Track progress ─────────────────────────────────────────
    //
    // Each Challenge Track is a 100-level themed side quest.  Beating level
    // 100 delivers the track's paired cosmetic bundle for free (earned, not
    // purchased).  Progress survives app restarts via UserDefaults.

    /// Highest level cleared per Challenge Track: [trackID: level (1…100)].
    /// Missing key = track not yet started.  Level 100 = track complete.
    @Published var trackProgress: [String: Int] {
        didSet { Self.save(trackProgress, trackProgressKey: "ra_trackProgress") }
    }

    /// Set of Challenge Track IDs fully completed (level 100 cleared).
    /// The reward bundle is granted exactly once when a track enters this set.
    @Published var completedTracks: Set<String> {
        didSet { Self.saveStringSet(completedTracks, forKey: "ra_completedTracks") }
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
        didSet { UserDefaults.standard.set(equippedGoal.rawValue, forKey: "ra_equippedGoal") }
    }
    @Published var equippedTrail: TrailColor {
        didSet { UserDefaults.standard.set(equippedTrail.rawValue, forKey: "ra_equippedTrail") }
    }
    @Published var equippedFloor: Floor {
        didSet { UserDefaults.standard.set(equippedFloor.rawValue, forKey: "ra_equippedFloor") }
    }
    @Published var equippedPit: Pit {
        didSet { UserDefaults.standard.set(equippedPit.rawValue, forKey: "ra_equippedPit") }
    }
    @Published var equippedMusic: MusicTrack {
        didSet { UserDefaults.standard.set(equippedMusic.rawValue, forKey: "ra_equippedMusic") }
    }
    // equippedBall lives on `activeSkin` — already defined above.

    /// The currently-equipped Ball Pack, or nil when an individual ball
    /// skin is equipped.  When non-nil, `activeSkin` is driven by the
    /// pack's shuffle (see `advancePackSkin()`) and is overwritten at the
    /// start of every attempt.
    @Published var equippedPackID: String? {
        didSet {
            if let id = equippedPackID {
                UserDefaults.standard.set(id, forKey: "ra_equippedPack")
            } else {
                UserDefaults.standard.removeObject(forKey: "ra_equippedPack")
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
    init() {
        let saved = UserDefaults.standard.integer(forKey: "ra_level")
        currentLevel = max(1, saved)
        activeSkin = BallSkin(rawValue: UserDefaults.standard.string(forKey: "ra_skin") ?? "") ?? .red
        playerName = UserDefaults.standard.string(forKey: "ra_name") ?? ""
        hapticsEnabled = UserDefaults.standard.object(forKey: "ra_haptics") as? Bool ?? true
        soundEnabled = UserDefaults.standard.object(forKey: "ra_sound") as? Bool ?? true
        ballStartsAtTop = UserDefaults.standard.object(forKey: "ra_startAtTop") as? Bool ?? true
        seenOnboarding = UserDefaults.standard.bool(forKey: "ra_seenOnboarding")
        seenWelcomeMoment = UserDefaults.standard.bool(forKey: "ra_seenWelcomeMoment")
        seenTutorialReward = UserDefaults.standard.bool(forKey: "ra_seenTutorialReward")

        bestStars       = Self.loadIntValueDict(key: "ra_bestStars")
        bestTime        = Self.loadDoubleValueDict(key: "ra_bestTime")
        collectedCoins  = Self.loadSetDict(key: "ra_collectedCoins")
        let unlocked    = UserDefaults.standard.integer(forKey: "ra_highestUnlocked")
        highestUnlocked = max(currentLevel, max(1, unlocked))  // never less than currentLevel

        // Lives — default to a full bar.  `as? Int ?? Self.livesMax` covers
        // the case where no key has been written yet (fresh install).
        // `max(0, ...)` guards against a corrupt negative value.
        lives          = max(0, UserDefaults.standard.object(forKey: "ra_lives") as? Int ?? Self.livesMax)
        lastLifeLostAt = UserDefaults.standard.object(forKey: "ra_lastLifeLostAt") as? Date
        unlimitedLives = UserDefaults.standard.bool(forKey: "ra_unlimitedLives")

        // Daily reward / login streak.
        dailyStreak    = UserDefaults.standard.integer(forKey: "ra_dailyStreak")
        lastDailyClaim = UserDefaults.standard.object(forKey: "ra_lastDailyClaim") as? Date

        // Starter Pack offer state.
        starterPackShownAt = UserDefaults.standard.object(forKey: "ra_starterPackShownAt") as? Date
        starterPackClaimed = UserDefaults.standard.bool(forKey: "ra_starterPackClaimed")

        // Ratings prompt.
        lastReviewPromptDate = UserDefaults.standard.object(forKey: "ra_lastReviewPromptDate") as? Date

        // Cosmetic economy — load owned-sets to local lets first, then
        // assign to the stored properties.  We re-use the locals when
        // computing the equipped cosmetics below; referring to
        // `self.ownedGoals` directly would be a "self used before all
        // stored properties initialised" error here.
        coinBalance = max(0, UserDefaults.standard.integer(forKey: "ra_coinBalance"))
        let loadedOwnedBalls   = Self.loadStringSet(forKey: "ra_ownedBallSkins")
        let loadedOwnedGoals   = Self.loadStringSet(forKey: "ra_ownedGoals")
        let loadedOwnedTrails  = Self.loadStringSet(forKey: "ra_ownedTrails")
        let loadedOwnedFloors  = Self.loadStringSet(forKey: "ra_ownedFloors")
        let loadedOwnedPits    = Self.loadStringSet(forKey: "ra_ownedPits")
        let loadedOwnedMusic   = Self.loadStringSet(forKey: "ra_ownedMusic")
        let loadedOwnedBundles = Self.loadStringSet(forKey: "ra_ownedBundles")
        let loadedOwnedPacks   = Self.loadStringSet(forKey: "ra_ownedPacks")
        ownedBallSkins = loadedOwnedBalls
        ownedGoals     = loadedOwnedGoals
        ownedTrails    = loadedOwnedTrails
        ownedFloors    = loadedOwnedFloors
        ownedPits      = loadedOwnedPits
        ownedMusic     = loadedOwnedMusic
        ownedBundles   = loadedOwnedBundles
        ownedPacks     = loadedOwnedPacks
        trackProgress  = Self.loadTrackProgress(key: "ra_trackProgress")
        completedTracks = Self.loadStringSet(forKey: "ra_completedTracks")
        // Equipped cosmetics — load saved raw values, fall back to the
        // category's starter if the loaded item is non-starter and not
        // in the owned set.  Floor + Pit replaced the legacy
        // `BackgroundTheme` (any saved ra_equippedBackground value is
        // simply discarded — Mac requested reset-to-defaults for the
        // single existing tester).
        let savedGoal  = GoalSkin(rawValue:   UserDefaults.standard.string(forKey: "ra_equippedGoal")  ?? "")
        let savedTrail = TrailColor(rawValue: UserDefaults.standard.string(forKey: "ra_equippedTrail") ?? "")
        let savedFloor = Floor(rawValue:      UserDefaults.standard.string(forKey: "ra_equippedFloor") ?? "")
        let savedPit   = Pit(rawValue:        UserDefaults.standard.string(forKey: "ra_equippedPit")   ?? "")
        let savedMusic = MusicTrack(rawValue: UserDefaults.standard.string(forKey: "ra_equippedMusic") ?? "")
        equippedGoal  = Self.legitimise(savedGoal,  owned: loadedOwnedGoals,  starter: GoalSkin.starter)
        equippedTrail = Self.legitimise(savedTrail, owned: loadedOwnedTrails, starter: TrailColor.starter)
        equippedFloor = Self.legitimise(savedFloor, owned: loadedOwnedFloors, starter: Floor.starter)
        equippedPit   = Self.legitimise(savedPit,   owned: loadedOwnedPits,   starter: Pit.starter)
        equippedMusic = Self.legitimise(savedMusic, owned: loadedOwnedMusic,  starter: MusicTrack.starter)

        // Restore the equipped Ball Pack only if it's still owned;
        // otherwise leave it nil so the individual `activeSkin` (loaded
        // above) stays in effect.
        let savedPack  = UserDefaults.standard.string(forKey: "ra_equippedPack")
        equippedPackID = savedPack.flatMap { loadedOwnedPacks.contains($0) ? $0 : nil }
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
        Task {
            try? await SocialClient.shared.syncProgress(
                climbLevel: climb,
                highestUnlocked: unlocked,
                totalStars: stars
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

    // MARK: - Result recording

    /// Call when the player completes a level.  Stars only ever increase,
    /// times only ever decrease, collected coins never un-collect.
    func recordResult(level: Int, stars: Int, time: TimeInterval, coinIndices: Set<Int>) {
        if stars > (bestStars[level] ?? 0) {
            bestStars[level] = stars
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

    /// Current life count including any regen that has accumulated since
    /// `lastLifeLostAt`.  Read this for display + gating.  Stored `lives`
    /// only updates when `commitRegen()` or `consumeLife()` is called.
    var displayedLives: Int {
        if unlimitedLives { return Self.livesMax }
        guard lives < Self.livesMax, let last = lastLifeLostAt else { return lives }
        let elapsed = Date.now.timeIntervalSince(last)
        let regenCount = Int(elapsed / Self.livesRegenInterval)
        return min(Self.livesMax, lives + regenCount)
    }

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

    /// Decrement lives by 1.  Returns true if a life was consumed, false if
    /// the player was already at zero.  Unlimited-lives subscribers always
    /// return true without decrementing.
    ///
    /// The regen timer only starts when the player's count drops BELOW
    /// `livesMax`.  Otherwise a player with 78 stockpiled lives would
    /// see the regen clock churning the moment they lose their first one,
    /// which is confusing.  Stockpile drains silently until you hit the
    /// natural bar, then regen kicks in.
    @discardableResult
    func consumeLife() -> Bool {
        if unlimitedLives { return true }
        commitRegen()
        if lives <= 0 { return false }
        lives -= 1
        if lives < Self.livesMax && lastLifeLostAt == nil {
            lastLifeLostAt = .now
        }
        return true
    }

    /// Award lives (e.g. from rewarded ad or IAP grant).  No cap — lives
    /// stockpile unbounded so the HUD can show 6 marbles + a "+N" indicator
    /// for whatever the player has banked.
    func addLives(_ count: Int) {
        guard count > 0 else { return }
        if unlimitedLives { return }
        commitRegen()
        lives += count
        // Stockpiled lives don't need the regen timer running.  Clear it
        // so it isn't ticking through scenarios it can't affect.
        if lives >= Self.livesMax {
            lastLifeLostAt = nil
        }
    }

    // MARK: - Cosmetic economy

    /// Per-pickup coin award on first-time collection.  Each level has
    /// up to 3 currency-coins on the floor → 0…3 coins per first clear
    /// from pickups alone.
    static let coinPerPickup: Int = 1
    /// Flat coin award the first time a player clears a level.  Stacks
    /// with pickups so a perfect first clear yields `coinPerClear + 3`
    /// coins.  Subsequent clears award 0 (no farming).
    static let coinPerClear:  Int = 2

    /// Award coins to the player's balance.  Use this everywhere — never
    /// mutate coinBalance directly.
    func addCoins(_ amount: Int) {
        guard amount > 0 else { return }
        coinBalance += amount
    }

    /// Spend coins.  Returns false (no-op) if balance is insufficient.
    @discardableResult
    func spendCoins(_ amount: Int) -> Bool {
        guard amount >= 0 else { return false }
        guard coinBalance >= amount else { return false }
        coinBalance -= amount
        return true
    }

    // MARK: - Daily reward / login streak

    /// Coins granted on each day of the 7-day cycle (day 1 … day 7).  After
    /// day 7 the ladder repeats from the top, but `dailyStreak` keeps climbing
    /// so an unbroken streak still reads as a big number in the HUD.
    static let dailyRewardLadder: [Int] = [25, 40, 60, 80, 100, 150, 300]

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
        addCoins(amount)
        return amount
    }

    // MARK: - Starter Pack offer

    /// Fires once: true the first time `coinBalance` reaches 50 AND the
    /// player hasn't claimed or permanently dismissed the offer yet.
    /// HomeView observes `coinBalance` and checks this to auto-present
    /// the sheet.
    var shouldTriggerStarterPack: Bool {
        !starterPackClaimed && starterPackShownAt == nil && coinBalance >= 50
    }

    /// True while the 48-hour countdown is still ticking — the offer sheet
    /// is still worth showing (e.g., player re-opens the app mid-window).
    var starterPackOfferActive: Bool {
        guard !starterPackClaimed, let shownAt = starterPackShownAt else { return false }
        return Date().timeIntervalSince(shownAt) < 48 * 3_600
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
        DispatchQueue.main.async {
            if let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                SKStoreReviewController.requestReview(in: scene)
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
        guard level >= 100, !completedTracks.contains(trackID) else { return }
        completedTracks.insert(trackID)
        deliverTrackReward(for: trackID)
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
                bundle.music.allSatisfy  { isOwned($0) }
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
        case let m as MusicTrack:  ownedMusic.insert(m.rawValue)
        default: break
        }
    }

    /// Attempt to purchase a cosmetic with coins.  Returns true on
    /// success, false if already owned or insufficient balance.
    @discardableResult
    func purchase<Item: CosmeticItem>(_ item: Item) -> Bool {
        if isOwned(item) { return false }
        guard spendCoins(item.coinCost) else { return false }
        grant(item)
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
        guard spendCoins(pack.price(in: self)) else { return false }
        pack.grantContents(to: self)
        ownedPacks.insert(pack.id)
        return true
    }

    /// Equip a whole Pack: remember it, reset the shuffle bag, and apply
    /// the first shuffled member so menus/previews immediately show a
    /// pack ball.
    func equipPack(_ pack: BallPack) {
        equippedPackID = pack.id
        packBag = []
        advancePackSkin()
    }

    /// Equip an individual ball skin — clears any equipped Pack so the
    /// shuffle stops and this exact skin stays put.
    func equipBall(_ skin: BallSkin) {
        equippedPackID = nil
        packBag = []
        activeSkin = skin
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

    private static func saveStringSet(_ set: Set<String>, forKey key: String) {
        UserDefaults.standard.set(Array(set), forKey: key)
    }

    private static func loadStringSet(forKey key: String) -> Set<String> {
        guard let arr = UserDefaults.standard.array(forKey: key) as? [String] else {
            return []
        }
        return Set(arr)
    }

    private static func save(_ dict: [Int: Int], intValueDict key: String) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: dict.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func save(_ dict: [Int: Double], doubleValueDict key: String) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: dict.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func save(_ dict: [Int: Set<Int>], setDict key: String) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: dict.map { (String($0.key), Array($0.value)) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadIntValueDict(key: String) -> [Int: Int] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stringKeyed = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { entry in
            Int(entry.key).map { k in (k, entry.value) }
        })
    }

    private static func loadDoubleValueDict(key: String) -> [Int: Double] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stringKeyed = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { entry in
            Int(entry.key).map { k in (k, entry.value) }
        })
    }

    private static func loadSetDict(key: String) -> [Int: Set<Int>] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stringKeyed = try? JSONDecoder().decode([String: [Int]].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { entry in
            Int(entry.key).map { k in (k, Set(entry.value)) }
        })
    }

    /// Persist a [String: Int] dictionary (e.g. trackProgress) to UserDefaults.
    /// Keys are already strings so no conversion is needed.
    private static func save(_ dict: [String: Int], trackProgressKey key: String) {
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Load a [String: Int] dictionary from UserDefaults.
    private static func loadTrackProgress(key: String) -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return dict
    }
}
