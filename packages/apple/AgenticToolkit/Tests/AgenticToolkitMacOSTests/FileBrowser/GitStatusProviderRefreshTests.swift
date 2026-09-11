import AgenticToolkitCore
import XCTest
@testable import AgenticToolkitMacOS

final class GitStatusProviderRefreshTests: XCTestCase {
    func testRefreshDeliversStatusesOnTheMainThread() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("git-status-provider-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["init", "-b", "main"]
        git.currentDirectoryURL = root
        try git.run()
        git.waitUntilExit()
        try "x\n".write(to: root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

        let provider = GitStatusProvider(repoRoot: root, client: GitClient(configuration: .default))
        let delivered = expectation(description: "refresh completes")
        provider.refresh { files, directories in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(files["new.txt"], .untracked)
            XCTAssertTrue(directories.isEmpty)
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 10)
    }

    func testAFailedStatusDeliversNothingRatherThanAnEmptyStatus() {
        // An empty status is indistinguishable from a clean tree by the time
        // it reaches the file browser: `FileTreeManager` assigns
        // `node.gitStatus` from these maps unconditionally and the outline
        // view draws no badge for `nil`. Delivering `.empty` on failure
        // therefore repainted every modified, added and untracked file as
        // unmodified whenever git was misconfigured or timed out. The
        // completion is not called at all now, which leaves the last good
        // status on screen.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)")
        let provider = GitStatusProvider(repoRoot: missing, client: GitClient(configuration: .default))
        let delivered = expectation(description: "refresh completes")
        delivered.isInverted = true
        provider.refresh { _, _ in
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 5)
    }
}
