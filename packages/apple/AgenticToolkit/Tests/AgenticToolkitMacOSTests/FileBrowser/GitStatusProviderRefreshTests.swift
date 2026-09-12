import AgenticToolkitCore
import XCTest
@testable import AgenticToolkitMacOS

final class GitStatusProviderRefreshTests: XCTestCase {

    /// A result reaches every registered observer, on the main actor, and says
    /// what git said. The provider broadcasts rather than answering whoever
    /// asked — one provider serves every pane of a checkout — so "the observer
    /// heard about it" is the whole contract, not a detail of who called
    /// `refresh()`.
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
        let delivered = expectation(description: "the observer is told")
        // The token *is* the registration: let it go and the observer goes
        // with it, so it is held until the wait returns.
        let observation = provider.observe { result in
            XCTAssertTrue(Thread.isMainThread)
            guard case .status(let status) = result else {
                return XCTFail("git could be asked here, so the result must be a status")
            }
            XCTAssertEqual(status.files["new.txt"], .untracked)
            XCTAssertTrue(status.directories.isEmpty)
            delivered.fulfill()
        }
        provider.refresh()
        wait(for: [delivered], timeout: 10)
        withExtendedLifetime(observation) {}
    }

    /// A failure is reported as `.unavailable`, never as an empty status.
    ///
    /// The two are indistinguishable by the time they reach the file browser:
    /// `FileTreeManager` assigns `node.gitStatus` from the maps it is given and
    /// the outline view draws no badge for `nil`, so answering a failed run
    /// with `.empty` repainted every modified, added and untracked file as
    /// unmodified whenever git was misconfigured or timed out. Saying "we could
    /// not ask" out loud is what lets the consumer leave the last good status
    /// on screen.
    func testAFailedStatusIsReportedAsUnavailableRatherThanAnEmptyStatus() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)")
        let provider = GitStatusProvider(repoRoot: missing, client: GitClient(configuration: .default))
        let delivered = expectation(description: "the observer is told")
        let observation = provider.observe { result in
            guard case .unavailable = result else {
                return XCTFail("a status git could not be asked for is not an empty status")
            }
            delivered.fulfill()
        }
        provider.refresh()
        wait(for: [delivered], timeout: 10)
        withExtendedLifetime(observation) {}
    }

    /// Dropping the token unregisters, which is the reason it is a token at
    /// all: a consumer cannot forget the second half of an
    /// `addObserver`/`removeObserver` pair that does not exist.
    func testDroppingTheObservationStopsDelivery() throws {
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

        let provider = GitStatusProvider(repoRoot: root, client: GitClient(configuration: .default))
        let cancelled = expectation(description: "the dropped observer is not told")
        cancelled.isInverted = true
        do {
            let observation = provider.observe { _ in cancelled.fulfill() }
            withExtendedLifetime(observation) {}
        }
        provider.refresh()
        wait(for: [cancelled], timeout: 3)
    }
}
