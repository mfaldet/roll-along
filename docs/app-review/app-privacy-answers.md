# App Privacy answers for Roll Along 1.1

Answers for App Store Connect → App Privacy, based on what the app's own code
sends and on Google's published description of what the Google Mobile Ads SDK
collects (Google's "App store data disclosure" page for iOS, describing SDK
13.12.0, read 2026-11-15 and again 2026-11-23; version 1.1 uses SDK 13.12.0).

Version 1.1 is for players aged 9 and up and treats every player as a child:
ad requests carry Google's child age treatment, ad content is capped at
"General audiences", and the SDK's coarse-location collection is switched off.
None of that changes which rows are declared below except Coarse Location; see
"Open points".

**Check these against Xcode before saving them.** After archiving, the
Organizer's "Generate Privacy Report" lists what the app's privacy file and
the Google SDK's own privacy file declare. If that report and this page
disagree, the report wins and this page should be corrected.

## First question

**Do you or your third-party partners collect data from this app?** Yes.

## Tracking

**Is data used to track the user?** No, for every data type.

Why: the app never shows the tracking prompt, never reads the advertising
identifier, requests non-personalized ads only, and marks every ad request for
child treatment. Apple defines tracking as
linking data from the app with third-party data for targeted advertising or
ad measurement, or sharing it with a data broker. If ads are ever changed to
personalized, this answer changes and the tracking prompt becomes required.

## Data types to declare

"App" means the app's own code sending to its Supabase backend. "Google" means
the Google Mobile Ads SDK.

| Data type (Apple's name) | Collected by | Linked to the user? | Purposes |
|---|---|---|---|
| Identifiers → **User ID** | App: the account ID created by Sign in with Apple | Yes | App Functionality |
| Identifiers → **Device ID** | App: a random ID per install, for analytics. Google: a device identifier (not the advertising identifier, since the app never requests it) | No | Analytics; Third-Party Advertising |
| Contact Info → **Email Address** | App: only if Apple includes one with the sign-in; the app does not ask for it | Yes | App Functionality |
| User Content → **Gameplay Content** | App: signed-in profile shown to other players (preset nickname, level, scores, clan, friends, trophies) | Yes | App Functionality |
| User Content → **Gameplay Content** | App: anonymous gameplay events (levels, rounds, trophies) | No | Analytics |
| Usage Data → **Product Interaction** | App: screens opened, buttons tapped. Google: ad taps and video views | No | Analytics; Third-Party Advertising |
| Usage Data → **Advertising Data** | App: which steps of a rewarded ad happened. Google: ads the player has seen | No | Analytics; Third-Party Advertising |
| Purchases → **Purchase History** | App: that a purchase happened, with product and displayed price, against the random install ID | No | Analytics |
| Location → **Coarse Location** | Google: approximate location derived from the IP address. The SDK's own collection is switched off in 1.1; kept declared until confirmed (see Open points) | No | Third-Party Advertising |
| Diagnostics → **Crash Data** | Google: SDK crash logs | No | Analytics; Third-Party Advertising |
| Diagnostics → **Performance Data** | Google: launch time, hang rate, energy use | No | Analytics; Third-Party Advertising |
| Diagnostics → **Other Diagnostic Data** | App: phone model, iOS version and app version on each analytics event, and on each feedback message | No (analytics); Yes when feedback is sent signed in | Analytics; App Functionality |
| User Content → **Customer Support** | App: the Bug / Idea / Question / Compliment message a player writes in Settings → Send Feedback, with the screen it came from; linked to the account ID only when signed in | Yes | App Functionality |

App Store Connect asks about each data type once. Where a type appears twice
above (Gameplay Content), give the combined answer: **linked: yes**, purposes
**App Functionality and Analytics**. For Other Diagnostic Data, give
**linked: yes** (feedback sent while signed in carries the account ID), purposes
**Analytics and App Functionality**.

Send Feedback also sends a one-way hash of the random install ID, used only to
limit how many messages one phone can send. It is not stored with the raw ID
and cannot be matched to analytics, so it adds no new Device ID purpose; Device
ID stays declared for analytics as above.

## Data types to answer "not collected"

Name, phone number, physical address, health and fitness, financial info,
precise location, sensitive info, contacts, emails or text messages, photos or
videos, audio, other user content, browsing history, search history,
surroundings, body data.

The only player-written text is Send Feedback, which goes privately to the
developer (declared above as Customer Support). Nothing a player writes is shown
to other players: names are built from preset lists and clan chat is fixed
phrases.

## Open points

- **Email Address.** The app asks Apple for no email. Whether Supabase stores
  one anyway is answered by running `docs/privacy/check-stored-emails.sql`
  (read-only). If it reports no emails, remove Email Address here and from
  `RollAlong/PrivacyInfo.xcprivacy`. Until then it stays declared, to be safe.
- **Coarse location.** Version 1.1 sets `coarseLocationCollectionEnabled` to
  false, and the app never asks for location permission. Google's disclosure
  page says coarse location "including location derived from IP address" can be
  disabled "through SDK controls", which points at this setting, but it does
  not say in so many words that IP-derived location stops. Keep the row
  declared unless the Xcode privacy report for the 1.1 archive no longer lists
  it, or Google confirms it.
- **"Linked" for Google's rows.** Marked "No" because ads are non-personalized
  and no account information is passed to Google. Google's page does not state
  a linked/not-linked answer per type; the Xcode privacy report shows what the
  SDK itself declares.

## Settings elsewhere in App Store Connect that 1.1 changes

These are not on the App Privacy page, but they must agree with it.

- **Age rating.** Redo the age rating questionnaire so the result is 9+.
  Version 1.0 was submitted as 13+.
- **Kids Category.** Optional, and a separate decision from the age rating. It
  has its own rules on third-party ads and analytics. Do not select it without
  deciding that on purpose; see `docs/privacy/questions-for-a-lawyer.md`.
- **Privacy Policy URL.** Unchanged until the new policy is approved and
  published. The draft is `docs/privacy/privacy-policy-draft-1.1.html`.
- **AdMob.** In the AdMob console, the app's own "maximum ad content rating"
  and any child-directed setting should agree with the app. The SDK settings
  override the console, so this is for consistency, not function.

## Other fields on the same page

- **Privacy Policy URL:** https://mfaldet.github.io/roll-along/privacy.html
- **User Privacy Choices URL:** optional; leave empty.
