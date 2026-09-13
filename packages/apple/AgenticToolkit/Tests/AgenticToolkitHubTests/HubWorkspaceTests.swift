import XCTest
@testable import AgenticToolkitHub

final class HubWorkspaceTests: XCTestCase {
    func testIdentityAndLabel() {
        let workspace = HubWorkspace(slug: "acme", name: "Acme Inc", type: .organization)
        XCTAssertEqual(workspace.id, "acme")
        XCTAssertEqual(workspace.listLabel, "Acme Inc (acme)")
        XCTAssertEqual(workspace, HubWorkspace(slug: "acme", name: "Acme Inc", type: .organization))
    }

    func testCodableRoundTripUsesRawTypeValues() throws {
        let workspace = HubWorkspace(slug: "core", name: "Core Team", type: .team)
        let data = try JSONEncoder().encode(workspace)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"type\":\"team\""), json)
        XCTAssertEqual(try JSONDecoder().decode(HubWorkspace.self, from: data), workspace)
    }
}
