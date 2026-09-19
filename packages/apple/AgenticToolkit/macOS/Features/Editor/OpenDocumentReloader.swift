import AgenticToolkitCore
import AgenticToolkitLanguage
import Foundation
import LanguageServerProtocol
import os

/// Anything that can watch one directory and report paths that changed
/// underneath it. `FileSystemWatcher` is the implementation; the protocol
/// exists so `OpenDocumentReloader` can be tested without FSEvents, whose
/// 0.5 s coalescing latency and kernel-side delivery make it a source of
/// flakes rather than of signal in a unit test.
@MainActor
public protocol DirectoryWatching: AnyObject {
    func start()
    func stop()
}

extension FileSystemWatcher: DirectoryWatching {}

/// Notices that a file open in the editor changed on disk, and reloads the
/// buffer.
///
/// **What was broken without it.** A `TextDocument` was read once, at open,
/// and never looked at the file again. Switch branches, run a formatter, let
/// another editor write the file — the buffer went on showing the old text,
/// showed no sign that anything had happened, and the next save wrote the old
/// text back over the new, destroying the change with no warning and no undo.
/// VS Code reloads a clean buffer in place and prompts on a dirty one; this is
/// the reload half, which is the half that prevents data loss.
///
/// **Three cases, and the middle one is the point.**
///
/// - The text on disk equals the text in the buffer: nothing happens. Our own
///   save comes back through the watcher a moment after it lands, and a
///   reloader that did not check would answer every save with a redundant
///   `replaceAll` — a new version, a full-text `didChange` to every language
///   server, and a wiped selection, on every autosave.
/// - The buffer has unsaved edits: **nothing happens**, and the conflict is
///   logged. Reloading here would throw away the user's typing to install
///   someone else's change, which is a worse outcome than the staleness it
///   cures. Prompting is the right answer and needs UI that does not exist
///   yet; refusing to destroy work is what this can do correctly today.
/// - Otherwise the buffer is clean and behind: `replaceAll(with:)`, which
///   bumps the version and notifies every observer, language servers included.
///
/// A file that was **deleted** leaves the buffer exactly as it is. An open
/// editor over a file that has gone is an ordinary state — a branch switch, a
/// working-tree clean — and emptying the buffer would turn a recoverable
/// situation into a lost one, since the buffer is then the only copy of the
/// text.
///
/// **Directories, not files.** FSEvents watches directories; a watch on a file
/// path stops reporting the moment an atomic save replaces the inode, which is
/// how every careful writer writes. Watching the parent directory survives
/// that, at the cost of hearing about siblings — which is why every delivered
/// path is matched back against the open set before anything is read.
@MainActor
public final class OpenDocumentReloader {

    /// Builds a watcher for one directory. Injected so tests can drive the
    /// handler directly.
    public typealias WatcherFactory = @MainActor (
        _ directoryPath: String,
        _ handler: @escaping @Sendable ([String]) -> Void
    ) -> DirectoryWatching

    /// Reads a file's text, or throws. Injected for the same reason.
    public typealias TextReader = (URL) throws -> String

    private let store: TextDocumentStore
    private let makeWatcher: WatcherFactory
    private let readText: TextReader

    /// One watcher per directory, with the number of open documents under it.
    ///
    /// Refcounted rather than one watcher per document: several files from one
    /// directory is the ordinary case, and an FSEvent stream per open tab is a
    /// kernel resource per tab for no additional information.
    private struct Watch {
        let watcher: DirectoryWatching
        var documentCount: Int
    }
    private var watches: [String: Watch] = [:]

    /// The resolved on-disk path each open URI corresponds to, and its
    /// directory — computed at open, because resolving symlinks touches the
    /// filesystem and a watcher callback is not the place to pay for it.
    private struct Tracked {
        let url: URL
        let directoryPath: String
    }
    private var tracked: [DocumentUri: Tracked] = [:]

    private var observation: TextDocumentStoreObservation?

    public init(
        store: TextDocumentStore,
        makeWatcher: @escaping WatcherFactory = { path, handler in
            FileSystemWatcher(rootPath: path, excludedPrefixes: [], handler: handler)
        },
        readText: @escaping TextReader = { url in
            try String(contentsOf: url, encoding: .utf8)
        }
    ) {
        self.store = store
        self.makeWatcher = makeWatcher
        self.readText = readText
    }

    // MARK: - Lifecycle

    /// Begins watching every document already open, and every one opened
    /// after. Idempotent.
    ///
    /// Seeding from `openDocuments` rather than relying on future events is
    /// what makes the order of app startup not matter: the editor may well
    /// have opened a file before anything constructed this.
    public func start() {
        guard observation == nil else { return }
        for document in store.openDocuments {
            beginWatching(document.uri)
        }
        observation = store.addObserver { [weak self] event in
            self?.handle(event)
        }
    }

    /// Stops every watcher and unsubscribes. Idempotent, and `start()` after
    /// it is a fresh start rather than a no-op.
    ///
    /// Not a `deinit`: this type is `@MainActor` and a `deinit` cannot reach
    /// its isolated state. Nothing leaks without one — `FileSystemWatcher`
    /// stops itself when it is released, and releasing this releases every
    /// watcher it holds.
    public func stop() {
        observation = nil
        for watch in watches.values {
            watch.watcher.stop()
        }
        watches = [:]
        tracked = [:]
    }

    private func handle(_ event: TextDocumentEvent) {
        switch event {
        case .opened(let uri, _, _, _):
            beginWatching(uri)
        case .closed(let uri):
            endWatching(uri)
        case .changed, .dirtyStateChanged:
            break
        }
    }

    // MARK: - Watching

    private func beginWatching(_ uri: DocumentUri) {
        // Already tracked: the store refcounts opens, so two panes on one file
        // raise `.opened` once — but seeding and an event can still overlap.
        guard tracked[uri] == nil else { return }
        guard let url = URL(string: uri), url.isFileURL else { return }

        let resolved = url.resolvingSymlinksInPath()
        let directoryPath = resolved.deletingLastPathComponent().path
        tracked[uri] = Tracked(url: resolved, directoryPath: directoryPath)

        if var existing = watches[directoryPath] {
            existing.documentCount += 1
            watches[directoryPath] = existing
            return
        }

        let watcher = makeWatcher(directoryPath) { [weak self] paths in
            // `FileSystemWatcher` already hops to the main queue; the hop here
            // is what makes that a guarantee of this type rather than a detail
            // of one implementation of the protocol.
            Task { @MainActor [weak self] in
                self?.pathsChanged(paths)
            }
        }
        watches[directoryPath] = Watch(watcher: watcher, documentCount: 1)
        watcher.start()
    }

    private func endWatching(_ uri: DocumentUri) {
        guard let entry = tracked.removeValue(forKey: uri) else { return }
        guard var watch = watches[entry.directoryPath] else { return }
        watch.documentCount -= 1
        guard watch.documentCount <= 0 else {
            watches[entry.directoryPath] = watch
            return
        }
        watch.watcher.stop()
        watches.removeValue(forKey: entry.directoryPath)
    }

    // MARK: - Reloading

    private func pathsChanged(_ paths: [String]) {
        // The watch is on directories, so most of what arrives is about files
        // nobody has open. Build the lookup once rather than scanning the open
        // set per path.
        guard !tracked.isEmpty else { return }
        var byPath: [String: DocumentUri] = [:]
        for (uri, entry) in tracked {
            byPath[entry.url.path] = uri
        }
        for path in Set(paths) {
            guard let uri = byPath[path] else { continue }
            reloadIfNeeded(uri)
        }
    }

    private func reloadIfNeeded(_ uri: DocumentUri) {
        guard let entry = tracked[uri], let document = store.document(for: uri) else { return }

        let onDisk: String
        do {
            onDisk = try readText(entry.url)
        } catch {
            // Deleted, renamed away, or momentarily absent between an atomic
            // writer's unlink and rename. All three say the same thing: there
            // is nothing to reload from, and the buffer is the better copy.
            return
        }

        // Our own save, echoing back. Comparing the text rather than tracking
        // the write is what makes this correct for a save this process did not
        // make — another window, a checkout that restored the same bytes — as
        // well as for one it did.
        guard onDisk != document.text else { return }

        guard !document.isDirty else {
            Self.logger.notice(
                """
                \(uri, privacy: .public) changed on disk while it had unsaved \
                edits; keeping the buffer. Saving will overwrite the on-disk \
                change.
                """
            )
            return
        }

        // `replaceAll(with:)` clears the dirty flag itself, which is exactly
        // right here and is why nothing follows this line: the buffer now
        // holds what the file holds, so there is nothing unsaved about it.
        document.replaceAll(with: onDisk)
    }
}

extension OpenDocumentReloader: Loggable {
    public static nonisolated let logger = makeLogger()
}
