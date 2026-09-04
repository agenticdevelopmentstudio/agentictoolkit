import AgenticToolkitCore
import Foundation
import LanguageServerProtocol
import os

/// Debounced autosave for `TextDocument`s. Modeled directly on
/// `NotesManager`'s `scheduleSave`/`flushPendingSaves` (`macOS/Features/NotesWindow/NotesManager.swift`,
/// lines 94-137): a dictionary of per-key `Task`s, cancel-and-reschedule on
/// each touch, and a flush that cancels everyone, awaits each task, and only
/// then performs at most one write per key.
///
/// Foundation-only, same import rules as `TextDocument` — the write itself is
/// injected by the caller (Task 1.3), not hardcoded here, which is what makes
/// this type testable without touching the filesystem.
@MainActor
public final class TextDocumentSaveScheduler {

    private let debounce: Duration
    private let write: @MainActor (TextDocument) throws -> Void

    /// The document to write once its debounce elapses, keyed by `uri`. Held
    /// separately from `pendingTasks` so `flushPendingSaves()` can snapshot
    /// and clear both before writing anything.
    private var pendingDocuments: [DocumentUri: TextDocument] = [:]
    private var pendingTasks: [DocumentUri: Task<Void, Never>] = [:]

    public init(debounce: Duration = .seconds(1), write: @escaping @MainActor (TextDocument) throws -> Void) {
        self.debounce = debounce
        self.write = write
    }

    /// Schedules `document` to be written after `debounce`. A pending task
    /// for the same `uri` is cancelled and replaced — ten keystrokes inside
    /// the debounce window produce exactly one write. A no-op on a document
    /// that is already clean: nothing to save means no task to arm.
    public func schedule(_ document: TextDocument) {
        guard document.isDirty else { return }

        let uri = document.uri
        pendingTasks[uri]?.cancel()
        pendingDocuments[uri] = document

        let debounce = self.debounce
        pendingTasks[uri] = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            self.pendingTasks.removeValue(forKey: uri)
            guard let pending = self.pendingDocuments.removeValue(forKey: uri) else { return }
            self.performWrite(pending)
        }
    }

    /// Drops a pending save for `uri` without writing — for a document being
    /// closed and discarded.
    public func cancel(uri: DocumentUri) {
        pendingTasks[uri]?.cancel()
        pendingTasks.removeValue(forKey: uri)
        pendingDocuments.removeValue(forKey: uri)
    }

    /// Immediately persists every pending debounced save.
    ///
    /// Follows `NotesManager.flushPendingSaves()` exactly: snapshot the
    /// pending map, clear it, cancel every task, `await` every task, and only
    /// then perform the writes. That ordering — cancel everyone first, then
    /// wait for each to observe cancellation before writing — is what
    /// guarantees at most one write per document during a flush regardless of
    /// where each task was in its lifecycle; collapsing it into a single pass
    /// would race a task's own write against this one.
    public func flushPendingSaves() async {
        let documents = pendingDocuments
        let tasks = pendingTasks
        pendingDocuments.removeAll()
        pendingTasks.removeAll()

        for task in tasks.values { task.cancel() }
        for task in tasks.values { await task.value }

        for document in documents.values {
            performWrite(document)
        }
    }

    /// The `uri`s with a save currently pending.
    public var pendingURIs: [DocumentUri] {
        Array(pendingDocuments.keys)
    }

    private func performWrite(_ document: TextDocument) {
        do {
            try write(document)
            document.markClean()
        } catch {
            let uri = document.uri
            let reason = error.localizedDescription
            logger.error("Auto-save failed for \(uri, privacy: .public): \(reason, privacy: .public)")
        }
    }
}

extension TextDocumentSaveScheduler: Loggable {
    public static nonisolated let logger = makeLogger()
}
