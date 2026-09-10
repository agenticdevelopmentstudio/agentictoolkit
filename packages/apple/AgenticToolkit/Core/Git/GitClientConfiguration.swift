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

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        timeout: TimeInterval = 5,
        submoduleHandling: SubmoduleHandling = .ignore
    ) {
        self.executableURL = executableURL
        self.timeout = timeout
        self.submoduleHandling = submoduleHandling
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
