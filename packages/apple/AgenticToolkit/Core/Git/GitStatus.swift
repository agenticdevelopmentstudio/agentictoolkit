import Foundation

/// The working tree's status as `git status --porcelain=v1` reports it,
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

    /// Parses `git status --porcelain=v1` output into file and directory status maps.
    public static func parse(porcelain output: String) -> GitStatus {
        var fileStatuses: [String: GitFileStatus] = [:]

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.count >= 3 else { continue }
            let statusChars = String(line.prefix(2))
            let filePath = String(line.dropFirst(3))

            let indexStatus = statusChars.first ?? " "
            let workTreeStatus = statusChars.last ?? " "

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
            } else if indexStatus == "R" {
                status = .renamed
                if let arrowRange = filePath.range(of: " -> ") {
                    let newPath = String(filePath[arrowRange.upperBound...])
                    fileStatuses[newPath] = status
                    continue
                }
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
