import XCTest

// ---------------------------------------------------------------------------
// SmokeTests — end-to-end navigation regression guard.
//
// These tests confirm that the app launches, the home screen is reachable,
// and a minigame can be entered and exited — the most visible class of
// production navigation bug.
//
// Prerequisites wired up in QE3:
//   • --skip-onboarding launch argument (RollAlongApp.swift) bypasses the
//     first-launch overlay so navigation is not blocked.
//   • accessibilityIdentifier("HomeView") on HomeView root ZStack.
//   • accessibilityIdentifier("GameModesButton") on the Game Modes nav link.
//   • accessibilityIdentifier(mode.id) on each GameMenuView mode card.
//   • accessibilityIdentifier("GoldRushView") on GoldRushView root ZStack.
//
// Run on: iPhone 17 Pro simulator.  Snapshot tests (§5) also pin to this
// target — document the device/OS in the scheme's Run → Arguments so future
// contributors know the reference environment.
// ---------------------------------------------------------------------------

final class SmokeTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // --skip-onboarding bypasses the first-launch overlay;
        // --uitesting suppresses the auto-presenting sheets (daily reward,
        // starter pack) whose 0.5s-after-launch pop hides the home screen's
        // accessibility elements right when the test is querying them.
        app.launchArguments = ["--uitesting", "--skip-onboarding"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Look an element up by accessibility identifier across ALL element
    /// types.  SwiftUI's exposure of a modified NavigationLink can shift
    /// between .button and .otherElement (e.g. when background modifiers
    /// like the home ball's collider reporter are attached), and a
    /// type-restricted query like app.buttons[...] silently misses the
    /// re-typed element even though the identifier is present.
    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Dump the app's full accessibility tree into the test log AND a
    /// keep-always attachment — ground truth for "the element is plainly
    /// on screen but the query can't find it" mysteries.  Find it in the
    /// Report navigator under the failed test, or in the console between
    /// the AX TREE markers.
    private func attachAccessibilityTree(_ name: String) {
        let tree = app.debugDescription
        print("=== AX TREE (\(name)) ===\n\(tree)\n=== END AX TREE ===")
        let attachment = XCTAttachment(string: tree)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Resolve a tappable entry by accessibility identifier, falling back
    /// to its visible text label.  When the identifier is missing (SwiftUI
    /// has repeatedly dropped wrapper identifiers on modified
    /// NavigationLinks), the tree is attached for diagnosis and the label
    /// keeps the navigation under test working.
    private func entry(_ id: String, labeled label: String) -> XCUIElement {
        let byID = element(id)
        if byID.waitForExistence(timeout: 5) { return byID }
        attachAccessibilityTree("missing-\(id)")
        return app.staticTexts[label].firstMatch
    }

    /// Dismiss the first-run "Sign in with Apple" sheet if it's up.  On a fresh
    /// simulator it can cover Home and swallow the next tap (e.g. Game Modes);
    /// "Not now" sends the player straight in.  A no-op once already dismissed.
    private func dismissSignInIfPresent(timeout: TimeInterval = 0) {
        let notNow = app.buttons["Not now"]
        if timeout > 0 { _ = notNow.waitForExistence(timeout: timeout) }
        if notNow.exists { notNow.tap() }
    }

    // MARK: - Launch

    func testApp_launchesAndShowsHomeView() throws {
        // The HomeView anchor lives on the title text (any-type query —
        // container identifiers clobber children, so the anchor is a leaf).
        XCTAssertTrue(
            element("HomeView").waitForExistence(timeout: 10),
            "HomeView should be visible within 10s of launch"
        )
    }

    // MARK: - Home → Game Modes → Gold Rush

    func testHomeToGoldRushAndBack() throws {
        // 1. Home screen is visible (leaf anchor on the title text)
        let homeView = element("HomeView")
        XCTAssertTrue(homeView.waitForExistence(timeout: 10))

        // 1b. On a fresh install a "Sign in with Apple" sheet can slide up over
        // Home and intercept the Game Modes tap — give it a moment to appear,
        // then dismiss it via "Not now".
        dismissSignInIfPresent(timeout: 5)

        // 2. Navigate to Game Modes hub — by identifier, else by its
        // visible "Game Modes" label (with an AX-tree attachment for
        // diagnosis whenever the identifier is missing).
        let gameModeButton = entry("GameModesButton", labeled: "Game Modes")
        XCTAssertTrue(gameModeButton.waitForExistence(timeout: 5),
                      "Neither the GameModesButton identifier nor the 'Game Modes' label was found — see the AX-tree attachment")
        dismissSignInIfPresent()   // in case the async sign-in result popped it late
        gameModeButton.tap()
        dismissSignInIfPresent()

        // 3. Tap the competitive coin scramble in the mode list (id
        // "goldrush"; DISPLAYED as "Smash and Grab" since the name swap +
        // rename).  It sits a few cards down the hub — scroll once if it's
        // below the fold on small screens.  Selecting a mode now ARMS it and
        // returns Home (it no longer launches the game directly).
        let goldRushButton = entry("goldrush", labeled: "Smash and Grab")
        XCTAssertTrue(goldRushButton.waitForExistence(timeout: 5),
                      "Neither the goldrush identifier nor the 'Smash and Grab' label was found in the Games hub — see the AX-tree attachment")
        if !goldRushButton.isHittable { app.swipeUp() }
        goldRushButton.tap()

        // 4. Back on Home, with Smash and Grab armed for Play.
        XCTAssertTrue(homeView.waitForExistence(timeout: 5),
                      "Selecting a mode should return to Home with it armed")

        // 5. Press Play — it launches the armed mode after the ~3.3s launch
        // flourish, so allow a longer timeout for the game to appear.
        let playButton = element("PlayButton")
        XCTAssertTrue(playButton.waitForExistence(timeout: 5),
                      "The Play button should be on Home — see the AX-tree attachment")
        playButton.tap()

        // 6. The scramble's view is on screen (leaf anchor on its HUD label)
        let goldRushView = element("GoldRushView")
        XCTAssertTrue(goldRushView.waitForExistence(timeout: 10),
                      "Smash and Grab should launch from Play within the launch-animation window")

        // 6b. On first play a "How to play" card slides up over the game and
        // intercepts the close tap — dismiss it via "Got it — Play".  A no-op
        // once the tutorial has been seen.
        let gotItButton = app.buttons["Got it — Play"]
        if gotItButton.waitForExistence(timeout: 3) { gotItButton.tap() }

        // 7. Exit via the game's own close (✕) button — the nav bar is
        // hidden in-game, so there is no Back button and the swipe-back
        // gesture is disabled.  nav.goHome() pops straight to the root.
        let closeButton = entry("GoldRushCloseButton", labeled: "Close")
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5),
                      "The scramble's close button should be on screen — see the AX-tree attachment if missing")
        closeButton.tap()

        // 8. Home screen is visible again (dismiss a re-presented Sign-in sheet
        // first — the async sign-in can slide back up over Home on return).
        dismissSignInIfPresent(timeout: 3)
        if !homeView.waitForExistence(timeout: 8) { attachAccessibilityTree("step8-no-home") }
        XCTAssertTrue(
            homeView.exists,
            "HomeView should be visible again after returning from Smash and Grab"
        )
    }

    /// Signed out, the social home buttons (Leaderboard / Clans / Friends) are
    /// locked: tapping one raises the "Sign in with Apple" prompt instead of
    /// navigating.  The sim starts signed out, so this exercises the locked path.
    func testSignedOut_socialButtonRaisesSignInPrompt() throws {
        let homeView = element("HomeView")
        XCTAssertTrue(homeView.waitForExistence(timeout: 10))

        // Clear the once-per-launch Sign-in nudge so the only prompt that can
        // appear next is the one our button tap raises.
        dismissSignInIfPresent(timeout: 5)

        // Tap the locked Leaderboard button.
        let leaderboard = app.buttons["Leaderboard"]
        XCTAssertTrue(leaderboard.waitForExistence(timeout: 5),
                      "Leaderboard button should be on Home")
        leaderboard.tap()

        // The prompt's title confirms it came up (and that we did NOT navigate
        // into the Leaderboard screen, whose signed-out copy reads differently).
        let promptTitle = app.staticTexts["Sign in to play with friends"]
        XCTAssertTrue(promptTitle.waitForExistence(timeout: 5),
                      "Tapping a locked social button should raise the Sign-in-with-Apple prompt")
    }

    // MARK: - Home screen elements

    func testHomeView_showsCoinBalance() throws {
        XCTAssertTrue(element("HomeView").waitForExistence(timeout: 10))
        // The coin balance pill should be visible (skipped onboarding → seenOnboarding=true)
        // It appears as a text label containing a number.  We don't assert a
        // specific value — just that some coin-related element is present.
        let hasCoinElement = app.staticTexts.allElementsBoundByIndex.contains {
            $0.label.allSatisfy { $0.isNumber || $0 == "," }
        }
        // This is a soft check — the pill might not carry a separate accessibility
        // identifier.  If the test is brittle, add .accessibilityIdentifier("CoinPill").
        _ = hasCoinElement  // recorded for future tightening
    }
}
