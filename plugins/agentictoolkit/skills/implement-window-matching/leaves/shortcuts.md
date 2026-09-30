<!-- leaf: implement-window-matching/shortcuts · source: window-matching-shortcuts.md -->

**Rules** (cite as `implement-window-matching/shortcuts#<slug>`):

- `index-shortcut-count` MUST
- `index-shortcut-order` MUST
- `action-shortcut-names` MUST
- `all-shortcuts-list` MUST
- `unique-names` MUST
- `stable-raw-values` MUST
- `default-index-chords` MUST
- `default-add-chord` MUST
- `default-remove-chord` MUST
- `default-next-chord` MUST
- `default-previous-chord` MUST
- `default-picker-chord` MUST
- `every-name-has-default` MUST
- `names-module-internal` MUST
- `init-signature` MUST
- `register-on-init` MUST
- `register-once` MUST
- `no-unregister-on-release` MUST
- `weak-handler-capture` MUST
- `reserve-external` MUST
- `init-log` MUST
- `main-actor-isolation` MUST
- `dispatch-index` MUST
- `index-out-of-range-noop` MUST
- `index-read-at-fire-time` MUST
- `dispatch-add` MUST
- `dispatch-remove` MUST
- `dispatch-next` MUST
- `dispatch-previous` MUST
- `dispatch-picker` MUST
- `key-down-only` MUST
- `result-ignored` MUST
- `customization-persistence` MUST
- `global-event-tap` MUST
- `reservation-follows-customization` MUST

# Window Matching Shortcuts

## Overview

The window-context shortcut scheme for macOS. It has two parts:

- **SystemWindowShortcutNames** — an extension on `KeyboardShortcuts.Name` that declares fourteen named global shortcuts, each with a Control+Option default, plus two ordered lists (`contextSwitchByIndex`, `allWindowContextShortcuts`).
- **SystemWindowShortcutManager** — a `@MainActor` final class that, on construction, registers a key-down handler for every one of those names, dispatches each to a `SystemWindowContextsModel` action, and reserves the chords with `KeyCommandRegistry.shared` so the app's own key-command settings refuse them.

Use it once per app that hosts window contexts: the host constructs one manager at feature start and retains it for the app's lifetime (`WindowContextsCoordinator.start()` does exactly this). The model's behavior behind each action belongs to Window Matching System Windows Contexts; this recipe covers only the scheme and the dispatch.

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

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded literal) | `window contexts` | Owner name passed to `reserveExternal`; `KeyCommandRegistry.availability(of:for:)` shows it to the user as "taken by window contexts" when they try to bind a reserved chord in Settings. It is a hardcoded English literal, not a localized string. |

