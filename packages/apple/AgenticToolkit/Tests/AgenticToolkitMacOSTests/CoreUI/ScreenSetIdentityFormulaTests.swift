import XCTest
import AgenticToolkitDisplays
@testable import AgenticToolkitMacOS

/// `ScreenSet.identity(of:)` (persisted window-position keys) and
/// `DisplayChange.setID(of:)` (change classification) implement the same
/// set-id formula in two places. This pins them together on the screens of
/// `ScreenPersistedFormatGoldenTests`, so neither can drift from the other.
/// `ScreenSet.identity` is persisted-format code: if this fails, change
/// `DisplayChange.setID`, never `ScreenSet.identity`.
final class ScreenSetIdentityFormulaTests: XCTestCase {
    /// The three screens of the golden `ScreenSet`: one with a display UUID,
    /// one with only a name, and one with neither.
    private let goldenScreens = [
        ScreenSnapshot(
            fingerprint: ScreenFingerprint(
                displayUUID: "048A89FA-FE44-4BA4-A2DB-5DCF22A949BB", localizedName: "LG UltraFine",
                resolutionWidth: 3840, resolutionHeight: 2160, isMain: true
            ),
            frame: CGRect(x: 0, y: 0, width: 3840, height: 2160),
            visibleFrame: CGRect(x: 0, y: 0, width: 3840, height: 2135),
            backingScaleFactor: 2
        ),
        ScreenSnapshot(
            fingerprint: ScreenFingerprint(
                displayUUID: nil, localizedName: "LG UltraFine-less",
                resolutionWidth: 1920, resolutionHeight: 1080, isMain: false
            ),
            frame: CGRect(x: 3840, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 3840, y: 0, width: 1920, height: 1080),
            backingScaleFactor: 1
        ),
        ScreenSnapshot(
            fingerprint: ScreenFingerprint(
                displayUUID: nil, localizedName: nil, resolutionWidth: 100, resolutionHeight: 100, isMain: false
            ),
            frame: CGRect(x: -100, y: 0, width: 100, height: 100),
            visibleFrame: CGRect(x: -100, y: 0, width: 100, height: 100),
            backingScaleFactor: 1
        )
    ]

    private let goldenID = "048A89FA-FE44-4BA4-A2DB-5DCF22A949BB+LG UltraFine-less+unnamed-display"

    func testScreenSetIdentityMatchesDisplayChangeSetID() {
        XCTAssertEqual(ScreenSet.identity(of: goldenScreens), goldenID)
        XCTAssertEqual(DisplayChange.setID(of: goldenScreens.map(\.geometry)), goldenID)
    }

    func testFormulasAgreeInAnyOrderAndWithDuplicates() {
        let reordered = Array(goldenScreens.reversed()) + [goldenScreens[2]]
        XCTAssertEqual(
            ScreenSet.identity(of: reordered), DisplayChange.setID(of: reordered.map(\.geometry))
        )
    }
}
