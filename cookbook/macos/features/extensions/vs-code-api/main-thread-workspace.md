---
id: 1cacbe17-bca6-458c-bf1f-df9efa3652be
title: MainThreadWorkspace
domain: agentictoolkit://cookbook/macos/features/extensions/vs-code-api/main-thread-workspace
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The extension host''s vscode.workspace adaptor: name, workspaceFolders,
  getWorkspaceFolder, and the seven fs operations, terminating in the app''s own FileSystemService
  and workspace roots.'
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- workspace
- filesystem
- javascriptcore
- mainactor
depends-on: []
related:
- agentictoolkit://cookbook/macos/features/extensions/host
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/main-thread-commands
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

# MainThreadWorkspace

## Overview

`MainThreadWorkspace.swift` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWorkspace.swift`) is the extension host's `vscode.workspace` adaptor: `name`, `workspaceFolders`, `getWorkspaceFolder`, and the seven `fs` operations (`readFile`, `writeFile`, `readDirectory`, `stat`, `delete`, `rename`, `createDirectory`). `name` and `workspaceFolders` read a narrow protocol, `ExtensionWorkspaceRoots` (`workspaceDisplayName`, `workspaceRootURLs`), rather than the app's full `ProjectWorkspace`, so the extension host's dependency surface on the app's project model is exactly two fields, not a `GitRepo`, a `ProjectDatabase`, and a tab layout. Every `fs` member terminates in a required `FileSystemServicing` instance, shared across every extension's adaptor rather than one per extension, so that the app's own `FileSystemService` serial queue — not two independent queues — orders concurrent writes to the same file. The class is `@MainActor`-isolated, matching every other adaptor in this file (`JSValue` and `JSContext` are not `Sendable`, and JavaScriptCore always calls back on the thread that made the call, which for this host is always the main actor), and is meant as **one instance per extension**, mirroring `ExtensionHost` and `MainThreadCommands`: nothing in the type enforces that, but the folder-entry cache's promise of a stable `getWorkspaceFolder`/`workspaceFolders` object identity depends on it. `name` and `workspaceFolders` are read live on every access rather than snapshotted at construction, because extensions activate at app launch, ahead of any project window, and a snapshot taken then would freeze "no workspace" for the process's whole life. Whoever owns this adaptor must call `dispose()` when it tears the extension host down; an `fs` operation already in flight when that happens is left to finish on disk, but its promise rejects instead of resolving into a torn-down extension.

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
- **rename-overwrite-defaults-false**: `handleRename` MUST read `overwrite` from an optional third `options` argument as `options?.forProperty("overwrite")?.toBool() ?? false`.
- **create-directory-requires-a-file-uri**: `handleCreateDirectory` MUST return `VSCodeAPI.rejectedPromise(message: "vscode.workspace.fs.createDirectory requires a file-scheme vscode.Uri argument.", in:)` when the first argument is missing or is not a `file:`-scheme `vscode.Uri`.
- **required-url-rejects-non-file-schemes**: `requiredURL(from:at:in:)` MUST return `nil` for a `vscode.Uri` whose `URL.isFileURL` is `false`, including a scheme-relative string and any non-`file` scheme, even when `VSCodeAPI.url(from:in:)` itself successfully parses that value for a non-filesystem caller.
- **file-system-operations-run-off-a-genuine-pending-promise**: `runFileSystemOperation` MUST build the returned promise with `JSValue(newPromiseIn:fromExecutor:)`, MUST start `operation` inside a `Task`, and MUST NOT resolve or reject synchronously before that `Task` runs.
- **operation-checks-teardown-before-running**: `runFileSystemOperation`'s `Task` MUST reject with the "torn down" wording `JSValueBridge.rejectTornDown` produces, and MUST NOT call `operation()` at all, when `self` has been deallocated or `isDisposed` is already `true` at the `Task`'s first turn.
- **operation-checks-teardown-after-running**: `runFileSystemOperation`'s `Task` MUST reject with the same "torn down" wording, and MUST NOT deliver `operation`'s result to `resolveWith`, when `self` has been deallocated or `isDisposed` became `true` while `operation` was in flight, even though `operation` itself completed successfully.
- **operation-error-mapping-uses-filesystemserviceerror-description**: `rejectionValue(for:in:)` MUST build the rejected `Error`'s `message` from `FileSystemServiceError.errorDescription` when the thrown error is a `FileSystemServiceError`, and from `"\(error)"` for any other error type.
- **operation-error-mapping-sets-a-code-only-for-classified-errors**: `rejectionValue(for:in:)` MUST set the rejected `Error`'s `code` property to the result of `vsCodeErrorCode(for:)` when the thrown error is a `FileSystemServiceError`, and MUST leave `code` unset for any other error type.
- **error-code-mapping-is-fixed**: `vsCodeErrorCode(for:)` MUST map `.fileNotFound` to `"FileNotFound"`, `.fileExists` to `"FileExists"`, `.fileIsADirectory` to `"FileIsADirectory"`, `.fileNotADirectory` to `"FileNotADirectory"`, and `.noPermissions` to `"NoPermissions"`, and MUST map `.directoryNotEmpty` and every `*Failed` case (`.readFailed`, `.writeFailed`, `.statFailed`, `.readDirectoryFailed`, `.deleteFailed`, `.renameFailed`, `.createDirectoryFailed`) to `"Unavailable"`.
- **uint8array-bridging-adopts-the-buffer-with-no-per-byte-boxing**: `uint8ArrayValue(from:in:)` MUST build the returned typed array with `JSObjectMakeTypedArrayWithBytesNoCopy`, copying `data`'s bytes into a raw buffer exactly once (`memcpy`-equivalent), and MUST NOT bridge through a `[UInt8]`-to-`NSNumber`-array intermediate.
- **uint8array-bridging-frees-on-failure**: `uint8ArrayValue(from:in:)` MUST deallocate the raw buffer itself and return `JSValueBridge.undefinedOrNull(in:)` when `JSObjectMakeTypedArrayWithBytesNoCopy` fails (returns `nil` or sets a non-`nil` exception).
- **uint8array-deallocator-runs-off-the-main-actor**: `freeTypedArrayBytes`, the deallocator `uint8ArrayValue(from:in:)` registers, MUST be declared at file scope, outside `MainThreadWorkspace`'s `@MainActor` isolation, because JavaScriptCore invokes it from its own garbage-collector thread, never from the main actor.
- **uint8array-decoding-prefers-the-typed-array-fast-path**: `data(fromUint8Array:)` MUST read a `Uint8Array` argument's bytes via `JSObjectGetTypedArrayBytesPtr` and copy them once into a `Data`, without boxing each byte as an `NSNumber`, whenever `JSValueGetTypedArrayType` reports `kJSTypedArrayTypeUint8Array` for that value.
- **uint8array-decoding-falls-back-for-plain-arrays**: `data(fromUint8Array:)` MUST fall back to `numbersData(from:)` (reading `value.toArray()` and converting each element to a `UInt8` via `NSNumber.uint8Value`) when the argument has no `JSContext`, is not a `Uint8Array`, or is any other array-like value; this fallback MUST accept a plain JavaScript array of byte numbers.
- **operation-value-type-must-be-sendable**: `runFileSystemOperation`'s generic `operation` closure MUST be declared `@escaping @Sendable () async throws -> Value` with `Value: Sendable`, and its `resolveWith` closure MUST be declared `@escaping @MainActor (Value, JSContext) -> Any`, so a `JSValue` (not `Sendable`) is never captured directly by the `Task`.
- **promise-settlement-crosses-actors-through-a-box**: `runFileSystemOperation` MUST capture the promise's `resolve`/`reject` `JSValue`s for its `Task` through a `PromiseSettlementBox`, never as a bare `JSValue` capture, and each captured pair MUST be used only on the main actor that created it.
- **dispose-marks-torn-down-and-nothing-else**: `dispose()` MUST set `isDisposed` to `true` and MUST NOT attempt to unregister `fs`, `workspaceFolders`, `name`, or `getWorkspaceFolder` from any registry, because those four are installed directly into the shim's member table by whoever calls `defineVSCodeMember`, and that table is owned and torn down by `ExtensionHost`, not by this adaptor.
- **logging-conformance**: `MainThreadWorkspace` MUST conform to `Loggable`, exposing a `nonisolated static let logger` built with `makeLogger()`.

## Appearance

Not applicable — this is the extension host's `vscode.workspace` adaptor, not a visual component.

## States

Not applicable — this is the extension host's `vscode.workspace` adaptor, not a visual component. Its only lifecycle-shaped behavior is the constructed-versus-disposed status of the adaptor itself, captured under Behavioral Requirements (`dispose-marks-torn-down-and-nothing-else`, `operation-checks-teardown-before-running`, `operation-checks-teardown-after-running`) rather than as a visual-state table.

## Accessibility

Not applicable — this is the extension host's `vscode.workspace` adaptor, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| main-thread-workspace-001 | read-file-resolves-a-real-uint8array | `fs.readFile(Uri.file(path))` against a file containing bytes `[0, 1, 127, 128, 255]` | The promise resolves with a value where `bytes instanceof Uint8Array` is `true`, `bytes.length === 5`, and `Array.from(bytes)` equals `[0, 1, 127, 128, 255]` — `MainThreadWorkspaceTests.readFileReachesTheServiceAndResolvesWithARealUint8Array` |
| main-thread-workspace-002 | write-file-always-creates-and-overwrites | `fs.writeFile(Uri.file(path), new Uint8Array([9, 8, 7, 0, 255]))` against a path with no existing file | The promise resolves, and reading the file from disk afterward yields exactly `[9, 8, 7, 0, 255]` — `MainThreadWorkspaceTests.writeFileReachesTheServiceAndTheBytesLandOnDisk` |
| main-thread-workspace-003 | read-directory-resolves-two-element-tuples | `fs.readDirectory(Uri.file(dir))` against a directory containing file `a.txt` and subdirectory `sub` | The promise resolves with an array of two two-element entries; as an unordered set the entries equal `["a.txt:1", "sub:2"]` (`FileType.file.rawValue == 1`, `FileType.directory.rawValue == 2`) — `MainThreadWorkspaceTests.readDirectoryReachesTheServiceAndResolvesWithTheTupleShape` |
| main-thread-workspace-004 | stat-resolves-the-filestat-shape | `fs.stat(Uri.file(path))` against an 11-byte file created, then (after a delay) overwritten in place | The promise resolves with `type === 1`, `size === 11`, `ctime` inside the file's creation-time window, and `mtime` inside the later modification-time window (the two windows do not overlap) — `MainThreadWorkspaceTests.statReachesTheServiceAndResolvesWithTheStatShape` |
| main-thread-workspace-005 | delete-options-default-both-false (delegated result) | `fs.delete(Uri.file(path))` with no options argument, against an existing plain file | The promise resolves, and `FileManager.default.fileExists(atPath:)` for that path is `false` afterward — `MainThreadWorkspaceTests.deleteReachesTheServiceAndRemovesTheFile` |
| main-thread-workspace-006 | rename-overwrite-defaults-false (delegated result) | `fs.rename(Uri.file(source), Uri.file(target))` with no options argument, `source` containing `"payload"`, `target` not existing | The promise resolves; `source` no longer exists on disk, and `target`'s contents equal `"payload"` — `MainThreadWorkspaceTests.renameReachesTheServiceAndMovesTheFile` |
| main-thread-workspace-007 | write-file-always-creates-and-overwrites (delegated result) | `fs.createDirectory(Uri.file(nested/child))` against a path whose parent does not yet exist | The promise resolves, and the target path exists on disk as a directory afterward — `MainThreadWorkspaceTests.createDirectoryReachesTheServiceAndCreatesTheDirectory` |
| main-thread-workspace-008 | error-code-mapping-is-fixed | `fs.readFile(Uri.file(path))` where `path` does not exist | The promise rejects with `error.code === "FileNotFound"` — `MainThreadWorkspaceTests.readFileOnAMissingPathRejectsWithFileNotFound` |
| main-thread-workspace-009 | error-code-mapping-is-fixed | `fs.readFile(Uri.file(dir))` where `dir` is a directory | The promise rejects with `error.code === "FileIsADirectory"` — `MainThreadWorkspaceTests.readFileOnADirectoryRejectsWithFileIsADirectory` |
| main-thread-workspace-010 | error-code-mapping-is-fixed | `fs.readDirectory(Uri.file(path))` where `path` is a plain file | The promise rejects with `error.code === "FileNotADirectory"` — `MainThreadWorkspaceTests.readDirectoryOnAFileRejectsWithFileNotADirectory` |
| main-thread-workspace-011 | error-code-mapping-is-fixed | `fs.createDirectory(Uri.file(path))` where `path` is already occupied by a plain file | The promise rejects with `error.code === "FileExists"` — `MainThreadWorkspaceTests.createDirectoryOverAnExistingFileRejectsWithFileExists` |
| main-thread-workspace-012 | error-code-mapping-is-fixed | `fs.readFile(Uri.file(path))` where `path`'s POSIX mode is `0o000` | The promise rejects with `error.code === "NoPermissions"` — `MainThreadWorkspaceTests.readFileOnAnUnreadableFileRejectsWithNoPermissions` |
| main-thread-workspace-013 | error-code-mapping-is-fixed | `fs.delete(Uri.file(dir))` where `dir` is non-empty and no `recursive` option is passed | The promise rejects with `error.code === "Unavailable"` — `MainThreadWorkspaceTests.deleteOnANonEmptyDirectoryWithoutRecursiveRejectsWithUnavailable` |
| main-thread-workspace-014 | workspace-folders-resolves-to-undefined-when-empty | `vscode.workspace.workspaceFolders` read with `workspaceRoots: nil` | `vscode.workspace.workspaceFolders === undefined` is `true` — `MainThreadWorkspaceTests.workspaceFoldersIsUndefinedWithNoWorkspace` |
| main-thread-workspace-015 | folder-entry-uri-is-a-real-vscode-uri, folder-entry-name-is-the-last-path-component, folder-entry-index-matches-position | `vscode.workspace.workspaceFolders` read with one root `root-one` | `folders.length === 1`, `folders[0].uri instanceof vscode.Uri`, `folders[0].uri.fsPath` equals the root's path, `folders[0].name === "root-one"`, `folders[0].index === 0` — `MainThreadWorkspaceTests.workspaceFoldersAnswersOneRealFolderWithARealUri` |
| main-thread-workspace-016 | folder-entry-uri-has-no-trailing-slash | `vscode.workspace.workspaceFolders[0].uri.fsPath` read for a root nested three directories deep | `fsPath` equals the root `URL`'s `.path` exactly and `fsPath.hasSuffix("/")` is `false` — `MainThreadWorkspaceTests.workspaceFoldersAnswersANestedRootWithATrailingSlashFreeFsPath` |
| main-thread-workspace-017 | folder-entry-uri-preserves-a-private-prefix | `vscode.workspace.workspaceFolders[0].uri.fsPath` read for a root created at a literal `/private/...` path | `fsPath` equals the root's literal path and `fsPath.hasPrefix("/private/")` is `true` — `MainThreadWorkspaceTests.workspaceFoldersAnswersAPrivatePrefixedRootWithThePrefixIntact` |
| main-thread-workspace-018 | name-resolves-the-live-display-name | `vscode.workspace.name` read with `workspaceRoots.workspaceDisplayName == "My Project"` | `vscode.workspace.name === "My Project"` — `MainThreadWorkspaceTests.nameAnswersTheDisplayNameWhenAWorkspaceIsOpen` |
| main-thread-workspace-019 | name-resolves-to-undefined-when-absent | `vscode.workspace.name` read with `workspaceRoots: nil` | `vscode.workspace.name === undefined` is `true` and `vscode.workspace.name === null` is `false` — `MainThreadWorkspaceTests.nameIsUndefinedWithNoWorkspace` |
| main-thread-workspace-020 | get-workspace-folder-answers-the-same-object-workspace-folders-produced | `vscode.workspace.getWorkspaceFolder(Uri.file(fileInsideRoot))` for a file directly inside the one registered root | The returned object is `===` to `vscode.workspace.workspaceFolders[0]`, and its `name` equals the root's name — `MainThreadWorkspaceTests.getWorkspaceFolderAnswersTheContainingRootForAFileInsideIt` |
| main-thread-workspace-021 | get-workspace-folder-matches-the-longest-containing-root | roots `["outer", "outer/inner"]` (outer registered first); query a file under `outer/inner` and a sibling file under `outer/inner-extra` | The `outer/inner` file's folder has `name === "inner"`; the `outer/inner-extra` file's folder has `name === "outer"` (not falsely matched to `inner` by string prefix) — `MainThreadWorkspaceTests.getWorkspaceFolderPicksTheLongestMatchingRoot` |
| main-thread-workspace-022 | get-workspace-folder-answers-undefined-outside-every-root | `vscode.workspace.getWorkspaceFolder(Uri.file(outsidePath))` for a path outside the one registered root | The call answers `undefined` — `MainThreadWorkspaceTests.getWorkspaceFolderAnswersUndefinedForAFileOutsideEveryRoot` |
| main-thread-workspace-023 | fs-is-a-deferred-sub-namespace-with-seven-members, fs-miss-and-probe-recording-is-wired | probe `'copy' in vscode.workspace.fs`, then call `vscode.workspace.fs.copy(a, b)` | The probe is `false`; the call throws `NotImplementedError`; `notImplementedLedger.accesses` has exactly one entry for `vscode.workspace.fs.copy` with `count === 1` and `probeCount === 1` — `MainThreadWorkspaceTests.anUnimplementedFsMemberThrowsAndIsRecordedInTheLedger` |
| main-thread-workspace-024 | operation-checks-teardown-before-running | call `fs.readFile(...)`, attach `.then`, then call `workspace.dispose()` before the underlying `Task` has had its first turn | The promise rejects with a message containing `"torn down"` rather than resolving with the file's real contents — `MainThreadWorkspaceTests.disposingWhileAnOperationIsInFlightRejectsRatherThanCrashing` |
| main-thread-workspace-025 | operation-checks-teardown-after-running | call `fs.readFile(...)` against a `FileSystemServicing` double whose `readFile` suspends until released; wait for it to enter, call `workspace.dispose()`, then release it | The promise rejects with a message containing `"torn down"`, even though the underlying operation completed successfully after disposal — `MainThreadWorkspaceTests.disposingWhileAnOperationIsGenuinelySuspendedRejectsRatherThanDeliveringAResult` |

## Edge Cases

- **Null/empty input**: `vscode.workspace.workspaceFolders` read with zero workspace roots MUST resolve to `undefined`, never `[]`, per **workspace-folders-resolves-to-undefined-when-empty** (MUST).
- **Null/empty input**: `getWorkspaceFolder(uri)` called with zero arguments MUST answer `undefined` (the string-and-first-argument guard fails identically to a non-`vscode.Uri` first argument), per **get-workspace-folder-answers-undefined-for-a-missing-argument** (MUST).
- **Null/empty input**: `handleGetWorkspaceFolder` MUST return Swift `nil` (which `VSCodeAPI.member` bridges to JavaScript `undefined` rather than raising) when `JSContext.current()` itself is `nil`; this is a defensive guard for a condition that does not arise on an ordinary JavaScript-triggered call, not a distinct error path with its own message (fact, traced to `handleGetWorkspaceFolder`'s first `guard`).
- **Boundary values**: a workspace root equal to the filesystem root or the empty-string last path component is not specially rejected; `folderEntries(in:)` and `workspaceFolderValue(for:index:in:)` build an entry for any `URL` the roots object supplies, with no minimum- or maximum-length check (MUST, per **workspace-folders-resolves-one-entry-per-root**, which imposes no such check).
- **Boundary values**: a query path that equals a root's own path exactly (not merely a descendant of it) MUST match that root in `getWorkspaceFolder`, per **get-workspace-folder-matches-the-longest-containing-root**'s `targetPath == rootPath` branch (MUST).
- **Boundary values**: a query path whose string is a *character* prefix of a root's path but not a *path-component* prefix (e.g. `outer/inner-extra` against root `outer/inner`) MUST NOT match that root, per **get-workspace-folder-matches-the-longest-containing-root**'s trailing-slash-qualified comparison (MUST).
- **Concurrent access**: `MainThreadWorkspace` is `@MainActor`-isolated with no additional locking; `cachedFolderEntries`, `cachedFolderURLs`, and `isDisposed` are read and mutated only on the main actor, so there is no data race over those fields to define behavior for (MUST).
- **Concurrent access**: two extensions writing to the same file concurrently through their own `MainThreadWorkspace` instances MUST see their writes ordered by the single shared `FileSystemService`'s own serial queue, never interleaved at sub-write granularity, per **file-system-service-is-shared-not-per-extension** (MUST); a caller that instead constructs one `FileSystemService` per extension loses this guarantee entirely, since that is then two independent queues.
- **Concurrent access**: nothing in this file detects or reports a second `JSContext` sharing one `MainThreadWorkspace` instance; the one-instance-per-extension convention that makes the folder-entry cache's object-identity promise hold is enforced by the adaptor's owner, not by this type (fact, not a marker — see Design Decisions).
- **Error states**: a `readFile`/`writeFile`/`readDirectory`/`stat`/`delete`/`rename`/`createDirectory` call whose `FileSystemServicing` throws a `FileSystemServiceError` MUST reject with that error's own `errorDescription` as the message and, for the five classified cases, a matching `code`; any other thrown error MUST reject with `"\(error)"` as the message and no `code` property at all, per **operation-error-mapping-uses-filesystemserviceerror-description** and **operation-error-mapping-sets-a-code-only-for-classified-errors** (MUST).
- **Error states**: a call whose first (or, for `rename`, second) argument is not a `file:`-scheme `vscode.Uri` MUST reject with this adaptor's own fixed message for that member, MUST NOT reach `fileSystemService` at all, per **required-url-rejects-non-file-schemes** (MUST).
- **Error states**: a `writeFile` call whose second argument is present but is not decodable as byte data (not a `Uint8Array` and not an array of byte numbers) MUST reject with `"vscode.workspace.fs.writeFile requires a Uint8Array of contents."`, per **write-file-requires-a-uint8array-second-argument** (MUST).
- **Cancellation or timeout**: none of the seven `fs` operations, `readFile` through `createDirectory`, imposes a timeout or accepts a `CancellationToken`; an operation that never completes on the `FileSystemServicing` side leaves its promise pending indefinitely (fact, not a marker — no timeout or cancellation parameter exists anywhere in this file's signatures).
- **Cancellation or timeout**: disposing the adaptor while an operation is genuinely suspended mid-`await` MUST still reject that operation's promise once it completes, rather than resolving it or crashing, per **operation-checks-teardown-after-running** (MUST); the underlying disk operation itself is not cancelled and runs to completion.
- **Offline or disconnected state**: not applicable — every `fs` operation reads or writes the local filesystem through `FileSystemServicing`; this file has no network dependency and no notion of connectivity.
- **Missing or unreachable resource**: `getWorkspaceFolder` and `workspaceFolders` answer `undefined` (never throw or reject) when `workspaceRoots` is `nil` or the queried path matches no root, per **workspace-folders-resolves-to-undefined-when-empty** and **get-workspace-folder-answers-undefined-outside-every-root** (MUST).
- **No change notification**: this file declares no `onDidChangeWorkspaceFolders`-shaped event; `workspaceFolders` and `getWorkspaceFolder` are read live on each access (so a later read after the workspace changes sees the new roots), but nothing here pushes a notification to an extension that is not actively re-reading (fact, traced to the class's own doc comment: "there are no `onDidChangeWorkspaceFolders` events, because no event plumbing exists to route one through"; deliberate, not a marker).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `workspaceRoots` | `ExtensionWorkspaceRoots?` | none (required, no default) | The workspace this adaptor exposes through `name` and `workspaceFolders`, or `nil` for "no workspace open." |
| `notImplementedLedger` | `NotImplementedLedger` | none (required, no default) | Where a reach for an undefined `vscode.workspace.fs` member is recorded, keyed by `extensionIdentifier` and member path. |
| `extensionIdentifier` | `String` | none (required, no default) | The extension this adaptor belongs to, recorded alongside every `fs` ledger entry. |
| `fileSystemService` | `FileSystemServicing` | none (required, no default) | Where every `fs` operation actually reads and writes; MUST be the single instance shared across every extension's adaptor, per **file-system-service-is-shared-not-per-extension**. |

## Deep Linking

Not applicable: `MainThreadWorkspace.swift` defines no URL, route, or navigable destination — it dispatches JavaScript-originated `vscode.workspace` calls into workspace state and a filesystem service, with no navigation surface of its own.

## Localization

`MainThreadWorkspace` rejects and raises with hardcoded English string literals; none carries a localization key, `String(localized:)` call, or String Catalog entry. Every rejected message reaches the extension as a rejected JavaScript promise, so an extension author sees the literal English text regardless of locale.

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
| (none — literal only, from `FileSystemServiceError.errorDescription`) | varies by case | Passed through verbatim as the rejected `Error`'s `message` whenever `fileSystemService` throws a `FileSystemServiceError`. |

## Accessibility Options

Not applicable: `MainThreadWorkspace.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; `name`, `workspaceFolders`, `getWorkspaceFolder`, and every `fs` member are always available once a `MainThreadWorkspace` is constructed.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; it has no `OSLog` call either (see Logging) — its only observable effect on the outside world is through the `vscode.workspace` API surface itself and the `notImplementedLedger` entries `fs`'s stub records for members this task did not implement.

## Privacy

- **Data collected**: `MainThreadWorkspace` collects no data of its own. It exposes the app's own workspace roots (paths and a display name) and the app's own local filesystem contents to whichever extension's `JSContext` it is installed on; every path and byte handled by an `fs` call is the caller-supplied argument or the file's own on-disk contents, forwarded to `FileSystemServicing` and back, never copied elsewhere or inspected beyond the `file:`-scheme check.
- **Storage**: `MainThreadWorkspace` performs no storage of its own; `cachedFolderEntries` and `cachedFolderURLs` are in-memory only, rebuilt from `workspaceRoots` on demand, and exist for the adaptor's lifetime. `FileSystemService`'s own on-disk reads and writes are the app's local filesystem, out of this file's scope.
- **Transmission**: nothing here leaves the process voluntarily; every `fs` call is an in-process JavaScriptCore round trip between the host and a `JSContext` the same process owns, terminating in a local filesystem read or write. The `file:`-scheme check in `requiredURL(from:at:in:)` is documented in the source as a security boundary specifically because, without it, a `vscode.Uri` built from an arbitrary string (for example `https://attacker.example/etc/passwd`, whose `.path` is `/etc/passwd`) would let an extension read or overwrite any local file `FileSystemService` can reach, under the guise of a non-`file` URI — this is the one point in the file where an extension's chosen input, if unvalidated, could reach the local filesystem outside the workspace it was given.
- **Retention**: the folder-entry cache is retained until `workspaceRoots.workspaceRootURLs` changes (rebuilt) or the adaptor itself is deallocated; nothing here persists across process launches.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `MainThreadWorkspace` (via `Loggable`'s default, derived from the type name)

| Event | Level | Message |
|-------|-------|---------|

`MainThreadWorkspace` conforms to `Loggable` and exposes `logger`, but no member in this file ever calls it: no `readFile`/`writeFile`/`readDirectory`/`stat`/`delete`/`rename`/`createDirectory` failure, no teardown rejection, and no `name`/`workspaceFolders`/`getWorkspaceFolder` resolution writes a log line anywhere in this file (fact, contrasted with `MainThreadCommands`, which logs caller-less callback failures at `error` level; this adaptor has no equivalent caller-less-dispatch concept to log about). Every failure this file produces reaches the extension directly, as a rejected promise or a raised exception, with no separate host-side log entry.

## Platform Notes

- **SwiftUI**: not applicable to this file — `MainThreadWorkspace.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing in this component renders a view.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWorkspace.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is `@MainActor`-isolated per its class declaration, and the `FileSystemService` actor and `ExtensionWorkspaceRoots` protocol it depends on are likewise part of this macOS-only codebase today.
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
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
