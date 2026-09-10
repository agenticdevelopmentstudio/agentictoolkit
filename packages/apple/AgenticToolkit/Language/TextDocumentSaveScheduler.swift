import AgenticToolkitCore
import Foundation
import LanguageServerProtocol
import os

/// Debounced autosave for `TextDocument`s.
///
/// The per-key debounce, the cancel-and-reschedule, and the
/// cancel-then-await-then-write-once flush all live in
/// `KeyedDebouncer` (`Core/Concurrency/KeyedDebouncer.swift`) — this type is
/// the `TextDocument`-shaped face of it. It used to be a hand-copy of
/// `NotesManager`'s `scheduleSave`/`flushPendingSaves`, which is why the
/// debouncer exists: three copies of that pattern each had to be corrected
/// separately, and the correction below is the one they all needed.
///
/// **A failed write does not lose the edit.** The debouncer keeps an entry
/// until its work completes without throwing, so a write that hits a full
/// disk, a revoked network volume or a file that turned read-only leaves the
/// document *still pending*, still dirty, and re-armed with backoff — and
/// `flushPendingSaves()` at termination still finds it and tries again. The
/// previous shape removed the document from its pending map before attempting
/// the write and only logged on failure, so nothing re-armed, nothing
/// re-inserted it, and the quit-time flush reported success over an empty map.
///
/// Foundation-only, same import rules as `TextDocument` — the write itself is
/// injected by the caller, not hardcoded here, which is what makes this type
/// testable without touching the filesystem.
@MainActor
public final class TextDocumentSaveScheduler {

    /// Persists one document's current text.
    ///
    /// `async` deliberately: this runs from the main actor, and a synchronous
    /// atomic write of a multi-megabyte file — or of any file on a network
    /// volume or a sleeping external disk — beachballs the UI on every
    /// autosave tick while the user is still typing. The caller is expected to
    /// snapshot on the main actor and do the I/O off it; the scheduler only
    /// decides *when*.
    public typealias Write = @MainActor (TextDocument) async throws -> Void

    private let write: Write
    private let debouncer: KeyedDebouncer<DocumentUri>

    public init(debounce: Duration = .seconds(1), write: @escaping Write) {
        self.write = write
        self.debouncer = KeyedDebouncer(debounce: debounce) { uri, error in
            let reason = error.localizedDescription
            TextDocumentSaveScheduler.logger.error(
                "Auto-save failed for \(uri, privacy: .public): \(reason, privacy: .public) — still pending, will retry"
            )
        }
    }

    /// Schedules `document` to be written after the debounce. A pending save
    /// for the same `uri` is replaced — ten keystrokes inside the debounce
    /// window produce exactly one write. A no-op on a document that is already
    /// clean: nothing to save means no work to arm.
    ///
    /// The closure holds `document` strongly, and the debouncer holds the
    /// closure until the write succeeds. That retention *is* the guarantee
    /// that a failed write has something left to retry.
    public func schedule(_ document: TextDocument) {
        guard document.isDirty else { return }
        debouncer.schedule(key: document.uri) { [weak self] in
            try await self?.performWrite(document)
        }
    }

    /// Drops a pending save for `uri` without writing — for a document being
    /// closed and discarded.
    public func cancel(uri: DocumentUri) {
        debouncer.cancel(key: uri)
    }

    /// Immediately persists the pending debounced save for `uri` alone,
    /// leaving every other pending save armed and still debouncing.
    ///
    /// This, not `flushPendingSaves()`, is what a file switch calls. The store
    /// and this scheduler are one instance for the whole app, so a
    /// whole-scheduler flush on every click would write every dirty document
    /// in every other window — defeating their debounce and hitching the click
    /// that triggered it.
    ///
    /// Two concurrent flushes of the same `uri` — an eviction and a file
    /// switch, say — do not produce two writes: the debouncer runs at most one
    /// unit of work per key at a time and the second flush awaits the first.
    public func flushPendingSave(uri: DocumentUri) async {
        await debouncer.flush(key: uri)
    }

    /// Immediately persists every pending debounced save, and answers with the
    /// `uri`s whose write *still* failed.
    ///
    /// Call at termination. A non-empty answer is a genuine "this work did not
    /// reach the disk" — the old shape could not report one, because a failed
    /// write had already removed itself from the pending map.
    @discardableResult
    public func flushPendingSaves() async -> [DocumentUri] {
        await debouncer.flushAll()
    }

    /// The `uri`s with a save currently pending — scheduled, in flight, or
    /// awaiting a retry after a failed write.
    public var pendingURIs: [DocumentUri] {
        debouncer.pendingKeys
    }

    /// Writes `document` and, if nothing was typed in the meantime, marks it
    /// clean.
    ///
    /// The version check is what the `async` write costs: the write suspends,
    /// so the user can type into the same document between the bytes being
    /// snapshotted and the write landing. Marking clean unconditionally there
    /// would clear the dirty indicator over a buffer that is genuinely newer
    /// than the file. The edit is not lost by declining — `TextDocument`'s
    /// change handler has already scheduled the next save for it.
    private func performWrite(_ document: TextDocument) async throws {
        let versionAtWrite = document.version
        try await write(document)
        guard document.version == versionAtWrite else { return }
        document.markClean()
    }
}

extension TextDocumentSaveScheduler: Loggable {
    public static nonisolated let logger = makeLogger()
}
