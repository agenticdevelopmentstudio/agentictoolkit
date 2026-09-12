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
/// **`workspaceRoots` is read once**, the first time either `workspaceFolders`
/// or `getWorkspaceFolder` needs it, and never again. A workspace that adds or
/// removes a folder after that point is invisible to an already-activated
/// extension — the same snapshot-at-activation contract `vscode.workspace.name`
/// keeps. Nothing in this task asked for live updates, and the shim's
/// `defineMember` has no notion of one: `table[name] = value` is a plain
/// assignment, not a JavaScript accessor property, so there is nowhere to
/// route a later change even if this type tried to notice one.
///
/// **`undefined`, not `null`, for an absent `name` or `workspaceFolders`.**
/// `JSValue(undefinedIn:)` is the only way to build a genuine `undefined`, and
/// it needs a live `JSContext` — unavailable at the point this adaptor's
/// `Any` values are constructed for `defineVSCodeMember`, which runs before
/// `activate()` so the member exists before the extension's own top-level
/// code can read it. `fs`, `workspaceFolders` and `name` are therefore built
/// as `ExtensionHost.DeferredVSCodeValue`, resolved by `apply(_:to:)` at the
/// one point a queued definition meets a live context. This is a small,
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
@MainActor
public final class MainThreadWorkspace {

    /// The roots this adaptor exposes, or `nil` when no workspace is open.
    /// Read through `ExtensionWorkspaceRoots` rather than `ProjectWorkspace`
    /// directly — see that protocol's own doc for why.
    private let workspaceRoots: ExtensionWorkspaceRoots?

    /// Where every `fs` operation actually reads and writes. A private
    /// default rather than a required parameter, unlike `MainThreadCommands`'
    /// `registry`: `FileSystemService` holds no state a caller could lose by
    /// not sharing an instance — it wraps `FileManager`, which is itself
    /// already process-wide — so nothing is silently dropped the way an
    /// unshared `CommandRegistry` would drop the app's own command palette.
    private let fileSystemService: FileSystemService

    /// Set by `dispose()`. Checked before every `fs` promise settles, so an
    /// operation that outlives its host answers with a rejection instead of
    /// delivering a result — or crashing — into a torn-down extension.
    private var isDisposed = false

    /// This adaptor's own answer to `vscode.workspace.workspaceFolders`,
    /// built once and reused by `getWorkspaceFolder` so the two answer with
    /// the same object identity. `nil` until first needed; see the type's own
    /// doc for why a workspace change after that point is not reflected.
    private var cachedFolderEntries: [WorkspaceFolderEntry]?

    /// One built folder: the pieces `getWorkspaceFolder`'s longest-prefix
    /// match needs (`url`), and the already-bridged JavaScript object
    /// `workspaceFolders` and `getWorkspaceFolder` both hand back.
    private struct WorkspaceFolderEntry {
        let url: URL
        let value: JSValue
    }

    /// Carries a promise's `resolve`/`reject` `JSValue`s into a `Task`.
    ///
    /// `@unchecked Sendable`, on the same terms as `VSCodeAPI.swift`'s own
    /// `UncheckedJSValueBox`: nothing here actually crosses an isolation
    /// domain — `runFileSystemOperation`'s `Task { @MainActor in … }` reads
    /// both values back on the same main actor that created them — but
    /// `Task.init` checks its `operation` closure against `Sendable`, and a
    /// bare `JSValue` is not, and is not a type this module can extend with
    /// a conformance. This box is the honest way to state the guarantee the
    /// surrounding code already holds.
    private struct SettlementBox: @unchecked Sendable {
        let resolve: JSValue
        let reject: JSValue
    }

    /// - Parameters:
    ///   - workspaceRoots: The workspace this adaptor exposes, or `nil` for
    ///     none. Not defaulted: a caller that forgot to pass the host's real
    ///     workspace would otherwise silently get "no workspace" for every
    ///     extension.
    ///   - fileSystemService: Where `fs` operations run. Defaults to a private
    ///     instance — see the property's own doc for why that is safe here.
    public init(workspaceRoots: ExtensionWorkspaceRoots?, fileSystemService: FileSystemService = FileSystemService()) {
        self.workspaceRoots = workspaceRoots
        self.fileSystemService = fileSystemService
    }

    // MARK: - vscode.workspace.name

    /// `implementation` for `vscode.workspace.name`, handed to
    /// `ExtensionHost.defineVSCodeMember(namespacePath:name:implementation:)`
    /// as-is. A `ExtensionHost.DeferredVSCodeValue`, not a plain `String?`: see
    /// this type's own doc for why an absent name needs a live `JSContext` to
    /// become genuine `undefined`.
    public private(set) lazy var name: Any = ExtensionHost.DeferredVSCodeValue { [weak self] context in
        guard let displayName = self?.workspaceRoots?.workspaceDisplayName else {
            return MainThreadWorkspace.undefinedValue(in: context)
        }
        return displayName
    }

    // MARK: - vscode.workspace.workspaceFolders

    /// `implementation` for `vscode.workspace.workspaceFolders`. `undefined`
    /// when there are no roots — never an empty array, matching VS Code's own
    /// contract for this member.
    public private(set) lazy var workspaceFolders: Any = ExtensionHost.DeferredVSCodeValue { [weak self] context in
        guard let self else { return MainThreadWorkspace.undefinedValue(in: context) }
        let entries = self.folderEntries(in: context)
        guard !entries.isEmpty else { return MainThreadWorkspace.undefinedValue(in: context) }
        return entries.map(\.value)
    }

    /// Builds (once) and returns the folder objects both `workspaceFolders`
    /// and `getWorkspaceFolder` answer with. Idempotent, so it makes no
    /// difference which of the two is read first.
    private func folderEntries(in context: JSContext) -> [WorkspaceFolderEntry] {
        if let cachedFolderEntries { return cachedFolderEntries }
        let urls = workspaceRoots?.workspaceRootURLs ?? []
        var entries: [WorkspaceFolderEntry] = []
        entries.reserveCapacity(urls.count)
        for (index, url) in urls.enumerated() {
            guard let value = MainThreadWorkspace.workspaceFolderValue(for: url, index: index, in: context) else {
                continue
            }
            entries.append(WorkspaceFolderEntry(url: url, value: value))
        }
        cachedFolderEntries = entries
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
    private static func workspaceFolderValue(for url: URL, index: Int, in context: JSContext) -> JSValue? {
        guard let uriValue = VSCodeAPI.uriValue(for: url, in: context),
              let object = JSValue(newObjectIn: context) else {
            return nil
        }
        object.setObject(uriValue, forKeyedSubscript: "uri" as NSString)
        object.setObject(url.lastPathComponent, forKeyedSubscript: "name" as NSString)
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
    public private(set) lazy var fs: Any = ExtensionHost.DeferredVSCodeValue { [weak self] context in
        guard let self else { return MainThreadWorkspace.undefinedValue(in: context) }
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
            path: "vscode.workspace.fs", members: members, in: context, recordMiss: nil, recordProbe: nil
        ) else {
            return MainThreadWorkspace.undefinedValue(in: context)
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
                message: "vscode.workspace.fs.readFile requires a vscode.Uri argument.", in: context)
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
                message: "vscode.workspace.fs.writeFile requires a vscode.Uri argument.", in: context)
        }
        guard arguments.count > 1, let data = MainThreadWorkspace.data(fromUint8Array: arguments[1]) else {
            return VSCodeAPI.rejectedPromise(
                message: "vscode.workspace.fs.writeFile requires a Uint8Array of contents.", in: context)
        }
        let path = url.path
        let service = fileSystemService
        return runFileSystemOperation(path: "vscode.workspace.fs.writeFile", in: context, {
            try await service.writeFile(atPath: path, contents: data, create: true, overwrite: true)
        }, resolveWith: { _, context in MainThreadWorkspace.undefinedValue(in: context) })
    }

    /// `readDirectory(uri): Thenable<[string, FileType][]>` — an array of
    /// two-element arrays, matching VS Code's own shape, not an array of
    /// `{name, type}` objects.
    private func handleReadDirectory() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        guard let url = MainThreadWorkspace.requiredURL(from: arguments, at: 0, in: context) else {
            return VSCodeAPI.rejectedPromise(
                message: "vscode.workspace.fs.readDirectory requires a vscode.Uri argument.", in: context)
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
                message: "vscode.workspace.fs.stat requires a vscode.Uri argument.", in: context)
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
                message: "vscode.workspace.fs.delete requires a vscode.Uri argument.", in: context)
        }
        let options = arguments.count > 1 ? arguments[1] : nil
        let recursive = MainThreadWorkspace.boolOption(options, key: "recursive")
        let useTrash = MainThreadWorkspace.boolOption(options, key: "useTrash")
        let path = url.path
        let service = fileSystemService
        return runFileSystemOperation(path: "vscode.workspace.fs.delete", in: context, {
            try await service.delete(atPath: path, recursive: recursive, useTrash: useTrash)
        }, resolveWith: { _, context in MainThreadWorkspace.undefinedValue(in: context) })
    }

    /// `rename(source, target, options?): Thenable<void>`. `overwrite`
    /// defaults `false`, matching VS Code's own documented default.
    private func handleRename() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        guard let fromURL = MainThreadWorkspace.requiredURL(from: arguments, at: 0, in: context),
              let toURL = MainThreadWorkspace.requiredURL(from: arguments, at: 1, in: context) else {
            return VSCodeAPI.rejectedPromise(
                message: "vscode.workspace.fs.rename requires two vscode.Uri arguments.", in: context)
        }
        let options = arguments.count > 2 ? arguments[2] : nil
        let overwrite = options?.forProperty("overwrite")?.toBool() ?? false
        let fromPath = fromURL.path
        let toPath = toURL.path
        let service = fileSystemService
        return runFileSystemOperation(path: "vscode.workspace.fs.rename", in: context, {
            try await service.rename(fromPath: fromPath, toPath: toPath, overwrite: overwrite)
        }, resolveWith: { _, context in MainThreadWorkspace.undefinedValue(in: context) })
    }

    /// `createDirectory(uri): Thenable<void>`.
    private func handleCreateDirectory() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        guard let url = MainThreadWorkspace.requiredURL(from: arguments, at: 0, in: context) else {
            return VSCodeAPI.rejectedPromise(
                message: "vscode.workspace.fs.createDirectory requires a vscode.Uri argument.", in: context)
        }
        let path = url.path
        let service = fileSystemService
        return runFileSystemOperation(path: "vscode.workspace.fs.createDirectory", in: context, {
            try await service.createDirectory(atPath: path)
        }, resolveWith: { _, context in MainThreadWorkspace.undefinedValue(in: context) })
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
    /// `resolve`/`reject` are handed to the `Task` through `SettlementBox`,
    /// not captured directly. `Task.init`'s `operation` closure is checked
    /// against `Sendable`, and a bare `JSValue` — not `Sendable`, and not a
    /// type this module owns to add a conformance to — would be flagged
    /// there even though both values are only ever touched back on the main
    /// actor that created them. `VSCodeAPI.swift`'s own `UncheckedJSValueBox`
    /// is the precedent for this exact shape: an `@unchecked Sendable`
    /// wrapper stating the guarantee the surrounding design already holds,
    /// rather than reaching for a broader escape hatch.
    private func runFileSystemOperation<Value: Sendable>(
        path: String,
        in context: JSContext,
        _ operation: @escaping @Sendable () async throws -> Value,
        resolveWith: @escaping @MainActor (Value, JSContext) -> Any
    ) -> JSValue? {
        JSValue(newPromiseIn: context) { [weak self] resolveValue, rejectValue in
            let settlement = SettlementBox(resolve: resolveValue, reject: rejectValue)
            Task { @MainActor [weak self] in
                guard let self, !self.isDisposed else {
                    MainThreadWorkspace.rejectTornDown(settlement.reject, path: path)
                    return
                }
                do {
                    let result = try await operation()
                    guard let self, !self.isDisposed, let resultContext = settlement.resolve.context else {
                        MainThreadWorkspace.rejectTornDown(settlement.reject, path: path)
                        return
                    }
                    _ = self
                    settlement.resolve.call(withArguments: [resolveWith(result, resultContext)])
                } catch {
                    guard let self, !self.isDisposed, let errorContext = settlement.reject.context else {
                        MainThreadWorkspace.rejectTornDown(settlement.reject, path: path)
                        return
                    }
                    _ = self
                    settlement.reject.call(
                        withArguments: [MainThreadWorkspace.rejectionValue(for: error, in: errorContext)])
                }
            }
        }
    }

    /// Rejects `reject` with the same wording `VSCodeAPI.member`'s own
    /// teardown path uses, so an extension's `catch` sees one consistent
    /// message for "this adaptor is gone" everywhere it can happen.
    private static func rejectTornDown(_ reject: JSValue, path: String) {
        guard let context = reject.context,
              let errorValue = JSValue(
                newErrorFromMessage: "\(path) is unavailable: this extension's host has been torn down.",
                in: context) else {
            return
        }
        reject.call(withArguments: [errorValue])
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
            return MainThreadWorkspace.undefinedValue(in: context)
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

    /// A genuine JavaScript `undefined`, built from whatever context is live
    /// at the call site. Falls back to `NSNull` — JavaScript `null` — only if
    /// `JSValue(undefinedIn:)` itself fails to answer, which nothing observed
    /// while building this adaptor ever caused.
    private static func undefinedValue(in context: JSContext) -> Any {
        if let value = JSValue(undefinedIn: context) {
            return value
        }
        return NSNull()
    }

    /// `Data` to a genuine JavaScript `Uint8Array`. `JSValue` has no direct
    /// bridge from `NSData` to a typed array — `NSData` is absent from
    /// `JSValue`'s own Objective-C conversion table entirely, so an `NSData`
    /// handed across would arrive as an opaque wrapper object, not something
    /// `instanceof Uint8Array` or indexing would work on. Going through a
    /// plain array of byte numbers and `new Uint8Array(...)` is the
    /// unglamorous route that is actually in that table twice over: `NSArray`
    /// bridges to a JavaScript `Array`, and `Uint8Array`'s own constructor
    /// accepts any array-like of numbers.
    private static func uint8ArrayValue(from data: Data, in context: JSContext) -> Any {
        guard let arrayValue = JSValue(object: [UInt8](data), in: context),
              let constructor = context.evaluateScript("(function (bytes) { return new Uint8Array(bytes); })"),
              let result = constructor.call(withArguments: [arrayValue]) else {
            return undefinedValue(in: context)
        }
        return result
    }

    /// A `Uint8Array` argument to `Data`. `JSValue.toArray()` reads `length`
    /// and indexed properties — which a typed array has, same as a plain
    /// array — so it works directly on a `Uint8Array` without a JavaScript
    /// conversion step first.
    private static func data(fromUint8Array value: JSValue) -> Data? {
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
        guard let object = JSValue(newObjectIn: context) else { return undefinedValue(in: context) }
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
    /// or `nil` if the index is out of range or the value is not a
    /// `vscode.Uri`.
    private static func requiredURL(from arguments: [JSValue], at index: Int, in context: JSContext) -> URL? {
        guard arguments.indices.contains(index) else { return nil }
        return VSCodeAPI.url(from: arguments[index], in: context)
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
