---
id: 2cd6ffc0-e9db-425b-99ba-eb826ffff118
title: ThemedTerminalView
domain: agentictoolkit://recipes/themed-terminal-view
type: ingredient
version: 1.0.0
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
- https://developer.apple.com/design/human-interface-guidelines/
approved-by: ''
approved-date: ''
---

# ThemedTerminalView

## Overview

`ThemedTerminalView` (`packages/apple/AgenticToolkit/macOS/Features/TerminalSession/ThemedTerminalView.swift`) is an internal, `@MainActor`-confined `NSView` subclass of SwiftTerm's `LocalProcessTerminalView` that decides, on every relevant AppKit and SwiftTerm callback, whether its block-shaped text caret is drawn filled or as a hollow outline. SwiftTerm's own `CursorStyle` has no hollow-block case and its caret view is internal to the package, so `ThemedTerminalView` fakes the outline by drawing a border on the caret subview's own layer rather than substituting a caret of its own — SwiftTerm keeps ownership of the caret's position, size, and blink animation. The class is declared `internal` rather than `public` because a public `NSView` subclass would name `LocalProcessTerminalView` in the framework's generated Objective-C header, and that header cannot resolve the Swift-only `SwiftTerm` module the name depends on. Two independent inputs decide the hollow-versus-filled state: a per-instance `CaretAppearance` value the caller sets directly, and — only when that appearance opts in via `marksActivePane` — whether this view sits inside the pane that `ComposableTabsActivePane` (`agentictoolkit://recipes/composable-tabs-active-pane`) currently treats as active for its window.

## Behavioral Requirements

- **confines-to-main-actor**: The component MUST be usable only on the main actor; the class is declared `@MainActor`.
- **rejects-coder-initializer**: The component MUST fatal-error if constructed through `init?(coder:)`.
- **exposes-caret-appearance**: The component MUST expose a public `caretAppearance` property of type `CaretAppearance` (with fields `color: NSColor`, `textColor: NSColor`, `isAlwaysHollow: Bool`, `marksActivePane: Bool`), defaulting to `CaretAppearance()` when the caller sets no value.
- **recomputes-caret-on-appearance-change**: WHEN `caretAppearance` is set to a new value, the component MUST re-evaluate whether the caret is hollow and re-apply the caret's color, text color, and border accordingly.
- **recomputes-caret-on-window-attach**: WHEN `viewDidMoveToWindow` runs, the component MUST re-evaluate whether the caret is hollow and re-apply the caret's color, text color, and border accordingly.
- **observes-active-pane-changes**: The component MUST subscribe, at initialization, to `ComposableTabsActivePane.didChangeNotification` for the lifetime of the instance.
- **filters-active-pane-notifications-by-window**: WHEN a `ComposableTabsActivePane.didChangeNotification` is received, the component MUST re-evaluate and re-apply the caret's appearance only if the notification's `object` is an `NSWindow` identical to the view's own `window`; otherwise it MUST take no action.
- **reapplies-outline-on-cursor-shown**: WHEN SwiftTerm invokes `showCursor(source:)`, the component MUST re-apply the caret's border using its already-computed hollow/filled state, without recomputing that state.
- **reapplies-outline-on-cursor-style-change**: WHEN SwiftTerm invokes `cursorStyleChanged(source:newStyle:)`, the component MUST re-apply the caret's border using its already-computed hollow/filled state, without recomputing that state.
- **computes-hollow-from-always-hollow-flag**: The component MUST treat the caret as hollow whenever `caretAppearance.isAlwaysHollow` is `true`, regardless of `marksActivePane` or the active-pane state.
- **computes-hollow-from-active-pane-when-marking**: WHEN `caretAppearance.isAlwaysHollow` is `false` AND `caretAppearance.marksActivePane` is `true`, the component MUST treat the caret as hollow if and only if `ComposableTabsActivePane.shared.isInActivePane(self)` returns `false`.
- **fills-caret-by-default**: WHEN `caretAppearance.isAlwaysHollow` is `false` AND `caretAppearance.marksActivePane` is `false`, the component MUST treat the caret as filled, independent of the active-pane state.
- **applies-clear-caret-color-when-hollow**: WHEN the caret is hollow, the component MUST set the inherited `caretColor` property to `.clear`.
- **applies-appearance-color-when-filled**: WHEN the caret is filled, the component MUST set the inherited `caretColor` property to `caretAppearance.color`.
- **applies-text-color-when-hollow**: WHEN the caret is hollow, the component MUST set the inherited `caretTextColor` property to `caretAppearance.textColor`.
- **clears-text-color-override-when-filled**: WHEN the caret is filled, the component MUST set the inherited `caretTextColor` property to `nil`.
- **draws-hollow-border**: WHEN the caret is hollow AND SwiftTerm's caret subview can be located, the component MUST set that subview layer's border width to `1` point and its border color to `caretAppearance.color`.
- **removes-border-when-filled**: WHEN the caret is filled AND SwiftTerm's caret subview can be located, the component MUST set that subview layer's border width to `0` and its border color to `nil`.
- **tolerates-missing-caret-subview**: WHEN SwiftTerm's caret subview cannot be located, the component MUST take no action on the border and MUST NOT raise an error or crash.
- **identifies-caret-subview-by-type-name-suffix**: The component MUST locate SwiftTerm's caret subview by finding the first direct subview whose runtime type name (via `String(describing: type(of:))`) ends with the suffix `"CaretView"`.
- **caches-caret-subview-reference**: The component MUST cache the located caret subview through a weak reference, and MUST re-search its subviews for a replacement whenever the cached reference's `superview` is no longer the component itself.

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
- **Contrast ratio**: NEEDS REVIEW: `caretAppearance.color` and `caretAppearance.textColor` are caller-supplied `NSColor` values applied verbatim (see **applies-appearance-color-when-filled**, **applies-text-color-when-hollow**); the source performs no contrast computation or validation of its own. Whether a given theme's caret color meets a minimum contrast ratio against the terminal background cannot be determined from this file — it requires inspecting the theme/palette values actually passed in at the call site, which is outside the given source.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| themed-terminal-view-001 | confines-to-main-actor | Attempt to construct or mutate `ThemedTerminalView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| themed-terminal-view-002 | rejects-coder-initializer | Construct via `ThemedTerminalView(coder:)` with any `NSCoder` | Execution traps via `fatalError` |
| themed-terminal-view-003 | exposes-caret-appearance | Construct `ThemedTerminalView` and read `caretAppearance` before setting it | `caretAppearance.color == .white`, `caretAppearance.textColor == .white`, `caretAppearance.isAlwaysHollow == false`, `caretAppearance.marksActivePane == false` |
| themed-terminal-view-004 | recomputes-caret-on-appearance-change | View with default `caretAppearance`; set `caretAppearance.isAlwaysHollow = true` | `caretColor` becomes `.clear` and the caret subview's layer border width becomes `1` without any other call |
| themed-terminal-view-005 | recomputes-caret-on-window-attach | View constructed with `caretAppearance.isAlwaysHollow == true`, not yet in a window; add it to a window | After `viewDidMoveToWindow` runs, `caretColor == .clear` and the caret subview's border width is `1` |
| themed-terminal-view-006 | observes-active-pane-changes | Construct a `ThemedTerminalView` | A `Cancellable` for `ComposableTabsActivePane.didChangeNotification` is present in the instance's `cancellables` set |
| themed-terminal-view-007 | filters-active-pane-notifications-by-window | View is in window A; post `ComposableTabsActivePane.didChangeNotification` with `object` set to window B | The view's caret color/border are unchanged |
| themed-terminal-view-008 | filters-active-pane-notifications-by-window | View is in window A; post `ComposableTabsActivePane.didChangeNotification` with `object` set to window A | `updateCaret()` runs and the caret's color/border reflect the current `caretAppearance`/active-pane state |
| themed-terminal-view-009 | reapplies-outline-on-cursor-shown | `isHollow` already computed as `true`; invoke `showCursor(source:)` | The caret subview's border width is (re)set to `1` in `caretAppearance.color` without `caretColor`/`caretTextColor` being recomputed from `caretAppearance` |
| themed-terminal-view-010 | reapplies-outline-on-cursor-style-change | `isHollow` already computed as `false`; invoke `cursorStyleChanged(source:newStyle:)` with any `CursorStyle` | The caret subview's border width is (re)set to `0` regardless of `newStyle`'s value |
| themed-terminal-view-011 | computes-hollow-from-always-hollow-flag | `caretAppearance.isAlwaysHollow = true`, `caretAppearance.marksActivePane = true`, view is in the active pane | Caret is hollow |
| themed-terminal-view-012 | computes-hollow-from-active-pane-when-marking | `caretAppearance.isAlwaysHollow = false`, `caretAppearance.marksActivePane = true`, `ComposableTabsActivePane.shared.isInActivePane(view) == false` | Caret is hollow |
| themed-terminal-view-013 | computes-hollow-from-active-pane-when-marking | `caretAppearance.isAlwaysHollow = false`, `caretAppearance.marksActivePane = true`, `ComposableTabsActivePane.shared.isInActivePane(view) == true` | Caret is filled |
| themed-terminal-view-014 | fills-caret-by-default | `caretAppearance.isAlwaysHollow = false`, `caretAppearance.marksActivePane = false`, view not inside any composable-tabs pane | Caret is filled |
| themed-terminal-view-015 | applies-clear-caret-color-when-hollow | Caret computed as hollow | `caretColor == .clear` |
| themed-terminal-view-016 | applies-appearance-color-when-filled | Caret computed as filled, `caretAppearance.color == .systemBlue` | `caretColor == .systemBlue` |
| themed-terminal-view-017 | applies-text-color-when-hollow | Caret computed as hollow, `caretAppearance.textColor == .black` | `caretTextColor == .black` |
| themed-terminal-view-018 | clears-text-color-override-when-filled | Caret computed as filled | `caretTextColor == nil` |
| themed-terminal-view-019 | draws-hollow-border | Caret computed as hollow, caret subview present, `caretAppearance.color == .systemBlue` | Caret subview layer `borderWidth == 1`, `borderColor == NSColor.systemBlue.cgColor` |
| themed-terminal-view-020 | removes-border-when-filled | Caret computed as filled, caret subview present | Caret subview layer `borderWidth == 0`, `borderColor == nil` |
| themed-terminal-view-021 | tolerates-missing-caret-subview | No subview whose type name ends in `"CaretView"` exists (e.g. `applyOutline()` called before SwiftTerm adds its caret) | No exception is thrown; no layer property is modified |
| themed-terminal-view-022 | identifies-caret-subview-by-type-name-suffix | Add a subview whose dynamic type name is `"XTermCaretView"` | `caretView` resolves to that subview |
| themed-terminal-view-023 | caches-caret-subview-reference | `caretView` resolved once; the resolved subview is removed and replaced by a new subview of a matching type name | A subsequent `caretView` access re-searches and returns the new subview rather than the stale (now-detached) one |

## Edge Cases

- **Null/empty input**: `caretAppearance` defaults to `CaretAppearance()` when the caller never sets it, resolving to a filled caret in `.white`/`.white` (see **fills-caret-by-default**). This is the well-defined default, not an error condition. MUST.
- **Boundary values**: Not applicable — the only caller-supplied inputs are two `NSColor` values and two `Bool` flags, none of which have a numeric range; the one numeric constant in the file, `outlineWidth: CGFloat = 1`, is fixed and not caller-configurable.
- **Concurrent access**: Not applicable — the class is `@MainActor`, so every mutation path (the `caretAppearance` `didSet`, the notification `sink`, and the `showCursor`/`cursorStyleChanged` overrides) is confined to the main actor by the compiler (see **confines-to-main-actor**).
- **Error states**: WHEN the `ComposableTabsActivePane.didChangeNotification`'s `object` is not an `NSWindow` (including `nil`), the component MUST silently ignore the notification and take no action, per the `guard ... as? NSWindow` in the subscription closure. There is no other error-producing dependency (no network, database, or file-system access) in this file, so Cookbook Compliance's networking/error-handling requirements are Not applicable here.
- **Offline/disconnected state**: Not applicable — the component performs no networking; its only external interaction is a local `NotificationCenter` publisher and AppKit view-hierarchy calls.
- **Caret subview not yet present**: `applyOutline()`'s `guard let caret = caretView else { return }` MUST make border application a silent no-op rather than crash (see **tolerates-missing-caret-subview**). MUST.
- **Caret subview rebuilt by SwiftTerm**: WHEN the cached weak `cachedCaret` reference's `superview` is no longer `self`, the component MUST re-search rather than reuse the stale reference (see **caches-caret-subview-reference**). MUST.
- **View not yet embedded in any composable-tabs pane while `marksActivePane == true`**: `ComposableTabsActivePane.isInActivePane` treats a view with no `ComposableTabsPaneBackgroundView` ancestor as always "in the active pane," so `marksActivePane` alone cannot force the caret hollow outside composable-tabs context — only `isAlwaysHollow` can (traced to `ComposableTabsActivePane.isInActivePane`'s superview-walk returning `true` when no ancestor pane is found). MUST.
- **Multiple `ThemedTerminalView` instances across different windows**: each instance MUST ignore a `didChangeNotification` whose `object` window does not match its own `window`, so a pane-activation change in one window never repaints a caret in another (see **filters-active-pane-notifications-by-window**). MUST.

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
- **WinUI 3**: If hosting a real terminal buffer, `Microsoft.Terminal.Control.TermControl` (from the Windows Terminal control package) exposes cursor styling via its settings but, like SwiftTerm, has no built-in hollow-outline cursor style — reproduce the same border-overlay technique used here: track the active cell's caret with a `Border` element layered over the terminal surface, and toggle between a filled state (`Border.Background` set to the caret color, `BorderThickness="0"`) and a hollow state (`Border.Background` set to `Transparent`, `BorderThickness="1"`, `BorderBrush` set to the caret color) through a `VisualStateManager` `VisualState`, mirroring this file's `borderWidth`/`borderColor` toggle exactly. Use the app's `Window.Activated`/`Deactivated` events as the WinUI analog of `NSWindow.didBecomeKey`/`didResignKey` for tracking which pane is active per window, and a shared static event (or `WeakEventManager`) as the analog of `NotificationCenter.default.publisher(for: ComposableTabsActivePane.didChangeNotification)` for broadcasting an active-pane change to every terminal control that needs to repaint its caret.

## Design Decisions

**Decision**: The class is declared `internal` rather than `public` or `open`.
**Rationale**: Per source: "a *public* NSView subclass would name `LocalProcessTerminalView` in the framework's generated Objective-C header, which then cannot find the Swift-only `SwiftTerm` module."
**Approved: pending**

**Decision**: `showCursor(source:)` and `cursorStyleChanged(source:newStyle:)` call only `applyOutline()`, reusing the last-computed `isHollow`, rather than calling `updateCaret()` (which would recompute `isHollow` and rewrite `caretColor`/`caretTextColor`).
**Rationale**: Per source: "Deliberately *not* on the `showCursor` path, which runs on every cursor movement: the two colours below are properties SwiftTerm holds on to, so they want writing when the answer changes rather than once a frame."
**Approved: pending**

**Decision**: SwiftTerm's caret subview is located by matching a runtime type-name suffix (`"CaretView"`) rather than a typed accessor, and the match is weakly cached.
**Rationale**: Per source: "SwiftTerm adds its caret as a direct subview but exposes no accessor for it, so it is recognized by class name... Cached, because the search is not free and the caller is not rare... a per-keystroke cost for an answer that changes when SwiftTerm rebuilds its subviews and at no other time."
**Approved: pending**

**Decision**: A view with no `ComposableTabsPaneBackgroundView` ancestor — or a window with no active pane recorded yet — is treated by `ComposableTabsActivePane.isInActivePane` as "in the active pane," so `marksActivePane` never hollows such a caret.
**Rationale**: Per `ComposableTabsActivePane.swift`: "A view in no pane at all — the standalone terminal window, the quick note panel — counts as active: 'not the active pane' has to mean *another* pane holds the user, not that there are no panes to hold them."
**Approved: pending**

**Decision**: `CaretAppearance.color` and `CaretAppearance.textColor` default to the literal `NSColor.white` rather than a semantic theme token.
**Rationale**: No rationale is given in source comments for this specific choice; it is recorded here as a technical-debt observation because it affects the `no-raw-hex` compliance check below — see Compliance.
**Approved: pending**

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | Architecture |
| [no-raw-hex](agenticdevelopercookbook://compliance/ui-tokens#no-raw-hex) | failed | UI Tokens |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |

`main-actor-confined` passes because the class is declared `@MainActor` (see **confines-to-main-actor**). `no-raw-hex` fails because `CaretAppearance.color` and `CaretAppearance.textColor` default to the literal `NSColor.white` rather than a semantic palette token (see the corresponding Design Decision). `differentiate-without-color` passes because the active-pane state `marksActivePane` conveys is carried by the caret's shape (filled versus hollow), not by color alone. `contrast-ratio` is `partial`: the caret's colors are applied verbatim from caller input with no contrast computation in this file, so conformance depends entirely on what the caller supplies — see the **Contrast ratio** entry under Accessibility. `keyboard-navigable` and `screen-reader-support` pass because `ThemedTerminalView` adds no keyboard handling, role, or label of its own, leaving `LocalProcessTerminalView`'s own behavior unmodified.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
