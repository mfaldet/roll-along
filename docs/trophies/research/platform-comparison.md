# Platform Achievement Systems — Comparison Research (ex-PlayStation)

**Date:** 2026-07-02
**Purpose:** Inform the design of a trophy system for Roll Along (SwiftUI, iOS 18+, currently **zero GameKit integration** — verified by grep across `RollAlong/*.swift`). Covers Xbox, Steam, Apple Game Center (primary focus), Nintendo, and custom mobile/F2P systems, plus a build-vs-buy analysis. PlayStation is covered in a separate doc.
**Method:** Web research with cited URLs; claims that could not be verified against a primary source are marked "(unverified)".

---

## 1. Xbox — Gamerscore

### The model
- Every achievement carries a **Gamerscore (GS)** point value; the player's total GS is a lifetime cross-game score attached to the profile.
- Current certification rules (XR-055, Microsoft GDK cert requirements, v16.3 dated 2026-07-01): a title must ship with **minimum 10 achievements and exactly 1,000 GS at launch** (max 100 achievements at launch). Post-launch, titles may add up to **+100 achievements / +1,000 GS per semi-annual window** (Jan–Jun, Jul–Dec), with a **lifetime cap of 500 achievements / 5,000 GS**. A **single achievement cannot exceed 200 GS**. Source: https://learn.microsoft.com/en-us/gaming/gdk/docs/store/policies/console/certification-requirements?view=gdk-2510
- Other cert rules worth copying as design hygiene:
  - **XR-057:** all base-game achievements must be earnable without buying anything; no real-money or cheat-menu unlocks.
  - **XR-060:** once published, an achievement can never be removed and its unlock rules/point value can never change — only its text and art can be edited. (Plan identifiers and criteria carefully up front.)
  - **XR-062:** names/descriptions must stay at roughly ESRB E10+ content level, no profanity.

### Historical shape (why the numbers are what they are)
- Xbox 360 era: retail games got 1,000 GS with optional **+250 GS increments via DLC**; Arcade titles got 200 GS. The modern GDK table above replaced those rules. Sources: https://www.giantbomb.com/xbox-360/3045-20/forums/what-is-the-current-gamerscore-limit-per-game-wdlc-472580/ , https://www.neogaf.com/threads/ms-updates-achievement-rules-allows-for-extra-achievements-via-dlc.140824/ (era details community-documented — unverified against archived Microsoft policy)
- The constant across 20 years: **launch budget is fixed and equal for every game**, expansions are rationed, and the per-achievement ceiling stops any single unlock from dominating the economy.

### Rarity display
- An achievement is **"rare" when fewer than 10% of players** who own the game have unlocked it. Rare unlocks get a **diamond icon** on the achievement tile and a distinct unlock pop-up + sound. Rolled out to all Xbox One games in 2016. Sources: https://xbox.fandom.com/wiki/Achievement , https://www.trueachievements.com/n39996/how-to-see-achievements-and-delete-achievements-on-xbox (threshold widely reported; exact Microsoft-published definition not located — "(unverified)" at primary-source level)
- Note the design: **binary tier (rare / not rare) + one icon**, not a percentage readout in the tile. The precise % is visible on the achievement detail page.
- The rare-unlock moment is deliberately theatrical (different animation + sound) — the celebration scales with the accomplishment, which players consistently cite as the best part of the system.

### Completion-percentage culture
- The Xbox profile shows a per-game completion % — this drives a large completionist community.
- **TrueAchievements** (1M+ registered users) recomputes score by rarity: **TA Ratio = sqrt(gamers-with-game / gamers-with-achievement)**, and TA Score = GS x TA Ratio, so rare achievements are worth more. Ratios drift over time as more people unlock. Sources: https://www.trueachievements.com/n32457/ta-score , https://www.trueachievements.com/forum/viewthread.aspx?tid=154262
- Lesson: a fixed point economy (1,000 GS) plus third-party rarity weighting shows players want **both** a stable score and a bragging-rights rarity signal. Building rarity weighting in from day one avoids outsourcing it.

### Lessons for Roll Along
1. Fixed total point budget makes scores comparable across games and forces curation.
2. Immutability-after-publish is the norm on every platform — trophy IDs and criteria must be stable forever.
3. A single "rare" threshold with a distinct icon + sound is cheap and highly legible.

---

## 2. Steam

### Global achievement percentages
- Steam publishes **per-game global unlock percentages** on public stats pages (`https://steamcommunity.com/stats/<appid>/achievements`, e.g. Vampire Survivors: https://steamcommunity.com/stats/1794680/achievements ). The in-client achievements page shows the same global % next to each achievement, sorted most-to-least common.
- Rarity formula: **(players who unlocked) / a denominator Valve does not document** — the community is split between *all owners of the game* and *players who have launched it at least once*, with no Valve confirmation either way; update cadence is likewise unpublished **(unverified)**. What holds under either reading: the denominator is noisy — a big sale or bundle floods it with new owners/players and temporarily deflates every percentage. Community discussion (both positions, unresolved): https://steamcommunity.com/discussions/forum/1/864976114818230901/ ; official dev docs (expose global percentages, no formula given): https://partner.steamgames.com/doc/features/achievements
- Steam displays raw percentages, **no named rarity tiers** — tiering is left to third parties.

### Perfect Games & profile culture
- The profile's **Achievement Showcase** includes a **"Perfect Games" count** (games at 100% achievements) and an average completion rate; there is also a **"Rarest Achievement Showcase"**. Valve added the perfect-games surfacing in 2018. Sources: https://www.pcgamer.com/steam-shows-your-perfect-games-now-experiments-with-open-bazaar-approach-to-browsing/ , https://steamcommunity.com/discussions/forum/0/1743358239842091022/
- Average completion rate is computed only over games where the player has unlocked at least one achievement (community-documented): https://steamcommunity.com/sharedfiles/filedetails/?id=650166273

### Limits and the 2018 anti-spam change
- New games are capped at **100 achievements** until Steam's "confidence metric" lifts the game out of **"Profile Features Limited"** status; below that bar the achievements don't count toward player totals or showcases. Once trusted, the cap rises to **5,000**. Introduced 2018 to kill achievement-spam shovelware. Sources: https://kotaku.com/valve-adds-limits-to-steam-achievements-to-fight-rise-o-1826873740 , https://steamcommunity.com/discussions/forum/0/3819656548993343340/
- Lesson: unlimited/huge achievement counts destroyed the currency's meaning; every platform has since converged on curation.

### Third-party trackers
- A whole ecosystem ranks players and computes rarity-weighted scores: **TrueSteamAchievements** (https://truesteamachievements.com/), **AchievementStats** (https://achievementstats.com/), plus completionist.me, AStats, SteamHunters (ecosystem existence per search results; individual feature sets unverified).
- These exist because Valve exposes owner counts and unlock counts through public pages/Web API; the trackers add the tiers, ratios, and leaderboards Valve declines to build.
- Lesson: public per-achievement stats APIs create a community layer for free. Game Center's rarity API is Apple's (closed) answer to this.

### Lessons for Roll Along
1. Percent-of-players is the universally understood rarity currency; publish the raw number and let presentation add tiers.
2. Rarity denominators are noisy (sales, virality spikes) — never hard-code gameplay rewards to a live rarity number.
3. A "perfect games"/100% counter is a powerful meta-goal for completionists; a single-game equivalent is a visible **overall trophy-completion %**.

---

## 3. Apple Game Center (primary section)

### Capabilities in 2025–2026
GameKit's achievement stack is `GKAchievement` (per-player progress) + `GKAchievementDescription` (metadata: title, pre/post-earn descriptions, image, points, hidden, replayable, rarity). Configured in App Store Connect, or — new in Xcode 26 — in a **GameKit bundle inside Xcode** that syncs to App Store Connect and supports local testing via the **Game Progress Manager** (test unlocks without touching production). Sources: https://developer.apple.com/documentation/gamekit/rewarding-players-with-achievements , WWDC25 "Get started with Game Center": https://developer.apple.com/videos/play/wwdc2025/214/

### Points budget & hard limits (all Apple-documented)
| Limit | Value | Source |
|---|---|---|
| Max achievements per game | **100** | https://developer.apple.com/documentation/gamekit/rewarding-players-with-achievements |
| Max points per achievement | **100** | same |
| Max total points per game | **1,000** | same |
| Achievement ID | letters/numbers (periods and underscores likely also allowed — Apple's analogous identifier rules permit them and reverse-DNS IDs are the common convention; exact charset not confirmed at the cited page, verify in ASC), **<= 100 chars, permanent** (never editable) | https://developer.apple.com/help/app-store-connect/reference/game-center/achievements/ |
| Image | **required**, 1024x1024 px, .png/.jpg/.jpeg, RGB, >= 72 ppi | same |
| Localization | **>= 1 language required**; per language: display name + pre-earned description + earned description | same |
| Archiving | live achievements can be archived (removed from GC UI, not returned by API); takes up to 24h; reversible | https://developer.apple.com/help/app-store-connect/configure-game-center/manage-achievements/ |

Design implication: 100 achievements x 1,000 points means an average of 10 pts each if you ever want the full 100; Apple suggests **holding back budget so future updates can add achievements** ("progressively add achievements to each version of your game until you reach the limit").

### Progress-based achievements
- Progress is a **`percentComplete` value 0–100** reported via `GKAchievement.report(_:)` (iOS 6+). Dashboard shows locked (0), in-progress bar (0<x<100), and earned (100) states. Source: https://developer.apple.com/documentation/gamekit/rewarding-players-with-achievements
- **Progress is monotonic:** "If the reported value is higher than the previous value... the value on Game Center is updated. Players never lose progress on achievements" — lower reports are ignored, so re-reporting is naturally idempotent. Source (archived GameKit guide): https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/GameKit_Guide/Achievements/Achievements.html
- The game must compute the percentage itself (GC doesn't aggregate counters for you — no server-side "do X 50 times" counter like Xbox stats).
- `isReplayable` (configured as "Achievable More Than Once") lets a player re-earn an achievement; the completion banner re-fires.

### Hidden achievements
- Configurable per achievement ("hidden until earned"). A hidden achievement is **revealed the moment any progress is reported — even 0.0%** — so don't report progress on story-spoiler achievements until unlock. Non-hidden achievements are browsable in the locked state with their pre-earn description. Sources: archived guide (above) + https://developer.apple.com/documentation/gamekit/rewarding-players-with-achievements

### Rarity percentages (introduced iOS 17)
- **`GKAchievementDescription.rarityPercent`** — "The percentage of players of this game that earned the achievement." Type `Double?`, range **0.0–100.0**, and **`nil` when there isn't enough data to compute rarity**. Availability confirmed from Apple's doc JSON: **iOS/iPadOS 17.0, macOS 14.0, tvOS 17.0** (visionOS/watchOS also listed). Source: https://developer.apple.com/documentation/gamekit/gkachievementdescription/raritypercent-4bh6k
- Apple does not document the computation window, denominator ("players of this game" — presumably GC-authenticated players, not all installs), refresh cadence, or the minimum-data threshold behind `nil` (all **unverified/undocumented**). Expect `nil` for a small game at launch.
- Marketing framing: "With achievement rarity, players can view the number of other players who've unlocked a particular achievement, so they'll stay motivated" — i.e., rarity is shown to players inside the Game Center dashboard/Games app achievement UI, and is also available to your own UI via the API. Source: https://developer.apple.com/game-center/
- This is the **only zero-backend rarity source available to an iOS indie** — the direct analogue of Steam's global stats and Xbox's diamond, but only for players/games participating in GC.

### In-game UI: GKAccessPoint + dashboard
- **`GKAccessPoint`** (iOS 14+): a system-drawn floating widget you enable in a corner; opens the Game Center dashboard, and its "highlights" surface achievements. Programmatic open: `GKAccessPoint.shared.trigger(state:handler:)` — e.g. straight to the achievements screen. Sources: https://developer.apple.com/documentation/gamekit/gkaccesspoint , https://developer.apple.com/documentation/gamekit/gkaccesspoint/trigger(state:handler:)
- **`GKGameCenterViewController`**: full dashboard sheet, can be initialized directly in an achievements state or even to a single achievement; delegate callback on dismiss. Source: https://developer.apple.com/documentation/gamekit/gkgamecenterviewcontroller
- Or skip Apple's UI entirely: `GKAchievementDescription.loadAchievementDescriptions()` returns localized titles/descriptions/points/rarity, plus image loading, so you can render achievements in your own SwiftUI screens. Source: https://developer.apple.com/documentation/gamekit/rewarding-players-with-achievements

### iOS 26: the Games app + App Store surfacing (big discovery change)
- WWDC25 introduced the **Apple Games app**, pre-installed on iOS/iPadOS/macOS 26 (shipped fall 2025). Sources: https://www.apple.com/newsroom/2025/06/introducing-the-apple-games-app-a-personalized-home-for-games/ , https://developer.apple.com/videos/play/wwdc2025/215/
- Apple's developer pitch: "games that include Game Center features and In-App Events are prominently displayed across the Games app"; every GC-enabled game gets a **dedicated page** where "players can also view the latest in your game like In-App Events and Game Center activity, **such as achievements, scores, and friend activity**"; achievements appear "as recommendations across the Games app" and players "see which ones their friends have completed"; GC-enabled games are eligible for the **Top Played chart shown in the Games app and on the App Store**. Source: https://developer.apple.com/games-app/
- Also new at WWDC25: **Challenges** (score competitions auto-built from existing leaderboards, no new code beyond `submitScore`) and **Activities** (deep links into game content). Source: https://developer.apple.com/videos/play/wwdc2025/214/
- Net: since iOS 26, adopting GC achievements is no longer just a trophy feature — it is **App Store/Games-app discovery surface area** for a small game.

### Sign-in requirement & adoption
- Any GameKit use requires the **local player to be authenticated**: set `GKLocalPlayer.local.authenticateHandler` at launch; GameKit hands you a sign-in view controller if the device user isn't signed in; `isAuthenticated` gates everything. One device-level GC account covers all games. Sources: https://developer.apple.com/documentation/gamekit/authenticating-a-player , https://developer.apple.com/documentation/gamekit/gklocalplayer/isauthenticated
- If the player declines sign-in, achievements cannot be reported for them — your design must tolerate permanently-signed-out players.
- **No official adoption statistic exists.** Data points: one indie (Six Ages) reported ~**59% of active users** GC-authenticated (2018, single game — unverified as an industry figure): https://developer.apple.com/forums/thread/105837 ; Game Center had ~405M lifetime accounts by end-2015: https://9to5mac.com/2015/12/29/game-center-players/ . Since iOS ~10 the OS nudges sign-in at device setup, so most modern devices are signed in (unverified). Planning assumption: **a meaningful minority of Roll Along players will not have GC active.**

### Offline unlock queueing
- Apple's documented position: "If an error occurs, such as when a network is not available, Game Kit automatically resends the data at an appropriate time." Source: https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/GameKit_Guide/Achievements/Achievements.html
- Practitioner reality: the auto-resend has historically been **unreliable**, and devs ship their own persistence + retry (e.g., re-report on next authenticated launch). Sources: http://simx.me/technonova/software_development/offline_game_center_reporting.html , https://forums.solar2d.com/t/game-center-report-achievements-after-playing-offline/336881
- Mitigation is easy because reporting is idempotent (server keeps the max %): **persist unlocks locally (source of truth), re-report everything not yet confirmed on each launch.**

### SwiftUI integration patterns
- **There is no first-party SwiftUI API for GameKit as of iOS 26** — WWDC25 sample code is delegate/UIKit-style (session 214 shows `GKLocalPlayerListener` on an AppDelegate). Patterns for a SwiftUI app:
  1. Authenticate in `App.init`/first-scene `.task`; present the handler's view controller via the key window's root VC (or a `UIViewControllerRepresentable` shim).
  2. `GKAccessPoint.shared` is window-level and works fine over SwiftUI; toggle `isActive` per screen so it doesn't overlap gameplay HUD.
  3. Wrap `GKGameCenterViewController` in `UIViewControllerRepresentable` for a `.sheet`/`.fullScreenCover`.
  4. Or fully custom: load `GKAchievementDescription`s (incl. `rarityPercent`) into an `@Observable` store and render native SwiftUI — Apple explicitly supports rendering achievement data in your own interface.
- Banner control: set `showsCompletionBanner = false` before reporting to suppress the system toast when you show your own unlock animation.
- Reset: `GKAchievement.resetAchievements(completionHandler:)` clears **all** of the local player's progress (also re-hides previously revealed hidden achievements) — debug/QA tool only, never ship a UI path to it.

### Operations: configuration, testing, release, automation
- **Config surfaces:** App Store Connect (web) or the Xcode 26 **GameKit bundle** checked into the repo (syncs to ASC; achievements/leaderboards/challenges/activities in one artifact under version control). Source: https://developer.apple.com/videos/play/wwdc2025/214/
- **Local testing:** Game Progress Manager in Xcode 26 simulates progress/unlocks on-device without touching production data; prerelease achievements are annotated with a prerelease indicator in the dashboard. Sources: WWDC25 214 (above), https://developer.apple.com/documentation/gamekit/rewarding-players-with-achievements
- **Release flow:** GC features start "Not Live" in App Store Connect, are testable via TestFlight, and go live with app review — so trophy content updates ride the normal release train.
- **Automation:** the App Store Connect API has full CRUD endpoints for Game Center achievements (create/localize/upload images/archive), so the trophy catalog could be generated from a JSON source of truth in-repo — same philosophy as `LevelOverrides.json`. Source: https://developer.apple.com/documentation/appstoreconnectapi/game-center-achievements
- **Analytics:** App Store Connect provides a "Game Center achievement catalog report" for tracking configured achievements. Source: https://developer.apple.com/help/app-store-connect/reference/game-center-achievement-catalog-report

### Game Center limits recap (one glance)
| Dimension | Value |
|---|---|
| Achievements per game | 100 (archive to free UI clutter, IDs live forever) |
| Points | 1,000 total / 100 max each; points are GC-status only, no economy hooks |
| Progress | 0–100 `percentComplete`, monotonic, client-computed |
| Rarity | `rarityPercent: Double?` iOS 17+, nil until sufficient data, Apple-computed |
| Hidden | supported; revealed by any progress report (even 0%) |
| Repeatable | `isReplayable` per achievement |
| Art | mandatory 1024x1024 RGB png/jpg per achievement |
| Localization | mandatory >= 1 locale; 3 strings per locale per achievement |
| Auth | required (device-level GC account); must handle declined sign-in |
| Min OS for full feature set | iOS 17 (rarity) — Roll Along's iOS 18 floor clears everything except iOS 26-only Games-app extras |

---

## 4. Nintendo — the no-achievements platform

- Neither Switch 1 nor Switch 2 has a system-level achievement system; Nintendo is the only one of the big three without one, and confirmed the omission again for Switch 2 (2025) (secondary reporting; no official Nintendo statement located — unverified). Sources: https://www.makeuseof.com/nintendo-switch-have-achievements/ , https://www.howtogeek.com/the-switch-doesnt-have-achievements-and-i-hope-it-never-does/
- The commonly-cited rationale is philosophical (play for fun, not checklists; avoid engagement-bait filler) — Nintendo has never given an official reason (unverified).
- The closest platform-level construct is Nintendo Switch Online's "Missions & Rewards" (platform points redeemable for profile icons), which is account-meta, not per-game achievements (widely reported; unverified here).
- **What devs do instead — build in-game:**
  - *Fire Emblem Engage* ships an in-game achievement list that pays out **in-game currency** per unlock.
  - *Astral Chain* has 180+ "orders" (missions/collectibles) tracked in-game. Source for both: https://www.makeuseof.com/nintendo-switch-have-achievements/
  - Multiplatform games (e.g., Vampire Survivors, below) keep one in-game achievement list and simply mirror it to platform trophies where a platform layer exists.
- **Lesson (the strongest precedent for Roll Along):** on a platform with no trophy layer, the successful pattern is an **in-game achievement wall with functional rewards** — exactly the "custom trophy room" option, and it doubles as the fallback for iOS players without Game Center.

---

## 5. Mobile/F2P custom (non-platform) achievement systems

1. **Pokémon GO — Medals.** Every medal has **Bronze/Silver/Gold/Platinum tiers**; the full medal wall lives on the trainer profile; type medals give **functional catch bonuses (+1..+4)** and some unlock wardrobe items. Tiered medals turn one accomplishment into four dopamine hits and make the profile a showcase. Sources: https://bulbapedia.bulbagarden.net/wiki/Medal_(GO) , https://niantic.helpshift.com/hc/en/6-pokemon-go/faq/101-how-do-i-level-up-and-earn-medals/
2. **Clash of Clans — Achievements.** Three tiers per achievement; rewards are **XP + gems (premium currency)**; the list shows on the player profile. Paying players in soft/premium currency makes the system self-marketing — players seek achievements out. Source: https://clashofclans.fandom.com/wiki/Achievements
3. **Vampire Survivors — Unlocks/Secrets.** 449 achievements ("Unlocks" in-game) where **every unlock grants content** — characters, stages, features, or gold; a "Secrets" menu hints at hidden ones. The same in-game list mirrors to Steam/Xbox achievements where available — the canonical **"custom source of truth + platform mirror"** architecture. Source: https://vampire.survivors.wiki/w/Achievements
4. **Alto's Odyssey — Goals (iOS indie archetype).** **180 hand-crafted goals, 3 per level x 60 levels**; completing a level's goals is the progression system itself and unlocks characters every 10 levels. Goals-as-progression keeps sessions purposeful in an endless game. Sources: https://altosodyssey.fandom.com/wiki/Goals , https://www.appunwrapper.com/2018/02/21/altos-odyssey-list-of-goals-for-all-levels/
- Cross-cutting pattern: mobile custom systems almost always attach **tangible rewards** (currency/content/bonuses) and a **profile showcase**; platform systems attach only status. Roll Along already has coins, cosmetics, and a profile/public-profile surface — all four precedents map cleanly onto existing systems.
- Second pattern: **tiers over one-shots.** Pokémon GO (4 tiers) and Clash of Clans (3 tiers) stretch each accomplishment across the whole player lifecycle; single-tier walls (Steam-style) front-load unlocks and go quiet for veterans.
- Third pattern: none of these games needed a platform service or rarity stat to make achievements sticky — rarity is a status garnish, rewards and showcase do the retention work.

---

## 6. Build vs Buy for Roll Along

**Context (verified in repo):** no GameKit anywhere in `RollAlong/` today; `PrivacyInfo.xcprivacy` present with a no-tracking posture; Supabase social backend (profiles/friends/clans) already exists; economy has coins + deep cosmetics catalogue; `ProfileView`/`PublicProfileView` are natural showcase surfaces.

| Criterion | A. Custom trophy room only | B. Game Center only | C. BOTH: custom room + GC mirror |
|---|---|---|---|
| Rarity % source | None without backend; Supabase aggregate possible (extra work, needs anti-cheat thought) | `rarityPercent` free (iOS 17+), but `nil` until enough data; denominator = GC players only | Custom UI shows GC `rarityPercent` when non-nil; graceful "—% " fallback; optional Supabase aggregate later |
| Backend needed | No (local persistence) / optional Supabase for rarity+sync | No — Apple hosts everything | No — GC hosts rarity; local store is source of truth |
| Players without GC sign-in | 100% served | Excluded (can't report or view) | 100% served by custom room; GC layer is additive |
| Offline behavior | Perfect — local unlocks, instant | Docs claim auto-resend; historically unreliable; needs own queue anyway | Local unlock always instant; re-report queue flushes to GC when online (idempotent, max-wins) |
| Privacy / no-tracking posture | Best — zero third-party data flow | Good — Apple first-party, no ad-tracking; but adds a visible Apple account layer + friends surface | Same as B; GC is opt-in per player (decline = custom-only experience) |
| Discovery (iOS 26 Games app / App Store) | None | Full: dedicated Games-app page, achievements/friend activity surfaced, Top Played eligibility | Full — mirroring unlocks is enough to light up the Games app |
| Reward integration (coins/cosmetics) | Full control — trophies can pay coins like CoC/Vampire Survivors | Not possible — GC awards points only, no hooks into game economy | Full control in custom layer; GC mirrors status only |
| UX control (trophy-room aesthetic, tiers, secret reveals) | Total | Locked to Apple dashboard UI (or render GC data in own UI, still bound by 100/1,000 limits and monotonic %) | Total — custom room is canonical; GC constraints only bind the mirrored subset |
| Immutability / limits | None — can rebalance freely (with care for player trust) | 100 achievements / 1,000 pts / permanent IDs / archive-only removal | Custom side free; keep the GC-mirrored subset stable; can mirror only the stable "canon" trophies |
| Dev cost | Medium: models + persistence + UI + unlock plumbing | Low-medium: ASC config, auth flow, report calls, edge cases (signed-out, offline) | Highest, but mostly A + a thin `GameCenterMirror` (auth + report + rarity fetch) |
| Cheating/integrity | Local-only = trivially cheatable (acceptable for cosmetic status) | Client-reported too (GC has no server validation for indies) | Same; nothing here is worth hardening |

### Analysis
- **A (custom only)** matches the Nintendo-indie/mobile-F2P precedent, keeps the no-tracking posture pristine, serves every player, and lets trophies pay coins/cosmetics — but forfeits the only free rarity signal and the entire iOS 26 Games-app discovery surface, which is a real acquisition cost for a small App Store game.
- **B (GC only)** is the least work but is a poor fit alone: players without GC get nothing, no reward hooks into the coin economy, UI is Apple's, and the 100/1,000/permanent-ID constraints bind the whole design forever.
- **C (custom source of truth + GC mirror)** is the industry-standard architecture (Vampire Survivors et al.): the in-app trophy room is canonical, unlocks instantly offline, pays rewards, and renders rarity from `rarityPercent` when Apple has enough data; mirroring to GC costs one small service class and buys rarity + Games-app/App Store discovery + friends-comparison for free. Risks to manage: `rarityPercent == nil` early on (ship a fallback state), GC's permanent-ID rule (only mirror trophies whose criteria are final), and the WWDC25 challenges/activities features tempting scope creep (leaderboards already exist in-app via Supabase — a GC leaderboard mirror is a separate decision).

**Bottom line:** the research supports **C**, with **A as the shippable first milestone** (the custom room works standalone; the GC mirror is a bolt-on that can land in a later release without reworking anything, provided trophy identifiers are chosen to be GC-legal — safest is plain alphanumeric (periods/underscores likely also allowed — verify in ASC), <= 100 chars, stable forever — from day one).

### Implementation sketch for Option C (phased)
1. **Phase 1 — custom trophy room (no GC).** Trophy catalog as data (id, title, pre/post descriptions, criteria key, tier, secret flag, coin reward); local persistence of progress/unlocks; unlock toast; trophy-room screen; showcase slots on `ProfileView`/`PublicProfileView` (Supabase already syncs profile data). Follow platform norms: monotonic progress, stable IDs, secret trophies stay fully hidden until unlock, celebration scales with tier.
2. **Phase 2 — GC mirror.** `GameCenterMirror` service: `authenticateHandler` at launch (silent if declined), map trophy IDs -> GC achievement IDs, flush a persisted re-report queue on launch/foreground (idempotent by GC's max-wins rule), `showsCompletionBanner = false` (custom toast owns the moment), pull `rarityPercent` into the trophy-room UI with a "not enough data yet" fallback.
3. **Phase 3 (optional) — discovery extras.** Evaluate GC leaderboard mirroring to unlock iOS 26 Challenges; consider Activities deep links (e.g., straight into a climb level or minigame) for Games-app surfacing.

### Open questions for design review (not settled by research)
- Trophy count and tiering for v1 (platform norms suggest ~20–50 curated, mixed difficulty, a few <10%-style "diamond" aspirations).
- Whether trophies pay coins (mobile norm, fits economy) or stay status-only (console norm) — interacts with the calibrated economy work in `docs/economy/`.
- Whether rarity ever displays for non-GC players (requires Supabase aggregation — deferrable; UI should degrade gracefully either way).
- Which subset of trophies is "canon" enough to mirror to GC given permanent-ID immutability (minigame trophies churn more than climb trophies).
- Whether the 1,000-point GC budget is spent fully at launch or rationed for post-launch additions (Apple and Xbox both design for rationing).
