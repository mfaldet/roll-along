# Release 1.0.1

Version 1.0.1, build 2026112101. One bug fix: the "Watch ad" button could stay stuck on "Ad not ready yet" until the app was closed and reopened.

## What's New (App Store text)

> Fixed a problem where "Watch ad" for an extra life could stay stuck on "Ad not ready yet." Ads now load again by themselves, so the button works without restarting the game.

## What was checked, and what was not

- **Run and passing:** the 8 new unit tests in `RollAlongTests/AdRetryScheduleTests.swift`, compiled and run with Swift 6.0.3 on Linux against `RollAlong/AdRetrySchedule.swift`.
- **Syntax-checked only:** `AdManager.swift`, `BallGameView.swift` and `RollAlongApp.swift`. They need the iOS SDK and the Google Mobile Ads SDK to compile, which the machine that prepared this release does not have.
- **Not run:** the full existing test suite and the simulator check. Both need Xcode. They are steps 2 and 3 below.

## Steps for the owner

1. Pull the branch and open `RollAlong.xcodeproj` in Xcode.
2. Run the full test suite (Product > Test) on an iPhone simulator. Every test should pass, including the new `AdRetryScheduleTests`.
3. Check the fix in the simulator with a Debug build (it uses Google's test ad unit):
   1. Turn the Mac's network off, launch the game, run out of lives and tap "Watch ad". The "Ad not ready yet" alert should show.
   2. Turn the network back on and stay on the Out of Lives screen. Within about 10 to 30 seconds, tap "Watch ad" again: a test ad should play, and finishing it should add one life.
   3. Send the app to the background and bring it back with no ad loaded: an ad should load without any tap.
4. Confirm the version reads 1.0.1 and the build 2026112101 (target RollAlong > General).
5. Select "Any iOS Device (arm64)", then Product > Archive.
6. In the Organizer, Distribute App > App Store Connect > Upload.
7. In App Store Connect, create version 1.0.1 for Roll Along and select the uploaded build.
8. Paste the What's New text above.
9. **On the new version's page, enter the Marketing URL: `https://faldetadvisory.com/portfolio/roll-along`.**
10. Submit for review.
