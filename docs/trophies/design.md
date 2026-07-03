# Trophy System — Design Brief

> Status: **S0-gating rulings RULED 2026-07-02 (§11 #1/#2/#3/#14):** catalog adopted; ladder **Bronze → Silver → Gold → Diamond → Platinum** (Diamond-vs-cosmetic disambiguation riders binding); rewards = prestige + earned-only regalia, never coins. Remaining §11 rows stay open (pre-S3/pre-launch).
> Date: 2026-07-02 · Revised 2026-07-02 (reconciled against `trophy-catalog.md`; privacy + Home-grid notes added)
> Based on the six research docs in `docs/trophies/research/`
> All `file:line` refs are against HEAD `064f3cd`; anchor on symbol names, lines drift.
> Provenance: verified at `064f3cd`, reconciled same-day to `origin/main` `42d1925` (PRs #113/#114/#118–#120/#122–#124 merged 2026-07-02 — economy calibration + tier reprice are LIVE); line refs anchored by symbol, see `research/repo-delta-2026-07-02.md`.
> Tip drift (2026-07-02, post-reconciliation): `origin/main` has since moved `42d1925` → `fb98819` — one commit, the IAP launch-race fix (StoreKitManager delivery ledger `ra_iapDeliveredTxnIDs`) is now MERGED; touches StoreKitManager + its tests only, no GameState or trophy-surface changes.

**→ §11 "Decisions for Mac" at the bottom records the rulings landed 2026-07-02 (#1/#2/#3/#14) and every still-open row. Everything above it is the argument for each recommendation.**

> **Reconciliation with `trophy-catalog.md`.** The sibling catalog was authored
> to item level after this brief and diverges from it in six places. Treat the
> catalog as the proposed final *shape* and this brief as the *argument*; each
> delta is flagged inline below and consolidated as **decision #14** (plus the
> rung-4 name inside **decision #2**) so Mac rules on the final shape exactly
> once. The deltas: **(1)** tier 4 is named **Legend** (3 trophies), not
> Summit — and the catalog contains a Legend trophy *named* "The Summit" (§2);
> **(2)** the list is **89 trophies** (49 B / 25 S / 11 G / 3 Legend /
> 1 capstone), not this brief's ~40-55 sketch; **(3)** **5 hidden** trophies
> (all Secret & Whimsy), not 0-2; **(4)** the capstone covers the **73 visible
> Bronze/Silver/Gold** trophies — Social, Secret & Whimsy, and the Legends are
> excluded from the capstone path — not "every base trophy"; **(5)** per-trophy
> **point weights are deferred** by the catalog (this brief's 15/30/90/180/300
> are defaults, not commitments); **(6)** the catalog recommends the capstone
> *name* "Roll of Honor" where this brief argued for the literal "Platinum"
> (R3, §2).
>
> → **RULED 2026-07-02:** Mac adopted the catalog (#14 — 89 trophies, 5 hidden,
> 73-visible capstone scope, point weights deferred) but overruled both names:
> rung 4 is **Diamond** (§2 R2 — not Legend; the disambiguation riders are now
> binding) and the capstone's display name is **Platinum** ("Roll of Honor"
> survives only as an optional future name idea for the Trophy Room *screen*,
> not the trophy). Ids unchanged; `climb_summit` keeps its display name
> "The Summit" — no collision with a Diamond grade. Operative text in all four
> docs now reads Diamond/Platinum; the deltas above stand as authored, for the
> record.

---

## 1. Vision & principles

**What "trophy culture" means for Roll Along.** A trophy is a permanent public
monument to something a player did — not a quest, not a coupon, not a login
nudge. PlayStation sustained a 16-year hunting subculture on pure status:
grades, a capstone award, rarity percentages, and one escalating celebration.
Roll Along already has the raw material — 5,000 climb levels across 50 named
worlds, 8 Challenge Tracks, 12 minigames, a deep cosmetics catalogue, a
Supabase social layer — but its only achievement surface is an 11-badge
profile wall that is unpersisted, un-celebrated, and can silently *un-earn*
itself (ProfileView.swift:388-474). The trophy system replaces that wall with
a real one: latched forever, celebrated once, ranked by rarity, visible on
public profiles, and deep enough that hunting trophies becomes its own way to
play the game.

**Design principles** (distilled from the research; each traces to a doc):

1. **Prestige-first.** Trophies are status, not currency. Every reward
   retrofit Sony ever tried failed or backfired; purity is stable
   (f2p §4, §7.12).
2. **Every trophy earnable at $0, forever.** No IAP criteria, no counting the
   secret Money/Diamond cosmetics in any completion math, no "spend coins"
   trophies (Sell Back refunds are recycled capital, not play income — a
   spend counter is churnable at a 50% loss per cycle under the merged
   `min(coinCost/2, paidPrice)` sell-back — economy §5b).
3. **Trophies are ratchets.** Once unlocked, never revoked — not by
   `resetProgress()`, not by Sell Back, not by a broken streak. Latched state,
   never recomputed from live stats (features §2.7, backend §2.3).
4. **Key to lifetime stats, never to specific content.** Climb levels are
   swappable files (`LevelOverrides.json`); a trophy naming a layout dies with
   a content swap (f2p §7.9). Trophy vocabulary = mode ids, track ids,
   world numbers, lifetime counters.
5. **No time-limited, no missable, no population-dependent trophies.**
   Permanent self-paced monuments; seasonal content gets event rewards, not
   trophies (psn §5.3, f2p §7.5-7.6).
6. **Short and chunky, front-loaded with delight.** Modern norm is ~13-30
   trophies per "list" (the shipped catalog runs long at 89 — see the
   reconciliation note and decision #14, RULED 2026-07-02: adopted); median player completes ~10% of
   content — the first
   third of the list is all most players ever see. First ~15 trophies double
   as a discovery map (one per minigame, first track, first friend, first
   clan) that hands players to the social layer, which carries endgame
   retention (f2p §1, psn §4.4).
7. **Grade must match effort.** A brutal condition at a low grade reads as
   contempt (Mein Leben); quantity/difficulty scales with grade; hard
   trophies must be fun-hard, ≤ ~30 repetitions of any one task (psn §5.2).
8. **One celebration escalation.** Standard unlock = one small toast with one
   signature sound; the capstone gets the full-screen blowout. Never
   interrupt a live tilt run — coalesce to run end (f2p §7.10).
9. **Hidden = spoilers only.** Roll Along has almost none; this brief's
   original target was 0-2 hidden trophies — the catalog ships **5** (all
   Secret & Whimsy, ~6% of the list, none gating the capstone; decision
   #14 — ratified 2026-07-02) — with progress never reported on them until unlock (psn §1.4).
10. **Stable IDs, immutable criteria, additive-only catalog.** Every platform
    converged on this (Xbox XR-060, GC permanent IDs, Steam confidence
    gates). Choose GC-legal ids (alphanumeric, ≤100 chars) from day one even
    if Game Center ships later (platform §3, §6).

---

## 2. Tier ladder

### Option A — Faithful PSN: Bronze / Silver / Gold + Platinum capstone

Three per-trophy grades weighted 15/30/90 points, plus **one** Platinum
awarded automatically for earning every base trophy. This is the
battle-tested shape: 70.3% of PSN platinums are literally "all/every"
conditions, and the point ratios have survived 16 years of tuning. Simple,
legible, nothing to invent.

### Option B — Mac's five rungs: Bronze / Silver / Gold / Diamond per-trophy + Platinum capstone

Four per-trophy grades — the fourth reserved for the true peaks (finish
golden-gauntlet, world 10 of the climb, an ultra-skill feat per minigame) —
plus Platinum as the all-trophies capstone. This is richer than PSN: it gives
the list a visible "aspirational shelf" above Gold, matching Roll Along's
unusually deep content (a 5,000-level climb needs more headroom than a 20-hour
console game). Suggested point weights: 15 / 30 / 90 / 180 / Platinum 300
(the catalog defers point weights entirely — treat these as defaults for the
eventual points pass, not commitments).

### The "Diamond" naming collision — this is real, decide it deliberately

**"Diamond" already means something specific in Roll Along:** the Diamond
ball is the $19.99 unlimited-lives IAP exclusive (StoreKitManager
`deliverReward` — the file was heavily rewritten post-`064f3cd`, locate by symbol),
the flagship of the Iconic pay-gated cosmetic tier alongside the Money trio —
items that never appear in the shop, catalog, or rotation. A **Diamond trophy
tier** would put the word on two opposite meanings at once: *paid exclusive*
(cosmetics) vs *earned pinnacle* (trophies). Worst case, players assume
Diamond trophies are pay-gated — the exact accusation the reward policy (§5)
is designed to never face. Note also that Xbox uses a **diamond icon** to
mean *rare*, a third meaning that would collide with our rarity system (§3).

Resolutions considered:

| Resolution | Verdict |
|---|---|
| **R1 — Rename the trophy tier.** Keep Mac's five-rung shape, name rung 4 something Roll Along owns. This brief's original candidate was **Summit** — the 50th and final climb world is literally "The Summit" (LevelLayout.swift:46-89), so the word already means "the top of the game" — but the catalog was authored with **Legend**, and it contains a Legend trophy *named* "The Summit" (`climb_summit`, clear level 5,000) plus the capstone name candidate "The Grand Summit," so "Summit" as a *grade* name now collides inside our own list. Runner-ups: Marble, Pinnacle, Aurum. | **Recommended — with "Legend"** |
| **R2 — Keep "Diamond", disambiguate by context.** Ship it and rely on UI framing. Cheap, honors Mac's words verbatim, but the collision surfaces exactly where it hurts most: a player who owns the Diamond *ball* reading a Diamond *trophy* row, and every future support/App Store review conversation. | Not recommended |
| **R3 — Roll Along-flavored capstone instead of Platinum.** e.g. the capstone is "The Summit Trophy" and rung 4 stays Diamond. Inverts the problem (Platinum is the universally understood capstone word; Diamond still collides). | Not recommended |

**Recommendation: Option B with R1, rung 4 named "Legend"** — Bronze /
Silver / Gold / **Legend** per-trophy, plus the Platinum-equivalent capstone
(scope per §9: the visible Bronze/Silver/Gold base list — the catalog
excludes Social, Secret & Whimsy, and the Legends from the capstone path).
Mac gets his five rungs and the Diamond collision dies. "Legend" is the
catalog as-authored; "Summit" remains viable only if `climb_summit`'s
display name ("The Summit") and the "Grand Summit" capstone candidate are
renamed in trophy-catalog.md. If Mac overrules and wants the literal word
Diamond, R2 is survivable — but then the rarity system must not use diamond
iconography, and no trophy-reward cosmetic may ever visually reference the
Diamond ball.

**→ RULED 2026-07-02: Mac chose R2 — rung 4 is named "Diamond"** (overruling
the R1/"Legend" recommendation). R2's riders are therefore **binding
constraints**, written into the operative sections:

- **(a)** the Diamond *trophy grade* always gets its own glyph/color
  treatment, visually and contextually distinct from the Diamond *cosmetic*
  gating tier (the $19.99 paid exclusive) — §6, sprint S2-T1;
- **(b)** the rarity display never uses diamond iconography at any rarity
  band — §3, sprint S3-T4;
- **(c)** no regalia cosmetic may reference the Diamond ball — §5;
- **(d)** UI copy never says "Diamond trophy" of the cosmetic tier nor
  "Diamond cosmetic" of the trophy tier — §6/§7.

The ruled ladder: **Bronze → Silver → Gold → Diamond → Platinum** (capstone
display name ruled with #14). `climb_summit` keeps its display name
"The Summit" — the grade is Diamond, so there is no collision, and no rename
chain fires. The collision analysis above stands as authored, for the record.

Trophy **points** feed a profile trophy level later if wanted (PSN's 1-999
banding is cheap to copy) — but v1 ships grades + capstone only; a points
level is a fast-follow, never a reward hook.

---

## 3. Rarity system

**Labels and thresholds** — adopt PSN's, community-measured and universally
understood:

| Label | Earned-by share |
|---|---|
| Common | ≥ 50% |
| Rare | < 50% |
| Very Rare | < 15% |
| Ultra Rare | < 5% |

Tier label is the primary display (list rows); the raw percentage shows on
the trophy detail view only. Rationale: "0.9%" on an unstarted trophy tells a
casual "not for you"; the label motivates without gatekeeping (f2p §6).

**Denominator decision.** Three candidates exist (backend §5):

1. `players` rows — signed-in accounts only. Currently 1 row; permanently
   biased toward engaged players. **Rejected.**
2. Distinct anonymous install UUIDs from `events` (`app_launch`) — the
   closest analogue to PSN's "players who booted the game." Reinstalls and
   multi-device double-count (each install is a "player"), offline-forever
   installs never count. **Recommended** — and critically, use the *same
   UUID rail* for the numerator (trophy-unlock rows keyed by the same
   install UUID), so numerator and denominator can never diverge across the
   two identity systems that deliberately never join.
3. Per-trophy "eligible population" (played that mode). More honest,
   dramatically more infra. **Deferred** — a v2 refinement at most.

**Cold-start plan.** Day-1 percentages are noise (f2p §6). Rules:

- Until the denominator reaches **500 distinct installs** AND **30 days
  post-launch**: show no rarity at all — a quiet "Rarity coming soon" dash on
  detail views, nothing on list rows.
- After the threshold: show tier labels everywhere, percentages on detail.
- Never hard-code any gameplay or reward behavior to a live rarity number
  (Steam's sale-spike lesson, platform §2).

**Update cadence.** Recompute server-side **daily** (a scheduled job writing
`trophy_stats`); the client caches the last-fetched stats and renders stale
data gracefully. Rarity is a garnish — nothing about unlocking depends on it,
so a stale or unreachable stats table degrades to "no label," never an error.

**Binding rider (Diamond ruling, §2 R2 — 2026-07-02):** the rarity display
never uses diamond iconography at any rarity band — no diamond glyphs on
Common/Rare/Very Rare/Ultra Rare labels, list rows, or detail views (Xbox's
diamond-means-rare convention is explicitly rejected here). In trophy contexts
the diamond glyph belongs to the **Diamond trophy grade** alone — and even
there it must stay visually distinct from the Diamond *ball* cosmetic (§5,
§6). Enforced in sprint S3-T4's acceptance criteria.

---

## 4. Rarity/unlock data architecture

Constraints this must honor (backend doc, all verified): first-party
no-tracking posture (all first-party data currently declared Linked=false;
note the manifest's `NSPrivacyTracking=true` exists too, solely for the
AdMob ATT/IDFA path — backend §6); sign-in optional and currently ~0%
adopted; fully-offline play; no offline queue exists today and one-shot
events don't self-heal; delete-account must cascade; UserDefaults dies on
reinstall; server sync is one-way push with no hydrate path.

### Option A — Game Center as system of record for rarity

Apple computes `rarityPercent` (iOS 17+), zero backend. But: denominator =
GC-authenticated players only; `nil` until Apple has "enough data"
(undocumented threshold — expect nil for a small game for a long time);
requires shipping GC before rarity exists at all; signed-out players see
nothing. **Rejected as the system of record** (fine as a bonus signal, §8).

### Option B — Supabase aggregation

Anonymous unlock counting on the existing analytics rail: client posts
trophy-unlock facts keyed by the install UUID; a scheduled rollup writes a
`trophy_stats(trophy_id, earned_count, install_count, pct)` table with
`SELECT` granted to `anon` — the project's first anon-readable object, an
explicit RLS decision. Serves 100% of players including signed-out, stays
inside the not-linked privacy envelope (same UUID already declared as
DeviceID/analytics), works for the in-app Trophy Room. Costs: one migration,
one scheduled job, one small client fetch.

### Option C — Hybrid: local unlocks + Supabase counts + optional GC mirror (RECOMMENDED)

Layered, each layer independently shippable:

1. **Local source of truth.** A latched store: `ra_trophyUnlocks` —
   `[trophyID: unlockedAtISO8601]` plus progress counters for cumulative
   trophies. Written only by the trophy engine at GameState choke points
   (features §3); never derived from regressable stats; untouched by
   `resetProgress()` and Sell Back.
2. **Supabase rarity + sync (Option B) on top**, with two write paths:
   - *Anonymous counting (all players):* dedicated
     `trophy_unlocks(install_id, trophy_id, unlocked_at)` table, INSERT-only
     for anon (unique on install_id+trophy_id, upsert-ignore = idempotent).
     Do **not** route through `AnalyticsClient` — its buffer is memory-only
     and events die on app kill (backend §7).
   - *Signed-in trophy case:* `player_trophies(player_id, trophy_id,
     unlocked_at)` `ON DELETE CASCADE` off `players`, powering public-profile
     showcases.
   - *Offline durability:* no outbox machinery — sync is an **idempotent
     full-snapshot upsert** ("here are ALL my unlocked ids"), flushed on
     launch/foreground/sign-in. This converts one-shot events back into
     self-healing snapshots, the pattern the whole codebase already uses.
   - *Rarity counters are detached and increment-only:* `trophy_stats`
     derives from `trophy_unlocks` (anonymous rail), so **account deletion
     doesn't rewrite rarity history** — the delete-account cascade removes
     `player_trophies` (personal data) while the anonymous counts survive,
     exactly like `events` rows today. PSN behaves the same way.
3. **Optional GC mirror** (§8), a later phase.

**App Privacy impact of the signed-in layer — decide with the schema, not at
submission.** The anonymous rail (layer 2's `trophy_unlocks`) stays inside
the not-linked envelope. But `player_trophies` rows keyed to a
Sign-in-with-Apple `player_id` — surfaced as a public-profile showcase (§7) —
are gameplay data **linked to the user's identity** under Apple's definition.
`PrivacyInfo.xcprivacy` today declares GameplayContent `Linked=false` and no
User ID data type at all; if the signed-in layer ships, GameplayContent (and
likely a User ID type) flips to `Linked=true` for signed-in players, and the
App Privacy nutrition labels change. This ruling belongs with the S3 schema
migration's acceptance criteria — the sprint plan currently parks it in
S4-T5, the final pre-submission pass, where a forced answer would surprise
the submission (flagged for sprint-plan.md).

> **OPEN:** the existing `players`-table stat sync (level, wins, streaks
> keyed to the same account) raises the same linked-data question *today*,
> independent of trophies — audit whether the manifest is already stale
> before treating this as a trophy-only change.

**Reinstall / device-transfer persistence — be concrete:**

| Mechanism | What it covers | Verdict |
|---|---|---|
| iCloud/encrypted backup + device migration | UserDefaults transfers losslessly today | Free, covers most real players |
| **`NSUbiquitousKeyValueStore` (iCloud KV)** — mirror only the trophy ratchet (id set + timestamps; well under the 1 MB / 1024-key caps). Merge rule: **union** (max-merge on timestamps). Requires adding the iCloud KV entitlement — a new capability, flag to Mac. | Delete+reinstall with no backup restore; two-device divergence for trophies specifically | **Recommended** — trophies are the highest-emotion state in the game and the only state small enough to sync this cheaply |
| **Supabase restore for signed-in players** — on sign-in (session already survives reinstall via Keychain), fetch `player_trophies` and **union into local**. This is deliberately the app's *first hydrate-from-server path*; scoping it to trophies-only (a pure ratchet, union is always safe) avoids the general save-restore problem that clobbers `players` today. | Signed-in reinstallers, cross-device | **Recommended** |
| GC re-report (monotonic, max-wins) | GC-visible copies only | Bonus, if/when GC ships |

Net: an anonymous player who reinstalls without a backup and without iCloud
KV still loses trophies — same accepted risk as every other stat — but the
two cheap mirrors shrink that hole to nearly zero for real players.

---

## 5. Reward policy

| Option | Economy risk (from internal-economy.md) | Verdict |
|---|---|---|
| **P1 — Prestige-only** (pure PSN) | Zero. | Base policy |
| **P2 — Prestige + 3-5 earned-only regalia cosmetics at true milestones** | Zero coin inflation; reuses the proven Trophy-ball/golden-gauntlet gating (Cosmetics.swift:105); advertises the catalog. Must be styled as *earned regalia* (gold trim, laurels, engraved marble) so it complements rather than undercuts paid families; never in shop/rotation/bundles; excluded from all completion math. | **Recommended — RULED 2026-07-02: adopted** |
| **P3 — Small coin grants** | Quantified in economy §5c: a 40-trophy bronze sweep at 25-50 coins injects 1,000-2,000 coins (~1 free Legendary at the live 1,500 price; the $0.99 pack now grants 750), front-loaded in week 1 and paid retroactively to every existing player at launch; full sweeps of 5,000-10,000 break the 30-60-min time-to-afford calibration outright. Stacks double-pay on the daily ladder Mac already cut 86%. Also the overjustification trap. If ever wanted for feel: lifetime pool ≤ ~105-315 coins total, nothing over 35/trophy, all via `addCoins`, re-derived against the live post-reprice catalogue (the 750/1,000/1,250/1,500 reprice merged 2026-07-02, PR #124) — i.e., so constrained it isn't worth the balancing tax. | Not recommended |

**Recommendation: P2 — RULED 2026-07-02 (decision #3): adopted.** Mac's
words: trophies are "purely clout (recognition)", "maybe some cosmetics for
prestige and earned regalia", and "Do not mint coins for trophy rewards."
Concretely: the **capstone grants one
exclusive regalia ball** (engraved trophy-gold — visually distinct from both
the purchasable catalog and the Diamond/Money IAP items), and 2-4 more
regalia pieces sit on true monuments (all 8 tracks; all minigames won on
Hard; climb world milestones). Everything else pays nothing but the toast,
the rarity label, and the showcase. **Binding rider (Diamond ruling, §2 R2):
no regalia cosmetic may reference the Diamond ball** — regalia reads as
earned trophy-gold, never as the paid Iconic tier. The written commitment is
**DONE (2026-07-02)**: **trophies never mint coins** is recorded as the
trophy-system addendum in `docs/economy/07-decisions.md` — the rulings log,
on main since PR #113 — with the one-line pointer from
`docs/economy/README.md` in place (S4-T6 re-verifies both at freeze; nothing
is queued). Trophies must also stay
out of the planned Roll Pass's reward territory — the pass sells content and
cosmetics; trophies only ever confer status and regalia.

Also: fixing the badge wall removes the existing "Unlimited Power"
pay-for-badge anti-pattern (ProfileView.swift:461-466) — it must **not**
migrate into the trophy list.

---

## 6. Unlock UX

**Toast anatomy.** One compact banner, top of screen (clear of the
tilt-critical play area), auto-dismiss ~3s: grade icon + trophy name +
grade-colored accent; one **signature unlock sound** used for every grade
(the sound is the brand — PSN's lesson), differentiated by **haptics**:
light impact (Bronze/Silver), medium (Gold), heavy + double-tap (Diamond).
Tapping the toast deep-links to the trophy in the Trophy Room.

**Binding rider (Diamond ruling, §2 R2 — 2026-07-02):** the Diamond grade's
icon and accent are bespoke — its glyph/color treatment must be visually and
contextually distinct from the Diamond *ball* / Iconic cosmetic gating tier
(the $19.99 paid exclusive) everywhere the grade renders (toast, Trophy Room
rows, showcase). Copy discipline rides along: UI copy never says "Diamond
trophy" of the cosmetic tier nor "Diamond cosmetic" of the trophy grade.
Enforced in sprint S2-T1's acceptance criteria.

**Never mid-run.** In a tilt game a banner is a death sentence (f2p §7.10).
Unlocks earned during a run queue and present **coalesced at run end** on the
existing result overlays — climb `winOverlay` (BallGameView.swift:4109), the
per-minigame result overlays, and the fell/out-of-lives overlays. Multiple
unlocks in one run = one stacked card ("3 trophies unlocked"), not three
toasts.

**Capstone blowout** (and a lighter version for Diamond-grade): full-screen
moment — unique fanfare distinct from the standard chime, confetti burst,
the trophy rendered big, then an auto-composed **share card** via the
existing `ResultShareCard` machinery (Cosmetics.swift:3707) — the mobile
analog of the PS5 platinum clip. Shown once, replayable from the Trophy Room.

**Anti-spam batching.** Retroactive grants at launch (existing players will
qualify for many trophies instantly) get a **single one-time "Trophy Room
opens" summary sheet** — never a toast cascade. Rate limit: max 1 toast
in-flight; overflow coalesces.

**Accessibility.** Every toast posts a VoiceOver announcement ("Trophy
unlocked: <name>, Gold"). `reduceMotion` swaps confetti/scale animations for
crossfades. Haptics respect the existing `haptics` setting; sounds respect
the `sound` setting. Grade must never be conveyed by color alone — the icon
shape differs per grade.

---

## 7. Trophy Room UX

**Entry points:** a Trophies tile in the Home nav grid (HomeView.swift:319-330)
and the rebuilt Badges card on ProfileView linking through. Two Home-grid
collisions to resolve when the tile lands (sprint S2-T3): the grid is fully
packed (a 2×4 arrangement under the Play row — Leaderboard / Game Modes
(2-wide) / Shop, then Settings / Clans / Friends / Profile — no free cell),
so either the grid grows a row or an existing cell moves; and the
**Leaderboard tile already uses `trophy.fill`** as its glyph
(HomeView.swift:321), so either Leaderboard re-icons (e.g. `chart.bar.fill`,
`list.number`) or Trophies takes a distinct glyph (`rosette`, `medal.fill`).

**List structure.** Grouped by content area, ordered along the common play
path (Apple HIG): Getting Rolling (discovery/tutorial arc) → The Climb
(worlds/stars/streaks) → Challenge Tracks → Minigames (per-mode subsections)
→ Collections (cosmetics/bundles) → Social (friends/clans/gifts) → the
capstone row. Header shows overall completion % and per-grade counts.
Sort toggles: play-path (default) / rarity / recently unlocked / locked-first.

**Row anatomy:** grade icon, name, description, rarity label (post
cold-start), unlock timestamp if earned, **progress bar for cumulative
trophies** ("Win 50 Paint Ball matches — 31/50") fed by the same latched
counters that trigger the unlock. Detail view adds the raw rarity %.

**Hidden trophies:** 5 in the shipped catalog (§1 P9, decision #14). Render
as "??? — Hidden trophy" rows that reveal on unlock; no "reveal all" toggle
needed at that count.

**Pinning (PS5's most re-engaging feature):** pin up to 3 trophies; pinned
trophies surface as a compact progress chip on GameMenuView and pre-run
screens — a standing answer to "what am I chasing?"

**Profile showcase.** Own profile: the Badges card becomes the Trophy card
(counts per grade, capstone status, pinned/rarest highlights). **Public
profiles:** sync a small showcase to Supabase — per-grade counts + up to 3
showcased trophy ids (player-chosen, default = rarest earned) — rendered on
PublicProfileView, which today explicitly says badges "aren't synced".
Showcase visibility default: **on for signed-in players** (it's the point of
the feature; profiles are already opt-in via sign-in), with a Settings toggle.

**Clan surface (defer, small):** v1 ships nothing clan-specific. Cheap
fast-follow: post a `clan_events` row on capstone/Diamond unlocks ("Mac earned
the capstone") — the activity-feed table already exists.

**Binding rider (Diamond ruling, §2 R2):** every rarity surface in the room —
list rows, detail views, showcases — follows §3's no-diamond-iconography rule,
and §6's glyph/copy discipline applies wherever a grade renders: the Diamond
grade icon never borrows the Diamond ball's art, and copy never crosses
"Diamond trophy" (grade) with "Diamond cosmetic" (paid tier).

---

## 8. Game Center mirroring strategy

Recommended, as a **separate later phase** — the custom room is canonical and
complete without it (platform doc bottom line: Option C, custom source of
truth + thin GC mirror, the Vampire Survivors architecture).

- **Why bother:** iOS 26 gives GC-enabled games a dedicated Games-app page,
  achievement surfacing, friend-activity re-engagement notifications, and Top
  Played chart eligibility — free discovery for an indie, fully
  compatible with the first-party no-tracking posture (GC is Apple first-party, per-player
  opt-in; declining sign-in degrades to custom-only).
- **What mirrors:** the stable canon subset — climb milestones, track
  completions, capstone. Choose all trophy ids GC-legal from day one
  (alphanumeric, ≤100 chars, permanent). Ration the 1,000-point / 100-slot
  budget: spend well under half at launch, reserve headroom for future
  minigames/tracks (Apple and Xbox both design for rationing).
- **What stays custom-only:** anything whose criteria might still move,
  per-difficulty deep cuts, social trophies, and the regalia grants
  (GC awards points only — rewards live in the custom layer).
- **Mechanics:** `showsCompletionBanner = false` (our toast owns the moment);
  persisted re-report of the full unlock set on launch (idempotent — GC keeps
  max progress); never report interim progress on hidden trophies; never
  trust GC for restore (local + Supabase are the truth). GC's
  `rarityPercent` can display as a secondary "among Game Center players"
  stat when non-nil — never replacing the Supabase number.
- **Config as code:** Xcode 26 GameKit bundle in-repo, or ASC API generation
  from the trophy catalog JSON — same philosophy as `LevelOverrides.json`.

---

## 9. Catalog governance

- **Catalog as data.** `TrophyCatalog.json` bundled in-app (the
  LevelOverrides pattern): id, title, pre/post descriptions, grade, area,
  criteria key + target, hidden flag, reward ref, `addedInVersion`. A
  guardrail test validates ids (GC-legal, unique, lowercase-kebab matching
  repo convention), grade budgets, and that no criteria references a
  specific level layout or an IAP-gated item.
- **Stable IDs, immutable criteria.** Once shipped, an id and its unlock
  rule never change (Xbox XR-060 / GC permanence as house rules). Text and
  art may be polished; semantics may not. Fixing a broken trophy =
  loosening criteria only (never tightening) + auto-grant to anyone who met
  the old bar.
- **Adding trophies post-launch:** additive-only, batched with content
  updates (new minigame ships with its trophies). New trophies **do not**
  retroactively invalidate the capstone: capstone = the launch base list —
  per the catalog, the **73 visible Bronze/Silver/Gold** trophies (Social,
  Secret & Whimsy, and the Diamond trophies excluded — decision #14, RULED
  2026-07-02); post-launch
  additions join versioned groups (PSN's DLC-group
  model) that never gate the already-earned capstone. Rarity implication:
  new trophies inherit the full install denominator and debut Ultra Rare —
  expected and fine; the cold-start suppression (§3) applies per-trophy by
  earn-count if wanted, or just let labels settle over the daily recompute.
- **Never remove an earned trophy.** Retiring a trophy = hide it from the
  locked list for players who lack it; earners keep it forever
  (unobtainable-trophy graveyards are the most-litigated grievance —
  f2p §7.5).
- **Kill-switch / remote config:** the app has no remote-config system
  today; don't build one for this. The proportionate lever: trophy *display*
  can consult `trophy_stats` (already fetched) for a server-set
  `is_paused` flag per trophy to hide a glitched trophy's UI within a day,
  while unlock logic stays client-side and additive. Full remote catalog
  control is out of scope.

---

## 10. Anti-cheat / integrity

**Trust model: client-trusted, by design.** Unlocks are computed and latched
on-device; Supabase writes are client-asserted, just like every leaderboard
stat today (client-trusted absolute snapshots, CHECK constraints only —
backend §4.4). GC reporting is also client-asserted; Apple does no indie-side
validation.

**What's at stake:** cosmetic status and rarity percentages. No money, no
gameplay advantage. The proportionate posture for an indie:

1. **Don't harden the client.** A jailbroken device editing UserDefaults is
   indistinguishable from a legit player and affects only their own profile.
2. **Keep the aggregates spam-resistant, not cheat-proof:** unique
   constraint on (install_id, trophy_id); server-side timestamp
   (`unlocked_at DEFAULT now()`, ignore client clocks for counting); basic
   rate plausibility in the rollup job (an install unlocking the entire
   catalog in one minute gets excluded from `trophy_stats` counting — flag,
   don't reject the write).
3. **Optional cheap validation for signed-in showcases:** `player_trophies`
   inserts could cross-check the player's own `players` stat row (e.g. a
   "climb world 10" trophy vs `climb_level`) via a CHECK-style trigger — do
   this only if showcase abuse actually appears; it costs schema coupling.
4. **Never let rarity feed rewards** (§3) — that keeps the incentive to
   forge unlocks at "bragging in a small community," which is
   self-policing.

---

## 11. DECISIONS FOR MAC

| # | Decision | Options | Recommendation | Why |
|---|---|---|---|---|
| 1 | **Tier ladder shape** | A: Bronze/Silver/Gold + Platinum (faithful PSN) · B: five rungs (4 per-trophy grades + Platinum-equivalent capstone) | **B** — **RULED 2026-07-02: B, as recommended** (ladder: Bronze → Silver → Gold → Diamond → Platinum) | Roll Along's content depth (5,000 levels, 8 tracks, 12 minigames) earns an aspirational shelf above Gold; it's also what you asked for — minus one word (see #2). The catalog implements B as 49 Bronze / 25 Silver / 11 Gold + 3 Diamond + 1 capstone |
| 2 | **The "Diamond" name** | R1: rename rung 4 → **Legend** (catalog as-authored) or **Summit** (requires renaming the catalog's "The Summit" trophy + "Grand Summit" capstone candidate) · R2: keep Diamond, disambiguate by context · R3: Roll Along-flavored capstone name instead | **R1 — "Legend"** → **RULED 2026-07-02: Mac chose R2 — "Diamond"** (overruling the recommendation; R2's riders are now binding — see §2/§3/§5/§6/§7 + sprint S2-T1/S3-T4) | Diamond already means *$19.99 paid exclusive* in this game (Diamond ball / Iconic tier) and *rare* on Xbox; an earned-pinnacle grade wearing the paid tier's name invites the pay-to-achieve accusation. "Summit" was this brief's original pick, but the catalog ships a rung-4 trophy *named* "The Summit" (`climb_summit`) — as a grade name it would now collide inside our own list (§2). *Ruling note:* `climb_summit` keeps "The Summit"; no rename chain fires under Diamond |
| 3 | **Reward policy** | P1 prestige-only · P2 prestige + 3-5 earned-only regalia cosmetics · P3 small coin grants | **P2** — **RULED 2026-07-02: P2, as recommended.** Mac: trophies are "purely clout (recognition)", "maybe some cosmetics for prestige and earned regalia", "Do not mint coins for trophy rewards." Economy-log addendum DONE same day (§5) | Zero coin inflation, reuses the proven Trophy-ball gating, advertises the catalog; P3 injects 1,000-10,000 coins against the freshly recalibrated economy (calibration-1 + the tier reprice merged 2026-07-02) and stacks on surfaces you already nerfed (§5) |
| 4 | **Rarity architecture** | A: Game Center computes it · B: Supabase aggregation · C: hybrid (local truth + Supabase counts + optional GC) | **C** (B is the load-bearing layer) | Serves 100% of players incl. signed-out/offline; same anonymous UUID as numerator and denominator; GC's number is nil-prone and GC-players-only (§4) |
| 5 | **Rarity denominator** | players table · distinct install UUIDs · per-trophy eligible population | **Distinct install UUIDs** | Closest analogue to PSN's "booted the game"; the only denominator that exists for anonymous players; documented double-count caveats accepted (§3) |
| 6 | **Cold-start threshold** | numbers from day 1 · suppress until 500 installs + 30 days | **Suppress until 500 installs + 30 days** | Day-1 percentages are noise and flip within weeks; labels-first, raw % on detail views (§3) |
| 7 | **iCloud KV entitlement for the trophy ratchet** | yes (new capability) · no (UserDefaults + Supabase only) | **Yes** | Trophies are the highest-emotion state in the game; the ratchet is tiny (one id/timestamp map), union-merge is always safe, and it closes the reinstall hole for anonymous players (§4). It is a posture change from "No iCloud KV sync in use" — your call |
| 8 | **Supabase restore-on-sign-in (first hydrate-from-server path)** | yes, trophies-only union · no | **Yes** | A pure ratchet is the one state where restore can't clobber anything; scoping to trophies avoids the general save-restore problem (§4) |
| 9 | **Game Center mirror** | never · later phase · at launch | **Later phase** (design ids GC-legal now) | Custom room is complete without it; iOS 26 Games-app discovery is real upside worth one small service class when the catalog has settled (§8) |
| 10 | **Public showcase default** | on for signed-in (with toggle) · opt-in | **On for signed-in, Settings toggle** | Sign-in is already the opt-in gate for public profiles; a showcase nobody sees defeats the culture goal (§7) |
| 11 | **Pay-adjacent trophies** | none ever · allow "own Diamond/Money" style trophies | **None ever** *(formally still open — #3's 2026-07-02 never-mint-coins ruling affirms the spirit, but this row awaits its own ruling)* | One paid trophy reframes the whole list as marketing; also kills the existing "Unlimited Power" badge pattern during migration, and keeps Money items secret (§5, economy §5b) |
| 12 | **Retroactive grants at launch** | grant instantly from existing stats · start everyone at zero | **Grant from existing stats** (via the one-time summary sheet, no toast cascade) *(still open — proceeding per recommendation mid-S0; Mac may veto)* | Existing stats (stars, wins, tracks, streak history) already prove the deeds; zeroing insults the exact veterans trophy culture is for (§6) |
| 13 | **Anonymous unlock counting table** (`trophy_unlocks`, INSERT-only anon, first anon-readable aggregate in `trophy_stats`) | approve · rarity for signed-in only | **Approve** | Stays inside the existing not-linked analytics envelope (same install UUID); without it, rarity exists for ~0% of players (§4, backend §5-6) |
| 14 | **Catalog shape divergences from this brief** (see the reconciliation note at the top) | Adopt trophy-catalog.md as-authored: 89 trophies (49/25/11/3/1) · 5 hidden (all Secret & Whimsy) · capstone = the 73 visible B/S/G, excluding Social/Whimsy/Legends · point weights deferred · capstone named "Roll of Honor" — OR pull the catalog back to this brief's sketch (~40-55 trophies, 0-2 hidden, capstone = every base trophy, literal "Platinum") | **Adopt the catalog** → **RULED 2026-07-02: adopted, as recommended** — with two same-day naming overrides: rung 4 = **Diamond** (#2, R2) and capstone display name = **Platinum** ("Roll of Honor" survives only as an optional future Trophy Room screen-name idea; all ids unchanged) | The catalog is the later-stage, item-level artifact and internally consistent; this brief's numbers were pre-catalog estimates. Excluding Social/hidden/Legends from the capstone is Sony's own house rule (difficulty and population-dependence quarantined off the platinum path) and keeps the capstone offline- and $0-achievable |

Suggested reading order for ruling: #14 (catalog reconciliation), #2 (naming),
#3 (rewards), #7/#8/#13 (the three posture changes), then the rest are
mechanics.

**Ruling status (2026-07-02):** #1, #2, #3, and #14 — the S0 gate — are
RULED (see the rows above). Still open: #12 (mid-S0 — proceeding per
recommendation, Mac may veto), #4/#5/#6/#7/#8/#10/#13 plus the rarity display
vocabulary (catalog Q8) before S3, and #9/#11 before launch (#11's spirit is
affirmed by #3's never-mint-coins ruling, but the row itself is unruled).

---

## Appendix — v1 scope sketch (for the implementation brief, not a ruling)

- Launch scope — superseded by `trophy-catalog.md` (decision #14, RULED
  2026-07-02: adopted): **89
  trophies** — 49 Bronze / 25 Silver / 11 Gold / 3 Diamond / 1 Platinum
  capstone.
  (This brief's original ~40-55 sketch predates the catalog.) At 89 of GC's
  100 slots, "well under the caps" no longer holds for a full mirror — the
  §8 GC mirror must stay a rationed canon *subset*, with the 1,000-point
  budget allocated at mirror time (point weights deferred per #14).
- Engine: `TrophyEngine` observing/called from the GameState choke points
  (`recordResult`, `advanceLevel`, `advanceTrackProgress`,
  `recordMinigameResult`, `recordCompetitiveWin`, `grant`, `addCoins`,
  `claimDailyReward`, PB recorders) + StoreKit `deliverReward` excluded from
  criteria by policy. Disco and RollOut write bests in-view today and need
  rerouting through GameState first (features §3).
- New instrumentation needed for launch criteria: lifetime falls, lifetime
  coins earned (hook `addCoins`), solo-mode play counts, no-fall streaks —
  all latched counters in the trophy store, not new GameState stats.
- New files enter `project.pbxproj` by hand (4 entries each — repo gotcha).
- Supabase DDL enters as a proper migration; `trophy_stats` rollup as a
  scheduled job; RLS decisions per §4.
- Merged-branch reconciliation (2026-07-02, `origin/main` `42d1925`): the
  CotD `.oneShot` fast-path (PR #123) and track-coin-masking fix (PR #119)
  are MERGED — the "land before trophies key off climb records" precondition
  is satisfied; the trophy engine's climb-mode guard is now defense-in-depth,
  keyed to `activeMode.progression.recordsClimbResult` (mirroring the shipped
  assert in BallGameView). The tier reprice is merged too (PR #124): coin
  values (if any ever) re-derive against the live 750–1,500 catalogue at the
  canonical ~25 coins/min — there is no pending reprice ruling to wait for.
