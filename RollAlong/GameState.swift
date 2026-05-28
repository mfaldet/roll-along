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
