# PlayStation Trophy System — Research Brief

**Date:** 2026-07-02
**Purpose:** Source-of-truth research on Sony's trophy system as design inspiration for a Roll Along trophy system. Every claim cites a URL; anything that could not be pinned to a source is tagged **(unverified)**. Sony's actual TRC (Technical Requirements Checklist) is confidential, so all developer-rule figures are community-documented reconstructions.

---

## 1. Anatomy of the system

### 1.1 History in one paragraph

Trophies launched with PS3 firmware 2.40 on July 2, 2008 (the update was pulled the same day over a bricking bug and reissued as 2.41 on July 8); [Super Stardust HD was the first game with trophy support](https://en.wikipedia.org/wiki/Super_Stardust_HD). Trophy support became mandatory for most new certified games from 2009 onward, and the original platinum icon was a pink crown that was replaced before any platinum-bearing game shipped ([PlayStation Wiki/Fandom](https://playstation.fandom.com/wiki/Trophies), [PlayStation.Blog 2008 walkthrough](https://blog.playstation.com/2008/06/30/firmware-v240-walkthrough-part-2-trophies/comment-page-10/)). Rarity statistics were added with the PS4 in 2013 ([PlayStationTrophies forum](https://www.playstationtrophies.org/forum/topic/235402-ps4-trophy-rarity-question/)). The one major overhaul came October 7, 2020, just before PS5 launch ([PlayStation.Blog](https://blog.playstation.com/2020/10/07/upcoming-trophy-levelling-changes-detailed/)).

### 1.2 Grades and points

Four grades, officially ranked by difficulty: Bronze < Silver < Gold < Platinum ([PlayStation support](https://www.playstation.com/en-us/support/games/how-to-earn-trophies-on-playstation--consoles/)).

| Grade | Points (post-Oct 2020) | Notes |
|---|---|---|
| Bronze | 15 | Baseline tasks |
| Silver | 30 | Mid-difficulty |
| Gold | 90 | Hard/long tasks |
| Platinum | 300 (was 180 pre-Oct 2020) | Awarded for completing the rest of the base list |

Point values: [PSNProfiles "The Trophy System Explained"](https://psnprofiles.com/guide/18274-the-trophy-system-explained), [PSU formula article](https://www.psu.com/news/here-is-how-playstations-new-trophy-system-formula-works-and-what-value-is-attributed-to-each-trophy/); the 180→300 platinum change is confirmed empirically in [Kwak, WebSci'22](https://arxiv.org/abs/2205.15163).

### 1.3 The Platinum

- Earned by collecting **every other trophy in the base (non-DLC) list**. In a dataset of 377,938 trophies, **70.3% of platinum conditions literally contain "all" or "every"** (vs 6.8%/13.6%/15.7% for bronze/silver/gold) — the platinum is structurally "the completion award" ([Kwak 2022](https://arxiv.org/abs/2205.15163)).
- Historically only "full-size" games could include one; small/budget titles shipped platinum-less lists. Empirically, lists cluster at two point budgets: ~300 points (short games, no platinum) and ~1,200 points (full games with platinum, 180-pt accounting) ([Kwak 2022](https://arxiv.org/abs/2205.15163)). Today whether to include a platinum is effectively the developer's call ([PlayStationTrophies forum](https://www.playstationtrophies.org/forum/topic/304111-does-sony-make-developers-follow-rules-for-trophies/)).

### 1.4 Hidden trophies

- A hidden trophy conceals its name/description until unlocked; the stated purpose is spoiler protection for story-linked trophies ([Kwak 2022](https://arxiv.org/abs/2205.15163)).
- Industry usage is **declining**: hidden ratios peaked above 25% of a list around 2013–2015 and fell to 10–15% by 2021; hidden *platinums* fell from ~1 in 6 (2010) to nearly zero (2021) — developers learned players want targetable goals ([Kwak 2022](https://arxiv.org/abs/2205.15163)).
- Since a September 2022 PS5 update, players can toggle **Reveal All** per game from the Trophies screen options ([Push Square](https://www.pushsquare.com/news/2022/09/reveal-all-hidden-trophies-at-once-with-new-ps5-update)).

### 1.5 DLC trophies

- DLC trophies live in separate groups appended to the game's list and are **never required for the platinum**; community-documented TRC limits: each DLC pack ≤ 200 points, and base list + all DLC ≤ **128 trophies** total (PS3/Vita/PS4-era rules) ([PSNProfiles guide](https://psnprofiles.com/guide/18274-the-trophy-system-explained), [PlayStationTrophies forum](https://www.playstationtrophies.org/forum/topic/304111-does-sony-make-developers-follow-rules-for-trophies/)). PS5-era caps: **(unverified)**.
- DLC rarity is computed against **the whole base-game player population** (rather than only players of the DLC), so DLC trophies skew Ultra Rare regardless of difficulty ([PlayStationTrophies forum](https://www.playstationtrophies.org/forum/topic/235402-ps4-trophy-rarity-question/)). The exact denominator is community-documented, not Sony-published — see §2.

### 1.6 Developer rules (community-documented; official TRC is under NDA)

- A list containing a platinum must total **at least 1,260 points** (i.e., ≥ 960 points of bronze/silver/gold + the 300-pt platinum) ([PSNProfiles guide](https://psnprofiles.com/guide/18274-the-trophy-system-explained)).
- No rules on grade mix — an all-gold list is legal ([PlayStationTrophies forum](https://www.playstationtrophies.org/forum/topic/304111-does-sony-make-developers-follow-rules-for-trophies/)).
- The two observed budget clusters (~300 and ~1,200 points) in 13,792 games strongly suggest Sony enforces per-game point ceilings at certification ([Kwak 2022](https://arxiv.org/abs/2205.15163)).

### 1.7 Trophy points → PSN account level (1–999)

- Since Oct 7, 2020 the level range is **1–999** (previously 1–100); existing accounts were remapped upward (example given: level 12 → "low 200s") ([PlayStation.Blog](https://blog.playstation.com/2020/10/07/upcoming-trophy-levelling-changes-detailed/)).
- **Level-icon bands (official):** Bronze **1–299**, Silver **300–599**, Gold **600–998**, Platinum **999**, each icon carrying "a subtle distinction to visually suggest how close you are to the next level" ([PlayStation.Blog](https://blog.playstation.com/2020/10/07/upcoming-trophy-levelling-changes-detailed/)).
- Community-documented points-per-level curve: 60 pts/level for 1–99; 90 for 100–199; 450 for 200–299; 900 for 300–399; 1,350 for 400–499; 1,800 for 500–599; 2,250 for 600–699; 2,700 for 700–799; 3,150 for 800–899; 3,600 for 900–999 ([PSNProfiles guide](https://psnprofiles.com/guide/18274-the-trophy-system-explained), [Avid Achievers](https://avidachievers.com/trophy-guides/playstation-trophy-level-explained/)).
- Levels confer **no rewards** — they are pure status/identity ([Playbite](https://www.playbite.com/q/how-do-playstation-trophy-levels-work)). Trophies can be earned offline and sync (auto or manual) when back online ([PlayStation support](https://www.playstation.com/en-us/support/games/how-to-earn-trophies-on-playstation--consoles/)).

Level-band quick reference ([PlayStation.Blog](https://blog.playstation.com/2020/10/07/upcoming-trophy-levelling-changes-detailed/)):

| Level range | Profile icon |
|---|---|
| 1–299 | Bronze |
| 300–599 | Silver |
| 600–998 | Gold |
| 999 | Platinum |

### 1.8 What trophy conditions actually say (corpus data)

[Kwak's WebSci'22 study](https://arxiv.org/abs/2205.15163) ran semantic role labeling over all 377,938 trophy descriptions:

- **Top condition verbs across all genres:** complete (level/mission/game/chapter/quest), get (trophy/star/score/kill/medal), defeat, win, collect, kill, find, have, finish, use. "Complete something" is the single most common condition type; "collect something" is second; "defeat something" third.
- **Genres have signature verbs:** Arcade/Shooter lean on *destroy*; Adventure/RPG on *obtain*; Sport games have 6/10 unique verbs (score, play, earn, perform, hit…). A trophy list reads like its genre.
- **Numeric scope scales with grade:** the average number of objects in a condition rises with grade — roughly 30 for Bronze up to ~68 for Platinum-adjacent conditions — i.e., grades encode quantity as much as difficulty.
- **Playtime anchors:** median playtime is ~5h for small (type-L) games vs ~10.5h for full-price (type-H); average completionist time is **8.6h (L) vs 23.6h (H)** — useful yardsticks for how much total effort a "full" list represents.

## 2. Rarity

- **Labels (official):** Common, Rare, Very Rare, Ultra Rare. Sony's own documentation names the four tiers but does not publish cutoffs ([PlayStation TV manual](https://manuals.playstation.net/document/en/pstv/trophies/about.html), [PlayStation support](https://www.playstation.com/en-us/support/games/how-to-earn-trophies-on-playstation--consoles/)).
- **Community-measured thresholds:** a trophy starts Common, becomes **Rare below 50%**, **Very Rare below 15%**, **Ultra Rare below 5%** of the eligible population ([MakeUseOf](https://www.makeuseof.com/what-are-playstation-trophies-what-do-they-do/), corroborated by [GamesRadar](https://www.gamesradar.com/11-easiest-rare-trophies-and-how-to-unlock-them/)).

| PSN label | Earned-by share |
|---|---|
| Common | ≥ 50% |
| Rare | < 50% |
| Very Rare | < 15% |
| Ultra Rare | < 5% |

- **Denominator:** players who earned the trophy ÷ **players who have played the game** (booted it on their account) — not purchasers, not trophy-earners-only ([Playbite](https://www.playbite.com/q/how-do-trophy-percentages-for-games-work-on-psn), [GameFAQs](https://gamefaqs.gamespot.com/boards/691087-playstation-4/72943079)). Community-derived: Sony publishes neither cutoffs nor denominator, and some community sources say "players who own the game" instead **(unverified)**. Consequence: games many people boot once produce inflated Ultra Rare counts, and DLC trophies inherit the whole base-game denominator ([PlayStationTrophies forum](https://www.playstationtrophies.org/forum/topic/235402-ps4-trophy-rarity-question/)).
- **Update cadence:** percentages recalculate periodically on PSN; the exact schedule is unpublished **(unverified)**.
- **Third-party rarity:** PSNProfiles displays its own five-tier site rarity (adding "Uncommon") computed only from its registered users ([PSNProfiles forum](https://forum.psnprofiles.com/topic/100427-what-is-the-rarity-to-percent-range/); exact site cutoffs **(unverified)** — the site blocks scraping). Kwak shows why the distinction matters: PSNProfiles members' completion distribution peaks at 100% while PSN-wide rates are far lower — enthusiast-community stats are heavily biased vs the whole player base ([Kwak 2022](https://arxiv.org/abs/2205.15163)).
- **Base rates for calibration:** PSN-wide platinum completion in full-price games rose from **4.2% (2008) to 39.2% (2021)**; gold completion hit 57.4% in 2021; distributions are bi-modal (hard stays hard, plus a wave of deliberately easy lists); Visual Novel genre completion reached 75.0% ([Kwak 2022](https://arxiv.org/abs/2205.15163)).

## 3. UX

### 3.0 Timeline of UX escalation

Sony shipped celebration and tracking features incrementally — each one a discrete, copyable idea:

| Year | Feature |
|---|---|
| 2008 | Toast + per-generation signature sound (PS3 FW 2.40) ([Fandom](https://playstation.fandom.com/wiki/Trophies)) |
| 2013 | Rarity percentages added with PS4 ([PST forum](https://www.playstationtrophies.org/forum/topic/235402-ps4-trophy-rarity-question/)) |
| 2014→ | PS4 auto-screenshot on unlock ([Stevivor](https://stevivor.com/news/ps5-trophy-notifications-pop-top-right-screen-record-video/)) |
| 2020 | Level overhaul (1–999, icon bands), platinum 180→300 pts ([PS.Blog](https://blog.playstation.com/2020/10/07/upcoming-trophy-levelling-changes-detailed/)) |
| 2020 | PS5 auto video clip of the unlock build-up ([Push Square](https://www.pushsquare.com/guides/how-to-turn-off-trophy-videos-on-ps5)) |
| 2022 | Pin-up-to-5 tracker overlay + hidden "Reveal All" toggle ([Push Square](https://www.pushsquare.com/news/2022/09/reveal-all-hidden-trophies-at-once-with-new-ps5-update), [AskPlayStation](https://x.com/AskPlayStation/status/1528163752310349824)) |
| 2023 | Unique platinum unlock animation ([Push Square](https://www.pushsquare.com/news/2023/03/ps5-firmware-update-adds-fancy-new-animation-for-earning-a-platinum-trophy)) |

### 3.1 Unlock toast

- **Position:** PS4 toasts appear **top-left**; PS5 moved them to the **top-right** ([Stevivor](https://stevivor.com/news/ps5-trophy-notifications-pop-top-right-screen-record-video/)).
- **Sound:** each console generation has a distinct unlock chime; the PS3 "ding" and PS5 tone are meme-grade recognizable (soundboards/ringtones exist for all of them — [Voicemod](https://tuna.voicemod.net/sound/25902f41-6eb2-4508-a2e5-28ddb38941c2), [Myinstants](https://www.myinstants.com/en/search/?name=trophy+ps)). The **platinum has its own unique notification sound** on PS5 ([Push Square](https://www.pushsquare.com/news/2023/03/ps5-firmware-update-adds-fancy-new-animation-for-earning-a-platinum-trophy)).
- **Auto-capture:** PS4 auto-screenshots trophy unlocks; PS5 by default saves **a screenshot plus a 15s (configurable 30s) video clip ending at the unlock** — i.e., it retroactively captures the build-up ([Stevivor](https://stevivor.com/news/ps5-trophy-notifications-pop-top-right-screen-record-video/), [Push Square](https://www.pushsquare.com/guides/how-to-turn-off-trophy-videos-on-ps5)). Players can disable it under Settings → Captures and Broadcasts → Trophies; storage bloat is a common complaint ([Push Square talking point](https://www.pushsquare.com/news/2025/01/talking-point-ps5-saves-video-clips-when-you-earn-trophies-do-you-leave-that-feature-on)).

### 3.2 Trophy list UI and in-game tracking

- Per-game list shows grade icon, name, description (masked if hidden), earn timestamp, and rarity label + percentage; base game and DLC groups are separated ([PlayStation support](https://www.playstation.com/en-us/support/games/how-to-earn-trophies-on-playstation--consoles/)).
- PS5 Control Center "trophy cards" let players **pin up to 5 trophies per game** and **Start Tracking** a trophy so its live progress floats as an overlay while playing ([official support tweet](https://x.com/AskPlayStation/status/1528163752310349824), [SeekingTech](https://seekingtech.com/how-to-view-sort-and-pin-trophies-on-the-control-center-menu-of-ps5/)). This 2022 tracker feature was credited with reactivating lapsed trophy hunters ([Tom's Guide](https://www.tomsguide.com/news/the-ps5-system-update-has-made-me-a-trophy-hunter-again)).
- Profile display: trophy level with its bronze/silver/gold/platinum band icon plus per-grade counts, visible on console, PlayStation App, and to friends ([PlayStation.Blog](https://blog.playstation.com/2020/10/07/upcoming-trophy-levelling-changes-detailed/)).

### 3.3 Platinum celebration

- Regular trophies share one toast; the platinum gets a **unique sound and, since a March 2023 firmware update, a unique celebratory animation** — a small touch that trophy hunters received as meaningful escalation ([Push Square](https://www.pushsquare.com/news/2023/03/ps5-firmware-update-adds-fancy-new-animation-for-earning-a-platinum-trophy)).
- The auto-captured platinum screenshot/clip feeds a social ritual: posting the plat pop.

## 4. Culture — why hunting became a subculture

### 4.1 The ecosystem

- **PSNProfiles** — profile tracking, per-game leaderboards, rarity leaderboards, a "100% Club" per game, and community trophy guides with difficulty/hours metadata ([psnprofiles.com](https://psnprofiles.com/), [guides announcement](https://forum.psnprofiles.com/topic/13765-gameplay-trophy-guides-on-psnprofiles/)).
- **PowerPyx** — the dominant guide publisher; the standard "Trophy Guide & Roadmap" format (estimated difficulty /10, hours-to-plat, number of playthroughs, missables flagged, step ordering) ([powerpyx.com](https://www.powerpyx.com/), e.g. [Astro's Playroom roadmap](https://www.powerpyx.com/astros-playroom-trophy-guide-roadmap/)).
- Also TrueTrophies, Exophase, PSN Trophy Leaders ([Wikipedia — Trophy hunting (video games)](https://en.wikipedia.org/wiki/Trophy_hunting_(video_games))).

### 4.2 Motivations (with research)

- **Competence feedback / SDT:** self-determination theory frames achievements as satisfying the need for competence; games pull players via competence, autonomy, relatedness (Ryan, Rigby & Przybylski, ["The Motivational Pull of Video Games"](https://www.researchgate.net/publication/225998888_The_Motivational_Pull_of_Video_Games_A_Self-Determination_Theory_Approach)); Kwak's literature review notes achievements plausibly serve intrinsic and extrinsic motivation **simultaneously**, and cites a focus study (Cruz et al., 36 console players) with mixed reactions — "positive feedback, diverse ways to play, boosted self-esteem" vs "achievements felt like burdens/extra tasks" ([Kwak 2022](https://arxiv.org/abs/2205.15163)).
- **Anatomy of an achievement:** Hamari & Eranti's framework — signifier (name/icon/description) + completion logic + reward — maps 1:1 onto trophies and is the cleanest mental model for designing one ([summarized in Kwak 2022](https://arxiv.org/abs/2205.15163)).
- **The meta-game:** Jakobsson's "The Achievement Machine" describes Xbox achievements as "an invisible MMO that all Xbox Live members participate in, whether they like it or not" — one persistent quest system spanning every game ([Game Studies 11(1)](https://gamestudies.org/1101/articles/jakobsson)); trophies are PlayStation's instance of it.
- **Gaming capital:** Consalvo's concept — accumulated trophies work as social currency/credibility among peers; public profiles make expertise legible and comparable ([Kwak 2022](https://arxiv.org/abs/2205.15163)).
- **Identity and status:** hunters describe completionism as identity ("I've always been a completionist gamer… earning trophies just came naturally" — Roughdawg4), choose games by challenge or completion speed, and treat unlocks as meta-goals; the demand side spawned an easy-platinum shovelware economy that Sony has fought with delistings ([Wikipedia](https://en.wikipedia.org/wiki/Trophy_hunting_(video_games))).
- **Rarity as bragging rights:** the Ultra Rare label converts a stat into visible status; whole community lists exist for ultra-rare platinums ([PSNProfiles UR platinum index](https://psnprofiles.com/trophies?rarity=ultra-rare&type=platinum), [DualShockers rarest platinums](https://www.dualshockers.com/rare-platinum-trophies-players-have-earned/)).
- Recent gamification research continues to find achievement-style rewards differentially motivating by player type (SDT + Hexad) ([ScienceDirect, 2026](https://www.sciencedirect.com/science/article/pii/S2451958826000564)).

### 4.3 Scale of the meta-game

- PSN had **109M+ monthly active users as of March 2021** — the trophy system is arguably the largest single achievement economy in console gaming ([Kwak 2022](https://arxiv.org/abs/2205.15163), citing Sony).
- Cross-platform: of top-100-rated 2021 games, 45 shipped on PlayStation; for games shared with Xbox, 97.6% of trophies have a 1:1 achievement twin, completion rates correlate strongly across platforms (Pearson r = 0.87), and **completion runs consistently higher on PlayStation than Xbox** — Kwak speculates the level/platinum structure itself elicits more completion ([Kwak 2022](https://arxiv.org/abs/2205.15163)).

### 4.4 What the aggregate data says designers learned

From 13,792 games / 377,938 trophies ([Kwak 2022](https://arxiv.org/abs/2205.15163)):

- Trophy counts per full-price game fell from a mode of **51 (2008) to 13 (2021)**; games with >35 trophies dropped from 77.4% to 25.2%.
- Bronze counts shrank while gold counts grew — same point budget, fewer/bigger rewards ("achievements for harder tasks are more frequently given, while those for simpler tasks are decreasing").
- Hidden ratios fell to 10–15%; hidden platinums to ~0.
- Completion rates rose across all grades (platinum 4.2% → 39.2%).

Industry-wide drift over 15 years = **fewer, chunkier, more visible, more completable trophies**.

## 5. Design lessons — loved vs hated lists

### 5.1 Celebrated

- **Astro's Playroom (PS5):** 1 Platinum / 5 Gold / 14 Silver / 31 Bronze, zero missables, ~6–7 hours, "easy, quick, and fun… your first PS5 platinum"; the list doubles as a tour of the game's content ([PSNProfiles guide](https://psnprofiles.com/guide/11237-astros-playroom-trophy-guide), [Push Square](https://www.pushsquare.com/guides/astros-playroom-all-trophies-and-how-to-unlock-the-platinum)).
- **Sony first-party house style (post-2018):** difficulty-tied trophies dropped so platinums are accessible to anyone willing to do everything (Horizon Forbidden West, Ratchet & Clank: Rift Apart); where difficulty trophies exist they're quarantined in separate DLC lists that don't gate the plat (Horizon Zero Dawn, Days Gone); players report Spider-Man/Horizon-style plats as ones they earn "by playing the game as they would anyway" ([Push Square — "Sony's First-Parties Have Perfected the Art of Compelling Trophy Lists"](https://www.pushsquare.com/news/2020/07/sonys_first-parties_have_perfected_the_art_of_compelling_trophy_lists), [Gameranx](https://gameranx.com/features/id/289193/article/horizon-forbidden-west-difficulty-trophies/)).

### 5.2 Hated (the canonical villains)

- **Wolfenstein II "Mein Leben"** — finish the whole game on max difficulty with no saves, one life; insult compounded by it being **only a bronze** (effort/grade mismatch) ([Push Square hardest platinums](https://www.pushsquare.com/guides/the-hardest-ps4-platinum-trophies?page=2)).
- **Star Ocean: The Last Hope** — ~45-hour game, **~400+ hour platinum** across 5+ playthroughs with missable-chest heartbreak ([XDA hardest platinums](https://www.xda-developers.com/hardest-platinum-trophies-playstation/)).
- **FFX "Lightning Dancer"** — dodge 200 consecutive lightning strikes; pure twitch/RNG outlier in an RPG ([GameRant](https://gamerant.com/hardest-final-fantasy-trophies-achievements/)).
- **Mortal Kombat 9 "My Kung Fu Is Stronger"** — max mastery of every character; years-scale grind ([GameRant impossible platinums](https://gamerant.com/games-with-impossible-platinum-trophies-to-get-unlock/)).
- **Online-population dependencies rot:** Black Ops 2's platinum died with its servers (2023); Transformers: Fall of Cybertron's MP trophies died in 2020; Portal 2 "Professor Portal" requires a partner who has never played (matchmaking dead); LittleBigPlanet 3 lost even trivial trophies like "create a playlist" when Sony killed its servers ([GameRant](https://gamerant.com/games-with-impossible-platinum-trophies-to-get-unlock/), [TheGamer](https://www.thegamer.com/10-playstation-games-with-unobtainable-platinums/)).
- **Glitched trophies:** FlatOut 4 "Jay Will Be Proud!" broke via patch — an unobtainable plat from QA neglect ([TheGamer](https://www.thegamer.com/10-playstation-games-with-unobtainable-platinums/)).
- **Repetition data:** completion falls as conditions get more repetitive; the sweet spot for hard (gold) trophies is ≤ ~30 repetitions of a task — beyond that players bail ([Kwak 2022](https://arxiv.org/abs/2205.15163)).

### 5.3 DOs and DON'Ts

1. **DO** make the top award = "did everything meaningful once" — 70.3% of platinums are literally "all/every" conditions; players love plats earned "by playing the way I would anyway."
2. **DO** keep the list short and chunky: modern norm is ~13–30 trophies, weighted toward fewer, higher-grade rewards, not 50 bronze pebbles.
3. **DO** give the top award escalated ceremony — unique sound, unique animation, capture-worthy moment (Sony added both, years apart, to loud approval).
4. **DO** publish rarity — it converts a private stat into social status and gives every trophy a second life after unlock.
5. **DO** support in-game progress visibility (pin/track with live counters); it demonstrably re-engages players.
6. **DO** hide only story-spoiler trophies, and give players a reveal toggle; the industry converged on ~10–15% hidden.
7. **DO** keep every trophy deterministic, trackable, and guide-able (the PowerPyx roadmap format — difficulty /10, hours, playthroughs — is how hunters triage; a list that can't be roadmapped gets skipped).
8. **DON'T** gate the top award behind difficulty spikes or twitch outliers alien to the core loop (Mein Leben, Lightning Dancer); quarantine "for the sickos" challenges in a side list that doesn't block the plat.
9. **DON'T** ship grind an order of magnitude beyond the game's natural length (400h plat on a 45h game); keep repetitive conditions ≤ ~30 reps and make grinds overlap with normal play.
10. **DON'T** make trophies depend on other players existing (population-dependent, server-dependent, "partner who never played") — every such trophy has an expiry date and poisons the whole list retroactively.
11. **DON'T** allow missables without warning; no-missable lists (Astro, God of War-era Sony) are consistently praised, and missables force anxiety-driven guide-first play.
12. **DON'T** mismatch grade and effort (a brutal bronze reads as contempt), and **DON'T** ship untested conditions — one glitched trophy makes completion impossible and enrages precisely your most devoted players.

## Transferable principles for a mobile indie game

1. **Four grades + one umbrella award works at any scale.** Keep bronze/silver/gold-equivalents for texture and a single platinum-equivalent per major content area ("did everything once"). Its condition should be *the union of the others*, so it needs no extra bookkeeping.
2. **Adopt a fixed point budget per "list".** Sony's ~1,260-point discipline is why levels stay comparable across games. For one game: give each trophy a point weight (15/30/90/300 ratios are battle-tested) and let the sum drive a profile level so future content can't inflate old status.
3. **Level = pure status with icon bands.** The 1–999 level with bronze→silver→gold→platinum icon bands at fixed cut points (299/599/999) is cheap to render and gives long-horizon identity without any economy entanglement — deliberately give **no coin/IAP rewards** for levels to keep it uncorruptible.
4. **Rarity is the cheapest social feature you can ship.** One percentage per trophy (earned ÷ players who launched the game) plus four labels at <50/<15/<5 cutoffs. Choose and document the denominator up front; recompute on a schedule; expect a "boot once" long tail to inflate ultra-rares.
5. **Escalate the celebration exactly once.** Standard unlock = small toast (consistent corner, one signature sound — the sound *is* the brand). Platinum-equivalent = full-screen moment with unique audio + confetti + auto-generated shareable card (the mobile analog of the PS5 trophy clip).
6. **Build the tracker into the game, not a menu.** Pinnable trophies with live progress counters (PS5's 5-pin model) map naturally to a mobile HUD chip or pre-run screen; progress visibility is the single most re-engaging trophy feature Sony shipped.
7. **Design for the guide ecosystem even if it's just your Discord.** Every trophy: deterministic condition, visible progress, no hidden state. If a fan couldn't write a PowerPyx-style roadmap (difficulty /10, est. hours, order), redesign it.
8. **Respect the mortality of live features.** Any trophy touching multiplayer, live events, or seasonal content needs a sunset plan (auto-grant or condition swap) — PlayStation's unobtainable-platinum graveyard is the cautionary tale.
9. **Tune to completion-rate targets, not vibes.** Post-launch, check the funnel: first bronze ≈ near-100%, story trophies track retention, platinum-equivalent somewhere in the 5–40% band (PSN's plat rates rose 4.2%→39.2% as design got friendlier — pick where on that spectrum the game should sit and adjust).
10. **Hidden = spoilers only; missables = never; grind = overlapping with fun.** The three rules that separate loved lists from hated ones, straight from 15 years of PlayStation community consensus.

---

*Compiled 2026-07-02 from official Sony documentation, the Oct 2020 PlayStation.Blog overhaul post, Kwak (WebSci'22) — the only large-scale empirical study of the trophy corpus (13,792 games / 377,938 trophies) — plus community canon (PSNProfiles, PowerPyx, Push Square, TheGamer, GameRant, XDA, Stevivor) and achievement-motivation literature (Ryan/Rigby/Przybylski; Jakobsson; Hamari & Eranti; Consalvo).*
