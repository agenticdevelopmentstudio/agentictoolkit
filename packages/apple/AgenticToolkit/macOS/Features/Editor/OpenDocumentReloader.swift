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
    ///
    /// `@Sendable` because it is called off the main actor — see
    /// `reloadIfNeeded(_:)`. The default reads with `String(contentsOf:)`,
    /// which is a synchronous read of a whole file that may be on a network
    /// volume, and that is the entire reason it does not run here.
    public typealias TextReader = @Sendable (URL) throws -> String

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

        /// What the file looked like the last time its text was read, and
        /// `nil` before there was one or after the file went away.
        ///
        /// This is what keeps a watcher event from costing a whole-file read.
        /// The stream is created with `kFSEventStreamCreateFlagFileEvents`,
        /// which reports metadata as readily as content — a chmod, an xattr
        /// written by Spotlight or a Finder tag, an ownership change — and
        /// coalescing turns one save into several callbacks. None of those
        /// moves the size or the modification date, and without this every one
        /// of them read the file from start to finish, on the actor drawing
        /// the window, to conclude nothing had changed.
        ///
        /// It is taken *before* the read, not after: a writer that lands
        /// between the stat and the read leaves a signature that does not
        /// match what was read, so the next event reads again rather than
        /// trusting text nobody ever saw.
        var lastRead: FileSignature?
    }
    private var tracked: [DocumentUri: Tracked] = [:]

    private var observation: TextDocumentStoreObservation?

    /// Every reload that has not finished reading yet, by a token that is
    /// unique to the reload rather than to the URI.
    ///
    /// Held rather than discarded for the same reason `PendingTeardowns`
    /// exists: work that outlives the call that started it still has to be
    /// waitable by someone. Here that someone is a test, which drives a
    /// watcher callback and then wants to assert on the buffer — see
    /// `settled()`.
    ///
    /// Keyed per reload and not per URI because two events for one file can
    /// overlap, and a second one storing itself under the same key would
    /// retire the first from this table while it was still running — leaving
    /// `settled()` satisfied by work that had not happened. Nothing is
    /// cancelled when they overlap: a read that comes back stale is already a
    /// no-op, because `apply` will not act on a signature that has moved.
    private var inFlight: [Int: Task<Void, Never>] = [:]

    /// Hands out the keys of `inFlight`. Main-actor-confined, so it needs
    /// nothing more than an increment to be unique.
    private var nextReloadToken = 0

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

    /// **The stat is on this actor; the read is not.**
    ///
    /// Everything above the read is cheap and belongs here: the signature is
    /// two fields of a `stat`, and it answers most callbacks without touching
    /// the file at all. The read itself is a different animal —
    /// `String(contentsOf:)` on a whole file, and this editor opens files from
    /// wherever the user has them, including a network volume that can stall
    /// for seconds. Doing that here stops the run loop: no typing, no
    /// scrolling, no cursor, in a window whose own document is not even the
    /// one that changed.
    ///
    /// So the read hops to `BlockingWork` and the decision comes back. What
    /// returns from that hop is checked against the world again before it is
    /// used — the buffer can be edited, saved, closed or reloaded by a later
    /// event while the read is out, and the signature recorded before the hop
    /// is exactly the token that says whether this read is still the current
    /// one *(idempotency)*.
    private func reloadIfNeeded(_ uri: DocumentUri) {
        // The store is checked here as well as in `apply` — here to avoid
        // reading a file for a buffer that is already gone, there because it
        // can go while the read is out.
        guard let entry = tracked[uri], store.document(for: uri) != nil else { return }

        guard let signature = FileSignature(of: entry.url) else {
            // Deleted, renamed away, or momentarily absent between an atomic
            // writer's unlink and rename. All three say the same thing: there
            // is nothing to reload from, and the buffer is the better copy.
            //
            // Forgetting the signature is the part that matters. A file that
            // comes back can be the same length at the same instant — a branch
            // switched away and back restores the timestamp it recorded — and
            // a reloader that still believed the old one would leave the
            // buffer showing the other branch's text with no event left to
            // correct it.
            tracked[uri]?.lastRead = nil
            return
        }

        // Nothing a read could tell us that this has not. Note this is not the
        // check below in a cheaper form: that one asks whether the *buffer* is
        // behind the file, this one asks whether the file moved at all since
        // we last looked, and only the second can be answered without reading.
        guard signature != entry.lastRead else { return }
        tracked[uri]?.lastRead = signature

        let url = entry.url
        let reader = readText
        nextReloadToken += 1
        let token = nextReloadToken
        inFlight[token] = Task { [weak self] in
            let onDisk: String
            do {
                onDisk = try await BlockingWork.run(qos: .userInitiated) {
                    try reader(url)
                }
            } catch {
                // Between the stat and the read — an atomic writer's window is
                // exactly this wide. Nothing was read, so nothing is known:
                // drop the signature so the next event does not skip on the
                // strength of a read that never happened.
                self?.finishReload(token) { reloader in
                    reloader.tracked[uri]?.lastRead = nil
                }
                return
            }
            self?.finishReload(token) { reloader in
                reloader.apply(onDisk, to: uri, readAt: signature)
            }
        }
    }

    /// Runs `body` back on the actor and retires this reload's entry.
    ///
    /// The retirement is unconditional and happens whichever way the read
    /// went: an entry left behind would make `settled()` wait forever on a
    /// task that has already finished.
    private func finishReload(
        _ token: Int, _ body: @escaping (OpenDocumentReloader) -> Void
    ) {
        body(self)
        inFlight[token] = nil
    }

    /// What to do with text that has come back from a read.
    ///
    /// - Parameter signature: what the file looked like when this read was
    ///   started. If `lastRead` has moved since, a later event has already
    ///   read the file again and this text is stale — the newer read is the
    ///   one that should decide, and applying this one would put older bytes
    ///   in the buffer and leave no event behind to correct it.
    private func apply(_ onDisk: String, to uri: DocumentUri, readAt signature: FileSignature) {
        guard tracked[uri]?.lastRead == signature else { return }
        guard let document = store.document(for: uri) else { return }

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

    /// Waits for every reload currently reading a file to finish applying.
    ///
    /// The reload is asynchronous by design — that is the whole of the change
    /// that put the read off this actor — and a watcher callback therefore
    /// returns before the buffer has been touched. Production has nobody who
    /// needs to know when it has; a test that drove a watcher and then asserted
    /// on the buffer very much does, and the alternative is a sleep that is
    /// either flaky or slow.
    func settled() async {
        while let task = inFlight.values.first {
            await task.value
        }
    }
}

extension OpenDocumentReloader: Loggable {
    public static nonisolated let logger = makeLogger()
}
