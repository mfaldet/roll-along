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
Solo minigames pay no coins. Competitive minigames pay 1, 2 or 3 coins on Easy, Normal or Hard whatever the result; a win also earns 1 ticket. Gold Rush, a 30-second bonus round, costs 5 tickets and pays up to about 100 coins. Tickets come only from wins, cannot be bought and have no other use.

IN-APP PURCHASES (10)
Lives (tap the lives counter, top-left of Home): 20, 120, 300 Lives (consumable); Diamond Balls, unlimited lives (non-consumable).
Coins (Shop, tap the coin balance): 100, 600, 1,300, 3,000, 10,000 (consumable); the 10,000 pack includes the fixed "Money Ball" skin shown on its card. No randomized purchases.
Starter Pack (non-consumable): 500 coins plus the Aurora ball, trail and boundary, one time only; offered on Home once the coin balance first reaches 250, for 48 hours. Quickest way: buy 600 coins, return to Home.
Restore: Settings > Purchases > Restore Purchases.

ADS
One rewarded video (Google AdMob), only when the player chooses "Watch ad" for an extra life. Non-personalized, "Teen" rating, no tracking (no ATT prompt, no IDFA).

NO USER-WRITTEN CONTENT
Players cannot type text other players see. Nicknames are two preset words; clan names are two preset words plus a number; clan descriptions and clan chat are fixed phrases. The server rejects anything else. The only free-text field is Send Feedback, which goes privately to the developer.

CLANS, FRIENDS AND THE MONTHLY CLAN BATTLE
Clans hold up to 12 players. Each player has a server-assigned friend code (letters and digits) that others can type on the Friends screen; it is shown only if the player shares it. Each calendar month, a clan's score is the new stars its members earn in the main game, counted by our server. At month end, contributing members of ranked clans receive 100 to 1,000 in-game coins, claimed on the Clans screen. December 2026 is a warm-up with no prizes. No entry fee, nothing to buy; coins buy cosmetics only and have no cash value. An owner can remove a member or hand over ownership. Players can ask their clan for lives (up to 6, free to givers) and send one life per day to each friend.

ACCOUNT DELETION
Settings > Account > Delete Account (when signed in). After confirming, the account and all its server data are deleted immediately and the player is signed out.

COSMETIC RELEASE CALENDAR
Cosmetic collections release on fixed dates. The dates are kept on our server, with the same dates built into the app, so we can adjust a date without an app update. This only changes when a cosmetic collection appears in the Shop; nothing else is switched on remotely. The next collections are shown by name and date in Shop > Catalog > "Coming soon". Seasonal collections return each year.

TROPHIES
86 display-only trophies earned by playing; they never grant coins or purchasable items.

SEND FEEDBACK
Settings > About > Send Feedback: Bug, Idea or Complaint, up to 1,000 characters, private to the developer (players cannot read it back). Adds app version, iOS version, phone model, source screen, and account ID if signed in. 5 per phone per day; sent later if offline.

NOTIFICATIONS
Two optional local notifications (shop restock, lives full), off until turned on in Settings.

PRIVACY POLICY AND CONTACT
Settings > About, and https://mfaldet.github.io/roll-along/privacy.html
Contact: rollalongsupport@gmail.com
```

---

## Before pasting, check these are true

- [ ] `docs/feedback/feedback-schema.sql` (step 10) has been applied, or
      Send Feedback messages will wait on the phone and never arrive.
- [ ] `docs/cosmetics/cosmetic-calendar.sql` (step 11) has been applied. Until
      it is, the app uses its built-in dates, which are the same, so nothing
      breaks; but dates can only be changed from the server after it is applied.
- [ ] `docs/social/clan-look.sql` (step 13, after step 12) has been applied, or
      a clan owner's icon and color choice cannot be saved (clans still show
      the default shield on blue, so nothing else breaks).
- [ ] `docs/social-schema-v4.sql` has been applied ("The server rejects anything
      not built from these lists" is only true after that).
- [ ] The Supabase project is running and not paused during review.
- [ ] All ten purchases are "Ready to Submit" and attached to the version.
- [ ] The Home button labels and paths above match the build you submit.
