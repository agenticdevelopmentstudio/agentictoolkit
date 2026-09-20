import Foundation

/// A file's size and modification date — the cheap answer to "is this the same
/// file it was?", for the callers that would otherwise read the whole thing to
/// find out.
///
/// It exists because two places had already built it privately and a third was
/// about to. The extension host takes one of an extension's entry point to
/// decide whether a host needs tearing down and rebuilding; the open-document
/// reloader takes one of every watched file to decide whether a filesystem
/// event is worth reading a whole buffer's worth of text for, on the main
/// actor. Both want exactly this and nothing more.
///
/// **What it does not catch, plainly:** a rewrite that lands on the same byte
/// count *and* the same modification date. APFS records that date with
/// nanosecond resolution, so producing one takes deliberate effort — but a
/// caller that must not miss a change at any cost wants a hash of the contents,
/// not this.
///
/// **It says nothing about a file that is not there.** `init?` answers `nil`
/// for anything it could not stat, and a caller decides what absence means:
/// the reloader forgets what it knew, because whatever comes back has to be
/// read afresh however innocent its stamp looks.
public struct FileSignature: Equatable, Sendable {

    /// The file's size in bytes.
    public let size: Int

    /// The file's content modification date.
    public let modified: Date

    public init(size: Int, modified: Date) {
        self.size = size
        self.modified = modified
    }

    /// Stats `url`, or answers `nil` if there is nothing to stat — no such
    /// file, no permission, a path that is not a file.
    ///
    /// **`attributesOfItem(atPath:)`, not `url.resourceValues(forKeys:)`, and
    /// that is the whole correctness of this type.** A `URL` caches the
    /// resource values it has been asked for, so a second signature taken from
    /// the same `URL` value answers with the first one's numbers however much
    /// the file has changed underneath — which is precisely and only the
    /// question a signature is ever asked. A caller that holds the `URL` of a
    /// file it is watching, which is every caller here, would compare a value
    /// to itself forever and conclude nothing ever changes.
    public init?(of url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        self.init(size: size, modified: modified)
    }
}
