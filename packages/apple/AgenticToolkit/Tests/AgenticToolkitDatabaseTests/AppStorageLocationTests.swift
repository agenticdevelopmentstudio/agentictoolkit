import XCTest
@testable import AgenticToolkitDatabase

final class AppStorageLocationTests: XCTestCase {

    func testStripsSpacesFromADisplayName() {
        XCTAssertEqual(AppStorageLocation.token(for: "Coffee Grinder"), "CoffeeGrinder")
    }

    func testLeavesASingleWordNameAlone() {
        XCTAssertEqual(AppStorageLocation.token(for: "Percolator"), "Percolator")
    }

    func testStripsPunctuationAndPathSeparators() {
        XCTAssertEqual(AppStorageLocation.token(for: "Coffee/Grinder 2.0"), "CoffeeGrinder20")
    }

    func testFallsBackWhenNothingUsableSurvives() {
        XCTAssertEqual(AppStorageLocation.token(for: "   "), "AgenticToolkit")
    }

    func testDirectoryIsTheLowercasedTokenAsADotfolder() {
        let home = URL(fileURLWithPath: "/tmp/home")
        XCTAssertEqual(
            AppStorageLocation.directory(inHome: home, token: "CoffeeGrinder").path,
            "/tmp/home/.coffeegrinder")
    }

    /// Capitalization in a display name is cosmetic, so it must not move the
    /// store. This is the property that makes it safe for the files inside the
    /// directory to be named for their contents rather than for the app.
    func testDirectoryIgnoresTheCaseOfTheToken() {
        let home = URL(fileURLWithPath: "/tmp/home")
        XCTAssertEqual(
            AppStorageLocation.directory(inHome: home, token: "COFFEEgrinder").path,
            AppStorageLocation.directory(inHome: home, token: "CoffeeGrinder").path)
    }
}
