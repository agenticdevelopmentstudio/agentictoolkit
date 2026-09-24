---
id: f8e734aa-f401-4218-9f1e-56ed98c28d3d
title: Button View
domain: agentictoolkit://recipes/button-view
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AppKit NSView wrapping a single NSButton for a settings row, with three Auto
  Layout placements (fill, leading, centered) and an optional press callback.
platforms:
- swift
- macos
tags:
- ui
- button
- macos
- settings
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# Button View

## Overview

`ButtonView` is an AppKit `NSView` from the ComposableSettingsWindow system integration (`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ButtonView.swift`) that wraps a single `NSButton` as one settings row and conforms to `SettingsViewProtocol`. Its title and the action performed on press are both driven entirely by a caller-supplied `ButtonViewModel`, not configured on the view itself. A nested `Placement` enum controls how the button sits in the row it is given: stretched across the whole row (`.fill`, the default), sized to its own title at the row's leading edge (`.leading`), or sized to its own title and centered in the row (`.centered`).

`ButtonViewModel` (`ComposableSettingsWindow/ViewModels/ButtonViewModel.swift`) is a `class` subclassing `AbstractViewModel`. It exposes `title: String` (immutable — declared `let` on `AbstractViewModel`) and `wasPressedCallback: (() -> Void)?` (mutable, `internal`, default `nil`); `AbstractViewModel` also carries `explanation: String?` (immutable), which `ButtonView` never reads.

## Behavioral Requirements

- **creates-button-with-viewmodel-title**: The component MUST initialize its `button` property as an `NSButton` whose title is `viewModel.title`, with no target or action set at creation time.
- **reads-title-once-at-init**: The component MUST read `viewModel.title` only once, at initialization, to construct `button`'s title; it never re-reads `viewModel.title` afterward. `ButtonViewModel.title` (inherited from `AbstractViewModel`) is declared `let`, so there is no later point at which a changed value could exist to re-read.
- **retains-view-model-strongly**: The component MUST hold `viewModel` as a strong reference (`private let viewModel: ButtonViewModel`) for its own lifetime, keeping `viewModel` — and any closure it holds, including `wasPressedCallback` — alive at least as long as the view itself.
- **exposes-button-publicly**: The component MUST expose the underlying `NSButton` as a public, read-only `button` property.
- **disables-autoresizing-mask-translation**: The component MUST set `translatesAutoresizingMaskIntoConstraints = false` on both itself and `button`.
- **adds-button-as-subview**: The component MUST add `button` as a subview of itself.
- **defaults-placement-to-fill**: The component MUST default its `placement` initializer parameter to `.fill` when the caller supplies none.
- **placement-fixed-at-init**: The component MUST fix `placement`'s effect on `button`'s constraints at initialization; it exposes no property or method to change `placement`, or to re-run the placement logic, after construction.
- **fills-view-in-fill-placement**: WHEN `placement` is `.fill`, the component MUST pin all four edges of `button` to the corresponding edges of the view, so `button` occupies the view's full bounds.
- **constrains-vertical-edges-in-non-fill-placement**: WHEN `placement` is `.leading` or `.centered`, the component MUST constrain `button`'s top and bottom edges to equal the view's top and bottom edges.
- **caps-trailing-edge-in-non-fill-placement**: WHEN `placement` is `.leading` or `.centered`, the component MUST constrain `button`'s trailing edge to be less than or equal to the view's trailing edge, so `button` never extends past the view.
- **aligns-leading-edge-in-leading-placement**: WHEN `placement` is `.leading`, the component MUST constrain `button`'s leading edge to equal the view's leading edge.
- **floors-leading-edge-in-centered-placement**: WHEN `placement` is `.centered`, the component MUST constrain `button`'s leading edge to be greater than or equal to the view's leading edge.
- **centers-button-in-centered-placement**: WHEN `placement` is `.centered`, the component MUST constrain `button`'s horizontal center to equal the view's horizontal center.
- **wires-button-action**: The component MUST set `button.target` to itself and `button.action` to its `buttonWasPressed(_:)` selector.
- **invokes-pressed-callback**: WHEN `button` is pressed AND `viewModel.wasPressedCallback` is non-nil, the component MUST invoke `viewModel.wasPressedCallback`.
- **takes-no-action-without-callback**: WHEN `button` is pressed AND `viewModel.wasPressedCallback` is nil, the component MUST NOT perform any action beyond `button`'s own native press feedback.
- **rejects-frame-initializer**: The component MUST fatal-error if constructed through the inherited `NSView.init(frame:)` initializer.
- **rejects-coder-initializer**: The component MUST fatal-error if constructed through `init?(coder:)`.
- **confines-to-main-actor**: The component MUST be usable only on the main actor; the class is declared `@MainActor`.

## Appearance

- **Corner radius**: Not set by `ButtonView`; governed entirely by `NSButton`'s default bezel style — no `bezelStyle`, `isBordered`, or layer customization appears in source.
- **Padding**: Not set; `ButtonView` applies no internal padding around `button`. Any inset between the button's content and its own edge is `NSButton`'s unmodified default.
- **Font**: Not set; `button.font` is never assigned, so `NSButton(title:target:action:)`'s default control font applies.
- **Background**: Not set; `ButtonView` performs no drawing or layer coloring of its own.
- **Foreground/Text**: Not set; no `attributedTitle` or `contentTintColor` customization appears in source, so `NSButton`'s default title color applies.
- **Border**: Not set; no border or bezel customization appears in source.
- **Shadow**: Not set; no shadow customization appears in source.
- **Min/Max size**: Not set via explicit width/height constraints. In `.fill`, `button`'s size equals the view's bounds (via `pinToEdges`). In `.leading`/`.centered`, `button`'s height equals the view's height (top and bottom pinned); its width is bounded by the trailing cap (and, for `.centered`, the leading floor) but not fixed — the final width is `button`'s own intrinsic content size for its title, constrained not to exceed the view.

## States

| State | Appearance change |
|-------|------------------|
| Default | `button` displays `viewModel.title` in `NSButton`'s default bezel style; no custom styling from `ButtonView`. |
| Pressed | Not styled by `ButtonView`; any pressed visual is `NSButton`'s own native bezel press feedback. |
| Disabled | Not implemented in `ButtonView`; the source never reads or sets `button.isEnabled`. A caller may set it directly through the public `button` property, at which point `NSButton`'s native disabled dimming applies. |
| Focused | Not styled by `ButtonView`; any focus ring is `NSButton`'s own native focus appearance. |
| Loading | Not applicable: `ButtonView` performs no asynchronous work of its own and defines no loading state. |

## Accessibility

- **Role**: `button`, inherited from `NSButton`; `ButtonView` sets no custom accessibility role.
- **Label**: The accessible name is `button`'s title, set from `viewModel.title` at construction (see **creates-button-with-viewmodel-title**); `ButtonView` sets no separate accessibility label.
- **Announce state changes**: Not applicable: `ButtonView` defines no disabled or loading state of its own (see States); if a caller disables `button` directly, the enabled/disabled announcement is `NSButton`'s native behavior, not something `ButtonView` implements.
- **Keyboard navigation**: Inherited from `NSButton` — Tab/Shift-Tab move focus onto and off the button, and Space or Return activates it through the target/action wired in **wires-button-action**. `ButtonView` adds no custom key handling.
- **Minimum tap target**: `ButtonView` keeps AppKit's system metrics for `button` — no `controlSize`, width or height override — so the click target is the regular-size push-button bezel sized to its title, as the macOS Human Interface Guidelines prescribe for pointer-driven controls. A port to touch platforms would need to give the equivalent control at least the platform minimum (44×44 pt on iOS, 48×48 dp on Android, 40×40 epx on WinUI 3); this is porting guidance, not a behavior of the AppKit source.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| button-view-001 | creates-button-with-viewmodel-title | `ButtonViewModel(title: "Save")` | `button.title == "Save"` |
| button-view-002 | creates-button-with-viewmodel-title | `ButtonViewModel(title: "")` | `button.title == ""`; no crash |
| button-view-003 | exposes-button-publicly | Any initialized `ButtonView` | `view.button` is externally accessible and is the same `NSButton` instance added as its subview |
| button-view-004 | disables-autoresizing-mask-translation | Any initialized `ButtonView` | `view.translatesAutoresizingMaskIntoConstraints == false` and `view.button.translatesAutoresizingMaskIntoConstraints == false` |
| button-view-005 | adds-button-as-subview | Any initialized `ButtonView` | `view.subviews` contains `view.button` |
| button-view-006 | defaults-placement-to-fill | `ButtonView(viewModel: vm)` with no `placement` argument | Resulting layout matches the `.fill` behavior in button-view-007 |
| button-view-007 | fills-view-in-fill-placement | `placement: .fill`, host view laid out at 200×40 | `button`'s frame equals (0, 0, 200, 40) |
| button-view-008 | constrains-vertical-edges-in-non-fill-placement | `placement: .leading`, host view laid out at 200×40 | `button`'s top and bottom edges equal the host view's top and bottom edges (button height == 40) |
| button-view-009 | caps-trailing-edge-in-non-fill-placement | `placement: .leading`, `viewModel.title`'s intrinsic width exceeds the host view's width | `button`'s trailing edge does not exceed the host view's trailing edge |
| button-view-010 | aligns-leading-edge-in-leading-placement | `placement: .leading` | `button`'s leading edge equals the host view's leading edge |
| button-view-011 | floors-leading-edge-in-centered-placement | `placement: .centered`, host view wider than `button`'s intrinsic width | `button`'s leading edge is greater than or equal to the host view's leading edge |
| button-view-012 | centers-button-in-centered-placement | `placement: .centered`, host view laid out at 200×40 | `button`'s horizontal center equals the host view's horizontal center (x == 100) |
| button-view-013 | wires-button-action | Any initialized `ButtonView` | `button.target === view`; `button.action == Selector("buttonWasPressed:")` |
| button-view-014 | invokes-pressed-callback | `viewModel.wasPressedCallback` set to a closure that flips a flag; simulate a click on `button` | The flag is `true` after the click |
| button-view-015 | takes-no-action-without-callback | `viewModel.wasPressedCallback == nil`; simulate a click on `button` | No exception is thrown; `button.target` and `button.action` are unchanged from **wires-button-action**; no call is observed on a spy substituted for any other collaborator |
| button-view-016 | rejects-frame-initializer | Construct via `ButtonView(frame: .zero)` | Execution traps via `fatalError` with message `init(frame frameRect: NSRect` |
| button-view-017 | rejects-coder-initializer | Construct via `ButtonView(coder:)` with any `NSCoder` | Execution traps via `fatalError` with message `init(coder:) has not been implemented` |
| button-view-018 | confines-to-main-actor | Attempt to construct or mutate a `ButtonView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| button-view-019 | placement-fixed-at-init | Any initialized `ButtonView` | `ButtonView`'s public interface exposes no property or method that reads or changes `placement`; the only code that consults `placement` runs once, inside `init` |
| button-view-020 | reads-title-once-at-init | Any initialized `ButtonView` | `button.title` was set from `viewModel.title` during `init` and by no other code path; `ButtonViewModel.title` is `let`, so no later value could exist for the component to re-read |
| button-view-021 | retains-view-model-strongly | Construct `let view = ButtonView(viewModel: ButtonViewModel(title: "Save") { flag = true })` in a scope where no other strong reference to the view model is kept; after the scope exits (only `view` remains reachable), simulate a click on `view.button` | The callback still fires and `flag` becomes `true`, showing `view` alone kept `viewModel` (and its closure) alive after every other reference was dropped |

`button-view-018` and `button-view-019` are static, code-inspection checks
(Swift's `@MainActor` isolation checking rejects an off-actor call at compile
time; `placement` having no reachable getter/setter is a fact about the
type's public interface), not vectors observed by running the program; a
port on a platform without the equivalent compile-time enforcement should
verify these as build-verification or API-surface review notes rather than
runtime tests.

## Edge Cases

- **Null/empty input**: `viewModel.title` as an empty string produces a `button` with an empty title and no crash (see button-view-002). `viewModel.wasPressedCallback` as `nil` is the default, documented case (see **takes-no-action-without-callback**).
- **Boundary values**: Not applicable — the only enumerated input, `Placement`, is a closed three-case enum with no numeric range, so there is no minimum/maximum boundary to exercise.
- **Concurrent access**: Not applicable — the class is declared `@MainActor`, so all construction and mutation is serialized to the main actor by the compiler (see **confines-to-main-actor**).
- **Error states**: Not applicable — `ButtonView` has no dependency on network, database, or file-system access. Its only external interaction is invoking `viewModel.wasPressedCallback`, whose error handling, if any, is the caller's responsibility inside that closure, not something `ButtonView` observes or handles.
- **Offline/disconnected state**: Not applicable — `ButtonView` performs no networking.
- **Very long title**: `ButtonView` sets no line-break or truncation mode on `button`; if `viewModel.title` is wider than the space the active `placement` leaves available, `NSButton`'s own default single-line truncation behavior applies unmodified by this component.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ButtonViewModel` | (required) | A `class` (subclass of `AbstractViewModel`) supplying `button`'s title (`title: String`, immutable) and the optional `wasPressedCallback: (() -> Void)?` closure invoked when `button` is pressed (mutable, default `nil`). |
| `placement` | `ButtonView.Placement` | `.fill` | Where `button` sits in its row: `.fill` stretches it across the whole row, `.leading` sizes it to its title at the row's leading edge, `.centered` sizes it to its title and centers it in the row. |

## Deep Linking

Not applicable: `ButtonView` is a settings-row control with no navigable identity of its own — it has no route, screen, or resource that a deep link could target.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none) | (none) | `viewModel.title` is supplied entirely by the caller; `ButtonView` defines no string keys or default text of its own. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `ButtonView` applies no animation or transition of its own; any press animation is `NSButton`'s unconditional system-level bezel feedback, which this component neither adds nor could gate. |
| Increase Contrast | Not applicable: `ButtonView` sets no custom colors of its own; all coloring is `NSButton`'s default system appearance, which already tracks the system's Increase Contrast setting. |
| Differentiate Without Color | Not applicable: `ButtonView` conveys no state through color; it defines exactly one visual presentation (the button with its title), and any color-based state such as pressed or disabled is `NSButton`'s own system chrome. |

## Feature Flags

Not applicable: the source contains no feature-flag check; `ButtonView` always constructs and wires `button` unconditionally.

## Analytics

Not applicable: the source emits no analytics events. Pressing `button` only invokes the caller-supplied `wasPressedCallback`; any analytics tracking is the caller's responsibility inside that closure.

## Privacy

- **Data collected**: None. `ButtonView` holds only the `title` string and a closure reference passed in by the caller through `ButtonViewModel`; it collects nothing of its own.
- **Storage**: N/A — no persistence; state lives only in memory for the view's lifetime.
- **Transmission**: N/A — `ButtonView` performs no network or IPC calls.
- **Retention**: N/A — nothing is retained beyond the view's lifetime.

## Logging

Not applicable: the source contains no logging calls.

## Platform Notes

- **SwiftUI**: Replace with `Button(viewModel.title) { viewModel.wasPressedCallback?() }`. Map `.fill` to `.frame(maxWidth: .infinity)` on the button (with a full-width button style so the tap target itself stretches, not just its label); map `.leading` to placing the button first in an `HStack` followed by a `Spacer()`, or `.frame(maxWidth: .infinity, alignment: .leading)`; map `.centered` to `.frame(maxWidth: .infinity, alignment: .center)`. No `fatalError`-guarded initializer is needed — SwiftUI views have no counterpart to `init(frame:)`/`init?(coder:)`.
- **Compose**: Replace with `Button(onClick = { viewModel.wasPressedCallback?.invoke() }) { Text(viewModel.title) }`. Map `.fill` to `Modifier.fillMaxWidth()` on the `Button`; map `.leading` to `Modifier.fillMaxWidth().wrapContentWidth(Alignment.Start)` on the `Button` inside a `Row`, so the button occupies the row's width but sizes and aligns its own tap target to its label at the start (mirroring the trailing-capped, leading-pinned constraints); map `.centered` to `Modifier.align(Alignment.CenterHorizontally)` in a `Column`, or `Arrangement.Center` in a `Row`.
- **React/Web**: Replace with `<button onClick={() => viewModel.wasPressedCallback?.()}>{viewModel.title}</button>`. Map `.fill` to `width: 100%` (or `display: block`) on the button; map `.leading` to `justify-content: flex-start` on a flex row containing the button; map `.centered` to `justify-content: center` on that row, or `margin-inline: auto` on the button itself.
- **AppKit / UIKit (source)**: `ButtonView.swift` is macOS-only (`import AppKit`) — there is no iOS/UIKit counterpart in this file. It is an `NSView` wrapping one `NSButton`, computing its three Auto Layout placements once at `init` time (placement cannot change after construction), with `init(frame:)` and `init?(coder:)` fatal-erroring rather than being usable, and the whole type isolated to `@MainActor`. A UIKit port to `UIView`/`UIButton` would need to add the enabled/highlighted/selected state handling that `NSButton`'s bezel already provides on macOS but `UIButton` requires more explicit configuration for.
- **WinUI 3**: Use a `Button` control with `Content` bound to `viewModel.Title` and `Click` wired to the equivalent of `buttonWasPressed`. Map `.fill` to `HorizontalAlignment="Stretch"` with `HorizontalContentAlignment="Stretch"`, placed in the row's `Grid` cell so it spans the row's width (mirroring `pinToEdges`); map `.leading` to `HorizontalAlignment="Left"` in that same cell (mirroring the top/bottom-pinned, trailing-capped constraints); map `.centered` to `HorizontalAlignment="Center"` (mirroring the leading-floored, center-x-pinned constraints). WinUI has no `fatalError`-style initializer guard, so enforce "always construct with a view model" through a required constructor parameter or a `required` property instead of a runtime crash on an unused inherited initializer. `Button`'s built-in `CommonStates` (`Normal`, `PointerOver`, `Pressed`, `Disabled`) via `VisualStateManager` already cover pressed/disabled visuals without custom state XAML, matching the source's own lack of custom pressed/disabled styling.

## Design Decisions

**Decision**: `.fill` is the default value of the `placement` parameter.
**Rationale**: Per the source's own doc comment, the default is `.fill` "because that is what every caller before this parameter got, and a settings row that silently changed shape would be a worse surprise than a verbose call site."
**Approved**: pending

**Decision**: The `.leading` and `.centered` placements bound `button`'s trailing edge (and, for `.centered`, its leading edge) with inequality constraints rather than pinning them exactly.
**Rationale**: Per the source's own comments: the trailing constraint is "less-than, not equal: the row is as wide as the card, and an equal trailing edge is the stretch `.fill` is for," and the `.centered` leading constraint is "greater-than... for the same reason as the trailing one; the centre anchor does the placing."
**Approved**: pending

**Decision**: `init(frame:)` and `init?(coder:)` are overridden only to call `fatalError`, rather than being omitted.
**Rationale**: `ButtonView` has no valid state without a `ButtonViewModel`. Blocking the two inherited `NSView` initializers this way means a caller who reaches them through generic `NSView`-typed construction code (e.g. Interface Builder decoding) crashes immediately with a diagnosable message, instead of silently producing a `ButtonView` with no view model.
**Approved**: pending

**Decision**: This recipe calls `ButtonView`'s container a "row" throughout, even though the source's own comments use both "row" (in the `Placement` doc comment: "where the button sits in the row it is given") and "card" (in the `.fill` and `.leading` case comments: "stretched across the whole card"; "the row is as wide as the card").
**Rationale**: The two words refer to the same concept in this file; "row" is kept as the single term for consistency with how a `SettingsViewProtocol` view's container is described elsewhere in the cookbook — `agentictoolkit://recipes/header-view` and `agentictoolkit://recipes/horizontal-stack-view` both describe `SettingsViewProtocol` as "the marker protocol every settings-row view in this system adopts" — and the source's own inconsistency is recorded here rather than silently smoothed over.
**Approved**: pending

**Decision**: This recipe describes `Self.pinToEdges(button, of: self)` (used in **fills-view-in-fill-placement**) as pinning all four edges of `button` to the corresponding edges of `self`.
**Rationale**: `pinToEdges` is not defined in `ButtonView.swift`, but its implementation was read directly: `static func pinToEdges(_ view: NSView, of container: NSView)` in `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/ViewLayout.swift` activates exactly four equal constraints — `view`'s top, leading, trailing, and bottom anchors to `container`'s corresponding anchors — confirming the `.fill` case comment ("Stretched across the whole card") describes the same behavior this recipe asserts.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | passed | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | failed | Accessibility |
| [touch-target-size](agenticdevelopercookbook://compliance/accessibility#touch-target-size) | passed | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | passed | Internationalization |

The `passed` statuses rest on `ButtonView` using an unmodified `NSButton` for its role, label, keyboard handling, and system-chrome contrast, and on `ButtonView` defining no string literals of its own. `dynamic-type-support` is `failed` because `button.font` is never set to a text-style-based font (e.g. `NSFont.preferredFont(forTextStyle:)`), so its title does not scale with the system text-size setting. `touch-target-size` is `passed` on macOS: the button keeps the system control metrics (see **Minimum tap target** under Accessibility).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: verified the `.fill`-placement `pinToEdges` behavior against its actual source and cited it; grounded the "row" vs "card" wording in sibling recipes; added named requirements and test vectors for title-read timing, view-model retention, and placement immutability; reworded the touch-target porting guidance to drop its RFC 2119 keyword; defined `ButtonViewModel`'s shape; tightened test vectors 015 and 018 and marked 018/019 as static checks; and made the Compose `.leading` mapping concrete. |
