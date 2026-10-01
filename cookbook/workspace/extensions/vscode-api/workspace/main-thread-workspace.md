---
id: 1cacbe17-bca6-458c-bf1f-df9efa3652be
title: VS Code Workspace Bridge
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api/workspace/main-thread-workspace
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The extension host''s vscode.workspace bridge: name, workspaceFolders,
  getWorkspaceFolder, and the seven fs operations, terminating in the app''s own
  filesystem service and workspace roots.'
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- workspace
- filesystem
depends-on: []
related:
- agentictoolkit://cookbook/workspace/extensions/host/extension-host
- agentictoolkit://cookbook/workspace/extensions/vscode-api/commands/main-thread-commands
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWorkspace.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/VSCodeAPI.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/JSValueBridge.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Host/ExtensionHost.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/FileSystem/FileSystemService.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/FileSystem/FileSystemServicing.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/MainThreadWorkspaceTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

# VS Code Workspace Bridge

## Overview

This bridge is the extension host's `vscode.workspace` counterpart: `name`, `workspaceFolders`, `getWorkspaceFolder`, and the seven `fs` operations (`readFile`, `writeFile`, `readDirectory`, `stat`, `delete`, `rename`, `createDirectory`). `name` and `workspaceFolders` read a narrow collaborator contract, `ExtensionWorkspaceRoots` (`workspaceDisplayName`, `workspaceRootURLs`), rather than the app's full project-workspace model, so this bridge's dependency surface on the app's project model is exactly two fields, not the app's much larger project state. Every `fs` member terminates in a required `FileSystemServicing` instance, shared across every extension's bridge rather than one per extension, so that the app's own shared filesystem service's serial ordering — not two independent orderings — orders concurrent writes to the same file. The component executes on a single, consistent execution context, matching every other bridge in this module, and is meant as **one instance per extension**, mirroring the extension-host bridge above this contract and the sibling commands bridge: nothing in the type enforces that, but the folder-entry cache's promise of a stable `getWorkspaceFolder`/`workspaceFolders` object identity depends on it. `name` and `workspaceFolders` are read live on every access rather than snapshotted at construction, because extensions activate at app launch, ahead of any project window, and a snapshot taken then would freeze "no workspace" for the process's whole life. Whoever owns this bridge must call `dispose()` when it tears the extension host down; an `fs` operation already in flight when that happens is left to finish on disk, but its promise rejects instead of resolving into a torn-down extension.

## Behavioral Requirements

- **single-context-execution**: this component MUST execute every stored-property read and write and every method body on a single, consistent execution context.
- **required-collaborators-no-defaults**: construction MUST require all four collaborators — the workspace roots, the not-implemented ledger, the extension identifier, and the filesystem service — with no default value, so a caller cannot silently construct a bridge with a private workspace, a lost ledger, or a private filesystem-service instance.
- **file-system-service-is-shared-not-per-extension**: the filesystem service a caller supplies MUST be the one instance shared across every extension's bridge, because that shared instance's own serial ordering is what orders two extensions' concurrent writes to the same path into one winner's bytes landing whole; an instance per extension gives two independent orderings and no guarantee between them.
- **name-resolves-the-live-display-name**: `name` MUST be a value that is resolved live on each access, reading `workspaceRoots?.workspaceDisplayName` and returning that string unchanged when it is non-null.
- **name-resolves-to-undefined-when-absent**: `name` MUST resolve to the JavaScript `undefined` value when `workspaceRoots` is null or `workspaceRoots?.workspaceDisplayName` is null.
- **workspace-folders-resolves-to-undefined-when-empty**: `workspaceFolders` MUST resolve to the JavaScript `undefined` value when `workspaceRoots` is null or `workspaceRoots.workspaceRootURLs` is empty, MUST NOT resolve to an empty JavaScript array in that case.
- **workspace-folders-resolves-one-entry-per-root**: `workspaceFolders` MUST resolve to an array with one `{uri, name, index}` object per root in `workspaceRoots.workspaceRootURLs`, in that array's own order.
- **folder-entry-uri-is-a-real-vscode-uri**: each `workspaceFolders` entry's `uri` MUST be built the same way `vscode.Uri` itself is constructed elsewhere in this bridge, so `instanceof vscode.Uri` and `.fsPath` both work on it.
- **folder-entry-uri-has-no-trailing-slash**: each `workspaceFolders` entry's `uri.fsPath` MUST equal the root path exactly, with no trailing `/`, even when the root path was constructed or standardized as a directory path.
- **folder-entry-uri-preserves-a-private-prefix**: each `workspaceFolders` entry's `uri.fsPath` MUST NOT be passed through standard path resolution, so a root whose literal path begins `/private/` keeps that prefix in `fsPath` regardless of whether the collapsed `/var/...` path currently exists on disk.
- **folder-entry-name-is-the-last-path-component**: each `workspaceFolders` entry's `name` MUST equal the last path component of the root path.
- **folder-entry-index-matches-position**: each `workspaceFolders` entry's `index` MUST equal its zero-based position in `workspaceRoots.workspaceRootURLs`.
- **folder-cache-rebuilds-only-when-roots-change**: the folder-entry cache MUST return its cached entries unchanged when the current `workspaceRoots.workspaceRootURLs` (or an empty list, when `workspaceRoots` is null) equals the cached root list, and MUST rebuild the array, then overwrite both the cached entries and the cached root list, whenever it differs.
- **folder-cache-distinguishes-empty-from-unbuilt**: the folder-entry cache's own record of which roots it was built from MUST be distinguishable from "not yet built" before the cache has ever run, and MUST be recorded as "built with zero roots" (not "unbuilt") once it has run with zero roots, so a read taken before a project opens does not permanently pin "no roots" for the life of the process.
- **get-workspace-folder-answers-undefined-for-a-missing-argument**: `getWorkspaceFolder` MUST answer the JavaScript `undefined` value when it is called with no first argument or that argument does not resolve to a URL.
- **get-workspace-folder-matches-the-longest-containing-root**: `getWorkspaceFolder` MUST, among every cached folder entry whose path equals the argument's path or is a path-component-boundary prefix of it (a real path-segment boundary, never a bare string prefix), return the entry whose path is longest.
- **get-workspace-folder-answers-the-same-object-workspace-folders-produced**: on a match, `getWorkspaceFolder` MUST return the exact same object (`===` in JavaScript) that `workspaceFolders` resolved to for that root, by reading both from the one shared folder-entry cache.
- **get-workspace-folder-answers-undefined-outside-every-root**: `getWorkspaceFolder` MUST answer the JavaScript `undefined` value when no cached folder entry contains the argument path.
- **get-workspace-folder-is-synchronous-and-raises-on-teardown**: `getWorkspaceFolder` MUST be a synchronous member that raises an exception, rather than rejecting a promise, when the bridge has already been torn down, answering `WorkspaceFolder | undefined` directly rather than a `Thenable`.
- **fs-is-a-deferred-sub-namespace-with-seven-members**: `fs` MUST be a lazily-installed sub-namespace exposing exactly `readFile`, `writeFile`, `readDirectory`, `stat`, `delete`, `rename`, and `createDirectory`.
- **fs-miss-and-probe-recording-is-wired**: reaching for an undefined member and merely probing for one (for example `'copy' in vscode.workspace.fs`) MUST each be recorded in the not-implemented ledger, keyed by this bridge's own extension identifier, so every reach for an undefined `vscode.workspace.fs` member is recorded under `vscode.workspace.fs.<name>` in the same ledger every other namespace's misses share.
- **each-fs-member-rejects-on-teardown**: `readFile`, `writeFile`, `readDirectory`, `stat`, `delete`, `rename`, and `createDirectory` MUST each reject their returned promise, rather than raising an exception, when the bridge has already been torn down.
- **read-file-requires-a-file-uri**: `readFile` MUST reject its returned promise with the message "vscode.workspace.fs.readFile requires a file-scheme vscode.Uri argument." when the first argument is missing or is not a `file:`-scheme `vscode.Uri`.
- **read-file-resolves-a-real-uint8array**: on success, `readFile` MUST resolve the returned promise with a genuine JavaScript `Uint8Array` (`instanceof Uint8Array` MUST be `true`) carrying the file's bytes unchanged, including byte values `0` and `255`.
- **write-file-requires-a-file-uri**: `writeFile` MUST reject its returned promise with the message "vscode.workspace.fs.writeFile requires a file-scheme vscode.Uri argument." when the first argument is missing or is not a `file:`-scheme `vscode.Uri`.
- **write-file-requires-a-uint8array-second-argument**: `writeFile` MUST reject its returned promise with the message "vscode.workspace.fs.writeFile requires a Uint8Array of contents." when a second argument is missing or cannot be decoded as byte data.
- **write-file-always-creates-and-overwrites**: `writeFile` MUST tell the filesystem service to create the file when it does not exist and to overwrite it when it does, unconditionally; `vscode.workspace.fs.writeFile` in this bridge MUST NOT accept or read any options argument.
- **read-directory-requires-a-file-uri**: `readDirectory` MUST reject its returned promise with the message "vscode.workspace.fs.readDirectory requires a file-scheme vscode.Uri argument." when the first argument is missing or is not a `file:`-scheme `vscode.Uri`.
- **read-directory-resolves-two-element-tuples**: on success, `readDirectory` MUST resolve the returned promise with an array of two-element arrays, `[name, type]`, built from the filesystem service's own directory-entry values, MUST NOT resolve with an array of `{name, type}` objects.
- **stat-requires-a-file-uri**: `stat` MUST reject its returned promise with the message "vscode.workspace.fs.stat requires a file-scheme vscode.Uri argument." when the first argument is missing or is not a `file:`-scheme `vscode.Uri`.
- **stat-resolves-the-filestat-shape**: on success, `stat` MUST resolve the returned promise with a `{type, ctime, mtime, size}` object, where `type` and `size` come from the filesystem service's own file-stat values unchanged, and `ctime`/`mtime` are each the creation or modification timestamp converted to milliseconds since the epoch, or `0` when that timestamp is unavailable.
- **delete-requires-a-file-uri**: `delete` MUST reject its returned promise with the message "vscode.workspace.fs.delete requires a file-scheme vscode.Uri argument." when the first argument is missing or is not a `file:`-scheme `vscode.Uri`.
- **delete-options-default-both-false**: `delete` MUST read `recursive` and `useTrash` from an optional second `options` argument, defaulting each to `false` when `options` is absent, the corresponding property is absent, or the property cannot be read as a boolean.
- **rename-requires-two-file-uris**: `rename` MUST reject its returned promise with the message "vscode.workspace.fs.rename requires two file-scheme vscode.Uri arguments." when either the first or second argument is missing or is not a `file:`-scheme `vscode.Uri`.
- **rename-overwrite-defaults-false**: `rename` MUST read `overwrite` from an optional third `options` argument, defaulting to `false` when it is absent or cannot be read as a boolean.
- **create-directory-requires-a-file-uri**: `createDirectory` MUST reject its returned promise with the message "vscode.workspace.fs.createDirectory requires a file-scheme vscode.Uri argument." when the first argument is missing or is not a `file:`-scheme `vscode.Uri`.
- **required-url-rejects-non-file-schemes**: the shared URI-validation step every `fs` member uses MUST treat a `vscode.Uri` as invalid when it is not a genuine file-system URI, including a scheme-relative string and any non-`file` scheme, even when the general URI-parsing step used elsewhere in this bridge successfully parses that value for a non-filesystem caller.
- **file-system-operations-run-off-a-genuine-pending-promise**: every `fs` operation MUST build its returned promise as a genuinely pending JavaScript promise, MUST start the underlying work as an asynchronous operation, and MUST NOT resolve or reject that promise synchronously before that operation begins running.
- **operation-checks-teardown-before-running**: every `fs` operation MUST reject with the fixed "torn down" wording, and MUST NOT run the underlying operation at all, when the bridge has already been deallocated or torn down before the asynchronous operation's first turn.
- **operation-checks-teardown-after-running**: every `fs` operation MUST reject with the same "torn down" wording, and MUST NOT deliver the underlying operation's result, when the bridge was deallocated or torn down while that operation was in flight, even though the operation itself completed successfully.
- **operation-error-mapping-uses-filesystemserviceerror-description**: the rejected error's `message` MUST come from `FileSystemServiceError`'s own description when the thrown error is a `FileSystemServiceError`, and from that error's default string description for any other error type.
- **operation-error-mapping-sets-a-code-only-for-classified-errors**: the rejected error's `code` property MUST be set to a mapped VS Code error code when the thrown error is a `FileSystemServiceError`, and MUST be left unset for any other error type.
- **error-code-mapping-is-fixed**: the error-code mapping MUST map file-not-found to `"FileNotFound"`, file-exists to `"FileExists"`, file-is-a-directory to `"FileIsADirectory"`, file-not-a-directory to `"FileNotADirectory"`, and no-permissions to `"NoPermissions"`, and MUST map directory-not-empty and every generic operation-failed case (read, write, stat, read-directory, delete, rename, create-directory) to `"Unavailable"`.
- **uint8array-bridging-adopts-the-buffer-with-no-per-byte-boxing**: converting file bytes into a `Uint8Array` MUST copy the underlying bytes into the returned array's buffer exactly once, and MUST NOT bridge through a byte-by-byte boxed-number intermediate.
- **uint8array-bridging-frees-on-failure**: this bridging MUST free the raw buffer itself and resolve to the JavaScript `undefined` value when the underlying typed-array construction fails.
- **uint8array-deallocator-runs-off-the-primary-context**: the deallocator this bridging registers for the typed array's buffer MUST be able to run outside this component's own single execution context, because the underlying JavaScript engine invokes it from its own garbage-collector thread, never from that context.
- **uint8array-decoding-prefers-the-typed-array-fast-path**: decoding a `Uint8Array` argument MUST read its bytes directly and copy them once into the resulting byte data, without boxing each byte as a separate object, whenever the argument is genuinely a `Uint8Array`.
- **uint8array-decoding-falls-back-for-plain-arrays**: decoding MUST fall back to reading the argument as a plain array of numbers and converting each element to a byte value, when the argument has no active JavaScript context, is not a `Uint8Array`, or is any other array-like value; this fallback MUST accept a plain JavaScript array of byte numbers.
- **operation-value-type-must-be-thread-safe**: the generic operation this bridge runs for each `fs` member MUST produce a thread-safe result value, and the closure that delivers that result back MUST itself run on this component's own single execution context, so a value that is not safe to move across execution contexts is never captured directly by the asynchronous operation.
- **promise-settlement-crosses-contexts-through-a-box**: every `fs` operation MUST capture the promise's resolve and reject functions for its asynchronous operation through an intermediate box, never as a bare direct capture, and each captured pair MUST be used only on the single execution context that created it.
- **dispose-marks-torn-down-and-nothing-else**: `dispose()` MUST mark the bridge torn down and MUST NOT attempt to unregister `fs`, `workspaceFolders`, `name`, or `getWorkspaceFolder` from any registry, because those four are installed directly into the shim's member table by whoever installs this bridge, and that table is owned and torn down by the extension-host bridge above this contract, not by this component.
- **logging-conformance**: this component MUST support the shared logging contract every bridge in this module implements, exposing a logger built the same way every sibling bridge builds its own.

## Appearance

Not applicable — this is the extension host's `vscode.workspace` bridge, not a visual component.

## States

Not applicable — this is the extension host's `vscode.workspace` bridge, not a visual component. Its only lifecycle-shaped behavior is the constructed-versus-disposed status of the bridge itself, captured under Behavioral Requirements (`dispose-marks-torn-down-and-nothing-else`, `operation-checks-teardown-before-running`, `operation-checks-teardown-after-running`) rather than as a visual-state table.

## Accessibility

Not applicable — this is the extension host's `vscode.workspace` bridge, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| main-thread-workspace-001 | read-file-resolves-a-real-uint8array | `fs.readFile(Uri.file(path))` against a file containing bytes `[0, 1, 127, 128, 255]` | The promise resolves with a value where `bytes instanceof Uint8Array` is `true`, `bytes.length === 5`, and `Array.from(bytes)` equals `[0, 1, 127, 128, 255]` |
| main-thread-workspace-002 | write-file-always-creates-and-overwrites | `fs.writeFile(Uri.file(path), new Uint8Array([9, 8, 7, 0, 255]))` against a path with no existing file | The promise resolves, and reading the file from disk afterward yields exactly `[9, 8, 7, 0, 255]` |
| main-thread-workspace-003 | read-directory-resolves-two-element-tuples | `fs.readDirectory(Uri.file(dir))` against a directory containing file `a.txt` and subdirectory `sub` | The promise resolves with an array of two two-element entries; as an unordered set the entries equal `["a.txt:1", "sub:2"]` (`FileType.file.rawValue == 1`, `FileType.directory.rawValue == 2`) |
| main-thread-workspace-004 | stat-resolves-the-filestat-shape | `fs.stat(Uri.file(path))` against an 11-byte file created, then (after a delay) overwritten in place | The promise resolves with `type === 1`, `size === 11`, `ctime` inside the file's creation-time window, and `mtime` inside the later modification-time window (the two windows do not overlap) |
| main-thread-workspace-005 | delete-options-default-both-false (delegated result) | `fs.delete(Uri.file(path))` with no options argument, against an existing plain file | The promise resolves, and the path no longer exists on disk afterward |
| main-thread-workspace-006 | rename-overwrite-defaults-false (delegated result) | `fs.rename(Uri.file(source), Uri.file(target))` with no options argument, `source` containing `"payload"`, `target` not existing | The promise resolves; `source` no longer exists on disk, and `target`'s contents equal `"payload"` |
| main-thread-workspace-007 | write-file-always-creates-and-overwrites (delegated result) | `fs.createDirectory(Uri.file(nested/child))` against a path whose parent does not yet exist | The promise resolves, and the target path exists on disk as a directory afterward |
| main-thread-workspace-008 | error-code-mapping-is-fixed | `fs.readFile(Uri.file(path))` where `path` does not exist | The promise rejects with `error.code === "FileNotFound"` |
| main-thread-workspace-009 | error-code-mapping-is-fixed | `fs.readFile(Uri.file(dir))` where `dir` is a directory | The promise rejects with `error.code === "FileIsADirectory"` |
| main-thread-workspace-010 | error-code-mapping-is-fixed | `fs.readDirectory(Uri.file(path))` where `path` is a plain file | The promise rejects with `error.code === "FileNotADirectory"` |
| main-thread-workspace-011 | error-code-mapping-is-fixed | `fs.createDirectory(Uri.file(path))` where `path` is already occupied by a plain file | The promise rejects with `error.code === "FileExists"` |
| main-thread-workspace-012 | error-code-mapping-is-fixed | `fs.readFile(Uri.file(path))` where `path`'s POSIX mode is `0o000` | The promise rejects with `error.code === "NoPermissions"` |
| main-thread-workspace-013 | error-code-mapping-is-fixed | `fs.delete(Uri.file(dir))` where `dir` is non-empty and no `recursive` option is passed | The promise rejects with `error.code === "Unavailable"` |
| main-thread-workspace-014 | workspace-folders-resolves-to-undefined-when-empty | `vscode.workspace.workspaceFolders` read with no workspace open | `vscode.workspace.workspaceFolders === undefined` is `true` |
| main-thread-workspace-015 | folder-entry-uri-is-a-real-vscode-uri, folder-entry-name-is-the-last-path-component, folder-entry-index-matches-position | `vscode.workspace.workspaceFolders` read with one root `root-one` | `folders.length === 1`, `folders[0].uri instanceof vscode.Uri`, `folders[0].uri.fsPath` equals the root's path, `folders[0].name === "root-one"`, `folders[0].index === 0` |
| main-thread-workspace-016 | folder-entry-uri-has-no-trailing-slash | `vscode.workspace.workspaceFolders[0].uri.fsPath` read for a root nested three directories deep | `fsPath` equals the root path exactly and `fsPath.hasSuffix("/")` is `false` |
| main-thread-workspace-017 | folder-entry-uri-preserves-a-private-prefix | `vscode.workspace.workspaceFolders[0].uri.fsPath` read for a root created at a literal `/private/...` path | `fsPath` equals the root's literal path and `fsPath.hasPrefix("/private/")` is `true` |
| main-thread-workspace-018 | name-resolves-the-live-display-name | `vscode.workspace.name` read with `workspaceRoots.workspaceDisplayName == "My Project"` | `vscode.workspace.name === "My Project"` |
| main-thread-workspace-019 | name-resolves-to-undefined-when-absent | `vscode.workspace.name` read with no workspace open | `vscode.workspace.name === undefined` is `true` and `vscode.workspace.name === null` is `false` |
| main-thread-workspace-020 | get-workspace-folder-answers-the-same-object-workspace-folders-produced | `vscode.workspace.getWorkspaceFolder(Uri.file(fileInsideRoot))` for a file directly inside the one registered root | The returned object is `===` to `vscode.workspace.workspaceFolders[0]`, and its `name` equals the root's name |
| main-thread-workspace-021 | get-workspace-folder-matches-the-longest-containing-root | roots `["outer", "outer/inner"]` (outer registered first); query a file under `outer/inner` and a sibling file under `outer/inner-extra` | The `outer/inner` file's folder has `name === "inner"`; the `outer/inner-extra` file's folder has `name === "outer"` (not falsely matched to `inner` by string prefix) |
| main-thread-workspace-022 | get-workspace-folder-answers-undefined-outside-every-root | `vscode.workspace.getWorkspaceFolder(Uri.file(outsidePath))` for a path outside the one registered root | The call answers `undefined` |
| main-thread-workspace-023 | fs-is-a-deferred-sub-namespace-with-seven-members, fs-miss-and-probe-recording-is-wired | probe `'copy' in vscode.workspace.fs`, then call `vscode.workspace.fs.copy(a, b)` | The probe is `false`; the call throws `NotImplementedError`; `notImplementedLedger.accesses` has exactly one entry for `vscode.workspace.fs.copy` with `count === 1` and `probeCount === 1` |
| main-thread-workspace-024 | operation-checks-teardown-before-running | call `fs.readFile(...)`, attach `.then`, then call `workspace.dispose()` before the underlying asynchronous operation has had its first turn | The promise rejects with a message containing `"torn down"` rather than resolving with the file's real contents |
| main-thread-workspace-025 | operation-checks-teardown-after-running | call `fs.readFile(...)` against a filesystem-service double whose `readFile` suspends until released; wait for it to enter, call `workspace.dispose()`, then release it | The promise rejects with a message containing `"torn down"`, even though the underlying operation completed successfully after disposal |

## Edge Cases

- **Null/empty input**: `vscode.workspace.workspaceFolders` read with zero workspace roots MUST resolve to `undefined`, never `[]`, per **workspace-folders-resolves-to-undefined-when-empty** (MUST).
- **Null/empty input**: `getWorkspaceFolder(uri)` called with zero arguments MUST answer `undefined` (the string-and-first-argument guard fails identically to a non-`vscode.Uri` first argument), per **get-workspace-folder-answers-undefined-for-a-missing-argument** (MUST).
- **Null/empty input**: `getWorkspaceFolder` MUST answer the JavaScript `undefined` value, rather than raising, when there is no active JavaScript context to answer into; this is a defensive guard for a condition that does not arise on an ordinary JavaScript-triggered call, not a distinct error path with its own message (fact).
- **Boundary values**: a workspace root equal to the filesystem root or the empty-string last path component is not specially rejected; the folder-entry cache builds an entry for any root the roots object supplies, with no minimum- or maximum-length check (MUST, per **workspace-folders-resolves-one-entry-per-root**, which imposes no such check).
- **Boundary values**: a query path that equals a root's own path exactly (not merely a descendant of it) MUST match that root in `getWorkspaceFolder`, per **get-workspace-folder-matches-the-longest-containing-root**'s exact-path-match branch (MUST).
- **Boundary values**: a query path whose string is a *character* prefix of a root's path but not a *path-component* prefix (e.g. `outer/inner-extra` against root `outer/inner`) MUST NOT match that root, per **get-workspace-folder-matches-the-longest-containing-root**'s trailing-slash-qualified comparison (MUST).
- **Concurrent access**: this component executes on a single, consistent execution context with no additional locking; the cached folder entries, the cached root list, and the torn-down flag are read and mutated only on that context, so there is no data race over those fields to define behavior for (MUST).
- **Concurrent access**: two extensions writing to the same file concurrently through their own bridge instances MUST see their writes ordered by the single shared filesystem service's own serial ordering, never interleaved at sub-write granularity, per **file-system-service-is-shared-not-per-extension** (MUST); a caller that instead constructs one filesystem-service instance per extension loses this guarantee entirely, since that is then two independent orderings.
- **Concurrent access**: nothing in this component detects or reports a second JavaScript context sharing one bridge instance; the one-instance-per-extension convention that makes the folder-entry cache's object-identity promise hold is enforced by the bridge's owner, not by this component (fact, not a marker — see Design Decisions).
- **Error states**: a `readFile`/`writeFile`/`readDirectory`/`stat`/`delete`/`rename`/`createDirectory` call whose filesystem service throws a `FileSystemServiceError` MUST reject with that error's own description as the message and, for the five classified cases, a matching `code`; any other thrown error MUST reject with that error's default string description as the message and no `code` property at all, per **operation-error-mapping-uses-filesystemserviceerror-description** and **operation-error-mapping-sets-a-code-only-for-classified-errors** (MUST).
- **Error states**: a call whose first (or, for `rename`, second) argument is not a `file:`-scheme `vscode.Uri` MUST reject with this bridge's own fixed message for that member, MUST NOT reach the filesystem service at all, per **required-url-rejects-non-file-schemes** (MUST).
- **Error states**: a `writeFile` call whose second argument is present but is not decodable as byte data (not a `Uint8Array` and not an array of byte numbers) MUST reject with `"vscode.workspace.fs.writeFile requires a Uint8Array of contents."`, per **write-file-requires-a-uint8array-second-argument** (MUST).
- **Cancellation or timeout**: none of the seven `fs` operations, `readFile` through `createDirectory`, imposes a timeout or accepts a `CancellationToken`; an operation that never completes on the filesystem service's side leaves its promise pending indefinitely (fact, not a marker — no timeout or cancellation parameter exists anywhere in this component's signatures).
- **Cancellation or timeout**: disposing the bridge while an operation is genuinely suspended mid-flight MUST still reject that operation's promise once it completes, rather than resolving it or crashing, per **operation-checks-teardown-after-running** (MUST); the underlying disk operation itself is not cancelled and runs to completion.
- **Offline or disconnected state**: not applicable — every `fs` operation reads or writes the local filesystem through the filesystem service; this component has no network dependency and no notion of connectivity.
- **Missing or unreachable resource**: `getWorkspaceFolder` and `workspaceFolders` answer `undefined` (never throw or reject) when `workspaceRoots` is null or the queried path matches no root, per **workspace-folders-resolves-to-undefined-when-empty** and **get-workspace-folder-answers-undefined-outside-every-root** (MUST).
- **No change notification**: this component declares no `onDidChangeWorkspaceFolders`-shaped event; `workspaceFolders` and `getWorkspaceFolder` are read live on each access (so a later read after the workspace changes sees the new roots), but nothing here pushes a notification to an extension that is not actively re-reading (fact, traced to this component's own documentation: "there are no `onDidChangeWorkspaceFolders` events, because no event plumbing exists to route one through"; deliberate, not a marker).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `workspaceRoots` | `ExtensionWorkspaceRoots?` | none (required, no default) | The workspace this bridge exposes through `name` and `workspaceFolders`, or null for "no workspace open." |
| `notImplementedLedger` | `NotImplementedLedger` | none (required, no default) | Where a reach for an undefined `vscode.workspace.fs` member is recorded, keyed by `extensionIdentifier` and member path. |
| `extensionIdentifier` | `String` | none (required, no default) | The extension this bridge belongs to, recorded alongside every `fs` ledger entry. |
| `fileSystemService` | `FileSystemServicing` | none (required, no default) | Where every `fs` operation actually reads and writes; MUST be the single instance shared across every extension's bridge, per **file-system-service-is-shared-not-per-extension**. |

## Deep Linking

Not applicable: this bridge defines no URL, route, or navigable destination — it dispatches JavaScript-originated `vscode.workspace` calls into workspace state and a filesystem service, with no navigation surface of its own.

## Localization

This bridge rejects and raises with hardcoded English string literals; none carries a localization key or any platform localization mechanism's entry. Every rejected message reaches the extension as a rejected JavaScript promise, so an extension author sees the literal English text regardless of locale.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `vscode.workspace.fs.readFile requires a file-scheme vscode.Uri argument.` | Rejected when `readFile`'s first argument is missing or not a `file:`-scheme `vscode.Uri`. |
| (none — literal only) | `vscode.workspace.fs.writeFile requires a file-scheme vscode.Uri argument.` | Rejected when `writeFile`'s first argument is missing or not a `file:`-scheme `vscode.Uri`. |
| (none — literal only) | `vscode.workspace.fs.writeFile requires a Uint8Array of contents.` | Rejected when `writeFile`'s second argument is missing or undecodable. |
| (none — literal only) | `vscode.workspace.fs.readDirectory requires a file-scheme vscode.Uri argument.` | Rejected when `readDirectory`'s first argument is missing or not a `file:`-scheme `vscode.Uri`. |
| (none — literal only) | `vscode.workspace.fs.stat requires a file-scheme vscode.Uri argument.` | Rejected when `stat`'s first argument is missing or not a `file:`-scheme `vscode.Uri`. |
| (none — literal only) | `vscode.workspace.fs.delete requires a file-scheme vscode.Uri argument.` | Rejected when `delete`'s first argument is missing or not a `file:`-scheme `vscode.Uri`. |
| (none — literal only) | `vscode.workspace.fs.rename requires two file-scheme vscode.Uri arguments.` | Rejected when `rename`'s first or second argument is missing or not a `file:`-scheme `vscode.Uri`. |
| (none — literal only) | `vscode.workspace.fs.createDirectory requires a file-scheme vscode.Uri argument.` | Rejected when `createDirectory`'s first argument is missing or not a `file:`-scheme `vscode.Uri`. |
| (none — literal only, from the filesystem service's own error description) | varies by case | Passed through verbatim as the rejected error's `message` whenever the filesystem service throws a `FileSystemServiceError`. |

## Accessibility Options

Not applicable: this bridge renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: this bridge declares no feature-flag key and contains no conditional feature-gating logic; `name`, `workspaceFolders`, `getWorkspaceFolder`, and every `fs` member are always available once this bridge is constructed.

## Analytics

Not applicable: this component contains no analytics or event-emission call of any kind; it makes no logging call either (see Logging) — its only observable effect on the outside world is through the `vscode.workspace` API surface itself and the `notImplementedLedger` entries `fs`'s stub records for members this task did not implement.

## Privacy

- **Data collected**: this bridge collects no data of its own. It exposes the app's own workspace roots (paths and a display name) and the app's own local filesystem contents to whichever extension it is installed on; every path and byte handled by an `fs` call is the caller-supplied argument or the file's own on-disk contents, forwarded to the filesystem service and back, never copied elsewhere or inspected beyond the `file:`-scheme check.
- **Storage**: this bridge performs no storage of its own; the folder-entry cache is in-memory only, rebuilt from `workspaceRoots` on demand, and exists for the bridge's lifetime. The filesystem service's own on-disk reads and writes are the app's local filesystem, out of this component's scope.
- **Transmission**: nothing here leaves the process voluntarily; every `fs` call is an in-process round trip between the host and the same process's own JavaScript engine, terminating in a local filesystem read or write. The `file:`-scheme check this bridge performs is documented as a security boundary specifically because, without it, a `vscode.Uri` built from an arbitrary string (for example `https://attacker.example/etc/passwd`, whose `.path` is `/etc/passwd`) would let an extension read or overwrite any local file the filesystem service can reach, under the guise of a non-`file` URI — this is the one point in this bridge where an extension's chosen input, if unvalidated, could reach the local filesystem outside the workspace it was given.
- **Retention**: the folder-entry cache is retained until `workspaceRoots.workspaceRootURLs` changes (rebuilt) or the bridge itself is deallocated; nothing here persists across process launches.

## Logging

Subsystem: the app's own bundle identifier, or a fixed fallback when unavailable | Category: derived from this component's own name

| Event | Level | Message |
|-------|-------|---------|

This component supports the shared logging contract (see **logging-conformance**), but no member ever calls it: no `readFile`/`writeFile`/`readDirectory`/`stat`/`delete`/`rename`/`createDirectory` failure, no teardown rejection, and no `name`/`workspaceFolders`/`getWorkspaceFolder` resolution writes a log line anywhere in this component (fact, contrasted with the sibling commands bridge, which logs caller-less callback failures at error level; this bridge has no equivalent caller-less-dispatch concept to log about). Every failure this component produces reaches the extension directly, as a rejected promise or a raised exception, with no separate host-side log entry.

## Platform Notes

- **SwiftUI**: not applicable to this file — `MainThreadWorkspace.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing in this component renders a view.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWorkspace.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is `@MainActor`-isolated per its class declaration, and the `FileSystemService` actor and `ExtensionWorkspaceRoots` protocol it depends on are likewise part of this macOS-only codebase today. The class's own name is `MainThreadWorkspace`. `name` and `workspaceFolders` are each an `ExtensionHost.LiveVSCodeValue`, resolving through `JSValueBridge.undefinedOrNull(in:)` for the undefined cases; `fs` is an `ExtensionHost.DeferredVSCodeValue` installed via `VSCodeAPI.subNamespace(path:members:in:recordMiss:recordProbe:)`, and each `fs` member and `getWorkspaceFolder` itself is built with `VSCodeAPI.member(..., whenTornDown:, ...)` (`.rejectedPromise` for the seven `fs` members, `.raisedException` for `getWorkspaceFolder`). Folder-entry URIs are built with `VSCodeAPI.uriValue(for:in:)`; a root's trailing-slash-free `fsPath` is produced by rebuilding its `URL` with `isDirectory: false` from `url.path` rather than passing it through `URL.standardizedFileURL` (which would also strip a `/private` prefix conditionally on what currently exists on disk), while `name` is read via `lastPathComponent`. The folder-entry cache is `folderEntries(in:)`, backed by `cachedFolderEntries`/`cachedFolderURLs`; `handleGetWorkspaceFolder` reads its argument via `VSCodeAPI.currentArguments()` and `VSCodeAPI.url(from:in:)`, and matches by comparing `url.standardizedFileURL.path` against each entry's `rootPath` with a trailing `/` appended. Each `fs` handler (`handleReadFile`, `handleWriteFile`, `handleReadDirectory`, `handleStat`, `handleDelete`, `handleRename`, `handleCreateDirectory`) validates its URI argument through `requiredURL(from:at:in:)`, which checks `URL.isFileURL`; `handleDelete` and `handleRename` read their options via `boolOption(_:key:)`/`toBool()`. Every `fs` handler runs through `runFileSystemOperation`, which builds the returned promise with `JSValue(newPromiseIn:fromExecutor:)`, starts the operation inside a `Task`, and settles it through a `PromiseSettlementBox` rather than capturing the promise's `resolve`/`reject` `JSValue`s directly (`JSValue` is not `Sendable`); the operation closure itself is declared `@escaping @Sendable () async throws -> Value` with `Value: Sendable`, and its result-delivery closure is `@escaping @MainActor (Value, JSContext) -> Any`. Failure mapping runs through `rejectionValue(for:in:)` and `vsCodeErrorCode(for:)`, reading `FileSystemServiceError.errorDescription` for the message. `uint8ArrayValue(from:in:)` builds a real `Uint8Array` with `JSObjectMakeTypedArrayWithBytesNoCopy`, copying bytes into a raw buffer once and freeing it on failure; its deallocator, `freeTypedArrayBytes`, is declared at file scope outside the class's `@MainActor` isolation because JavaScriptCore's garbage collector invokes it off the main actor. `data(fromUint8Array:)` reads a genuine `Uint8Array` via `JSObjectGetTypedArrayBytesPtr` when `JSValueGetTypedArrayType` reports `kJSTypedArrayTypeUint8Array`, falling back to `numbersData(from:)` (`value.toArray()` plus `NSNumber.uint8Value` per element) otherwise. `dispose()` sets `isDisposed`; the four top-level members are installed by whoever calls `defineVSCodeMember`, owned by `ExtensionHost`. `MainThreadWorkspace` conforms to `Loggable`, exposing a `nonisolated static let logger` built with `makeLogger()`, with subsystem `Bundle.main.bundleIdentifier` and category derived from the type name.
- **Compose**: model `MainThreadWorkspace` as a Kotlin `class MainThreadWorkspace(...)` confined to the main dispatcher, backed by a `kotlinx.coroutines.Dispatchers.Main`-confined instance rather than an actor (Kotlin has no built-in actor isolation the way Swift does). `ExtensionWorkspaceRoots` becomes a plain interface with `val workspaceDisplayName: String?` and `val workspaceRootURLs: List<Uri>`; the `Uint8Array` bridge becomes whatever byte-array type the chosen JavaScript engine binding (Rhino or J2V8) exposes — a `NativeArrayBuffer`/`V8TypedArray` in place of `JSObjectMakeTypedArrayWithBytesNoCopy`, adopting the buffer the same way to avoid per-byte boxing. `FileSystemServicing`'s seven operations become `suspend fun` members of an interface, and the folder-entry cache becomes a plain `MutableMap`/pair-of-fields guarded by the same main-dispatcher confinement, since nothing here needs a `Mutex`.
- **React/Web**: this component's own upstream is VS Code's real `MainThreadDocumentsAndEditors`/`ExtHostWorkspace` pairing (`mainThreadWorkspace.ts`, `extHostWorkspace.ts`), already TypeScript, so a web port is closer to restoring the original than translating it: `fs`'s seven members map directly onto Node's `fs/promises` (or a browser-side virtual filesystem) behind the same `Uint8Array`-in/`Uint8Array`-out contract, `workspaceFolders` and `getWorkspaceFolder` become plain object/array reads with no `JSContext`-bridging concerns at all, and every promise this file hand-settles through `JSValue(newPromiseIn:fromExecutor:)` becomes a native `Promise`.
- **WinUI 3**: model `MainThreadWorkspace` as a class whose every member runs on a captured `DispatcherQueue` (the `@MainActor` equivalent — WinUI 3 has no compiler-enforced actor isolation, so every entry point MUST assert `DispatcherQueue.HasThreadAccess` or marshal via `DispatcherQueue.TryEnqueue` at the top of the method). `ExtensionWorkspaceRoots` becomes an interface exposing `string? WorkspaceDisplayName` and `IReadOnlyList<string> WorkspaceRootPaths`; `FileSystemServicing`'s seven operations become `Task`-returning members of an interface backed by `Windows.Storage.StorageFile`/`StorageFolder` or plain `System.IO` calls, with a single shared instance across extensions preserving the ordering guarantee `file-system-service-is-shared-not-per-extension` requires (a `SemaphoreSlim`-guarded queue, or a single `Channel<T>` consumer, stands in for `FileSystemService`'s serial `DispatchQueue`). The `Uint8Array` bridge becomes whatever byte-array shape the chosen JavaScript engine binding uses — ClearScript's `ITypedArray`/`byte[]` marshaling, or Jint's `Uint8Array`-backed `JsValue`, standing in for `JSObjectMakeTypedArrayWithBytesNoCopy`/`JSObjectGetTypedArrayBytesPtr` — and `getWorkspaceFolder`'s longest-prefix match becomes an ordinary `string.StartsWith` comparison against each cached root's normalized path, at a path-separator boundary, mirroring the source's trailing-`/`-qualified comparison rather than a bare string prefix.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWorkspace.swift` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because the file's only responsibilities are the four `vscode.workspace` members' own argument validation, the `fs` sub-namespace's dispatch to `FileSystemServicing`, and the folder-entry cache; actual filesystem work is delegated to `FileSystemService`, JavaScript call/promise/disposable/sub-namespace ceremony is delegated to `VSCodeAPI`, and the workspace's own identity is delegated to `ExtensionWorkspaceRoots` rather than reached through the app's full `ProjectWorkspace`. `unit-test-coverage` is partial: the given `MainThreadWorkspaceTests.swift` suite thoroughly covers all seven `fs` operations reaching the real `FileSystemService` and landing on disk, five of the six mapped `FileSystemServiceError` codes plus the `Unavailable` collapse, `workspaceFolders`/`name`/`getWorkspaceFolder` across no-workspace, single-root, nested-root, `/private`-prefixed-root, and longest-prefix-match cases, the unimplemented-member ledger path, and both halves of in-flight teardown — but no test in the given sources exercises `rename`'s `overwrite: true` branch, a `writeFile` call using the plain-array (`numbersData`) fallback rather than a genuine `Uint8Array`, or a non-`FileSystemServiceError` thrown from `fileSystemService` reaching `rejectionValue(for:in:)`'s untyped-error branch. `input-sanitization` passes because `requiredURL(from:at:in:)` validates every `fs` argument's URI scheme before it ever reaches `FileSystemServicing`, refusing any non-`file`-scheme value — the security boundary the source's own comment documents explicitly, closing the path a scheme-confused URI (an `https:` URL whose `.path` happens to name a local file) would otherwise open into the local filesystem. `no-hardcoded-strings` fails because every rejected message this file constructs directly (see Localization) is an English literal with no localization mechanism.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/vscode-api/workspace/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
