import Foundation
import os
import AgenticToolkitCore

/// Coordinates in-memory note state and storage persistence.
/// All access must happen on the main actor.
@MainActor
public final class NotesManager {

    // MARK: - Observation

    /// Posted after `notes` changes — a create, an edit, a pin toggle, a
    /// delete, or a load. The manager is the sole owner of that array and had
    /// no way to say it had changed, so every view holding one asked its own
    /// caller to remember to call `reload()`: the split view controller does
    /// it after each of its own actions, and anything that mutated notes from
    /// somewhere else (Quick Note's save, a scripting command, a second
    /// window) left every other view stale until it was reopened.
    ///
    /// The notification carries no payload. `object` is the posting manager,
    /// so a host with more than one can tell them apart, and observers read
    /// `notes` from it — a snapshot in `userInfo` would be a second source of
    /// truth that is already stale by the time it is read.
    ///
    /// Posted on the main queue, always, because both the poster and every
    /// observer are `@MainActor`: `NotificationCenter` delivers synchronously
    /// on the posting thread, and this class is main-actor-isolated, so a post
    /// from here is already a main-queue delivery.
    public static let notesDidChangeNotification = Notification.Name(
        "AgenticToolkit.NotesManager.notesDidChange")

    private func postNotesDidChange() {
        NotificationCenter.default.post(name: Self.notesDidChangeNotification, object: self)
    }

    // MARK: - State

    public private(set) var notes: [Note] = []
    public private(set) var isLoaded: Bool = false

    // MARK: - Dependencies

    private let storage: NoteStorage
    private var saveTasks: [UUID: Task<Void, Never>] = [:]

    /// Debounce interval for auto-save.
    private static let saveDebounce: Duration = .seconds(1)

    // MARK: - Initialization

    public init(storage: NoteStorage) {
        self.storage = storage
    }

    // MARK: - Load

    public func loadNotes() async {
        do {
            let loaded = try storage.fetchAllNotes()
            notes = loaded.sorted(by: Note.defaultSort)
            isLoaded = true
            postNotesDidChange()
            logger.info("Loaded \(loaded.count) notes")
        } catch {
            isLoaded = true
            logger.error("Failed to load notes: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - CRUD

    @discardableResult
    public func createNote(title: String, content: String) async -> UUID {
        let note = Note.new(title: title, content: content)
        notes.append(note)
        notes.sort(by: Note.defaultSort)
        do {
            try storage.insertNote(note)
        } catch {
            logger.error("Failed to persist new note: \(error.localizedDescription, privacy: .public)")
        }
        // Posted whether or not the write succeeded: `notes` already holds the
        // new note either way, and an observer showing the manager's array
        // must match it even when the note is only in memory.
        postNotesDidChange()
        return note.id
    }

    /// Updates title and content with a 1-second debounce to avoid excessive writes.
    public func updateNote(_ note: Note, title: String, content: String) async {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var updated = notes[idx]
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmed.isEmpty ? Note.untitledTitle : trimmed
        updated.content = content
        updated.modifiedDate = Date()
        notes[idx] = updated
        notes.sort(by: Note.defaultSort)
        postNotesDidChange()
        scheduleSave(updated)
    }

    public func togglePin(note: Note) async {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var updated = notes[idx]
        updated.isPinned.toggle()
        updated.modifiedDate = Date()
        notes[idx] = updated
        notes.sort(by: Note.defaultSort)
        do {
            try storage.updateNote(updated)
        } catch {
            logger.error("Failed to toggle pin: \(error.localizedDescription, privacy: .public)")
        }
        postNotesDidChange()
    }

    public func deleteNote(id: UUID) async {
        notes.removeAll(where: { $0.id == id })
        do {
            try storage.deleteNote(id: id)
        } catch {
            logger.error("Failed to delete note: \(error.localizedDescription, privacy: .public)")
        }
        postNotesDidChange()
    }

    // MARK: - Debounced Save

    /// Schedules a save after `saveDebounce`. Subsequent calls for the same
    /// note ID cancel the pending task and reschedule.
    private func scheduleSave(_ note: Note) {
        let noteID = note.id
        saveTasks[noteID]?.cancel()
        saveTasks[noteID] = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled, let self else { return }
            self.saveTasks.removeValue(forKey: noteID)
            guard let current = self.notes.first(where: { $0.id == noteID }) else { return }
            do {
                try self.storage.updateNote(current)
            } catch {
                self.logger.error("Auto-save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Immediately persists any pending debounced saves. Cancels the scheduled
    /// tasks and awaits their completion to avoid racing writes, then performs
    /// a single synchronous write per affected note.
    ///
    /// Call before app termination.
    public func flushPendingSaves() async {
        let pending = saveTasks
        saveTasks.removeAll()

        // Cancel everyone first, then wait for each to observe cancellation
        // before writing — this guarantees at most one write per note during
        // flush, regardless of where the task was in its lifecycle.
        for (_, task) in pending { task.cancel() }
        for (_, task) in pending { await task.value }

        for (noteID, _) in pending {
            guard let note = notes.first(where: { $0.id == noteID }) else { continue }
            do {
                try storage.updateNote(note)
            } catch {
                logger.error("Flush save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension NotesManager: Loggable {
    public static nonisolated let logger = makeLogger()
}
