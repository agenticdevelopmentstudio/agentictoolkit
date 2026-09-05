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

    /// Posted when a read or write against storage fails, right after
    /// `storageFailure` is set. Same shape and same reasoning as
    /// `notesDidChangeNotification`: no payload, `object` is the manager, and
    /// delivery is already on the main queue because this class is
    /// `@MainActor` and `NotificationCenter` delivers synchronously.
    ///
    /// A notification rather than a delegate because the manager has more than
    /// one host — a notes window, a notes pane, Quick Note — and a failure
    /// belongs to the manager, not to whichever of them happened to trigger it.
    public static let storageDidFailNotification = Notification.Name(
        "AgenticToolkit.NotesManager.storageDidFail")

    private func postNotesDidChange() {
        NotificationCenter.default.post(name: Self.notesDidChangeNotification, object: self)
    }

    // MARK: - State

    public private(set) var notes: [Note] = []
    public private(set) var isLoaded: Bool = false

    /// The last read or write that failed, or `nil` if none has since it was
    /// last cleared.
    ///
    /// It exists because the alternative was worse than no error handling: the
    /// UI went on asserting a write had succeeded. A failed insert left a note
    /// in `notes` and in the sidebar, every keystroke after it scheduled a save
    /// that threw `.notFound`, and the whole session's writing was gone at the
    /// next launch with nothing having said a word. Logging is not a user
    /// interface.
    ///
    /// Deliberately one value, not a queue: a failing database fails every
    /// operation, and the second alert would say the same thing as the first.
    /// Deliberately not an error-reporting framework either — this is the
    /// smallest thing that makes a failed write visible.
    public private(set) var storageFailure: NotesStorageFailure?

    /// Called by whichever host showed the failure, so a second host does not
    /// show it again.
    public func clearStorageFailure() {
        storageFailure = nil
    }

    private func record(_ operation: NotesStorageFailure.Operation, _ error: any Error) {
        logger.error(
            "\(operation.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        storageFailure = NotesStorageFailure(
            operation: operation, message: error.localizedDescription)
        NotificationCenter.default.post(name: Self.storageDidFailNotification, object: self)
    }

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
            record(.load, error)
        }
    }

    // MARK: - CRUD

    /// `nil` when the note could not be persisted — and in that case the note
    /// is not in `notes` either.
    ///
    /// A note that exists only in an array is not a note. Keeping it visible
    /// was the whole defect: the user typed into it all session, every save
    /// threw `.notFound` because nothing was ever inserted, and it was gone at
    /// the next launch. Removing it costs the user the text they had typed so
    /// far, which is at most a title on a brand-new note, and it is the only
    /// answer that leaves the screen telling the truth.
    @discardableResult
    public func createNote(title: String, content: String) async -> UUID? {
        let note = Note.new(title: title, content: content)
        do {
            try storage.insertNote(note)
        } catch {
            record(.create, error)
            return nil
        }
        notes.append(note)
        notes.sort(by: Note.defaultSort)
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
            record(.save, error)
        }
        postNotesDidChange()
    }

    public func deleteNote(id: UUID) async {
        notes.removeAll(where: { $0.id == id })
        do {
            try storage.deleteNote(id: id)
        } catch {
            record(.delete, error)
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
                self.record(.save, error)
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
                record(.save, error)
            }
        }
    }
}

extension NotesManager: Loggable {
    public static nonisolated let logger = makeLogger()
}

/// A storage read or write that failed, in the terms the user needs to hear it
/// in: which of their actions did not happen, and what the system said.
public struct NotesStorageFailure: Equatable, Sendable {

    public enum Operation: String, Sendable {
        case load
        case create
        case save
        case delete

        /// The sentence the alert leads with. Phrased as the user's action
        /// rather than the API's — "Couldn't Save Note", not "updateNote
        /// threw" — because that is the part they can act on.
        public var title: String {
            switch self {
            case .load: return "Couldn't Load Notes"
            case .create: return "Couldn't Create Note"
            case .save: return "Couldn't Save Note"
            case .delete: return "Couldn't Delete Note"
            }
        }

        /// What the failure means for what is on screen. `create` is the one
        /// that removed something, so it is the one that has to say so.
        public var consequence: String {
            switch self {
            case .load: return "Your notes could not be read from disk."
            case .create: return "The new note was not saved and has been removed."
            case .save: return "Your most recent changes are not saved to disk yet."
            case .delete: return "The note may reappear the next time Whippet starts."
            }
        }
    }

    public let operation: Operation

    /// `localizedDescription` of the underlying error, shown verbatim. A
    /// paraphrase would drop exactly the detail that distinguishes a full disk
    /// from a locked database.
    public let message: String

    public init(operation: Operation, message: String) {
        self.operation = operation
        self.message = message
    }
}
