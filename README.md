# Roll Along

A tilt-controlled marble game for iPhone. Tilt the phone to roll a marble through the endless Adventure mode, 10 minigames and 8 challenge tracks; collect cosmetics; earn trophies; compete on leaderboards.

**Platform:** iPhone, iOS 18 or later · **Language:** Swift / SwiftUI · **Build:** Xcode 26 or later

Version 1.0 is being prepared for TestFlight and the App Store. This file says what works, what has known faults and what is planned.

---

## What works

The main mode is called **Adventure** in the game. In the code it is still named `climb` (ids, file comments, database columns); those internal names are unchanged.

### Game modes

| Mode | What you do |
|---|---|
| **Adventure** (the main mode) | Tilt to the goal past the holes. The first 100 levels are authored (`LevelOverrides.json`); after that levels are generated, so Adventure does not end. Stars, coins and lives. |
| **Challenge Tracks** (8) | Themed 100-level tracks generated from a seed. Finishing one grants a cosmetic collection. |
| **Competitive minigames** (6, against AI rivals) | Comet Clash, Sumo Survival, Paint Ball, Smash and Grab, Marble Cup, King of the Hill |
| **Solo minigames** (4) | Zen Garden, Gold Rush, Roll Up, Disco Ball |

All game art is drawn in code with SwiftUI `Canvas`; there are no image assets apart from the app icon.

**Where things are.** Home → Game Modes has Adventure, the Challenge Packs and one **Minigames** button, which opens a two-column grid of every minigame (order: `MinigamesGridView.minigameOrder` in `GameMenuView.swift`). Pressing and holding a minigame tile plays its preview clip, if one has been added (`RollAlong/MinigameClips/`, spec in [`docs/minigame-clips.md`](docs/minigame-clips.md)). The Trophy Room opens from the Trophies card on Profile; Home has no Trophies button.

### Everything else

- **Cosmetics.** 74 ball skins plus goals, trails, floors, pits, boundaries and music, bought with coins. Sold through a shop that rotates hourly and through collections. See *Release calendar* below.
- **Trophies.** 86 trophies in v1.0, shown in the Trophy Room as 44 tiles in four sections (Adventure, Challenges, Minigames, Personal). A *stack* tile holds the steps of one measure and evolves as steps are earned; a *feat* tile is a one-off. Platinum, the header badge, needs the 68 visible Bronze/Silver/Gold trophies outside Friends & Clans and Secrets. Trophies never grant coins. The full list is in [`docs/trophies/trophy-list.md`](docs/trophies/trophy-list.md).
- **In-app purchases** (StoreKit 2). Eight consumables (lives and coins) and two one-time unlocks (Unlimited Lives, Starter Pack). The top coin pack also includes the Money Ball skin, stated on the purchase card. Restore Purchases is in Settings.
- **Ads.** One rewarded video ("watch an ad for a life") through Google AdMob. Requests are always non-personalized; there is no tracking prompt because the app does not track. Ad content is capped at Google's "Teen" rating.
- **Sign-in.** Optional Sign in with Apple, needed only for leaderboards, friends and clans. The app does not ask for a name or email address. Delete Account is in Settings.
- **Friends, clans, leaderboards.** Friend requests, sending lives, clans with a fixed-phrase chat, and leaderboards for Adventure and the minigames (per difficulty where a game has difficulty levels). A player's Adventure level shows as a badge next to their name; friends and clan lists show levels gained this week. A clan holds up to 12 players. A clanmate's life request collects up to 6 lives, one per clanmate, at no cost to the giver; it closes after 24 hours, and the asker waits 6 hours before the next. Open requests show as a red count on Home's Clans button. "Send life" to a friend is one per friend per day. Every player has a friend code on their profile; Friends → Add by code finds that exact player. All social clocks (seasons, weekly pace, daily limits) run on Eastern time.
- **Monthly clan battle.** A season is a calendar month. A clan's season score is the new Adventure stars its members earn that month, counted by the server. Clans → Rankings sorts by season score (also total levels and total stars) and shows the days left. At month end the server ranks the clans and awards coins by tier to members who contributed; the clan that finishes first gets a win. A player claims their coins on the Clans screen. December 2026 is a rehearsal with no prizes. Design: `docs/social/social-revision-proposal.md`.
- **How a level starts.** Settings → Tap to Start (the default: a level waits for a tap) or Auto Start. Applies to Adventure and Challenge Tracks. The level clock starts when play starts.
- **No free text.** A nickname is two preset words (15,093 combinations, not unique; the player's Adventure level is shown beside it everywhere as part of the name). A clan name is two preset words plus a number (about 32 million). Lists are in `docs/social/preset-names.md`, clan tags are derived from the name, and clan descriptions come from a fixed list (`PresetNames` in `SocialClient.swift`). Nothing a player types is ever shown to another player.
- **Notifications.** Two local notifications (shop restock, lives full), each switched on by the player in Settings. No push server.
- **Analytics.** The app's own anonymous event log. See *Services*.

### Release calendar

Most cosmetics are held back at launch and released on a schedule stored in the app (`CosmeticSchedule` in `Cosmetics.swift`):

- 13 collections are available on day one, including everything the game gives away.
- 37 more arrive in 12 drops, one every 28 days, counted from a single `launchDate`.
- The Catalog shows the next drop and its date in a "Coming soon" row.
- 16 seasonal collections open for their window each year.

Launch date: **December 15, 2026**. Drops: Jan 12, Feb 9, Mar 9, Apr 6, May 4, Jun 1, Jun 29, Jul 27, Aug 24, Sep 21, Oct 19 and Nov 16, 2027. If the release day moves, change `CosmeticSchedule.launchDate` and every drop moves with it.

---

## Known faults

- **Pinball is not in v1.0.** It is unfinished, so it has been removed from the build along with its leaderboard and trophies. The work in progress is kept in `tools/pinball/` (not part of the app).
- **Leaderboards are kept per difficulty.** Every board for a game with difficulty levels (the six competitive games and Disco Ball) has three tabs, Easy / Normal / Hard (Disco Ball: Hardcore), and a run counts only on its own difficulty's board. Competitive boards rank by wins, then best score; Disco Ball by most crossings in one run, then the faster average time per crossing. The Disco Ball boards need `docs/leaderboard-discoball.sql`; until it is run they say "not available yet", and nothing else is affected. Disco Ball has no time limit on any difficulty.
- **Roll Out is not in v1.0.** Its mazes need rebuilding (maze 4 has no route from start to goal), so it is switched off in the mode registry (`GameModeCatalogue`) like Pinball: in no menu, no leaderboard and no trophies. `RollOutView.swift` and its route stay in the code for later.
- **The Challenge of the Day is not in v1.0.** It is switched off in the mode registry (`GameModeCatalogue`) like Roll Out: in no menu, no notification and no trophies (its four trophies and two tiles are out of the catalog), and it no longer follows the Tap to Start setting. Its code, saved completions and trophy funnel are kept. The daily reward and its streak are separate and unchanged.
- **Adventure sound effects are system placeholder sounds.**
- **Five authored levels** (78, 83, 89, 92, 97) have a coin on the rim of a hole. `node scripts/verify-levels.mjs` lists them.
- **Leaderboard and season scores are only lightly checked by the server.** `docs/social-schema-v5.sql` refuses impossible values (more than three stars per level), caps the stars that count toward a season per day, and adds a switch to exclude a player or clan. It does not stop a determined cheater.
- **`docs/social-schema-v5.sql` is not on the live database yet.** Until it is applied (with `docs/social-schedule.sql`), weekly pace, clan rankings, the monthly clan battle, the 12-member cap and the life-request limits do not work; the rest of the social screens fall back to how they worked before.
- **The month-end job has never run on the live database.** It was tested on a local database only. If the Supabase project is paused the scheduled jobs do not run; the month-end job catches up the day after it wakes.
- **Clans have an owner and members only.** The owner can remove a member and hand over ownership; there are no promote or demote ranks.
- **Trophy tables are not on the live database yet** (checked 2026-11-15). Until `docs/trophies/trophy-schema.sql` is applied, trophies work on the device but rarity figures and the public trophy showcase do not.
- **Account deletion** removes all server data. The app now asks Apple for a one-time code and sends it to the server so the Sign in with Apple token can be revoked, but the server half is not deployed yet (`docs/delete-account-apple-revoke.md`).
- **iCloud trophy backup** is written but switched off for v1.0 (`UbiquitousTrophyKVStore.isEnabledInThisBuild`). Nothing in the game is backed up to iCloud: deleting the app, or moving to a new phone without restoring a backup, loses local progress. Purchases restore from Apple, and signed-in players get their trophies back from the server once the trophy tables exist.
- **Invite links use the `rollalong://` scheme**, which most messaging apps do not turn into a tappable link.
- **Automated tests cover** trophies, game state, purchases and cosmetics. Minigame play, sign-in and the social screens are tested by hand only. There is no CI.

## Planned

- Pinball, rebuilt, in a later update, with its own trophies.
- Roll Out, with hand-built mazes and its two trophies.
- The Challenge of the Day, with its four trophies, if it comes back.
- Real sound effects.
- iPad support.
- iCloud trophy backup and a Game Center mirror for trophies.
- Moving the release calendar to the server if dates need to change without an app update.

---

## Services

| Service | Used for | Notes |
|---|---|---|
| **Apple** | Sign in with Apple, in-app purchases | |
| **Supabase** | Sign-in sessions, database (profiles, leaderboards, friends, clans, trophies), the `delete-account` function, analytics events | One project. The keys in the source are Supabase's public client keys; data is protected by the row-level rules in `docs/*.sql`. |
| **Google AdMob** | Rewarded video ads | Non-personalized only. |
| **GitHub Pages** | The privacy policy page | Published from the `gh-pages` branch. `docs/site/privacy.html` is the working copy. |

Nothing else is contacted. In particular the app does not use Vercel, Game Center or a push-notification server.

**Analytics, in plain words.** Each install gets a random ID. Events record what happened in the game (levels, minigame rounds, purchases, ad steps, screens opened) with the app version, iOS version and phone model. They are not tied to the player's account, Apple ID or advertising ID.

---

## Building

1. Open `RollAlong.xcodeproj` in Xcode 26 or later.
2. Run on a **physical iPhone** with iOS 18 or later. The simulator does not report device motion, so the marble will not move there.
3. For purchase testing without App Store Connect, the scheme's Run action uses `RollAlong/Products.storekit`.

Tests: Product → Test (unit tests in `RollAlongTests`, a UI smoke test in `RollAlongUITests`).

Package versions are pinned by `Package.resolved`, which is committed.

## Project layout

```
RollAlong/
├── RollAlongApp.swift            app entry, launch tasks
├── HomeView.swift                routing hub
├── GameMode.swift                mode registry and tutorial text
├── BallGameView.swift            Adventure engine (also Zen, Gold Rush, daily, tracks)
├── *View.swift                   one file per self-contained minigame
├── GameState.swift               all saved player state
├── Cosmetics.swift               cosmetic catalogue, shop rotation, release calendar
├── StoreKitManager.swift         purchases and restore
├── AdManager.swift               rewarded ads
├── AppleAuthManager.swift        Sign in with Apple → Supabase session
├── SocialClient.swift            friends, clans, leaderboards; preset names
├── AnalyticsClient.swift         anonymous event log
├── Trophy*.swift, TrophyCatalog.json   trophy system
└── PrivacyInfo.xcprivacy         privacy manifest
docs/
├── *.sql                         database schema and access rules (apply in order; v4 = preset names, v5 = pace, cap, guards, life requests, monthly clan battle; then social-schedule.sql)
├── delete-account-apple-revoke.md   server change for revoking the Apple token on deletion
├── app-review/                   review notes, purchase table and App Privacy answers for App Store Connect
├── site/privacy.html             working copy of the published privacy policy
├── social/                       preset name lists; social and clans design (monthly clan battle)
├── minigame-ai-tuning-proposal.md   how the opponents work and how to tune them
├── trophies/, economy/, research/   design notes
└── AppStore.md, TestFlight.md    OUT OF DATE — see the note at the top of each
tools/pinball/                    held-back Pinball work, not built into the app
```

Saved state lives in `UserDefaults`, except the sign-in session token (Keychain) and signed-in social data (Supabase).

## License

Personal project — all rights reserved.
