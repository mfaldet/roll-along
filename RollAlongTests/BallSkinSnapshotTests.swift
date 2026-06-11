import XCTest
import SwiftUI
import SnapshotTesting
@testable import RollAlong

// ---------------------------------------------------------------------------
// BallSkinSnapshotTests — pin the *rendered* appearance of cosmetic ball
// skins so a regression in BallSkin's gradient palette (a wrong colour stop,
// a dropped case) is caught visually rather than slipping to the App Store.
//
// FIRST-RUN BEHAVIOUR (important):
//   With no reference images on disk, `assertSnapshot` RECORDS them and the
//   test FAILS by design.  Run once, commit the generated `__Snapshots__/`
//   folder next to this file, then every later run compares against it.
//   To intentionally re-record after a palette change, set
//   `isRecording = true` in setUp (or delete the stale reference images).
//
// REFERENCE ENVIRONMENT: iPhone 16 Pro, iOS 18 (matches SmokeTests).  Pixel
//   output is device/OS/scale dependent — always run snapshots on this one
//   pinned simulator or they will fail spuriously across machines.  A 0.98
//   precision tolerance below absorbs sub-pixel anti-aliasing noise.
// ---------------------------------------------------------------------------

final class BallSkinSnapshotTests: XCTestCase {

    // Flip to true (or delete __Snapshots__) to regenerate references.
    override func setUp() {
        super.setUp()
        // isRecording = true
    }

    /// A BallSkin rendered at a fixed size on a black field, framed with a
    /// little padding so the radial highlight isn't clipped.
    private func host(_ skin: BallSkin, diameter: CGFloat = 120) -> some View {
        BallSkinView(skin: skin, diameter: diameter)
            .frame(width: 140, height: 140)
            .background(Color.black)
    }

    private func assertSkin(_ skin: BallSkin,
                            file: StaticString = #file,
                            testName: String = #function,
                            line: UInt = #line) {
        assertSnapshot(
            of: host(skin),
            as: .image(precision: 0.98, layout: .fixed(width: 140, height: 140)),
            file: file, testName: testName, line: line
        )
    }

    func testRedSkin()   { assertSkin(.red) }
    func testBlueSkin()  { assertSkin(.blue) }
    func testGreenSkin() { assertSkin(.green) }
}
