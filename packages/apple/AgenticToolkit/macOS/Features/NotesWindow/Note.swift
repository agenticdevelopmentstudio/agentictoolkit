import Foundation
import AgenticToolkitMarkdown

public struct Note: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var content: String
    public let createdDate: Date
    public var modifiedDate: Date
    public var isPinned: Bool

    public init(
        id: UUID,
        title: String,
        content: String,
        createdDate: Date,
        modifiedDate: Date,
        isPinned: Bool
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.isPinned = isPinned
    }

    /// Sort comparator: pinned notes first, then by modifiedDate descending.
    public static let defaultSort: @Sendable (Note, Note) -> Bool = { lhs, rhs in
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        return lhs.modifiedDate > rhs.modifiedDate
    }

    /// The title a note gets when nobody has named it.
    ///
    /// It *is* `MarkdownText.untitled`, not a second string that means the same
    /// thing. Two spellings of "unnamed" is one spelling too many, and the two
    /// met: `MarkdownText.deriveTitle` answers `"Untitled"` for a document with
    /// no heading, `MarkdownNoteStorage.storedTitle(for:)` asks whether a note
    /// is still unnamed by comparing against both that derivation and this
    /// constant, and while the two differed a note titled `"Untitled"` — which
    /// is exactly what a never-named note reads back as, since `note(from:)`
    /// takes its title from the document — was not recognised as unnamed and
    /// got a frontmatter `title: Untitled` written into it for nothing.
    /// One constant, so that comparison cannot be wrong again.
    public static let untitledTitle = MarkdownText.untitled

    /// Creates a new note with sane defaults. Treats empty/whitespace titles as `untitledTitle`.
    public static func new(title: String, content: String) -> Note {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return Note(
            id: UUID(),
            title: trimmed.isEmpty ? untitledTitle : trimmed,
            content: content,
            createdDate: Date(),
            modifiedDate: Date(),
            isPinned: false
        )
    }
}
