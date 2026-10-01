---
id: 62c755ed-eeba-4ada-a907-4a0f802e0466
title: Window Matching Shortcuts
domain: agentictoolkit://cookbook/system/system-windows/window-shortcuts
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Global modifier-chord shortcut scheme (14 named chords) and the manager that
  dispatches each chord to a window-contexts model action.
platforms:
- swift
- macos
tags:
- window-matching
- window-contexts
- keyboard-shortcuts
- global-hotkeys
depends-on: []
related:
- agentictoolkit://cookbook/system/system-windows/window-contexts
references:
- https://github.com/sindresorhus/KeyboardShortcuts
approved-by: ''
approved-date: ''
---

# Window Matching Shortcuts

## Overview

The window-context global shortcut scheme. It has two parts:

- **The shortcut scheme** — fourteen named global shortcuts, each defaulting to the scheme's own modifier pair plus a distinct key, plus two ordered lists: the nine switch-by-index names, and all fourteen names together.
- **The shortcut manager** — a component that, on construction, registers a key-down handler for every one of those names, dispatches each to a window-contexts model action, and reserves the chords with the app's key-command registry so the app's own key-command settings refuse them.

Use it once per app that hosts window contexts: the host constructs one manager at feature start and retains it for the app's lifetime. The model's behavior behind each action belongs to [Window Matching System Windows Contexts](agentictoolkit://cookbook/system/system-windows/window-contexts); this recipe covers only the scheme and the dispatch.

## Behavioral Requirements

### Shortcut names (data shape)

- **index-shortcut-count**: The scheme MUST declare exactly nine switch-by-index shortcuts, named `switchToContext1` through `switchToContext9`.
- **index-shortcut-order**: The switch-by-index list MUST hold the nine switch-by-index names in ascending order, so element 0 is `switchToContext1` and element 8 is `switchToContext9`.
- **action-shortcut-names**: The scheme MUST declare five further shortcuts named `addWindow`, `removeWindow`, `nextContext`, `previousContext` and `contextPicker`.
- **all-shortcuts-list**: The full shortcut list MUST contain exactly fourteen names: the nine switch-by-index names in order, followed by `addWindow`, `removeWindow`, `nextContext`, `previousContext`, `contextPicker`, in that order.
- **unique-names**: Every identifier in the full shortcut list MUST be unique.
- **stable-raw-values**: Each name's stored identifier MUST equal its name (for example `"addWindow"`) and MUST NOT be renamed, because that identifier is also the stable, persisted storage key for a user's customization of that chord.
- **default-index-chords**: Each `switchToContextN` name MUST default to the scheme's modifier pair plus the digit key N (N = 1…9).
- **default-add-chord**: `addWindow` MUST default to the scheme's modifier pair plus A.
- **default-remove-chord**: `removeWindow` MUST default to the scheme's modifier pair plus X.
- **default-next-chord**: `nextContext` MUST default to the scheme's modifier pair plus N.
- **default-previous-chord**: `previousContext` MUST default to the scheme's modifier pair plus P.
- **default-picker-chord**: `contextPicker` MUST default to the scheme's modifier pair plus Space.
- **every-name-has-default**: Every name in the full shortcut list MUST ship a non-nil default shortcut.
- **names-module-internal**: The fourteen names and both lists MUST NOT be exposed as part of the toolkit's public interface; code outside the toolkit reaches them only through the shortcut manager and the toolkit's own settings UI.

### Manager construction and registration

- **init-signature**: The manager MUST expose exactly one construction path, taking the window-contexts model as its only required input, and MUST retain a reference to that model for its own lifetime.
- **register-on-init**: Constructing the manager MUST register a key-down handler for all fourteen names before construction completes.
- **register-once**: Registration MUST happen only during construction; the manager MUST NOT expose any way to register, re-register or unregister handlers afterward.
- **no-unregister-on-release**: The manager MUST NOT remove its handlers or release its chord reservation when it is no longer referenced; it performs no explicit teardown.
- **weak-handler-capture**: Each handler MUST reference the manager in a way that does not by itself keep the manager alive, so a handler that fires after the manager is gone does nothing.
- **reserve-external**: After registering handlers, construction MUST reserve the full shortcut list with the key-command registry under owner `"window contexts"`.
- **init-log**: Construction MUST emit one info-level log message confirming that the manager was initialized and every handler registered, after registration completes.

### Dispatch (key-down → model action)

- **dispatch-index**: A key-down on the name at position `i` (0…8) of the switch-by-index list MUST call the model's context-switch action with the `id` of the context at index `i`.
- **index-out-of-range-noop**: When `i` is greater than or equal to the model's context count, a switch-by-index key-down MUST do nothing: no model call and no error.
- **index-read-at-fire-time**: The switch-by-index handler MUST read the model's context list when the key is pressed, not when the handler is registered, so it follows contexts added or removed after launch.
- **dispatch-add**: A key-down on `addWindow` MUST call the model's add-frontmost-window action.
- **dispatch-remove**: A key-down on `removeWindow` MUST call the model's remove-frontmost-window action.
- **dispatch-next**: A key-down on `nextContext` MUST call the model's switch-to-next-context action.
- **dispatch-previous**: A key-down on `previousContext` MUST call the model's switch-to-previous-context action.
- **dispatch-picker**: A key-down on `contextPicker` MUST call the model's toggle-context-picker action.
- **key-down-only**: Handlers MUST fire on key-down; the manager MUST NOT register key-up handlers.
- **result-ignored**: The manager MUST discard the success/failure result returned by the add-frontmost-window and remove-frontmost-window actions; failures surface only through the model's own error state and logging.

### Persistence and side effects

- **customization-persistence**: User customizations of any chord MUST persist in local, per-user settings storage, under a key derived from the name's stored identifier; the manager itself MUST NOT read or write that storage directly.
- **global-event-tap**: Handlers MUST fire system-wide, including when the host app is not frontmost; the underlying shortcut-recording layer installs and owns the global event tap.
- **reservation-follows-customization**: The reservation MUST refuse the chord each name currently holds (the registry compares against the name's live, possibly user-customized shortcut at check time), so a user-customized chord stays reserved and the old default is freed.

## Appearance

Not applicable — this is a global keyboard-shortcut scheme and dispatcher, not a visual component.

## States

Not applicable — this is a global keyboard-shortcut scheme and dispatcher, not a visual component.

## Accessibility

Not applicable — this is a global keyboard-shortcut scheme and dispatcher, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wms-001 | index-shortcut-count | Read the switch-by-index list's length | `9` |
| wms-002 | all-shortcuts-list | Read the full shortcut list's length | `14` |
| wms-003 | unique-names | Map the full shortcut list to identifiers; compare the count with the count of the set of them | Counts equal |
| wms-004 | index-shortcut-order, stable-raw-values | Map the switch-by-index list to identifiers | `["switchToContext1", …, "switchToContext9"]` in that order |
| wms-005 | every-name-has-default | For each name in the full shortcut list, read its default shortcut | Non-nil for all fourteen |
| wms-006 | action-shortcut-names, default-picker-chord, all-shortcuts-list | Read `contextPicker`'s identifier, its default shortcut, and whether the full shortcut list contains it | `"contextPicker"`, non-nil, `true` |
| wms-007 | default-index-chords | Read `switchToContext3`'s default shortcut | Key `3`, modifiers exactly the scheme's modifier pair |
| wms-008 | default-add-chord, default-remove-chord, default-next-chord, default-previous-chord | Read the defaults of `addWindow`, `removeWindow`, `nextContext`, `previousContext` | A, X, N, P respectively, each with exactly the scheme's modifier pair |
| wms-009 | all-shortcuts-list | Read elements 9…13 of the full shortcut list | `addWindow`, `removeWindow`, `nextContext`, `previousContext`, `contextPicker` |
| wms-010 | register-on-init, dispatch-index | Model with contexts `[A, B, C]`; construct the manager; fire key-down for `switchToContext2` | The context-switch action is called once, targeting `B`'s id |
| wms-011 | index-out-of-range-noop | Model with 2 contexts; fire key-down for `switchToContext5` | No model action called; no error set |
| wms-012 | index-out-of-range-noop | Model with 0 contexts; fire key-down for `switchToContext1` | No model action called |
| wms-013 | index-read-at-fire-time | Construct the manager with 1 context; append a second context; fire `switchToContext2` | The context-switch action is called, targeting the new context's id |
| wms-014 | dispatch-add, result-ignored | Fire key-down for `addWindow` | The add-frontmost-window action is called once; the manager takes no further action on its result |
| wms-015 | dispatch-remove | Fire key-down for `removeWindow` | The remove-frontmost-window action is called once |
| wms-016 | dispatch-next | Fire key-down for `nextContext` | The switch-to-next-context action is called once |
| wms-017 | dispatch-previous | Fire key-down for `previousContext` | The switch-to-previous-context action is called once |
| wms-018 | dispatch-picker | Fire key-down for `contextPicker` twice | The toggle-context-picker action is called twice (picker visibility returns to its starting value) |
| wms-019 | reserve-external | Construct the manager; ask the key-command registry about the availability of the scheme's modifier pair plus A for an unrelated command id | Unavailable, reported as taken by window contexts |
| wms-020 | reservation-follows-customization | Construct the manager; customize `addWindow` to the scheme's modifier pair plus Z; query availability of that chord and of the scheme's modifier pair plus A for an unrelated command | Z is unavailable, reported as taken by window contexts; A is not refused by the window-contexts reservation |
| wms-021 | weak-handler-capture, no-unregister-on-release | Construct a manager, drop every reference to it, fire key-down for `addWindow` | No model action called; the chord remains reserved in the registry |
| wms-022 | init-log | Construct the manager | One info-level log confirming initialization and handler registration, in the manager's own logging category |

## Edge Cases

- **Fewer contexts than the index**: A switch-by-index key-down whose index is at or beyond the model's context count MUST be a no-op; this is the documented behavior of the underlying switch-by-index action ("Out-of-range indices (fewer contexts exist) are a no-op.").
- **Empty context list**: With zero contexts every switch-by-index key MUST be a no-op; next/previous/add/remove still dispatch, and the model decides the outcome (for example the switch-to-next-context action does nothing below two contexts).
- **More than nine contexts**: Contexts at index 9 and above MUST have no switch-by-index shortcut; they are reachable only through next/previous or the picker.
- **Negative index**: Cannot occur; indices come from enumerating a fixed nine-element list, so the handler MUST only ever see 0…8.
- **No frontmost eligible window / no active context**: The add and remove shortcuts MUST still call the model; the model reports failure and records the reason, and the manager MUST NOT react to that result.
- **Model switch failure**: If the context-switch action fails inside the model, the model logs it and records the failure; the manager MUST NOT observe or retry it.
- **Manager discarded**: Handlers remain registered and the chords remain reserved, but each handler MUST do nothing because its reference to the manager no longer resolves. Lifetime retention is a caller precondition ("Instantiate once at app launch and retain it for the app's lifetime").
- **Manager constructed twice**: Each instance registers its own handlers, so one key-down MUST call the model once per live instance; the reservation is replaced, not duplicated, because reserving the list removes an existing entry with the same identifier before adding. Single construction is the documented caller precondition.
- **User clears a chord**: A name whose shortcut the user removed MUST NOT fire; its handler stays registered and fires again if a chord is re-assigned.
- **User resets to defaults**: Resetting the full shortcut list (as the toolkit's shortcuts settings tab does) MUST restore the defaults listed in Behavioral Requirements; handlers need no re-registration.
- **Chord taken by the OS or another app**: The manager MUST NOT detect or report a conflict with a system or third-party global hotkey; whether the chord fires is decided by the underlying shortcut-recording layer and the OS.
- **Concurrent access**: Not applicable as a race: the manager is confined to one designated thread, handlers run on that same thread, and key-downs are delivered serially, so dispatches MUST execute one at a time in key-press order. See Platform Notes for how that confinement is enforced.
- **Network / offline**: Not applicable — the component performs no network I/O.
- **Timeouts and cancellation**: Not applicable — every dispatch is a synchronous call with no timeout and nothing to cancel.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | window-contexts model | required | The model every shortcut dispatches to; injected at construction and retained. |
| `switchToContext1` … `switchToContext9` | named shortcut | the scheme's modifier pair + 1 … + 9 | Switch to the context at index 0…8. User-customizable; persisted under the name's identifier. |
| `addWindow` | named shortcut | the scheme's modifier pair + A | Add the frontmost window to the active context. |
| `removeWindow` | named shortcut | the scheme's modifier pair + X | Remove the frontmost window from its context. |
| `nextContext` | named shortcut | the scheme's modifier pair + N | Switch to the next context. |
| `previousContext` | named shortcut | the scheme's modifier pair + P | Switch to the previous context. |
| `contextPicker` | named shortcut | the scheme's modifier pair + Space | Toggle the context picker. |
| Reservation owner | string | `"window contexts"` (hardcoded) | The owner name the key-command registry reports for these chords. Not configurable. |
| Registry | key-command registry | the app's shared instance (hardcoded) | The registry the chords are reserved in. Not injectable. |

## Deep Linking

Not applicable: the manager only reacts to global key-down events and registers no URL scheme or route.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded literal) | `window contexts` | Owner name passed to the reservation call; the key-command registry shows it to the user as "taken by window contexts" when they try to bind a reserved chord in Settings. It is a hardcoded English literal, not a localized string. |

## Accessibility Options

Not applicable: the component draws nothing and has no motion, contrast or color-only signal for Reduce Motion, Increase Contrast or Differentiate Without Color to affect.

## Feature Flags

Not applicable: registration is unconditional at construction and the source reads no flag; the host decides whether to construct the manager at all.

## Analytics

Not applicable: neither source file records any analytics event.

## Privacy

Not applicable: the manager stores no user data itself; the only persisted values are the user's chord customizations, which the underlying shortcut-recording layer keeps in local, per-user settings storage and never transmits.

## Logging

Subsystem: the app's bundle identifier | Category: the manager's own logging category (see Platform Notes for the literal values the current implementation uses).

| Event | Level | Message |
|-------|-------|---------|
| Manager constructed and all handlers registered | info | A message confirming initialization and handler registration (see Platform Notes for the literal string the current implementation logs) |

No other event is logged: individual key-downs, out-of-range index no-ops and ignored add/remove results produce no log line from the manager (the model logs its own errors).

## Platform Notes

- **SwiftUI**: The source is AppKit-agnostic Swift in `SystemWindowShortcutNames.swift` (the `KeyboardShortcuts.Name` extension) and `SystemWindowShortcutManager.swift` (the dispatcher), both on the third-party `KeyboardShortcuts` package. A SwiftUI host constructs the manager once from its app or feature start (as `WindowContextsCoordinator.start()` does) and shows `KeyboardShortcuts.Recorder(for:)` rows for customization. SwiftUI's own `.keyboardShortcut` only fires while the app is active, so it cannot replace the global handlers.
- **Compose**: Compose Desktop has no system-wide hotkey API; a port starts from a native hook library (for example JNativeHook) or a platform-specific `RegisterHotKey` / Carbon bridge, keeping the fourteen names as persisted keys (Jetpack DataStore or `java.util.prefs.Preferences`) and a single dispatcher object on the UI thread. Android has no equivalent of global chords; the actions map to app-scoped `KeyEvent` handling or `ShortcutManager` launcher shortcuts instead.
- **React/Web**: A browser page cannot register OS-wide hotkeys; only in-page `keydown` listeners on `window` work, and only while the tab has focus. Electron's `globalShortcut.register(accelerator, callback)` is the closest match (accelerators like `Control+Alt+1`), with customizations persisted in `electron-store` or `localStorage` under the same raw-value keys.
- **AppKit / UIKit** (source platform): On macOS, the scheme's modifier pair is literally Control+Option, and the underlying mechanism without the `KeyboardShortcuts` package is Carbon `RegisterEventHotKey` (what `KeyboardShortcuts` wraps) or an `NSEvent.addGlobalMonitorForEvents` monitor (which needs Accessibility permission and cannot consume the event). Custom chords persist in `UserDefaults`. UIKit has no global hotkeys; `UIKeyCommand` on the responder chain works only while the app is frontmost with a hardware keyboard. The manager (`SystemWindowShortcutManager`) is declared `@MainActor` and is not `Sendable`, which is what confines every handler and model call to the main actor and makes constructing or invoking it from off the main actor a compile-time error; a construction attempt from a non-main-actor context without `await` fails to compile rather than running. The reservation call is `KeyCommandRegistry.shared.reserveExternal(allWindowContextShortcuts, owner: "window contexts")`. Logging: subsystem is `Bundle.main.bundleIdentifier` (via `Loggable`), category `SystemWindowShortcutManager`; the one line logged, at info level on construction, is the literal string `SystemWindowShortcutManager initialized, all handlers registered`.
- **WinUI 3** (the reason this recipe exists): WinUI 3 `KeyboardAccelerator` elements fire only while the window has focus, so a port uses Win32 `RegisterHotKey(hwnd, id, MOD_CONTROL | MOD_ALT, vk)` through P/Invoke (or CsWin32), with the window handle from `WinRT.Interop.WindowNative.GetWindowHandle(window)` and a subclassed window procedure (`SetWindowSubclass`) that receives `WM_HOTKEY` and maps the hotkey id to the action. The scheme's modifier pair (Control+Option on macOS) translates to Ctrl+Alt (`MOD_CONTROL | MOD_ALT`, plus `MOD_NOREPEAT` to match key-down-once). Unlike the source, `RegisterHotKey` fails when another process already holds the chord, so a port gets a conflict signal the macOS source never surfaces; decide how to report it. Persist customizations with `Windows.Storage.ApplicationData.Current.LocalSettings.Values[rawValue]` (packaged) or a `System.Text.Json` settings file, and call `UnregisterHotKey` on shutdown since the OS does not tie registration to object lifetime. Dispatch on the UI thread via `DispatcherQueue.TryEnqueue`, which matches the source's `@MainActor` isolation.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemWindows/Shortcuts/` |

## Design Decisions

**Decision**: Raw values of the fourteen names are frozen as storage keys.
**Rationale**: The doc comment states the raw values are "stable `UserDefaults` storage keys for persisted user customizations — do not rename them"; renaming would silently drop every user's custom chords. (Swift/AppKit: the storage is `UserDefaults`.)
**Approved**: pending

**Decision**: Out-of-range switch-by-index is a silent no-op, and the index is resolved against the model's current context list at key-press time.
**Rationale**: The nine chords are fixed while the number of contexts varies at runtime; resolving late means the chords always track the current list order without re-registration, and a chord for a context that does not exist is harmless.
**Approved**: pending

**Decision**: Chords are reserved with `KeyCommandRegistry` under owner `"window contexts"`.
**Rationale**: The source comment: "So Settings › Key Commands refuses these chords instead of letting a second command fire on them too." Both handlers would otherwise fire on one key-down. (Swift/AppKit: `KeyCommandRegistry` is this toolkit's own reservation service.)
**Approved**: pending

**Decision**: Handlers capture the manager weakly and are never unregistered; the manager is expected to live for the app's lifetime.
**Rationale**: The class doc comment makes single construction and lifetime retention the caller's contract, so no teardown path exists; the weak capture only guards against a handler touching a freed manager. (Swift: implemented as a weak closure-capture list.)
**Approved**: pending

**Decision**: Add/remove results are ignored by the manager.
**Rationale**: The model already records the failure reason in `lastError` and logs thrown errors, so the dispatcher adds no second reporting path.
**Approved**: pending

**Decision**: Control+Option is the single modifier family for every default.
**Rationale**: The doc comment calls it "the standard keyboard-shortcut scheme"; the `CommandPaletteCoordinator` doc comment refers to it as the established global family, which other global chords follow. (Apple platforms: Control+Option; see the WinUI 3 Platform Notes entry for the Windows equivalent, Ctrl+Alt.)
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |

Separation of concerns passes: the names file holds only the scheme data, the manager only maps key-downs to model calls, and all context logic stays in `SystemWindowContextsModel`. Unit-test coverage is partial: `SystemWindowShortcutNamesTests` covers the name list, ordering, uniqueness and defaults, but nothing tests the manager's dispatch, the out-of-range no-op or the registry reservation. Explicit error handling is partial: the manager discards the `Bool` results of add/remove and relies on the model's `lastError`, which is a reported path rather than a swallowed one. The reservation owner `"window contexts"` is a hardcoded English literal that reaches the user in the Settings conflict message. Keyboard navigation passes in the sense that every window-context action has a keyboard path, which is this component's whole purpose.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to system/system-windows/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from SystemWindowShortcutManager.swift and SystemWindowShortcutNames.swift |
