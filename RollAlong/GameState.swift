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
    @Published var ownedMusic:       Set<String> {
        didSet { Self.saveStringSet(ownedMusic, forKey: "ra_ownedMusic") }
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
        seenTutorialReward = UserDefaults.standard.bool(forKey: "ra_seenTutorialReward")

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

        // Cosmetic economy — load owned-sets to local lets first, then
        // assign to the stored properties.  We re-use the locals when
        // computing the equipped cosmetics below; referring to
        // `self.ownedGoals` directly would be a "self used before all
        // stored properties initialised" error here.
        coinBalance = UserDefaults.standard.integer(forKey: "ra_coinBalance")
        let loadedOwnedBalls   = Self.loadStringSet(forKey: "ra_ownedBallSkins")
        let loadedOwnedGoals   = Self.loadStringSet(forKey: "ra_ownedGoals")
        let loadedOwnedTrails  = Self.loadStringSet(forKey: "ra_ownedTrails")
        let loadedOwnedFloors  = Self.loadStringSet(forKey: "ra_ownedFloors")
        let loadedOwnedPits    = Self.loadStringSet(forKey: "ra_ownedPits")
        let loadedOwnedMusic   = Self.loadStringSet(forKey: "ra_ownedMusic")
        let loadedOwnedBundles = Self.loadStringSet(forKey: "ra_ownedBundles")
        ownedBallSkins = loadedOwnedBalls
        ownedGoals     = loadedOwnedGoals
        ownedTrails    = loadedOwnedTrails
        ownedFloors    = loadedOwnedFloors
        ownedPits      = loadedOwnedPits
        ownedMusic     = loadedOwnedMusic
        ownedBundles   = loadedOwnedBundles
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
}
