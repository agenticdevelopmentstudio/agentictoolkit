<!-- leaf: implement-extension-host-vs-2/code-api-main-thread-workspace--part-3 · source: extension-host-vs-code-api-main-thread-workspace.md -->

# MainThreadWorkspace — continued (part 3)

**Rules** (cite as `implement-extension-host-vs-2/code-api-main-thread-workspace--part-3#<slug>`):

- `rename-overwrite-defaults-false` MUST
- `create-directory-requires-a-file-uri` MUST
- `required-url-rejects-non-file-schemes` MUST
- `file-system-operations-run-off-a-genuine-pending-promise` MUST
- `operation-checks-teardown-before-running` MUST
- `operation-checks-teardown-after-running` MUST
- `operation-error-mapping-uses-filesystemserviceerror-description` MUST
- `operation-error-mapping-sets-a-code-only-for-classified-errors` MUST
- `error-code-mapping-is-fixed` MUST
- `uint8array-bridging-adopts-the-buffer-with-no-per-byte-boxing` MUST
- `uint8array-bridging-frees-on-failure` MUST
- `uint8array-deallocator-runs-off-the-main-actor` MUST
- `uint8array-decoding-prefers-the-typed-array-fast-path` MUST
- `uint8array-decoding-falls-back-for-plain-arrays` MUST
- `operation-value-type-must-be-sendable` MUST
- `promise-settlement-crosses-actors-through-a-box` MUST
- `dispose-marks-torn-down-and-nothing-else` MUST
- `logging-conformance` MUST

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
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `workspaceRoots` | `ExtensionWorkspaceRoots?` | none (required, no default) | The workspace this adaptor exposes through `name` and `workspaceFolders`, or `nil` for "no workspace open." |
| `notImplementedLedger` | `NotImplementedLedger` | none (required, no default) | Where a reach for an undefined `vscode.workspace.fs` member is recorded, keyed by `extensionIdentifier` and member path. |
| `extensionIdentifier` | `String` | none (required, no default) | The extension this adaptor belongs to, recorded alongside every `fs` ledger entry. |
| `fileSystemService` | `FileSystemServicing` | none (required, no default) | Where every `fs` operation actually reads and writes; MUST be the single instance shared across every extension's adaptor, per **file-system-service-is-shared-not-per-extension**. |

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

