import XCTest
@testable import AgenticToolkitDatabase

final class AppStorageLocationTests: XCTestCase {

    func testStripsSpacesFromADisplayName() {
        XCTAssertEqual(AppStorageLocation.token(for: "Kitchen IDE"), "KitchenIDE")
    }

    func testLeavesASingleWordNameAlone() {
        XCTAssertEqual(AppStorageLocation.token(for: "Whippet"), "Whippet")
    }

    func testStripsPunctuationAndPathSeparators() {
        XCTAssertEqual(AppStorageLocation.token(for: "Kitchen/IDE 2.0"), "KitchenIDE20")
    }

    func testFallsBackWhenNothingUsableSurvives() {
        XCTAssertEqual(AppStorageLocation.token(for: "   "), "AgenticToolkit")
    }

    func testDirectoryIsTheLowercasedTokenAsADotfolder() {
        let home = URL(fileURLWithPath: "/tmp/home")
        XCTAssertEqual(
            AppStorageLocation.directory(inHome: home, token: "KitchenIDE").path,
            "/tmp/home/.kitchenide")
    }
}
