# App Privacy answers for Roll Along 1.0

Answers for App Store Connect → App Privacy, based on what the app's own code
sends and on Google's published description of what the Google Mobile Ads SDK
collects (Google's "App store data disclosure" page for iOS, describing SDK
13.12.0, read 2026-11-15; the app is pinned to SDK 13.4.0).

**Check these against Xcode before saving them.** After archiving, the
Organizer's "Generate Privacy Report" lists what the app's privacy file and
the Google SDK's own privacy file declare. If that report and this page
disagree, the report wins and this page should be corrected.

## First question

**Do you or your third-party partners collect data from this app?** Yes.

## Tracking

**Is data used to track the user?** No, for every data type.

Why: the app never shows the tracking prompt, never reads the advertising
identifier, and requests non-personalized ads only. Apple defines tracking as
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
| Location → **Coarse Location** | Google: approximate location derived from the IP address | No | Third-Party Advertising |
| Diagnostics → **Crash Data** | Google: SDK crash logs | No | Analytics; Third-Party Advertising |
| Diagnostics → **Performance Data** | Google: launch time, hang rate, energy use | No | Analytics; Third-Party Advertising |
| Diagnostics → **Other Diagnostic Data** | App: phone model, iOS version and app version on each analytics event | No | Analytics |

App Store Connect asks about each data type once. Where a type appears twice
above (Gameplay Content), give the combined answer: **linked: yes**, purposes
**App Functionality and Analytics**.

## Data types to answer "not collected"

Name, phone number, physical address, health and fitness, financial info,
precise location, sensitive info, contacts, emails or text messages, photos or
videos, audio, customer support, other user content, browsing history, search
history, surroundings, body data.

There is no player-written content: names are built from preset lists and clan
chat is fixed phrases.

## Open points

- **Email Address.** Declared to be safe. After a fresh sign-in on a new
  account, look at Supabase → Authentication → Users. If the email column is
  empty, remove Email Address here and from `RollAlong/PrivacyInfo.xcprivacy`.
- **"Linked" for Google's rows.** Marked "No" because ads are non-personalized
  and no account information is passed to Google. Google's page does not state
  a linked/not-linked answer per type; the Xcode privacy report shows what the
  SDK itself declares.
- **Coarse location.** Google says it can be switched off in the SDK. It is
  left on.

## Other fields on the same page

- **Privacy Policy URL:** https://mfaldet.github.io/roll-along/privacy.html
- **User Privacy Choices URL:** optional; leave empty.
