import AgenticToolkitCore
import Combine
import XCTest
@testable import AgenticToolkitMacOS

/// Covers what `TerminalSession.detectGitBranch` publishes, which is what the
/// terminal tab's title reads: `folder: branch` when `gitBranch` is set, and
/// bare `folder` when it is not (`TerminalSession.displayTitle`).
///
/// The detached case is the one worth pinning. `GitClient.currentBranch`
/// answers `nil` there — correct for an API asked "which branch?" — and a
/// straight pass-through would silently turn `~/repo: HEAD` into `~/repo`,
/// taking away the only signal the user has that they are not on a branch.
///
/// `TerminalSession.terminalView` is `lazy`, so constructing a session here
/// starts no shell.
@MainActor
final class TerminalSessionGitBranchTests: XCTestCase {
    func testACheckedOutBranchIsPublishedByName() async throws {
        let repo = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let branch = try await detectedBranch(in: repo.path)
        XCTAssertEqual(branch, "main")
    }

    func testADetachedHeadIsPublishedAsHEAD() async throws {
        let repo = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        try run(["checkout", "--detach"], in: repo)
        let branch = try await detectedBranch(in: repo.path)
        XCTAssertEqual(branch, "HEAD", "a detached checkout must still render as 'folder: HEAD'")
    }

    func testADirectoryThatIsNotARepositoryPublishesNil() async throws {
        let plain = FileManager.default.temporaryDirectory
            .appendingPathComponent("terminal-session-plain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plain) }
        let branch = try await detectedBranch(in: plain.path)
        XCTAssertNil(branch)
    }

    // MARK: - Helpers

    /// Runs one detection and returns the first value `gitBranch` publishes.
    private func detectedBranch(in directory: String) async throws -> String? {
        let session = TerminalSession(
            name: "test",
            workingDirectory: directory,
            gitClient: GitClient(configuration: .default)
        )
        let published = expectation(description: "gitBranch is published")
        var observed: String?
        let cancellable = session.$gitBranch
            .dropFirst()
            .sink { value in
                observed = value
                published.fulfill()
            }
        session.detectGitBranch(for: directory)
        await fulfillment(of: [published], timeout: 10)
        cancellable.cancel()
        return observed
    }

    /// A throwaway repository with one commit on `main`.
    private func makeRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("terminal-session-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try run(["init", "-b", "main"], in: root)
        try run(["config", "user.email", "test@example.com"], in: root)
        try run(["config", "user.name", "Test"], in: root)
        // The developer's own global config may turn signing on; a signing
        // prompt would hang this commit rather than fail it.
        try run(["config", "commit.gpgsign", "false"], in: root)
        try "one\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try run(["add", "a.txt"], in: root)
        try run(["commit", "-m", "initial"], in: root)
        return root
    }

    /// Drives the system binary directly, so the fixture never depends on the
    /// type under test. Only ever pointed at a throwaway directory this suite made.
    private func run(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, arguments.joined(separator: " "))
    }
}
