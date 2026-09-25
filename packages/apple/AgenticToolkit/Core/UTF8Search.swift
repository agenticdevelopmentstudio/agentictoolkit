import Foundation

extension String {

    /// Whether the string's UTF-8 bytes contain `needle`'s, found with `memmem`
    /// on the string's own storage.
    ///
    /// For prefilters that run on every line of a large file: `contains(_:)`
    /// on a `String` takes Foundation's generic substring search, which walks
    /// indices a character at a time, and on a 130 MB transcript that search
    /// was nearly all of the scan. A byte match is exact for any needle,
    /// because UTF-8 never lets one character's bytes start inside another's.
    /// Hold a hot needle as bytes (`Array("marker".utf8)`) and pass those.
    public func containsUTF8(_ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty else { return true }
        var copy = self
        return copy.withUTF8 { bytes in
            needle.withUnsafeBytes { marker in
                memmem(bytes.baseAddress, bytes.count, marker.baseAddress, marker.count) != nil
            }
        }
    }

    /// ``containsUTF8(_:)-([UInt8])`` for a needle held as a string.
    public func containsUTF8(_ needle: String) -> Bool {
        containsUTF8(Array(needle.utf8))
    }
}
