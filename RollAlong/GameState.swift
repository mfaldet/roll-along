import SwiftUI

final class GameState: ObservableObject {
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

    init() {
        let saved = UserDefaults.standard.integer(forKey: "ra_level")
        currentLevel = saved > 0 ? saved : 1
        activeSkin = BallSkin(rawValue: UserDefaults.standard.string(forKey: "ra_skin") ?? "") ?? .red
        playerName = UserDefaults.standard.string(forKey: "ra_name") ?? ""
        hapticsEnabled = UserDefaults.standard.object(forKey: "ra_haptics") as? Bool ?? true
        soundEnabled = UserDefaults.standard.object(forKey: "ra_sound") as? Bool ?? true
        ballStartsAtTop = UserDefaults.standard.object(forKey: "ra_startAtTop") as? Bool ?? true
        seenOnboarding = UserDefaults.standard.bool(forKey: "ra_seenOnboarding")
        seenWelcomeMoment = UserDefaults.standard.bool(forKey: "ra_seenWelcomeMoment")

        bestStars       = Self.loadIntValueDict(key: "ra_bestStars")
        bestTime        = Self.loadDoubleValueDict(key: "ra_bestTime")
        collectedCoins  = Self.loadSetDict(key: "ra_collectedCoins")
        let unlocked    = UserDefaults.standard.integer(forKey: "ra_highestUnlocked")
        highestUnlocked = max(1, unlocked)

        // Lives — default to a full bar.  `as? Int ?? Self.livesMax` covers
        // the case where no key has been written yet (fresh install).
        lives          = UserDefaults.standard.object(forKey: "ra_lives") as? Int ?? Self.livesMax
        lastLifeLostAt = UserDefaults.standard.object(forKey: "ra_lastLifeLostAt") as? Date
        unlimitedLives = UserDefaults.standard.bool(forKey: "ra_unlimitedLives")
    }

    // MARK: - Level progression

    func advanceLevel() {
        currentLevel += 1
        if currentLevel > highestUnlocked {
            highestUnlocked = currentLevel
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
    @discardableResult
    func consumeLife() -> Bool {
        if unlimitedLives { return true }
        commitRegen()
        if lives <= 0 { return false }
        lives -= 1
        if lastLifeLostAt == nil { lastLifeLostAt = .now }
        return true
    }

    /// Award lives (e.g. from rewarded ad or IAP).  Caps at livesMax.
    func addLives(_ count: Int) {
        if unlimitedLives { return }
        commitRegen()
        lives = min(Self.livesMax, lives + count)
        if lives >= Self.livesMax {
            lastLifeLostAt = nil
        }
    }

    // MARK: - Persistence helpers (UserDefaults can't store [Int: T] directly)

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
}
