---
id: ea2dae31-1020-4930-aa12-15f7d04967a5
title: ProgressView
domain: agentictoolkit://recipes/progress-view
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings row wrapping one NSProgressIndicator, switching
  between a determinate bar and an indeterminate animation from a Combine value.
platforms:
- swift
- macos
tags:
- settings
- status-indicator
- progress
- macos
- appkit
depends-on: []
related:
- agentictoolkit://recipes/checkbox-view
- agentictoolkit://recipes/button-view
- agentictoolkit://recipes/explanation-view
references:
- https://developer.apple.com/documentation/appkit/nsprogressindicator
- https://developer.apple.com/documentation/uikit/uiprogressview
- https://learn.microsoft.com/en-us/uwp/api/windows.ui.xaml.controls.progressbar.isindeterminate
- https://developer.mozilla.org/en-US/docs/Web/HTML/Element/progress
approved-by: ''
approved-date: ''
---

# ProgressView

## Overview

`ComposableSettings.ProgressView`
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ProgressView.swift`)
is a macOS `NSView` conforming to `SettingsViewProtocol` (an empty marker
protocol every `ComposableSettings` row view conforms to, with no
requirements of its own) that wraps a single `NSProgressIndicator` pinned
edge-to-edge inside itself. It is driven entirely by a
`ComposableSettings.ProgressViewModel`: a Combine subscription to the view
model's `$progress` publisher (`Double?`, where `nil` means indeterminate per
the view model's own doc comment) flips the indicator between a determinate
bar showing a numeric value and an animating indeterminate bar every time
`progress` changes, for as long as the view exists.

## Behavioral Requirements

- **constructs-progress-indicator-at-regular-control-size**: The component
  MUST initialize `progressIndicator` as an `NSProgressIndicator` with
  `controlSize` set to `.regular`.
- **exposes-progress-indicator-publicly**: The component MUST expose the
  underlying `NSProgressIndicator` as a public, read-only `progressIndicator`
  property.
- **uses-constraint-based-layout**: The component MUST be positioned using
  Auto Layout constraints, not the legacy autoresizing mask, for both itself
  and `progressIndicator` (see AppKit / UIKit Platform Notes for the exact
  API).
- **adds-progress-indicator-as-subview**: The component MUST add
  `progressIndicator` as a subview of itself.
- **pins-progress-indicator-to-edges**: The component MUST pin
  `progressIndicator`'s top, leading, trailing, and bottom edges to the
  corresponding edges of the view (`Self.pinToEdges`), with no additional
  inset.
- **reflects-initial-progress-value**: The component MUST reflect
  `viewModel.progress`'s value in `progressIndicator` immediately upon
  construction, before any further change to `viewModel.progress` occurs.
- **tracks-progress-changes**: The component MUST update `progressIndicator`
  every time `viewModel.progress` changes, for as long as the view exists.
- **shows-determinate-bar-for-non-nil-progress**: WHEN `viewModel.progress`
  is non-nil, the component MUST set `progressIndicator.isIndeterminate` to
  `false`, set `progressIndicator.doubleValue` to that value, and call
  `progressIndicator.stopAnimation(nil)`.
- **shows-indeterminate-animation-for-nil-progress**: WHEN
  `viewModel.progress` is `nil`, the component MUST set
  `progressIndicator.isIndeterminate` to `true` and call
  `progressIndicator.startAnimation(nil)`.
- **continues-updates-while-retained**: The component MUST continue applying
  updates from **tracks-progress-changes** for as long as the view instance
  is retained (see AppKit / UIKit Platform Notes for the exact subscription
  mechanism).
- **rejects-frame-initializer**: The component MUST fatal-error if
  constructed through the inherited `NSView.init(frame:)` initializer.
- **rejects-coder-initializer**: The component MUST fatal-error if
  constructed through `init?(coder:)`.
- **confines-to-main-actor**: The component MUST be usable only on the main
  actor; the class is declared `@MainActor`.

## Appearance

- **Corner radius**: Not set by `ProgressView`; the bar's rounded ends are
  `NSProgressIndicator`'s own default rendering — no `CALayer`,
  `wantsLayer`, or corner-radius code appears in source.
- **Padding**: 0 — `progressIndicator` is pinned directly to all four edges
  of the view with no additional constant (**pins-progress-indicator-to-edges**).
- **Font**: Not applicable — `NSProgressIndicator` draws no text of its own,
  and no font-related code appears in `ProgressView.swift`.
- **Background**: Not set; `ProgressView` performs no drawing or layer
  coloring of its own. The indicator's track color is
  `NSProgressIndicator`'s default system appearance.
- **Foreground/Text**: Not applicable — no title or value text is rendered
  by `progressIndicator` or by `ProgressView` itself.
- **Border**: Not set; no border customization appears anywhere in source.
- **Shadow**: Not set; no shadow customization appears anywhere in source.
- **Min/Max size**: Not set via any explicit width/height constraint on the
  view. `progressIndicator`'s size equals the view's bounds exactly, via
  required-priority equal constraints on all four edges
  (**pins-progress-indicator-to-edges**), so the view has no intrinsic size
  floor or ceiling of its own — its size is whatever the caller's row
  layout gives it. `controlSize = .regular` gives `progressIndicator` its
  own natural bar height as an intrinsic content size; if the container the
  view is placed in is shorter than that height, the required edge-pinning
  constraints can conflict with the indicator's own vertical content-size
  constraints at layout time. The source neither guards against nor
  documents this case.

## States

| State | Appearance change |
|-------|------------------|
| Default | Reflects `viewModel.progress` at construction time (**reflects-initial-progress-value**): a determinate bar if non-nil, an animating indeterminate bar if `nil`. `ProgressViewModel`'s `progress` parameter defaults to `nil`, so a `ProgressView` built from a default-valued view model starts indeterminate and animating. |
| Determinate | `progressIndicator.doubleValue` equals `viewModel.progress`; `isIndeterminate == false`; animation stopped; the bar shows the filled proportion of `doubleValue` against `NSProgressIndicator`'s default 0–100 range (see Configuration). |
| Indeterminate | `isIndeterminate == true`; `startAnimation(nil)` has been called, producing `NSProgressIndicator`'s default `.bar`-style indeterminate animation (a continuously animating bar, not a spinning wheel — `style` is never set away from its `.bar` default anywhere in source). |
| Pressed | Not applicable: `ProgressView` defines no target/action, gesture recognizer, or tracking area — it is a purely display-only, non-interactive view. |
| Disabled | Not implemented in `ProgressView`; the source never reads or sets `progressIndicator.isEnabled`. A caller may set it directly through the public `progressIndicator` property, at which point `NSProgressIndicator`'s native dimmed appearance applies. |
| Focused | Not applicable: the view never becomes key/first responder; the source overrides no responder-chain behavior, and `NSView`'s own default (`acceptsFirstResponder == false`) applies unmodified. |
| Loading | This is the Indeterminate state above (`viewModel.progress == nil`) — `ProgressView` has no separate loading concept beyond it. |

## Accessibility

- **Role/trait**: Not observable beyond AppKit's defaults — no explicit
  accessibility role override appears in source. `progressIndicator` is a
  plain `NSProgressIndicator`, which AppKit exposes to assistive technology
  with its own default progress-indicator role and value reporting.
- **Label requirements**: NEEDS REVIEW: Not implemented in source. No line
  in `ProgressView.swift` calls `progressIndicator.setAccessibilityLabel(_:)`
  or `setAccessibilityTitleUIElement(_:)` to connect `progressIndicator` to
  `viewModel.title` (a required `String` on `ProgressViewModel`, inherited
  from `AbstractViewModel`, describing what the progress represents). Every
  other `SettingsViewProtocol` row in this same directory that carries a
  title (e.g. `CheckboxView`, which calls
  `toggle.setAccessibilityTitleUIElement(label)`) links its control to that
  title for VoiceOver; `ProgressView` does not, so VoiceOver announces only
  AppKit's default progress-indicator role and current value, with no
  indication of what operation the progress belongs to. This would be
  settled by adding an explicit accessibility-label or title-UI-element call
  in `ProgressView.swift`, or by confirming with the owning team that the
  caller composing this view into a row is always responsible for that
  linkage instead.
- **Announce state changes (e.g., loading, disabled)**: Determinate ↔
  indeterminate transitions are carried entirely by
  `progressIndicator.isIndeterminate`/`doubleValue`/animation state
  (**shows-determinate-bar-for-non-nil-progress**,
  **shows-indeterminate-animation-for-nil-progress**), which
  `NSProgressIndicator` surfaces to VoiceOver through its own accessibility
  value reporting; no separate `NSAccessibility.post` or announcement call
  appears in `ProgressView.swift`.
- **Minimum tap target**: Not applicable — `ProgressView` defines no
  target/action, gesture recognizer, or click handling; it is a purely
  visual, non-interactive display element with no tap target to size.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| progress-view-001 | constructs-progress-indicator-at-regular-control-size | `ProgressView(viewModel: vm)` | `view.progressIndicator.controlSize == .regular` |
| progress-view-002 | exposes-progress-indicator-publicly | Any initialized `ProgressView` | `view.progressIndicator` is externally accessible and is the same `NSProgressIndicator` instance added as its subview |
| progress-view-003 | uses-constraint-based-layout | Any initialized `ProgressView` | `view.translatesAutoresizingMaskIntoConstraints == false` and `view.progressIndicator.translatesAutoresizingMaskIntoConstraints == false` |
| progress-view-004 | adds-progress-indicator-as-subview | Any initialized `ProgressView` | `view.subviews` contains `view.progressIndicator` |
| progress-view-005 | pins-progress-indicator-to-edges | Host view laid out at a fixed frame, e.g. 200×20 | `progressIndicator`'s resolved frame equals the host view's frame exactly, with zero inset on all four edges |
| progress-view-006 | reflects-initial-progress-value | `ProgressViewModel(title: "T", progress: 0.5)` | Immediately after `init`, `progressIndicator.isIndeterminate == false` and `progressIndicator.doubleValue == 0.5` |
| progress-view-007 | reflects-initial-progress-value | `ProgressViewModel(title: "T")` (default `progress: nil`) | Immediately after `init`, `progressIndicator.isIndeterminate == true` |
| progress-view-008 | tracks-progress-changes | Construct with `progress: 0.2`, then set `viewModel.progress = 0.9` | `progressIndicator.doubleValue` becomes `0.9`; `isIndeterminate` remains `false` |
| progress-view-009 | tracks-progress-changes | Construct with `progress: 0.2`, then set `viewModel.progress = nil` | `progressIndicator.isIndeterminate` becomes `true` |
| progress-view-010 | shows-determinate-bar-for-non-nil-progress | Set `viewModel.progress = 42.0` | `progressIndicator.isIndeterminate == false`; `progressIndicator.doubleValue == 42.0`; the indicator's animation is stopped |
| progress-view-011 | shows-indeterminate-animation-for-nil-progress | Set `viewModel.progress = nil` | `progressIndicator.isIndeterminate == true`; the indicator's animation is running |
| progress-view-012 | continues-updates-while-retained | Construct the view, keep no external reference to its Combine subscription, then set `viewModel.progress` to three different values in turn | `progressIndicator` updates on every one of the three changes |
| progress-view-013 | rejects-frame-initializer | Construct via `ProgressView(frame: .zero)` | Execution traps via `fatalError` with message `init(frame frameRect: NSRect` |
| progress-view-014 | rejects-coder-initializer | Construct via `ProgressView(coder:)` with any `NSCoder` | Execution traps via `fatalError` with message `init(coder:) has not been implemented` |
| progress-view-015 | confines-to-main-actor | Attempt to construct or mutate a `ProgressView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |

progress-view-006, -008, and -009 use progress values in a 0–1-normalized
range (0.5, 0.2, 0.9) while progress-view-010 uses the source's native 0–100
range (42.0); `ProgressView` passes `viewModel.progress` through to
`progressIndicator.doubleValue` unmodified regardless of scale — the consumer
chooses the scale (see the Design Decision on `minValue`/`maxValue` below).
progress-view-015 is a static, compile-time check: `@MainActor` isolation is
enforced by the Swift compiler and verified by the build, not by a runtime
assertion.

## Edge Cases

- **Null/empty input**: `viewModel.progress` is `Double?`; `nil` is the
  documented indeterminate case, not an error (per `ProgressViewModel`'s own
  doc comment). `viewModel.title` is a non-optional, non-empty-guarded
  `String`; an empty string has no observable effect on `ProgressView`
  itself, since the view never reads `title` (see Design Decisions).
- **Boundary values**: `progressIndicator`'s `minValue`/`maxValue` are never
  set by `ProgressView`, leaving `NSProgressIndicator`'s default 0–100
  range in effect. `ProgressView` neither validates nor clamps `progress`
  before assigning it to `doubleValue`; a value at exactly `0.0` or `100.0`
  renders as fully empty or fully filled, and a value outside that range
  (negative, or greater than `100.0`) is passed through to
  `progressIndicator.doubleValue` unmodified — any resulting clamp or
  visual boundary is `NSProgressIndicator`'s own native display behavior,
  not something `ProgressView` governs.
- **Concurrent access**: Not applicable — both
  `ComposableSettings.ProgressView` and `ComposableSettings.ProgressViewModel`
  are `@MainActor`-isolated (**confines-to-main-actor**); the Swift compiler
  enforces that isolation at compile time, and the main actor serializes
  construction, subscription delivery, and `progress` mutation at runtime.
- **Error states**: Not applicable — `ProgressView` performs no network,
  database, or file-system access of its own. It only reflects whatever
  value `viewModel.progress` reports; any error signaling for the
  underlying operation the progress represents is the caller's
  responsibility, outside this component.
- **Offline/disconnected state**: Not applicable — `ProgressView` performs
  no networking.
- **View deallocated mid-progress**: `cancellable` is a stored instance
  property with no explicit `deinit` override in `ProgressView.swift`; when
  the view is deallocated, ARC releases `cancellable`, which cancels the
  Combine subscription through `AnyCancellable`'s own default deinit
  behavior — not custom code in this component.
- **Rapid successive progress updates**: `viewModel.$progress.sink` delivers
  each published value synchronously, in order, on the actor `progress` is
  mutated from (the main actor, per `@MainActor` isolation); `progressIndicator`
  is updated once per published value, with no debouncing, throttling, or
  coalescing in source.

## Configuration

`ProgressView`
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ProgressView.swift`):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ProgressViewModel` | (required) | Supplies the `progress` value (`Double?`, `nil` = indeterminate) that drives `progressIndicator`. Also carries `title`/`explanation`, inherited from `AbstractViewModel`, though `ProgressView` itself never reads them (see Design Decisions). |

```swift
public init(viewModel: ProgressViewModel)
```

## Deep Linking

Not applicable: `ProgressView` is a display-only row inside a composable
settings window, not a navigable screen; no URL scheme, route, or deep-link
handler appears anywhere in `ProgressView.swift`.

## Localization

Not applicable: `ProgressView` renders no text of its own — `progressIndicator`
shows only a numeric value or an animation, never a string. `title` and
`explanation` exist on `ProgressViewModel` (inherited from
`AbstractViewModel`) but `ProgressView.swift` never reads or displays them,
so this component defines no string literal that would need translation.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `progressIndicator`'s indeterminate animation is `NSProgressIndicator`'s own built-in system animation, started and stopped only via `startAnimation(nil)`/`stopAnimation(nil)`; `ProgressView` sets no animation timing, easing, or motion parameters of its own and neither adds nor could gate AppKit's system-level indeterminate rendering. |
| Increase Contrast | Not applicable: `ProgressView` sets no custom `NSColor` of its own; all coloring is `NSProgressIndicator`'s default system appearance, which already tracks the system's Increase Contrast setting. |
| Differentiate Without Color | Not applicable: `ProgressView` conveys its determinate/indeterminate state through `NSProgressIndicator`'s own fill proportion and motion, not through a color-only distinction of the component's own; it sets no color of its own to differentiate. |

## Feature Flags

Not applicable: the source contains no feature-flag check; `ProgressView`
always constructs and wires `progressIndicator` unconditionally.

## Analytics

Not applicable: the source contains no analytics, tracking, or telemetry
call.

## Privacy

- **Data collected**: None — `ProgressView` holds only a `Double?` progress
  value and a reference to `viewModel`; it originates no data of its own.
- **Storage**: Not applicable — the source performs no persistence of any
  kind.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only `progressIndicator`,
  `viewModel`, and `cancellable`, for its own lifetime.

## Logging

Not applicable: the source contains no logging call (no `print`, `os_log`,
or logger reference anywhere in source).

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
  and `init?(coder:)` fatal-erroring rather than being usable, and the whole
  type isolated to `@MainActor`. **uses-constraint-based-layout** is
  implemented by setting `translatesAutoresizingMaskIntoConstraints = false`
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

## Design Decisions

**Decision**: `ProgressView` never reads `viewModel.title` or
`viewModel.explanation` (both inherited from `AbstractViewModel`), unlike
every other `SettingsViewProtocol` row in this same directory
(`CheckboxView`, `TextEditView`, `ColorPickerView`, `StepperView`, and
others), which all build a label from `viewModel.title`.
**Rationale**: Not explained anywhere in `ProgressView.swift` — no comment
addresses why the title and explanation the view model carries go unused.
This recipe records the deviation from sibling views rather than assuming a
row-composition convention (e.g. that a caller always pairs `ProgressView`
with a separate label or `ExplanationView`) that the given source does not
itself show.
**Approved**: pending

**Decision**: The initial progress value is applied twice at construction —
once implicitly, because `viewModel.$progress.sink` (a `@Published`
publisher) delivers the current value synchronously to a new subscriber,
and once explicitly via `self.apply(progress: viewModel.progress)`
immediately after `sink` returns.
**Rationale**: This produces no observable difference (the same value is
applied twice in a row, both before `init` returns), but it is present in
source as written; this recipe records it rather than silently simplifying
it away. No comment in source explains whether the explicit call is
defensive redundancy or an oversight.
**Approved**: pending

**Decision**: `progressIndicator`'s `minValue`/`maxValue` are never set by
`ProgressView`, leaving `NSProgressIndicator`'s default 0–100 range in
effect; `ProgressViewModel.progress`'s own doc comment states only that a
non-nil value "drives a determinate bar (consumer chooses the scale)."
**Rationale**: Because the scale is left at the default range and
`progressIndicator` is exposed publicly, a caller wanting a different scale
must reach through the public `progressIndicator` property and set
`minValue`/`maxValue` directly — neither `ProgressView` nor
`ProgressViewModel` provides a dedicated API for it.
**Approved**: pending

**Decision**: `init(frame frameRect: NSRect)`'s fatal-error message is the
literal string `init(frame frameRect: NSRect`, missing a closing
parenthesis, and does not follow the sentence form of the sibling
`init?(coder:)` message.
**Rationale**: documented here as a source quirk rather than corrected, for
the same reason sibling recipes in this file family record it: it reads as
a truncated fragment of the initializer's own signature, very likely a
typo, but the source is unchanged for this recipe.
**Approved**: pending

**Decision**: `progressIndicator`'s edges are pinned to the view's edges
with required-priority equal constraints (`Self.pinToEdges`) rather than
offering a placement choice the way `ButtonView` offers `.fill`/`.leading`/
`.centered`.
**Rationale**: `ProgressView` has exactly one placement — full-bleed — with
no enum or parameter offering an alternative. This recipe records that as a
genuine difference in scope from `ButtonView`, not an oversight; the source
gives it no other placement to describe.
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
Options). `screen-reader-support` is `failed` because of the open question
tracked under Accessibility above: no accessibility label or title-UI-element
link connects `progressIndicator` to `viewModel.title`, so `ProgressView`
plainly does not implement this check today.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial recipe — extracted from the Apple `ProgressView` (AppKit, macOS) source. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: corrected the SwiftUI and Compose Platform Notes for scale and default style mismatches; restated two implementation-detail requirements as observable behavior and moved their AppKit mechanics into Platform Notes; added references for platform API claims and related links to sibling row recipes; reformatted Design Decisions' Approved line; fixed the concurrent-access wording; annotated the mixed-scale and compile-time-only test vectors; removed an editorial aside from the WinUI 3 bullet; corrected the Compliance status and category casing and pruned non-catalog compliance checks. |
