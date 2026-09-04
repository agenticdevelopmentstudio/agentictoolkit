import AgenticToolkitCore
import AgenticToolkitLanguage
import Foundation
import os

/// Owns the app-wide `TextDocumentStore` and `TextDocumentSaveScheduler` —
/// the shared services every file editor pane opens documents through and
/// schedules autosaves on. Modeled directly on `NotesCoordinator`: one
/// instance per host, constructed once and threaded down through the
/// injection seam described in `WhippetDocumentPanes`, never constructed
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
    public init(
        debounce: Duration = .seconds(1),
        write: @escaping @MainActor (TextDocument) throws -> Void
    ) {
        self.store = TextDocumentStore()
        self.saveScheduler = TextDocumentSaveScheduler(debounce: debounce, write: write)
        super.init()
    }

    /// Wait for any debounced saves before the app exits, exactly like
    /// `NotesCoordinator.terminate()` does for `NotesManager`.
    public override func terminate() async {
        await saveScheduler.flushPendingSaves()
    }
}

extension TextDocumentCoordinator: Loggable {
    public static nonisolated let logger = makeLogger()
}
