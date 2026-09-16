//
//  MainThreadWorkspace.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore
import OSLog
import AgenticToolkitCore

/// The workspace roots an `ExtensionHost` was given, narrowed to exactly what
/// `vscode.workspace` needs.
///
/// **Ruling:** this adaptor does not take a `ProjectWorkspace`. That type is a
/// large, app-shaped object — a `GitRepo`, a `ProjectDatabase`, a tab layout,
/// language services — and an extension host that held the whole thing could
/// reach members `vscode.workspace` has no business exposing, and would carry
/// a dependency from this framework's extension-host code onto the app's
/// project model for two fields. This protocol is the entire surface
/// `MainThreadWorkspace` needs, so it is the entire surface a host can reach.
/// The conformance that adapts `ProjectWorkspace` to it lives beside
/// `ProjectWorkspace` itself, not here — it is a fact about what a project
/// is, not a fact about extensions.
///
/// `@MainActor`, matching `ProjectWorkspace` and every other adaptor in this
/// file: nothing here is ever read off the main actor.
@MainActor
public protocol ExtensionWorkspaceRoots: AnyObject {

    /// The workspace's display name, or `nil` when it has none.
    /// `vscode.workspace.name`, before `MainThreadWorkspace` turns an absent
    /// one into JavaScript `undefined`.
    var workspaceDisplayName: String? { get }

    /// One entry per root, in order. `vscode.workspace.workspaceFolders`,
    /// before `MainThreadWorkspace` adds each folder's index and wraps its
    /// path in a `vscode.Uri`.
    ///
    /// Empty, not absent, when there are no roots — `nil` is not a value this
    /// property can hold, and `MainThreadWorkspace` is what turns "empty"
    /// into `undefined`, per VS Code's own contract that
    /// `workspaceFolders` is never an empty array.
    var workspaceRootURLs: [URL] { get }
}

/// The `vscode.workspace` adaptor: `fs`, `workspaceFolders`, `name` and
/// `getWorkspaceFolder`, terminating in the app's own `FileSystemService` and
/// in whatever `ExtensionWorkspaceRoots` its owner constructed it with.
///
/// **One instance per extension**, mirroring `ExtensionHost` and
/// `MainThreadCommands`. Nothing enforces it, but `getWorkspaceFolder`'s
/// promise about answering the same object `workspaceFolders` produced
/// depends on it: this adaptor caches the folders it builds against the one
/// `JSContext` it expects to be installed on, and a second context would
/// either see a stale cache or silently rebuild one, neither of which this
/// type tries to detect.
///
/// **`workspaceRoots` is read on every access**, not snapshotted. Each read of
/// `workspaceFolders` or `getWorkspaceFolder` asks the roots object what the
/// roots are now, and rebuilds the folder objects only when that answer
/// differs from the one they were built from (`folderEntries(in:)`).
///
/// The alternative — snapshot at first read — is what shipped first, and it
/// is wrong here for a reason specific to *when* this host activates:
/// extensions are activated at app launch, ahead of any project window, and
/// an extension's top-level code reads `workspaceFolders` right then. The
/// snapshot therefore captured "no roots" on the ordinary launch and held it
/// for the life of the process. `vscode.workspace.name` keeps no such
/// snapshot either, for the same reason — it is a
/// `DeferredVSCodeValue` that reads `workspaceDisplayName` when resolved.
///
/// Both members are installed through the shim's `defineLiveMember` — an
/// accessor property whose getter calls back into this adaptor — rather than
/// `defineMember`'s plain `table[name] = value` assignment, which is what
/// made "read once" the only available behaviour before.
///
/// What this type still does *not* do is *notify*: there are no
/// `onDidChangeWorkspaceFolders` events, because no event plumbing exists to
/// route one through. An extension that reads sees the current workspace; an
/// extension waiting to be told does not. The two are separable, and only the
/// first was a defect.
///
/// **`undefined`, not `null`, for an absent `name` or `workspaceFolders`.**
/// `JSValue(undefinedIn:)` is the only way to build a genuine `undefined`, and
/// it needs a live `JSContext` — unavailable at the point this adaptor's
/// `Any` values are constructed for `defineVSCodeMember`, which runs before
/// `activate()` so the member exists before the extension's own top-level
/// code can read it. `fs` is therefore built as an
/// `ExtensionHost.DeferredVSCodeValue`, resolved by `apply(_:to:)` at the one
/// point a queued definition meets a live context; `workspaceFolders` and
/// `name` take the live form of the same box
/// (`ExtensionHost.LiveVSCodeValue`), which resolves in the same place and
/// then again on every read. This is a small,
/// additive change to `ExtensionHost.apply(_:to:)` beyond what this task's
/// brief named (an `ExtensionHost.init` parameter) — see the task report for
/// why the alternative (a Swift `nil` boxed in `Any`, which bridges to
/// `NSNull`/JavaScript `null`, per `VSCodeAPI.resolvedPromise`'s own doc
/// comment) does not satisfy the tested contract.
///
/// **Whoever owns this adaptor must call `dispose()` when it tears the
/// extension host down.** An `fs` operation started before that point keeps
/// running — there is no way to cancel a `FileSystemService` call already in
/// flight, and no reason to: the disk operation itself is harmless to finish
/// — but `dispose()` means its result is never delivered to a torn-down
/// extension. Without it, a slow `readFile` that outlives its host would
/// resolve a promise nothing is listening to, which is quiet rather than
/// unsafe, but not what "torn down" should mean.
///
/// `@MainActor` for the reason every adaptor in this file is: `JSContext` and
/// `JSValue` are not `Sendable`, and every block below runs on the thread that
/// made the call, which for this host is always the main actor.
/// Frees the buffer `uint8ArrayValue(from:in:)` handed to
/// `JSObjectMakeTypedArrayWithBytesNoCopy`, once JavaScriptCore has collected
/// the array that adopted it.
///
/// **This is at file scope, outside the `@MainActor` class, deliberately.** It
/// is the one piece of this file that does *not* run on the main actor:
/// JavaScriptCore calls a typed-array deallocator from its own garbage
/// collector thread, in `Heap::runEndPhase`. Written as a closure literal
/// inside the class it inherited the class's isolation, and the isolation
/// check Swift emits on the `@convention(c)` thunk then trapped the whole
/// process — `dispatch_assert_queue` on a thread that is not and cannot be the
/// main queue. It killed the test runner outright rather than failing a test,
/// and only when a GC happened to collect a `readFile` result, which is why it
/// read as a flake: the crash is in the collector, arbitrarily far from the
/// read that allocated the buffer.
///
/// Nothing here touches the actor's state, so nonisolation costs nothing:
/// `deallocate()` on a pointer JavaScriptCore is finished with is the whole
/// body.
private func freeTypedArrayBytes(
    _ bytes: UnsafeMutableRawPointer?,
    _ deallocatorContext: UnsafeMutableRawPointer?
) {
    bytes?.deallocate()
}

@MainActor
public final class MainThreadWorkspace {

    /// The roots this adaptor exposes, or `nil` when no workspace is open.
    /// Read through `ExtensionWorkspaceRoots` rather than `ProjectWorkspace`
    /// directly — see that protocol's own doc for why.
    private let workspaceRoots: ExtensionWorkspaceRoots?

    /// Where every `fs` operation actually reads and writes. **Required, and
    /// shared with every other extension's adaptor** — the same rule as
    /// `MainThreadCommands`' `registry`, for a reason that is easy to miss.
    ///
    /// This used to carry a private default, on the argument that
    /// `FileSystemService` "holds no state a caller could lose" because it
    /// wraps a process-wide `FileManager`. That was wrong about the one piece
    /// of state it does hold: its **serial `DispatchQueue`**, which is the
    /// whole of its ordering guarantee. Two extensions with an instance each
    /// are two queues, so their writes to one file interleave at block
    /// granularity — a `writeFile` from each, and the result is neither
    /// extension's bytes. With one instance the queue orders them, and the
    /// loser's write lands whole. The cost is the throughput ceiling
    /// `FileSystemService`'s own concurrency discussion already names, which
    /// is the trade that discussion says to make.
    ///
    /// `ExtensionHostInstaller.Collaborators` owns the shared instance, beside
    /// the diagnostic store and the presenters, for the same reason they are
    /// there.
    ///
    /// Typed as ``FileSystemServicing``, not the concrete actor: the only
    /// reason is a test's need to substitute a double whose operations
    /// suspend under the test's own control, so it can exercise
    /// `runFileSystemOperation`'s in-flight teardown path. Nothing here
    /// depends on the concrete type.
    private let fileSystemService: FileSystemServicing

    /// Where a reach for an undefined `fs` member is recorded — the same
    /// ledger `ExtensionHost` holds, so a report reading the ledger sees
    /// `vscode.workspace.fs` misses beside every other namespace's. Required,
    /// not defaulted: a caller that forgot to pass the host's real ledger
    /// would otherwise silently lose every `fs` miss, the same failure mode
    /// this parameter exists to close.
    private let notImplementedLedger: NotImplementedLedger

    /// The extension this adaptor belongs to, recorded alongside every `fs`
    /// miss and probe so the ledger can tell one extension's reach from
    /// another's. Matches `ExtensionHost.identifier`.
    private let extensionIdentifier: String

    /// Set by `dispose()`. Checked before every `fs` promise settles, so an
    /// operation that outlives its host answers with a rejection instead of
    /// delivering a result — or crashing — into a torn-down extension.
    private var isDisposed = false

    /// This adaptor's own answer to `vscode.workspace.workspaceFolders`,
    /// built on demand and reused by `getWorkspaceFolder` so the two answer
    /// with the same object identity. `nil` until first needed, and again
    /// whenever `cachedFolderURLs` stops matching the roots — see
    /// `folderEntries(in:)`.
    private var cachedFolderEntries: [WorkspaceFolderEntry]?

    /// The `workspaceRootURLs` `cachedFolderEntries` was built from, which is
    /// what makes the cache re-derivable rather than write-once. `nil` and
    /// `[]` are deliberately different values here: `[]` is "built, from no
    /// roots", `nil` is "not built yet", and conflating them is what made a
    /// read taken before a project opened stick forever.
    private var cachedFolderURLs: [URL]?

    /// One built folder: the pieces `getWorkspaceFolder`'s longest-prefix
    /// match needs (`url`), and the already-bridged JavaScript object
    /// `workspaceFolders` and `getWorkspaceFolder` both hand back.
    private struct WorkspaceFolderEntry {
        let url: URL
        let value: JSValue
    }

    /// - Parameters:
    ///   - workspaceRoots: The workspace this adaptor exposes, or `nil` for
    ///     none. Not defaulted: a caller that forgot to pass the host's real
    ///     workspace would otherwise silently get "no workspace" for every
    ///     extension.
    ///   - notImplementedLedger: Where a reach for an undefined `fs` member is
    ///     recorded. Not defaulted, on the same grounds as `workspaceRoots`:
    ///     mirrors `ExtensionHost.notImplementedLedger`, and a caller
    ///     constructs this adaptor from a host's own ledger so the two never
    ///     disagree about where a miss goes.
    ///   - extensionIdentifier: The extension this adaptor belongs to, carried
    ///     alongside every ledger entry. Mirrors `ExtensionHost.identifier`.
    ///   - fileSystemService: Where `fs` operations run. Not defaulted, on the
    ///     same grounds as `workspaceRoots` and for a sharper reason: an
    ///     instance per extension is a serial queue per extension, which is no
    ///     write ordering between two extensions at all. See the property's
    ///     own doc.
    public init(
        workspaceRoots: ExtensionWorkspaceRoots?,
        notImplementedLedger: NotImplementedLedger,
        extensionIdentifier: String,
        fileSystemService: FileSystemServicing
    ) {
        self.workspaceRoots = workspaceRoots
        self.notImplementedLedger = notImplementedLedger
        self.extensionIdentifier = extensionIdentifier
        self.fileSystemService = fileSystemService
    }

    // MARK: - vscode.workspace.name

    /// `implementation` for `vscode.workspace.name`, handed to
    /// `ExtensionHost.defineVSCodeMember(namespacePath:name:implementation:)`
    /// as-is. An `ExtensionHost.LiveVSCodeValue`, not a plain `String?`, for
    /// two reasons: an absent name needs a live `JSContext` to become genuine
    /// `undefined`, and the name is app state that arrives after activation —
    /// see this type's own doc.
    public private(set) lazy var name: Any = ExtensionHost.LiveVSCodeValue { [weak self] context in
        guard let displayName = self?.workspaceRoots?.workspaceDisplayName else {
            return JSValueBridge.undefinedOrNull(in: context)
        }
        return displayName
    }

    // MARK: - vscode.workspace.workspaceFolders

    /// `implementation` for `vscode.workspace.workspaceFolders`. `undefined`
    /// when there are no roots — never an empty array, matching VS Code's own
    /// contract for this member.
    ///
    /// An `ExtensionHost.LiveVSCodeValue`: read at every access, because an
    /// extension reads this during activation and this host activates at app
    /// launch, before any project window exists.
    public private(set) lazy var workspaceFolders: Any = ExtensionHost.LiveVSCodeValue { [weak self] context in
        guard let self else { return JSValueBridge.undefinedOrNull(in: context) }
        let entries = self.folderEntries(in: context)
        guard !entries.isEmpty else { return JSValueBridge.undefinedOrNull(in: context) }
        return entries.map(\.value)
    }

    /// Builds and returns the folder objects both `workspaceFolders` and
    /// `getWorkspaceFolder` answer with. Idempotent, so it makes no
    /// difference which of the two is read first.
    ///
    /// The cache is keyed on the roots it was built from, not on "have I run
    /// before". An extension's top-level code reads
    /// `vscode.workspace.workspaceFolders` during activation, and this host
    /// activates extensions at app launch — before any project window exists,
    /// so `workspaceRootURLs` is empty at that moment for the ordinary
    /// launch. A run-once cache recorded that emptiness permanently: the
    /// extension saw `undefined`, and so did every later read, for the whole
    /// life of the process, no matter which project the user then opened.
    /// Every `workspaceContains:`-shaped extension was dead on arrival.
    ///
    /// Re-deriving costs a `[URL]` comparison per read and preserves the
    /// object identity `getWorkspaceFolder` promises for as long as the
    /// answer is genuinely the same: identity is rebuilt exactly when the
    /// workspace itself changed, which is the one case where handing back the
    /// old objects would be wrong anyway.
    private func folderEntries(in context: JSContext) -> [WorkspaceFolderEntry] {
        let urls = workspaceRoots?.workspaceRootURLs ?? []
        if let cachedFolderEntries, cachedFolderURLs == urls { return cachedFolderEntries }
        var entries: [WorkspaceFolderEntry] = []
        entries.reserveCapacity(urls.count)
        for (index, url) in urls.enumerated() {
            guard let value = MainThreadWorkspace.workspaceFolderValue(for: url, index: index, in: context) else {
                continue
            }
            entries.append(WorkspaceFolderEntry(url: url, value: value))
        }
        cachedFolderEntries = entries
        cachedFolderURLs = urls
        return entries
    }

    /// One `{ uri, name, index }` object — a plain JavaScript object, not a
    /// `JSExport` type, because nothing about this member needs to recompute
    /// anything after construction: the roots are a fixed snapshot (see this
    /// type's own doc), so `uri` can be built once, right here, where a live
    /// `JSContext` already exists. `uri` is a real `vscode.Uri` — built by
    /// `VSCodeAPI.uriValue(for:in:)`, the same call `vscode.Uri` itself uses —
    /// not a plain string, so `instanceof vscode.Uri` and `.fsPath` both work
    /// on it.
    ///
    /// `url` is stripped of any trailing-slash "directory" marking before it
    /// reaches `VSCodeAPI.uriValue`. `VSCodeAPI.uriValue(for:in:)` builds the
    /// `vscode.Uri` from `url.absoluteString`, and a `URL` built or
    /// standardized with `isDirectory: true` -- which is exactly what a
    /// workspace root's `URL` is, since it names an existing directory --
    /// keeps a trailing `/` in `absoluteString` all the way through to
    /// `Uri.parse` and out the other side as `.fsPath`. Real VS Code's
    /// `fsPath` never carries one, for any root, so an extension comparing
    /// `folder.uri.fsPath` against its own idea of the root -- a config
    /// value, a path it just joined -- sees a spurious mismatch on every real
    /// workspace. Rebuilding a file `URL` from `url.path` with
    /// `isDirectory: false` keeps the path characters identical and only
    /// removes the marker responsible for the trailing slash — `url.path`
    /// already carries no trailing slash of its own, unlike
    /// `url.absoluteString`, so nothing further needs to be stripped from it.
    /// This deliberately does **not** go through `url.standardizedFileURL`:
    /// that also resolves `..` and, worse, strips a leading `/private`
    /// whenever the result happens to name something that currently exists
    /// on disk — a root's `fsPath` would then depend on whether the
    /// directory was present at the moment this ran, not on the path it was
    /// given. `handleGetWorkspaceFolder`'s matcher standardizes deliberately,
    /// for the opposite reason: there, collapsing `/private/var/foo` and
    /// `/var/foo` onto the same root is exactly what a comparison wants.
    private static func workspaceFolderValue(for url: URL, index: Int, in context: JSContext) -> JSValue? {
        let filePathURL = URL(fileURLWithPath: url.path, isDirectory: false)
        guard let uriValue = VSCodeAPI.uriValue(for: filePathURL, in: context),
              let object = JSValue(newObjectIn: context) else {
            return nil
        }
        object.setObject(uriValue, forKeyedSubscript: "uri" as NSString)
        object.setObject(filePathURL.lastPathComponent, forKeyedSubscript: "name" as NSString)
        object.setObject(index, forKeyedSubscript: "index" as NSString)
        return object
    }

    // MARK: - vscode.workspace.getWorkspaceFolder

    /// `implementation` for `vscode.workspace.getWorkspaceFolder`. Synchronous
    /// — real VS Code answers `WorkspaceFolder | undefined`, not a
    /// `Thenable`, so `raisedException` is the right teardown response, same
    /// as `MainThreadCommands.registerCommand`.
    public private(set) lazy var getWorkspaceFolder: Any = VSCodeAPI.member(
        "vscode.workspace.getWorkspaceFolder", of: self, whenTornDown: .raisedException
    ) { $0.handleGetWorkspaceFolder() }

    /// The longest matching root wins — a file two directories under a nested
    /// project root answers with that nested root, not the outer one that
    /// also contains it. Matching is on standardized paths, at a path
    /// component boundary: `/a/bc` is not "inside" root `/a/b`, even though
    /// the string `/a/b` is a prefix of `/a/bc`.
    private func handleGetWorkspaceFolder() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        guard let uriArgument = arguments.first, let url = VSCodeAPI.url(from: uriArgument, in: context) else {
            return JSValue(undefinedIn: context)
        }
        let entries = folderEntries(in: context)
        let targetPath = url.standardizedFileURL.path
        var bestMatch: WorkspaceFolderEntry?
        var bestLength = -1
        for entry in entries {
            let rootPath = entry.url.standardizedFileURL.path
            let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            let isMatch = targetPath == rootPath || targetPath.hasPrefix(rootPrefix)
            guard isMatch, rootPath.count > bestLength else { continue }
            bestLength = rootPath.count
            bestMatch = entry
        }
        guard let bestMatch else { return JSValue(undefinedIn: context) }
        return bestMatch.value
    }

    // MARK: - vscode.workspace.fs

    // swiftlint:disable identifier_name
    /// `implementation` for `vscode.workspace.fs`: a sub-namespace carrying
    /// the seven `FileSystemService`-backed operations, built via
    /// `VSCodeAPI.subNamespace`. A `ExtensionHost.DeferredVSCodeValue` like
    /// `name` and `workspaceFolders`, because `subNamespace` itself needs a
    /// live `JSContext`.
    ///
    /// `recordMiss`/`recordProbe` are real closures bound to
    /// `notImplementedLedger` and `extensionIdentifier`, not `nil`. A fresh
    /// `subNamespace` call does not get miss-recording "for free" — the
    /// stub's `get` trap throws `NotImplementedError` unconditionally
    /// whether or not a recorder was supplied; only the *recording* of that
    /// reach is conditional on `recordMiss`/`recordProbe` being real
    /// functions. Passing `nil` for both, as this call used to, therefore
    /// left every reach under `vscode.workspace.fs` invisible to the ledger
    /// while still throwing correctly — the throw and the recording are two
    /// independent things, and only wiring these closures turns both on.
    public private(set) lazy var fs: Any = ExtensionHost.DeferredVSCodeValue { [weak self] context in
        guard let self else { return JSValueBridge.undefinedOrNull(in: context) }
        let ledger = self.notImplementedLedger
        let identifier = self.extensionIdentifier
        let recordMiss: @convention(block) (String) -> Void = { memberPath in
            MainActor.assumeIsolated {
                // The `_ =` is load-bearing: removing it breaks the build.
                // `MainActor.assumeIsolated` is generic in its closure's result
                // and is not `@discardableResult`, so a single-expression body
                // here infers `T == NotImplementedAccess` against this
                // `Void`-returning `@convention(block)` closure and fails to
                // type-check. `record`'s own `@discardableResult`
                // (`NotImplementedLedger.swift:113`) does not cover that.
                _ = ledger.record(memberPath: memberPath, extensionIdentifier: identifier)
            }
        }
        let recordProbe: @convention(block) (String) -> Void = { memberPath in
            MainActor.assumeIsolated {
                // The `_ =` is load-bearing: removing it breaks the build.
                // `MainActor.assumeIsolated` is generic in its closure's result
                // and is not `@discardableResult`, so a single-expression body
                // here infers `T == NotImplementedAccess` against this
                // `Void`-returning `@convention(block)` closure and fails to
                // type-check. `recordProbe`'s own `@discardableResult`
                // (`NotImplementedLedger.swift:124`) does not cover that.
                _ = ledger.recordProbe(memberPath: memberPath, extensionIdentifier: identifier)
            }
        }
        let members: [String: Any] = [
            "readFile": VSCodeAPI.member(
                "vscode.workspace.fs.readFile", of: self, whenTornDown: .rejectedPromise
            ) { $0.handleReadFile() },
            "writeFile": VSCodeAPI.member(
                "vscode.workspace.fs.writeFile", of: self, whenTornDown: .rejectedPromise
            ) { $0.handleWriteFile() },
            "readDirectory": VSCodeAPI.member(
                "vscode.workspace.fs.readDirectory", of: self, whenTornDown: .rejectedPromise
            ) { $0.handleReadDirectory() },
            "stat": VSCodeAPI.member(
                "vscode.workspace.fs.stat", of: self, whenTornDown: .rejectedPromise
            ) { $0.handleStat() },
            "delete": VSCodeAPI.member(
                "vscode.workspace.fs.delete", of: self, whenTornDown: .rejectedPromise
            ) { $0.handleDelete() },
            "rename": VSCodeAPI.member(
                "vscode.workspace.fs.rename", of: self, whenTornDown: .rejectedPromise
            ) { $0.handleRename() },
            "createDirectory": VSCodeAPI.member(
                "vscode.workspace.fs.createDirectory", of: self, whenTornDown: .rejectedPromise
            ) { $0.handleCreateDirectory() }
        ]
        guard let namespaceValue = VSCodeAPI.subNamespace(
            path: "vscode.workspace.fs", members: members, in: context,
            recordMiss: recordMiss, recordProbe: recordProbe
        ) else {
            return JSValueBridge.undefinedOrNull(in: context)
        }
        return namespaceValue
    }
    // swiftlint:enable identifier_name

    /// `readFile(uri): Thenable<Uint8Array>`.
    private func handleReadFile() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        guard let url = MainThreadWorkspace.requiredURL(from: arguments, at: 0, in: context) else {
            return VSCodeAPI.rejectedPromise(
                message: "vscode.workspace.fs.readFile requires a file-scheme vscode.Uri argument.", in: context)
        }
        let path = url.path
        let service = fileSystemService
        return runFileSystemOperation(path: "vscode.workspace.fs.readFile", in: context, {
            try await service.readFile(atPath: path)
        }, resolveWith: { data, context in
            MainThreadWorkspace.uint8ArrayValue(from: data, in: context)
        })
    }

    /// `writeFile(uri, content: Uint8Array): Thenable<void>`. Always creates
    /// and always overwrites — real `vscode.workspace.fs.writeFile` takes no
    /// options, and both are true unconditionally.
    private func handleWriteFile() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        guard let url = MainThreadWorkspace.requiredURL(from: arguments, at: 0, in: context) else {
            return VSCodeAPI.rejectedPromise(
                message: "vscode.workspace.fs.writeFile requires a file-scheme vscode.Uri argument.", in: context)
        }
        guard arguments.count > 1, let data = MainThreadWorkspace.data(fromUint8Array: arguments[1]) else {
            return VSCodeAPI.rejectedPromise(
                message: "vscode.workspace.fs.writeFile requires a Uint8Array of contents.", in: context)
        }
        let path = url.path
        let service = fileSystemService
        return runFileSystemOperation(path: "vscode.workspace.fs.writeFile", in: context, {
            try await service.writeFile(atPath: path, contents: data, create: true, overwrite: true)
        }, resolveWith: { _, context in JSValueBridge.undefinedOrNull(in: context) })
    }

    /// `readDirectory(uri): Thenable<[string, FileType][]>` — an array of
    /// two-element arrays, matching VS Code's own shape, not an array of
    /// `{name, type}` objects.
    private func handleReadDirectory() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        guard let url = MainThreadWorkspace.requiredURL(from: arguments, at: 0, in: context) else {
            return VSCodeAPI.rejectedPromise(
                message: "vscode.workspace.fs.readDirectory requires a file-scheme vscode.Uri argument.", in: context)
        }
        let path = url.path
        let service = fileSystemService
        return runFileSystemOperation(path: "vscode.workspace.fs.readDirectory", in: context, {
            try await service.readDirectory(atPath: path)
        }, resolveWith: { entries, _ in
            entries.map { [$0.name, $0.type.rawValue] as [Any] }
        })
    }

    /// `stat(uri): Thenable<FileStat>` — `type` as VS Code's own integer
    /// bitmask (identical raw values to `FileSystemService.FileType`, so no
    /// translation table is needed), `ctime`/`mtime` in milliseconds since the
    /// epoch, `0` when `FileSystemService` did not report a date — see
    /// `FileSystemService.FileStat`'s own doc: "a caller can collapse" that
    /// distinction, and VS Code's `FileStat` has no field for "unknown".
    private func handleStat() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        guard let url = MainThreadWorkspace.requiredURL(from: arguments, at: 0, in: context) else {
            return VSCodeAPI.rejectedPromise(
                message: "vscode.workspace.fs.stat requires a file-scheme vscode.Uri argument.", in: context)
        }
        let path = url.path
        let service = fileSystemService
        return runFileSystemOperation(path: "vscode.workspace.fs.stat", in: context, {
            try await service.stat(atPath: path)
        }, resolveWith: { stat, context in
            MainThreadWorkspace.statValue(for: stat, in: context)
        })
    }

    /// `delete(uri, options?): Thenable<void>`. `recursive` and `useTrash`
    /// both default `false` when the caller omits `options` — a permanent,
    /// non-recursive delete is the conservative reading, and this default is
    /// a best-effort guess rather than a confirmed reading of VS Code's own
    /// documentation (see the task report's concerns).
    private func handleDelete() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        guard let url = MainThreadWorkspace.requiredURL(from: arguments, at: 0, in: context) else {
            return VSCodeAPI.rejectedPromise(
                message: "vscode.workspace.fs.delete requires a file-scheme vscode.Uri argument.", in: context)
        }
        let options = arguments.count > 1 ? arguments[1] : nil
        let recursive = MainThreadWorkspace.boolOption(options, key: "recursive")
        let useTrash = MainThreadWorkspace.boolOption(options, key: "useTrash")
        let path = url.path
        let service = fileSystemService
        return runFileSystemOperation(path: "vscode.workspace.fs.delete", in: context, {
            try await service.delete(atPath: path, recursive: recursive, useTrash: useTrash)
        }, resolveWith: { _, context in JSValueBridge.undefinedOrNull(in: context) })
    }

    /// `rename(source, target, options?): Thenable<void>`. `overwrite`
    /// defaults `false`, matching VS Code's own documented default.
    private func handleRename() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        guard let fromURL = MainThreadWorkspace.requiredURL(from: arguments, at: 0, in: context),
              let toURL = MainThreadWorkspace.requiredURL(from: arguments, at: 1, in: context) else {
            return VSCodeAPI.rejectedPromise(
                message: "vscode.workspace.fs.rename requires two file-scheme vscode.Uri arguments.", in: context)
        }
        let options = arguments.count > 2 ? arguments[2] : nil
        let overwrite = options?.forProperty("overwrite")?.toBool() ?? false
        let fromPath = fromURL.path
        let toPath = toURL.path
        let service = fileSystemService
        return runFileSystemOperation(path: "vscode.workspace.fs.rename", in: context, {
            try await service.rename(fromPath: fromPath, toPath: toPath, overwrite: overwrite)
        }, resolveWith: { _, context in JSValueBridge.undefinedOrNull(in: context) })
    }

    /// `createDirectory(uri): Thenable<void>`.
    private func handleCreateDirectory() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        guard let url = MainThreadWorkspace.requiredURL(from: arguments, at: 0, in: context) else {
            return VSCodeAPI.rejectedPromise(
                message: "vscode.workspace.fs.createDirectory requires a file-scheme vscode.Uri argument.", in: context)
        }
        let path = url.path
        let service = fileSystemService
        return runFileSystemOperation(path: "vscode.workspace.fs.createDirectory", in: context, {
            try await service.createDirectory(atPath: path)
        }, resolveWith: { _, context in JSValueBridge.undefinedOrNull(in: context) })
    }

    // MARK: - The promise bridge

    /// Builds a genuinely-pending `Thenable`, kicks `operation` off in a
    /// `Task`, and settles the promise on the main actor once it finishes —
    /// Ruling: `JSValue(newPromiseIn:fromExecutor:)`, per this task's brief.
    ///
    /// `resolve` and `reject` are captured directly by the `Task` closure and
    /// nowhere else — no `[ObjectIdentifier: JSValue]` table, per the brief's
    /// second constraint. Each is a bounded, single-use capture that is
    /// released the moment the `Task` finishes.
    ///
    /// Checked twice for teardown, not once: before `operation` runs at all
    /// (the adaptor may already be disposed by the time this `Task` gets its
    /// first turn) and again after it finishes (disposed while the operation
    /// was in flight). Either way the promise rejects with the same
    /// "unavailable: torn down" wording `VSCodeAPI.member`'s own teardown
    /// path uses, rather than delivering a result — or a raw thrown error —
    /// to an extension the host has already abandoned.
    ///
    /// `resolve`/`reject` are handed to the `Task` through
    /// `PromiseSettlementBox`, not captured directly. `Task.init`'s
    /// `operation` closure is checked against `Sendable`, and a bare
    /// `JSValue` — not `Sendable`, and not a type this module owns to add a
    /// conformance to — would be flagged there even though both values are
    /// only ever touched back on the main actor that created them. That box
    /// and `UncheckedSendableBox`, which it is declared beside in
    /// `VSCodeAPI.swift`, are this directory's one statement of that
    /// guarantee, rather than a broader escape hatch.
    private func runFileSystemOperation<Value: Sendable>(
        path: String,
        in context: JSContext,
        _ operation: @escaping @Sendable () async throws -> Value,
        resolveWith: @escaping @MainActor (Value, JSContext) -> Any
    ) -> JSValue? {
        JSValue(newPromiseIn: context) { [weak self] resolveValue, rejectValue in
            // `valueWithNewPromiseInContext:fromExecutor:` declares both
            // executor arguments `_Null_unspecified`, so Swift types them
            // `JSValue?` here. JavaScriptCore always supplies both; with
            // either missing there is nothing to settle the promise through,
            // so the only honest answer is to leave it pending.
            guard let resolveValue, let rejectValue else { return }
            let settlement = PromiseSettlementBox(resolve: resolveValue, reject: rejectValue)
            Task { @MainActor [weak self] in
                guard let self, !self.isDisposed else {
                    JSValueBridge.rejectTornDown(settlement.reject, path: path)
                    return
                }
                do {
                    let result = try await operation()
                    guard !self.isDisposed, let resultContext = settlement.resolve.context else {
                        JSValueBridge.rejectTornDown(settlement.reject, path: path)
                        return
                    }
                    settlement.resolve.call(withArguments: [resolveWith(result, resultContext)])
                } catch {
                    guard !self.isDisposed, let errorContext = settlement.reject.context else {
                        JSValueBridge.rejectTornDown(settlement.reject, path: path)
                        return
                    }
                    settlement.reject.call(
                        withArguments: [MainThreadWorkspace.rejectionValue(for: error, in: errorContext)])
                }
            }
        }
    }

    // MARK: - Error mapping

    /// Builds the JavaScript `Error` an `fs` rejection carries: `message` from
    /// `FileSystemServiceError`'s own `errorDescription`, and a `code`
    /// property naming one of VS Code's `FileSystemError` codes wherever this
    /// adaptor can tell which one applies.
    private static func rejectionValue(for error: Error, in context: JSContext) -> Any {
        let message: String
        let code: String?
        if let fileSystemError = error as? FileSystemServiceError {
            message = fileSystemError.errorDescription ?? "\(fileSystemError)"
            code = vsCodeErrorCode(for: fileSystemError)
        } else {
            message = "\(error)"
            code = nil
        }
        guard let errorValue = JSValue(newErrorFromMessage: message, in: context) else {
            return JSValueBridge.undefinedOrNull(in: context)
        }
        if let code {
            errorValue.setObject(code, forKeyedSubscript: "code" as NSString)
        }
        return errorValue
    }

    /// `FileSystemServiceError` to VS Code's `FileSystemError` codes, built
    /// from task 5.4b's actual cases rather than guessed at.
    ///
    /// Four map directly, because 5.4b's own pre-checks detect exactly these
    /// before the underlying `FileManager` call: `.fileNotFound`,
    /// `.fileExists`, `.fileIsADirectory`, `.fileNotADirectory`.
    /// `.noPermissions` maps to VS Code's `NoPermissions` even though 5.4b's
    /// own report calls this detection best-effort rather than a pre-check —
    /// it is still the only VS Code code that means what it means.
    /// `.directoryNotEmpty` has no VS Code equivalent (5.4b's own report notes
    /// this and leaves the choice to this task): mapped to `Unavailable` with
    /// the original message carried through, a deliberate choice rather than
    /// an oversight. Every `*Failed` case is an operation that failed for a
    /// reason 5.4b could not classify more specifically than "the underlying
    /// call threw" — also `Unavailable`, for the same reason.
    private static func vsCodeErrorCode(for error: FileSystemServiceError) -> String {
        switch error {
        case .fileNotFound:
            return "FileNotFound"
        case .fileExists:
            return "FileExists"
        case .fileIsADirectory:
            return "FileIsADirectory"
        case .fileNotADirectory:
            return "FileNotADirectory"
        case .noPermissions:
            return "NoPermissions"
        case .directoryNotEmpty,
             .readFailed,
             .writeFailed,
             .statFailed,
             .readDirectoryFailed,
             .deleteFailed,
             .renameFailed,
             .createDirectoryFailed:
            return "Unavailable"
        }
    }

    // MARK: - Bridging helpers

    /// `Data` to a genuine JavaScript `Uint8Array`, through JavaScriptCore's
    /// own typed-array C entry point.
    ///
    /// `JSValue` has no *Objective-C* bridge from `NSData` to a typed array —
    /// `NSData` is absent from `JSValue`'s conversion table entirely, so an
    /// `NSData` handed across arrives as an opaque wrapper object, not
    /// something `instanceof Uint8Array` or indexing would work on. The route
    /// that table does offer — a plain `[UInt8]` bridged to a JS `Array`, fed
    /// to `new Uint8Array(...)` — is correct and quadratically expensive in
    /// the wrong place: it boxes **one `NSNumber` per byte** (a megabyte file
    /// is a million allocations), builds a second JS array of a million
    /// doubles to copy them out of, and recompiles the same one-line
    /// constructor script on every single `readFile`. All of it on the main
    /// actor, where `fs.readFile` runs.
    ///
    /// `JSObjectMakeTypedArrayWithBytesNoCopy` (macOS 10.12+) takes the bytes
    /// directly and adopts the buffer, so the whole cost is one `memcpy` out
    /// of the `Data` into a buffer JavaScriptCore then owns: the deallocator
    /// it calls when the array is collected is what frees it, which is why
    /// the allocation cannot be a Swift array's storage. Every failure path
    /// below frees the buffer itself, since a call that returns `nil` never
    /// took ownership and so never calls the deallocator.
    private static func uint8ArrayValue(from data: Data, in context: JSContext) -> Any {
        let byteCount = data.count
        // One byte minimum: `UnsafeMutableRawPointer.allocate` with a zero
        // byte count is undefined, and an empty file is an ordinary read.
        let bytes = UnsafeMutableRawPointer.allocate(
            byteCount: max(byteCount, 1), alignment: MemoryLayout<UInt8>.alignment)
        if byteCount > 0 {
            data.copyBytes(to: bytes.assumingMemoryBound(to: UInt8.self), count: byteCount)
        }
        var exception: JSValueRef?
        let object = JSObjectMakeTypedArrayWithBytesNoCopy(
            context.jsGlobalContextRef,
            kJSTypedArrayTypeUint8Array,
            bytes,
            byteCount,
            freeTypedArrayBytes,
            nil,
            &exception)
        guard let object, exception == nil, let value = JSValue(jsValueRef: object, in: context) else {
            bytes.deallocate()
            return JSValueBridge.undefinedOrNull(in: context)
        }
        return value
    }

    /// A `Uint8Array` argument to `Data` — the inverse of
    /// `uint8ArrayValue(from:in:)`, and cheap for the same reason.
    ///
    /// `JSValue.toArray()` also works here (a typed array has `length` and
    /// indexed properties, same as a plain array) and carries the same
    /// per-byte `NSNumber` on the way in that the read path carried on the
    /// way out, so `writeFile` of a megabyte was a million boxes on the main
    /// actor. `JSObjectGetTypedArrayBytesPtr` hands over the backing store
    /// instead, and `Data(bytes:count:)` copies once out of it.
    ///
    /// The pointer is only valid until JavaScript next runs — a typed array's
    /// buffer can be detached or moved — so it is read into `Data`
    /// immediately and never stored.
    ///
    /// **The array-of-numbers path stays, as a fallback.** `vscode.d.ts`
    /// declares `content: Uint8Array` and that is what the fast path reads,
    /// but `toArray()` accepted a plain `[1, 2, 3]` before this and an
    /// extension that passes one is writing a file today. Narrowing what is
    /// accepted is a separate decision from making the declared shape cheap,
    /// and this change is only the second.
    private static func data(fromUint8Array value: JSValue) -> Data? {
        guard let context = value.context else { return numbersData(from: value) }
        let contextRef = context.jsGlobalContextRef
        let valueRef = value.jsValueRef
        guard JSValueGetTypedArrayType(contextRef, valueRef, nil) == kJSTypedArrayTypeUint8Array else {
            return numbersData(from: value)
        }
        var exception: JSValueRef?
        guard let object = JSValueToObject(contextRef, valueRef, &exception), exception == nil else {
            return nil
        }
        let byteLength = JSObjectGetTypedArrayByteLength(contextRef, object, &exception)
        guard exception == nil else { return nil }
        guard byteLength > 0 else { return Data() }
        guard let bytes = JSObjectGetTypedArrayBytesPtr(contextRef, object, &exception),
              exception == nil else {
            return nil
        }
        return Data(bytes: bytes, count: byteLength)
    }

    /// Anything array-like of byte numbers, read one boxed `NSNumber` at a
    /// time. See `data(fromUint8Array:)` for when this runs and why it is no
    /// longer the path a `Uint8Array` takes.
    private static func numbersData(from value: JSValue) -> Data? {
        guard let numbers = value.toArray() else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(numbers.count)
        for number in numbers {
            guard let byte = (number as? NSNumber)?.uint8Value else { return nil }
            bytes.append(byte)
        }
        return Data(bytes)
    }

    /// `stat`'s `{type, ctime, mtime, size}` object.
    private static func statValue(for stat: FileSystemService.FileStat, in context: JSContext) -> Any {
        guard let object = JSValue(newObjectIn: context) else { return JSValueBridge.undefinedOrNull(in: context) }
        object.setObject(stat.type.rawValue, forKeyedSubscript: "type" as NSString)
        object.setObject(millisecondsSinceEpoch(stat.creationDate), forKeyedSubscript: "ctime" as NSString)
        object.setObject(millisecondsSinceEpoch(stat.modificationDate), forKeyedSubscript: "mtime" as NSString)
        object.setObject(stat.size, forKeyedSubscript: "size" as NSString)
        return object
    }

    /// `nil` collapses to `0`, matching `FileSystemService.FileStat`'s own
    /// doc: "a caller can collapse" the not-reported case, and VS Code's
    /// `FileStat` has no field for it.
    private static func millisecondsSinceEpoch(_ date: Date?) -> Double {
        guard let date else { return 0 }
        return date.timeIntervalSince1970 * 1000
    }

    /// `arguments[index]`, converted to a `URL` via `VSCodeAPI.url(from:in:)`,
    /// or `nil` if the index is out of range, the value is not a
    /// `vscode.Uri`, or the URI does not carry the `file:` scheme.
    ///
    /// **The scheme check is a security boundary, not a tidiness rule.**
    /// `VSCodeAPI.url(from:in:)` deliberately accepts any scheme, because its
    /// other callers need that: a diagnostic is keyed by an `untitled:` URI
    /// before the document is saved, and a `DiagnosticRelatedInformation`
    /// target is legitimately an `https:` documentation link. Every member
    /// reached through *this* helper, by contrast, ends in
    /// `FileSystemService`, which is handed `url.path` and reads or writes
    /// that path on disk with no scheme of its own to check against.
    ///
    /// Without this guard `URL(string:)` happily parses
    /// `https://attacker.example/etc/passwd`, whose `.path` is `/etc/passwd`,
    /// so `fs.readFile('https://attacker.example/etc/passwd')` reads the local
    /// file and hands its bytes back to extension JavaScript — the host's
    /// authority, reachable from a string the extension chose. The same shape
    /// turns `fs.delete` and `fs.writeFile` into arbitrary local writes. The
    /// check belongs here rather than in `url(from:in:)` because this is the
    /// narrowest point that every filesystem member passes through and no
    /// non-filesystem caller does.
    ///
    /// `isFileURL` is the whole test: it is true only for an absolute URL
    /// whose scheme is `file`, so a scheme-relative string (`/tmp/x`, which
    /// `URL(string:)` parses with a `nil` scheme) is refused too. VS Code's
    /// own `workspace.fs` surface takes a `Uri` and never a string, so
    /// nothing legitimate is lost.
    private static func requiredURL(from arguments: [JSValue], at index: Int, in context: JSContext) -> URL? {
        guard arguments.indices.contains(index) else { return nil }
        guard let url = VSCodeAPI.url(from: arguments[index], in: context), url.isFileURL else {
            return nil
        }
        return url
    }

    /// `options?.<key>` as a `Bool`, defaulting `false` when `options` is
    /// `nil`, the property is absent, or it is not something `toBool()` can
    /// read — the same permissive reading `handleRename`'s own `overwrite`
    /// uses inline, pulled out once `handleDelete` needed it twice.
    private static func boolOption(_ options: JSValue?, key: String) -> Bool {
        options?.forProperty(key)?.toBool() ?? false
    }

    // MARK: - Teardown

    /// Marks this adaptor torn down. `fs` operations already in flight
    /// reject rather than deliver a result; see this type's own doc.
    ///
    /// Unlike `MainThreadCommands.dispose()`, there is no registry to
    /// unregister from — `fs`, `workspaceFolders`, `name` and
    /// `getWorkspaceFolder` are all installed directly into the shim's member
    /// table by whoever called `defineVSCodeMember`, and that table belongs
    /// to the `ExtensionHost`, which is what actually goes away.
    public func dispose() {
        isDisposed = true
    }
}

extension MainThreadWorkspace: Loggable {

    /// The adaptor's own log destination, matching `MainThreadCommands`.
    public static nonisolated let logger = makeLogger()
}
