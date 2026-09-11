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
            // Counted and sliced in UTF-8 bytes, not in `Character`s. The
            // record's shape — `XY`, a space, then the path — is defined in
            // bytes, and `-z` hands the path over as raw bytes with no
            // quoting. A path beginning with a combining mark merges with the
            // preceding space into a single grapheme cluster, so `record.count`
            // read 3 for a record that is four bytes long and `dropFirst(3)`
            // consumed the first byte of the path along with the separator —
            // yielding an empty path that trapped the directory roll-up below.
            let bytes = Array(record.utf8)
            guard bytes.count >= 3 else { continue }

            // The status columns are ASCII by definition, so widening each
            // byte to a scalar is exact rather than a reinterpretation.
            let indexStatus = Character(UnicodeScalar(bytes[0]))
            let workTreeStatus = Character(UnicodeScalar(bytes[1]))

            // Rename/copy records are recognised and consumed first, ahead
            // of every other test: `RM` (renamed *and* modified — the state
            // a `git mv` followed by an edit leaves) and `RD` must key under
            // the new path as renames, not fall through to the M/A/D ladder
            // below and get keyed under a bogus compound string.
            //
            // The two-field shape belongs to the record, not to the index
            // column: git writes the origin path whenever *either* column is
            // `R` or `C`, so " R" (renamed in the work tree, which is what a
            // `git mv` followed by `git add -N` leaves) carries one too.
            // Testing only the index column left that field unconsumed, and
            // the loop then read the origin path as if it were the next
            // status record — dropping the rename and minting a phantom entry
            // keyed on the origin path minus its first three characters.
            let isRename = indexStatus == "R" || workTreeStatus == "R"
            let isCopy = indexStatus == "C" || workTreeStatus == "C"
            if isRename || isCopy {
                // The origin path is a second NUL-terminated field. It must
                // be consumed here regardless of whether this record is kept,
                // or the next record parsed would be misaligned. Consumed
                // *before* the path is decoded, for the same reason: a record
                // this parser gives up on must still leave the cursor where
                // the next record begins.
                if index < fields.endIndex {
                    index += 1
                }
            }

            // Every volume macOS mounts stores filenames as UTF-8, so this
            // decode does not fail in practice — but `-z` hands over raw
            // bytes and the failable initializer is the honest spelling of
            // that. A record whose path will not decode costs that one entry.
            //
            // An *empty* path costs that one entry too. Nothing names the
            // empty string, so a `""` key is a phantom entry no lookup by
            // real path can ever hit — and it is what the directory roll-up
            // below has to guard against. Dropping it here keeps the
            // malformed record from reaching two places at once.
            guard let filePath = String(bytes: bytes.dropFirst(3), encoding: .utf8),
                  !filePath.isEmpty else { continue }

            if isRename || isCopy {
                if isRename {
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
            // `split` omits empty subsequences, so a path that is empty — or
            // is nothing but separators — yields no components at all, and
            // `removeLast()` on that traps the process. The parse above no
            // longer manufactures such a path, but this is a `public` parser
            // reached from the file-browser refresh: a malformed record must
            // cost one entry, not the whole app (`fail-fast` bounded to the
            // record that caused it).
            guard !components.isEmpty else { continue }
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
