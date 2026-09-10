import AgenticToolkitCore
import AgenticToolkitLanguage
import Foundation
import os

/// Owns the app-wide `TextDocumentStore` and `TextDocumentSaveScheduler` —
/// the shared services every file editor pane opens documents through and
/// schedules autosaves on. Modeled directly on `NotesCoordinator`: one
/// instance per host, constructed once and threaded down through the
/// injection seam described in `DocumentPanes`, never constructed
/// inside a view (a `TextDocumentStore`'s refcounted `open`/`close` only
/// means anything with exactly one shared instance across the app).
///
/// `terminate()` is wired into `AppFeatureRegistry`'s existing termination
/// sweep automatically: `AppFeature.init()` registers `self`, and hosts
/// already call `terminate()` on every registered feature during shutdown
/// (see `NotesCoordinator.terminate()` and the host's `applicationWillTerminate`
/// wiring) — so flushing pending saves here needs no additional host-side
/// call site.
@MainActor
public final class TextDocumentCoordinator: AppFeature {

    public let store: TextDocumentStore
    public let saveScheduler: TextDocumentSaveScheduler

    /// - Parameter write: Persists one document's current text to disk.
    ///   Callers should preserve their own prior save semantics (atomic
    ///   write, encoding, success/failure logging) — this coordinator does
    ///   not second-guess how the write happens, only when.
    ///
    ///   `async`: this is called from the main actor, so the caller is
    ///   expected to snapshot the text there and do the I/O off it. A
    ///   synchronous write here blocks the UI on every autosave tick, which
    ///   the project's "all lengthy tasks must be done asynchronously" rule
    ///   forbids.
    public init(
        debounce: Duration = .seconds(1),
        write: @escaping TextDocumentSaveScheduler.Write
    ) {
        self.store = TextDocumentStore()
        self.saveScheduler = TextDocumentSaveScheduler(debounce: debounce, write: write)
        super.init()
    }

    /// Wait for any debounced saves before the app exits, exactly like
    /// `NotesCoordinator.terminate()` does for `NotesManager`.
    ///
    /// A flush can now answer that some documents did *not* reach the disk —
    /// the scheduler keeps a failed write pending rather than dropping it —
    /// and the last thing this process can usefully do about it is say so.
    public override func terminate() async {
        let unsaved = await saveScheduler.flushPendingSaves()
        guard !unsaved.isEmpty else { return }
        let list = unsaved.joined(separator: ", ")
        Self.logger.error(
            "Exiting with \(unsaved.count, privacy: .public) unsaved document(s): \(list, privacy: .public)"
        )
    }
}

extension TextDocumentCoordinator: Loggable {
    public static nonisolated let logger = makeLogger()
}
