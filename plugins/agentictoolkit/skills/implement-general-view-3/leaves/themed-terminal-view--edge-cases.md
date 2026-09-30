<!-- leaf: implement-general-view-3/themed-terminal-view--edge-cases · source: themed-terminal-view.md -->

# Themed Terminal View (Hollow Caret)

**Rules** (cite as `implement-general-view-3/themed-terminal-view--edge-cases#<slug>`):

- `error-states` MUST — WHEN the ComposableTabsActivePane.didChangeNotification's object is not an NSWindow (including nil), the component MUST …

## Edge Cases

- **Null/empty input**: `caretAppearance` defaults to `CaretAppearance()` when the caller never sets it, resolving to a filled caret in `.white`/`.white` (see #requirements/default-fill). This is the well-defined default, not an error condition.
- **Boundary values**: Not applicable — the only caller-supplied inputs are two `NSColor` values and two `Bool` flags, none of which have a numeric range; the one numeric constant in the file, `outlineWidth: CGFloat = 1`, is fixed and not caller-configurable.
- **Concurrent access**: Not applicable — the class is `@MainActor`, so every mutation path (the `caretAppearance` `didSet`, the notification `sink`, and the `showCursor`/`cursorStyleChanged` overrides) is confined to the main actor by the compiler (see #requirements/main-actor-isolation).
- **Error states**: WHEN the `ComposableTabsActivePane.didChangeNotification`'s `object` is not an `NSWindow` (including `nil`), the component MUST silently ignore the notification and take no action, per the `guard ... as? NSWindow` in the subscription closure. There is no other error-producing dependency (no network, database, or file-system access) in this file, so Cookbook Compliance's networking/error-handling requirements are Not applicable here.
- **Offline/disconnected state**: Not applicable — the component performs no networking; its only external interaction is a local `NotificationCenter` publisher and AppKit view-hierarchy calls.
- **Caret subview not yet present**: `applyOutline()`'s `guard let caret = caretView else { return }` makes border application a silent no-op rather than a crash (see #requirements/missing-caret-subview-tolerance).
- **Caret subview rebuilt by SwiftTerm**: WHEN the cached weak `cachedCaret` reference's `superview` is no longer `self`, the component re-searches rather than reuses the stale reference (see #requirements/caret-subview-cache).
- **View not yet embedded in any composable-tabs pane while `marksActivePane == true`**: the caret stays filled regardless of `marksActivePane` — only `isAlwaysHollow` can force it hollow outside composable-tabs context — because `agentictoolkit://recipes/composable-tabs-active-pane#requirements/view-outside-any-pane-counts-as-active` treats such a view as always "in the active pane."
- **Multiple `ThemedTerminalView` instances across different windows**: each instance ignores a `didChangeNotification` whose `object` window does not match its own `window`, so a pane-activation change in one window never repaints a caret in another (see #requirements/active-pane-notification-window-filter).
