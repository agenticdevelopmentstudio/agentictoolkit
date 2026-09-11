import Foundation

/// Everything `GitClient` needs to know before it spawns a process.
public struct GitClientConfiguration: Sendable, Equatable {
    public enum SubmoduleHandling: Sendable, Equatable {
        case ignore
        case include
    }

    public var executableURL: URL
    public var timeout: TimeInterval
    public var submoduleHandling: SubmoduleHandling
    /// Merged over the spawned child's environment, alongside `GitClient`'s
    /// own `GIT_TERMINAL_PROMPT` override — see `GitClient.execute`. Empty by
    /// default and additive: existing callers, `fromSettings()` included, are
    /// unaffected. Exists so a caller (a test, in particular) can redirect
    /// something like `GIT_CONFIG_GLOBAL` without mutating process-wide state
    /// with `setenv`, which every other concurrently-running test would also
    /// see.
    public var extraEnvironment: [String: String]

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        timeout: TimeInterval = 5,
        submoduleHandling: SubmoduleHandling = .ignore,
        extraEnvironment: [String: String] = [:]
    ) {
        self.executableURL = executableURL
        self.timeout = timeout
        self.submoduleHandling = submoduleHandling
        self.extraEnvironment = extraEnvironment
    }

    public static let `default` = GitClientConfiguration()

    /// Reads the user's settings. Main-actor because `UserSetting` is.
    @MainActor
    public static func fromSettings() -> GitClientConfiguration {
        GitClientConfiguration(
            executableURL: URL(fileURLWithPath: UserSettings.gitExecutablePath.value),
            timeout: TimeInterval(max(1, UserSettings.gitStatusTimeoutSeconds.value)),
            submoduleHandling: UserSettings.gitStatusIncludesSubmodules.value ? .include : .ignore
        )
    }
}
