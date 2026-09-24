import XCTest
@testable import AgenticToolkitCore

/// Moved from `SessionEnricherTests`, whose copies stay and now test the
/// daemon's forward. These make the toolkit's own suite prove the toolkit's
/// own code.
final class GitProjectRootTests: XCTestCase {

    private var cleanup: [String] = []

    override func tearDown() {
        for path in cleanup { try? FileManager.default.removeItem(atPath: path) }
        cleanup = []
    }

    private func makeTempDir(_ label: String) throws -> String {
        let path = NSTemporaryDirectory() + "git-project-root-\(label)-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        cleanup.append(path)
        return path
    }

    @discardableResult
    private func git(_ args: [String], in dir: String) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", dir] + args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func initRepo(_ dir: String) throws {
        try XCTSkipIf(git(["init", "-q"], in: dir).status != 0, "git unavailable")
        git(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init"],
            in: dir)
    }

    /// `/var` and `/private/var` are one directory; compare the last component.
    private func dirName(_ path: String) -> String { (path as NSString).lastPathComponent }

    func testAPlainDirectoryIsNotAWorkingTree() throws {
        XCTAssertEqual(GitProjectRoot.resolve(at: try makeTempDir("plain")), .notAGitWorkingTree)
        XCTAssertEqual(GitProjectRoot.resolve(at: ""), .notAGitWorkingTree)
    }

    func testASubdirectoryResolvesToItsRepository() throws {
        let repo = try makeTempDir("repo")
        try initRepo(repo)
        let deep = repo + "/Sources/Deep"
        try FileManager.default.createDirectory(atPath: deep, withIntermediateDirectories: true)

        XCTAssertEqual(GitProjectRoot.root(at: deep).map(dirName), dirName(repo))
    }

    func testALinkedWorktreeCollapsesToTheMainWorkingTree() throws {
        let repo = try makeTempDir("main")
        try initRepo(repo)
        let worktree = try makeTempDir("wt-parent") + "/wt"
        let add = git(["worktree", "add", "-b", "resolution", worktree], in: repo)
        try XCTSkipIf(add.status != 0, "git worktree add unavailable: \(add.output)")

        guard case .resolved(let root) = GitProjectRoot.resolve(at: worktree) else {
            return XCTFail("a linked worktree must resolve")
        }
        XCTAssertEqual(dirName(root), dirName(repo))
    }

    func testAMissingDirectoryIsUndetermined() {
        XCTAssertEqual(GitProjectRoot.resolve(at: "/no/such/dir-\(UUID().uuidString)"), .undetermined)
    }
}
