import Foundation
import LanguageServerProtocol

/// The single place a local file `URL` becomes the `DocumentUri` (LSP's
/// `file://` string form) it is opened under. Two independent call sites
/// need to agree on exactly this string for exactly the same file — the
/// file editor, opening a document into a `TextDocumentStore`, and the file
/// tree, looking that same document back up by its node's `URL` to show a
/// dirty indicator — so this is that one place, rather than two ad hoc
/// `url.absoluteString`s that would silently drift apart if either changed.
extension URL {
    public var documentUri: DocumentUri {
        absoluteString
    }
}
