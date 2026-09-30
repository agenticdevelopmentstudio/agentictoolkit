<!-- leaf: implement-window-management/window-manager--part-2 · source: window-management-window-manager.md -->

# WindowManager — continued (part 2)

**Rules** (cite as `implement-window-management/window-manager--part-2#<slug>`):

- `main-actor-isolation` MUST
- `namespace-thread-safety` MUST
- `screenshot-isolation` MUST
- `shared-instance` MUST
- `single-screen-manager` MUST
- `frames-ownership` MUST
- `registry-ownership` MUST
- `self-registration-target` MUST
- `recent-limit-on-init` MUST
- `recent-limit-mirror` MUST
- `recent-limit-weak-capture` MUST
- `termination-observer` MUST
- `terminating-default` MUST
- `terminating-latch` MUST
- `terminating-one-way` MUST
- `terminating-consumer` MUST
- `interaction-kinds` MUST
- `close-ignored` MUST
- `spec-gate` MUST
- `document-recent` MUST
- `non-document-recents-noop` MUST
- `document-url` MUST
- `recent-limit-write` MUST
- `recent-limit-default` MUST
- `register-restorable` MUST
- `restore-builds-all` MUST
- `restore-visibility-pass` MUST
- `restore-visibility-rule` MUST
- `restore-missing-factory-log` MUST
- `restore-then-reopen` MUST
- `restore-reentrant` MAY
- `visible-ids-default` MUST
- `reopen-no-app` MUST
- `reopen-policy` MUST
- `reopen-policy-default` MUST
- `reopen-system-default` MUST
- `reopen-disabled-closes` MUST
- `reopen-disabled-keeps-others` MUST
- `reopen-enabled-opens-recents` MUST
- `reopen-all-recents` MUST
- `registry-register` MUST
- `registry-empty-id` MUST
- `registry-lookup` MUST
- `registry-registered-ids` MUST
- `registry-visible-ids` MUST
- `registry-has-visible` MUST
- `registry-single-visibility-definition` MUST
- `registry-no-pruning` MUST

## Behavioral Requirements

### Isolation and ownership

- **main-actor-isolation**: `WindowManager`, `WindowRegistry`, the `WindowStateStorage` protocol and `SettingsStoreWindowStateStorage` MUST be isolated to the main actor; every operation on them MUST run on the main thread.
- **namespace-thread-safety**: `WindowStateNamespace` MUST be callable from any thread; its current prefix MUST be guarded by a lock rather than by actor isolation.
- **screenshot-isolation**: `WindowScreenshot.captureOwnWindow(_:)` MUST be callable from any thread, and `WindowScreenshot.writePNG(of:to:)` MUST run on the main actor.
- **shared-instance**: `WindowManager.shared` MUST be a single process-wide instance built with the shared `ScreenManager`.
- **single-screen-manager**: A `WindowManager` constructed without a `screenManager` MUST use `ScreenManager.shared`, never a newly created `ScreenManager`, so exactly one instance owns the persisted screen-set list and the screen-change observer.
- **frames-ownership**: Each `WindowManager` MUST create exactly one `WindowFrameManager` from its `screenProvider`, `storage` and screen manager, and expose it as `frames`.
- **registry-ownership**: Each `WindowManager` MUST create exactly one empty `WindowRegistry` and expose it as `registry`.
- **self-registration-target**: A `SingleWindowController` MUST register itself with `WindowManager.shared.registry` during its initializer; a separately constructed `WindowManager`'s registry is populated only by explicit `register(_:)` calls.

### Initialization side effects

- **recent-limit-on-init**: The initializer MUST write `UserSettings.recentWindowsCount.currentValue` to the `NSRecentDocumentsLimit` key in standard user defaults before returning.
- **recent-limit-mirror**: After initialization, every change published by `UserSettings.recentWindowsCount` MUST be re-applied to `NSRecentDocumentsLimit`, delivered on the main run loop.
- **recent-limit-weak-capture**: The settings subscription MUST hold the manager weakly, so it does not keep the manager alive.
- **termination-observer**: The initializer MUST subscribe to `NSApplication.willTerminateNotification` from any sender.

### Termination latch

- **terminating-default**: `isTerminating` MUST be `false` after initialization.
- **terminating-latch**: When `NSApplication.willTerminateNotification` is posted, `isTerminating` MUST become `true`.
- **terminating-one-way**: The manager MUST NOT reset `isTerminating` to `false` on its own; only module-internal code (tests) can write it.
- **terminating-consumer**: `SingleWindowController.windowWillClose(_:)` MUST skip persisting `visible = false` while `WindowManager.shared.isTerminating` is `true`, and MUST persist it when `isTerminating` is `false`.

### Recents recording

- **interaction-kinds**: `InteractionKind` MUST have exactly two cases, `show` and `close`, and MUST be `Sendable`.
- **close-ignored**: `windowDidInteract(_:kind:)` with `.close` MUST have no effect.
- **spec-gate**: `windowDidInteract(_:kind:)` with `.show` MUST have no effect when the controller has no `windowSpec` or when the spec's `behavior` does not contain `.includeInRecents`.
- **document-recent**: `windowDidInteract(_:kind:)` with `.show`, a spec containing `.includeInRecents`, and a non-nil `documentURL` MUST pass that URL to `NSDocumentController.shared.noteNewRecentDocumentURL(_:)`.
- **non-document-recents-noop**: A non-document window (nil `documentURL`) that passes the spec gate MUST NOT be recorded anywhere; the source states single-window tracking "lands in a follow-up slice with `WindowRecentsTracker`".
- **document-url**: `SingleWindowController.documentURL` MUST return the `fileURL` of the controller's document when the document is an `NSDocument`, and `nil` otherwise.

### Recent-document limit

- **recent-limit-write**: `applyRecentDocumentCountFromSettings()` MUST write the current `UserSettings.recentWindowsCount` value, unchanged and unvalidated, to the `NSRecentDocumentsLimit` user default.
- **recent-limit-default**: `UserSettings.recentWindowsCount` MUST default to `10`.

### Launch restore

- **register-restorable**: `registerRestorable(id:make:)` MUST store `make` under `id`, replacing any factory previously stored under the same `id`, and MUST NOT call `make`.
- **restore-builds-all**: `restoreOnLaunch()` MUST call every registered factory exactly once per invocation, in unspecified order.
- **restore-visibility-pass**: After running the factories, `restoreOnLaunch()` MUST call `restoreVisibilityIfNeeded()` on the live controller for every ID in `registry.registeredIDs`.
- **restore-visibility-rule**: `restoreVisibilityIfNeeded()` MUST show the window only when the controller's spec has `persistsVisibility` and the last persisted visibility for its `windowID` is exactly `true`; a persisted `false` or no persisted value MUST leave it closed.
- **restore-missing-factory-log**: For each ID returned by `frames.visibleWindowIDs()` that has neither a registered factory nor a live registry controller, `restoreOnLaunch()` MUST log one error `restoreOnLaunch: visible window '<id>' has no registered factory` with the ID marked public.
- **restore-then-reopen**: `restoreOnLaunch()` MUST call `reopenRecentsOnLaunch()` after the visibility pass and the missing-factory check.
- **restore-reentrant**: `restoreOnLaunch()` MAY be called again (the source recommends it on reactivation, such as a second-launch distributed notification); each call reruns every factory and the full pass.
- **visible-ids-default**: A `WindowStateStorage` that does not implement `visibleWindowIDs()` MUST report an empty list.
- **visible-ids-settings-store**: NEEDS REVIEW: Not implemented in source. `SettingsStoreWindowStateStorage`, the default storage of `WindowManager` and `WindowManager.shared`, does not implement `visibleWindowIDs()`, so it inherits the empty default and the missing-factory error declared by the `WindowStateStorage` doc comment ("Lets `WindowManager.restoreOnLaunch()` detect a window that was visible but has no registered factory") never fires in the default configuration; settling it needs either a `SettingsStore` key-enumeration API or an explicit statement that the check is UserDefaults-storage-only.

### Reopen on launch

- **reopen-no-app**: `reopenRecentsOnLaunch()` MUST return without effect when no `NSApplication` instance exists.
- **reopen-policy**: The decision MUST be `UserSettings.reopenOnLaunchPolicy.currentValue.shouldReopen(systemDefault:)`, where `useSystem` returns the system default, `always` returns `true` and `never` returns `false`.
- **reopen-policy-default**: `UserSettings.reopenOnLaunchPolicy` MUST default to `useSystem`.
- **reopen-system-default**: The system default MUST be the boolean value of the `NSQuitAlwaysKeepsWindows` user default, reading `false` when the key is absent.
- **reopen-disabled-closes**: When the decision is not to reopen, the method MUST close, through its window controller, every app window whose window controller has a non-nil document, and MUST open nothing.
- **reopen-disabled-keeps-others**: When the decision is not to reopen, windows without a window controller or whose controller has no document MUST be left open.
- **reopen-enabled-opens-recents**: When the decision is to reopen, the method MUST request `NSDocumentController.shared.openDocument(withContentsOf:display:completionHandler:)` with `display: true` for every URL in `NSDocumentController.shared.recentDocumentURLs` that is not already the `fileURL` of an open window's `NSDocument`.
- **reopen-all-recents**: When the decision is to reopen, the method MUST open every recent URL, not only the documents that were open when the app last quit; `canReopenOnLaunch` in the window spec is not consulted.
- **reopen-open-failure**: NEEDS REVIEW: Not implemented in source. The `openDocument` completion handler is empty, so a recent document that fails to open (moved, deleted, unreadable) produces no log, no user-facing error and no removal from recents; settling it needs a decision on whether failures are logged, presented, or pruned.

### Window registry

- **registry-register**: `register(_:)` MUST store a weak reference to the controller under its `windowID`, replacing any prior entry for that ID.
- **registry-empty-id**: `register(_:)` MUST ignore a controller whose `windowID` is the empty string.
- **registry-lookup**: `controller(forID:)` MUST return the live controller registered under the ID, or `nil` when none was registered or the registered controller has been deallocated.
- **registry-registered-ids**: `registeredIDs` MUST list the IDs of every registered controller that is still alive, whether or not its window is open, in unspecified order.
- **registry-visible-ids**: `visibleIDs` MUST list the IDs of registered, alive controllers whose `isVisible` is `true`, in unspecified order.
- **registry-has-visible**: `hasVisibleWindow` MUST be `true` exactly when at least one registered, alive controller has `isVisible == true`.
- **registry-single-visibility-definition**: `visibleIDs` and `hasVisibleWindow` MUST use the same visibility test, `controller?.isVisible == true`.
- **registry-no-pruning**: Entries for deallocated controllers MUST remain in storage until the same ID is re-registered; they are filtered out of every read.

