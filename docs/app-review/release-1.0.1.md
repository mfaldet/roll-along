# Release 1.0.1

Version 1.0.1, build 2026112101. One bug fix: the "Watch ad" button could stay stuck on "Ad not ready yet" until the app was closed and reopened.

## What's New (App Store text)

> Fixed a problem where "Watch ad" for an extra life could stay stuck on "Ad not ready yet." Ads now load again by themselves, so the button works without restarting the game.

## What was checked, and what was not

- **Run and passing:** the 8 new unit tests in `RollAlongTests/AdRetryScheduleTests.swift`, compiled and run with Swift 6.0.3 on Linux against `RollAlong/AdRetrySchedule.swift`.
- **Syntax-checked only:** `AdManager.swift`, `BallGameView.swift`, `RollAlongApp.swift`, `SettingsView.swift` and `BallSkinView.swift`. They need the iOS SDK and the Google Mobile Ads SDK to compile, which the machine that prepared this release does not have.
- **Not run:** the full existing test suite and the simulator check. Both need Xcode. They are steps 2 and 3 below.

## Debug-only test button

Settings > Debug > **Show Out of Lives screen** exists in Debug builds only. All of its code in `SettingsView.swift` is inside `#if DEBUG`, the project defines `DEBUG` for the Debug configuration only, and the scheme archives with the Release configuration, so none of it is compiled into the build that goes to the App Store.

## Steps for the owner

1. Pull the branch and open `RollAlong.xcodeproj` in Xcode.
2. Run the full test suite (Product > Test) on an iPhone simulator. Every test should pass, including the new `AdRetryScheduleTests`.
3. Check the fix in the simulator with a Debug build (it uses Google's test ad unit). The simulator cannot be tilted, so a level cannot be played or lost there; the debug button below is the way to the Out of Lives screen.

   **To reach the Out of Lives screen, at any point below:** on the Home screen tap **Settings**, scroll to the **Debug** section at the bottom, and tap **Show Out of Lives screen**. It sets lives to zero, moves the saved game past the tutorial levels if it is still in them, and opens Adventure on the real Out of Lives screen. On a fresh simulator, first close the welcome screen and any reward sheet so the Home buttons show.

   **A. The ad plays and pays one life.**
   1. With the Mac online, run the app and wait a few seconds on the Home screen.
   2. Go to the Out of Lives screen with the debug button.
   3. Tap **Watch ad — +1 life**. A Google test ad should play. If "Ad not ready yet" shows instead, tap OK, wait a few seconds and tap again.
   4. Watch the ad to the end and close it. Back on the Out of Lives screen, a **Play Now** button should now show above Watch ad, and the lives row should show one extra life.

   **B. The bug itself: a failed load recovers without restarting the app.**
   1. Stop the app. Turn the Mac's Wi-Fi off (the simulator uses the Mac's connection).
   2. Run the app and wait about 30 seconds on the Home screen. Offline, Google's SDK can take that long to finish starting, and no ad load is attempted before it has.
   3. Go to the Out of Lives screen with the debug button and tap **Watch ad — +1 life**. "Ad not ready yet" should show. Tap OK.
   4. Turn the Mac's Wi-Fi back on and wait until the Mac is online again.
   5. Tap **Watch ad — +1 life**. This tap starts a load. If the alert shows again, tap OK, wait a few seconds and tap once more. The test ad should play. In version 1.0 it never would: the alert kept showing until the app was closed and reopened.

   **C. The retry happens by itself.**
   1. Repeat steps B1 to B4, then do not tap anything. Stay on the Out of Lives screen for up to 2 minutes (the longest wait between retries).
   2. Tap **Watch ad — +1 life** once. The ad should play on that first tap.

   **D. Returning to the app loads an ad.**
   1. Repeat steps B1 to B3.
   2. Send the app to the background (Device > Home in the Simulator menu).
   3. Turn the Mac's Wi-Fi back on and wait until the Mac is online again.
   4. Open the app again from the simulator's Home screen and wait about 10 seconds.
   5. Tap **Watch ad — +1 life** once. The ad should play on that first tap.
4. Confirm the version reads 1.0.1 and the build 2026112101 (target RollAlong > General).
5. Select "Any iOS Device (arm64)", then Product > Archive.
6. In the Organizer, Distribute App > App Store Connect > Upload.
7. In App Store Connect, create version 1.0.1 for Roll Along and select the uploaded build.
8. Paste the What's New text above.
9. **On the new version's page, enter the Marketing URL: `https://faldetadvisory.com/portfolio/roll-along`.**
10. Submit for review.
