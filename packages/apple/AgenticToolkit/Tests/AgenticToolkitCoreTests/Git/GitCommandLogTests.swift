import Foundation
import Testing
@testable import AgenticToolkitCore

/// Covers `GitCommandLog.redactedArguments`, the pure function that decides what
/// an argument list looks like once it reaches the log.
///
/// It is tested directly rather than through `GitClient`: the redaction rule is
/// about a list of strings, and asserting it by spawning git and then reading
/// the unified log back would test OSLog's delivery rather than the rule. The
/// argument lists below are copied from `GitClient`'s own call sites, so a verb
/// that changes its arguments breaks a test here rather than leaking quietly.
@Suite("GitCommandLog.redactedArguments")
struct GitCommandLogTests {
    @Test("a non-config verb is passed through untouched")
    func nonConfigVerbUntouched() {
        let arguments = ["status", "--porcelain=v1", "-uall", "--ignore-submodules"]
        #expect(GitCommandLog.redactedArguments(verb: "status", arguments: arguments) == arguments)
    }

    @Test("a config verb that only names a key keeps every argument")
    func configReadsKeepTheirArguments() {
        // `globalConfig()` — all flags, so there is no key and nothing follows one.
        let list = ["--global", "--list", "--null"]
        #expect(GitCommandLog.redactedArguments(verb: "config", arguments: list) == list)

        // `unsetGlobalConfig(key:)` — the key is last, so nothing follows it.
        let unset = ["--global", "--unset", "user.email"]
        #expect(GitCommandLog.redactedArguments(verb: "config", arguments: unset) == unset)
    }

    @Test("a config write redacts the value and keeps its length")
    func configWriteRedactsTheValue() {
        // `setGlobalConfig(key:value:)`.
        let redacted = GitCommandLog.redactedArguments(
            verb: "config",
            arguments: ["--global", "user.email", "someone@example.com"]
        )
        #expect(redacted == ["--global", "user.email", "<redacted:19>"])
    }

    @Test("everything after the key is redacted, flag-shaped or not")
    func redactionIsPositionalNotShapeBased() {
        let redacted = GitCommandLog.redactedArguments(
            verb: "config",
            arguments: ["--global", "core.pager", "--dash-leading-value", "trailing"]
        )
        #expect(redacted == ["--global", "core.pager", "<redacted:20>", "<redacted:8>"])
    }

    @Test("an empty argument list is returned as-is")
    func emptyArguments() {
        #expect(GitCommandLog.redactedArguments(verb: "config", arguments: []).isEmpty)
    }
}
