<!-- leaf: implement-window-matching/shortcuts--part-2 · source: window-matching-shortcuts.md -->

# Window Matching Shortcuts — continued (part 2)

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
