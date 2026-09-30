<!-- leaf: implement-extension-host-vs-2/code-api-main-thread-workspace--part-5 · source: extension-host-vs-code-api-main-thread-workspace.md -->

# MainThreadWorkspace — continued (part 5)

## Design Decisions

**Decision**: `fileSystemService` is a single instance shared across every extension's `MainThreadWorkspace`, passed in as a required constructor parameter rather than defaulted or constructed per adaptor.
**Rationale**: `FileSystemService`'s only piece of state that matters here is its serial `DispatchQueue`, which is its whole ordering guarantee for concurrent writes to the same file. One instance per extension would give each extension its own queue — two extensions writing to the same path would interleave at block granularity, and the result would belong to neither extension's own write. Sharing one instance costs a shared throughput ceiling (the trade `FileSystemService`'s own concurrency discussion already accepts) in exchange for that ordering guarantee holding across every extension, not just within one.
**Approved**: pending

**Decision**: `workspaceFolders` and `name` are read live on every access (`ExtensionHost.LiveVSCodeValue`), re-deriving the folder cache from `workspaceRoots.workspaceRootURLs` on each read, rather than snapshotting the answer once.
**Rationale**: extensions activate at app launch, before any project window exists, and an extension's own top-level code typically reads `vscode.workspace.workspaceFolders` during that activation. A snapshot taken at that moment would capture "no roots" and hold it for the rest of the process's life, no matter which project the user later opened — every `workspaceContains:`-shaped extension would be dead on arrival. Re-deriving costs a `[URL]` comparison per read and, because the cache key is the roots themselves rather than "have I run before," also preserves the `getWorkspaceFolder`/`workspaceFolders` object-identity promise for as long as the answer is genuinely unchanged.
**Approved**: pending

**Decision**: `handleGetWorkspaceFolder` and `workspaceFolders` share one cache (`folderEntries(in:)`), rather than each building its own folder objects independently.
**Rationale**: `getWorkspaceFolder`'s documented contract is to answer the same object `workspaceFolders` produced for a given root (`===` in JavaScript), not merely an object with equal fields. Building from independent code paths could not make that promise reliably; reading from one shared, roots-keyed cache is what makes "the same object" true by construction rather than by coincidence.
**Approved**: pending

**Decision**: a workspace root's `URL` is rebuilt as `URL(fileURLWithPath: url.path, isDirectory: false)` before it reaches `VSCodeAPI.uriValue`, rather than passed through as given or through `url.standardizedFileURL`.
**Rationale**: a workspace root's `URL` is built or standardized with `isDirectory: true` (since it names an existing directory), which keeps a trailing `/` in `absoluteString` all the way through `Uri.parse` and out through `.fsPath`. Real VS Code's `fsPath` never carries a trailing slash for any root, so leaving it in would make every extension that compares `folder.uri.fsPath` against its own idea of the root see a spurious mismatch on every real workspace. `url.standardizedFileURL` was rejected as the fix because it also resolves `..` and strips a leading `/private` whenever the collapsed result currently exists on disk — a root's `fsPath` would then depend on whether the directory happened to exist at the moment this code ran, not on the path it was given. Rebuilding from `url.path` (which already carries no trailing slash) with `isDirectory: false` removes exactly the trailing-slash marker and nothing else. `handleGetWorkspaceFolder`'s own matcher standardizes deliberately, for the opposite reason: collapsing `/private/var/foo` and `/var/foo` onto the same root is exactly what a *comparison* wants, even though it is wrong for a value being *handed back* as `fsPath`.
**Approved**: pending

**Decision**: `delete`'s `recursive` and `useTrash` options both default to `false` when the caller omits `options`.
**Rationale**: a permanent, non-recursive delete is the conservative reading when no option is given. The source's own comment marks this as a best-effort guess rather than a confirmed reading of VS Code's own documentation for `vscode.workspace.fs.delete`. Parity with VS Code's own `FileDeleteOptions` defaults is therefore asserted by this host, not cited from `vscode.d.ts`.
**Approved**: pending

**Decision**: `data(fromUint8Array:)` keeps a plain-array fallback (`numbersData(from:)`) alongside the typed-array fast path, rather than rejecting anything that is not a genuine `Uint8Array`.
**Rationale**: `vscode.d.ts` declares `writeFile`'s `content` parameter as `Uint8Array`, and that is what the fast path reads. But `JSValue.toArray()` accepted a plain `[1, 2, 3]` before the fast path existed, and an extension that already passes one is writing a file today. Narrowing what is accepted is a separate decision from making the declared shape cheap to read, and this change is only the second.
**Approved**: pending

**Decision**: one instance per extension (matching `ExtensionHost` and `MainThreadCommands`) is a convention this adaptor documents but does not enforce at runtime.
**Rationale**: enforcing it would mean either a static registry mapping `JSContext` to adaptor instance (adding a second bookkeeping structure this file's owner would then have to keep synchronized with `ExtensionHost`'s own one-per-extension lifecycle) or a runtime check with no clear failure action beyond logging — and this file already delegates dispatch bookkeeping to its owner (`ExtensionHost`/`ExtensionHostInstaller.Collaborators`) rather than duplicating it. The convention is instead the contract this recipe states outright (**required-collaborators-no-defaults**, and the class's own "one instance per extension" doc), leaving detection to the owner that actually constructs one `MainThreadWorkspace` per `ExtensionHost`.
**Approved**: pending
