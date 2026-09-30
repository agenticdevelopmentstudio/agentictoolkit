<!-- leaf: implement-general-view-3/themed-terminal-view · source: themed-terminal-view.md -->

**Rules** (cite as `implement-general-view-3/themed-terminal-view#<slug>`):

- `main-actor-isolation` MUST
- `coder-initializer` MUST
- `caret-appearance-property` MUST
- `appearance-change-recompute` MUST
- `window-attach-recompute` MUST
- `active-pane-subscription` MUST
- `active-pane-notification-window-filter` MUST
- `cursor-shown-outline-reapply` MUST
- `cursor-style-change-outline-reapply` MUST
- `always-hollow-flag` MUST
- `active-pane-marking` MUST
- `default-fill` MUST
- `hollow-caret-color` MUST
- `filled-caret-color` MUST
- `hollow-text-color` MUST
- `filled-text-color` MUST
- `hollow-border` MUST
- `filled-border` MUST
- `missing-caret-subview-tolerance` MUST
- `caret-subview-type-name-match` MUST
- `caret-subview-cache` SHOULD

# Themed Terminal View (Hollow Caret)

## Overview

`ThemedTerminalView` (`packages/apple/AgenticToolkit/macOS/Features/TerminalSession/ThemedTerminalView.swift`) is an internal, `@MainActor`-confined `NSView` subclass of SwiftTerm's `LocalProcessTerminalView` that decides, on every relevant AppKit and SwiftTerm callback, whether its block-shaped text caret is drawn filled or as a hollow outline. SwiftTerm's own `CursorStyle` enum (`SwiftTerm/TerminalOptions.swift`) has no hollow-block case among its six styles, and its caret view (`SwiftTerm/Mac/MacCaretView.swift`'s `CaretView` class) is internal to the package, so `ThemedTerminalView` fakes the outline by drawing a border on the caret subview's own layer rather than substituting a caret of its own — SwiftTerm keeps ownership of the caret's position, size, and blink animation. The class is declared `internal` rather than `public` because a public `NSView` subclass would name `LocalProcessTerminalView` in the framework's generated Objective-C header, and that header cannot resolve the Swift-only `SwiftTerm` module the name depends on. Two independent inputs decide the hollow-versus-filled state: a per-instance `CaretAppearance` value the caller sets directly, and — only when that appearance opts in via `marksActivePane` — whether this view sits inside the pane that `ComposableTabsActivePane` (`agentictoolkit://recipes/composable-tabs-active-pane`) currently treats as active for its window.

## Behavioral Requirements

- **main-actor-isolation**: The component MUST be usable only on the main actor; the class is declared `@MainActor`.
- **coder-initializer**: The component MUST fatal-error if constructed through `init?(coder:)`.
- **caret-appearance-property**: The component MUST expose a public `caretAppearance` property of type `CaretAppearance` (with fields `color: NSColor`, `textColor: NSColor`, `isAlwaysHollow: Bool`, `marksActivePane: Bool`), defaulting to `CaretAppearance()` when the caller sets no value.
- **appearance-change-recompute**: WHEN `caretAppearance` is set to a new value, the component MUST re-evaluate whether the caret is hollow and re-apply the caret's color, text color, and border accordingly.
- **window-attach-recompute**: WHEN `viewDidMoveToWindow` runs, the component MUST re-evaluate whether the caret is hollow and re-apply the caret's color, text color, and border accordingly.
- **active-pane-subscription**: The component MUST subscribe, at initialization, to `ComposableTabsActivePane.didChangeNotification` for the lifetime of the instance.
- **active-pane-notification-window-filter**: WHEN a `ComposableTabsActivePane.didChangeNotification` is received, the component MUST re-evaluate and re-apply the caret's appearance only if the notification's `object` is an `NSWindow` identical to the view's own `window`; otherwise it MUST take no action.
- **cursor-shown-outline-reapply**: WHEN SwiftTerm invokes `showCursor(source:)`, the component MUST re-apply the caret's border using its already-computed hollow/filled state, without recomputing that state.
- **cursor-style-change-outline-reapply**: WHEN SwiftTerm invokes `cursorStyleChanged(source:newStyle:)`, the component MUST re-apply the caret's border using its already-computed hollow/filled state, without recomputing that state.
- **always-hollow-flag**: The component MUST treat the caret as hollow whenever `caretAppearance.isAlwaysHollow` is `true`, regardless of `marksActivePane` or the active-pane state.
- **active-pane-marking**: WHEN `caretAppearance.isAlwaysHollow` is `false` AND `caretAppearance.marksActivePane` is `true`, the component MUST treat the caret as hollow if and only if `ComposableTabsActivePane.shared.isInActivePane(self)` returns `false`.
- **default-fill**: WHEN `caretAppearance.isAlwaysHollow` is `false` AND `caretAppearance.marksActivePane` is `false`, the component MUST treat the caret as filled, independent of the active-pane state.
- **hollow-caret-color**: WHEN the caret is hollow, the component MUST set the inherited `caretColor` property to `.clear`.
- **filled-caret-color**: WHEN the caret is filled, the component MUST set the inherited `caretColor` property to `caretAppearance.color`.
- **hollow-text-color**: WHEN the caret is hollow, the component MUST set the inherited `caretTextColor` property to `caretAppearance.textColor`.
- **filled-text-color**: WHEN the caret is filled, the component MUST set the inherited `caretTextColor` property to `nil`.
- **hollow-border**: WHEN the caret is hollow AND SwiftTerm's caret subview can be located, the component MUST set that subview layer's border width to `1` point and its border color to `caretAppearance.color`.
- **filled-border**: WHEN the caret is filled AND SwiftTerm's caret subview can be located, the component MUST set that subview layer's border width to `0` and its border color to `nil`.
- **missing-caret-subview-tolerance**: WHEN SwiftTerm's caret subview cannot be located, the component MUST take no action on the border and MUST NOT raise an error or crash.
- **caret-subview-type-name-match**: The component MUST locate SwiftTerm's caret subview by finding the first direct subview whose runtime type name (via `String(describing: type(of:))`) ends with the suffix `"CaretView"`.
- **caret-subview-cache**: The component SHOULD cache the located caret subview through a weak reference, and SHOULD re-search its subviews for a replacement whenever the cached reference's `superview` is no longer the component itself.

## Appearance

- **Corner radius**: Not set — no `cornerRadius` assignment appears in source; only a plain rectangular layer border is applied to the caret subview.
- **Padding**: Not applicable — `ThemedTerminalView` lays out no content of its own; it only mutates an existing SwiftTerm-owned subview's layer properties.
- **Font**: Not set — no font assignment appears in source; the terminal's font is entirely `LocalProcessTerminalView`'s own.
- **Background**: Not set — `ThemedTerminalView` sets no background color of its own; the terminal's background is entirely `LocalProcessTerminalView`'s own.
- **Foreground/Text**: `caretTextColor` is set to `caretAppearance.textColor` only while the caret is hollow, so the glyph under the outline reads as ordinary text (per source: "nothing is reversed out of an outline"); it is cleared to `nil` while the caret is filled, leaving SwiftTerm's own reversed-text color in effect.
- **Border**: The caret subview's layer border is `1` point wide (`Self.outlineWidth`) in `caretAppearance.color` while hollow, and `0` width with a `nil` color while filled.
- **Shadow**: Not set — no shadow customization appears in source.
- **Min/Max size**: Not set — `ThemedTerminalView` defines no size constraint of its own; sizing is entirely `LocalProcessTerminalView`'s.

## Accessibility

- **Role**: Not set by `ThemedTerminalView` — no accessibility role/trait assignment appears in source; whatever role `LocalProcessTerminalView` establishes is inherited unmodified.
- **Label**: Not set by `ThemedTerminalView` — no accessibility label assignment appears in source; labeling is entirely `LocalProcessTerminalView`'s own responsibility.
- **Announce state changes**: Not applicable: `ThemedTerminalView` defines no disabled or loading state of its own to announce (see States).
- **Keyboard navigation**: Not set by `ThemedTerminalView` — no key-handling override appears in source; keyboard input and focus traversal are entirely `LocalProcessTerminalView`'s own, inherited unmodified.
- **Minimum tap target**: Not applicable — `ThemedTerminalView` defines no tap/click target of its own; it inherits `LocalProcessTerminalView`'s full-bounds hit area unmodified and sets no separate frame or size constraint.
- **contrast-ratio**: NEEDS REVIEW: Not implemented in source. `caretAppearance.color` and `caretAppearance.textColor` are caller-supplied `NSColor` values applied verbatim (see #requirements/filled-caret-color, #requirements/hollow-text-color) with no contrast computation of its own; whether a given theme's caret color meets a minimum contrast ratio against the terminal background requires inspecting the theme/palette values actually passed in at the call site, outside this source.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `caretAppearance` | `CaretAppearance` | `CaretAppearance()` | The struct the caller sets to drive the caret's fill/outline decision; setting it re-evaluates and re-applies the caret's appearance. |
| `caretAppearance.color` | `NSColor` | `.white` | The caret's own color — its fill when filled, its outline when hollow. |
| `caretAppearance.textColor` | `NSColor` | `.white` | The glyph color under a hollow caret, so the character under the outline reads as ordinary text. |
| `caretAppearance.isAlwaysHollow` | `Bool` | `false` | Forces the caret hollow unconditionally, regardless of `marksActivePane` or the active-pane state. |
| `caretAppearance.marksActivePane` | `Bool` | `false` | When `true` (and `isAlwaysHollow` is `false`), hollows the caret whenever this view is not inside the pane `ComposableTabsActivePane` currently treats as active. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the caret's border-width/border-color and `caretColor`/`caretTextColor` changes are instantaneous property assignments with no animation, transition, or movement code in source. |
| Increase Contrast | Not applicable from within this file: `ThemedTerminalView` performs no color computation of its own — `caretAppearance.color`/`textColor` are applied verbatim from whatever the caller supplies (see the open question on contrast-ratio under Accessibility). |
| Differentiate Without Color | Supported: the active-pane indication conveyed by `marksActivePane` is the caret's *shape* — filled block versus hollow outline — not its color alone, per source: "A full block, which also says which pane the user is working in: filled here, an outline in every other pane." |

## Privacy

- **Data collected**: None of its own — `ThemedTerminalView` holds only the `CaretAppearance` value (two colors, two booleans) and a weak view reference in memory. The terminal session's actual command/output content is entirely `LocalProcessTerminalView`'s responsibility, outside this file.
- **Storage**: N/A — no persistence call appears in source; state lives only in memory for the view's lifetime.
- **Transmission**: N/A — `ThemedTerminalView` performs no network or IPC calls.
- **Retention**: N/A — nothing is retained beyond the view's lifetime.

