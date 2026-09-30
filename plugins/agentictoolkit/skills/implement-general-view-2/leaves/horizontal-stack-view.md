<!-- leaf: implement-general-view-2/horizontal-stack-view · source: horizontal-stack-view.md -->

**Rules** (cite as `implement-general-view-2/horizontal-stack-view#<slug>`):

- `confines-to-main-actor` MUST
- `disables-autoresizing-mask-translation` MUST
- `wraps-a-horizontal-nsstackview` MUST
- `group-spacing` MUST
- `inner-stack-constraints-only` MUST
- `adds-stack-view-as-subview` MUST
- `pins-stack-view-to-container-edges` MUST
- `ignores-explicit-frame` MUST
- `convenience-init-uses-zero-frame` MUST
- `rejects-coder-initializer` MUST
- `forwards-added-views-to-inner-stack-view` MUST
- `conforms-to-settings-view-protocol` MUST

# Horizontal Stack View

## Overview

`ComposableSettings.HorizontalStackView`, at `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/HorizontalStackView.swift`, is a thin AppKit `NSView` wrapper around a horizontal `NSStackView`, used to arrange a row of sibling views left-to-right within the ComposableSettingsWindow system integration. It is nested in the `ComposableSettings` namespace and conforms to `SettingsViewProtocol`, the marker protocol every settings-row view in this system adopts (its sibling `VerticalStackView` is the vertical counterpart, differing only in orientation and in that its inner stack view is exposed as a public property rather than private). `HorizontalStackView` has no caller-configurable options: its only public initializer is a parameterless `convenience init()`, its inter-item spacing is fixed to `SettingsLayout.default[.groupSpacing]`, and its only other public member is `addArrangedSubview(_:)`, which forwards to the wrapped `NSStackView`.

## Behavioral Requirements

- **confines-to-main-actor**: The component MUST be usable only on the main actor; the class is declared `@MainActor`.
- **disables-autoresizing-mask-translation**: The component MUST set `translatesAutoresizingMaskIntoConstraints = false` on itself.
- **wraps-a-horizontal-nsstackview**: The component MUST construct an internal `NSStackView` with `orientation = .horizontal`.
- **group-spacing**: The component MUST set the internal stack view's `spacing` to `SettingsLayout.default[.groupSpacing]` (20.0pt, per `ViewLayout.swift`'s `SettingsLayout.default` values) at initialization.
- **inner-stack-constraints-only**: The component MUST set `translatesAutoresizingMaskIntoConstraints = false` on the internal stack view.
- **adds-stack-view-as-subview**: The internal stack view MUST be a subview of the component itself (see Platform Notes for how the source wires this).
- **pins-stack-view-to-container-edges**: The component MUST activate constraints pinning the internal stack view's top, leading, trailing, and bottom anchors to the corresponding anchors of the component itself (see Platform Notes for the helper the source uses).
- **ignores-explicit-frame**: The designated initializer, `init(frame frameRect: NSRect)`, MUST discard the caller-supplied `frameRect` and call `super.init(frame: .zero)` unconditionally, regardless of the argument's value.
- **convenience-init-uses-zero-frame**: The public `convenience init()` MUST call `self.init(frame: .zero)`.
- **rejects-coder-initializer**: `required init?(coder: NSCoder)` MUST fatal-error (trap) unconditionally when invoked (see Platform Notes for the source's trap message).
- **forwards-added-views-to-inner-stack-view**: The public `addArrangedSubview(_ view: NSView)` method MUST forward its argument to the internal stack view (see Platform Notes for the call the source uses).
- **conforms-to-settings-view-protocol**: The component MUST conform to `SettingsViewProtocol`.

## Appearance

- **Corner radius**: None; the source never sets `wantsLayer` or `layer?.cornerRadius` — the view is not layer-backed.
- **Padding**: None of its own. The internal stack view is pinned flush to all four edges of the component with zero additional inset (see **pins-stack-view-to-container-edges**); the only spacing the component introduces is the `SettingsLayout.default[.groupSpacing]` gap between arranged subviews (see **group-spacing**).
- **Font**: Not applicable — `HorizontalStackView` renders no text or other font-dependent content of its own.
- **Background**: None; the view is not layer-backed and sets no `layer?.backgroundColor` or `NSColor`-based fill — it is fully transparent, showing whatever sits behind it.
- **Foreground/Text**: Not applicable — `HorizontalStackView` has no text or foreground content; it only positions its arranged subviews.
- **Border**: None; the source never sets `layer?.borderWidth` or `layer?.borderColor`.
- **Shadow**: None; the source never sets any shadow property.
- **Min/Max size**: No explicit min/max width or height constraints of its own. Because the internal stack view is pinned flush to all four edges with zero inset, the component's size is driven entirely by its arranged subviews' intrinsic content sizes plus the `SettingsLayout.default[.groupSpacing]` inter-item spacing (see **group-spacing**).

## Accessibility

- **Role/trait**: Not applicable — `HorizontalStackView` is a transparent layout container; the source sets no `accessibilityRole`, `accessibilityLabel`, or `isAccessibilityElement` override. It exists only to lay out its arranged subviews, each of which owns its own accessibility properties (and, where relevant, its own recipe).
- **Label requirements**: Not applicable — `HorizontalStackView` renders no text and carries no semantic content of its own to name.
- **Announce state changes**: Not applicable — `HorizontalStackView` defines no state that changes (see States); there is nothing for an announcement to report.
- **Minimum tap target**: Not applicable — `HorizontalStackView` is not an interactive control; the source wires no target/action or gesture recognizer to it, so it has no tap target to size.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `HorizontalStackView` applies no animation, transition, or motion effect of its own — it assigns layout constraints once, at initialization, with no animator proxy or transition wrapping any of it. |
| Increase Contrast | Not applicable: `HorizontalStackView` is not layer-backed and sets no color of its own; it has no visual surface for Increase Contrast to affect. |
| Differentiate Without Color | Not applicable: `HorizontalStackView` conveys no state or meaning through color — it renders no color at all. |

## Privacy

- **Data collected**: None. `HorizontalStackView`'s only stored property is `stackView`, an internal `NSStackView`; it holds no caller-supplied data of its own.
- **Storage**: Not applicable — `HorizontalStackView` performs no persistence of any kind.
- **Transmission**: Not applicable — `HorizontalStackView` performs no network or IPC calls.
- **Retention**: Not applicable — nothing is retained beyond the view instance's own lifetime.

## Platform Notes

- **SwiftUI**: `HStack(spacing:)` is the direct equivalent, with `spacing` sourced from the equivalent of `SettingsLayout.default[.groupSpacing]`. Unlike this AppKit type, which takes children imperatively via repeated `addArrangedSubview(_:)` calls after construction, an `HStack` takes its children declaratively as trailing-closure content at the call site — there is no separate "add a child later" step to port.
- **Compose**: `Row(horizontalArrangement = Arrangement.spacedBy(...))`, with the spacing value sourced from the equivalent of the `groupSpacing` token. As with SwiftUI, Compose children are declared inline rather than appended imperatively after construction, so a port drops the `addArrangedSubview`-style API entirely.
- **React/Web**: A `<div>` with `display: flex; flex-direction: row; gap: <groupSpacing>px;` (a CSS Flexbox row). The `gap` property supplies the equivalent of `NSStackView.spacing` directly, with no manual spacer elements needed; children are ordinary DOM children in document order, corresponding to the order arranged subviews are added.
- **AppKit / UIKit (source)**: `HorizontalStackView.swift` (`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/HorizontalStackView.swift`) is macOS-only (`import AppKit`) — there is no iOS/UIKit counterpart in this file. It constructs a single `NSStackView` (`orientation = .horizontal`), adds it via `addSubview(_:)`, then pins it to all four edges of the outer `NSView` via `Self.pinToEdges(_:of:)` (`ViewLayout.swift`), and exposes exactly one mutating method, `addArrangedSubview(_:)`, that forwards to the wrapped stack view via `stackView.addArrangedSubview(view)`; the outer `NSView` itself renders nothing. `init?(coder:)` traps with the message `init(coder:) has not been implemented`. A UIKit port would use `UIStackView` directly (no wrapping `UIView` needed, since `UIStackView` is itself a `UIView`), making this wrapper layer unnecessary on that platform.
- **WinUI 3**: Use a `StackPanel` with `Orientation="Horizontal"` and `Spacing` bound to the app's equivalent of the `GroupSpacing` layout token (WinUI's `StackPanel.Spacing` is the direct analog of `NSStackView.spacing` — no manual spacer elements needed, matching the React/Web note above). `StackPanel` has no `IsEnabled`-driven visual states of its own to define in a `VisualStateManager` group, since — like the source — it is a pure layout container with no interactive states (see States). Children are added via `panel.Children.Add(view)`, mirroring `addArrangedSubview(_:)`; there is no WinUI equivalent needed for the source's edge-pinning step, since a `StackPanel` placed directly in its parent (e.g. via `Grid` row/column stretch, or `HorizontalAlignment="Stretch"`/`VerticalAlignment="Stretch"`) already fills its allotted space without the source's separate `pinToEdges` constraint-activation call:
  ```xml
  <StackPanel Orientation="Horizontal"
              Spacing="{StaticResource GroupSpacing}"
              HorizontalAlignment="Stretch"
              VerticalAlignment="Stretch"/>
  ```

## Design Decisions

**Decision**: `init(frame frameRect: NSRect)` discards its `frameRect` argument and always calls `super.init(frame: .zero)`.
**Rationale**: `HorizontalStackView` positions itself entirely through Auto Layout (`translatesAutoresizingMaskIntoConstraints = false` plus the activated edge-pinning constraints). The inherited frame-based initializer exists only so the type can still be constructed through it at all; the source ignores the caller-supplied rect rather than reconciling it with the Auto Layout constraints that take over immediately afterward. This is the same pattern used by the sibling `VerticalStackView` and `DividerView`.
**Approved**: pending

**Decision**: `addArrangedSubview(_:)` is the only public mutation entry point; no counterpart for removing an arranged subview is exposed.
**Rationale**: Not explained in source comments. This is consistent with the ComposableSettingsWindow pattern of assembling a settings row or panel once, at construction time, rather than mutating it afterward. Recorded here as a known limitation of the public API rather than an intended, documented contract, since nothing in the source states it was deliberate.
**Approved**: pending

**Decision**: `stackView` is declared `private`, unlike the otherwise structurally identical `VerticalStackView`, whose `stackView` property is `public`.
**Rationale**: Not explained in source comments. This is a genuine asymmetry between the two sibling wrappers: a caller of `HorizontalStackView` cannot reach the internal `NSStackView` to reconfigure it (e.g. alignment or distribution) or to remove an arranged subview directly, while a caller of `VerticalStackView` can. Recorded here rather than smoothed over, since the two types would otherwise read as interchangeable except for orientation.
**Approved**: pending
