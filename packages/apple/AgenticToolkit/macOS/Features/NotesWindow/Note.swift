import Foundation
import AgenticToolkitMarkdown

public struct Note: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var content: String
    public let createdDate: Date
    public var modifiedDate: Date
    public var isPinned: Bool

    /// A note has no title field of its own — this is `MarkdownDocument.title`,
    /// the same derivation adh applies: frontmatter `title`/`name` first, then
    /// the first body line, then `untitledTitle`. Computed, not stored, so it
    /// can never go stale against `content` between an edit and the next save.
    public var title: String { MarkdownText.deriveTitle(content) }

    /// The list preview, likewise derived rather than stored — see
    /// `MarkdownDocument.excerpt`. Skips the line `title` came from, so a
    /// heading used as the title never repeats itself as the first line of
    /// the preview underneath it.
    public var excerpt: String {
        MarkdownText.deriveExcerpt(MarkdownText.excerptSource(content), frontmatterFrom: content)
    }

    public init(
        id: UUID,
        content: String,
        createdDate: Date,
        modifiedDate: Date,
        isPinned: Bool
    ) {
        self.id = id
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
    /// thing — `MarkdownText.deriveTitle` already answers `"Untitled"` for a
    /// document with no heading and no frontmatter title, and this is that
    /// same constant so a comparison against it can never disagree.
    public static let untitledTitle = MarkdownText.untitled

    /// Creates a new note with sane defaults. Title and excerpt are derived
    /// from `content` — an empty note derives `untitledTitle`, via
    /// `MarkdownText.deriveTitle("")`.
    public static func new(content: String) -> Note {
        Note(
            id: UUID(),
            content: content,
            createdDate: Date(),
            modifiedDate: Date(),
            isPinned: false
        )
    }
}
