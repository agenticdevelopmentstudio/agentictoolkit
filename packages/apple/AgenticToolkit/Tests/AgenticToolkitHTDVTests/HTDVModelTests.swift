import XCTest
@testable import AgenticToolkitHTDV

final class HTDVModelTests: XCTestCase {
    func testModuleVersionIsSet() {
        XCTAssertEqual(HTDVModule.version, "0.1.0")
    }
}
