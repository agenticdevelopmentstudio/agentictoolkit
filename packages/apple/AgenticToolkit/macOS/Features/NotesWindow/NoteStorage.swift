import Foundation

/// Abstract storage interface for note persistence.
/// Clients provide a concrete implementation backed by their storage layer
/// (SQLite, Core Data, file system, etc.).
///
/// All methods are synchronous and may throw on I/O failure.
/// Thread safety is the implementor's responsibility.
///
/// `Sendable` because `NotesManager` calls these methods from outside the
/// main actor (M1(b) in the review this fixes) — a note read or write can
/// take real disk I/O, and doing it while holding the main actor blocked
/// every other main-actor-isolated host sharing this manager (Quick Note, a
/// second notes window) for the duration. An implementor whose storage is
/// not safe to call from a non-isolated context cannot conform.
public protocol NoteStorage: Sendable {
    func fetchAllNotes() throws -> [Note]
    func insertNote(_ note: Note) throws
    func updateNote(_ note: Note) throws
    func deleteNote(id: UUID) throws
}
