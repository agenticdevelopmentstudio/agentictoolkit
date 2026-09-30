<!-- leaf: implement-general-view-3/themed-terminal-view--test-vectors · source: themed-terminal-view.md -->

# Themed Terminal View (Hollow Caret)

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| themed-terminal-view-002 | coder-initializer | Construct via `ThemedTerminalView(coder:)` with any `NSCoder` | Execution traps via `fatalError` |
| themed-terminal-view-003 | caret-appearance-property | Construct `ThemedTerminalView` and read `caretAppearance` before setting it | `caretAppearance.color == .white`, `caretAppearance.textColor == .white`, `caretAppearance.isAlwaysHollow == false`, `caretAppearance.marksActivePane == false` |
| themed-terminal-view-004 | appearance-change-recompute | View with default `caretAppearance`; set `caretAppearance.isAlwaysHollow = true` | `caretColor` becomes `.clear` and the caret subview's layer border width becomes `1` without any other call |
| themed-terminal-view-005 | window-attach-recompute | View constructed with `caretAppearance.isAlwaysHollow == true`, not yet in a window; add it to a window | After `viewDidMoveToWindow` runs, `caretColor == .clear` and the caret subview's border width is `1` |
| themed-terminal-view-006 | active-pane-subscription | Construct a `ThemedTerminalView`, add it to a window, then immediately post `ComposableTabsActivePane.didChangeNotification` with `object` set to that window, with no other intervening call | The caret's color/border are recomputed in response, showing the subscription was already active right after construction |
| themed-terminal-view-007 | active-pane-notification-window-filter | View is in window A; post `ComposableTabsActivePane.didChangeNotification` with `object` set to window B | The view's caret color/border are unchanged |
| themed-terminal-view-008 | active-pane-notification-window-filter | View is in window A; post `ComposableTabsActivePane.didChangeNotification` with `object` set to window A | `updateCaret()` runs and the caret's color/border reflect the current `caretAppearance`/active-pane state |
| themed-terminal-view-009 | cursor-shown-outline-reapply | `caretAppearance.marksActivePane = true`, `isAlwaysHollow = false`, view currently the active pane (filled: border width `0`); without changing `caretAppearance`, another pane in the same window becomes active (so `isInActivePane(view)` would now return `false`), but no `didChangeNotification` reaches this view's window; then invoke `showCursor(source:)` | The caret subview's border width stays `0` and `caretColor` stays `caretAppearance.color` — the stale computed state from before the pane change, not a freshly recomputed one |
| themed-terminal-view-010 | cursor-style-change-outline-reapply | `caretAppearance.marksActivePane = true`, `isAlwaysHollow = false`, view currently NOT the active pane (hollow: border width `1`); without changing `caretAppearance`, this view's pane becomes active (so `isInActivePane(view)` would now return `true`), but no `didChangeNotification` reaches this view; then invoke `cursorStyleChanged(source:newStyle:)` with any `CursorStyle` | The caret subview's border width stays `1` in `caretAppearance.color` regardless of `newStyle` — the stale hollow state persists |
| themed-terminal-view-011 | always-hollow-flag | `caretAppearance.isAlwaysHollow = true`, `caretAppearance.marksActivePane = true`, view is in the active pane | Caret is hollow |
| themed-terminal-view-012 | active-pane-marking | `caretAppearance.isAlwaysHollow = false`, `caretAppearance.marksActivePane = true`, `ComposableTabsActivePane.shared.isInActivePane(view) == false` | Caret is hollow |
| themed-terminal-view-013 | active-pane-marking | `caretAppearance.isAlwaysHollow = false`, `caretAppearance.marksActivePane = true`, `ComposableTabsActivePane.shared.isInActivePane(view) == true` | Caret is filled |
| themed-terminal-view-014 | default-fill | `caretAppearance.isAlwaysHollow = false`, `caretAppearance.marksActivePane = false`, view not inside any composable-tabs pane | Caret is filled |
| themed-terminal-view-015 | hollow-caret-color | Caret computed as hollow | `caretColor == .clear` |
| themed-terminal-view-016 | filled-caret-color | Caret computed as filled, `caretAppearance.color == .systemBlue` | `caretColor == .systemBlue` |
| themed-terminal-view-017 | hollow-text-color | Caret computed as hollow, `caretAppearance.textColor == .black` | `caretTextColor == .black` |
| themed-terminal-view-018 | filled-text-color | Caret computed as filled | `caretTextColor == nil` |
| themed-terminal-view-019 | hollow-border | Caret computed as hollow, caret subview present, `caretAppearance.color == .systemBlue` | Caret subview layer `borderWidth == 1`, `borderColor == NSColor.systemBlue.cgColor` |
| themed-terminal-view-020 | filled-border | Caret computed as filled, caret subview present | Caret subview layer `borderWidth == 0`, `borderColor == nil` |
| themed-terminal-view-021 | missing-caret-subview-tolerance | No subview whose type name ends in `"CaretView"` exists (e.g. `applyOutline()` called before SwiftTerm adds its caret) | No exception is thrown; no layer property is modified |
| themed-terminal-view-022 | caret-subview-type-name-match | Add a subview whose dynamic type name is `"XTermCaretView"` | `caretView` resolves to that subview |
| themed-terminal-view-023 | caret-subview-cache | `caretView` resolved once; the resolved subview is removed and replaced by a new subview of a matching type name | A subsequent `caretView` access re-searches and returns the new subview rather than the stale (now-detached) one |

`main-actor-isolation` has no row here: it is a compile-time guarantee, verified by the Swift compiler's `@MainActor` isolation checking, not by a runtime conformance vector (see Design Decisions).
