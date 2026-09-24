---
id: 61c7b509-78d1-4407-9a4e-25b155f06fbb
title: WindowManager
domain: agentictoolkit://recipes/window-management-window-manager
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: macOS main-actor coordinator for window frame and visibility persistence,
  the live window registry, launch restore and document recents.
platforms:
- swift
- macos
tags:
- window-management
- persistence
- recents
- macos
depends-on:
- agentictoolkit://recipes/settings-storage
- agentictoolkit://recipes/window-management-screen-manager
- agentictoolkit://recipes/single-window-controller
related:
- agentictoolkit://recipes/window-management-recents
references: []
approved-by: ''
approved-date: ''
---

# WindowManager

## Overview

`WindowManager` (in `WindowManager.swift`) is the top-level coordinator for the
toolkit's macOS window infrastructure. It owns:

- `frames`, a `WindowFrameManager` that persists window frames and visibility
  and reacts to screen changes (specified by the frame-manager and
  [ScreenManager](agentictoolkit://recipes/window-management-screen-manager)
  recipes);
- `registry`, a `WindowRegistry` that looks up live `SingleWindowController`s by
  `windowID` through weak references;
- the launch-restore pass (`registerRestorable(id:make:)`, `restoreOnLaunch()`,
  `reopenRecentsOnLaunch()`);
- document recents recording (`windowDidInteract(_:kind:)`) and the mirror of
  `UserSettings.recentWindowsCount` into AppKit's recent-documents limit;
- an app-termination latch (`isTerminating`) that lets
  [SingleWindowController](agentictoolkit://recipes/single-window-controller)
  tell a user close from a quit close.

The recipe also covers the persistence layer it is built on: the
`WindowStateStorage` protocol, its two implementations
(`SettingsStoreWindowStateStorage`, the default, and
`UserDefaultsWindowStateStorage`), the `WindowStateNamespace` key prefix that
lets two copies of one app keep separate layouts, and the `WindowScreenshot`
own-window capture utility that lives in the same folder.

Production code uses `WindowManager.shared`; tests construct an isolated
instance with a mock `ScreenProvider`, in-memory storage and an isolated
`ScreenManager`.

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

### Window state storage

- **storage-protocol**: `WindowStateStorage` MUST provide `loadState(for:)`, `saveState(_:for:)`, `removeState(for:)`, `loadVisibility(for:)`, `saveVisibility(_:for:)`, `removeVisibility(for:)` and `visibleWindowIDs()`, all keyed by window ID string.
- **storage-independent-keys**: Frame state and visibility MUST be stored under separate keys so a window can persist one without the other.
- **storage-key-format**: The frame key MUST be `WindowStateNamespace.current + keyPrefix + id` and the visibility key MUST be `WindowStateNamespace.current + visibilityKeyPrefix + id`.
- **storage-key-defaults**: `keyPrefix` MUST default to `WindowState_` and `visibilityKeyPrefix` MUST default to `WindowVisible_` in both implementations.
- **storage-namespace-late-binding**: Both implementations MUST read the namespace when composing each key, not at construction, so a namespace set after a storage was created applies to it.
- **storage-state-json**: `PersistedWindowState` MUST be stored as JSON-encoded `Data` in both implementations, so either implementation reads state the other wrote over the same defaults domain.
- **storage-visibility-native**: Visibility MUST be stored as a native boolean (not JSON) in both implementations.
- **storage-visibility-tristate**: `loadVisibility(for:)` MUST return `nil` when the key has never been written, and the stored boolean otherwise, so "never shown" is distinct from "explicitly hidden".
- **storage-remove**: `removeState(for:)` and `removeVisibility(for:)` MUST delete the key, after which the matching load returns `nil`.
- **userdefaults-target**: `UserDefaultsWindowStateStorage` MUST read and write `UserDefaults.standard`.
- **userdefaults-visible-ids**: `UserDefaultsWindowStateStorage.visibleWindowIDs()` MUST return, in unspecified order, the ID suffix of every standard-defaults key that starts with `WindowStateNamespace.current + visibilityKeyPrefix` and whose value is the boolean `true`.
- **settings-store-target**: `SettingsStoreWindowStateStorage` MUST route every key through its injected `SettingsStore` with `isSecure == false`, so values land in the store's non-secure provider.
- **settings-store-change-signal**: Writes and removals through `SettingsStoreWindowStateStorage` MUST emit the key name on the store's `changes` publisher when the provider emits (the UserDefaults provider does); `UserDefaultsWindowStateStorage` emits nothing.
- **settings-store-non-bool-visibility**: When a visibility key exists but does not hold a boolean, `SettingsStoreWindowStateStorage.loadVisibility(for:)` MUST return `false` (the setting's default), whereas `UserDefaultsWindowStateStorage` returns `nil`.
- **storage-codec-failure**: NEEDS REVIEW: Not implemented in source. In both implementations a `PersistedWindowState` that fails to encode is silently not written, and stored data that fails to decode reads as `nil` (never saved), with no log or error to the caller; settling it needs a decision on whether codec failures are logged or surfaced.

### Namespace

- **namespace-default**: `WindowStateNamespace.current` MUST be the empty string until a host sets a namespace, so un-namespaced keys match the existing on-disk format.
- **namespace-qualify**: `qualify(_:)` MUST return `current + key`.
- **namespace-token**: `isolate(toPath:)` MUST set `current` to `Instance` + the lowercase hex of the first 4 bytes of the SHA-256 of the path's UTF-8 bytes + `_` (8 hex characters).
- **namespace-stable**: `isolate(toPath:)` MUST produce the same prefix for the same path on every call and launch.
- **namespace-no-raw-path**: The prefix MUST NOT contain any substring of the path.
- **namespace-bundle**: `isolateToRunningBundle(_:)` MUST call `isolate(toPath:)` with the bundle's standardized bundle-URL path, defaulting to the main bundle.
- **namespace-reset**: `reset()` MUST set `current` back to the empty string.
- **namespace-host-timing**: A host that wants isolation MUST call `isolateToRunningBundle()` before it first touches `WindowManager` (per the type's doc comment); keys written earlier stay under the previous prefix.

### Window screenshot

- **screenshot-capture**: `captureOwnWindow(_:)` MUST return a `CGImage` of the given window captured with `optionIncludingWindow`, `boundsIgnoreFraming` and `bestResolution` over a null rectangle, or `nil` when the capture fails.
- **screenshot-symbol-missing**: When the `CGWindowListCreateImage` symbol cannot be resolved at runtime, `captureOwnWindow(_:)` MUST return `nil` rather than crash.
- **screenshot-symbol-once**: The symbol MUST be resolved at most once per process.
- **screenshot-no-permission**: Own-window capture MUST NOT require or request Screen Recording permission.
- **screenshot-png-offscreen**: `writePNG(of:to:)` MUST return `false` and write nothing when the window's `windowNumber` is not positive.
- **screenshot-png-failure**: `writePNG(of:to:)` MUST return `false` when capture, PNG encoding or the file write fails.
- **screenshot-png-success**: `writePNG(of:to:)` MUST write PNG data to the URL and return `true` when every step succeeds.

## Appearance

Not applicable — this is a window-state coordination and persistence service, not a visual component.

## States

Not applicable — this is a window-state coordination and persistence service, not a visual component.

## Accessibility

Not applicable — this is a window-state coordination and persistence service, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wm-001 | terminating-default, terminating-latch | Fresh manager; post `NSApplication.willTerminateNotification` | `isTerminating` is `false` before, `true` after (`WindowManagerTerminationTests`) |
| wm-002 | terminating-consumer | Visibility-persisting controller shown (visibility `true`); `isTerminating = true`; call `windowWillClose(_:)` | Persisted visibility stays `true` |
| wm-003 | terminating-consumer | Same, `isTerminating == false`; call `windowWillClose(_:)` | Persisted visibility becomes `false` |
| wm-004 | recent-limit-write | `recentWindowsCount = 7`, call `applyRecentDocumentCountFromSettings()`; then `3` and call again | `NSRecentDocumentsLimit` reads `7`, then `3` (`WindowManagerRecentsTests`) |
| wm-005 | recent-limit-mirror, recent-limit-on-init | Touch `WindowManager.shared`; set `recentWindowsCount = 12`; wait one main-queue turn | `NSRecentDocumentsLimit` reads `12` |
| wm-006 | register-restorable, restore-builds-all | Register factories `alpha` and `beta`; call `restoreOnLaunch()` | Both factories ran; built set is `{alpha, beta}` (`WindowManagerSimulatedRelaunchTests`) |
| wm-007 | register-restorable | Call `registerRestorable(id:make:)` without calling `restoreOnLaunch()` | Factory has not run |
| wm-008 | register-restorable | Register two factories under the same ID; call `restoreOnLaunch()` | Only the second factory runs |
| wm-009 | restore-visibility-pass, restore-visibility-rule | Registered visibility-persisting controller with persisted visibility `true`; `restoreOnLaunch()` | Window is shown |
| wm-010 | restore-visibility-rule | Same with persisted `false`, and again with no persisted value | Window stays closed in both cases |
| wm-011 | restore-missing-factory-log | `UserDefaultsWindowStateStorage` with visibility `true` for `ghost`; no factory, no controller; `restoreOnLaunch()` | One error log naming `ghost` |
| wm-012 | reopen-no-app | Headless process with no `NSApplication`; `reopenRecentsOnLaunch()` | Returns; no crash; nothing opened |
| wm-013 | reopen-policy | `shouldReopen(systemDefault:)` for `useSystem`/`always`/`never` with `true` and `false` | `true`/`false`; `true`/`true`; `false`/`false` |
| wm-014 | reopen-disabled-closes, reopen-disabled-keeps-others | Policy `never`; one document window and one non-document window open; `reopenRecentsOnLaunch()` | Document window's controller closed; non-document window still open |
| wm-015 | reopen-enabled-opens-recents | Policy `always`; recents `[A, B]`; `A` already open | One open request, for `B`, with `display: true` |
| wm-016 | close-ignored | `windowDidInteract(controller, kind: .close)` with an `.includeInRecents` document controller | No recent URL noted |
| wm-017 | spec-gate | `.show` for a document controller whose spec lacks `.includeInRecents` (and one with no spec) | No recent URL noted |
| wm-018 | document-recent | `.show` for a controller with default behavior and document URL `U` | `noteNewRecentDocumentURL(U)` called once |
| wm-019 | registry-register, registry-lookup | Register controller `a`; look up `a` and `b` | Returns the controller for `a`, `nil` for `b` |
| wm-020 | registry-empty-id | Register a controller with `windowID == ""` | `registeredIDs` is empty |
| wm-021 | registry-registered-ids, registry-has-visible | Register a controller without showing it | `registeredIDs` contains it; `hasVisibleWindow` is `false` (`WindowRegistryVisibilityTests`) |
| wm-022 | registry-visible-ids, registry-has-visible | Register and show a controller | `visibleIDs` contains it; `hasVisibleWindow` is `true` |
| wm-023 | registry-has-visible | Show then `dismiss()` the only controller | `hasVisibleWindow` is `false` |
| wm-024 | registry-has-visible | One closed and one shown controller | `hasVisibleWindow` is `true` |
| wm-025 | registry-lookup, registry-no-pruning | Register, show, dismiss, release the only strong reference | `controller(forID:)` is `nil`; `hasVisibleWindow` is `false` |
| wm-026 | storage-visibility-tristate | Fresh key; load; save `false`; load | `nil`, then `false` |
| wm-027 | storage-remove | Save state and visibility for `w`; remove both; load both | Both `nil` |
| wm-028 | storage-key-format, namespace-default | Namespace empty; save visibility for `log` with default prefixes | Defaults key is `WindowVisible_log` |
| wm-029 | namespace-default, namespace-qualify | `qualify("WindowState_log")` with no namespace set | `WindowState_log` (`WindowStateNamespaceTests`) |
| wm-030 | namespace-token, namespace-stable | `isolate(toPath: "/a/worktree/Stenographer.app")` | `current == "Instance2e03b243_"`; same value on a repeat call |
| wm-031 | namespace-token | `isolate(toPath: "/another/worktree/Stenographer.app")` | `current == "Instance30aace28_"`, differs from wm-030 |
| wm-032 | namespace-no-raw-path | `isolate(toPath: "/Users/someone/secret-project/Stenographer.app")` | `current` contains neither `someone` nor `secret-project` |
| wm-033 | storage-namespace-late-binding, userdefaults-visible-ids | Save state and visibility `true` for `log` un-namespaced; isolate; load both and list visible IDs; save visibility `false`; reset; load | Namespaced loads are `nil` and `log` is not listed; after reset visibility is `true` and `log` is listed |
| wm-034 | namespace-reset | Isolate to any path, then `reset()` | `current == ""` |
| wm-035 | storage-state-json | Save a state through `SettingsStoreWindowStateStorage` over a UserDefaults-backed store; load through `UserDefaultsWindowStateStorage` | Equal state returned |
| wm-036 | settings-store-non-bool-visibility | Write the string `"x"` under `WindowVisible_w`; load via each implementation | `SettingsStoreWindowStateStorage` returns `false`; `UserDefaultsWindowStateStorage` returns `nil` |
| wm-037 | visible-ids-default | Storage double that omits `visibleWindowIDs()` | Returns `[]` |
| wm-038 | screenshot-capture | `captureOwnWindow(0)` | `nil` (`WindowScreenshotTests`) |
| wm-039 | screenshot-png-offscreen | `writePNG(of:to:)` on a never-ordered-in window | Returns `false`; no file at the URL |
| wm-040 | screenshot-png-success | `writePNG(of:to:)` on an on-screen window owned by the process, writable URL | Returns `true`; file holds PNG data |
| wm-041 | screenshot-png-failure | On-screen window; URL in a non-existent directory | Returns `false` |
| wm-042 | single-screen-manager | `WindowManager(screenProvider:storage:)` with no `screenManager` | `frames` uses `ScreenManager.shared` |

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `screenProvider` | `ScreenProvider` | `RealScreenProvider()` | Source of live screens, passed to `WindowFrameManager`. |
| `storage` | `WindowStateStorage` | `SettingsStoreWindowStateStorage(settings: UserSettings.shared)` | Persistence for frames and visibility. |
| `screenManager` | `ScreenManager?` | `nil` (resolved to `ScreenManager.shared`) | Owner of the screen-set list and screen-change observer. |
| `keyPrefix` | `String` | `"WindowState_"` | Frame-state key prefix (both storage implementations). |
| `visibilityKeyPrefix` | `String` | `"WindowVisible_"` | Visibility key prefix (both storage implementations). |
| `settings` | `SettingsStore` | none (required) | Store backing `SettingsStoreWindowStateStorage`. |
| `UserSettings.recentWindowsCount` | `UserSetting<Int>` (`recentWindowsCount`) | `10` | Mirrored into `NSRecentDocumentsLimit`. |
| `UserSettings.reopenOnLaunchPolicy` | `UserSetting<ReopenOnLaunchPolicy>` (`reopenOnLaunchPolicy`) | `.useSystem` | Whether recent documents reopen at launch. |
| `NSQuitAlwaysKeepsWindows` | system user default (`Bool`) | `false` when absent | System default consulted by `.useSystem`. |
| `NSRecentDocumentsLimit` | user default (`Int`) | written by the manager | AppKit's recent-documents cap. |
| `WindowStateNamespace` | process-wide prefix | `""` | Set by `isolateToRunningBundle(_:)` / `isolate(toPath:)`, cleared by `reset()`. |
| restorable factories | `[String: @MainActor () -> Void]` | empty | Registered by the host via `registerRestorable(id:make:)`. |

## Deep Linking

Not applicable: the source registers no URL scheme or route; restore is driven by `restoreOnLaunch()` and document recents by `NSDocumentController`.

## Localization

Not applicable: the source produces no user-facing strings; its only text is a developer log line and the `displayName` of `ReopenOnLaunchPolicy`, which belongs to the settings UI rather than this component.

## Accessibility Options

Not applicable: the component renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: the source reads no feature flag; the user settings it reads (`recentWindowsCount`, `reopenOnLaunchPolicy`) are preferences, not flags.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

- **Data collected**: Per window ID, a `PersistedWindowState` (frame placements per screen set, including display UUID and localized display name fingerprints) and a visibility boolean; document URLs passed to the system recent-documents list.
- **Storage**: Window state and visibility in the settings store's non-secure provider (UserDefaults by default) or directly in `UserDefaults.standard`; recents in AppKit's recent-documents store. The namespace prefix is a hash, so a build path never reaches the preferences file.
- **Transmission**: None from this component; a `SettingsStore` backed by the iCloud provider syncs these keys through that provider.
- **Retention**: Until removed by `removeState(for:)` / `removeVisibility(for:)` or the preferences domain is deleted; recents are capped by `NSRecentDocumentsLimit`.

## Logging

Subsystem: `com.agentic-cookbook.agentictoolkit` | Category: `WindowManager`

| Event | Level | Message |
|-------|-------|---------|
| Persisted-visible window with no factory and no live controller during `restoreOnLaunch()` | error | `restoreOnLaunch: visible window '<id>' has no registered factory` (ID public) |

Registry changes, storage reads and writes, codec failures, reopen decisions, document-open failures and screenshot failures are not logged.

## Platform Notes

- **SwiftUI**: No SwiftUI in the source. A SwiftUI macOS app gets frame persistence from `Window`/`WindowGroup` scene autosave and `defaultPosition`/`defaultSize`, and document recents from `DocumentGroup`; launch restore of utility windows still needs a coordinator like this one calling `openWindow(id:)` for IDs saved visible, with `@AppStorage` or `SceneStorage` in place of `WindowStateStorage`.
- **Compose**: Compose for Android has no multi-window desktop model; a Compose Desktop port starts from `rememberWindowState` and `WindowPosition`, persists with DataStore plus `kotlinx.serialization`, keeps the registry as a `Map<String, WeakReference<…>>` confined to `Dispatchers.Main`, and replaces the termination latch with an `ApplicationScope` exit hook. The namespace hash maps to `MessageDigest.getInstance("SHA-256")`.
- **React/Web**: Browsers own window placement; an Electron port starts from `BrowserWindow.getBounds`/`setBounds`, `app.on('before-quit')` for the termination latch, `app.addRecentDocument` for recents, `electron-store` or `localStorage` with `JSON.stringify` for storage, `webContents.capturePage()` for screenshots, and Node `crypto.createHash('sha256')` for the namespace.
- **AppKit / UIKit**: Source files: `WindowManager.swift` (Combine sink on `UserSettings.recentWindowsCount`, selector-based `NotificationCenter` observer for `willTerminateNotification`, `os.Logger`, `NSDocumentController` recents and reopen), `WindowRegistry.swift` (weak boxes over `SingleWindowController`), `WindowStateStorage.swift`, `SettingsStoreWindowStateStorage.swift` (`StorableSetting` keys through `SettingsStore`), `UserDefaultsWindowStateStorage.swift` (`JSONEncoder`/`JSONDecoder` over `UserDefaults.standard`, `dictionaryRepresentation()` scan), `WindowStateNamespace.swift` (`OSAllocatedUnfairLock`, CryptoKit `SHA256`), `WindowScreenshot.swift` (`dlsym` of `CGWindowListCreateImage`, `NSBitmapImageRep` PNG). UIKit has no free-floating windows; scene restoration (`stateRestorationActivity`, `UISceneSession.userInfo`) replaces frame and visibility persistence.
- **WinUI 3**: Start from `Microsoft.UI.Windowing.AppWindow` (`Position`, `Size`, `MoveAndResize`, `Show`/`Hide`, `IsVisible`, `Closing` event) with `DisplayArea` for screen bounds. Keep the manager and registry on the UI thread via `DispatcherQueue`; hold controllers in a `Dictionary<string, WeakReference<T>>` and expose `VisibleIds`/`HasVisibleWindow` through `INotifyPropertyChanged` if bound. Persist `PersistedWindowState` with `System.Text.Json` into `Windows.Storage.ApplicationData.Current.LocalSettings` (the 8 KB per-value limit favors one key per window, as the source already does) and store visibility as a native `bool` value so absence stays distinguishable via `ContainsKey`. Replace `willTerminateNotification` with `Application.Current` exit handling or `AppWindow.Closing` plus an app-level shutdown flag; replace the Combine settings sink with a `PropertyChanged` handler. Document recents map to `Windows.Storage.AccessCache.StorageApplicationPermissions.MostRecentlyUsedList` (with `MaximumItemsAllowed` in place of `NSRecentDocumentsLimit`) and jump lists (`Windows.UI.StartScreen.JumpList`). The namespace hash is `System.Security.Cryptography.SHA256.HashData`, guarded with `lock`. Own-window screenshots use `Windows.Graphics.Capture` with `GraphicsCaptureItem.TryCreateFromWindowId` or `RenderTargetBitmap` for XAML content, encoded with `BitmapEncoder.PngEncoderId`. Windows coordinates are top-left origin, unlike AppKit.

## Design Decisions

**Decision**: `WindowManager` is a thin coordinator over two sub-services (`frames`, `registry`) instead of one type that does everything.
**Rationale**: The type doc comment directs most callers to a sub-service (`frames.restoreFrame(...)`, `registry.controller(forID:)`); frame persistence and live lookup change independently.
**Approved**: pending

**Decision**: An omitted `screenManager` resolves to `ScreenManager.shared`, never a new instance.
**Rationale**: Per the initializer comment, a second `ScreenManager` on the same persistence key would clobber the real one's state and double-register the notification observer.
**Approved**: pending

**Decision**: Termination is latched with a one-way `isTerminating` flag read by `SingleWindowController.windowWillClose(_:)`.
**Rationale**: AppKit sends `windowWillClose:` to still-visible windows after `applicationWillTerminate`; persisting hidden there stopped windows left open from reopening (`WindowManagerTerminationTests`).
**Approved**: pending

**Decision**: Restore is driven by registered factories (`registerRestorable`) rather than hosts hand-constructing controllers.
**Rationale**: The doc comment says this ensures "a window can't silently miss restore"; the missing-factory error log exists to surface the remaining wiring gap loudly.
**Approved**: pending

**Decision**: The recent-documents cap is set by writing the `NSRecentDocumentsLimit` user default.
**Rationale**: `NSDocumentController.maximumRecentDocumentCount` is read-only; the default is the public knob and avoids subclassing `NSDocumentController`.
**Approved**: pending

**Decision**: When reopen is disabled the manager actively closes document windows AppKit restored.
**Rationale**: The comment calls this overriding AppKit's own state restoration; it closes through the window controller so the controller, not just the window, is torn down.
**Approved**: pending

**Decision**: The registry holds weak references and never prunes dead entries.
**Rationale**: A dropped controller "naturally disappears" from lookups; the number of window IDs is small and bounded, so dead boxes cost little.
**Approved**: pending

**Decision**: `WindowStateNamespace` is a process-wide lock-guarded static read at key-composition time, not an injected dependency.
**Rationale**: `WindowManager.shared` builds its storage on first access from anywhere, so an injected namespace would miss the storages that matter; the lock (not `@MainActor`) lets non-main-actor code compose the same keys.
**Approved**: pending

**Decision**: The namespace is an 8-hex-character SHA-256 prefix of the bundle path, empty by default.
**Rationale**: The bundle path is the identity that differs between two copies (bundle ID is shared, pid changes each launch); hashing keeps keys short and keeps directory names out of preferences; the empty default preserves every existing installation's layout.
**Approved**: pending

**Decision**: Both storage implementations use the same key formats and encodings (JSON state, native boolean visibility).
**Rationale**: Swapping `SettingsStoreWindowStateStorage` in over a UserDefaults-backed store reads existing state without migration, per its doc comment.
**Approved**: pending

**Decision**: `WindowScreenshot` resolves the deprecated `CGWindowListCreateImage` through `dlsym`.
**Rationale**: ScreenCaptureKit is async and requires Screen Recording permission even for own windows; the legacy symbol works without permission, and runtime resolution avoids the deprecation warning while degrading to `nil` if the symbol disappears.
**Approved**: pending

**Decision**: Non-document single windows are not recorded in recents yet.
**Rationale**: The source marks this intentional, pending `WindowRecentsTracker` in a follow-up slice.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | failed | Best Practices |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | partial | Reliability |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | passed | Performance |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |

separation-of-concerns passes because frame persistence (`WindowFrameManager`), live lookup (`WindowRegistry`), storage (`WindowStateStorage` and its two implementations), key namespacing (`WindowStateNamespace`) and capture (`WindowScreenshot`) are separate types behind a thin coordinator. unit-test-coverage is partial: the termination latch, recent-limit mirror, factory execution, registry visibility, namespace isolation and screenshot failure paths have tests, but `reopenRecentsOnLaunch()`, `windowDidInteract(_:kind:)` and the missing-factory log do not. explicit-error-handling fails because storage encode/decode failures and document-open failures are discarded without a signal (the open questions on storage-codec-failure and reopen-open-failure). data-integrity is partial because corrupt stored state reads as never-saved and is overwritten, and the two storage implementations disagree on a non-boolean visibility value. state-recovery passes because frames and visibility persist across launches and `restoreOnLaunch()` replays them. graceful-degradation passes because a headless run skips reopen, a missing capture symbol yields `nil`, and an empty window ID is ignored. health-observability is partial because the missing-factory wiring gap is logged, but that check is inert under the default storage (the open question on visible-ids-settings-store). main-thread-freedom passes because every main-actor operation is bounded by the number of window IDs or recent documents, and document opening is asynchronous. no-pii-in-logs passes because the single log line carries only a host-chosen window ID. data-minimization passes because the namespace stores a hash instead of the bundle path.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation from `WindowManager.swift`, `WindowRegistry.swift`, `WindowStateStorage.swift`, `SettingsStoreWindowStateStorage.swift`, `UserDefaultsWindowStateStorage.swift`, `WindowStateNamespace.swift`, `WindowScreenshot.swift` and their tests |
