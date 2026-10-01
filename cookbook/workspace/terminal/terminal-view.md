---
id: 2cd6ffc0-e9db-425b-99ba-eb826ffff118
title: Themed Terminal View (Hollow Caret)
domain: agentictoolkit://cookbook/workspace/terminal/terminal-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A terminal view that toggles its block text caret between filled and
  hollow-outline based on the current theme and whether its pane has focus.
platforms:
- swift
- macos
tags:
- terminal
- caret
- composable-tabs
depends-on:
- agentictoolkit://cookbook/ui/layout/composable-tabs/active-pane
related: []
references:
- https://github.com/migueldeicaza/SwiftTerm/blob/8e7a1e154f470e19c709a00a8768df348ba5fc43/Sources/SwiftTerm/TerminalOptions.swift
- https://github.com/migueldeicaza/SwiftTerm/blob/8e7a1e154f470e19c709a00a8768df348ba5fc43/Sources/SwiftTerm/Mac/MacCaretView.swift
approved-by: ''
approved-date: ''
---

# Themed Terminal View (Hollow Caret)

## Overview

This is a terminal view — layered on the terminal-emulation library this
codebase uses — that decides, on every relevant view-hierarchy and
terminal-engine callback, whether its block-shaped text caret is drawn
filled or as a hollow outline. The underlying terminal-emulation
library's own cursor-style options have no hollow-block case among them,
and its own caret subview is not exposed for direct replacement, so this
view fakes the outline by drawing a border on the caret subview's own
layer rather than substituting a caret of its own — the underlying
library keeps ownership of the caret's position, size, and blink
animation. Two independent inputs decide the hollow-versus-filled state:
a per-instance appearance value the caller sets directly, and — only
when that appearance opts in via marking the active pane — whether this
view sits inside the pane that the active-pane tracker currently treats
as active for its window.

## Behavioral Requirements

- **main-thread-confinement**: The component MUST be usable only on the
  UI's main execution context.
- **caret-appearance-property**: The component MUST expose a public
  appearance property (fields: a caret color, a text color, an
  always-hollow flag, a marks-active-pane flag), defaulting to a white
  caret color and white text color with both flags `false` when the
  caller sets no value.
- **appearance-change-recompute**: WHEN the appearance property is set to
  a new value, the component MUST re-evaluate whether the caret is
  hollow and re-apply the caret's color, text color, and border
  accordingly.
- **window-attach-recompute**: WHEN the view is attached (or moved) to a
  window, the component MUST re-evaluate whether the caret is hollow and
  re-apply the caret's color, text color, and border accordingly.
- **active-pane-subscription**: The component MUST subscribe, at
  initialization, to the active-pane tracker's change notification for
  the lifetime of the instance.
- **active-pane-notification-window-filter**: WHEN a change notification
  from the active-pane tracker is received, the component MUST
  re-evaluate and re-apply the caret's appearance only if the
  notification identifies the same window as the view's own window;
  otherwise it MUST take no action.
- **cursor-shown-outline-reapply**: WHEN the terminal engine signals that
  the cursor is now shown, the component MUST re-apply the caret's
  border using its already-computed hollow/filled state, without
  recomputing that state.
- **cursor-style-change-outline-reapply**: WHEN the terminal engine
  signals that its cursor style changed, the component MUST re-apply the
  caret's border using its already-computed hollow/filled state, without
  recomputing that state.
- **always-hollow-flag**: The component MUST treat the caret as hollow
  whenever the always-hollow flag is `true`, regardless of the
  marks-active-pane flag or the active-pane state.
- **active-pane-marking**: WHEN the always-hollow flag is `false` AND the
  marks-active-pane flag is `true`, the component MUST treat the caret
  as hollow if and only if this view is not currently within the pane
  the active-pane tracker considers active.
- **default-fill**: WHEN the always-hollow flag is `false` AND the
  marks-active-pane flag is `false`, the component MUST treat the caret
  as filled, independent of the active-pane state.
- **hollow-caret-color**: WHEN the caret is hollow, the component MUST
  set the inherited caret-color property to fully transparent.
- **filled-caret-color**: WHEN the caret is filled, the component MUST
  set the inherited caret-color property to the appearance's own color.
- **hollow-text-color**: WHEN the caret is hollow, the component MUST set
  the inherited caret-text-color property to the appearance's own text
  color.
- **filled-text-color**: WHEN the caret is filled, the component MUST
  clear the inherited caret-text-color property to its unset/default
  state.
- **hollow-border**: WHEN the caret is hollow AND the terminal engine's
  caret subview can be located, the component MUST set that subview's
  layer border width to `1` point and its border color to the
  appearance's own color.
- **filled-border**: WHEN the caret is filled AND the terminal engine's
  caret subview can be located, the component MUST set that subview's
  layer border width to `0` and clear its border color.
- **missing-caret-subview-tolerance**: WHEN the terminal engine's caret
  subview cannot be located, the component MUST take no action on the
  border and MUST NOT raise an error or crash.
- **caret-subview-type-name-match**: The component MUST locate the
  terminal engine's caret subview by finding the first direct subview
  whose runtime type name ends with the suffix `"CaretView"`.
- **caret-subview-cache**: The component SHOULD cache the located caret
  subview through a weak reference, and SHOULD re-search its subviews
  for a replacement whenever the cached reference's superview is no
  longer the component itself.

## Appearance

- **Corner radius**: Not set — no rounding is applied; only a plain
  rectangular border is applied to the caret subview.
- **Padding**: Not applicable — this view lays out no content of its
  own; it only mutates an existing terminal-engine-owned subview's layer
  properties.
- **Font**: Not set — the terminal's font is entirely the underlying
  terminal engine's own.
- **Background**: Not set — this view sets no background color of its
  own; the terminal's background is entirely the underlying terminal
  engine's own.
- **Foreground/Text**: The caret's text color is set to the appearance's
  own text color only while the caret is hollow, so the glyph under the
  outline reads as ordinary text (per source: "nothing is reversed out
  of an outline"); it is cleared to its unset/default state while the
  caret is filled, leaving the terminal engine's own reversed-text color
  in effect.
- **Border**: The caret subview's layer border is `1` point wide in the
  appearance's own color while hollow, and `0` width with no color while
  filled.
- **Shadow**: Not set — no shadow customization appears in source.
- **Min/Max size**: Not set — this view defines no size constraint of
  its own; sizing is entirely the underlying terminal engine's own.

## States

| State | Appearance change |
|-------|------------------|
| Default | On construction, the appearance defaults to a white caret color and white text color, with the always-hollow and marks-active-pane flags both `false`, which resolves to the Filled state below. |
| Pressed | Not applicable: this view renders a text caret, not a pressable control, and defines no pressed-state handling of its own. |
| Disabled | Not applicable: the source never reads or sets an enabled/disabled flag on this view. |
| Focused | Not applicable as a first-responder concept: the caret's hollow/filled decision is driven by the always-hollow/marks-active-pane flags plus the active-pane tracker, not by this view's own key/first-responder status directly. |
| Loading | Not applicable: this view performs no asynchronous work of its own. |
| Filled (custom) | The caret color equals the appearance's own color, the text color is unset, caret subview layer border width `0`. Reached when the always-hollow flag is `false` and either the marks-active-pane flag is `false` or this view is within the active pane. |
| Hollow — always (custom) | The caret color is fully transparent, the text color equals the appearance's own text color, caret subview layer border width `1` in the appearance's own color. Reached whenever the always-hollow flag is `true`. |
| Hollow — inactive pane (custom) | Same appearance as "Hollow — always". Reached when the always-hollow flag is `false`, the marks-active-pane flag is `true`, and this view is not within the active pane. |

## Accessibility

- **Role**: Not set by this view — no accessibility role/trait assignment
  appears in source; whatever role the underlying terminal engine
  establishes is inherited unmodified.
- **Label**: Not set by this view — no accessibility label assignment
  appears in source; labeling is entirely the underlying terminal
  engine's own responsibility.
- **Announce state changes**: Not applicable: this view defines no
  disabled or loading state of its own to announce (see States).
- **Keyboard navigation**: Not set by this view — no key-handling
  override appears in source; keyboard input and focus traversal are
  entirely the underlying terminal engine's own, inherited unmodified.
- **Minimum tap target**: Not applicable — this view defines no
  tap/click target of its own; it inherits the underlying terminal
  engine's full-bounds hit area unmodified and sets no separate frame or
  size constraint.
- **contrast-ratio**: NEEDS REVIEW: Not implemented in source. The caret
  color and text color are caller-supplied values applied verbatim (see
  **filled-caret-color**, **hollow-text-color**) with no contrast
  computation of its own; whether a given theme's caret color meets a
  minimum contrast ratio against the terminal background requires
  inspecting the theme/palette values actually passed in at the call
  site, outside this source.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| themed-terminal-view-003 | caret-appearance-property | Construct the view and read the appearance property before setting it. | the appearance's color and text color are both white; its always-hollow and marks-active-pane flags are both `false`. |
| themed-terminal-view-004 | appearance-change-recompute | View with the default appearance; set the always-hollow flag to `true`. | the caret color becomes fully transparent and the caret subview's layer border width becomes `1`, without any other call. |
| themed-terminal-view-005 | window-attach-recompute | View constructed with the always-hollow flag `true`, not yet attached to a window; attach it to a window. | once attached, the caret color is fully transparent and the caret subview's border width is `1`. |
| themed-terminal-view-006 | active-pane-subscription | Construct the view, attach it to a window, then immediately post the active-pane tracker's change notification naming that window, with no other intervening call. | the caret's color/border are recomputed in response, showing the subscription was already active right after construction. |
| themed-terminal-view-007 | active-pane-notification-window-filter | View is in window A; post the active-pane tracker's change notification naming window B. | the view's caret color/border are unchanged. |
| themed-terminal-view-008 | active-pane-notification-window-filter | View is in window A; post the active-pane tracker's change notification naming window A. | the caret is recomputed and its color/border reflect the current appearance/active-pane state. |
| themed-terminal-view-009 | cursor-shown-outline-reapply | The appearance's marks-active-pane flag is `true` and always-hollow is `false`; the view is currently the active pane (filled: border width `0`). Without changing the appearance, another pane in the same window becomes active (so the view would now be outside the active pane), but no change notification reaches this view's window; then signal that the cursor is shown. | the caret subview's border width stays `0` and the caret color stays the appearance's own color — the stale computed state from before the pane change, not a freshly recomputed one. |
| themed-terminal-view-010 | cursor-style-change-outline-reapply | The appearance's marks-active-pane flag is `true` and always-hollow is `false`; the view is currently NOT the active pane (hollow: border width `1`). Without changing the appearance, this view's pane becomes active (so the view would now be within the active pane), but no change notification reaches this view; then signal a cursor-style change, with any style. | the caret subview's border width stays `1` in the appearance's own color regardless of the new style — the stale hollow state persists. |
| themed-terminal-view-011 | always-hollow-flag | The always-hollow flag is `true`, the marks-active-pane flag is `true`, the view is in the active pane. | the caret is hollow. |
| themed-terminal-view-012 | active-pane-marking | The always-hollow flag is `false`, the marks-active-pane flag is `true`, and the view is not within the active pane. | the caret is hollow. |
| themed-terminal-view-013 | active-pane-marking | The always-hollow flag is `false`, the marks-active-pane flag is `true`, and the view is within the active pane. | the caret is filled. |
| themed-terminal-view-014 | default-fill | The always-hollow flag is `false`, the marks-active-pane flag is `false`, the view is not inside any composable-tabs pane. | the caret is filled. |
| themed-terminal-view-015 | hollow-caret-color | The caret is computed as hollow. | the caret color is fully transparent. |
| themed-terminal-view-016 | filled-caret-color | The caret is computed as filled, with the appearance's color set to a particular blue. | the caret color equals that blue. |
| themed-terminal-view-017 | hollow-text-color | The caret is computed as hollow, with the appearance's text color set to black. | the caret text color equals black. |
| themed-terminal-view-018 | filled-text-color | The caret is computed as filled. | the caret text color is unset. |
| themed-terminal-view-019 | hollow-border | The caret is computed as hollow, the caret subview is present, the appearance's color is a particular blue. | the caret subview's layer border width is `1`, and its border color equals that blue. |
| themed-terminal-view-020 | filled-border | The caret is computed as filled, the caret subview is present. | the caret subview's layer border width is `0`, and it has no border color. |
| themed-terminal-view-021 | missing-caret-subview-tolerance | No subview whose type name ends in `"CaretView"` exists (for example, the border is applied before the terminal engine adds its caret). | no exception is thrown; no layer property is modified. |
| themed-terminal-view-022 | caret-subview-type-name-match | Add a subview whose dynamic type name is `"XTermCaretView"`. | the caret-subview lookup resolves to that subview. |
| themed-terminal-view-023 | caret-subview-cache | The caret subview is resolved once; the resolved subview is removed and replaced by a new subview of a matching type name. | a subsequent lookup re-searches and returns the new subview rather than the stale (now-detached) one. |

`main-thread-confinement` has no row here: it is a compile-time
guarantee, verified by the language's own isolation checking, not by a
runtime conformance vector (see Design Decisions).

## Edge Cases

- **Null/empty input**: The appearance defaults to a white color/white
  text with both flags `false` when the caller never sets it, resolving
  to a filled caret (see **default-fill**). This is the well-defined
  default, not an error condition.
- **Boundary values**: Not applicable — the only caller-supplied inputs
  are two colors and two boolean flags, none of which have a numeric
  range; the one numeric constant in the file, the outline width (`1`
  point), is fixed and not caller-configurable.
- **Concurrent access**: Not applicable — the component is confined to
  the UI's main execution context, so every mutation path (the
  appearance property's change handler, the notification subscription,
  and the cursor-shown/cursor-style-changed overrides) is confined there
  (see **main-thread-confinement**).
- **Error states**: WHEN the active-pane tracker's change notification
  does not name a window (including no window at all), the component
  MUST silently ignore the notification and take no action, per the
  type-checked guard in the subscription handler. There is no other
  error-producing dependency (no network, database, or file-system
  access) in this file, so Cookbook Compliance's networking/error-handling
  requirements are Not applicable here.
- **Offline/disconnected state**: Not applicable — the component performs
  no networking; its only external interaction is a local notification
  publisher and view-hierarchy calls.
- **Caret subview not yet present**: The border-application step's guard
  against a missing caret subview makes border application a silent
  no-op rather than a crash (see **missing-caret-subview-tolerance**).
- **Caret subview rebuilt by the terminal engine**: WHEN the cached weak
  subview reference's superview is no longer this view, the component
  re-searches rather than reuses the stale reference (see
  **caret-subview-cache**).
- **View not yet embedded in any composable-tabs pane while the
  marks-active-pane flag is `true`**: the caret stays filled regardless
  of the marks-active-pane flag — only the always-hollow flag can force
  it hollow outside composable-tabs context — because
  `agentictoolkit://cookbook/ui/layout/composable-tabs/active-pane#requirements/view-outside-any-pane-counts-as-active`
  treats such a view as always "in the active pane."
- **Multiple instances across different windows**: each instance ignores
  a change notification whose named window does not match its own
  window, so a pane-activation change in one window never repaints a
  caret in another (see **active-pane-notification-window-filter**).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| appearance | an appearance value | white color, white text, both flags `false` | The value the caller sets to drive the caret's fill/outline decision; setting it re-evaluates and re-applies the caret's appearance. |
| appearance's caret color | a color | white | The caret's own color — its fill when filled, its outline when hollow. |
| appearance's text color | a color | white | The glyph color under a hollow caret, so the character under the outline reads as ordinary text. |
| appearance's always-hollow flag | a boolean | `false` | Forces the caret hollow unconditionally, regardless of the marks-active-pane flag or the active-pane state. |
| appearance's marks-active-pane flag | a boolean | `false` | When `true` (and the always-hollow flag is `false`), hollows the caret whenever this view is not inside the pane the active-pane tracker currently treats as active. |

## Deep Linking

Not applicable: this view is a caret-rendering decorator on an existing
terminal view with no navigable route, screen, or resource identity of
its own — no URL scheme or routing code appears in source.

## Localization

Not applicable: the source contains no string literals passed to any
user-facing text API; every value it manipulates is a color, a boolean,
or a view reference.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the caret's border-width/border-color and caret-color/caret-text-color changes are instantaneous property assignments with no animation, transition, or movement code in source. |
| Increase Contrast | Not applicable from within this file: this view performs no color computation of its own — the caret color/text color are applied verbatim from whatever the caller supplies (see the open question on contrast-ratio under Accessibility). |
| Differentiate Without Color | Supported: the active-pane indication conveyed by the marks-active-pane flag is the caret's *shape* — filled block versus hollow outline — not its color alone, per source: "A full block, which also says which pane the user is working in: filled here, an outline in every other pane." |

## Feature Flags

Not applicable: the source contains no feature-flag check; this view
always evaluates and applies its caret appearance unconditionally.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

- **Data collected**: None of its own — this view holds only the
  appearance value (two colors, two booleans) and a weak view reference
  in memory. The terminal session's actual command/output content is
  entirely the underlying terminal engine's responsibility, outside this
  file.
- **Storage**: N/A — no persistence call appears in source; state lives
  only in memory for the view's lifetime.
- **Transmission**: N/A — this view performs no network or IPC calls.
- **Retention**: N/A — nothing is retained beyond the view's lifetime.

## Logging

Not applicable: the source contains no logging calls.

## Platform Notes

- **SwiftUI**: There is no SwiftUI-native terminal emulator equivalent to
  `LocalProcessTerminalView`; wrap it (or another terminal engine) in an
  `NSViewRepresentable`, exposing `CaretAppearance` as a `Binding` the
  representable's `updateNSView(_:context:)` writes into the wrapped
  `ThemedTerminalView`'s `caretAppearance` property on every SwiftUI
  update, rather than re-deriving the hollow/filled decision in SwiftUI
  itself.
- **Compose**: Wrap an Android terminal-emulation view (there is no
  Jetpack Compose-native equivalent) in an `AndroidView`, and reproduce
  the caret decision as a small `Drawable`/custom `View` overlay whose
  stroke is toggled on/off the same way this file toggles
  `layer.borderWidth`; drive it from a `mutableStateOf<CaretAppearance>`
  the same way `caretAppearance`'s `didSet` drives `updateCaret()`.
- **React/Web**: xterm.js exposes `cursorStyle: 'block' | 'underline' |
  'bar'` and theme colors (`cursor`, `cursorAccent`) but no built-in
  hollow-block style either; reproduce the outline by setting the cursor
  cell's CSS to a transparent background with a `1px solid`
  outline/border color, toggled by the same
  `isAlwaysHollow`/`marksActivePane`-equivalent booleans, and drive
  `cursorAccent` the way this file drives `caretTextColor`.
- **AppKit / UIKit (source)**: `ThemedTerminalView.swift` is macOS-only
  (`import AppKit`); there is no UIKit counterpart in this file. It
  subclasses SwiftTerm's `LocalProcessTerminalView`, is declared
  `internal` specifically to avoid an Objective-C header conflict with
  the Swift-only `SwiftTerm` module, locates SwiftTerm's private caret
  subview by matching its runtime type name's `"CaretView"` suffix (with
  a weak, superview-validated cache), and separates "recompute the
  hollow/filled decision" (`updateCaret()`, run on appearance/window/notification
  changes) from "just repaint the border" (`applyOutline()`, run on
  every SwiftTerm cursor callback) to avoid rewriting SwiftTerm's caret
  color properties on every cursor movement. The class itself is
  declared `@MainActor`, confining every property and method to the main
  actor, and overrides `init?(coder:)` to `fatalError`, since it is
  never constructed from a storyboard or nib.
- **WinUI 3**: If hosting a real terminal buffer,
  `Microsoft.Terminal.Control.TermControl` (from the Windows Terminal
  control package) is understood to expose some cursor-styling options
  through its settings, but this recipe has no cited source confirming
  whether it offers anything like a hollow-outline style, so treat that
  specific claim as unverified. Independent of what `TermControl` offers
  natively, the same border-overlay technique used here can be
  reproduced generically: track the active cell's caret with a `Border`
  element layered over the terminal surface, and toggle between a filled
  state (`Border.Background` set to the caret color, `BorderThickness="0"`)
  and a hollow state (`Border.Background` set to `Transparent`,
  `BorderThickness="1"`, `BorderBrush` set to the caret color) through a
  `VisualStateManager` `VisualState`, mirroring this file's
  `borderWidth`/`borderColor` toggle. Use a shared static event (or
  `WeakEventManager`) as the WinUI analog of
  `NotificationCenter.default.publisher(for: ComposableTabsActivePane.didChangeNotification)`
  for broadcasting an active-pane change to every terminal control that
  needs to repaint its caret — this class has no key-window handling of
  its own to draw an analogy from.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/TerminalSession/ThemedTerminalView.swift` |

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

**Decision**: `main-thread-confinement` has no runtime conformance vector; it is verified by the Swift compiler's `@MainActor` isolation checking at compile time.
**Rationale**: A MUST requirement enforced entirely by the type system needs no runtime test to demonstrate — violating it is a compile error, not an outcome a test vector could observe.
**Approved**: pending

**Decision**: `ThemedTerminalView` relies on `ComposableTabsActivePane.isInActivePane` treating a view with no `ComposableTabsPaneBackgroundView` ancestor as "in the active pane" (see `agentictoolkit://cookbook/ui/layout/composable-tabs/active-pane#requirements/view-outside-any-pane-counts-as-active`), so `marksActivePane` never hollows such a caret.
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

`platform-theming` fails because `CaretAppearance.color` and `CaretAppearance.textColor` default to the literal `NSColor.white` rather than a semantic, theme-aware color token, so the caret's own defaults do not adapt to the app's theme (see the corresponding Design Decision). `contrast-ratio` is `partial`: the caret's colors are applied verbatim from caller input with no contrast computation in this file, so conformance depends entirely on what the caller supplies — see the open question on contrast-ratio under Accessibility. `keyboard-navigable` and `screen-reader-support` are `partial`: `ThemedTerminalView` adds no keyboard handling, role, or label of its own and overrides none of `LocalProcessTerminalView`'s, but this file gives no evidence of what `LocalProcessTerminalView` itself provides for either, so full conformance cannot be confirmed from this source alone.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed requirements to subject-only names and fragment-form cross-references, replaced the unfounded HIG reference with cited SwiftTerm sources, softened the unsourced WinUI 3 TermControl claim and dropped its false key-window analogy, folded the composable-tabs edge case and design decision into a single dependency citation, rewrote the Compliance table to real catalog checks (`platform-theming` in place of `no-raw-hex`, dropped `main-actor-confined`/`differentiate-without-color`, `keyboard-navigable`/`screen-reader-support` marked `partial`), reworded the `NSColor.white` design decision as an unexamined default rather than unexplained "technical debt", demoted `caret-subview-cache` to SHOULD, rewrote the private-state test vectors in observable terms, moved the compile-time vector out of the conformance table, and removed trailing "MUST." noise from edge cases |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/terminal/. |
