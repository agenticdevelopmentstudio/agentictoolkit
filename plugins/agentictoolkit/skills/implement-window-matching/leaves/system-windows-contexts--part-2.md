<!-- leaf: implement-window-matching/system-windows-contexts--part-2 · source: window-matching-system-windows-contexts.md -->

# Window Matching System Windows Contexts — continued (part 2)

**Rules** (cite as `implement-window-matching/system-windows-contexts--part-2#<slug>`):

- `state-shape` MUST
- `state-order-meaning` MUST
- `state-excludes-settings` MUST
- `settings-shape` MUST
- `settings-lenient-decode` MUST
- `settings-typed-decode` MUST
- `reconcile-behavior-cases` MUST
- `reconcile-behavior-not-consumed` MUST
- `reconcile-item-shape` MUST
- `reconcile-candidate-shape` MUST
- `reconcile-models-not-sendable` MUST
- `configuration-shape` MUST
- `error-descriptions-store` MUST
- `error-descriptions-manager` MUST
- `unraised-error-cases` MUST
- `store-layout` MUST
- `store-json-format` MUST
- `store-ensure-directories` MUST
- `store-load-state-missing` MUST
- `store-load-state-errors` MUST
- `store-load-context-missing` MUST
- `store-save-context` MUST
- `store-delete-context` MUST
- `store-load-all-order` MUST
- `store-load-all-skips` MUST
- `store-load-all-state-error` MUST
- `store-save-all-content` MUST
- `store-save-all-no-prune` MUST
- `store-list-files` MUST
- `store-remove-all` MUST
- `store-lock` MUST
- `store-lock-failure` MUST
- `store-lock-blocking` MUST
- `store-reads-unlocked` MUST
- `store-sendable` MUST
- `manager-main-actor` MUST
- `manager-init` MUST
- `manager-load-state` MUST
- `manager-load-no-active-check` MUST
- `reconcile-stale-recycled` MUST
- `reconcile-stale-missing` MUST
- `reconcile-stale-persist` MUST
- `manager-root-directory` MUST

## Behavioral Requirements

### Data shapes

- **state-shape**: `SystemWindowContextsState` MUST hold `activeContextID: UUID?` and `contextIDs: [UUID]`, both defaulting to empty (`nil`, `[]`), and MUST be `Codable`, `Equatable`, and `Sendable`.
- **state-order-meaning**: `contextIDs` order MUST be the display order of contexts, where index 0 corresponds to keyboard shortcut 1 (per its doc comment).
- **state-excludes-settings**: `SystemWindowContextsState` MUST NOT carry application settings; hosts persist `SystemWindowContextsSettings` separately.
- **settings-shape**: `SystemWindowContextsSettings` MUST hold `launchAtLogin: Bool` (default `false`), `reconcileBehavior: ReconcileBehavior` (default `.prompt`), `hiddenApps: [String]` (default `[]`), and `showAppInDock: Bool` (default `false`), and MUST be `Codable`, `Equatable`, and `Sendable`.
- **settings-lenient-decode**: Decoding `SystemWindowContextsSettings` MUST substitute the default for each missing key, so `{}` decodes to the all-defaults value.
- **settings-typed-decode**: Decoding MUST throw when a present key holds the wrong type (for example `"launchAtLogin": "yes"`); only absence falls back to the default.
- **reconcile-behavior-cases**: `ReconcileBehavior` MUST declare exactly `prompt`, `auto`, `ignore`, in that order, each with its case name as its `String` raw value, and MUST be `CaseIterable`, `Codable`, `Equatable`, and `Sendable`.
- **reconcile-behavior-not-consumed**: The model MUST only store `reconcileBehavior` through `setReconcileBehavior(_:)`, and `performLaunchReconciliation()` always auto-applies matches and opens the Reconcile UI for the rest, whatever the stored value.
- **reconcile-item-shape**: `ReconcileItem` MUST carry `id` (the dormant snapshot's ID), `contextID`, `contextName`, `contextColor`, `app`, `titlePattern` (the fingerprint's title pattern), and `candidates: [ReconcileCandidate]`, and MUST be `Identifiable` and `Equatable`.
- **reconcile-candidate-shape**: `ReconcileCandidate` MUST carry `windowID: UInt32`, `app`, `windowTitle`, and `score: Int`, and its `id` MUST equal `windowID`.
- **reconcile-models-not-sendable**: `ReconcileItem` and `ReconcileCandidate` MUST NOT be declared `Sendable`; they are public structs without the conformance, so the compiler keeps them in the isolation domain that created them (the main actor, in `SystemWindowContextsModel`).
- **configuration-shape**: `SystemWindowContextsConfiguration` MUST be `Sendable` and hold `selfAppName: String?` (default `nil`), `settingsKey: String` (required), `contextNoun` (default `"context"`), `contextNounPlural` (default `contextNoun + "s"`), `notificationTitle` and `notificationIdentifier` (required), `defaultContexts: [DefaultContext]` (default `[]`), and `managesAppActivationPolicy: Bool` (default `true`).
- **error-descriptions-store**: Each `SystemWindowContextStoreError` case MUST produce its fixed English `errorDescription`: `directoryCreationFailed`, `encodingFailed`, `decodingFailed`, `writeFailed`, `readFailed` include the path (where present) and the underlying error's `localizedDescription`; `lockAcquisitionFailed` reads "Failed to acquire file lock at <path>"; `contextNotFound` reads "Context not found: <uuid>".
- **error-descriptions-manager**: Each `SystemWindowContextError` case MUST produce its fixed English `errorDescription` (for example `windowAlreadyAssigned` reads "Window <id> is already assigned to context '<name>'", `persistenceFailed` reads "Failed to persist state: <underlying>").
- **unraised-error-cases**: Callers MUST treat `SystemWindowContextError.alreadyActiveContext` and `.noActiveContext` as declared but unraised: no operation in these sources throws either case.

### Store: layout and I/O

- **store-layout**: `SystemWindowContextStore(rootDirectory:)` MUST place the state at `<root>/state.json`, one file per context at `<root>/contexts/<UUID uppercase string>.json`, and the lock file at `<root>/.lock`.
- **store-json-format**: The store MUST encode JSON pretty-printed with sorted keys and dates as ISO 8601, and MUST decode dates as ISO 8601.
- **store-ensure-directories**: `ensureDirectoryStructure()` MUST create `<root>` and `<root>/contexts` with intermediate directories, and MUST throw `directoryCreationFailed(path: <root>, underlying:)` when either creation fails.
- **store-load-state-missing**: `loadState()` MUST return `SystemWindowContextsState()` (no active context, no IDs) when `state.json` does not exist.
- **store-load-state-errors**: `loadState()` MUST throw `readFailed` when `state.json` exists but cannot be read, and `decodingFailed` when it cannot be decoded.
- **store-load-context-missing**: `loadContext(id:)` MUST throw `contextNotFound(id:)` when the context file does not exist, `readFailed` when it cannot be read, and `decodingFailed` when it cannot be decoded.
- **store-save-context**: `saveContext(_:)` MUST write the encoded context to its file with an atomic (write-then-replace) file write while holding the lock, throwing `encodingFailed` or `writeFailed` on failure.
- **store-delete-context**: `deleteContext(id:)` MUST remove the context file under the lock when it exists, and MUST succeed without effect when it does not; a removal failure propagates the underlying file-system error unwrapped.
- **store-load-all-order**: `loadAllContexts()` MUST return contexts in `state.contextIDs` order.
- **store-load-all-skips**: `loadAllContexts()` MUST skip any context whose file is missing, unreadable, or undecodable, logging "Skipping context <id>: <error>" at error level, rather than failing the whole load.
- **store-load-all-state-error**: `loadAllContexts()` MUST propagate the error when `state.json` itself cannot be read or decoded.
- **store-save-all-content**: `saveAll(contexts:activeContextID:)` MUST, under one lock, write every context's file and then write `state.json` with `activeContextID` and `contextIDs` equal to the contexts' IDs in the given order.
- **save-all-not-atomic**: NEEDS REVIEW: Not implemented in source. The doc comment says `saveAll` "updates the contexts state atomically", but each file is written independently; an encode or write failure on the Nth context throws after earlier context files are already replaced and before `state.json` is written, leaving disk partially updated. No rollback or journal exists; evidence that would settle it is whether the "atomically" contract is intended across files (a temp-directory swap) or only per file.
- **store-save-all-no-prune**: `saveAll` MUST NOT delete context files for IDs absent from `contexts`; orphan removal happens only through `deleteContext(id:)`.
- **store-list-files**: `listContextFiles()` MUST return `[]` when `<root>/contexts` is absent, MUST return the UUIDs parsed from every `*.json` filename whose stem is a valid UUID (ignoring other files), and MUST throw `readFailed` when the directory cannot be listed. The order MUST be treated as unspecified (directory listing order).
- **store-remove-all**: `removeAll()` MUST delete `<root>` recursively when it exists, without taking the lock, and propagate the underlying error unwrapped.
- **store-lock**: Every write operation (`saveContext`, `deleteContext`, `saveAll`) MUST first ensure the directory structure, open or create `<root>/.lock` with mode `0644`, take an exclusive `flock`, run the write, then unlock and close the descriptor exactly once.
- **store-lock-failure**: When the lock file cannot be opened, or the exclusive lock cannot be taken, the operation MUST throw `lockAcquisitionFailed(path:)` without running the write; on a failed lock the descriptor MUST be closed once.
- **store-lock-blocking**: The lock MUST block until acquired; there is no timeout and no non-blocking attempt.
- **store-reads-unlocked**: `loadState`, `loadContext`, `loadAllContexts`, and `listContextFiles` MUST NOT take the lock.
- **store-sendable**: `SystemWindowContextStore` MUST be usable from any thread (`@unchecked Sendable`); its safety rests on the write lock and on encoder and decoder instances that are configured once and never mutated.

### Manager: lifecycle and load

- **manager-main-actor**: `SystemWindowContextManager` MUST be confined to the main actor (`@MainActor`); every operation runs there and its state has no internal locking.
- **manager-init**: `init(windowManager:stateStore:windowMatcher:customHeuristicStore:)` MUST start with no contexts and no active context, and MUST default `customHeuristicStore` to a `CustomHeuristicStore` rooted at the state store's `rootDirectory`.
- **manager-load-state**: `loadState()` MUST read the active context ID and the contexts from the store, then invalidate stale window IDs, then load custom heuristic rules, and MUST propagate store read or decode errors on `state.json` unwrapped.
- **manager-load-no-active-check**: `loadState()` MUST keep a persisted `activeContextID` even when no loaded context has that ID (for example its file was skipped); `activeContext` then returns `nil`.
- **reconcile-stale-recycled**: On load, a snapshot whose `windowID` belongs to a live window of a different app (compared case-insensitively) MUST have its `windowID` cleared.
- **reconcile-stale-missing**: On load, a snapshot whose `windowID` is not in the live window list MUST have its `windowID` cleared only when its app has at least one live window; when its app has no live windows the `windowID` MUST be kept.
- **reconcile-stale-persist**: When at least one ID was cleared on load, the manager MUST log "Invalidated <n> stale window ID(s) on load" and persist; a persistence failure there MUST be logged and not thrown.
- **manager-root-directory**: `rootDirectory` MUST return the state store's root directory.

