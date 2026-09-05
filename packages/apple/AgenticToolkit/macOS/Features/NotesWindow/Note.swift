import Foundation

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

    /// The title a note gets when nobody has named it. Every place that
    /// blanks out a title — here and in `NotesManager.updateNote` — goes
    /// through this one constant, so a storage layer can recognise "the app
    /// never named this note" without hardcoding a second copy of the string.
    public static let untitledTitle = "Untitled Note"

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
