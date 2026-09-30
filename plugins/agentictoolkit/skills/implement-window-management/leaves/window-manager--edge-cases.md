<!-- leaf: implement-window-management/window-manager--edge-cases · source: window-management-window-manager.md -->

# WindowManager

**Rules** (cite as `implement-window-management/window-manager--edge-cases#<slug>`):

- `empty-window-id` MUST — WindowRegistry.register(_:) MUST ignore a controller with an empty windowID; storage calls with an empty ID compose a …
- `duplicate-registration` MUST — Re-registering an ID MUST replace the previous weak entry; the earlier controller is no longer reachable through the …
- `duplicate-restorable-id` MUST — A second registerRestorable for the same ID MUST replace the first factory.
- `factory-that-does-not-register` MUST — A factory that builds nothing, or builds a controller that is not registered, MUST NOT stop the pass; if its window was …
- `repeated-restore` MUST — Calling restoreOnLaunch() twice MUST rerun every factory; idempotence of the factories is the host's responsibility.
- `ordering` MUST — Factory execution and the registry visibility pass MUST run in dictionary order, which is unspecified; a host that …
- `headless-run` MUST — reopenRecentsOnLaunch() MUST return without effect when NSApp is nil (unit tests).
- `recent-url-already-open` MUST — A recent URL that matches an open NSDocument's fileURL MUST NOT be opened again.
- `recents-limit-out-of-range` MUST — A zero or negative recentWindowsCount MUST be written to NSRecentDocumentsLimit unchanged; how AppKit interprets it is …
- `termination-during-close` MUST — Windows closed by AppKit after willTerminate MUST keep their persisted visibility; once latched, isTerminating never …
- `deallocated-controller` MUST — A registry entry whose controller was released MUST read as absent from controller(forID:), registeredIDs, visibleIDs …
- `sunk-window` MUST — A window sunk behind the desktop by quiet presentation MUST still count as visible …
- `undecodable-stored-state` MUST — Corrupt or non-JSON WindowState_ data MUST read as nil; the next save overwrites it.
- `missing-or-non-boolean-visibility-value` MUST — A missing key MUST read as nil in both implementations; a non-boolean value reads as nil in the UserDefaults …
- `two-app-copies` MUST — Without isolateToRunningBundle(), two builds sharing a bundle identifier MUST share window-state keys; the last writer …
- `namespace-changed-mid-run` MUST — Keys written before a namespace change MUST stay under the old prefix and are not migrated.
- `namespace-collision` MUST — Two paths whose SHA-256 digests share their first 4 bytes MUST share a namespace (a 1-in-2^32 chance per pair); the …
- `missing-capture-symbol` MUST — If CoreGraphics stops exporting CGWindowListCreateImage, captureOwnWindow(_:) MUST return nil and writePNG(of:to:) MUST …
- `unwritable-screenshot-url` MUST — The write error MUST be converted to a false return; the error itself is not surfaced.

## Edge Cases

- **Empty window ID**: `WindowRegistry.register(_:)` MUST ignore a controller with an empty `windowID`; storage calls with an empty ID compose a key that is just the prefix and MUST behave like any other key.
- **Duplicate registration**: Re-registering an ID MUST replace the previous weak entry; the earlier controller is no longer reachable through the registry even if still alive.
- **Duplicate restorable ID**: A second `registerRestorable` for the same ID MUST replace the first factory.
- **Factory that does not register**: A factory that builds nothing, or builds a controller that is not registered, MUST NOT stop the pass; if its window was persisted visible, the missing-factory check does not fire because a factory exists for the ID (the check only looks for a missing factory and a missing controller together).
- **Repeated restore**: Calling `restoreOnLaunch()` twice MUST rerun every factory; idempotence of the factories is the host's responsibility.
- **Ordering**: Factory execution and the registry visibility pass MUST run in dictionary order, which is unspecified; a host that needs one window shown before another cannot rely on registration order.
- **Headless run**: `reopenRecentsOnLaunch()` MUST return without effect when `NSApp` is nil (unit tests).
- **Recent URL already open**: A recent URL that matches an open `NSDocument`'s `fileURL` MUST NOT be opened again.
- **Recent document missing on disk**: The open request is issued; the failure is discarded (see the open question on reopen-open-failure).
- **Recents limit out of range**: A zero or negative `recentWindowsCount` MUST be written to `NSRecentDocumentsLimit` unchanged; how AppKit interprets it is AppKit's behavior.
- **Termination during close**: Windows closed by AppKit after `willTerminate` MUST keep their persisted visibility; once latched, `isTerminating` never clears within the process.
- **Deallocated controller**: A registry entry whose controller was released MUST read as absent from `controller(forID:)`, `registeredIDs`, `visibleIDs` and `hasVisibleWindow`.
- **Sunk window**: A window sunk behind the desktop by quiet presentation MUST still count as visible (`WindowRegistryVisibilityTests.testASunkWindowStillCountsAsVisible`).
- **Undecodable stored state**: Corrupt or non-JSON `WindowState_` data MUST read as `nil`; the next save overwrites it.
- **Missing or non-boolean visibility value**: A missing key MUST read as `nil` in both implementations; a non-boolean value reads as `nil` in the UserDefaults implementation and `false` in the SettingsStore implementation.
- **Two app copies**: Without `isolateToRunningBundle()`, two builds sharing a bundle identifier MUST share window-state keys; the last writer wins.
- **Namespace changed mid-run**: Keys written before a namespace change MUST stay under the old prefix and are not migrated.
- **Namespace collision**: Two paths whose SHA-256 digests share their first 4 bytes MUST share a namespace (a 1-in-2^32 chance per pair); the source accepts this.
- **Concurrent access**: All manager, registry and storage operations run on the main actor and are serialized; `WindowStateNamespace` reads and writes are serialized by its unfair lock.
- **Missing capture symbol**: If CoreGraphics stops exporting `CGWindowListCreateImage`, `captureOwnWindow(_:)` MUST return `nil` and `writePNG(of:to:)` MUST return `false`.
- **Unwritable screenshot URL**: The write error MUST be converted to a `false` return; the error itself is not surfaced.
- **Offline or disconnected state**: Not applicable; the component performs no network I/O.
