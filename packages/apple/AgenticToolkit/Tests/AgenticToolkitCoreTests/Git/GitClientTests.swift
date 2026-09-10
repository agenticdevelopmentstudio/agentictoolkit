import Foundation
import Testing
@testable import AgenticToolkitCore

@Suite("GitClient", .serialized)
struct GitClientTests {
    private static let budget: TimeInterval = 10

    /// A fresh repository with one commit on `main`, one worktree on `feature`, and a modified file.
    private struct Fixture {
        let root: URL
        let worktree: URL

        static func make() async throws -> Fixture {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("git-client-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try await run(["init", "-b", "main"], in: root)
            try await run(["config", "user.email", "test@example.com"], in: root)
            try await run(["config", "user.name", "Test"], in: root)
            try "one\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
            try await run(["add", "a.txt"], in: root)
            try await run(["commit", "-m", "initial"], in: root)
            let worktree = root.appendingPathComponent("wt-feature")
            try await run(["worktree", "add", "-b", "feature", worktree.path], in: root)
            try "two\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
            return Fixture(root: root, worktree: worktree)
        }

        func tearDown() {
            try? FileManager.default.removeItem(at: root)
        }

        /// Drives the system binary directly, so the fixture never depends on the
        /// type under test. Only ever pointed at a throwaway directory this suite made.
        private static func run(_ arguments: [String], in directory: URL) async throws {
            let configuration = SubprocessChannel.Configuration(
                executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: arguments,
                environmentPolicy: .mergeOverParent,
                currentDirectoryURL: directory
            )
            let result = try await SubprocessChannel.run(configuration, budget: GitClientTests.budget)
            #expect(result.exitStatus == 0, "\(arguments.joined(separator: " ")): \(result.standardError)")
        }
    }

    /// Redirects `--global` reads and writes at a throwaway file for the life of one
    /// test, by setting `GIT_CONFIG_GLOBAL` in this process's environment.
    ///
    /// This is what makes the three global-config verbs testable without touching the
    /// developer's own `~/.gitconfig`. It works because `GitClient` spawns git with
    /// `SubprocessChannel`'s `.mergeOverParent` policy, which merges the client's own
    /// overrides *over* `ProcessInfo.processInfo.environment` — so a variable set here
    /// reaches the child. `ProcessInfo` reads `environ` afresh on every access, so
    /// `setenv` after launch is visible.
    ///
    /// The suite is `.serialized` because that environment is process-wide.
    private struct IsolatedGlobalConfig {
        let directory: URL
        let file: URL
        private let previousValue: String?

        /// Seeds the redirected file with one entry, so a read test does not depend on
        /// a write test having run first.
        static let seededKey = "atkgitclienttest.seeded"
        static let seededValue = "seeded-value"

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("git-client-global-config-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            file = directory.appendingPathComponent("config")
            try "[atkgitclienttest]\n\tseeded = \(Self.seededValue)\n"
                .write(to: file, atomically: true, encoding: .utf8)
            previousValue = ProcessInfo.processInfo.environment["GIT_CONFIG_GLOBAL"]
            setenv("GIT_CONFIG_GLOBAL", file.path, 1)
        }

        func tearDown() {
            if let previousValue {
                setenv("GIT_CONFIG_GLOBAL", previousValue, 1)
            } else {
                unsetenv("GIT_CONFIG_GLOBAL")
            }
            try? FileManager.default.removeItem(at: directory)
        }

        /// The developer's real global config, read only so a test can assert it was
        /// left byte-for-byte alone.
        static func realGlobalConfigBytes() -> Data? {
            try? Data(contentsOf: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".gitconfig"))
        }
    }

    @Test("status reports the modified file")
    func status() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.tearDown() }
        let client = GitClient(configuration: .default)
        let status = try await client.status(in: fixture.root)
        #expect(status.files["a.txt"] == .modified)
    }

    @Test("currentBranch names the checked-out branch")
    func currentBranch() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.tearDown() }
        let client = GitClient(configuration: .default)
        #expect(try await client.currentBranch(in: fixture.root) == "main")
        #expect(try await client.currentBranch(in: fixture.worktree) == "feature")
    }

    @Test("branches lists both branches and marks the current one")
    func branches() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.tearDown() }
        let client = GitClient(configuration: .default)
        let branches = try await client.branches(in: fixture.root)
        #expect(Set(branches.map(\.name)) == ["main", "feature"])
        #expect(branches.first { $0.name == "main" }?.isCurrent == true)
    }

    @Test("worktrees lists the main checkout first, then the worktree")
    func worktrees() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.tearDown() }
        let client = GitClient(configuration: .default)
        let trees = try await client.worktrees(in: fixture.root)
        #expect(trees.count == 2)
        #expect(trees[0].isMain)
        #expect(trees[0].branch == "main")
        #expect(trees[1].branch == "feature")
        #expect(trees[1].directory.resolvingSymlinksInPath().path
            == fixture.worktree.resolvingSymlinksInPath().path)
    }

    @Test("a missing executable throws executableNotFound before spawning")
    func missingExecutable() async {
        let configuration = GitClientConfiguration(executableURL: URL(fileURLWithPath: "/nonexistent/git"))
        let client = GitClient(configuration: configuration)
        await #expect(throws: GitClientError.executableNotFound(path: "/nonexistent/git")) {
            try await client.currentBranch(in: URL(fileURLWithPath: "/"))
        }
    }

    @Test("a failing command throws commandFailed with the verb and status")
    func commandFailed() async {
        let notARepo = FileManager.default.temporaryDirectory
        let client = GitClient(configuration: .default)
        await #expect(throws: GitClientError.self) {
            try await client.status(in: notARepo.appendingPathComponent("does-not-exist-\(UUID().uuidString)"))
        }
    }

    @Test("a timeout throws timedOut")
    func timesOut() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.tearDown() }
        // A one-millisecond budget: the process cannot finish in time.
        let client = GitClient(configuration: GitClientConfiguration(timeout: 0.001))
        await #expect(throws: GitClientError.timedOut(verb: "status")) {
            try await client.status(in: fixture.root)
        }
    }

    @Test("globalConfig reads the redirected global file")
    func globalConfig() async throws {
        let isolated = try IsolatedGlobalConfig()
        defer { isolated.tearDown() }
        let client = GitClient(configuration: .default)
        let entries = try await client.globalConfig()
        let seeded = entries.first { $0.key == IsolatedGlobalConfig.seededKey }
        #expect(seeded?.value == IsolatedGlobalConfig.seededValue)
    }

    @Test("setGlobalConfig writes a key the next read sees")
    func setGlobalConfig() async throws {
        let isolated = try IsolatedGlobalConfig()
        defer { isolated.tearDown() }
        let untouchedBefore = IsolatedGlobalConfig.realGlobalConfigBytes()
        let client = GitClient(configuration: .default)
        try await client.setGlobalConfig(key: "atkgitclienttest.added", value: "added-value")

        let entries = try await client.globalConfig()
        #expect(entries.first { $0.key == "atkgitclienttest.added" }?.value == "added-value")
        // The write landed in the redirected file, not anywhere else.
        let written = try String(contentsOf: isolated.file, encoding: .utf8)
        #expect(written.contains("added-value"))
        #expect(IsolatedGlobalConfig.realGlobalConfigBytes() == untouchedBefore,
                "the developer's real ~/.gitconfig must be untouched")
    }

    @Test("unsetGlobalConfig removes a key the next read no longer sees")
    func unsetGlobalConfig() async throws {
        let isolated = try IsolatedGlobalConfig()
        defer { isolated.tearDown() }
        let untouchedBefore = IsolatedGlobalConfig.realGlobalConfigBytes()
        let client = GitClient(configuration: .default)
        #expect(try await client.globalConfig().contains { $0.key == IsolatedGlobalConfig.seededKey })

        try await client.unsetGlobalConfig(key: IsolatedGlobalConfig.seededKey)

        #expect(try await client.globalConfig().isEmpty)
        #expect(IsolatedGlobalConfig.realGlobalConfigBytes() == untouchedBefore,
                "the developer's real ~/.gitconfig must be untouched")
    }
}
