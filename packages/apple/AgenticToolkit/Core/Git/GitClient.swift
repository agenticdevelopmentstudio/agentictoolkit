import Foundation

/// The toolkit's only door to git.
///
/// Every verb goes through `execute`, which resolves the configuration, spawns
/// the process with `SubprocessChannel.run`, records the invocation in
/// `GitCommandLog`, and maps every failure onto `GitClientError`. Nothing else
/// in the toolkit or in the app may spawn git directly: one door is what makes
/// git usage — by the app and by agents driving it — countable, attributable
/// and bounded by a single timeout.
///
/// **"Bottleneck" is about accounting, not about serialization.** This actor
/// holds no isolated mutable state, and every verb suspends at
/// `await SubprocessChannel.run`, which releases the actor for the whole
/// lifetime of the child. Ten concurrent callers therefore run ten concurrent
/// git processes, not one at a time — intentionally, since a `status` on one
/// repository has no reason to wait behind a `worktree list` on another. If a
/// limit is ever wanted, this is where it goes.
///
/// An actor rather than a struct so the door is a single, identifiable place at
/// runtime as well as in the source, and so later work (rate limiting, caching,
/// an in-memory ring of recent invocations) has somewhere to live that does not
/// change any caller.
public actor GitClient {
    /// The process-wide client; reads its configuration from `UserSettings` on
    /// every call, so a settings change takes effect on the next invocation
    /// without anything having to be rebuilt or re-injected.
    public static let shared = GitClient(configuration: { await GitClientConfiguration.fromSettings() })

    /// Where the `--global` config verbs start the process.
    ///
    /// `git config --global` neither discovers nor reads a repository, so this
    /// is only somewhere for the child to stand; it is never a repository this
    /// client touches. Home is used rather than a scratch path so the call is
    /// legible in the log.
    private static let homeDirectory = FileManager.default.homeDirectoryForCurrentUser

    /// Resolved on every call rather than captured once, so `shared` follows
    /// the user's settings.
    private let configurationProvider: @Sendable () async -> GitClientConfiguration

    public init(configuration provider: @escaping @Sendable () async -> GitClientConfiguration) {
        self.configurationProvider = provider
    }

    public init(configuration: GitClientConfiguration) {
        self.configurationProvider = { configuration }
    }

    // MARK: - Read-only verbs

    /// The working tree's status, as `git status --porcelain=v1 -uall` reports it.
    public func status(in directory: URL, caller: GitCaller = GitCaller()) async throws -> GitStatus {
        let configuration = await configurationProvider()
        var arguments = ["--porcelain=v1", "-uall"]
        if configuration.submoduleHandling == .ignore {
            arguments.append("--ignore-submodules")
        }
        let output = try await execute(
            verb: "status",
            arguments: arguments,
            directory: directory,
            caller: caller,
            configuration: configuration
        )
        return GitStatus.parse(porcelain: output)
    }

    /// The short name of HEAD's branch, or `nil` when HEAD is detached.
    public func currentBranch(in directory: URL, caller: GitCaller = GitCaller()) async throws -> String? {
        let output = try await execute(
            verb: "rev-parse",
            arguments: ["--abbrev-ref", "HEAD"],
            directory: directory,
            caller: caller,
            configuration: await configurationProvider()
        )
        let name = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == "HEAD" ? nil : name
    }

    /// Every local branch, in `git for-each-ref` order.
    public func branches(in directory: URL, caller: GitCaller = GitCaller()) async throws -> [GitBranch] {
        let output = try await execute(
            verb: "for-each-ref",
            arguments: ["--format=\(GitBranch.forEachRefFormat)", "refs/heads"],
            directory: directory,
            caller: caller,
            configuration: await configurationProvider()
        )
        return GitBranch.parse(forEachRef: output)
    }

    /// Every worktree of the repository containing `directory`, main one first.
    public func worktrees(in directory: URL, caller: GitCaller = GitCaller()) async throws -> [GitWorktree] {
        let output = try await execute(
            verb: "worktree",
            arguments: ["list", "--porcelain"],
            directory: directory,
            caller: caller,
            configuration: await configurationProvider()
        )
        return GitWorktree.parse(porcelain: output)
    }

    // MARK: - Global configuration

    /// Everything in the user's global git configuration.
    public func globalConfig(caller: GitCaller = GitCaller()) async throws -> [GitConfigEntry] {
        let output = try await execute(
            verb: "config",
            arguments: ["--global", "--list", "--null"],
            directory: Self.homeDirectory,
            caller: caller,
            configuration: await configurationProvider()
        )
        return GitConfigEntry.parse(nullSeparated: output)
    }

    /// Sets one key in the user's global git configuration. The value is
    /// redacted in `GitCommandLog`; see `GitCommandLog.redactedArguments`.
    public func setGlobalConfig(key: String, value: String, caller: GitCaller = GitCaller()) async throws {
        _ = try await execute(
            verb: "config",
            arguments: ["--global", key, value],
            directory: Self.homeDirectory,
            caller: caller,
            configuration: await configurationProvider()
        )
    }

    /// Removes one key from the user's global git configuration. Throws
    /// `.commandFailed` (git's exit status 5) when the key was not set.
    public func unsetGlobalConfig(key: String, caller: GitCaller = GitCaller()) async throws {
        _ = try await execute(
            verb: "config",
            arguments: ["--global", "--unset", key],
            directory: Self.homeDirectory,
            caller: caller,
            configuration: await configurationProvider()
        )
    }

    // MARK: - The bottleneck

    /// The single place this framework spawns git.
    ///
    /// Every exit is recorded in `GitCommandLog` before it becomes a return
    /// value or an error, so the log is a complete census of *attempts* rather
    /// than of successes — a missing executable and a cancelled caller each
    /// leave a record, which is the state of affairs someone reading the log is
    /// most likely trying to explain.
    ///
    /// The failure mapping is **total, by construction**: the `do` block ends
    /// in an unqualified `catch`, so no error can leave this method unrecorded
    /// or as a type outside `GitClientError`. Enumerating error types is what
    /// leaves gaps — `SubprocessChannel` can finish its stdout stream with a
    /// raw POSIX `NSError`, and its decoder with a `MessageFramingError`, and
    /// neither is anything a caller of `status(in:)` should have to know about.
    ///
    /// **`CancellationError` is the one exception, and it is deliberate.** It
    /// is recorded and then rethrown *unchanged*, because a cancelled task must
    /// keep seeing cancellation: wrapping it would break `Task.isCancelled`
    /// propagation and structured-concurrency cleanup for every caller,
    /// starting with a SwiftUI `.task` that is torn down while a `status` is in
    /// flight. It is therefore possible for a `GitClient` verb to throw
    /// something that is not a `GitClientError`, and only this.
    private func execute(
        verb: String,
        arguments: [String],
        directory: URL,
        caller: GitCaller,
        configuration: GitClientConfiguration
    ) async throws -> String {
        let executablePath = configuration.executableURL.path
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            // Recorded even though nothing was spawned. A user who types a
            // wrong path into Settings makes every git call fail here, and an
            // empty log is the least useful thing to hand them.
            GitCommandLog.record(verb: verb, arguments: arguments, directory: directory, caller: caller,
                                 duration: 0, exitStatus: nil)
            throw GitClientError.executableNotFound(path: executablePath)
        }
        let channelConfiguration = SubprocessChannel.Configuration(
            executableURL: configuration.executableURL,
            arguments: [verb] + arguments,
            // A non-empty environment is what makes `.mergeOverParent` merge
            // rather than inherit wholesale; git needs PATH and HOME, and this
            // one override stops a credential prompt from hanging the child
            // forever behind a terminal nobody is watching. `extraEnvironment`
            // merges on top so a caller (a test redirecting
            // `GIT_CONFIG_GLOBAL`, say) can add overrides of its own without
            // touching process-wide state — see
            // `GitClientConfiguration.extraEnvironment`.
            environment: ["GIT_TERMINAL_PROMPT": "0"]
                .merging(configuration.extraEnvironment) { _, override in override },
            environmentPolicy: .mergeOverParent,
            currentDirectoryURL: directory
        )
        let started = Date()
        let result: SubprocessChannel.RunResult
        do {
            result = try await SubprocessChannel.run(channelConfiguration, budget: configuration.timeout)
        } catch is WallClockBudgetExceeded {
            GitCommandLog.record(
                verb: verb, arguments: arguments, directory: directory, caller: caller,
                duration: Date().timeIntervalSince(started), exitStatus: nil
            )
            throw GitClientError.timedOut(verb: verb)
        } catch let error as CancellationError {
            GitCommandLog.record(
                verb: verb, arguments: arguments, directory: directory, caller: caller,
                duration: Date().timeIntervalSince(started), exitStatus: nil
            )
            throw error
        } catch {
            GitCommandLog.record(
                verb: verb, arguments: arguments, directory: directory, caller: caller,
                duration: Date().timeIntervalSince(started), exitStatus: nil
            )
            throw GitClientError.launchFailed(verb: verb, reason: error.localizedDescription)
        }
        GitCommandLog.record(
            verb: verb, arguments: arguments, directory: directory, caller: caller,
            duration: result.duration, exitStatus: result.exitStatus
        )
        guard result.exitStatus == 0 else {
            throw GitClientError.commandFailed(
                verb: verb,
                exitStatus: result.exitStatus,
                standardError: result.standardError
            )
        }
        // `String(bytes:encoding:)` rather than `String(decoding:as:)` to decode
        // a capture the same way `SubprocessChannel.standardErrorText()` does;
        // one framework, one ladder. It is not a correctness win, and neither
        // ladder round-trips a capture git could not express in UTF-8:
        // `String(decoding:)` would replace the offending bytes with U+FFFD and
        // hand the parser a path that matches nothing on disk, while a single
        // invalid byte here re-reads the *whole* capture as Latin-1 and
        // mojibakes every legitimate multi-byte character in it.
        return String(bytes: result.standardOutput, encoding: .utf8)
            ?? String(bytes: result.standardOutput, encoding: .isoLatin1)
            ?? ""
    }
}
