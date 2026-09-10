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
    /// no exit status at all — it timed out, or never launched.
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
        let joinedArguments = arguments.joined(separator: " ")
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
}

extension GitCommandLog: Loggable {
    public static nonisolated let logger = makeLogger()
}
