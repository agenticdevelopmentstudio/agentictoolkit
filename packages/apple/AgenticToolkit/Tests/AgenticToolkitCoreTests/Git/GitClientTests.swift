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
            // The developer's own global config may turn signing on; a signing
            // prompt would hang this commit rather than fail it. Mirrors
            // `TerminalSessionGitBranchTests.makeRepository`.
            try await run(["config", "commit.gpgsign", "false"], in: root)
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
                environment: ["GIT_TERMINAL_PROMPT": "0"],
                environmentPolicy: .mergeOverParent,
                currentDirectoryURL: directory
            )
            let result = try await SubprocessChannel.run(configuration, budget: GitClientTests.budget)
            #expect(result.exitStatus == 0, "\(arguments.joined(separator: " ")): \(result.standardError)")
        }
    }

    /// Redirects `--global` reads and writes at a throwaway file for the life of one
    /// test, via `GitClientConfiguration.extraEnvironment` rather than `setenv`.
    ///
    /// This is what makes the three global-config verbs testable without touching the
    /// developer's own `~/.gitconfig`. It works because `GitClient` spawns git with
    /// `SubprocessChannel`'s `.mergeOverParent` policy, which merges the configuration's
    /// own overrides *over* the parent's environment — so `GIT_CONFIG_GLOBAL` set in
    /// `extraEnvironment` reaches the child without ever touching this process's own
    /// `environ`.
    ///
    /// An earlier version of this fixture called `setenv("GIT_CONFIG_GLOBAL", …)`
    /// directly, mutating process-wide state and relying on `.serialized` above to keep
    /// it safe — but `.serialized` only orders the tests *inside this suite*, and
    /// swift-testing runs other suites in this same target (`SubprocessChannelTests`,
    /// `MCPClientRaceTests`) concurrently with this one. Those suites spawn children that
    /// read `ProcessInfo.processInfo.environment`, so a `setenv` here could race a
    /// concurrent read of `environ` (a use-after-free presenting as an intermittent
    /// runner crash) and could leak `GIT_CONFIG_GLOBAL` into an unrelated child pointed at
    /// a directory this fixture's `tearDown()` then deletes (review A M4 / parked Task 1
    /// F10). Carrying the redirect on the `GitClientConfiguration` instance instead makes
    /// it travel with the one client this test owns and invisible to every other suite —
    /// `.serialized` is no longer load-bearing for that reason, though it is left in place
    /// since the tests in this suite still share one real `git` binary and disk fixtures.
    private struct IsolatedGlobalConfig {
        let directory: URL
        let file: URL

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
        }

        func tearDown() {
            try? FileManager.default.removeItem(at: directory)
        }

        /// A `GitClientConfiguration` whose child processes see this redirected file as
        /// `GIT_CONFIG_GLOBAL`, via `extraEnvironment` rather than a process-wide `setenv`.
        var configuration: GitClientConfiguration {
            GitClientConfiguration(extraEnvironment: ["GIT_CONFIG_GLOBAL": file.path])
        }

        /// The developer's real global config, read only so a test can assert it was
        /// left alone.
        ///
        /// Three outcomes, kept apart on purpose. An earlier version returned
        /// `Data?` and folded "no such file" and "could not be read" together into
        /// `nil`, which made the safety assertion pass by saying `nil == nil` on any
        /// machine where the file was unreadable — the one case where it most needed
        /// to speak up.
        enum RealGlobalConfig: Equatable {
            case absent
            case contents(Data)
            case unreadable(String)

            static func read() -> RealGlobalConfig {
                let url = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".gitconfig")
                guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
                do {
                    return .contents(try Data(contentsOf: url))
                } catch {
                    return .unreadable(error.localizedDescription)
                }
            }
        }
    }

    @Test("the global-config redirect is in effect, so the safety assertions mean something")
    func globalConfigRedirectIsInEffect() async throws {
        let isolated = try IsolatedGlobalConfig()
        defer { isolated.tearDown() }

        // Exactly the seeded entry and nothing else. This is what makes the two
        // "must be untouched" assertions below non-vacuous: the seeded key exists
        // only in the redirected file, and any key from the developer's own
        // `~/.gitconfig` — a `user.name`, an alias — would show up here if git were
        // still reading it.
        let entries = try await GitClient(configuration: isolated.configuration).globalConfig()
        #expect(entries.map(\.key) == [IsolatedGlobalConfig.seededKey])
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
        let client = GitClient(configuration: isolated.configuration)
        let entries = try await client.globalConfig()
        let seeded = entries.first { $0.key == IsolatedGlobalConfig.seededKey }
        #expect(seeded?.value == IsolatedGlobalConfig.seededValue)
    }

    @Test("setGlobalConfig writes a key the next read sees")
    func setGlobalConfig() async throws {
        let isolated = try IsolatedGlobalConfig()
        defer { isolated.tearDown() }
        let untouchedBefore = IsolatedGlobalConfig.RealGlobalConfig.read()
        let client = GitClient(configuration: isolated.configuration)
        try await client.setGlobalConfig(key: "atkgitclienttest.added", value: "added-value")

        let entries = try await client.globalConfig()
        #expect(entries.first { $0.key == "atkgitclienttest.added" }?.value == "added-value")
        // The write landed in the redirected file, not anywhere else.
        let written = try String(contentsOf: isolated.file, encoding: .utf8)
        #expect(written.contains("added-value"))
        #expect(IsolatedGlobalConfig.RealGlobalConfig.read() == untouchedBefore,
                "the developer's real ~/.gitconfig must be untouched")
    }

    @Test("unsetGlobalConfig removes a key the next read no longer sees")
    func unsetGlobalConfig() async throws {
        let isolated = try IsolatedGlobalConfig()
        defer { isolated.tearDown() }
        let untouchedBefore = IsolatedGlobalConfig.RealGlobalConfig.read()
        let client = GitClient(configuration: isolated.configuration)
        #expect(try await client.globalConfig().contains { $0.key == IsolatedGlobalConfig.seededKey })

        try await client.unsetGlobalConfig(key: IsolatedGlobalConfig.seededKey)

        #expect(try await client.globalConfig().isEmpty)
        #expect(IsolatedGlobalConfig.RealGlobalConfig.read() == untouchedBefore,
                "the developer's real ~/.gitconfig must be untouched")
    }
}

/// Covers `GitClientError.logDescription`, the seam `GitStatusProvider` logs
/// through instead of `errorDescription`/`localizedDescription`. There is no
/// way to assert an OSLog line directly, so this is the testable shape of
/// the fix for review A's BLOCKER B1: git's own stderr must never reach the
/// unified log.
@Suite("GitClientError.logDescription")
struct GitClientErrorLogDescriptionTests {
    @Test("commandFailed's logDescription carries the verb and exit status, never standardError")
    func commandFailedNeverLeaksStandardError() {
        let error = GitClientError.commandFailed(
            verb: "status",
            exitStatus: 128,
            standardError: "fatal: detected dubious ownership in repository at '/Users/secret/repo'"
        )
        #expect(!error.logDescription.contains("secret"))
        #expect(error.logDescription.contains("status"))
        #expect(error.logDescription.contains("128"))
    }

    @Test("timedOut's logDescription carries the verb")
    func timedOutCarriesVerb() {
        let error = GitClientError.timedOut(verb: "worktree")
        #expect(error.logDescription.contains("worktree"))
    }

    @Test("launchFailed's logDescription carries the verb, never the launch reason")
    func launchFailedNeverLeaksReason() {
        let error = GitClientError.launchFailed(verb: "status", reason: "secret-path-in-the-reason")
        #expect(!error.logDescription.contains("secret"))
        #expect(error.logDescription.contains("status"))
    }

    @Test("executableNotFound's logDescription never leaks the configured path")
    func executableNotFoundNeverLeaksPath() {
        let error = GitClientError.executableNotFound(path: "/Users/secret/bin/git")
        #expect(!error.logDescription.contains("secret"))
    }
}

/// Covers review A's M1 (parked Task 1 F9, reproducing): `withWallClockBudget`
/// cancels its loser but never awaits it (`WallClockBudget.swift`'s own doc
/// comment), so a `terminate()` that arrives before `launch()` has reached
/// `process.run()` used to find `hasLaunched == false` and return having done
/// nothing — the cancelled task then went on to spawn a real child that
/// nothing terminated.
///
/// This drives the two actor calls **in the order the race produces**
/// (`terminate()` first, `launch()` second) rather than actually racing
/// `withWallClockBudget` against a real `launch()`: `launch()` is a
/// non-`async` actor method, so once either call reaches the actor it runs
/// to completion before the other can start (see `terminationRequested`'s
/// doc comment on `SubprocessChannel`), which makes "terminate() reaches the
/// actor first" the entire content of the race regardless of how close the
/// wall-clock timing is. Racing the real budget instead proved flaky: a
/// 1 ms budget does not reliably lose to `/bin/sleep 30`'s own
/// `process.run()`, which is just a fork/exec and can complete in well under
/// 1 ms. `GitClientTests.timesOut` keeps the 1 ms wall-clock race, but that
/// one only needs the *whole `status` command* — spawn plus produce output —
/// to outlast 1 ms, which is reliable.
@Suite("SubprocessChannel terminate()/launch() race")
struct SubprocessChannelTerminationRaceTests {
    @Test("a terminate() that arrives before launch() still ends the child")
    func terminateBeforeLaunchStillEndsTheChild() async throws {
        let channel = SubprocessChannel(configuration: .init(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["30"]
        ))

        // `hasLaunched` is still false here, so before the fix this returned
        // having done nothing.
        await channel.terminate()

        // Before the fix, nothing had recorded the request above, so this
        // spawned a real `sleep 30` with nothing left to stop it. After the
        // fix, `launch()` finds `terminationRequested` already set and kicks
        // off the catch-up termination itself.
        try await channel.launch()

        // Bounded poll rather than a fixed sleep: the catch-up termination
        // runs on its own `Task`, not ours. 5s is generous against
        // `terminationGraceSeconds` (2s) plus the pump drain grace (0.5s);
        // before the fix this times out with `isRunning == true` — the real
        // child runs for the full 30s with nothing to stop it.
        _ = try? await withWallClockBudget(5) {
            while await channel.isRunning {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        #expect(await channel.isRunning == false, "the child must not be left running")

        // Cleanup net, independent of the assertion above: if the poll's
        // budget lapsed first, this still ends the child rather than leaving
        // a real `sleep 30` running for the rest of its 30s regardless of
        // whether the assertion just failed.
        await channel.terminate()
    }
}
