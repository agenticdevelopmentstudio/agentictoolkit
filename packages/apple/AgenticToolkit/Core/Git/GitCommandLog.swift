import Foundation
import OSLog

/// The one place every git invocation is recorded.
///
/// It records **that** a git call happened and where it came from — verb,
/// arguments, working directory, calling file and function, duration, exit
/// status. It deliberately records **no command output**: neither stdout nor
/// stderr reaches this log. A repository's contents, a diff, a branch listing
/// and a failure message are all the caller's to handle; what belongs here is
/// the fact of the call, so git usage can be counted, attributed and audited
/// without the log becoming a copy of the repository.
public enum GitCommandLog {

    /// Records one invocation. `exitStatus` is `nil` when the process produced
    /// no exit status at all — it timed out, it was cancelled, it never
    /// launched, or its output channel failed.
    ///
    /// Arguments are logged at `.public` because they are the feature: a log
    /// that hides `--porcelain=v1 -uall` cannot answer "what did the app
    /// actually ask git to do". They pass through `redactedArguments` first,
    /// which is where the exceptions live.
    public static func record(
        verb: String,
        arguments: [String],
        directory: URL?,
        caller: GitCaller,
        duration: TimeInterval,
        exitStatus: Int32?
    ) {
        let milliseconds = Int((duration * 1000).rounded())
        let status = exitStatus.map(String.init) ?? "unfinished"
        let joinedArguments = redactedArguments(verb: verb, arguments: arguments)
            .joined(separator: " ")
        let path = directory?.path ?? "-"
        logger.info(
            """
            git \(verb, privacy: .public) \(joinedArguments, privacy: .public) \
            cwd=\(path, privacy: .public) \
            from=\(caller.file, privacy: .public):\(caller.function, privacy: .public) \
            \(milliseconds, privacy: .public)ms status=\(status, privacy: .public)
            """
        )
    }

    /// Replaces argument positions that carry user data with
    /// `<redacted:<length>>`, keeping the length visible so a log still shows
    /// that *something* was passed and how big it was.
    ///
    /// This lives in the funnel, not at the call sites, on purpose. Redacting
    /// where a verb is written would split the arguments git is spawned with
    /// from the arguments the log is handed — a new way for the two to drift
    /// apart silently — and would make "remember to redact" a rule every
    /// future verb has to independently honour. One rule here is a rule none
    /// of them can forget, which is the whole premise of routing git through a
    /// single client.
    ///
    /// `OSLogPrivacy.private` is the wrong lever for the same job: it collapses
    /// the entire interpolation for every verb, so `--porcelain=v1 -uall` and
    /// `--abbrev-ref HEAD` disappear from Console too. That deletes the feature
    /// to protect one argument position.
    ///
    /// Today there is exactly one rule. `git config`'s arguments are
    /// `[<flags>..., <key>, <value>]`: the key names a setting and is worth
    /// seeing, everything after it is the user's own data (`user.email`, a
    /// signing key, a URL that may carry a token). So the first non-flag
    /// argument is kept and every argument after it is redacted — "after the
    /// key", not "is a value", so an argument that happens to begin with `-`
    /// cannot slip through as a flag. `--list` and `--unset` forms have nothing
    /// after their key and are untouched.
    ///
    /// Expected additions as verbs arrive: `commit -m <message>` and any remote
    /// URL.
    static func redactedArguments(verb: String, arguments: [String]) -> [String] {
        guard verb == "config" else { return arguments }
        guard let keyIndex = arguments.firstIndex(where: { !$0.hasPrefix("-") }) else {
            return arguments
        }
        return arguments.enumerated().map { index, argument in
            index > keyIndex ? "<redacted:\(argument.count)>" : argument
        }
    }
}

extension GitCommandLog: Loggable {
    public static nonisolated let logger = makeLogger()
}
