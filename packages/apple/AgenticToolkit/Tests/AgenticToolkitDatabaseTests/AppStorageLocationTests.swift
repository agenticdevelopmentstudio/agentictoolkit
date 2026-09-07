import XCTest
@testable import AgenticToolkitDatabase

final class AppStorageLocationTests: XCTestCase {

    func testStripsSpacesFromADisplayName() {
        XCTAssertEqual(AppStorageLocation.token(for: "Coffee Grinder"), "CoffeeGrinder")
    }

    func testLeavesASingleWordNameAlone() {
        XCTAssertEqual(AppStorageLocation.token(for: "Whippet"), "Whippet")
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
}
