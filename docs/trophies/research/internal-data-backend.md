# Internal Data & Backend Audit — Trophy System Groundwork

**Date:** 2026-07-02 · **Scope:** local persistence, Supabase backend, identity, privacy, offline, telemetry — everything a trophy system with live rarity percentages must sit on. Read-only audit of the app source (`RollAlong/`), docs (`docs/`), and the live Supabase project `mhwpcwauzvmtmuphtajs` (via MCP, read-only).

> **POST-AUDIT UPDATE (2026-07-02, main @ `42d1925`).** 36 commits merged to
> main the same day as this audit (PRs #113/#114/#118–#120/#122–#124;
> authority: `repo-delta-2026-07-02.md`). What moved for THIS doc:
> (1) **new persisted key `ra_paidPrices`** (`[String: Int]`, keys
> `"<Type>:<rawValue>"` via `paidPriceKey`; PR #120) — added to §2.2 below;
> refund bookkeeping only, it never affects ownership sets.
> (2) **The delivered-transaction IAP ledger (`ra_iapDeliveredTxnIDs`) MERGED
> to main at `fb98819`** (2026-07-02, one commit after `42d1925`; it was
> already in the audited 064f3cd = main + that same fix, so the audit's ledger
> claims now hold ON main); §2.2/§9 updated accordingly.
> (3) New GameState purchase funnel **`purchaseBundle(_:price:)`**
> (GameState.swift:1589) — bundle buys moved out of CosmeticShopView (PR #120).
> (4) New analytics event **`daily_challenge_level_cleared`** (CotD `.oneShot`
> fast-path, PR #123) joined the `events` vocabulary (§8) — analytics-only,
> never a trophy trigger source.
> (5) `clan_events.kind` widened additively (chat/promotion/renamed kinds, v3
> migration, PR #122) — no impact on the trophy hook paths.
> (6) GameState line refs drifted +11 to +65 (e.g. reset/sell-back 650/665 →
> 663/715; string-set helpers 1538-1613 → ~1673-1690) — delta doc §2 has the
> symbol→line map. Supabase schema/RLS/delete-account facts and the
> rarity-architecture reasoning below are otherwise unchanged.

---

## 1. Executive summary

1. **All player progress lives in `UserDefaults.standard`** (~50 `ra_*` keys, write-through `didSet` persistence). No files, no Core Data, no CloudKit, no `NSUbiquitousKeyValueStore` — explicitly confirmed by the audit header in `RollAlong/GameState.swift:5-27` ("No iCloud KV sync in use").
2. **Reinstall without a backup restore loses everything** except the Sign-in-with-Apple Keychain token and StoreKit non-consumables. Trophies persisted the same way would be lost too — a real risk, but identical to the risk already accepted for stars/coins/cosmetics (§3).
3. **The server is a leaderboard mirror, not a save game.** Sync is strictly one-way (local → server, absolute snapshots, `try?` fire-and-forget). There is **no hydrate-from-server path anywhere** (§4.4, §6).
4. **Only Apple-signed-in players exist server-side** (`public.players`, currently **1 row**). A fresh anonymous install has *no* auth identity — its only server footprint is anonymous analytics rows keyed by a per-install UUID (§5). Rarity percentages computed off `players` would be uselessly biased; the analytics `events` table (1,167 rows) is the only install-level denominator that exists today.
5. **Privacy posture:** no PII server-side, nothing "linked to user" in the privacy manifest, analytics is anonymous + INSERT-only, and `delete-account` cascade-deletes all identified rows. Trophy counting must stay in this envelope: anonymous/not-linked counting, cascade-safe per-player rows, ideally increment-only aggregate counters (§6).
6. **No offline queue exists.** Failed social writes are silently dropped; the system survives only because every sync payload is a full snapshot that self-heals on the next push. One-shot "trophy unlocked" events do **not** self-heal — trophy→server sync needs a persisted outbox (§7).
7. **A working telemetry rail already phones home** (`AnalyticsClient` → Supabase `events`, batched, anon-key INSERT-only RLS). It is the obvious rail to piggyback `trophy_unlocked` on, but rarity *reads* need new infra: anon clients cannot SELECT anything from `events` (§8).

---

## 2. Local persistence today

### 2.1 Mechanism

- Single store: `UserDefaults` (injected, `.standard` in production) — `RollAlong/GameState.swift:485-488`.
- Every `@Published` property write-through-persists in its `didSet` (e.g. `currentLevel` → `ra_level` at `GameState.swift:32-34`; `lives` → `ra_lives` at `GameState.swift:132-134`).
- Load happens once in `GameState.init` (`GameState.swift:487-603`) with defensive decoding: missing/corrupt keys fall back to defaults, values are clamped (`GameState.swift:476-482`, coin clamp at `539-540`).
- Dictionaries persist as JSON-encoded `Data` blobs; sets as `[String]` arrays — helpers at `GameState.swift:1538-1613` (`saveStringSet`, `save(_:intValueDict:)`, `save(_:trackProgressKey:)`, etc.).

### 2.2 Key inventory (authoritative list at `GameState.swift:5-27`)

| Domain | Keys (all `ra_*`) | Notes |
|---|---|---|
| Climb progress | `level`, `bestStars`, `bestTime`, `collectedCoins`, `highestUnlocked` | per-level dicts, JSON blobs (`GameState.swift:106-117`) |
| Lives | `lives`, `lastLifeLostAt`, `unlimitedLives` | regen derived at read time (`GameState.swift:119-146`) |
| Economy | `coinBalance`, `tickets`, `goldrushCoinsTotal`, `paidPrices` (**`ra_paidPrices`**, added by PR #120 — `[String: Int]` keyed `"<Type>:<rawValue>"`; feeds `sellBackValue` refunds only) | `GameState.swift:207-250` |
| Cosmetics | `ownedBallSkins/Goals/Trails/Floors/Pits/Boundaries/Music/Bundles/Packs`, `freeGrantedItems`, `equipped*`, `skin` | `GameState.swift:255-296, 436-468` |
| Minigames | `pinballBest`, `zenSeconds`, `goldrushBest`, `rollupBestSeconds`, `minigameWins`, `minigameBests`, `minigameDiffPlays/Wins/Bests`, `playedModeIDs`, `currentModeID` | `GameState.swift:219-243, 310-341, 348-358` |
| Challenge content | `trackProgress`, `completedTracks`, `dailyChallengeDone/Failed/RunStarted`, `dailyStreak`, `lastDailyClaim` | `GameState.swift:298-392` |
| One-time UX / settings | `seenOnboarding`, `seenWelcomeMoment`, `seenTutorialReward`, `haptics`, `sound`, `introEnabled`, `startAtTop`, `notif*`, `name`, `primaryColorHex`, `minigameDifficulty`, `starterPack*`, `lastReviewPromptDate` | `GameState.swift:38-100, 168-201` |
| IAP ledger | `ra_iapDeliveredTxnIDs` | anti-double-grant ledger, cap 200 — **MERGED to `origin/main` at `fb98819`** (2026-07-02; absent at `42d1925`, present in the audited 064f3cd) — `StoreKitManager.deliveredLedgerKey` |
| Analytics identity | `analytics_user_id` | anonymous per-install UUID — `AnalyticsClient.swift:42, 58-67` |

Other stores: **Keychain** holds exactly one item, the Supabase refresh token `ra_supabase_refresh_token` (`AppleAuthManager.swift:131, 312-345`), saved `kSecAttrAccessibleAfterFirstUnlock`, **not** `kSecAttrSynchronizable` (no iCloud Keychain sync). One direct UserDefaults read outside GameState: `ContentView.swift:26` (`ra_introEnabled`).

### 2.3 Reset paths that a trophy design must respect

- `resetProgress()` clears stars/times/coins/unlocks but keeps cosmetics, name, one-time flags — `GameState.swift:663` (post-merge line), triggered from Settings (`SettingsView.swift` Reset sheet).
- `liquidateCoinCosmetics()` ("Sell Back") relocks sellable cosmetics for refund — `GameState.swift:715` (post-merge line; refund is now `sellBackValue = min(coinCost/2, paidPrice)` and clears the item's `ra_paidPrices` entry, MERGED #118/#120). Trophies keyed to "owns X cosmetics" can regress after launch-day unlock; decide whether trophies are ratchets (recommended, PlayStation-style: once earned, never revoked).

## 3. Reinstall / device transfer / iCloud — honest assessment

| Scenario | What survives today |
|---|---|
| Delete + reinstall, same device, no restore | **Nothing local.** UserDefaults wiped with the sandbox. Survivors: (a) Keychain refresh token — iOS preserves Keychain across app deletion, so the app can silently re-enter its Supabase session at next launch (`restoreSession`, `RollAlongApp.swift:38-43`); (b) StoreKit non-consumable (unlimited lives) via `Transaction.currentEntitlements` (`StoreKitManager.swift:216-245`). Consumable coins, stars, cosmetics, bests: **gone**. Analytics UUID regenerates → the install counts as a *new* user in `events`. |
| New device via iCloud backup / device-to-device migration | UserDefaults transfers (app data is in backups by default; **no** `isExcludedFromBackup` usage anywhere — verified by grep). Keychain item (AfterFirstUnlock, non-ThisDeviceOnly) also migrates in encrypted transfers. Effectively lossless. |
| Two devices, same Apple ID | **Divergent saves.** Nothing syncs continuously (no iCloud KV entitlement — `RollAlong.entitlements` contains only `com.apple.developer.applesignin`). If signed in on both, the `players` row is last-writer-wins per absolute-snapshot PATCH. |
| Reinstall while signed in (the ugly one) | Local state resets to level 1; the session silently restores from Keychain; the next level clear PATCHes `climb_level=2` etc. over the server row — **the server copy gets regressed** because sync is one-way push with no merge/max() guard (`GameState.swift:634-648`, `SocialClient.swift:125-135`). |

**Verdict for trophies:** trophies stored only in UserDefaults inherit loss-on-reinstall; trophies mirrored to `players`-style rows inherit the regression-on-reinstall clobber. Neither is acceptable for "permanent achievement" semantics — the trophy architecture needs either (a) a server-side ratchet (monotonic upsert, `GREATEST()`/insert-only unlock rows) for signed-in players, and/or (b) iCloud KV/CloudKit for the local tier. Note most real players restore devices from backup, so day-to-day risk is moderate — but "culture-killer on reinstall" is currently true for every stat in the game, and trophies raise the emotional stakes.

## 4. Supabase backend inventory (live, project `mhwpcwauzvmtmuphtajs`)

### 4.1 Tables (public schema; row counts as of 2026-07-02)

| Table | Rows | Purpose / key columns | RLS |
|---|---|---|---|
| `players` | 1 | One per Sign-in-with-Apple account, `id = auth.uid()`. Comment: "No PII." Headline stats: `display_name` (1-24 chars), `climb_level`, `highest_unlocked`, `total_stars`, `lives`, `coins_collected`, `needs_lives_at`, plus per-mode `*_best`/`*_wins` (pinball, zen_seconds, goldrush, snake, sumo, paintball, marblecup, koth, rollup + `rollup_best_seconds`) | SELECT to `authenticated` (all rows); INSERT/UPDATE own row only (`docs/social-schema.sql:291-303`) |
| `minigame_scores` | 4 | Per-difficulty boards: PK `(player_id, game, difficulty)`, `wins`, `best`; FK → players | authenticated read; upsert own |
| `friendships` | 0 | requester/addressee + status pending/accepted/blocked | visible to participants only (`social-schema.sql:345-362`) |
| `clans` / `clan_members` / `clan_events` | 1 / 1 / 2 | clans-as-lives-community; events feed kinds: created/joined/left/sent_life/requested_life/thanked | authenticated read (clan_events: members only, `social-schema-v2.sql:44-55`) |
| `life_gifts` | 0 | send 1-5 lives, `claimed_at` | participants |
| `events` | **1,167** | Anonymous analytics: `user_id` (device-install UUID, *not* auth.uid — column comment: "Anonymous device-install UUID. Persisted in the app via UserDefaults"), `session_id`, `event_name`, `properties` jsonb, `level`, `app_version`, `ios_version`, `device_model` | **INSERT-only for anon AND authenticated; no SELECT policy at all** (`docs/supabase-schema.sql:88-114`) — only service_role can read |

`auth.users`: **1 row** (a single account has ever signed in). `is_anonymous` column exists (Supabase anonymous-auth capable) but is unused today.

All player-referencing FKs are `ON DELETE CASCADE` (per project memory + delete-account function comments), so deleting an auth user removes the player row and every social row.

### 4.2 Edge functions

Exactly one: **`delete-account`** (verify_jwt=true, ACTIVE). Behavior (read from deployed source): identify caller from JWT → with service role, transfer any clan the caller owns to an heir (officer first, else earliest-joined member; sole-member clans left to cascade) → `auth.admin.deleteUser(userId)` → FK cascade wipes `players`, `clan_members`, `friendships`, `life_gifts`. Client call: `SocialClient.deleteMyAccount()` (`SocialClient.swift:57-87`), invoked from `SettingsView.swift:85-96`. **`events` rows are untouched** — they are keyed by the analytics install UUID, unlinkable to the auth account by design, so account deletion has nothing to delete there.

### 4.3 Migrations

Six in the managed history: `20260625042810 add_minigame_leaderboard_columns` → `20260701035953 add_rollup_leaderboard_columns` (also: social_v2_clan_events_and_needs_lives, social_grant_service_role_clans_minimal, add_competitive_leaderboard_stats, minigame_scores_per_difficulty). The base schemas (`events`, `players`, social v1) predate the migration history — canonical copies live in `docs/supabase-schema.sql`, `docs/social-schema.sql`, `docs/social-schema-v2.sql`. Trophy DDL should enter as a proper migration.

### 4.4 How leaderboards are computed today

**Entirely client-side over raw rows — no SQL aggregation, no views, no RPCs.**

- Client fetches up to N rows of `players` ordered by a PostgREST `order` clause (`climb_level.desc,total_stars.desc` default) — `SocialClient.fetchLeaderboard`, `SocialClient.swift:182-192`.
- Per-difficulty boards read `minigame_scores` with an embedded `players(...)` join — `SocialClient.swift:234-260`.
- "Your rank" = fetch up to 500 rows per board and `firstIndex(of: self)` client-side — `fetchAllRanks` / `fetchMinigameDifficultyRanks`, `SocialClient.swift:267-309`.
- Writes are client-trusted absolute snapshots: `syncProgress` (PATCH own row, `SocialClient.swift:125-135`), `syncMinigameStats` (PATCH, `140-169`), `syncMinigameScore` (upsert `on_conflict=player_id,game,difficulty`, `206-215`), `upsertMyProfile` (`101-121`). No server-side validation beyond CHECK constraints (non-negative, name length).

Implication: a "trophy rarity" percentage has no precedent to copy — nothing today computes an aggregate server-side. Rarity will be the first feature that *requires* a server-computed, anon-readable aggregate (view + scheduled refresh, trigger-maintained counter table, or edge function).

## 5. Identity coverage — the rarity denominator problem

What identity exists for each player class:

| Player class | auth.users | players row | events rows | Trophy-countable today? |
|---|---|---|---|---|
| Fresh anonymous install (the default; sign-in is opt-in via Settings) | none | none | yes — keyed by `ra_analytics_user_id`, a UUID minted on first launch (`AnalyticsClient.swift:58-67`) | only via anonymous events |
| Signed-in (Sign in with Apple) | 1 row | 1 row (created by `upsertMyProfile` after sign-in — `SettingsView.swift:37-55`) | yes (same anonymous UUID; **never joined** to auth.uid anywhere) | fully |
| Reinstaller | may retain auth via Keychain | retained (but regression-clobbered, §3) | **new** UUID → counted as a new user | double-counted |

Hard numbers right now: `players` = 1, `auth.users` = 1, `events` = 1,167 rows across an unknown-but->1 number of install UUIDs (distinct count requires service-role SQL; see `docs/soft-launch-metrics.sql:15-20` query #0). Sign-in conversion is effectively ~0% of installs.

**Consequences for PlayStation-style rarity ("X% of players earned this"):**

- Denominator = `players` count → counts only Apple-signed-in accounts; today that's 1 person; even at scale it biases toward engaged/social players, inflating every rarity percentage's apparent "commonness" among an elite subset.
- Denominator = distinct `events.user_id` → covers every install that ever launched online (closest analogue to PSN's "owners who launched the game"), but: reinstalls double-count, multi-device players double-count, offline-forever installs never count, and the UUID is deliberately unlinkable to the signed-in identity (privacy feature, §6).
- The two identity rails never meet: analytics `user_id` ≠ `auth.uid()`, and nothing joins them. Any trophy design that counts unlocks via one rail and players via the other must document that mismatch — or unify counting on a single rail (e.g. anonymous `trophy_unlocked` events for *all* players, with the same UUID as both numerator and denominator source; or adopt Supabase anonymous auth to give every install an auth identity, which the `is_anonymous` column already supports but would create server rows for every install — a posture change Mac must approve).

## 6. Privacy posture — constraints on server-side trophy counting

Stated posture (project memory: "no-tracking privacy posture"; `players` table comment "No PII"): identity-free by default, anonymous analytics, nothing linked to real-world identity.

Ground truth from `RollAlong/PrivacyInfo.xcprivacy`:

- `NSPrivacyTracking` = **true**, but *solely* for the AdMob ATT/IDFA path (lines 5-28; tracking domains are Google's). First-party data is separate.
- First-party collected types, all declared **Linked=false, Tracking=false, purpose=Analytics**: DeviceID (the anonymous install UUID, lines 37-52), GameplayContent (lines 54-69), PurchaseHistory (event names + product IDs only, lines 71-87), OtherDiagnosticData (hardware/OS strings, lines 89-104). UserDefaults required-reason CA92.1 (lines 108-125).
- `docs/AppStore.md:66-71` still says "Tracking: No / Data collected: None" — **stale** (predates ads/analytics/social); do not treat it as current, but its *spirit* (nothing identity-linked) matches the manifest.

Constraints this puts on trophy counting:

1. **No new identifiers.** Counting must reuse the existing anonymous install UUID (already declared as not-linked DeviceID) or use no identifier at all (pure aggregate increments). No IDFV/IDFA, no fingerprinting, nothing that links unlocks to a person.
2. **Unlock payloads must stay non-PII** — trophy id, timestamp, maybe app_version. A `trophy_unlocked` analytics event fits the existing GameplayContent declaration; a new *identified* trophy table on `players` stays inside the current "no PII, display-name-only" envelope.
3. **Delete-account cascade:** any per-player trophy rows (e.g. `player_trophies(player_id, trophy_id, unlocked_at)`) MUST be `ON DELETE CASCADE` off `players` like every other social table, and the `delete-account` function needs no change if that's true. Decide explicitly whether global rarity counters are (a) derived from surviving per-player rows — deletions retroactively change history and rarity drifts upward for the deleted player's trophies — or (b) kept as detached, increment-only anonymous counters that survive deletion (more privacy-friendly: retains zero per-person data, and account deletion doesn't erase the fact that *someone* earned it). PSN behaves like (b) in practice; recommend (b) with the per-player rows existing only for the signed-in player's own trophy-case UI.
4. **Read access needs care:** rarity percentages must be readable by *everyone* (including signed-out players browsing trophies). Today anon can read nothing. A `trophy_stats(trophy_id, earned_count, player_count, pct)` table/view with `SELECT` granted to `anon` exposes only aggregates — acceptable; granting anon SELECT on raw unlock rows is not.
5. **gh-pages / no-tracking marketing stance** (project memory): rarity is a *game feature*, not analytics — keep its wire traffic on the Supabase first-party rail, never a third-party SDK.

## 7. Offline reality — how features degrade, and what trophy sync must add

The game is fully playable offline (climb, minigames, cosmetics, economy are all local). Current degradation:

- **Signed out** (the default): every `SocialClient` method throws `SocialError.notSignedIn` (`SocialClient.swift:22, 41-52`, error enum at the file tail). Social screens render sign-in pitches: `LeaderboardView.swift:100-101, 650-655`; `FriendsView.swift:66-67, 483-488`; `ClansView.swift:66, 584-587`; `ProfileView.swift:637, 656` ("Sign in to see your global ranks.").
- **Signed in but offline:** reads surface error states in-view; writes are `try? await` fire-and-forget from detached Tasks — `syncSocialProgress` (`GameState.swift:634-648`), `syncMinigameStats` (`GameState.swift:1088-1109`), `syncMinigameScore` (`GameState.swift:1237-1245`), post-sign-in `upsertMyProfile` (`SettingsView.swift:40-55`). **A failed write is dropped forever — no queue, no retry, no dirty flag.**
- Why that's survivable today: every payload is an absolute snapshot of monotonically-growing local state, so the *next* successful sync (next level clear, next minigame finish) fully repairs the server row.
- Why it's NOT survivable for trophies: "unlocked trophy X at time T" is a one-shot fact. Under the current pattern an offline unlock would never reach the server (wrong rarity counts, empty server trophy case). **Trophy→server sync needs a persisted outbox** — e.g. a UserDefaults-backed `ra_pendingTrophyUnlocks` set drained on launch/foreground/sign-in — or must be derivable/replayable from a local snapshot ("here are ALL my unlocked trophy ids", idempotent upsert), which converts one-shot events back into self-healing snapshots and is the pattern most consistent with the existing code.
- Cautionary precedent: `AnalyticsClient`'s buffer is **memory-only** (cap 1,000; retry-on-next-flush at `AnalyticsClient.swift:52, 117-126, 149-164`; background flush at `RollAlongApp.swift:67-72`) — events die with the process. Don't route trophy unlocks through it without adding persistence, or accept undercounting.
- Life gifts show the only server→local value flow that exists (`claimGift` then `gameState.addLives`, `FriendsView.swift:592-593`) — proof the codebase has no generic server-state-restoration machinery to reuse.

## 8. Existing telemetry — what phones home today, and what to piggyback on

Yes — two first-party rails plus AdMob:

1. **AnalyticsClient → `POST /rest/v1/events`** (`AnalyticsClient.swift:25-35, 130-165`): anonymous, batched (30 s timer or 8 events), anon-key auth, `Prefer: return=minimal`. Event vocabulary in the wild (grep of `track(` call sites): `app_launch` (with level/lives/coin_balance/total_stars/highest_unlocked — `RollAlongApp.swift:44-58`), `app_resume`, `level_complete`/`level_fail`, `minigame_entered`, `minigame_result` (game/difficulty/won/payout — `GameState.swift:1248-1254`), `*_round_over`-family, `cosmetic_purchased`/`cosmetic_equipped`, `pack_purchased`, `iap_purchased/failed/pending/cancelled`, `ad_*`, `att_response`, `result_shared`, `ticket_earned`, `daily_challenge_started/completed`, `welcome_moment_dismissed`, `buy_coins_sheet_opened`, `buy_lives_sheet_opened`, `home_lives_pill_tapped`, `goldrush_charge`… (call sites across `BallGameView`, `HomeView`, `CosmeticShopView`, `AdManager`, `GoldRushView`, `PaintBallView`, `MarbleCupView`, `Cosmetics.swift`, `DiscoBallView`). Post-audit addition on main: `daily_challenge_level_cleared` (props `sub_level`, `time`; emitted from BallGameView's merged CotD `.oneShot` fast-path, PR #123 — fire-and-forget like everything on this rail, never a trophy trigger source). Note: sessions are per-cold-start only — `startNewSession()` is never called despite the 5-minute-idle comment at `RollAlongApp.swift:73-78`.
2. **SocialClient → `players`/`minigame_scores`** (signed-in only, §4.4) — already carries exactly the stat families most launch trophies would key off (climb level, stars, per-mode wins/bests).
3. **Google Mobile Ads SDK** (AdManager) — third-party; irrelevant to trophies, keep it that way.

**Analysis infra:** `docs/soft-launch-metrics.sql` (194 lines) is a copy-paste SQL-editor dashboard run with service_role — DAU, D1/D7 retention by install cohort, session length, mode popularity, clear-rate, share-rate, cosmetic pull, monetization funnel. It demonstrates the intended pattern: anon clients write events; humans (or a future cron) aggregate with service role. There is **no** automated aggregation job, no pg_cron usage, no readable-aggregates surface yet.

**Piggyback assessment for live rarity:** the write rail exists and is proven (1,167 rows). The missing pieces are (a) a durable client-side unlock record/outbox (§7), (b) a server aggregate (`trophy_stats`) maintained by trigger or scheduled job over either anonymous unlock events or per-player unlock rows, (c) an anon-readable SELECT surface for that aggregate — the first anon-readable object in the project, so it deserves an explicit RLS decision, and (d) a denominator decision (§5): distinct `events.user_id` (all installs, noisy) vs `players` count (signed-in only, biased) vs "players who reached the trophy's surface" (PSN-style earned-vs-eligible).

---

## 9. Reference index

| Topic | File:lines |
|---|---|
| UserDefaults key audit header | `RollAlong/GameState.swift:5-27` |
| GameState load path / helpers | `RollAlong/GameState.swift:487-603, 1538-1613` (at 064f3cd; helpers ≈ :1673-1690 at `origin/main`) |
| Reset / sell-back paths | `RollAlong/GameState.swift:650-718` (at 064f3cd; `resetProgress` :663 / `sellBackValue` :685 / `liquidateCoinCosmetics` :715 at `origin/main`) |
| Sync call sites (fire-and-forget) | `RollAlong/GameState.swift:634-648, 1088-1109, 1237-1245`; `RollAlong/SettingsView.swift:40-55` |
| Analytics client (identity, buffer, POST) | `RollAlong/AnalyticsClient.swift:20-165` |
| Social client (session, sync, boards, delete) | `RollAlong/SocialClient.swift:27-115, 125-309` |
| Auth + Keychain | `RollAlong/AppleAuthManager.swift:33-179, 312-345`; `RollAlong/RollAlongApp.swift:38-43` |
| StoreKit ledger + entitlement restore | `RollAlong/StoreKitManager.swift:136-245` (at 064f3cd) — **the launch-race ledger MERGED to main at `fb98819`** (`deliveredLedgerKey` at :166 there); the file was heavily rewritten on main, relocate by symbol |
| Privacy manifest / entitlements | `RollAlong/PrivacyInfo.xcprivacy:1-127`; `RollAlong/RollAlong.entitlements` |
| Schemas + metrics | `docs/supabase-schema.sql:27-114`; `docs/social-schema.sql:291-362`; `docs/social-schema-v2.sql:44-64`; `docs/soft-launch-metrics.sql` |
| Stale privacy copy (do not cite as current) | `docs/AppStore.md:49, 66-71` |
| Live backend | Supabase project `mhwpcwauzvmtmuphtajs`: tables/rows via MCP `list_tables`; `delete-account` edge function source via `get_edge_function`; 6 migrations 2026-06-25 → 2026-07-01 |
