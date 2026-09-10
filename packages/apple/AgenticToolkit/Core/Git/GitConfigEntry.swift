import Foundation

/// One `key\nvalue` record of `git config --list --null`.
public struct GitConfigEntry: Sendable, Equatable, Hashable, Identifiable {
    public let key: String
    public let value: String
    public var id: String { key }

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    /// Parses NUL-separated `config --list --null` output into entries.
    ///
    /// Within a record the key and value are separated by the *first* newline,
    /// not `=` -- the `--null` form exists precisely so a value can itself
    /// contain newlines, so only the first one is significant here. A
    /// value-less entry (e.g. `[alias]\n\tst` with no `= ...`) has no newline
    /// in its record at all and parses to an empty value. NUL is safe as the
    /// record delimiter because a config value cannot contain a NUL byte.
    public static func parse(nullSeparated output: String) -> [GitConfigEntry] {
        output.split(separator: "\0", omittingEmptySubsequences: true).map { record in
            if let newline = record.firstIndex(of: "\n") {
                let key = String(record[..<newline])
                let value = String(record[record.index(after: newline)...])
                return GitConfigEntry(key: key, value: value)
            }
            return GitConfigEntry(key: String(record), value: "")
        }
    }
}
