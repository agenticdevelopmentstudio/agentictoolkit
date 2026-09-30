import XCTest
@testable import AgenticToolkitMacOS

/// Freezes WindowManager's persisted screen format. If this fails, saved
/// window positions in every app would be orphaned — fix the code, not the test.
final class ScreenPersistedFormatGoldenTests: XCTestCase {
    // Verified byte-for-byte against the pre-migration encoder (commit 23ad69e7)
    // by running this test on the unchanged code; no regeneration was needed.
    // swiftlint:disable line_length
    private let golden = #"""
    {"firstSeen":0,"id":"048A89FA-FE44-4BA4-A2DB-5DCF22A949BB+LG UltraFine-less+unnamed-display","lastSeen":86400,"screens":[{"backingScaleFactor":2,"fingerprint":{"displayUUID":"048A89FA-FE44-4BA4-A2DB-5DCF22A949BB","isMain":true,"localizedName":"LG UltraFine","resolutionHeight":2160,"resolutionWidth":3840},"frame":[[0,0],[3840,2160]],"visibleFrame":[[0,0],[3840,2135]]},{"backingScaleFactor":1,"fingerprint":{"isMain":false,"localizedName":"LG UltraFine-less","resolutionHeight":1080,"resolutionWidth":1920},"frame":[[3840,0],[1920,1080]],"visibleFrame":[[3840,0],[1920,1080]]},{"backingScaleFactor":1,"fingerprint":{"isMain":false,"resolutionHeight":100,"resolutionWidth":100},"frame":[[-100,0],[100,100]],"visibleFrame":[[-100,0],[100,100]]}]}
    """#
    // swiftlint:enable line_length

    func testDecodesAndReencodesIdentically() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let set = try decoder.decode(ScreenSet.self, from: Data(golden.utf8))
        XCTAssertEqual(set.id, ScreenSet.identity(of: set.screens))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        XCTAssertEqual(try XCTUnwrap(String(bytes: try encoder.encode(set), encoding: .utf8)), golden)
    }
}
