# App Review notes for Roll Along 1.0

Paste the block below into App Store Connect → the version page → App Review
Information → Notes. It is under the 4,000-character limit. Update it if the
app changes.

---

```
Roll Along is a tilt-controlled marble game and needs a physical iPhone. The main mode, Adventure, starts from "Play" on the Home screen.

SIGN-IN (NO DEMO ACCOUNT NEEDED)
Fully playable without an account. Sign in with Apple is optional, the only method, and needed only for Leaderboard, Clans and Friends; please use your own Apple ID. No name or email is requested. Home > Settings > Account > Sign in with Apple.

WHERE THINGS ARE (Home screen)
Leaderboard, Clans, Friends (sign-in); Shop (cosmetics for in-game coins; Catalog inside); Profile; Settings; "Games" (10 minigames, 8 challenge tracks).

MINIGAME REWARDS
Solo minigames pay no coins. Competitive minigames pay 1, 2 or 3 coins on Easy, Normal or Hard whatever the result; a win also earns 1 ticket. Gold Rush, a 30-second bonus round, costs 5 tickets; each coin caught pays 1 coin (up to 100), or 2 after an optional 10-ticket boost. Tickets come only from wins and cannot be bought.

IN-APP PURCHASES (10)
Lives (tap the lives counter, top-left of Home): 20, 120, 300 Lives (consumable); Diamond Balls, unlimited lives plus the Diamond ball skin (non-consumable).
Coins (Shop, tap the coin balance): 100, 600, 1,300, 3,000, 10,000 (consumable); the first 10,000 pack also includes the fixed "Money Ball" skin shown on its card. No randomized purchases.
Starter Pack (non-consumable): 500 coins plus the Aurora ball, trail and boundary, once; shown on Home at the next app open after the tutorial (levels 1–10), for 48 hours.
Restore: Settings > Purchases > Restore Purchases.

ADS
One rewarded video (Google AdMob), only when the player chooses "Watch ad" for an extra life. Non-personalized, ad content capped at Google's "PG" rating, no tracking (no ATT prompt, no IDFA).

NO USER-WRITTEN CONTENT
Players cannot type text other players see. Nicknames are two preset words; clan names are two preset words plus a number (no tags); clan descriptions and clan chat are fixed phrases. The server rejects anything else. The only free-text field is Send Feedback, which goes privately to the developer.

CLANS, FRIENDS AND THE MONTHLY CLAN BATTLE
Clans hold up to 12 players. Each player has a server-assigned friend code others can type on the Friends screen; it is shown only if shared. Each calendar month, a clan's score is the new stars its members earn in the main game, counted by our server. At month end, contributing members of ranked clans receive 100 to 1,000 in-game coins, claimed on the Clans screen. December 2026 is a warm-up with no prizes. No entry fee, nothing to buy; coins buy cosmetics only and have no cash value. An owner can remove a member or hand over ownership. Players can ask their clan for lives (up to 6, one per clanmate, free to givers); lives can only be given to such requests.

ACCOUNT DELETION
Settings > Account > Delete Account (when signed in). After confirming, the account and all its server data are deleted immediately and the player is signed out.

COSMETIC RELEASE CALENDAR
Collections release on fixed dates kept on our server (also built into the app), so a date can change without an app update; nothing else is switched on remotely. 22 collections are sold, whole or one piece at a time; no other cosmetics are sold. The next collections are shown by name and date in Shop > Catalog > "Coming soon". Seasonal events return each year.

TROPHIES
86 display-only trophies earned by playing; they never grant coins or purchasable items.

SEND FEEDBACK
Settings > About > Send Feedback: Bug, Idea, Question or Compliment, up to 1,000 characters, private to the developer (players cannot read it back). Adds app version, iOS version, phone model, source screen, and account ID if signed in. 5 per phone per day; sent later if offline.

NOTIFICATIONS
Two optional local notifications (shop restock, lives full), off until turned on in Settings.

PRIVACY POLICY AND CONTACT
Settings > About, and https://mfaldet.github.io/roll-along/privacy.html
Contact: rollalongsupport@gmail.com
```

---

## Before pasting, check these are true

- [ ] Steps 1–17 are applied (confirmed: every check query true).  Step 16
      was applied in its original form, which also added
      `rollup_best_seconds`; step 18 removes it.
- [ ] Step 18, `docs/social/rollup-height-only.sql`, has been applied
      (Roll Up is scored by height only).
- [ ] Step 19, `docs/economy/season-prize-settings.sql`, has been applied, so
      clan season prizes are exactly 1,000 / 500 / 250 / 100 coins as the
      notes say.
- [ ] Step 21, `docs/cosmetics/cosmetic-calendar-full-collections.sql`, has
      been applied (release rows only for full collections; optional for the
      app, which ignores the old rows).
- [ ] Step 20, `docs/analytics/events-retention.sql`, has been applied
      (raw analytics events older than 90 days are deleted daily at 03:47 UTC).
- [ ] Right before submitting: delete the app on the test phones, then run
      `docs/launch/wipe-play-data.sql` (preview, wipe, check all true).  A
      test phone that opens the app afterwards re-uploads its scores.
- [ ] The Supabase project is running and not paused during review.
- [ ] All ten purchases are "Ready to Submit", attached to the version, and
      use the names and descriptions in `docs/app-review/in-app-purchases.md`.
- [ ] The Home button labels and paths above match the build you submit.
