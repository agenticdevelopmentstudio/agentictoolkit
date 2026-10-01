---
id: f8e734aa-f401-4218-9f1e-56ed98c28d3d
title: Button View
domain: agentictoolkit://cookbook/ui/settings/rows/button-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings-row control wrapping a single button, with three placements
  (fill, leading, centered) and an optional press callback.
platforms:
- swift
- macos
tags:
- ui
- button
- settings
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# Button View

## Overview

The Button View is a settings-row control that wraps a single button. Its
title and the action performed on press are both driven entirely by a
caller-supplied view model, not configured on the component itself. It
fulfills the same settings-row-view contract as its siblings in this
system. A placement option controls how the button sits in the row it is
given: stretched across the whole row (fill, the default), sized to its
own title at the row's leading edge (leading), or sized to its own title
and centered in the row (centered).

The view model exposes a `title` (immutable) and an optional
`wasPressedCallback` (mutable, default none) invoked when the button is
pressed; it also carries an `explanation` field common to every view model
in this family, which this component never reads.

## Behavioral Requirements

- **creates-button-with-view-model-title**: The component MUST initialize
  its button with a title equal to the view model's `title`, with no press
  action wired yet at creation time.
- **reads-title-once-at-init**: The component MUST read the view model's
  `title` only once, at initialization, to set the button's title; it
  never re-reads `title` afterward. The view model's `title` is immutable,
  so there is no later point at which a changed value could exist to
  re-read.
- **retains-view-model-strongly**: The component MUST hold a strong
  reference to its view model for its own lifetime, keeping the view model
  — and any callback it holds, including `wasPressedCallback` — alive at
  least as long as the component itself.
- **exposes-button-publicly**: The component MUST expose the underlying
  button as a public, read-only property.
- **defaults-placement-to-fill**: The component MUST default its placement
  parameter to fill when the caller supplies none.
- **placement-fixed-at-init**: The component MUST fix placement's effect
  on the button's position at initialization; it exposes no property or
  method to change placement, or to re-run the placement logic, after
  construction.
- **fills-view-in-fill-placement**: WHEN placement is fill, the component
  MUST pin all four edges of the button to the corresponding edges of the
  component, so the button occupies the component's full bounds (see
  Platform Notes for the mechanics the source uses).
- **constrains-vertical-edges-in-non-fill-placement**: WHEN placement is
  leading or centered, the component MUST constrain the button's top and
  bottom edges to equal the component's top and bottom edges.
- **caps-trailing-edge-in-non-fill-placement**: WHEN placement is leading
  or centered, the component MUST constrain the button's trailing edge to
  be less than or equal to the component's trailing edge, so the button
  never extends past the component.
- **aligns-leading-edge-in-leading-placement**: WHEN placement is leading,
  the component MUST constrain the button's leading edge to equal the
  component's leading edge.
- **floors-leading-edge-in-centered-placement**: WHEN placement is
  centered, the component MUST constrain the button's leading edge to be
  greater than or equal to the component's leading edge.
- **centers-button-in-centered-placement**: WHEN placement is centered,
  the component MUST constrain the button's horizontal center to equal
  the component's horizontal center.
- **wires-button-action**: The component MUST route the button's press
  interaction through its own press-handling logic rather than a callback
  attached directly to the button (see Platform Notes for the mechanism
  the source uses).
- **invokes-pressed-callback**: WHEN the button is pressed AND the view
  model's `wasPressedCallback` is set, the component MUST invoke it.
- **takes-no-action-without-callback**: WHEN the button is pressed AND the
  view model's `wasPressedCallback` is unset, the component MUST NOT
  perform any action beyond the button's own native press feedback.
- **requires-view-model-at-construction**: The component MUST require a
  view model to construct a usable instance; no construction path may
  produce a usable instance without one (see Platform Notes for
  how the source enforces this on this platform).
- **confines-to-ui-thread**: The component MUST be usable only on the UI
  thread.

## Appearance

- **Corner radius**: Not set by the component; governed entirely by the
  button's default bezel style — no custom shape or layer customization
  appears in source.
- **Padding**: Not set; the component applies no internal padding around
  the button. Any inset between the button's content and its own edge is
  the platform button's unmodified default.
- **Font**: Not set; the button's font is never assigned, so the
  platform's default control font applies.
- **Background**: Not set; the component performs no drawing or layer
  coloring of its own.
- **Foreground/Text**: Not set; no custom title-color or tint
  customization appears in source, so the button's default title color
  applies.
- **Border**: Not set; no border or bezel customization appears in
  source.
- **Shadow**: Not set; no shadow customization appears in source.
- **Min/Max size**: Not set via explicit width/height constraints. In
  fill, the button's size equals the component's bounds. In
  leading/centered, the button's height equals the component's height
  (top and bottom pinned); its width is bounded by the trailing cap (and,
  for centered, the leading floor) but not fixed — the final width is the
  button's own intrinsic content size for its title, constrained not to
  exceed the component.

## States

| State | Appearance change |
|-------|------------------|
| Default | The button displays the view model's `title` in the platform's default bezel style; no custom styling from the component. |
| Pressed | Not styled by the component; any pressed visual is the button's own native press feedback. |
| Disabled | Not implemented by the component; the source never reads or sets the button's enabled state. A caller may set it directly through the public button property, at which point the platform button's native disabled dimming applies. |
| Focused | Not styled by the component; any focus ring is the button's own native focus appearance. |
| Loading | Not applicable: the component performs no asynchronous work of its own and defines no loading state. |

## Accessibility

- **Role**: Button, inherited from the platform's native button; the
  component sets no custom accessibility role.
- **Label**: The accessible name is the button's title, set from the view
  model's `title` at construction (see **creates-button-with-view-model-title**);
  the component sets no separate accessibility label.
- **Announce state changes**: Not applicable: the component defines no
  disabled or loading state of its own (see States); if a caller disables
  the button directly, the enabled/disabled announcement is the button's
  native behavior, not something the component implements.
- **Keyboard navigation**: Inherited from the platform's native button —
  Tab/Shift-Tab move focus onto and off the button, and Space or Return
  activate it (see **wires-button-action**). The component adds no custom
  key handling.
- **Minimum tap target**: The component keeps the platform's system
  metrics for the button — no size override of any kind — so the click
  target is the button's regular size, sized to its title (see Platform
  Notes for platform-specific minimum-target guidance).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| button-view-001 | creates-button-with-view-model-title | Construct with a view model whose title is "Save" | The button's title is "Save" |
| button-view-002 | creates-button-with-view-model-title | Construct with a view model whose title is empty | The button's title is empty; no crash |
| button-view-003 | exposes-button-publicly | Any initialized instance | The button is externally accessible, is the same instance the component displays, and is fully contained within the component's layout (not a detached or independently-positioned element; see Platform Notes for the mechanism the source uses) |
| button-view-006 | defaults-placement-to-fill | Construct with no explicit placement | Resulting layout matches the fill behavior in button-view-007 |
| button-view-007 | fills-view-in-fill-placement | Placement is fill, host component laid out at 200×40 | The button's frame equals (0, 0, 200, 40) |
| button-view-008 | constrains-vertical-edges-in-non-fill-placement | Placement is leading, host component laid out at 200×40 | The button's top and bottom edges equal the host's top and bottom edges (button height == 40) |
| button-view-009 | caps-trailing-edge-in-non-fill-placement | Placement is leading, the title's intrinsic width exceeds the host's width | The button's trailing edge does not exceed the host's trailing edge |
| button-view-010 | aligns-leading-edge-in-leading-placement | Placement is leading | The button's leading edge equals the host's leading edge |
| button-view-011 | floors-leading-edge-in-centered-placement | Placement is centered, host wider than the button's intrinsic width | The button's leading edge is greater than or equal to the host's leading edge |
| button-view-012 | centers-button-in-centered-placement | Placement is centered, host component laid out at 200×40 | The button's horizontal center equals the host's horizontal center (x == 100) |
| button-view-013 | wires-button-action | Any initialized instance | The button's press interaction is wired to the component's own press-handling logic, not a callback attached directly on the button (verified as an implementation/code-inspection check; see Platform Notes for the mechanism the source uses) |
| button-view-014 | invokes-pressed-callback | The view model's `wasPressedCallback` set to a callback that flips a flag; simulate a press on the button | The flag is true after the press |
| button-view-015 | takes-no-action-without-callback | The view model's `wasPressedCallback` unset; simulate a press on the button | No exception is thrown; no call is observed on a spy substituted for any other collaborator |
| button-view-016 | requires-view-model-at-construction | Attempt to construct via a bare/default construction path that supplies no view model | Construction is rejected; no usable instance is produced. Not testable as an ordinary in-process assertion on every platform — where the failure mode is a runtime trap rather than a thrown/returned error, this requires a crash-test harness or a compile-time/unavailable check instead. |
| button-view-017 | requires-view-model-at-construction | Attempt to construct via a serialization/decoding-based construction path that supplies no view model | Construction is rejected; no usable instance is produced. Same testing caveat as above. |
| button-view-018 | confines-to-ui-thread | Attempt to construct or mutate the component from off the UI thread | Rejected by the platform's UI-thread confinement enforcement (compile-time on platforms with static isolation checking such as Swift's `@MainActor`, runtime-checked otherwise) |
| button-view-019 | placement-fixed-at-init | Any initialized instance | The component's public interface exposes no property or method that reads or changes placement; the only code that consults placement runs once, during construction |
| button-view-020 | reads-title-once-at-init | Any initialized instance | The button's title was set from the view model's title during construction and by no other code path; the view model's title is immutable, so no later value could exist for the component to re-read |
| button-view-021 | retains-view-model-strongly | Construct the component with a view model carrying a press callback that flips a flag, in a scope where no other strong reference to the view model is kept; after the scope exits (only the component remains reachable), simulate a press on the button | The callback still fires and the flag becomes true, showing the component alone kept the view model (and its callback) alive after every other reference was dropped |

`button-view-013`, `button-view-018` and `button-view-019` are static,
code-inspection checks (the platform's press-wiring mechanism and UI-thread
isolation checking reject a violation at compile time or by construction;
placement having no
reachable getter/setter is a fact about the type's public interface), not
vectors observed by running the program; a port on a platform without the
equivalent compile-time enforcement should verify these as build-verification
or API-surface review notes rather than runtime tests.

## Edge Cases

- **Null/empty input**: The view model's `title` as an empty string produces a button with an empty title and no crash (see button-view-002). The view model's `wasPressedCallback` unset is the default, documented case (see **takes-no-action-without-callback**).
- **Boundary values**: Not applicable — the only enumerated input, placement, is a closed three-option set with no numeric range, so there is no minimum/maximum boundary to exercise.
- **Concurrent access**: Not applicable — the component is confined to the UI thread, so all construction and mutation is serialized to that thread (see **confines-to-ui-thread**).
- **Error states**: Not applicable — the component has no dependency on network, database, or file-system access. Its only external interaction is invoking the view model's `wasPressedCallback`, whose error handling, if any, is the caller's responsibility inside that callback, not something the component observes or handles.
- **Offline/disconnected state**: Not applicable — the component performs no networking.
- **Very long title**: The component sets no line-break or truncation mode on the button; if the title is wider than the space the active placement leaves available, the platform button's own default single-line truncation behavior applies unmodified by this component.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | view model object | (required) | Supplies the button's title (immutable) and the optional `wasPressedCallback` callback invoked when the button is pressed (mutable, default none). |
| `placement` | one of fill / leading / centered | fill | Where the button sits in its row: fill stretches it across the whole row, leading sizes it to its title at the row's leading edge, centered sizes it to its title and centers it in the row. |

## Deep Linking

Not applicable: the component is a settings-row control with no navigable identity of its own — it has no route, screen, or resource that a deep link could target.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none) | (none) | The view model's `title` is supplied entirely by the caller; the component defines no string keys or default text of its own. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the component applies no animation or transition of its own; any press animation is the platform button's unconditional system-level feedback, which this component neither adds nor could gate. |
| Increase Contrast | Not applicable: the component sets no custom colors of its own; all coloring is the platform button's default system appearance, which already tracks the system's Increase Contrast setting. |
| Differentiate Without Color | Not applicable: the component conveys no state through color; it defines exactly one visual presentation (the button with its title), and any color-based state such as pressed or disabled is the platform button's own system chrome. |

## Feature Flags

Not applicable: the source contains no feature-flag check; the component always constructs and wires the button unconditionally.

## Analytics

Not applicable: the source emits no analytics events. Pressing the button only invokes the caller-supplied `wasPressedCallback`; any analytics tracking is the caller's responsibility inside that callback.

## Privacy

- **Data collected**: None. The component holds only the title string and a callback reference passed in by the caller through the view model; it collects nothing of its own.
- **Storage**: N/A — no persistence; state lives only in memory for the component's lifetime.
- **Transmission**: N/A — the component performs no network or IPC calls.
- **Retention**: N/A — nothing is retained beyond the component's lifetime.

## Logging

Not applicable: the source contains no logging calls.

## Platform Notes

- **SwiftUI**: Replace with `Button(viewModel.title) { viewModel.wasPressedCallback?() }`. Map fill to `.frame(maxWidth: .infinity)` on the button (with a full-width button style so the tap target itself stretches, not just its label); map leading to placing the button first in an `HStack` followed by a `Spacer()`, or `.frame(maxWidth: .infinity, alignment: .leading)`; map centered to `.frame(maxWidth: .infinity, alignment: .center)`. No `fatalError`-guarded initializer is needed — SwiftUI views have no counterpart to `init(frame:)`/`init?(coder:)`.
- **Compose**: Replace with `Button(onClick = { viewModel.wasPressedCallback?.invoke() }) { Text(viewModel.title) }`. Map fill to `Modifier.fillMaxWidth()` on the `Button`; map leading to `Modifier.fillMaxWidth().wrapContentWidth(Alignment.Start)` on the `Button` inside a `Row`, so the button occupies the row's width but sizes and aligns its own tap target to its label at the start (mirroring the trailing-capped, leading-pinned constraints); map centered to `Modifier.align(Alignment.CenterHorizontally)` in a `Column`, or `Arrangement.Center` in a `Row`.
- **React/Web**: Replace with `<button onClick={() => viewModel.wasPressedCallback?.()}>{viewModel.title}</button>`. Map fill to `width: 100%` (or `display: block`) on the button; map leading to `justify-content: flex-start` on a flex row containing the button; map centered to `justify-content: center` on that row, or `margin-inline: auto` on the button itself.
- **AppKit / UIKit (source)**: `ButtonView.swift` is macOS-only (`import AppKit`) — there is no iOS/UIKit counterpart in this file. It is an `NSView` wrapping one `NSButton`, added as a subview with `translatesAutoresizingMaskIntoConstraints = false` set on both itself and the button (satisfying **exposes-button-publicly**'s containment), computing its three Auto Layout placements once at `init` time via a shared `pinToEdges` helper (placement cannot change after construction), wiring the button's `target`/`action` to its own `buttonWasPressed(_:)` selector rather than a closure attached to the button directly (satisfying **wires-button-action**), with `init(frame:)` and `init?(coder:)` fatal-erroring rather than being usable (satisfying **requires-view-model-at-construction**), and the whole type isolated to `@MainActor` (satisfying **confines-to-ui-thread**). The AppKit source keeps system control metrics for the button (no `controlSize`, width, or height override), so the click target is the regular-size push-button bezel sized to its title, as the macOS Human Interface Guidelines prescribe for pointer-driven controls. A port to touch platforms would need to give the equivalent control at least the platform minimum (44×44 pt on iOS, 48×48 dp on Android, 40×40 epx on WinUI 3). A UIKit port to `UIView`/`UIButton` would need to add the enabled/highlighted/selected state handling that `NSButton`'s bezel already provides on macOS but `UIButton` requires more explicit configuration for.
- **WinUI 3**: Use a `Button` control with `Content` bound to `viewModel.Title` and `Click` wired to the equivalent of `buttonWasPressed`. Map fill to `HorizontalAlignment="Stretch"` with `HorizontalContentAlignment="Stretch"`, placed in the row's `Grid` cell so it spans the row's width (mirroring `pinToEdges`); map leading to `HorizontalAlignment="Left"` in that same cell (mirroring the top/bottom-pinned, trailing-capped constraints); map centered to `HorizontalAlignment="Center"` (mirroring the leading-floored, center-x-pinned constraints). WinUI has no `fatalError`-style initializer guard, so enforce "always construct with a view model" through a required constructor parameter or a `required` property instead of a runtime crash on an unused inherited initializer. `Button`'s built-in `CommonStates` (`Normal`, `PointerOver`, `Pressed`, `Disabled`) via `VisualStateManager` already cover pressed/disabled visuals without custom state XAML, matching the source's own lack of custom pressed/disabled styling.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ButtonView.swift` |

## Design Decisions

**Decision**: Fill is the default value of the placement parameter.
**Rationale**: Per the source's own doc comment, the default is `.fill` "because that is what every caller before this parameter got, and a settings row that silently changed shape would be a worse surprise than a verbose call site."
**Approved**: pending

**Decision**: The leading and centered placements bound the button's trailing edge (and, for centered, its leading edge) with inequality constraints rather than pinning them exactly.
**Rationale**: Per the source's own comments: the trailing constraint is "less-than, not equal: the row is as wide as the card, and an equal trailing edge is the stretch `.fill` is for," and the `.centered` leading constraint is "greater-than... for the same reason as the trailing one; the centre anchor does the placing."
**Approved**: pending

**Decision** (AppKit): `init(frame:)` and `init?(coder:)` are overridden only to call `fatalError`, rather than being omitted.
**Rationale**: `ButtonView` has no valid state without a `ButtonViewModel`. Blocking the two inherited `NSView` initializers this way means a caller who reaches them through generic `NSView`-typed construction code (e.g. Interface Builder decoding) crashes immediately with a diagnosable message, instead of silently producing a `ButtonView` with no view model.
**Approved**: pending

**Decision**: This recipe calls the component's container a "row" throughout, even though the source's own comments use both "row" (in the `Placement` doc comment: "where the button sits in the row it is given") and "card" (in the `.fill` and `.leading` case comments: "stretched across the whole card"; "the row is as wide as the card").
**Rationale**: The two words refer to the same concept in this file; "row" is kept as the single term for consistency with how a settings-row view's container is described elsewhere in the cookbook — `agentictoolkit://cookbook/ui/settings/layout/header-view` and `agentictoolkit://cookbook/ui/settings/layout/horizontal-stack-view` both describe the settings-row-view contract as "the marker protocol every settings-row view in this system adopts" — and the source's own inconsistency is recorded here rather than silently smoothed over.
**Approved**: pending

**Decision** (AppKit): This recipe describes `Self.pinToEdges(button, of: self)` (used in **fills-view-in-fill-placement**) as pinning all four edges of the button to the corresponding edges of the component.
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
| 1.1.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
