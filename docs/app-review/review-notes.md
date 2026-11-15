# App Review notes for Roll Along 1.0

Paste the block below into App Store Connect → the version page → App Review
Information → Notes. It is under the 4,000-character limit. Update it if the
app changes.

---

```
Roll Along is a tilt-controlled marble game. It needs a physical iPhone: the marble is steered by tilting the device.

SIGN-IN — NO DEMO ACCOUNT NEEDED
The game is fully playable without an account. Sign in with Apple is optional and is the only sign-in method; please use your own Apple ID. It is needed only for Leaderboard, Clans and Friends. The app does not request name or email. To sign in: Home > Settings > Account > Sign in with Apple (tapping Leaderboard, Clans or Friends while signed out also offers it).

WHERE THINGS ARE (buttons on the Home screen)
- Leaderboard, Clans, Friends: require sign-in.
- Shop: cosmetics bought with in-game coins. Catalog is inside the Shop.
- Profile and Settings.
- "Games" opens the 11 minigames and the 8 challenge tracks.

IN-APP PURCHASES (10)
Lives — tap the lives counter at the top-left of the Home screen:
  10 Lives, 60 Lives, 130 Lives (consumable), Unlimited Lives (non-consumable).
Coins — open Shop and tap the coin balance at the top-right:
  750, 4,500, 10,000, 22,500 and 60,000 coins (consumable). The 60,000 pack also includes the "Money Ball" skin; this is a fixed item, shown on the purchase card. There are no randomized purchases.
Starter Pack (non-consumable) — a one-time offer shown automatically on the Home screen the first time the coin balance reaches 250, and available for 48 hours after it first appears. Quickest way to see it: buy the 750-coin pack, then return to Home.
Restore: Settings > Purchases > Restore Purchases.

ADS
One rewarded video (Google AdMob), shown only when the player chooses "Watch ad" for an extra life. Ads are non-personalized, limited to Google's "Teen" content rating, and the app does not track (no ATT prompt, no IDFA).

NAMES AND CHAT — NO USER-WRITTEN CONTENT
Players cannot type any text that other players see. Nicknames (Settings > Nickname) and clan names are assembled from preset word lists plus a number; clan tags are derived from the name; clan descriptions are picked from a fixed list; clan chat is a set of fixed phrases. The server rejects anything not built from these lists.

ACCOUNT DELETION
Settings > Account > Delete Account (visible when signed in). After confirming, Apple asks the player to confirm once more; the account and all its server data (profile, friends, clan membership, leaderboard entries, trophies) are then deleted immediately and the player is signed out.

RELEASE CALENDAR FOR COSMETICS
Cosmetic collections are released on a fixed calendar stored in the app: 13 at launch, then a new group every 4 weeks. Upcoming collections are announced by name and date in Shop > Catalog > "Coming soon". Seasonal collections are available during their season each year. Nothing is switched on remotely.

NOTIFICATIONS
Two optional local notifications (shop restock, lives full), off until the player turns them on in Settings.

PRIVACY POLICY AND CONTACT
Settings > About, and https://mfaldet.github.io/roll-along/privacy.html
Contact: rollalongsupport@gmail.com
```

---

## Before pasting, check these are true

- [ ] `docs/social-schema-v4.sql` has been applied ("The server rejects anything
      not built from these lists" is only true after that).
- [ ] The Supabase project is running and not paused during review.
- [ ] All ten purchases are "Ready to Submit" and attached to the version.
- [ ] The Home button labels and paths above match the build you submit.
