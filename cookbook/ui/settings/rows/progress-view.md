---
id: ea2dae31-1020-4930-aa12-15f7d04967a5
title: Progress View
domain: agentictoolkit://cookbook/ui/settings/rows/progress-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings row wrapping a single progress indicator, switching
  between a determinate bar and an indeterminate animation as its underlying
  value changes.
platforms:
- swift
- macos
tags:
- settings
- status-indicator
- progress
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/rows/checkbox-view
- agentictoolkit://cookbook/ui/settings/rows/button-view
- agentictoolkit://cookbook/ui/settings/layout/explanation-view
references:
- https://developer.apple.com/documentation/appkit/nsprogressindicator
- https://developer.apple.com/documentation/uikit/uiprogressview
- https://learn.microsoft.com/en-us/uwp/api/windows.ui.xaml.controls.progressbar.isindeterminate
- https://developer.mozilla.org/en-US/docs/Web/HTML/Element/progress
approved-by: ''
approved-date: ''
---

# Progress View

## Overview

The Progress View is a settings row wrapping a single progress indicator,
pinned edge-to-edge inside itself. It is driven entirely by a progress view
model: a subscription to the view model's progress value (present or
absent, where absent means indeterminate per the view model's own doc
comment) flips the indicator between a determinate bar showing a numeric
value and an animating indeterminate bar every time that value changes, for
as long as the view exists.

## Behavioral Requirements

- **constructs-progress-indicator-at-regular-control-size**: The component
  MUST initialize the progress indicator at the platform's regular control
  size.
- **exposes-progress-indicator-publicly**: The component MUST expose the
  underlying progress indicator as a public, read-only property.
- **uses-constraint-based-layout**: The component MUST be positioned using
  layout constraints, not a legacy frame-based resizing mechanism, for both
  itself and the progress indicator (see Platform Notes for the exact
  mechanism).
- **adds-progress-indicator-as-subview**: The component MUST add the
  progress indicator as a child view of itself.
- **pins-progress-indicator-to-edges**: The component MUST pin the progress
  indicator's top, leading, trailing, and bottom edges to the corresponding
  edges of the view, with no additional inset.
- **reflects-initial-progress-value**: The component MUST reflect the view
  model's progress value immediately upon construction, before any further
  change to that value occurs.
- **tracks-progress-changes**: The component MUST update the progress
  indicator every time the view model's progress value changes, for as
  long as the view exists.
- **shows-determinate-bar-for-non-nil-progress**: WHEN the view model's
  progress value is present, the component MUST set the indicator to
  determinate, display that value, and stop any indeterminate animation.
- **shows-indeterminate-animation-for-nil-progress**: WHEN the view model's
  progress value is absent, the component MUST set the indicator to
  indeterminate and start its indeterminate animation.
- **continues-updates-while-retained**: The component MUST continue
  applying updates from **tracks-progress-changes** for as long as the
  view instance is retained (see Platform Notes for the exact subscription
  mechanism).
- **confines-to-ui-thread**: The component MUST be usable only from the UI
  thread.

## Appearance

- **Corner radius**: Not set by this component; the bar's rounded ends are
  the indicator's own default rendering — no custom drawing or
  corner-radius code appears in source.
- **Padding**: 0 — the progress indicator is pinned directly to all four
  edges of the view with no additional constant
  (**pins-progress-indicator-to-edges**).
- **Font**: Not applicable — the indicator draws no text of its own, and no
  font-related code appears in source.
- **Background**: Not set; the component performs no drawing or layer
  coloring of its own. The indicator's track color is the platform's
  default system appearance.
- **Foreground/Text**: Not applicable — no title or value text is rendered
  by the indicator or by the component itself.
- **Border**: Not set; no border customization appears anywhere in source.
- **Shadow**: Not set; no shadow customization appears anywhere in source.
- **Min/Max size**: Not set via any explicit width/height constraint on the
  view. The indicator's size equals the view's bounds exactly, via
  required-priority equal constraints on all four edges
  (**pins-progress-indicator-to-edges**), so the view has no intrinsic size
  floor or ceiling of its own — its size is whatever the caller's row
  layout gives it. The regular control size gives the indicator its own
  natural bar height as an intrinsic content size; if the container the
  view is placed in is shorter than that height, the required edge-pinning
  constraints can conflict with the indicator's own vertical content-size
  constraints at layout time. The source neither guards against nor
  documents this case.

## States

| State | Appearance change |
|-------|------------------|
| Default | Reflects the view model's progress value at construction time (**reflects-initial-progress-value**): a determinate bar if present, an animating indeterminate bar if absent. The view model's progress value defaults to absent, so a component built from a default-valued view model starts indeterminate and animating. |
| Determinate | The indicator's displayed value equals the view model's progress value; determinate mode is on; animation stopped; the bar shows the filled proportion of that value against the indicator's default 0–100 range (see Configuration). |
| Indeterminate | Indeterminate mode is on; the indeterminate animation has been started, producing the indicator's default bar-style indeterminate animation (a continuously animating bar, not a spinning wheel — no other animation style is ever selected anywhere in source). |
| Pressed | Not applicable: the component defines no click handling of any kind — it is a purely display-only, non-interactive view. |
| Disabled | Not implemented in this component; the source never reads or sets the indicator's enabled state. A caller may set it directly through the public progress-indicator property, at which point the platform's native dimmed appearance applies. |
| Focused | Not applicable: the view never becomes focused; the source overrides no focus-related behavior, and the platform's own default (not focusable) applies unmodified. |
| Loading | This is the Indeterminate state above (the view model's progress value is absent) — the component has no separate loading concept beyond it. |

## Accessibility

- **Role/trait**: Not observable beyond the platform's defaults — no
  explicit accessibility role override appears in source. The indicator is
  a plain progress indicator, which the platform exposes to assistive
  technology with its own default progress-indicator role and value
  reporting.
- **Label requirements**: Not implemented in source — no line in source
  connects the indicator to the view model's title (a required,
  non-empty-guarded string describing what the progress represents).
  Every other row in this same family that carries a title (e.g. the
  checkbox row) links its control to that title for a screen reader; this
  component does not, so a screen reader announces only the platform's
  default progress-indicator role and current value, with no indication
  of what operation the progress belongs to.
- **Announce state changes (e.g., loading, disabled)**: Determinate ↔
  indeterminate transitions are carried entirely by the indicator's own
  determinate/value/animation state
  (**shows-determinate-bar-for-non-nil-progress**,
  **shows-indeterminate-animation-for-nil-progress**), which the platform
  surfaces to a screen reader through its own accessibility value
  reporting; no separate announcement call appears in source.
- **Minimum tap target**: Not applicable — the component defines no click
  handling of any kind; it is a purely visual, non-interactive display
  element with no tap target to size.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| progress-view-001 | constructs-progress-indicator-at-regular-control-size | Construct the component with any view model | The indicator's control size is the platform's regular size |
| progress-view-002 | exposes-progress-indicator-publicly | Any initialized component | The progress indicator is externally accessible and is the same instance added as its child view |
| progress-view-003 | uses-constraint-based-layout | Any initialized component | The view and the progress indicator are both positioned via layout constraints, not the legacy frame-based resizing mechanism |
| progress-view-004 | adds-progress-indicator-as-subview | Any initialized component | The view's children include the progress indicator |
| progress-view-005 | pins-progress-indicator-to-edges | Host view laid out at a fixed frame, e.g. 200×20 | The indicator's resolved frame equals the host view's frame exactly, with zero inset on all four edges |
| progress-view-006 | reflects-initial-progress-value | View model constructed with title "T", progress = 0.5 | Immediately after construction, the indicator is determinate and its displayed value == 0.5 |
| progress-view-007 | reflects-initial-progress-value | View model constructed with title "T" and no progress value (the default) | Immediately after construction, the indicator is indeterminate |
| progress-view-008 | tracks-progress-changes | Construct with progress = 0.2, then set the view model's progress to 0.9 | The indicator's displayed value becomes 0.9; it remains determinate |
| progress-view-009 | tracks-progress-changes | Construct with progress = 0.2, then set the view model's progress to absent | The indicator becomes indeterminate |
| progress-view-010 | shows-determinate-bar-for-non-nil-progress | Set the view model's progress to 42.0 | The indicator is determinate; its displayed value == 42.0; its animation is stopped |
| progress-view-011 | shows-indeterminate-animation-for-nil-progress | Set the view model's progress to absent | The indicator is indeterminate; its animation is running |
| progress-view-012 | continues-updates-while-retained | Construct the view, keep no other external reference to its internal subscription, then set the view model's progress to three different values in turn | The indicator updates on every one of the three changes |
| progress-view-015 | confines-to-ui-thread | Attempt to construct or mutate the component from a thread other than the UI thread | The platform rejects or prevents the attempt (statically or at runtime, depending on platform — see Platform Notes) |

progress-view-006, -008, and -009 use progress values in a 0–1-normalized
range (0.5, 0.2, 0.9) while progress-view-010 uses the source's native 0–100
range (42.0); the component passes the view model's progress value through
to the indicator's displayed value unmodified regardless of scale — the
consumer chooses the scale (see the Design Decision on the indicator's
minimum/maximum values below). progress-view-015 is a static, compile-time
check on platforms that enforce UI-thread confinement statically; on
platforms that enforce it only at runtime, verify it as a runtime check
instead — see Platform Notes.

## Edge Cases

- **Null/empty input**: The view model's progress value is optional;
  absence is the documented indeterminate case, not an error (per the view
  model's own doc comment). The view model's title is a non-optional,
  non-empty-guarded string; an empty string has no observable effect on
  this component itself, since the view never reads title (see Design
  Decisions).
- **Boundary values**: The indicator's minimum/maximum values are never
  set by this component, leaving the indicator's default 0–100 range in
  effect. The component neither validates nor clamps the progress value
  before assigning it to the indicator; a value at exactly `0.0` or
  `100.0` renders as fully empty or fully filled, and a value outside that
  range (negative, or greater than `100.0`) is passed through to the
  indicator unmodified — any resulting clamp or visual boundary is the
  indicator's own native display behavior, not something this component
  governs.
- **Concurrent access**: Not applicable — both the component and its view
  model are confined to a single execution context
  (**confines-to-ui-thread**); that confinement is enforced at compile
  time on platforms that support it, and serializes construction,
  subscription delivery, and progress mutation at runtime.
- **Error states**: Not applicable — the component performs no network,
  database, or file-system access of its own. It only reflects whatever
  value the view model's progress reports; any error signaling for the
  underlying operation the progress represents is the caller's
  responsibility, outside this component.
- **Offline/disconnected state**: Not applicable — the component performs
  no networking.
- **View deallocated mid-progress**: The subscription is held in a stored
  property with no explicit teardown override in source; when the view is
  deallocated, the platform's own reference-counting releases that
  property, which cancels the subscription through its own default
  teardown behavior — not custom code in this component.
- **Rapid successive progress updates**: Each published value is delivered
  synchronously, in order, on the same execution context the progress
  value is mutated from (the UI thread, per **confines-to-ui-thread**); the
  indicator is updated once per published value, with no debouncing,
  throttling, or coalescing in source.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | progress view model | (required) | Supplies the progress value (optional; absent = indeterminate) that drives the indicator. Also carries a title/explanation, inherited from the base view model, though this component itself never reads them (see Design Decisions). |

## Deep Linking

Not applicable: this component is a display-only row inside a composable
settings window, not a navigable screen; no URL scheme, route, or
deep-link handler appears anywhere in source.

## Localization

Not applicable: this component renders no text of its own — the indicator
shows only a numeric value or an animation, never a string. Title and
explanation exist on the view model (inherited from the base view model)
but this component never reads or displays them, so it defines no string
literal that would need translation.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the indicator's indeterminate animation is the platform's own built-in system animation, started and stopped only via the component's start/stop animation calls; the component sets no animation timing, easing, or motion parameters of its own and neither adds nor could gate the platform's system-level indeterminate rendering. |
| Increase Contrast | Not applicable: the component sets no custom color of its own; all coloring is the indicator's default system appearance, which already tracks the system's Increase Contrast setting. |
| Differentiate Without Color | Not applicable: the component conveys its determinate/indeterminate state through the indicator's own fill proportion and motion, not through a color-only distinction of the component's own; it sets no color of its own to differentiate. |

## Feature Flags

Not applicable: the source contains no feature-flag check; the component
always constructs and wires the indicator unconditionally.

## Analytics

Not applicable: the source contains no analytics, tracking, or telemetry
call.

## Privacy

- **Data collected**: None — the component holds only an optional progress
  value and a reference to its view model; it originates no data of its
  own.
- **Storage**: Not applicable — the source performs no persistence of any
  kind.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the view retains only the progress
  indicator, the view model, and its internal subscription, for its own
  lifetime.

## Logging

Not applicable: the source contains no logging call (no print, log, or
logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: Use SwiftUI's own `ProgressView` type (same name as this
  component, a different API) —
  `ProgressView(value: viewModel.progress, total: 100).progressViewStyle(.linear)`
  when `progress` is non-nil for a determinate bar, or
  `ProgressView().progressViewStyle(.linear)` when it's `nil`. The explicit
  `.progressViewStyle(.linear)` is required on both branches: on macOS a bare
  `ProgressView()` renders a circular spinner by default, not the source's
  `.bar` style. The explicit `total: 100` is required on the determinate
  branch: `ProgressView(value:)` normalizes against a `0...1` range by
  default, while `NSProgressIndicator`'s default range (and this recipe's
  `progress` values) is 0–100. SwiftUI already switches rendering based on
  whether `value` is `nil`, mirroring `apply(progress:)`'s branch. Read
  `viewModel.progress` directly from an `ObservableObject`/`Observable`-backed
  view model in the view body instead of a manual Combine `sink`, letting
  SwiftUI's own diffing replace **tracks-progress-changes** and the stored
  `cancellable`.
- **Compose**: Use `LinearProgressIndicator(progress = { it })` bound to a
  `0f..1f`-normalized value — divide the source's 0–100 `progress` by 100
  (`progress / 100f`, or by `maxValue − minValue` if a caller has changed
  those through the public `progressIndicator` property) — when `progress` is
  non-nil, or the no-argument
  `LinearProgressIndicator()` overload (Compose's built-in indeterminate
  animation) when it's `nil`. Compose Material3 already splits determinate
  and indeterminate into two separate composables rather than one mutable
  `isIndeterminate` flag the way `NSProgressIndicator` does, so the port
  chooses the composable per state instead of mutating a shared instance.
- **React/Web**: Use the native `<progress value={progress} max={100} />`
  element when `progress` is non-nil (browsers render an indeterminate
  track automatically when the `value` attribute is entirely omitted,
  mirroring the nil/indeterminate branch), or `<progress />` with no
  `value` for the `nil` case. A CSS-animated element gives full styling
  control if needed; if so, gate its animation behind a
  `prefers-reduced-motion` media query, since the browser's own native
  `<progress>` indeterminate animation is not something the port controls
  directly (see Accessibility Options).
- **AppKit / UIKit (source)**: `ProgressView.swift` is macOS-only (`import
  AppKit`) — there is no iOS/UIKit counterpart in this file. It wraps one
  `NSProgressIndicator` pinned edge-to-edge inside an `NSView`, driven by a
  Combine subscription to `ProgressViewModel.$progress`, with `init(frame:)`
  fatal-erroring with the message `init(frame frameRect: NSRect` (see
  Design Decisions) and `init?(coder:)` fatal-erroring with the message
  `init(coder:) has not been implemented`, rather than either being usable,
  and the whole type isolated to `@MainActor`. **uses-constraint-based-layout**
  is implemented by setting `translatesAutoresizingMaskIntoConstraints = false`
  on both `self` and `progressIndicator`; **continues-updates-while-retained**
  is implemented by holding the `viewModel.$progress` subscription in a
  stored `cancellable: AnyCancellable?` property for the view's lifetime. A
  UIKit port would need `UIProgressView`
  for the determinate case and `UIActivityIndicatorView` for the
  indeterminate case, since `UIProgressView` — unlike `NSProgressIndicator`
  — has no built-in indeterminate mode of its own; the nil/non-nil branch in
  `apply(progress:)` would need to swap between two different UIKit control
  types rather than flip one `isIndeterminate` flag.
- **WinUI 3**: Use a `ProgressBar` control.
  Bind `ProgressBar.Value` to the caller's progress number (a 0–100 scale,
  matching `NSProgressIndicator`'s own default `minValue`/`maxValue`) when
  it's non-nil, and set `ProgressBar.IsIndeterminate="True"` when it's
  `nil` — `ProgressBar`'s `IsIndeterminate` dependency property is the
  direct analog of `isIndeterminate` in source
  (**shows-determinate-bar-for-non-nil-progress** /
  **shows-indeterminate-animation-for-nil-progress**), giving one control
  both modes the same way `NSProgressIndicator` does. Drive it from an
  `x:Bind`/`INotifyPropertyChanged` view-model property shaped like
  `ProgressViewModel.progress` (a nullable double), updating `Value` and
  `IsIndeterminate` together in that property's setter — the direct analog
  of `apply(progress:)`. Host the `ProgressBar` in its own `Grid` cell with
  `HorizontalAlignment="Stretch"` and `VerticalAlignment="Stretch"` and no
  `Margin`, reproducing `pinToEdges`'s edge-to-edge, no-inset placement.
  `ProgressBar` has no `fatalError`-style initializer guard, so enforce
  "always construct with a view model" through a required constructor
  parameter or `x:Bind` requirement instead of a runtime crash on an unused
  inherited initializer. `ProgressBar`'s determinate visual defaults to the
  system accent color, giving the same "no color decision made by this
  component" outcome as `NSProgressIndicator`'s system chrome (see
  Appearance).

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ProgressView.swift` |

## Design Decisions

**Decision**: This component never reads the view model's title or
explanation (both inherited from the base view model), unlike every other
row in this same family (the checkbox row, the text edit row, the color
picker row, the stepper row, and others), which all build a label from the
view model's title.
**Rationale**: Not explained anywhere in source (AppKit/UIKit) — no
comment addresses why the title and explanation the view model carries go
unused. This recipe records the deviation from sibling views rather than
assuming a row-composition convention (e.g. that a caller always pairs
this component with a separate label or an explanation row) that the given
source does not itself show.
**Approved**: pending

**Decision**: The initial progress value is applied twice at construction
— once implicitly, because the view model's progress subscription
delivers the current value synchronously to a new subscriber (AppKit/UIKit
source: a `@Published` publisher, `viewModel.$progress.sink`), and once
explicitly via a direct call immediately after that subscription is set
up (AppKit/UIKit source: `self.apply(progress: viewModel.progress)`).
**Rationale**: This produces no observable difference (the same value is
applied twice in a row, both before construction returns), but it is
present in source as written; this recipe records it rather than silently
simplifying it away. No comment in source explains whether the explicit
call is defensive redundancy or an oversight.
**Approved**: pending

**Decision**: The indicator's minimum/maximum values are never set by
this component, leaving the indicator's default 0–100 range in effect;
the view model's progress doc comment states only that a present value
"drives a determinate bar (consumer chooses the scale)."
**Rationale**: Because the scale is left at the default range and the
indicator is exposed publicly, a caller wanting a different scale must
reach through the public progress-indicator property and set the
minimum/maximum values directly — neither this component nor its view
model provides a dedicated API for it.
**Approved**: pending

**Decision**: The frame-based initializer's fatal-error message
(AppKit/UIKit source: `init(frame frameRect: NSRect)`) is the literal
string `init(frame frameRect: NSRect`, missing a closing parenthesis, and
does not follow the sentence form of the sibling coder-initializer
message.
**Rationale**: documented here as a source quirk rather than corrected,
for the same reason sibling recipes in this file family record it: it
reads as a truncated fragment of the initializer's own signature, very
likely a typo, but the source is unchanged for this recipe.
**Approved**: pending

**Decision**: The indicator's edges are pinned to the view's edges with
required-priority equal constraints rather than offering a placement
choice the way the button row offers fill/leading/centered placement.
**Rationale**: This component has exactly one placement — full-bleed —
with no choice offered as an alternative. This recipe records that as a
genuine difference in scope from the button row, not an oversight; the
source gives it no other placement to describe.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | failed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | passed | Accessibility |

`contrast-ratio` is `passed` because `ProgressView` sets no color of its
own — all rendering is `NSProgressIndicator`'s unmodified system chrome,
which already tracks platform contrast; the same absence of custom coloring
means `ProgressView` conveys its determinate/indeterminate state through
fill proportion and motion rather than a color-only cue (see Accessibility
Options). `screen-reader-support` is `failed` because, as recorded under
Label requirements in Accessibility above, no accessibility label or
title-UI-element link connects `progressIndicator` to `viewModel.title`, so
`ProgressView` plainly does not implement this check today.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial recipe — extracted from the Apple `ProgressView` (AppKit, macOS) source. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: corrected the SwiftUI and Compose Platform Notes for scale and default style mismatches; restated two implementation-detail requirements as observable behavior and moved their AppKit mechanics into Platform Notes; added references for platform API claims and related links to sibling row recipes; reformatted Design Decisions' Approved line; fixed the concurrent-access wording; annotated the mixed-scale and compile-time-only test vectors; removed an editorial aside from the WinUI 3 bullet; corrected the Compliance status and category casing and pruned non-catalog compliance checks. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
