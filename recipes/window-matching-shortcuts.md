---
id: 62c755ed-eeba-4ada-a907-4a0f802e0466
title: Window Matching Shortcuts
domain: agentictoolkit://recipes/window-matching-shortcuts
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Global Control+Option shortcut scheme (14 named chords) and the manager that
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
- agentictoolkit://recipes/window-matching-system-windows-contexts
references:
- https://github.com/sindresorhus/KeyboardShortcuts
approved-by: ''
approved-date: ''
---

# Window Matching Shortcuts

## Overview

The window-context shortcut scheme for macOS. It has two parts:

- **SystemWindowShortcutNames** — an extension on `KeyboardShortcuts.Name` that declares fourteen named global shortcuts, each with a Control+Option default, plus two ordered lists (`contextSwitchByIndex`, `allWindowContextShortcuts`).
- **SystemWindowShortcutManager** — a `@MainActor` final class that, on construction, registers a key-down handler for every one of those names, dispatches each to a `SystemWindowContextsModel` action, and reserves the chords with `KeyCommandRegistry.shared` so the app's own key-command settings refuse them.

Use it once per app that hosts window contexts: the host constructs one manager at feature start and retains it for the app's lifetime (`WindowContextsCoordinator.start()` does exactly this). The model's behavior behind each action belongs to [Window Matching System Windows Contexts](agentictoolkit://recipes/window-matching-system-windows-contexts); this recipe covers only the scheme and the dispatch.

## Behavioral Requirements

### Shortcut names (data shape)

- **index-shortcut-count**: The scheme MUST declare exactly nine switch-by-index shortcuts, named `switchToContext1` through `switchToContext9`.
- **index-shortcut-order**: The `contextSwitchByIndex` list MUST hold the nine switch-by-index names in ascending order, so element 0 is `switchToContext1` and element 8 is `switchToContext9`.
- **action-shortcut-names**: The scheme MUST declare five further shortcuts named `addWindow`, `removeWindow`, `nextContext`, `previousContext` and `contextPicker`.
- **all-shortcuts-list**: The `allWindowContextShortcuts` list MUST contain exactly fourteen names: the nine `contextSwitchByIndex` names in order, followed by `addWindow`, `removeWindow`, `nextContext`, `previousContext`, `contextPicker`, in that order.
- **unique-names**: Every raw value in `allWindowContextShortcuts` MUST be unique.
- **stable-raw-values**: Each name's raw value MUST equal its identifier (for example `"addWindow"`) and MUST NOT be renamed, because the doc comment declares the raw values to be the stable `UserDefaults` storage keys for persisted user customizations.
- **default-index-chords**: Each `switchToContextN` name MUST default to Control+Option plus the digit key N (N = 1…9).
- **default-add-chord**: `addWindow` MUST default to Control+Option+A.
- **default-remove-chord**: `removeWindow` MUST default to Control+Option+X.
- **default-next-chord**: `nextContext` MUST default to Control+Option+N.
- **default-previous-chord**: `previousContext` MUST default to Control+Option+P.
- **default-picker-chord**: `contextPicker` MUST default to Control+Option+Space.
- **every-name-has-default**: Every name in `allWindowContextShortcuts` MUST ship a non-nil default shortcut.
- **names-module-internal**: The fourteen names and both lists MUST be declared with internal (module-level) access, not `public`; code outside the toolkit module reaches them only through `SystemWindowShortcutManager` and the toolkit's own settings UI.

### Manager construction and registration

- **init-signature**: `SystemWindowShortcutManager` MUST expose one public initializer, `init(model: SystemWindowContextsModel)`, and MUST hold a strong reference to that model for its lifetime.
- **register-on-init**: The initializer MUST register a key-down handler for all fourteen names before returning.
- **register-once**: Registration MUST happen only in the initializer; the manager MUST NOT expose any public method to register, re-register or unregister handlers.
- **no-unregister-on-release**: The manager MUST NOT remove its handlers or release its chord reservation when it is deallocated; it has no `deinit`.
- **weak-handler-capture**: Each handler MUST capture the manager weakly, so a handler that fires after the manager is gone does nothing.
- **reserve-external**: After registering handlers, the initializer MUST call `KeyCommandRegistry.shared.reserveExternal` with `allWindowContextShortcuts` and owner `"window contexts"`.
- **init-log**: The initializer MUST emit one info-level log message, `SystemWindowShortcutManager initialized, all handlers registered`, after registration completes.
- **main-actor-isolation**: `SystemWindowShortcutManager` MUST be isolated to the main actor (`@MainActor`); it is not `Sendable`, and every handler and model call MUST run on the main actor.

### Dispatch (key-down → model action)

- **dispatch-index**: A key-down on the name at position `i` (0…8) of `contextSwitchByIndex` MUST call `model.switchContext(to:)` with the `id` of `model.contexts[i]`.
- **index-out-of-range-noop**: When `i` is greater than or equal to `model.contexts.count`, a switch-by-index key-down MUST do nothing: no model call and no error.
- **index-read-at-fire-time**: The switch-by-index handler MUST read `model.contexts` when the key is pressed, not when the handler is registered, so it follows contexts added or removed after launch.
- **dispatch-add**: A key-down on `addWindow` MUST call `model.addFrontmostWindow()`.
- **dispatch-remove**: A key-down on `removeWindow` MUST call `model.removeFrontmostWindow()`.
- **dispatch-next**: A key-down on `nextContext` MUST call `model.switchToNextContext()`.
- **dispatch-previous**: A key-down on `previousContext` MUST call `model.switchToPreviousContext()`.
- **dispatch-picker**: A key-down on `contextPicker` MUST call `model.toggleContextPicker()`.
- **key-down-only**: Handlers MUST fire on key-down; the manager MUST NOT register key-up handlers.
- **result-ignored**: The manager MUST discard the `Bool` returned by `addFrontmostWindow()` and `removeFrontmostWindow()`; failures surface only through the model's own `lastError` and logging.

### Persistence and side effects

- **customization-persistence**: User customizations of any chord MUST persist through the `KeyboardShortcuts` library in `UserDefaults`, under a key derived from the name's raw value; the manager itself MUST NOT read or write `UserDefaults`.
- **global-event-tap**: Handlers MUST fire system-wide, including when the host app is not frontmost; the `KeyboardShortcuts` library installs and owns the global event tap.
- **reservation-follows-customization**: The reservation MUST refuse the chord each name currently holds (the registry compares against `KeyboardShortcuts.getShortcut(for:)` at check time), so a user-customized chord stays reserved and the old default is freed.

## Appearance

Not applicable — this is a global keyboard-shortcut scheme and dispatcher, not a visual component.

## States

Not applicable — this is a global keyboard-shortcut scheme and dispatcher, not a visual component.

## Accessibility

Not applicable — this is a global keyboard-shortcut scheme and dispatcher, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wms-001 | index-shortcut-count | Read `contextSwitchByIndex.count` | `9` (from `SystemWindowShortcutNamesTests.contextSwitchByIndexHasNineEntries`) |
| wms-002 | all-shortcuts-list | Read `allWindowContextShortcuts.count` | `14` (from `allShortcutsCount`) |
| wms-003 | unique-names | Map `allWindowContextShortcuts` to raw values; compare count with the count of the set of them | Counts equal (from `namesAreUnique`) |
| wms-004 | index-shortcut-order, stable-raw-values | Map `contextSwitchByIndex` to raw values | `["switchToContext1", …, "switchToContext9"]` in that order (from `contextSwitchNamesAreOrdered`) |
| wms-005 | every-name-has-default | For each name in `allWindowContextShortcuts`, read `defaultShortcut` | Non-nil for all fourteen (from `allShortcutsHaveDefaults`) |
| wms-006 | action-shortcut-names, default-picker-chord, all-shortcuts-list | Read `contextPicker.rawValue`, `contextPicker.defaultShortcut`, `allWindowContextShortcuts.contains(.contextPicker)` | `"contextPicker"`, non-nil, `true` (from `contextPickerShortcutIsRegistered`) |
| wms-007 | default-index-chords | Read `switchToContext3.defaultShortcut` | Key `3`, modifiers exactly Control+Option |
| wms-008 | default-add-chord, default-remove-chord, default-next-chord, default-previous-chord | Read the defaults of `addWindow`, `removeWindow`, `nextContext`, `previousContext` | A, X, N, P respectively, each with exactly Control+Option |
| wms-009 | all-shortcuts-list | Read `allWindowContextShortcuts` elements 9…13 | `addWindow`, `removeWindow`, `nextContext`, `previousContext`, `contextPicker` |
| wms-010 | register-on-init, dispatch-index | Model with contexts `[A, B, C]`; construct the manager; fire key-down for `switchToContext2` | `model.switchContext(to: B.id)` called once |
| wms-011 | index-out-of-range-noop | Model with 2 contexts; fire key-down for `switchToContext5` | No model method called; no error set |
| wms-012 | index-out-of-range-noop | Model with 0 contexts; fire key-down for `switchToContext1` | No model method called |
| wms-013 | index-read-at-fire-time | Construct the manager with 1 context; append a second context; fire `switchToContext2` | `model.switchContext(to:)` called with the new context's id |
| wms-014 | dispatch-add, result-ignored | Fire key-down for `addWindow` | `model.addFrontmostWindow()` called once; manager takes no further action on either return value |
| wms-015 | dispatch-remove | Fire key-down for `removeWindow` | `model.removeFrontmostWindow()` called once |
| wms-016 | dispatch-next | Fire key-down for `nextContext` | `model.switchToNextContext()` called once |
| wms-017 | dispatch-previous | Fire key-down for `previousContext` | `model.switchToPreviousContext()` called once |
| wms-018 | dispatch-picker | Fire key-down for `contextPicker` twice | `model.toggleContextPicker()` called twice (picker visibility returns to its starting value) |
| wms-019 | reserve-external | Construct the manager; ask `KeyCommandRegistry.shared.availability(of:for:)` about Control+Option+A for an unrelated command id | `.unavailable("taken by window contexts")` |
| wms-020 | reservation-follows-customization | Construct the manager; set `addWindow` to Control+Option+Z; query availability of Control+Option+Z and of Control+Option+A for an unrelated command | Z is `.unavailable("taken by window contexts")`; A is not refused by the window-contexts reservation |
| wms-021 | weak-handler-capture, no-unregister-on-release | Construct a manager, drop every strong reference, fire key-down for `addWindow` | No model method called; the chord remains reserved in the registry |
| wms-022 | init-log | Construct the manager | One info log `SystemWindowShortcutManager initialized, all handlers registered` in category `SystemWindowShortcutManager` |
| wms-023 | main-actor-isolation | Construct the manager from a non-main-actor context without `await` | Compile-time error |

## Edge Cases

- **Fewer contexts than the index**: A switch-by-index key-down whose index is at or beyond `model.contexts.count` MUST be a no-op; this is the documented behavior of `switchToContext(at:)` ("Out-of-range indices (fewer contexts exist) are a no-op.").
- **Empty context list**: With zero contexts every switch-by-index key MUST be a no-op; next/previous/add/remove still dispatch, and the model decides the outcome (for example `switchToNextContext()` does nothing below two contexts).
- **More than nine contexts**: Contexts at index 9 and above MUST have no switch-by-index shortcut; they are reachable only through next/previous or the picker.
- **Negative index**: Cannot occur; indices come from `enumerated()` over a fixed nine-element list, so the handler MUST only ever see 0…8.
- **No frontmost eligible window / no active context**: The add and remove shortcuts MUST still call the model; the model returns `false` and sets `lastError`, and the manager MUST NOT react to that result.
- **Model switch failure**: If `switchContext(to:)` throws inside the model, the model logs it and sets `lastError`; the manager MUST NOT observe or retry it.
- **Manager deallocated**: Handlers remain registered with the library and the chords remain reserved, but each handler MUST do nothing because its weak reference is nil. The class doc comment makes lifetime retention a caller precondition ("Instantiate once at app launch and retain it for the app's lifetime").
- **Manager constructed twice**: Each instance registers its own handlers, so one key-down MUST call the model once per live instance; the reservation is replaced, not duplicated, because `reserveExternal` removes an existing entry with the same raw value before adding. Single construction is the documented caller precondition.
- **User clears a chord**: A name whose shortcut the user removed MUST NOT fire; its handler stays registered and fires again if a chord is re-assigned.
- **User resets to defaults**: `KeyboardShortcuts.reset(allWindowContextShortcuts)` (called by the toolkit's shortcuts settings tab) MUST restore the defaults listed in Behavioral Requirements; handlers need no re-registration.
- **Chord taken by macOS or another app**: The manager MUST NOT detect or report a conflict with a system or third-party global hotkey; whether the chord fires is decided by the `KeyboardShortcuts` library and the OS.
- **Concurrent access**: Not applicable as a race: the manager is `@MainActor`, handlers run on the main actor, and key-downs are delivered serially, so dispatches MUST execute one at a time in key-press order.
- **Network / offline**: Not applicable — the component performs no network I/O.
- **Timeouts and cancellation**: Not applicable — every dispatch is a synchronous main-actor call with no timeout and nothing to cancel.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | `SystemWindowContextsModel` | required | The model every shortcut dispatches to; injected through `init(model:)` and retained strongly. |
| `switchToContext1` … `switchToContext9` | `KeyboardShortcuts.Name` | Control+Option+1 … Control+Option+9 | Switch to the context at index 0…8. User-customizable; persisted in `UserDefaults` under the raw value. |
| `addWindow` | `KeyboardShortcuts.Name` | Control+Option+A | Add the frontmost window to the active context. |
| `removeWindow` | `KeyboardShortcuts.Name` | Control+Option+X | Remove the frontmost window from its context. |
| `nextContext` | `KeyboardShortcuts.Name` | Control+Option+N | Switch to the next context. |
| `previousContext` | `KeyboardShortcuts.Name` | Control+Option+P | Switch to the previous context. |
| `contextPicker` | `KeyboardShortcuts.Name` | Control+Option+Space | Toggle the context picker. |
| Reservation owner | `String` | `"window contexts"` (hardcoded) | The owner name `KeyCommandRegistry` reports for these chords. Not configurable. |
| Registry | `KeyCommandRegistry` | `.shared` (hardcoded) | The registry the chords are reserved in. Not injectable. |

## Deep Linking

Not applicable: the manager only reacts to global key-down events and registers no URL scheme or route.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded literal) | `window contexts` | Owner name passed to `reserveExternal`; `KeyCommandRegistry.availability(of:for:)` shows it to the user as "taken by window contexts" when they try to bind a reserved chord in Settings. It is a hardcoded English literal, not a localized string. |

## Accessibility Options

Not applicable: the component draws nothing and has no motion, contrast or color-only signal for Reduce Motion, Increase Contrast or Differentiate Without Color to affect.

## Feature Flags

Not applicable: registration is unconditional in `init(model:)` and the source reads no flag; the host decides whether to construct the manager at all.

## Analytics

Not applicable: neither source file records any analytics event.

## Privacy

Not applicable: the manager stores no user data itself; the only persisted values are the user's chord customizations, which the `KeyboardShortcuts` library keeps in local `UserDefaults` and never transmits.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`) | Category: `SystemWindowShortcutManager`

| Event | Level | Message |
|-------|-------|---------|
| Manager constructed and all handlers registered | info | `SystemWindowShortcutManager initialized, all handlers registered` |

No other event is logged: individual key-downs, out-of-range index no-ops and ignored add/remove results produce no log line from the manager (the model logs its own thrown errors).

## Platform Notes

- **SwiftUI**: The source is AppKit-agnostic Swift in `SystemWindowShortcutNames.swift` (the `KeyboardShortcuts.Name` extension) and `SystemWindowShortcutManager.swift` (the dispatcher), both on the third-party `KeyboardShortcuts` package. A SwiftUI host constructs the manager once from its app or feature start (as `WindowContextsCoordinator.start()` does) and shows `KeyboardShortcuts.Recorder(for:)` rows for customization. SwiftUI's own `.keyboardShortcut` only fires while the app is active, so it cannot replace the global handlers.
- **Compose**: Compose Desktop has no system-wide hotkey API; a port starts from a native hook library (for example JNativeHook) or a platform-specific `RegisterHotKey` / Carbon bridge, keeping the fourteen names as persisted keys (Jetpack DataStore or `java.util.prefs.Preferences`) and a single dispatcher object on the UI thread. Android has no equivalent of global chords; the actions map to app-scoped `KeyEvent` handling or `ShortcutManager` launcher shortcuts instead.
- **React/Web**: A browser page cannot register OS-wide hotkeys; only in-page `keydown` listeners on `window` work, and only while the tab has focus. Electron's `globalShortcut.register(accelerator, callback)` is the closest match (accelerators like `Control+Alt+1`), with customizations persisted in `electron-store` or `localStorage` under the same raw-value keys.
- **AppKit / UIKit**: On macOS without the package, the underlying mechanism is Carbon `RegisterEventHotKey` (what `KeyboardShortcuts` wraps) or an `NSEvent.addGlobalMonitorForEvents` monitor (which needs Accessibility permission and cannot consume the event). Persist custom chords in `UserDefaults`. UIKit has no global hotkeys; `UIKeyCommand` on the responder chain works only while the app is frontmost with a hardware keyboard.
- **WinUI 3**: WinUI 3 `KeyboardAccelerator` elements fire only while the window has focus, so a port uses Win32 `RegisterHotKey(hwnd, id, MOD_CONTROL | MOD_ALT, vk)` through P/Invoke (or CsWin32), with the window handle from `WinRT.Interop.WindowNative.GetWindowHandle(window)` and a subclassed window procedure (`SetWindowSubclass`) that receives `WM_HOTKEY` and maps the hotkey id to the action. Control+Option translates to Ctrl+Alt (`MOD_CONTROL | MOD_ALT`, plus `MOD_NOREPEAT` to match key-down-once). Unlike the source, `RegisterHotKey` fails when another process already holds the chord, so a port gets a conflict signal the macOS source never surfaces; decide how to report it. Persist customizations with `Windows.Storage.ApplicationData.Current.LocalSettings.Values[rawValue]` (packaged) or a `System.Text.Json` settings file, and call `UnregisterHotKey` on shutdown since the OS does not tie registration to object lifetime. Dispatch on the UI thread via `DispatcherQueue.TryEnqueue`, which matches the source's `@MainActor` isolation.

## Design Decisions

**Decision**: Raw values of the fourteen names are frozen as storage keys.
**Rationale**: The doc comment states the raw values are "stable `UserDefaults` storage keys for persisted user customizations — do not rename them"; renaming would silently drop every user's custom chords.
**Approved**: pending

**Decision**: Out-of-range switch-by-index is a silent no-op, and the index is resolved against `model.contexts` at key-press time.
**Rationale**: The nine chords are fixed while the number of contexts varies at runtime; resolving late means the chords always track the current list order without re-registration, and a chord for a context that does not exist is harmless.
**Approved**: pending

**Decision**: Chords are reserved with `KeyCommandRegistry` under owner `"window contexts"`.
**Rationale**: The source comment: "So Settings › Key Commands refuses these chords instead of letting a second command fire on them too." Both handlers would otherwise fire on one key-down.
**Approved**: pending

**Decision**: Handlers capture the manager weakly and are never unregistered; the manager is expected to live for the app's lifetime.
**Rationale**: The class doc comment makes single construction and lifetime retention the caller's contract, so no teardown path exists; the weak capture only guards against a handler touching a freed manager.
**Approved**: pending

**Decision**: Add/remove results are ignored by the manager.
**Rationale**: The model already records the failure reason in `lastError` and logs thrown errors, so the dispatcher adds no second reporting path.
**Approved**: pending

**Decision**: Control+Option is the single modifier family for every default.
**Rationale**: The doc comment calls it "the standard keyboard-shortcut scheme"; the `CommandPaletteCoordinator` doc comment refers to it as the established global family, which other global chords follow.
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
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from SystemWindowShortcutManager.swift and SystemWindowShortcutNames.swift |
