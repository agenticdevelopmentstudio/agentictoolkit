import Foundation

/// The working tree's status as `git status --porcelain=v1 -z` reports it,
/// keyed by repository-relative path, plus the merged status of every
/// directory that contains a changed file.
public struct GitStatus: Sendable, Equatable {
    public let files: [String: GitFileStatus]
    public let directories: [String: GitFileStatus]

    public init(files: [String: GitFileStatus], directories: [String: GitFileStatus]) {
        self.files = files
        self.directories = directories
    }

    public static let empty = GitStatus(files: [:], directories: [:])

    /// Parses `git status --porcelain=v1 -z` output into file and directory
    /// status maps. `-z` NUL-delimits every record instead of newline-
    /// terminating it, which keeps `core.quotePath`'s C-quoting off entirely
    /// — a path with a byte outside printable ASCII, or one that literally
    /// contains `" -> "`, arrives as its own field, unmangled. A rename or
    /// copy record (`XY` starting with `R` or `C`) carries **two** fields
    /// instead of one: the new path first, then a second NUL-terminated
    /// field with the original path — so this parser consumes that second
    /// field rather than splitting on an arrow, which is also what makes the
    /// old arrow-splitting bug (mis-keying `RM`/`RD` as
    /// `"old -> new"`) impossible: there is no arrow to look for any more.
    public static func parse(porcelain output: String) -> GitStatus {
        var fileStatuses: [String: GitFileStatus] = [:]

        let fields = output.split(separator: "\u{0}", omittingEmptySubsequences: true)
        var index = fields.startIndex
        while index < fields.endIndex {
            let record = fields[index]
            index += 1
            guard record.count >= 3 else { continue }
            let statusChars = String(record.prefix(2))
            let filePath = String(record.dropFirst(3))

            let indexStatus = statusChars.first ?? " "
            let workTreeStatus = statusChars.last ?? " "

            // Rename/copy records are recognised and consumed first, ahead
            // of every other test: `RM` (renamed *and* modified — the state
            // a `git mv` followed by an edit leaves) and `RD` must key under
            // the new path as renames, not fall through to the M/A/D ladder
            // below and get keyed under a bogus compound string.
            if indexStatus == "R" || indexStatus == "C" {
                // The origin path is a second NUL-terminated field. It must
                // be consumed here regardless of whether this record is kept,
                // or the next record parsed would be misaligned.
                if index < fields.endIndex {
                    index += 1
                }
                if indexStatus == "R" {
                    fileStatuses[filePath] = .renamed
                }
                continue
            }

            let status: GitFileStatus?
            if indexStatus == "?" || workTreeStatus == "?" {
                status = .untracked
            } else if indexStatus == "U" || workTreeStatus == "U" {
                status = .conflicted
            } else if indexStatus == "!" || workTreeStatus == "!" {
                status = .ignored
            } else if workTreeStatus == "M" || indexStatus == "M" {
                status = .modified
            } else if workTreeStatus == "A" || indexStatus == "A" {
                status = .added
            } else if workTreeStatus == "D" || indexStatus == "D" {
                status = .deleted
            } else {
                status = nil
            }

            if let resolved = status {
                fileStatuses[filePath] = resolved
            }
        }

        var dirStatuses: [String: GitFileStatus] = [:]
        for (path, status) in fileStatuses {
            var components = path.split(separator: "/")
            components.removeLast()
            var dirPath = ""
            for component in components {
                dirPath += (dirPath.isEmpty ? "" : "/") + component
                let existing = dirStatuses[dirPath]
                if existing == nil || status.priority > (existing?.priority ?? -1) {
                    dirStatuses[dirPath] = status
                }
            }
        }

        return GitStatus(files: fileStatuses, directories: dirStatuses)
    }
}
