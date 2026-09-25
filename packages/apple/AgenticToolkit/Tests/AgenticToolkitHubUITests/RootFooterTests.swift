import AgenticDeveloperHubClient
import AgenticToolkitHubService
import AppKit
import XCTest
@testable import AgenticToolkitHubUI

/// Review focus 4: the status footer replaces the hand-built strip, and with
/// no message it is hidden and reported as absent — not as an empty string a
/// script would read as "the strip says nothing".
@MainActor
final class RootFooterTests: XCTestCase {

    func testFooterHasTheSharedIdentifierAndStartsHidden() async throws {
        let composition = await HubAppComposition.macOS(sessionStore: InMemorySessionStore())
        let root = RootViewController(composition: composition)
        _ = root.view
        let label = try XCTUnwrap(Self.find("root.footer.status", in: root.view))
        XCTAssertTrue(label.isHiddenOrHasHiddenAncestor)
        XCTAssertNil(root.scriptStatusStripMessage)
    }

    private static func find(_ identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        for subview in view.subviews {
            if let found = find(identifier, in: subview) { return found }
        }
        return nil
    }
}
