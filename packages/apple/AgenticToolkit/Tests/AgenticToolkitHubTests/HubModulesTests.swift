import XCTest
import AgenticToolkitHTDV
@testable import AgenticToolkitHub

@MainActor
final class HubModulesTests: XCTestCase {
    private struct StubEditing: MarkdownEditing {
        @MainActor
        func makeEditor(
            initialText: String, onChange: @escaping @MainActor (String) -> Void
        ) -> PlatformViewController {
            PlatformViewController()
        }

        @MainActor
        func makeViewer(text: String) -> PlatformViewController { PlatformViewController() }
    }

    override func tearDown() async throws {
        HubModules.markdownEditing = PlainTextMarkdownEditing()
        try await super.tearDown()
    }

    func testDefaultIsPlainText() {
        XCTAssertTrue(HubModules.markdownEditing is PlainTextMarkdownEditing)
    }

    func testCanBeReplaced() {
        HubModules.markdownEditing = StubEditing()
        XCTAssertTrue(HubModules.markdownEditing is StubEditing)
    }
}
