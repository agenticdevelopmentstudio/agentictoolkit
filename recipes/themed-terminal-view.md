---
id: 2cd6ffc0-e9db-425b-99ba-eb826ffff118
title: Themed Terminal View (Hollow Caret)
domain: agentictoolkit://recipes/themed-terminal-view
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Internal AppKit LocalProcessTerminalView subclass that toggles its SwiftTerm
  block caret between filled and hollow-outline based on theme and composable-tabs
  pane focus.
platforms:
- swift
- macos
tags:
- terminal
- caret
- composable-tabs
- appkit
- macos
depends-on:
- agentictoolkit://recipes/composable-tabs-active-pane
related: []
references:
- https://github.com/migueldeicaza/SwiftTerm/blob/8e7a1e154f470e19c709a00a8768df348ba5fc43/Sources/SwiftTerm/TerminalOptions.swift
- https://github.com/migueldeicaza/SwiftTerm/blob/8e7a1e154f470e19c709a00a8768df348ba5fc43/Sources/SwiftTerm/Mac/MacCaretView.swift
approved-by: ''
approved-date: ''
---

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

## States

| State | Appearance change |
|-------|------------------|
| Default | On construction, `caretAppearance` is `CaretAppearance()` (`color`/`textColor` both `.white`, `isAlwaysHollow`/`marksActivePane` both `false`), which resolves to the Filled state below. |
| Pressed | Not applicable: `ThemedTerminalView` renders a text caret, not a pressable control, and defines no pressed-state handling of its own. |
| Disabled | Not applicable: the source never reads or sets an enabled/disabled flag on this view. |
| Focused | Not applicable as a first-responder concept: the caret's hollow/filled decision is driven by `isAlwaysHollow`/`marksActivePane` plus `ComposableTabsActivePane`, not by this view's own key/first-responder status directly. |
| Loading | Not applicable: `ThemedTerminalView` performs no asynchronous work of its own. |
| Filled (custom) | `caretColor == caretAppearance.color`, `caretTextColor == nil`, caret subview layer border width `0`. Reached when `isAlwaysHollow == false` and either `marksActivePane == false` or `isInActivePane(self) == true`. |
| Hollow — always (custom) | `caretColor == .clear`, `caretTextColor == caretAppearance.textColor`, caret subview layer border width `1` in `caretAppearance.color`. Reached whenever `isAlwaysHollow == true`. |
| Hollow — inactive pane (custom) | Same appearance as "Hollow — always". Reached when `isAlwaysHollow == false`, `marksActivePane == true`, and `isInActivePane(self) == false`. |

## Accessibility

- **Role**: Not set by `ThemedTerminalView` — no accessibility role/trait assignment appears in source; whatever role `LocalProcessTerminalView` establishes is inherited unmodified.
- **Label**: Not set by `ThemedTerminalView` — no accessibility label assignment appears in source; labeling is entirely `LocalProcessTerminalView`'s own responsibility.
- **Announce state changes**: Not applicable: `ThemedTerminalView` defines no disabled or loading state of its own to announce (see States).
- **Keyboard navigation**: Not set by `ThemedTerminalView` — no key-handling override appears in source; keyboard input and focus traversal are entirely `LocalProcessTerminalView`'s own, inherited unmodified.
- **Minimum tap target**: Not applicable — `ThemedTerminalView` defines no tap/click target of its own; it inherits `LocalProcessTerminalView`'s full-bounds hit area unmodified and sets no separate frame or size constraint.
- **Contrast ratio**: NEEDS REVIEW: `caretAppearance.color` and `caretAppearance.textColor` are caller-supplied `NSColor` values applied verbatim (see #requirements/filled-caret-color, #requirements/hollow-text-color); the source performs no contrast computation or validation of its own. Whether a given theme's caret color meets a minimum contrast ratio against the terminal background cannot be determined from this file — it requires inspecting the theme/palette values actually passed in at the call site, which is outside the given source.

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `caretAppearance` | `CaretAppearance` | `CaretAppearance()` | The struct the caller sets to drive the caret's fill/outline decision; setting it re-evaluates and re-applies the caret's appearance. |
| `caretAppearance.color` | `NSColor` | `.white` | The caret's own color — its fill when filled, its outline when hollow. |
| `caretAppearance.textColor` | `NSColor` | `.white` | The glyph color under a hollow caret, so the character under the outline reads as ordinary text. |
| `caretAppearance.isAlwaysHollow` | `Bool` | `false` | Forces the caret hollow unconditionally, regardless of `marksActivePane` or the active-pane state. |
| `caretAppearance.marksActivePane` | `Bool` | `false` | When `true` (and `isAlwaysHollow` is `false`), hollows the caret whenever this view is not inside the pane `ComposableTabsActivePane` currently treats as active. |

## Deep Linking

Not applicable: `ThemedTerminalView` is a caret-rendering decorator on an existing terminal view with no navigable route, screen, or resource identity of its own — no URL scheme or routing code appears in source.

## Localization

Not applicable: the source contains no string literals passed to any user-facing text API; every value it manipulates is a color, a boolean, or a view reference.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the caret's border-width/border-color and `caretColor`/`caretTextColor` changes are instantaneous property assignments with no animation, transition, or movement code in source. |
| Increase Contrast | Not applicable from within this file: `ThemedTerminalView` performs no color computation of its own — `caretAppearance.color`/`textColor` are applied verbatim from whatever the caller supplies (see **Contrast ratio** under Accessibility for the separate, genuine open question of whether those supplied colors themselves meet a contrast threshold). |
| Differentiate Without Color | Supported: the active-pane indication conveyed by `marksActivePane` is the caret's *shape* — filled block versus hollow outline — not its color alone, per source: "A full block, which also says which pane the user is working in: filled here, an outline in every other pane." |

## Feature Flags

Not applicable: the source contains no feature-flag check; `ThemedTerminalView` always evaluates and applies its caret appearance unconditionally.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

- **Data collected**: None of its own — `ThemedTerminalView` holds only the `CaretAppearance` value (two colors, two booleans) and a weak view reference in memory. The terminal session's actual command/output content is entirely `LocalProcessTerminalView`'s responsibility, outside this file.
- **Storage**: N/A — no persistence call appears in source; state lives only in memory for the view's lifetime.
- **Transmission**: N/A — `ThemedTerminalView` performs no network or IPC calls.
- **Retention**: N/A — nothing is retained beyond the view's lifetime.

## Logging

Not applicable: the source contains no logging calls.

## Platform Notes

- **SwiftUI**: There is no SwiftUI-native terminal emulator equivalent to `LocalProcessTerminalView`; wrap it (or another terminal engine) in an `NSViewRepresentable`, exposing `CaretAppearance` as a `Binding` the representable's `updateNSView(_:context:)` writes into the wrapped `ThemedTerminalView`'s `caretAppearance` property on every SwiftUI update, rather than re-deriving the hollow/filled decision in SwiftUI itself.
- **Compose**: Wrap an Android terminal-emulation view (there is no Jetpack Compose-native equivalent) in an `AndroidView`, and reproduce the caret decision as a small `Drawable`/custom `View` overlay whose stroke is toggled on/off the same way this file toggles `layer.borderWidth`; drive it from a `mutableStateOf<CaretAppearance>` the same way `caretAppearance`'s `didSet` drives `updateCaret()`.
- **React/Web**: xterm.js exposes `cursorStyle: 'block' | 'underline' | 'bar'` and theme colors (`cursor`, `cursorAccent`) but no built-in hollow-block style either; reproduce the outline by setting the cursor cell's CSS to a transparent background with a `1px solid` outline/border color, toggled by the same `isAlwaysHollow`/`marksActivePane`-equivalent booleans, and drive `cursorAccent` the way this file drives `caretTextColor`.
- **AppKit / UIKit (source)**: `ThemedTerminalView.swift` is macOS-only (`import AppKit`); there is no UIKit counterpart in this file. It subclasses SwiftTerm's `LocalProcessTerminalView`, is declared `internal` specifically to avoid an Objective-C header conflict with the Swift-only `SwiftTerm` module, locates SwiftTerm's private caret subview by matching its runtime type name's `"CaretView"` suffix (with a weak, superview-validated cache), and separates "recompute the hollow/filled decision" (`updateCaret()`, run on appearance/window/notification changes) from "just repaint the border" (`applyOutline()`, run on every SwiftTerm cursor callback) to avoid rewriting SwiftTerm's caret color properties on every cursor movement.
- **WinUI 3**: If hosting a real terminal buffer, `Microsoft.Terminal.Control.TermControl` (from the Windows Terminal control package) is understood to expose some cursor-styling options through its settings, but this recipe has no cited source confirming whether it offers anything like a hollow-outline style, so treat that specific claim as unverified. Independent of what `TermControl` offers natively, the same border-overlay technique used here can be reproduced generically: track the active cell's caret with a `Border` element layered over the terminal surface, and toggle between a filled state (`Border.Background` set to the caret color, `BorderThickness="0"`) and a hollow state (`Border.Background` set to `Transparent`, `BorderThickness="1"`, `BorderBrush` set to the caret color) through a `VisualStateManager` `VisualState`, mirroring this file's `borderWidth`/`borderColor` toggle. Use a shared static event (or `WeakEventManager`) as the WinUI analog of `NotificationCenter.default.publisher(for: ComposableTabsActivePane.didChangeNotification)` for broadcasting an active-pane change to every terminal control that needs to repaint its caret — this class has no key-window handling of its own to draw an analogy from.

## Design Decisions

**Decision**: The class is declared `internal` rather than `public` or `open`.
**Rationale**: Per source: "a *public* NSView subclass would name `LocalProcessTerminalView` in the framework's generated Objective-C header, which then cannot find the Swift-only `SwiftTerm` module."
**Approved**: pending

**Decision**: `showCursor(source:)` and `cursorStyleChanged(source:newStyle:)` call only `applyOutline()`, reusing the last-computed `isHollow`, rather than calling `updateCaret()` (which would recompute `isHollow` and rewrite `caretColor`/`caretTextColor`).
**Rationale**: Per source: "Deliberately *not* on the `showCursor` path, which runs on every cursor movement: the two colours below are properties SwiftTerm holds on to, so they want writing when the answer changes rather than once a frame."
**Approved**: pending

**Decision**: SwiftTerm's caret subview is located by matching a runtime type-name suffix (`"CaretView"`) rather than a typed accessor, and the match is weakly cached.
**Rationale**: Per source: "SwiftTerm adds its caret as a direct subview but exposes no accessor for it, so it is recognized by class name... Cached, because the search is not free and the caller is not rare... a per-keystroke cost for an answer that changes when SwiftTerm rebuilds its subviews and at no other time."
**Approved**: pending

**Decision**: `main-actor-isolation` has no runtime conformance vector; it is verified by the Swift compiler's `@MainActor` isolation checking at compile time.
**Rationale**: A MUST requirement enforced entirely by the type system needs no runtime test to demonstrate — violating it is a compile error, not an outcome a test vector could observe.
**Approved**: pending

**Decision**: `ThemedTerminalView` relies on `ComposableTabsActivePane.isInActivePane` treating a view with no `ComposableTabsPaneBackgroundView` ancestor as "in the active pane" (see `agentictoolkit://recipes/composable-tabs-active-pane#requirements/view-outside-any-pane-counts-as-active`), so `marksActivePane` never hollows such a caret.
**Rationale**: The consequence for this file: a `ThemedTerminalView` used outside any composable-tabs pane with `marksActivePane == true` stays filled rather than hollow, because it is never "not in" an active pane by that dependency's own rule. The rule itself, and why it treats an unclaimed view as active, belongs to `composable-tabs-active-pane` and is not restated here.
**Approved**: pending

**Decision**: `CaretAppearance.color` and `CaretAppearance.textColor` default to the literal `NSColor.white` rather than a semantic theme-color token.
**Rationale**: No rationale is given in source for this specific choice, and no call site in this codebase overrides it with a semantic token — nothing marks it deliberate, and nothing records a plan to pay it down. It should become whichever semantic accent/foreground color token the app's theme system exposes for this purpose once one exists; see the `platform-theming` compliance status below.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | failed | Platform Compliance |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |

`platform-theming` fails because `CaretAppearance.color` and `CaretAppearance.textColor` default to the literal `NSColor.white` rather than a semantic, theme-aware color token, so the caret's own defaults do not adapt to the app's theme (see the corresponding Design Decision). `contrast-ratio` is `partial`: the caret's colors are applied verbatim from caller input with no contrast computation in this file, so conformance depends entirely on what the caller supplies — see the **Contrast ratio** entry under Accessibility. `keyboard-navigable` and `screen-reader-support` are `partial`: `ThemedTerminalView` adds no keyboard handling, role, or label of its own and overrides none of `LocalProcessTerminalView`'s, but this file gives no evidence of what `LocalProcessTerminalView` itself provides for either, so full conformance cannot be confirmed from this source alone.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed requirements to subject-only names and fragment-form cross-references, replaced the unfounded HIG reference with cited SwiftTerm sources, softened the unsourced WinUI 3 TermControl claim and dropped its false key-window analogy, folded the composable-tabs edge case and design decision into a single dependency citation, rewrote the Compliance table to real catalog checks (`platform-theming` in place of `no-raw-hex`, dropped `main-actor-confined`/`differentiate-without-color`, `keyboard-navigable`/`screen-reader-support` marked `partial`), reworded the `NSColor.white` design decision as an unexamined default rather than unexplained "technical debt", demoted `caret-subview-cache` to SHOULD, rewrote the private-state test vectors in observable terms, moved the compile-time vector out of the conformance table, and removed trailing "MUST." noise from edge cases |
