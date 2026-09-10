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

    func testAFailedStatusDeliversEmptyStatuses() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)")
        let provider = GitStatusProvider(repoRoot: missing, client: GitClient(configuration: .default))
        let delivered = expectation(description: "refresh completes")
        provider.refresh { files, directories in
            XCTAssertTrue(files.isEmpty)
            XCTAssertTrue(directories.isEmpty)
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 10)
    }
}
