<!-- leaf: implement-extension-host-vs-2/code-api-main-thread-workspace--part-2 · source: extension-host-vs-code-api-main-thread-workspace.md -->

# MainThreadWorkspace — continued (part 2)

**Rules** (cite as `implement-extension-host-vs-2/code-api-main-thread-workspace--part-2#<slug>`):

- `main-actor-isolation` MUST
- `required-collaborators-no-defaults` MUST
- `file-system-service-is-shared-not-per-extension` MUST
- `name-resolves-the-live-display-name` MUST
- `name-resolves-to-undefined-when-absent` MUST
- `workspace-folders-resolves-to-undefined-when-empty` MUST
- `workspace-folders-resolves-one-entry-per-root` MUST
- `folder-entry-uri-is-a-real-vscode-uri` MUST
- `folder-entry-uri-has-no-trailing-slash` MUST
- `folder-entry-uri-preserves-a-private-prefix` MUST
- `folder-entry-name-is-the-last-path-component` MUST
- `folder-entry-index-matches-position` MUST
- `folder-cache-rebuilds-only-when-roots-change` MUST
- `folder-cache-distinguishes-empty-from-unbuilt` MUST
- `get-workspace-folder-answers-undefined-for-a-missing-argument` MUST
- `get-workspace-folder-matches-the-longest-containing-root` MUST
- `get-workspace-folder-answers-the-same-object-workspace-folders-produced` MUST
- `get-workspace-folder-answers-undefined-outside-every-root` MUST
- `get-workspace-folder-is-synchronous-and-raises-on-teardown` MUST
- `fs-is-a-deferred-sub-namespace-with-seven-members` MUST
- `fs-miss-and-probe-recording-is-wired` MUST
- `each-fs-member-rejects-on-teardown` MUST
- `read-file-requires-a-file-uri` MUST
- `read-file-resolves-a-real-uint8array` MUST
- `write-file-requires-a-file-uri` MUST
- `write-file-requires-a-uint8array-second-argument` MUST
- `write-file-always-creates-and-overwrites` MUST
- `read-directory-requires-a-file-uri` MUST
- `read-directory-resolves-two-element-tuples` MUST
- `stat-requires-a-file-uri` MUST
- `stat-resolves-the-filestat-shape` MUST
- `delete-requires-a-file-uri` MUST
- `delete-options-default-both-false` MUST
- `rename-requires-two-file-uris` MUST

## Behavioral Requirements

- **main-actor-isolation**: `MainThreadWorkspace` MUST be declared `@MainActor`; every stored property read and write and every method body MUST execute on the main actor.
- **required-collaborators-no-defaults**: `init(workspaceRoots:notImplementedLedger:extensionIdentifier:fileSystemService:)` MUST declare all four parameters with no default value, so a caller cannot silently construct an adaptor with a private workspace, a lost ledger, or a private `FileSystemServicing` instance.
- **file-system-service-is-shared-not-per-extension**: the `fileSystemService` a caller supplies MUST be the one instance shared across every extension's `MainThreadWorkspace`, because `FileSystemService`'s serial queue is what orders two extensions' concurrent writes to the same path into one winner's bytes landing whole; an instance per extension gives two independent queues and no ordering guarantee between them.
- **name-resolves-the-live-display-name**: `name` MUST be an `ExtensionHost.LiveVSCodeValue` that, on each resolution, reads `workspaceRoots?.workspaceDisplayName` and returns that `String` unchanged when it is non-`nil`.
- **name-resolves-to-undefined-when-absent**: `name` MUST resolve to `JSValueBridge.undefinedOrNull(in:)` when `workspaceRoots` is `nil` or `workspaceRoots?.workspaceDisplayName` is `nil`.
- **workspace-folders-resolves-to-undefined-when-empty**: `workspaceFolders` MUST resolve to `JSValueBridge.undefinedOrNull(in:)` when `workspaceRoots` is `nil` or `workspaceRoots.workspaceRootURLs` is empty, MUST NOT resolve to an empty JavaScript array in that case.
- **workspace-folders-resolves-one-entry-per-root**: `workspaceFolders` MUST resolve to an array with one `{uri, name, index}` object per URL in `workspaceRoots.workspaceRootURLs`, in that array's own order.
- **folder-entry-uri-is-a-real-vscode-uri**: each `workspaceFolders` entry's `uri` MUST be built by `VSCodeAPI.uriValue(for:in:)`, the same call `vscode.Uri` itself uses, so `instanceof vscode.Uri` and `.fsPath` both work on it.
- **folder-entry-uri-has-no-trailing-slash**: each `workspaceFolders` entry's `uri.fsPath` MUST equal the root `URL`'s `.path` exactly, with no trailing `/`, even when the root `URL` was constructed or standardized with `isDirectory: true`.
- **folder-entry-uri-preserves-a-private-prefix**: each `workspaceFolders` entry's `uri.fsPath` MUST NOT go through `URL.standardizedFileURL`, so a root whose literal path begins `/private/` keeps that prefix in `fsPath` regardless of whether the collapsed `/var/...` path currently exists on disk.
- **folder-entry-name-is-the-last-path-component**: each `workspaceFolders` entry's `name` MUST equal the root `URL`'s `lastPathComponent`.
- **folder-entry-index-matches-position**: each `workspaceFolders` entry's `index` MUST equal its zero-based position in `workspaceRoots.workspaceRootURLs`.
- **folder-cache-rebuilds-only-when-roots-change**: `folderEntries(in:)` MUST return the cached `[WorkspaceFolderEntry]` unchanged when the current `workspaceRoots.workspaceRootURLs` (or `[]` when `workspaceRoots` is `nil`) equals `cachedFolderURLs`, and MUST rebuild the array, then overwrite both `cachedFolderEntries` and `cachedFolderURLs`, whenever it differs.
- **folder-cache-distinguishes-empty-from-unbuilt**: `cachedFolderURLs` MUST be `nil` before `folderEntries(in:)` has ever run and MUST be `[]` (not `nil`) after it has run with zero roots, so a read taken before a project opens does not permanently pin "no roots" for the life of the process.
- **get-workspace-folder-answers-undefined-for-a-missing-argument**: `handleGetWorkspaceFolder` MUST return `JSValue(undefinedIn:)` when `VSCodeAPI.currentArguments()` has no first element or that element does not resolve to a `URL` via `VSCodeAPI.url(from:in:)`.
- **get-workspace-folder-matches-the-longest-containing-root**: `handleGetWorkspaceFolder` MUST, among every cached folder entry whose `url.standardizedFileURL.path` equals the argument's `standardizedFileURL.path` or is a path-component-boundary prefix of it (comparing against `rootPath` with a trailing `/` appended, never a bare string prefix), return the entry whose `rootPath.count` is greatest.
- **get-workspace-folder-answers-the-same-object-workspace-folders-produced**: on a match, `handleGetWorkspaceFolder` MUST return the same `JSValue` instance (`===` in JavaScript) that `workspaceFolders` resolved to for that root, by reading both from the one cache `folderEntries(in:)` maintains.
- **get-workspace-folder-answers-undefined-outside-every-root**: `handleGetWorkspaceFolder` MUST return `JSValue(undefinedIn:)` when no cached folder entry contains the argument path.
- **get-workspace-folder-is-synchronous-and-raises-on-teardown**: `getWorkspaceFolder` MUST be built with `VSCodeAPI.member(..., whenTornDown: .raisedException, ...)`, answering `WorkspaceFolder | undefined` directly rather than a `Thenable`.
- **fs-is-a-deferred-sub-namespace-with-seven-members**: `fs` MUST be an `ExtensionHost.DeferredVSCodeValue` that installs exactly `readFile`, `writeFile`, `readDirectory`, `stat`, `delete`, `rename`, and `createDirectory` via `VSCodeAPI.subNamespace(path:members:in:recordMiss:recordProbe:)`.
- **fs-miss-and-probe-recording-is-wired**: the `recordMiss` and `recordProbe` closures passed to `VSCodeAPI.subNamespace` for `fs` MUST call `notImplementedLedger.record(memberPath:extensionIdentifier:)` and `notImplementedLedger.recordProbe(memberPath:extensionIdentifier:)` respectively, each with this adaptor's own `extensionIdentifier`, so every reach for an undefined `vscode.workspace.fs` member is recorded under `vscode.workspace.fs.<name>` in the same ledger every other namespace's misses share.
- **each-fs-member-rejects-on-teardown**: `readFile`, `writeFile`, `readDirectory`, `stat`, `delete`, `rename`, and `createDirectory` MUST each be built with `VSCodeAPI.member(..., whenTornDown: .rejectedPromise, ...)`.
- **read-file-requires-a-file-uri**: `handleReadFile` MUST return `VSCodeAPI.rejectedPromise(message: "vscode.workspace.fs.readFile requires a file-scheme vscode.Uri argument.", in:)` when the first argument is missing or is not a `file:`-scheme `vscode.Uri`.
- **read-file-resolves-a-real-uint8array**: on success, `handleReadFile` MUST resolve the returned promise with a value built by `uint8ArrayValue(from:in:)`, a genuine JavaScript `Uint8Array` (`instanceof Uint8Array` MUST be `true`) carrying the file's bytes unchanged, including byte values `0` and `255`.
- **write-file-requires-a-file-uri**: `handleWriteFile` MUST return `VSCodeAPI.rejectedPromise(message: "vscode.workspace.fs.writeFile requires a file-scheme vscode.Uri argument.", in:)` when the first argument is missing or is not a `file:`-scheme `vscode.Uri`.
- **write-file-requires-a-uint8array-second-argument**: `handleWriteFile` MUST return `VSCodeAPI.rejectedPromise(message: "vscode.workspace.fs.writeFile requires a Uint8Array of contents.", in:)` when a second argument is missing or `data(fromUint8Array:)` cannot decode it.
- **write-file-always-creates-and-overwrites**: `handleWriteFile` MUST call `fileSystemService.writeFile(atPath:contents:create:overwrite:)` with `create: true` and `overwrite: true` unconditionally; `vscode.workspace.fs.writeFile` in this adaptor MUST NOT accept or read any options argument.
- **read-directory-requires-a-file-uri**: `handleReadDirectory` MUST return `VSCodeAPI.rejectedPromise(message: "vscode.workspace.fs.readDirectory requires a file-scheme vscode.Uri argument.", in:)` when the first argument is missing or is not a `file:`-scheme `vscode.Uri`.
- **read-directory-resolves-two-element-tuples**: on success, `handleReadDirectory` MUST resolve the returned promise with an array of two-element arrays, `[name, type.rawValue]` per `FileSystemService.DirectoryEntry`, MUST NOT resolve with an array of `{name, type}` objects.
- **stat-requires-a-file-uri**: `handleStat` MUST return `VSCodeAPI.rejectedPromise(message: "vscode.workspace.fs.stat requires a file-scheme vscode.Uri argument.", in:)` when the first argument is missing or is not a `file:`-scheme `vscode.Uri`.
- **stat-resolves-the-filestat-shape**: on success, `handleStat` MUST resolve the returned promise with a `{type, ctime, mtime, size}` object, where `type` is `FileSystemService.FileStat.type.rawValue` unchanged, `size` is `FileSystemService.FileStat.size` unchanged, and `ctime`/`mtime` are each `creationDate`/`modificationDate` converted to milliseconds since the epoch (`timeIntervalSince1970 * 1000`), or `0` when the corresponding `Date?` is `nil`.
- **delete-requires-a-file-uri**: `handleDelete` MUST return `VSCodeAPI.rejectedPromise(message: "vscode.workspace.fs.delete requires a file-scheme vscode.Uri argument.", in:)` when the first argument is missing or is not a `file:`-scheme `vscode.Uri`.
- **delete-options-default-both-false**: `handleDelete` MUST read `recursive` and `useTrash` from an optional second `options` argument via `boolOption(_:key:)`, defaulting each to `false` when `options` is absent, the corresponding property is absent, or the property is not something `toBool()` can read.
- **rename-requires-two-file-uris**: `handleRename` MUST return `VSCodeAPI.rejectedPromise(message: "vscode.workspace.fs.rename requires two file-scheme vscode.Uri arguments.", in:)` when either the first or second argument is missing or is not a `file:`-scheme `vscode.Uri`.
