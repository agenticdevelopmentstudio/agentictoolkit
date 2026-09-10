import Foundation

extension UserSettings {
    /// Absolute path of the git executable every toolkit git call runs.
    public static var gitExecutablePath = UserSetting<String>("git.executable_path", default: "/usr/bin/git")

    /// Wall-clock budget, in seconds, for one git invocation.
    public static var gitStatusTimeoutSeconds = UserSetting<Int>("git.status_timeout_seconds", default: 5)

    /// When false, `git status` runs with `--ignore-submodules`.
    public static var gitStatusIncludesSubmodules = UserSetting<Bool>(
        "git.status_includes_submodules",
        default: false
    )
}
