---
id: 5e9843b1-cc8d-4048-97e7-21991bf5830c
title: Horizontal Stack View
domain: agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/horizontal-stack-view
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: An AppKit NSView wrapping a horizontal NSStackView for ComposableSettingsWindow,
  pinned flush to all four edges, forwarding addArrangedSubview calls to it.
platforms:
- swift
- macos
tags:
- ui
- stack-view
- macos
- settings
depends-on: []
related:
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/vertical-stack-view
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/divider-view
references: []
approved-by: ''
approved-date: ''
---

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

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders as an invisible layout container, arranging its arranged subviews horizontally with `SettingsLayout.default[.groupSpacing]` spacing between them (see **group-spacing**); there is no other state. |
| Pressed | Not applicable: `HorizontalStackView` sets no target/action, gesture recognizer, or tracking area on itself — it cannot receive or respond to a press. (An arranged subview may itself be pressable; that is the subview's own concern, not this wrapper's.) |
| Disabled | Not applicable: the source never reads or sets `isEnabled` or any dimmed appearance — `HorizontalStackView` has no enabled/disabled concept. |
| Focused | Not applicable: `HorizontalStackView` never overrides `acceptsFirstResponder` and participates in no key view loop — it cannot become focused or show a focus ring. |
| Loading | Not applicable: `HorizontalStackView` performs no asynchronous work and defines no loading indicator. |

## Accessibility

- **Role/trait**: Not applicable — `HorizontalStackView` is a transparent layout container; the source sets no `accessibilityRole`, `accessibilityLabel`, or `isAccessibilityElement` override. It exists only to lay out its arranged subviews, each of which owns its own accessibility properties (and, where relevant, its own recipe).
- **Label requirements**: Not applicable — `HorizontalStackView` renders no text and carries no semantic content of its own to name.
- **Announce state changes**: Not applicable — `HorizontalStackView` defines no state that changes (see States); there is nothing for an announcement to report.
- **Minimum tap target**: Not applicable — `HorizontalStackView` is not an interactive control; the source wires no target/action or gesture recognizer to it, so it has no tap target to size.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| horizontal-stack-view-001 | confines-to-main-actor | Attempt to construct or mutate a `HorizontalStackView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking. This is a static/compile-time check, not one a runtime conformance suite executes. |
| horizontal-stack-view-002 | disables-autoresizing-mask-translation | Any initialized `HorizontalStackView` | `view.translatesAutoresizingMaskIntoConstraints == false` |
| horizontal-stack-view-003 | wraps-a-horizontal-nsstackview | `let stack = view.subviews.first as? NSStackView` on any initialized `HorizontalStackView` (`stackView` is `private`, so this is how a test reaches it) | `stack?.orientation == .horizontal` |
| horizontal-stack-view-004 | group-spacing | `let stack = view.subviews.first as? NSStackView` on any initialized `HorizontalStackView` | `stack?.spacing == SettingsLayout.default[.groupSpacing]` |
| horizontal-stack-view-005 | inner-stack-constraints-only | `let stack = view.subviews.first as? NSStackView` on any initialized `HorizontalStackView` | `stack?.translatesAutoresizingMaskIntoConstraints == false` |
| horizontal-stack-view-006 | adds-stack-view-as-subview | Any initialized `HorizontalStackView` | `view.subviews.first is NSStackView` (the internal stack view is `view`'s only subview) |
| horizontal-stack-view-007 | pins-stack-view-to-container-edges | `let stack = view.subviews.first as? NSStackView` on any initialized `HorizontalStackView`, laid out in a window with a non-zero frame | `stack?.frame` exactly matches `view.bounds` (top/leading/trailing/bottom anchors resolve equal) |
| horizontal-stack-view-008 | ignores-explicit-frame | Construct via `HorizontalStackView(frame: NSRect(x: 10, y: 10, width: 200, height: 50))` | `view.frame == .zero` immediately after `init`, before any layout pass runs |
| horizontal-stack-view-009 | convenience-init-uses-zero-frame | Construct via `HorizontalStackView()` | No crash; behavior identical to `HorizontalStackView(frame: .zero)` |
| horizontal-stack-view-010 | rejects-coder-initializer | Construct via `HorizontalStackView(coder:)` with any `NSCoder` | Execution traps via `fatalError` (any trap message satisfies the requirement; the source's is `init(coder:) has not been implemented`, see Platform Notes) |
| horizontal-stack-view-011 | forwards-added-views-to-inner-stack-view | Construct a `HorizontalStackView`, obtain `let stack = view.subviews.first as? NSStackView`, then call `view.addArrangedSubview(childView)` | `childView` appears in `stack?.arrangedSubviews`, in the order it was added |
| horizontal-stack-view-012 | conforms-to-settings-view-protocol | Any initialized `HorizontalStackView` | `view is SettingsViewProtocol` is `true` |

## Edge Cases

- **Null/empty input**: Not applicable — `addArrangedSubview(_:)`'s parameter is a non-optional `NSView`; Swift's type system rejects a `nil` argument at compile time. The parameterless `convenience init()` and the inherited `init(frame:)` (whose argument is discarded, see **ignores-explicit-frame**) leave no other caller-supplied value that could be null or empty. Calling `addArrangedSubview(_:)` zero times is a valid, un-special-cased path: the internal stack view's `arrangedSubviews` stays empty and the component collapses to whatever intrinsic size an empty `NSStackView` resolves to.
- **Boundary values**: `SettingsLayout.default[.groupSpacing]` (see **group-spacing**) is read exactly once, into `stackView.spacing`, at `init` time. `SettingsLayout` is `Observable`/`@Published`, but `HorizontalStackView` never subscribes to it, so if a caller mutates `SettingsLayout.default`'s underlying value after a `HorizontalStackView` instance already exists, that instance's spacing does not update — it stays at whatever `.groupSpacing` was when it was constructed. This is the same staleness pattern documented for the sibling `DividerView` and `VerticalStackView` wrappers.
- **Concurrent access**: Not applicable — the class is declared `@MainActor`, so construction and every mutation path (`addArrangedSubview`) are serialized to the main actor by the Swift compiler.
- **Error states**: Not applicable — `HorizontalStackView` has no dependency on network, database, or file-system access, and the source shows no error path of any kind.
- **Offline/disconnected state**: Not applicable — `HorizontalStackView` performs no networking.
- **No removal API**: `addArrangedSubview(_:)` is the only mutation entry point the source exposes; there is no `removeArrangedSubview` or equivalent. Once a view is added, the source itself provides no supported way to remove it again through this wrapper — a caller would have to reach the internal stack view's `arrangedSubviews` directly (which it cannot, since `stackView` is `private`) or remove the child view from its superview.

## Configuration

Not applicable: `HorizontalStackView` exposes no caller-configurable options. Its only public initializer is the parameterless `convenience init()`; `init(frame:)` accepts but discards its argument (see **ignores-explicit-frame**), and `init?(coder:)` fatal-errors unconditionally. Orientation and spacing are fixed at construction and are not exposed as settable properties.

## Deep Linking

Not applicable: `HorizontalStackView` is a layout container with no navigable identity of its own — it has no route, screen, or resource that a deep link could target.

## Localization

Not applicable: `HorizontalStackView` renders no text and defines no string keys of its own.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `HorizontalStackView` applies no animation, transition, or motion effect of its own — it assigns layout constraints once, at initialization, with no animator proxy or transition wrapping any of it. |
| Increase Contrast | Not applicable: `HorizontalStackView` is not layer-backed and sets no color of its own; it has no visual surface for Increase Contrast to affect. |
| Differentiate Without Color | Not applicable: `HorizontalStackView` conveys no state or meaning through color — it renders no color at all. |

## Feature Flags

Not applicable: the source contains no feature-flag check; `HorizontalStackView` always constructs and wires itself up unconditionally.

## Analytics

Not applicable: the source emits no analytics, tracking, or telemetry calls, and `HorizontalStackView` has no user interaction of its own to report.

## Privacy

- **Data collected**: None. `HorizontalStackView`'s only stored property is `stackView`, an internal `NSStackView`; it holds no caller-supplied data of its own.
- **Storage**: Not applicable — `HorizontalStackView` performs no persistence of any kind.
- **Transmission**: Not applicable — `HorizontalStackView` performs no network or IPC calls.
- **Retention**: Not applicable — nothing is retained beyond the view instance's own lifetime.

## Logging

Not applicable: the source contains no logging calls (no `os_log`, `Logger`, or `print`).

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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/HorizontalStackView.swift` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | passed | Accessibility |
| [text-expansion-tolerance](agenticdevelopercookbook://compliance/internationalization#text-expansion-tolerance) | passed | Internationalization |
| [rtl-layout-support](agenticdevelopercookbook://compliance/internationalization#rtl-layout-support) | passed | Internationalization |

Notes: separation-of-concerns passes trivially because `HorizontalStackView` contains no business logic to entangle with presentation — it is a single-layer AppKit view that only wraps and pins an `NSStackView`. unit-test-coverage fails because no test file exists for this type (`git ls-files` under this repo turns up only the `HorizontalStackView.swift` source and the unrelated `NSStackView+FullWidth.swift`, no `HorizontalStackViewTests.swift` or equivalent). dynamic-type-support passes because the component sets no min/max size of its own (see Appearance) and is sized entirely by its arranged subviews' intrinsic content size, so a child's text growing under a larger system font size is never fought or clipped by this container. text-expansion-tolerance passes for the same reason: the flush-pinned, unconstrained-size layout accommodates a translated child label expanding without truncation or overflow at this container's own level. rtl-layout-support passes because the component wraps a plain `NSStackView` with `orientation = .horizontal` and adds children only through the standard `addArrangedSubview` API, so it inherits AppKit's native RTL mirroring rather than implementing any custom left/right-sensitive positioning that could get RTL wrong.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: moved private implementation identifiers (`addSubview(_:)`, `Self.pinToEdges(_:of:)`, `stackView.addArrangedSubview(view)`, the `fatalError` message) out of requirements and into Platform Notes; named the `SettingsLayout.default[.groupSpacing]` token everywhere the spacing value is mentioned instead of repeating the literal; shortened two requirement names to subject-only kebab-case; fixed the Design Decisions `**Approved**:` format; listed sibling recipes in `related`; added this Change History table; fixed test vectors to reach the private `stackView` via `view.subviews.first as? NSStackView`, made vector 008 a concrete post-init assertion, and marked vector 001 as a compile-time check; removed an unsupported claim from the WinUI 3 note; cleaned up the Compliance table to cite only checks defined in the compliance catalog |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Compliance section rewritten as linked checks against the compliance catalog |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
