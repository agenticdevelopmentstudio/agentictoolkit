import AgenticToolkitCore
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class FileTreeManagerInjectedProviderTests: XCTestCase {
    func testAnInjectedProviderIsUsedInsteadOfANewOne() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ftm-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = GitStatusProvider(repoRoot: root)
        let manager = FileTreeManager(
            repoRootURL: root,
            packageURL: root.appendingPathComponent(".build"),
            config: .default,
            gitStatusProvider: provider
        )
        XCTAssertTrue(manager.gitStatusProvider === provider)
    }

    func testWithoutAnInjectedProviderTheManagerBuildsItsOwn() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ftm-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = FileTreeManager(
            repoRootURL: root,
            packageURL: root.appendingPathComponent(".build"),
            config: .default
        )
        XCTAssertEqual(manager.gitStatusProvider.repoRoot.path, root.path)
    }
}
