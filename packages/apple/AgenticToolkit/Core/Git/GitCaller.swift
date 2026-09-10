import Foundation

/// Where a git call came from, captured at the call site so the log can
/// attribute every process to a file and function.
///
/// The default arguments are the whole point: `#fileID` and `#function` are
/// evaluated in *the caller's* context, so a verb declared as
/// `caller: GitCaller = GitCaller()` records who asked without that caller
/// having to say anything.
public struct GitCaller: Sendable {
    public let file: String
    public let function: String

    public init(file: String = #fileID, function: String = #function) {
        self.file = file
        self.function = function
    }
}
