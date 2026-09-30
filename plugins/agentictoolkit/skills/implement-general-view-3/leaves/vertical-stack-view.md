<!-- leaf: implement-general-view-3/vertical-stack-view · source: vertical-stack-view.md -->

**Rules** (cite as `implement-general-view-3/vertical-stack-view#<slug>`):

- `confines-to-main-actor` MUST
- `disables-autoresizing-mask-translation` MUST
- `wraps-a-vertical-nsstackview` MUST
- `sets-arranged-subview-spacing-from-group-spacing-token` MUST
- `disables-autoresizing-mask-translation-on-inner-stack-view` MUST
- `adds-stack-view-as-subview` MUST
- `pins-stack-view-to-container-edges` MUST
- `exposes-stack-view-as-public-property` MUST
- `ignores-explicit-frame` SHOULD
- `convenience-init-uses-zero-frame` MUST
- `rejects-coder-initializer` MUST
- `forwards-added-views-to-inner-stack-view` MUST
- `conforms-to-settings-view-protocol` MUST

# Vertical Stack View

## Overview

`ComposableSettings.VerticalStackView`, at `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/VerticalStackView.swift`, is a thin AppKit `NSView` wrapper around a vertical `NSStackView`, used to arrange a column of sibling views top-to-bottom within the ComposableSettingsWindow system integration. It is nested in the `ComposableSettings` namespace and conforms to `SettingsViewProtocol`, the marker protocol every settings-row view in this system adopts (its sibling `HorizontalStackView` is the horizontal counterpart, differing only in orientation and in `stackView`'s access level — see Design Decisions). `VerticalStackView` has no caller-configurable options: its only public initializer is a parameterless `convenience init()`, its inter-item spacing is fixed to `SettingsLayout.default[.groupSpacing]`, its wrapped `NSStackView` is exposed as a public, read-only `stackView` property, and its only other public member is `addArrangedSubview(_:)`, which forwards to that same wrapped stack view.

## Behavioral Requirements

- **confines-to-main-actor**: The component MUST be usable only on the main actor; the class is declared `@MainActor`.
- **disables-autoresizing-mask-translation**: The component MUST set `translatesAutoresizingMaskIntoConstraints = false` on itself.
- **wraps-a-vertical-nsstackview**: The component MUST construct an internal `NSStackView` with `orientation = .vertical`.
- **sets-arranged-subview-spacing-from-group-spacing-token**: The component MUST set the internal stack view's `spacing` to `SettingsLayout.default[.groupSpacing]` (20.0pt, per `ViewLayout.swift`'s `SettingsLayout.default` values) at initialization.
- **disables-autoresizing-mask-translation-on-inner-stack-view**: The component MUST set `translatesAutoresizingMaskIntoConstraints = false` on the internal stack view.
- **adds-stack-view-as-subview**: The component MUST add the internal stack view to itself via `addSubview(_:)`.
- **pins-stack-view-to-container-edges**: The component MUST activate constraints pinning the internal stack view's top, leading, trailing, and bottom anchors to the corresponding anchors of the component itself, via `Self.pinToEdges(_:of:)` (defined in `ViewLayout.swift`).
- **exposes-stack-view-as-public-property**: The component MUST expose its internal `NSStackView` as a public, read-only (`let`) property named `stackView`.
- **ignores-explicit-frame**: The designated initializer, `init(frame frameRect: NSRect)`, SHOULD discard the caller-supplied `frameRect` and call `super.init(frame: .zero)` unconditionally, regardless of the argument's value; see Design Decisions for why a port should keep this rather than reconcile the caller's rect with Auto Layout.
- **convenience-init-uses-zero-frame**: The public `convenience init()` MUST call `self.init(frame: .zero)`.
- **rejects-coder-initializer**: `required init?(coder: NSCoder)` MUST fatal-error with the message `init(coder:) has not been implemented`.
- **forwards-added-views-to-inner-stack-view**: The public `addArrangedSubview(_ view: NSView)` method MUST forward its argument to the internal stack view via `stackView.addArrangedSubview(view)`.
- **conforms-to-settings-view-protocol**: The component MUST conform to `SettingsViewProtocol`.

## Appearance

- **Corner radius**: None; the source never sets `wantsLayer` or `layer?.cornerRadius` — the view is not layer-backed.
- **Padding**: None of its own. The internal stack view is pinned flush to all four edges of the component with zero additional inset (see **pins-stack-view-to-container-edges**); the only spacing the component introduces is the gap between arranged subviews set from `SettingsLayout.default[.groupSpacing]` (see **sets-arranged-subview-spacing-from-group-spacing-token**).
- **Font**: Not applicable — `VerticalStackView` renders no text or other font-dependent content of its own.
- **Background**: None; the view is not layer-backed and sets no `layer?.backgroundColor` or `NSColor`-based fill — it is fully transparent, showing whatever sits behind it.
- **Foreground/Text**: Not applicable — `VerticalStackView` has no text or foreground content; it only positions its arranged subviews.
- **Border**: None; the source never sets `layer?.borderWidth` or `layer?.borderColor`.
- **Shadow**: None; the source never sets any shadow property.
- **Min/Max size**: No explicit min/max width or height constraints of its own. Because the internal stack view is pinned flush to all four edges with zero inset, the component's size is driven entirely by its arranged subviews' intrinsic content sizes plus the inter-item spacing (see **sets-arranged-subview-spacing-from-group-spacing-token**).

## Accessibility

- **Role/trait**: Not applicable — `VerticalStackView` is a transparent layout container; the source sets no `accessibilityRole`, `accessibilityLabel`, or `isAccessibilityElement` override. It exists only to lay out its arranged subviews, each of which owns its own accessibility properties (and, where relevant, its own recipe).
- **Label requirements**: Not applicable — `VerticalStackView` renders no text and carries no semantic content of its own to name.
- **Announce state changes**: Not applicable — `VerticalStackView` defines no state that changes (see States); there is nothing for an announcement to report.
- **Minimum tap target**: Not applicable — `VerticalStackView` is not an interactive control; the source wires no target/action or gesture recognizer to it, so it has no tap target to size.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `VerticalStackView` applies no animation, transition, or motion effect of its own — it assigns layout constraints once, at initialization, with no animator proxy or transition wrapping any of it. |
| Increase Contrast | Not applicable: `VerticalStackView` is not layer-backed and sets no color of its own; it has no visual surface for Increase Contrast to affect. |
| Differentiate Without Color | Not applicable: `VerticalStackView` conveys no state or meaning through color — it renders no color at all. |

## Privacy

- **Data collected**: None. `VerticalStackView`'s only stored property is the public `stackView`, an `NSStackView`; it holds no caller-supplied data of its own.
- **Storage**: Not applicable — `VerticalStackView` performs no persistence of any kind.
- **Transmission**: Not applicable — `VerticalStackView` performs no network or IPC calls.
- **Retention**: Not applicable — nothing is retained beyond the view instance's own lifetime.

## Platform Notes

- **SwiftUI**: `VStack(spacing:)` is the direct equivalent, with `spacing` sourced from the equivalent of `SettingsLayout.default[.groupSpacing]`. Unlike this AppKit type, which takes children imperatively via repeated `addArrangedSubview(_:)` calls after construction, a `VStack` takes its children declaratively as trailing-closure content at the call site — there is no separate "add a child later" step to port, and no equivalent of a publicly exposed `stackView` is needed since `VStack` has no such wrapped sub-object.
- **Compose**: `Column(verticalArrangement = Arrangement.spacedBy(...))`, with the spacing value sourced from the equivalent of the `groupSpacing` token. As with SwiftUI, Compose children are declared inline rather than appended imperatively after construction, so a port drops the `addArrangedSubview`-style API entirely.
- **React/Web**: A `<div>` with `display: flex; flex-direction: column; gap: <groupSpacing>px;` (a CSS Flexbox column). The `gap` property supplies the equivalent of `NSStackView.spacing` directly, with no manual spacer elements needed; children are ordinary DOM children in document order, corresponding to the order arranged subviews are added.
- **AppKit / UIKit (source)**: `VerticalStackView.swift` (`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/VerticalStackView.swift`) is macOS-only (`import AppKit`) — there is no iOS/UIKit counterpart in this file. It wraps a single `NSStackView` (`orientation = .vertical`), pinned to all four edges of the outer `NSView` via `Self.pinToEdges(_:of:)` (`ViewLayout.swift`), exposes that wrapped stack view publicly as `stackView` (see Design Decisions), and exposes exactly one mutating method, `addArrangedSubview(_:)`, that forwards to it; the outer `NSView` itself renders nothing. A UIKit port would use `UIStackView` directly (no wrapping `UIView` needed, since `UIStackView` is itself a `UIView`), making this wrapper layer unnecessary on that platform.
- **WinUI 3**: Use a `StackPanel` with `Orientation="Vertical"` and `Spacing` bound to the app's equivalent of the `GroupSpacing` layout token (WinUI's `StackPanel.Spacing` is the direct analog of `NSStackView.spacing` — no manual spacer elements needed, matching the React/Web note above). `StackPanel` has no `IsEnabled`-driven visual states of its own to define in a `VisualStateManager` group, since — like the source — it is a pure layout container with no interactive states (see States). Children are added via `panel.Children.Add(view)`, mirroring `addArrangedSubview(_:)`; because `StackPanel.Children` is already a public property on the framework type itself, a WinUI port gets the equivalent of this source's public `stackView` exposure for free, with no separate wrapper property needed. There is no WinUI equivalent needed for the source's edge-pinning step either, since a `StackPanel` placed directly in its parent (e.g. via `Grid` row/column stretch, or `HorizontalAlignment="Stretch"`/`VerticalAlignment="Stretch"`) already fills its allotted space without the source's separate `pinToEdges` constraint-activation call:
  ```xml
  <StackPanel Orientation="Vertical"
              Spacing="{StaticResource GroupSpacing}"
              HorizontalAlignment="Stretch"
              VerticalAlignment="Stretch"/>
  ```

