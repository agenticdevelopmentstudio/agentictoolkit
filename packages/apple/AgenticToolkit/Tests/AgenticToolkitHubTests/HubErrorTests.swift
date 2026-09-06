import XCTest
@testable import AgenticToolkitHub

final class HubErrorTests: XCTestCase {
    func testModuleVersionIsSet() {
        XCTAssertEqual(HubModule.version, "0.1.0")
    }
}
