import AgenticToolkitCore
import AgenticToolkitLanguage
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

    /// The provider is scoped to the root it names — a multi-root browser must
    /// not paint one worktree's git status onto another's files. This exercises
    /// the actual matching logic in `FileBrowserViewController.makeManager(for:)`,
    /// which neither test above reaches: both construct `FileTreeManager`
    /// directly with the provider's `repoRoot` already equal to the manager's
    /// own root, so an always-true or inverted predicate would still pass them.
    func testAnInjectedProviderIsScopedToItsOwnRootInAMultiRootBrowser() {
        let rootA = FileManager.default.temporaryDirectory.appendingPathComponent("ftm-a-\(UUID().uuidString)")
        let rootB = FileManager.default.temporaryDirectory.appendingPathComponent("ftm-b-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let provider = GitStatusProvider(repoRoot: rootB)
        let browser = FileBrowserViewController(
            directories: FileBrowserDirectories(primary: rootA, additional: [rootB]),
            excludedURL: rootA.appendingPathComponent(".build"),
            documentStore: TextDocumentStore(),
            gitStatusProvider: provider
        )

        // `FileBrowserDirectories.init` standardizes every root it stores, so
        // `managersByRoot`'s keys are standardized too.
        guard let managerB = browser.managersByRoot[rootB.standardizedFileURL] else {
            return XCTFail("expected a manager for rootB")
        }
        XCTAssertTrue(managerB.gitStatusProvider === provider, "the matching root must use the injected provider")

        guard let managerA = browser.managersByRoot[rootA.standardizedFileURL] else {
            return XCTFail("expected a manager for rootA")
        }
        XCTAssertFalse(
            managerA.gitStatusProvider === provider,
            "a non-matching root must not receive the injected provider"
        )
        XCTAssertEqual(
            managerA.gitStatusProvider.repoRoot.path,
            rootA.path,
            "a non-matching root builds its own provider"
        )
    }
}
