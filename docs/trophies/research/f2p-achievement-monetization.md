# Achievements in F2P Mobile: Retention, Monetization Interplay, and the Prestige Line

**Date:** 2026-07-02
**Scope:** Web research on how achievement/trophy systems interact with free-to-play monetization and retention,
framed for Roll Along — an indie iOS marble game with a cosmetics-driven economy
(coins, lives, IAP coin packs, cosmetic collections; no ads, no-tracking privacy posture).
**Method note:** Sources favor published studies, platform documentation, and postmortem/design writing.
Vendor-blog statistics are flagged. Claims that could not be traced to a primary source are marked "(unverified)".

**TL;DR:**

- Achievements measurably help early/mid-game retention; social features carry the endgame — plan the trophy list as a bridge into Friends/Clans.
- Players respect trophies that celebrate goals they already had (collections, skill feats, discovery) and resent trophies that create obligations (expiring checklists, purchases, grinds).
- The safest reward philosophy for a bounded cosmetic economy: status-first, a few earned-only vanity cosmetics at true milestones, zero recurring currency payouts.
- Apple's iOS 26 Games app makes Game Center achievements a free discovery/re-engagement channel that fits a no-tracking posture.
- Rarity display motivates hunters and discourages casuals; show tier labels, gate raw percentages behind a population threshold (day-1 numbers are noise).

---

## 1. Retention evidence

**The strongest peer-reviewed signal: achievements drive early/mid-game retention; social drives endgame.**

- Park, Cha, Kwak & Chen analyzed in-game logs of 51,104 players in an online multiplayer game ("Achievement and Friends," WWW'17 companion).
- Finding: "Achievement features are important for players at the initial to the advanced phases, yet social features become the most predictive of longevity once players reach the highest level offered by the game." ([arXiv:1702.08005](https://arxiv.org/abs/1702.08005))
- Implication: achievements are a D1–D30 tool; past the content ceiling, friends/clans carry retention. Design the trophy list to hand players off to the social layer.

**Badges causally increase activity (field experiment, not just correlation).**

- Hamari ran a two-year field experiment (N≈1,410 pre / 1,579 post) introducing a badge system on a peer-to-peer service.
- Users in the badge condition were significantly more active on all four measured behaviors (posts, transactions, comments, page views).
- ([Computers in Human Behavior 71, 2017, DOI 10.1016/j.chb.2015.03.036](https://www.sciencedirect.com/science/article/abs/pii/S0747563215002265))
- Caveat: a marketplace, not a game — but one of the few true experiments on badge systems rather than correlational snapshots.

**Why players say they chase them (qualitative evidence).**

- Cruz, Hanus & Fox, "The need to achieve" (CHB 71): focus-group players valued meta-rewards for promoting different ways to play, positive feedback, and self-esteem / online-offline social status. ([ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S0747563215300960))
- Some participants felt *compelled* to earn everything — completionism has a compulsive edge designers must respect.
- Players were divided on whether badges signal skill or merely time invested — a reason to keep pure-grind trophies rare.
- A 2024 FDG paper on PS Trophy preferences reaches similar conclusions about recognition and social play. ([ACM DOI 10.1145/3649921.3656989](https://dl.acm.org/doi/10.1145/3649921.3656989))

**Completionism is a minority behavior — design for the curve, not the completionist.**

- Steam achievement analysis (n=725 games): very few players finish main-path content — mean 14%, median 10% completion. ([Entertainment Computing](https://www.sciencedirect.com/science/article/abs/pii/S1875952118300181))
- Kwak (WebSci'22) built a complete PlayStation trophy dataset to characterize achievement design and completion systematically. ([arXiv:2205.15163](https://arxiv.org/abs/2205.15163))
- Practical read: completionists are loud, loyal, and rare; the *first third* of the achievement list is the only part most players will ever see. Front-load delight.

**Sales/engagement correlation (old but frequently cited).**

- EEDAR studied 4,615 achievements across 187 Xbox 360 titles (2005–2007): more achievements correlated with higher Metacritic scores and higher US sales; online-play achievements correlated with ~50% more sales.
- EEDAR's own caveat: big budgets confound the correlation. ([Q&A: EEDAR's Zatkin On The Theory Of Achievements, Game Developer](https://www.gamedeveloper.com/game-platforms/q-a-eedar-s-zatkin-on-the-theory-of-achievements))

**Vendor-blog numbers to treat as directional only (unverified):**

- "70% of players motivated by short-term achievements"; "50% higher engagement with robust progression systems"; "15% higher week-1 retention with achievement sharing." ([MoldStud](https://moldstud.com/articles/p-the-science-of-retention-in-mobile-games))
- These circulate widely without traceable methodology; do not build projections on them.

---

## 2. Monetization interplay patterns

Ordered from most to least respected by players:

**a) Achievements that celebrate collection completion — respected.**

- Collection sets are among the strongest engagement mechanics in mobile: an 11-of-12 collection occupies mental space until closed (Zeigarnik effect), and set completion drives both play and spend. ([Yu-kai Chou on collection sets](https://yukaichou.com/advanced-gamification/game-design-technique-collection-sets/); [Psychology of Games on Zeigarnik/quest logs](https://www.psychologyofgames.com/2013/03/the-zeigarnik-effect-and-quest-logs/))
- Monopoly GO's sticker albums are the commercial extreme: milestone chests per set, a headline prize for full-album completion, pack sales riding the whole loop. ([TheGamer album guide](https://www.thegamer.com/monopoly-go-sticker-albums-faq-complete-guide/))
- Why the trophy version is respected: the trophy itself asks for nothing — it decorates a goal the player already wanted. The monetization pressure (if any) lives in the underlying collection, not the trophy.

**b) Achievements as soft tutorials for underused/monetized features — respected when honest.**

- Players often skip tutorials but read achievement lists; achievements get attention where help text does not. ([Faye Seidler, "Achievements are an Important Part of Game Design"](https://fayeseidlers.medium.com/achievements-are-an-important-part-of-game-design-c35a0d40533f))
- Minecraft's advancement tree doubles as a feature map; Into the Breach uses achievements to teach non-obvious tactics. (same source; also [Designing and Building a Robust, Comprehensive Achievement System](https://www.gamedeveloper.com/design/designing-and-building-a-robust-comprehensive-achievement-system))
- Apple's HIG endorses ordering achievements to match "the most common path through your game." ([HIG: Game Center](https://developer.apple.com/design/human-interface-guidelines/game-center) — quote is from the earlier dedicated achievements page, since folded into this one; original path `/design/human-interface-guidelines/technologies/game-center/achievements` is retired, archived copies exist on the Wayback Machine)
- The honesty line: "Play one round of each minigame" is discovery; "Win 500 rounds" is a chore wearing a tutorial's clothes.

**c) Achievements tied to battle-pass/track completion — tolerated, sliding toward resented.**

- Live-service players increasingly describe pass challenges as "chores, not fun." ([EA Forums, Battlefield 6](https://forums.ea.com/discussions/battlefield-6-general-discussion-en/battle-pass-challenges-are-a-chores-not-fun/12854411))
- Commentary ties engagement decline and "FOMO treadmill" burnout to stacked time-limited task systems across games. ([Game Rant](https://gamerant.com/live-service-battle-pass-seasons-fomo-wow-overwatch-2-diablo-4-bad/); [Battle Pass Fatigue, 2026](https://www.kidelight.com/2026/02/battle-pass-fatigue-is-live-service.html))
- The dividing line in sentiment: permanent, self-paced goals are respected; expiring checklists that convert play into obligation are resented.
- An achievement for finishing a *permanent* 100-level Challenge Track reads as a monument; an achievement for finishing a *seasonal* pass reads as a whip.

**d) Achievements that require engaging the store — resented.**

- "Spend X" / "buy Y" achievements convert the trophy list into advertising; players identify the business motive immediately.
- Community analysis of DLC-gated achievements: hunters feel "locked into a contract to buy all future DLC" to preserve 100%. ([Steam discussion](https://steamcommunity.com/discussions/forum/7/864974467636676690/)) — detailed in §3.

**Where achievements sit in the F2P retention stack:**

- Daily rewards, streaks, and passes are *appointment* mechanics; achievements are the *permanent* layer that narrates a player's history. ([Design The Game overview](https://www.designthegame.com/learning/tutorial/daily-rewards-streaks-battle-passes-player-retention))
- They complement the event cadence; they should never compete with it for urgency.

---

## 3. The ethical line: pay-gated trophies and manipulation

**Documented backlash patterns:**

- **Progression/advantage sold for money** draws the fiercest reactions: Star Wars Battlefront II (2017) forced EA to pull microtransactions pre-launch; Star Citizen's real-money-only "Flight Blades" reignited identical anger in 2025. ([Windows Central](https://www.windowscentral.com/gaming/star-citizens-new-flight-blades-microtransactions-spark-uproar))
- Players' stated principle: money must not replace merit; systems must stay neutral between payers and non-payers. ([pay-to-win deep dive](https://yigitatak.medium.com/a-deep-dive-into-pay-to-win-in-video-games-3fb1e46e232c))
- **Completion percentage held hostage by paid content:** achievement hunters describe DLC achievements as coercive — choose between a broken 100% after hundreds of hours, or buying DLC you don't want. ([Steam 100% Achievements Group](https://steamcommunity.com/groups/100pAG/discussions/1/1658943116241927286/))
- **Trophies as merch upsell:** Sony's 2025 "Franchise Rewards" (earn a Ghost of Tsushima platinum → *the right to buy* a $25 pin / $30 shirt) was panned as commercializing an intrinsic accomplishment. ([CBR, 2025-09-25](https://www.cbr.com/playstation-franchise-rewards-trophies-mistake/))
- **Overjustification risk:** attaching expected extrinsic rewards to intrinsically fun play can crowd out intrinsic motivation — the classic effect applied to achievements. ([Psychology of Games](https://www.psychologyofgames.com/2016/10/the-overjustification-effect-and-game-achievements/); [Machinations glossary](https://machinations.io/glossary/overjustification-effect); [Wikipedia](https://en.wikipedia.org/wiki/Overjustification_effect))

**Principles for keeping trophies prestige-pure while still supporting the business:**

1. **Every trophy earnable at $0.** Money may accelerate adjacent goals (cosmetics, lives) but must never be a requirement on the trophy path. One paid trophy re-frames the entire list as marketing.
2. **Trophies may point at monetized surfaces, never through them.** "Complete the Aurora collection" is fine if the collection is completable with earned coins; "Buy a coin pack" is not.
3. **No expiry, no removal.** Unobtainable trophies are the single most-litigated grievance in completionist communities (§7.5–7.6).
4. **The trophy list is the product's showroom, not its cash register.** EEDAR's framing: achievements extend engagement and word-of-mouth; the revenue effect is indirect. ([Game Developer](https://www.gamedeveloper.com/game-platforms/q-a-eedar-s-zatkin-on-the-theory-of-achievements))
5. **Decide the reward philosophy before launch and hold it.** Retrofits reliably backfire (§4, §7.12).

---

## 4. The reward question: nothing vs. currency vs. exclusive cosmetics

**Option A — No reward (PlayStation purity): status is the reward.**

- Sixteen years of PSN show status-only sustains a large hunting culture: platinum culture, rarity leaderboards, third-party ecosystems. ([PSNProfiles trophy system guide](https://psnprofiles.com/guide/18274-the-trophy-system-explained))
- Cost: mainstream players call trophies "pointless" and press for tangible value. ([Inverse](https://www.inverse.com/gaming/playstation-trophies-ps4-ps5-xbox-achievements-pointless))
- Sony's attempts to bolt value on afterward keep failing:
  - Sony Rewards trophy-points passes — shelved (per Inverse, above).
  - PlayStation Stars — earning ended July 2025, program fully ends 2026-11-02. ([PlayStation.Blog](https://blog.playstation.com/2025/05/21/playstation-stars-coming-to-a-close-as-sie-evaluates-new-ways-to-evolve-future-loyalty-program-efforts/))
  - Franchise Rewards — ridiculed (§3).
- Lesson: purity is stable; retrofitted rewards are churn.

**Option B — Small currency rewards.**

- Clash of Clans, the most durable F2P game in existence, pays small amounts of *premium* gems for achievements — deliberately seeding free players with tastes of premium currency. ([CoC Wiki: Gems](https://clashofclans.fandom.com/wiki/Gems); [achievement gem list](https://www.clasher.us/guide/free-gems-achievements-clash-of-clans))
- It works there because gem sinks are effectively unbounded (time-skips scale forever).
- In a *bounded cosmetic economy*, every achievement coin is a permanent faucet competing with IAP coin packs and must be netted against catalog pricing forever.
- Risk profile: medium — devalues coins if generous, insults if stingy ("5 coins for a platinum-tier feat"), and converts the trophy list into an economy surface requiring perpetual balancing.

**Option C — Exclusive cosmetic at milestones.**

- Grants a *non-economic* good: visible, brag-worthy, zero coin inflation — and it advertises the cosmetics system itself.
- This is the standard prestige pattern (ranked/mastery skins, emblems); PSN's closest analog was trophy-linked exclusive themes (only nine games ever offered them, per Inverse above).
- Risk: if the exclusive looks *better* than paid items it competes with the shop; if it reads as *earned regalia* (gold trim, laurels, engraved marble) it complements the shop.

**What successful actors chose:**

| Actor | Choice | Notes |
|---|---|---|
| Xbox | Points (Gamerscore) + rarity display, no goods | Diamond icon + distinct sound for sub-10% unlocks |
| PlayStation | Status only; value experiments repeatedly abandoned | Stars sunset 2026; Franchise Rewards backlash 2025 |
| Steam | Status + profile showcases | Policed inflation with 100-achievement confidence gates (§7.2) |
| Clash of Clans | Small premium-currency payouts | Viable only atop unbounded currency sinks |
| Monopoly GO | Collections *are* the monetization; in-economy prizes | Album completion = headline seasonal prize |

- Synthesis for a bounded, cosmetics-only economy: **status-first, a few exclusive vanity cosmetics at true milestones, no recurring currency payouts.**
- This also sidesteps the overjustification trap (§3): the reward is recognition, not payment.

---

## 5. App Store constraints and Apple ecosystem norms

**Game Center capacity and rules:**

- Up to **100 achievements** per game; **1,000 points** total; max 100 points per achievement. ([App Store Connect: Manage achievements](https://developer.apple.com/help/app-store-connect/configure-game-center/manage-achievements/))
- Achievements can be **hidden** until earned, and optionally repeatable. (same source)
- Artwork is required per achievement; localized pre-earned and earned descriptions per locale. ([reference](https://developer.apple.com/help/app-store-connect/reference/game-center/achievements/); [HIG: Game Center](https://developer.apple.com/design/human-interface-guidelines/game-center))
- Achievements must be approved in App Store Connect before they are available to players. (Manage achievements, above)

**HIG norms:**

- Display order = upload order; Apple recommends mirroring "the most common path through your game."
- "Be creative with an achievement's title, but straightforward with its description."
- "Providing beautiful achievements that reward a variety of gameplay styles and skill levels can encourage players to stay engaged." ([HIG: Game Center](https://developer.apple.com/design/human-interface-guidelines/game-center) — quotes in this section are from the earlier dedicated achievements HIG page, since folded into the Game Center page; verify exact wording against the live page or a Wayback capture of the retired path)

**The iOS 26 Games app is a live distribution channel:**

- Achievements and leaderboards surface in the system Games app Library, filterable per game. ([MacRumors iOS 26 Games app guide](https://www.macrumors.com/guide/ios-26-games-app/))
- Apple: players "get notified if a friend passes their score, so they can jump back in or redownload your game — even if they no longer have your game installed." ([Apple: Games app for developers](https://developer.apple.com/games-app/))
- Personalized discovery draws on what friends play; system-level score/time **Challenges** can be configured per game. ([Manage challenges](https://developer.apple.com/help/app-store-connect/configure-game-center/manage-challenges/))
- For a no-ads, no-tracking game this is rare free re-engagement infrastructure — Apple's own, no third-party SDK.

**Rarity is platform-computed now:**

- `GKAchievementDescription.rarityPercent` — "the percentage of players of a game that earned the achievement." ([Apple Developer docs](https://developer.apple.com/documentation/gamekit/gkachievementdescription/raritypercent-4bh6k))
- Introduced in iOS/iPadOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0 (confirmed from Apple's doc availability data; matches platform-comparison.md §3). Returns `nil` when there isn't enough data to compute rarity. Presentation thresholds remain app-side (§6).

**App Review guidelines touching achievements:** ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/))

- **4.5.3** — do not use Game Center to spam; do not mine/exploit Player IDs.
- **4.5.5** — use Player IDs only as approved; never display them to third parties.
- **3.2.2(x)** — apps must not force store-related actions to unlock functionality, but *may* "incentivize users to take specific actions within apps (e.g. completing a level...)".
- Nothing prohibits achievements granting in-game currency or cosmetics. The constraint set is spam, privacy, and coercion — not rewards.

---

## 6. Rarity display psychology ("0.9% of players earned this")

**Status signaling works:**

- PSN buckets trophies Common / Rare / Very Rare / Ultra Rare by earn percentage; rarity is core to hunting culture. ([PSNProfiles guide](https://psnprofiles.com/guide/18274-the-trophy-system-explained))
- Third-party leaderboards weight ultra-rares so heavily that a handful of sub-5% completions outrank thousands of easy trophies. ([Scorpio of Shadows on rarity leaderboards](https://www.scorpioofshadows.com/post/the-hidden-psnprofiles-leaderboard-changing-how-we-look-at-trophy-hunting))
- Xbox marks sub-10% achievements with a diamond icon and a distinct unlock sound — celebration scaled to rarity, added platform-wide in 2016. ([TrueAchievements forum](https://www.trueachievements.com/forum/viewthread.aspx?tid=976998); [Xbox wiki](https://xbox.fandom.com/wiki/Achievement))

**Goal-gradient effects cut both ways:**

- Effort accelerates as a visible goal nears; endowed progress (a bar that starts above zero) reliably boosts completion. ([Learning Loop](https://learningloop.io/plays/psychology/goal-gradient-effect); [LogRocket](https://blog.logrocket.com/ux-design/goal-gradient-effect/))
- A rarity label on a *nearly finished* achievement is fuel; "0.9%" on an *unstarted* one signals "not for you" to the median casual player.
- Platform mitigation: tier labels (Ultra Rare) at the surface, raw percentages on detail views only.

**Cold start: day-1 percentages are noise.**

- Steam's global stats illustrate every failure mode: denominators include everyone who ever launched the game; offline play and private profiles distort counts; sale spikes crater percentages overnight; the client reports different rarity values in different places. ([LevelUpTalk explainer](https://leveluptalk.com/news/steam-achievement-percentages-explained/); [Steam discussion](https://steamcommunity.com/discussions/forum/0/3361398061434477458/))
- At launch, "87% earned this" (only diehards installed) flips within weeks as the casual wave arrives.
- Live-game practice: suppress rarity display until a minimum earner population exists, then show tiers, recompute rolling. `rarityPercent` handles the math, not the presentation threshold — that is app-side.

---

## 7. Anti-patterns catalog

1. **Achievement-for-nothing inflation.** "Press Start"-tier awards and five-achievements-in-a-minute games (Avatar: The Burning Earth) are community punchlines that devalue whole lists. ([WatchMojo](https://www.watchmojo.com/articles/top-10-dumbest-achievements-in-video-games)) McClanahan's rule: the system "only has as much weight as the easiest means" of earning. ([Achievement Design 101, 2009](https://www.gamedeveloper.com/design/achievement-design-101))
2. **Achievement spam as a genre.** Steam "fake games" shipped 1,000–3,000 achievements unlockable in minutes until Valve imposed a 100-achievement cap plus confidence gates in 2018 — platform-level proof inflation gets policed. ([Kotaku on spam](https://kotaku.com/achievement-spam-games-are-causing-controversy-on-steam-1796528445); [Kotaku on Valve's limits](https://kotaku.com/valve-adds-limits-to-steam-achievements-to-fight-rise-o-1826873740); [Game Developer](https://www.gamedeveloper.com/business/valve-introduces-limits-for-new-games-to-prevent-fake-ones-from-gaming-steam))
3. **Grind achievements that fight the fun.** "Press A 2,047 times" (C&C3); idle-until-he-smokes (The Saboteur). Grinding is only acceptable when it overlaps natural play. ([Achievement Design 101](https://www.gamedeveloper.com/design/achievement-design-101); [Toptenz](https://www.toptenz.net/top-10-worst-types-of-video-game-achievements.php))
4. **Achievements that corrupt play.** Multiplayer awards that incentivize throwing matches or exploiting teammates — "players do what's efficient, not what's fun." ([Achievement Design 101](https://www.gamedeveloper.com/design/achievement-design-101)) Roll Along analog: "lose 10 Sumo rounds" would teach sandbagging vs. the AI.
5. **Unobtainable achievements after content removal/server shutdown.** The most persistent grievance in hunter communities; permanently broken completion poisons reviews for years. ([Steam suggestions thread](https://steamcommunity.com/discussions/forum/10/592912124322419164/); [Midnight Club: LA server closure](https://www.trueachievements.com/forum/viewthread.aspx?tid=446463); [Sea of Thieves legacy-achievement debate](https://www.seaofthieves.com/community/forums/topic/152170/legacy-achievement-removal-if-never-unlocked-in-order-to-accurately-reflect-completion))
6. **Time-limited / event-exclusive achievements.** Subclass of #5: permanent haves/have-nots, skewed completion stats, and a no-win removal decision later (earners object to removal; everyone else objects to keeping). (same sources)
7. **Pay-gated completion.** DLC/IAP-required achievements read as coercion; hunters describe feeling contractually obligated to keep buying. ([Steam discussion](https://steamcommunity.com/discussions/forum/7/864974467636676690/))
8. **Spoiler and purposeless-secret achievements.** Story-beat trophies spoil endings (BioShock's "good ending"); hidden achievements mostly push players to guides. Reserve hidden flags for genuine surprises. ([Achievement Design 101](https://www.gamedeveloper.com/design/achievement-design-101))
9. **Missable / point-of-no-return achievements.** Natural progression should never permanently lock one out. (same source) Roll Along analog: never key a trophy to a specific level layout — climb levels are swappable content files (LevelOverrides.json).
10. **Toast spam at the wrong moment.** Popups that interrupt play and awards misaligned with player goals are catalogued "achievement sins." ([Steve Bromley](https://www.stevebromley.com/blog/2012/12/05/4-achievement-sins-in-games/)) In a tilt-controlled game, a mid-run banner is a death sentence — queue to run end.
11. **Sync losses wiping progress.** Game Center achievement sync failures and lost progress are a recurring complaint class on Apple's own forums; offline unlocks that never reconcile destroy the long-horizon trust achievements exist to build. ([Apple Community: not syncing](https://discussions.apple.com/thread/254674614); [not unlocked](https://discussions.apple.com/thread/254976860); [example developer FAQ](https://support.inxile-entertainment.com/hc/en-us/articles/115004493867-Game-Center-Achievements-Not-Showing-iOS))
12. **Retrofitting rewards onto a prestige system.** Sony's serial failures — Rewards passes shelved, Stars sunset, Franchise Rewards backlash (§4) — show that changing what trophies *mean* after the fact reliably backfires.

---

## Recommendations for Roll Along

- **Ship trophies as a prestige system, not an economy faucet.** No recurring coin payouts. The coin economy (750–1500 cosmetic tiers, IAP coin packs) is bounded; achievement coins would be a permanent uncontrolled faucet competing with the game's only revenue stream. Clash of Clans' currency-payout model only works atop unbounded sinks (§4B).
- **Reserve 3–5 exclusive vanity cosmetics for true milestones** — e.g., an engraved trophy-gold ball for platinum-equivalent completion, a laurel roll trail for finishing every Challenge Track. Earned-only, never in shop or rotation; reuse the gating machinery already built for Diamond/Money items. Style them as *earned regalia* (gold trim, laurels), visually distinct from purchasable families so they advertise the catalog instead of undercutting it (§4C).
- **Every trophy earnable at $0, forever.** No "spend coins," no "buy a pack," nothing requiring an IAP-exclusive item. Exclude the secret Money/Diamond cosmetics from all collection-completion trophy math — a completion trophy that silently requires the 10,000-coin IAP is a pay-gated trophy in a costume (§3, §7.7).
- **Celebrate collection completion per-collection** ("Complete the Aurora collection"). It converts the existing cosmetics catalog into a trophy surface at zero economy cost and harnesses set-closure (Zeigarnik) motivation — the monetization-adjacent pattern players demonstrably respect most (§2a).
- **Use the first ~15 trophies as a discovery map:** one per minigame played, first pinball table, first Challenge Track started, first friend added, first clan joined. Achievement lists get read where tutorials get skipped (§2b) — and since achievements carry early retention while social carries endgame (§1), point early trophies *toward* Friends/Clans deliberately.
- **Key trophies to lifetime stats, never to specific level content.** GameState already tracks lifetime counters (total coins, minigame stats synced to Supabase); trigger from those. A trophy naming "level 47's diamond corridor" becomes unobtainable after a LevelOverrides content swap (§7.5, §7.9).
- **No time-limited trophies.** Daily Challenge and seasonal events get leaderboards and event rewards; trophies are permanent monuments (§2c, §7.6). Finishing a *permanent* 100-level Challenge Track is exactly the kind of monument worth a trophy.
- **In-app trophy room is the source of truth; Game Center is a mirror.** Persist locally (as lives/coins already are), report to GameKit opportunistically, reconcile with max-merge on conflict, never trust remote for restore (§7.11).
- **Budget the Game Center list deliberately:** stay well under the 100-achievement / 1,000-point cap with headroom for future minigames and tracks; hidden flags only for genuine secrets (Money-cosmetic discoveries); upload order = the common player path per HIG (§5).
- **Do Game Center properly because of the iOS 26 Games app:** system-surfaced achievements, leaderboards, and configured Challenges are free discovery and re-engagement ("redownload" notifications) fully compatible with the no-ads, no-tracking posture — it is Apple infrastructure, not a tracker SDK (§5).
- **Rarity display: tiers first, numbers later.** Show Common/Rare/Ultra Rare labels with an Xbox-style distinct celebration for sub-10% unlocks; suppress raw percentages until a minimum earner population exists (e.g., first ~30 days or a few thousand earners) because day-1 percentages are cold-start noise (§6).
- **Toast discipline:** queue unlocks earned mid-run and present one coalesced banner at run end; never interrupt an active tilt run (§7.10).
- **Write difficulty that is fun-hard, not chore-hard.** Every hard trophy should pass McClanahan's test — "why is this hard, and is that reason fun?" Precision feats (gold-star a Pinnacle level, deathless track phases) yes; raw volume counters only where they accrue from natural play (§7.3). And nothing that rewards playing *badly* in minigames (§7.4).
- **Commit to the reward philosophy in writing before launch.** Sony's decade of reward retrofits is the cautionary tale (§7.12); an economy-integrity note in `docs/economy/` stating "trophies never mint coins" will keep future balance passes honest.

---

*Compiled 2026-07-02 from web sources; all URLs inline. Vendor-blog statistics are flagged; platform behavior (Game Center, iOS 26 Games app) reflects documentation available as of this date.*
