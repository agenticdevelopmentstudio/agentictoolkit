<!-- leaf: implement-general-view-2/progress-view · source: progress-view.md -->

**Rules** (cite as `implement-general-view-2/progress-view#<slug>`):

- `constructs-progress-indicator-at-regular-control-size` MUST
- `exposes-progress-indicator-publicly` MUST
- `uses-constraint-based-layout` MUST
- `adds-progress-indicator-as-subview` MUST
- `pins-progress-indicator-to-edges` MUST
- `reflects-initial-progress-value` MUST
- `tracks-progress-changes` MUST
- `shows-determinate-bar-for-non-nil-progress` MUST
- `shows-indeterminate-animation-for-nil-progress` MUST
- `continues-updates-while-retained` MUST
- `rejects-frame-initializer` MUST
- `rejects-coder-initializer` MUST
- `confines-to-main-actor` MUST

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

## Accessibility

- **Role/trait**: Not observable beyond AppKit's defaults — no explicit
  accessibility role override appears in source. `progressIndicator` is a
  plain `NSProgressIndicator`, which AppKit exposes to assistive technology
  with its own default progress-indicator role and value reporting.
- **Label requirements**: Not implemented in source — no line in
  `ProgressView.swift` calls `progressIndicator.setAccessibilityLabel(_:)`
  or `setAccessibilityTitleUIElement(_:)` to connect `progressIndicator` to
  `viewModel.title` (a required `String` on `ProgressViewModel`, inherited
  from `AbstractViewModel`, describing what the progress represents). Every
  other `SettingsViewProtocol` row in this same directory that carries a
  title (e.g. `CheckboxView`, which calls
  `toggle.setAccessibilityTitleUIElement(label)`) links its control to that
  title for VoiceOver; `ProgressView` does not, so VoiceOver announces only
  AppKit's default progress-indicator role and current value, with no
  indication of what operation the progress belongs to.
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

## Configuration

`ProgressView`
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ProgressView.swift`):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ProgressViewModel` | (required) | Supplies the `progress` value (`Double?`, `nil` = indeterminate) that drives `progressIndicator`. Also carries `title`/`explanation`, inherited from `AbstractViewModel`, though `ProgressView` itself never reads them (see Design Decisions). |

```swift
public init(viewModel: ProgressViewModel)
```

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `progressIndicator`'s indeterminate animation is `NSProgressIndicator`'s own built-in system animation, started and stopped only via `startAnimation(nil)`/`stopAnimation(nil)`; `ProgressView` sets no animation timing, easing, or motion parameters of its own and neither adds nor could gate AppKit's system-level indeterminate rendering. |
| Increase Contrast | Not applicable: `ProgressView` sets no custom `NSColor` of its own; all coloring is `NSProgressIndicator`'s default system appearance, which already tracks the system's Increase Contrast setting. |
| Differentiate Without Color | Not applicable: `ProgressView` conveys its determinate/indeterminate state through `NSProgressIndicator`'s own fill proportion and motion, not through a color-only distinction of the component's own; it sets no color of its own to differentiate. |

## Privacy

- **Data collected**: None — `ProgressView` holds only a `Double?` progress
  value and a reference to `viewModel`; it originates no data of its own.
- **Storage**: Not applicable — the source performs no persistence of any
  kind.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only `progressIndicator`,
  `viewModel`, and `cancellable`, for its own lifetime.

