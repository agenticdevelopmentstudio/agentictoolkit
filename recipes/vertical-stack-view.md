---
id: 765b853f-36a2-4e4f-b8aa-2cd15714a67f
title: Vertical Stack View
domain: agentictoolkit://recipes/vertical-stack-view
type: ingredient
version: 1.1.1
status: review
language: en
created: 2026-09-23
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AppKit NSView wrapping a vertical NSStackView for ComposableSettingsWindow, pinned to all edges.
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
- agentictoolkit://recipes/horizontal-stack-view
references: []
approved-by: ''
approved-date: ''
---

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

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders as an invisible layout container, arranging its arranged subviews vertically with the spacing set from `SettingsLayout.default[.groupSpacing]` (see **sets-arranged-subview-spacing-from-group-spacing-token**); there is no other state. |
| Pressed | Not applicable: `VerticalStackView` sets no target/action, gesture recognizer, or tracking area on itself — it cannot receive or respond to a press. (An arranged subview may itself be pressable; that is the subview's own concern, not this wrapper's.) |
| Disabled | Not applicable: the source never reads or sets `isEnabled` or any dimmed appearance — `VerticalStackView` has no enabled/disabled concept. |
| Focused | Not applicable: `VerticalStackView` never overrides `acceptsFirstResponder` and participates in no key view loop — it cannot become focused or show a focus ring. |
| Loading | Not applicable: `VerticalStackView` performs no asynchronous work and defines no loading indicator. |

## Accessibility

- **Role/trait**: Not applicable — `VerticalStackView` is a transparent layout container; the source sets no `accessibilityRole`, `accessibilityLabel`, or `isAccessibilityElement` override. It exists only to lay out its arranged subviews, each of which owns its own accessibility properties (and, where relevant, its own recipe).
- **Label requirements**: Not applicable — `VerticalStackView` renders no text and carries no semantic content of its own to name.
- **Announce state changes**: Not applicable — `VerticalStackView` defines no state that changes (see States); there is nothing for an announcement to report.
- **Minimum tap target**: Not applicable — `VerticalStackView` is not an interactive control; the source wires no target/action or gesture recognizer to it, so it has no tap target to size.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| vertical-stack-view-001 | confines-to-main-actor | Static check (not a runtime test): inspect the `VerticalStackView` class declaration | `class VerticalStackView` carries the `@MainActor` attribute, which the Swift compiler then enforces at compile time for every construct/mutate call from off the main actor |
| vertical-stack-view-002 | disables-autoresizing-mask-translation | Any initialized `VerticalStackView` | `view.translatesAutoresizingMaskIntoConstraints == false` |
| vertical-stack-view-003 | wraps-a-vertical-nsstackview | Any initialized `VerticalStackView` | `view.stackView.orientation == .vertical` |
| vertical-stack-view-004 | sets-arranged-subview-spacing-from-group-spacing-token | Any initialized `VerticalStackView` | `view.stackView.spacing == SettingsLayout.default[.groupSpacing]` |
| vertical-stack-view-005 | disables-autoresizing-mask-translation-on-inner-stack-view | Any initialized `VerticalStackView` | `view.stackView.translatesAutoresizingMaskIntoConstraints == false` |
| vertical-stack-view-006 | adds-stack-view-as-subview | Any initialized `VerticalStackView` | `view.stackView` is present in `view.subviews` |
| vertical-stack-view-007 | pins-stack-view-to-container-edges | Any initialized `VerticalStackView`, laid out in a window with a non-zero frame | `view.constraints` contains four active constraints linking `view.stackView`'s top/leading/trailing/bottom anchors to the corresponding anchors of `view`, and (after layout) `view.stackView`'s frame exactly matches `view.bounds` |
| vertical-stack-view-008 | exposes-stack-view-as-public-property | From outside the type, read `view.stackView` | The property compiles and is accessible (public access level), and returns the same `NSStackView` instance that `addArrangedSubview(_:)` forwards to |
| vertical-stack-view-009 | ignores-explicit-frame | Construct via `VerticalStackView(frame: NSRect(x: 10, y: 10, width: 200, height: 50))` | `view.frame == .zero` immediately after `init(frame:)` returns, before any layout pass runs |
| vertical-stack-view-010 | convenience-init-uses-zero-frame | Construct via `VerticalStackView()` | No crash; behavior identical to `VerticalStackView(frame: .zero)` |
| vertical-stack-view-011 | rejects-coder-initializer | Construct via `VerticalStackView(coder:)` with any `NSCoder` | Execution traps via `fatalError` with message `init(coder:) has not been implemented` |
| vertical-stack-view-012 | forwards-added-views-to-inner-stack-view | Construct a `VerticalStackView`, then call `addArrangedSubview(childView)` | `childView` appears in `view.stackView.arrangedSubviews`, in the order it was added |
| vertical-stack-view-013 | conforms-to-settings-view-protocol | Any initialized `VerticalStackView` | `view is SettingsViewProtocol` is `true` |

## Edge Cases

- **Null/empty input**: Not applicable — `addArrangedSubview(_:)`'s parameter is a non-optional `NSView`; Swift's type system rejects a `nil` argument at compile time. The parameterless `convenience init()` and the inherited `init(frame:)` (whose argument is discarded, see **ignores-explicit-frame**) leave no other caller-supplied value that could be null or empty. Calling `addArrangedSubview(_:)` zero times is a valid, un-special-cased path: `stackView.arrangedSubviews` stays empty and the component collapses to whatever intrinsic size an empty `NSStackView` resolves to.
- **Boundary values**: `SettingsLayout.default[.groupSpacing]` is read exactly once, into `stackView.spacing`, at `init` time (see **sets-arranged-subview-spacing-from-group-spacing-token**). `SettingsLayout` conforms to `Observable` and its backing `values` dictionary is `@Published` (`ViewLayout.swift` and `:39`), but `VerticalStackView` never subscribes to it, so if a caller mutates `SettingsLayout.default`'s underlying value after a `VerticalStackView` instance already exists, that instance's spacing does not update — it stays at whatever `.groupSpacing` was when it was constructed. This is the same staleness pattern documented for the sibling `DividerView` and `HorizontalStackView` wrappers.
- **Concurrent access**: Not applicable — the class is declared `@MainActor`, so construction and every mutation path (`addArrangedSubview`, or direct manipulation of the exposed `stackView`) are serialized to the main actor by the Swift compiler.
- **Error states**: Not applicable — `VerticalStackView` has no dependency on network, database, or file-system access, and the source shows no error path of any kind.
- **Offline/disconnected state**: Not applicable — `VerticalStackView` performs no networking.
- **No dedicated removal API, but the internal stack view is directly reachable**: `addArrangedSubview(_:)` is the only mutation method the source exposes; there is no `removeArrangedSubview` or equivalent method on `VerticalStackView` itself. Because `stackView` is public (see Design Decisions), a caller CAN reach the internal `NSStackView` directly and call its own `removeArrangedSubview(_:)`, reorder `arrangedSubviews`, or change `alignment`/`distribution` without going through this wrapper's API.

## Configuration

Not applicable: `VerticalStackView` exposes no caller-configurable options through its own initializer or setters. Its only public initializer is the parameterless `convenience init()`; `init(frame:)` accepts but discards its argument (see **ignores-explicit-frame**), and `init?(coder:)` fatal-errors unconditionally. Orientation and spacing are fixed at construction and are not exposed as settable properties on `VerticalStackView` itself. The public `stackView` property (see **exposes-stack-view-as-public-property**) does let a caller reconfigure the wrapped `NSStackView` directly after construction (see Design Decisions) — but this is a consequence of that property's access level, not a formal configuration option this component defines.

## Deep Linking

Not applicable: `VerticalStackView` is a layout container with no navigable identity of its own — it has no route, screen, or resource that a deep link could target.

## Localization

Not applicable: `VerticalStackView` renders no text and defines no string keys of its own.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `VerticalStackView` applies no animation, transition, or motion effect of its own — it assigns layout constraints once, at initialization, with no animator proxy or transition wrapping any of it. |
| Increase Contrast | Not applicable: `VerticalStackView` is not layer-backed and sets no color of its own; it has no visual surface for Increase Contrast to affect. |
| Differentiate Without Color | Not applicable: `VerticalStackView` conveys no state or meaning through color — it renders no color at all. |

## Feature Flags

Not applicable: the source contains no feature-flag check; `VerticalStackView` always constructs and wires itself up unconditionally.

## Analytics

Not applicable: the source emits no analytics, tracking, or telemetry calls, and `VerticalStackView` has no user interaction of its own to report.

## Privacy

- **Data collected**: None. `VerticalStackView`'s only stored property is the public `stackView`, an `NSStackView`; it holds no caller-supplied data of its own.
- **Storage**: Not applicable — `VerticalStackView` performs no persistence of any kind.
- **Transmission**: Not applicable — `VerticalStackView` performs no network or IPC calls.
- **Retention**: Not applicable — nothing is retained beyond the view instance's own lifetime.

## Logging

Not applicable: the source contains no logging calls (no `os_log`, `Logger`, or `print`).

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

## Design Decisions

**Decision**: `init(frame frameRect: NSRect)` discards its `frameRect` argument and always calls `super.init(frame: .zero)`.
**Rationale**: `VerticalStackView` positions itself entirely through Auto Layout (`translatesAutoresizingMaskIntoConstraints = false` plus the activated edge-pinning constraints). The inherited frame-based initializer exists only so the type can still be constructed through it at all; the source ignores the caller-supplied rect rather than reconciling it with the Auto Layout constraints that take over immediately afterward. This is the same pattern used by the sibling `HorizontalStackView` and `DividerView`, so a port SHOULD keep discarding the caller's rect for parity with those siblings rather than reconcile it with the constraints that immediately override it (see **ignores-explicit-frame**).
**Approved**: pending

**Decision**: `stackView` is declared `public`, unlike the otherwise structurally identical `HorizontalStackView`, whose `stackView` property is `private`.
**Rationale**: Not explained in source comments. This is a genuine asymmetry between the two sibling wrappers: a caller of `VerticalStackView` can reach the internal `NSStackView` to reconfigure it (e.g. alignment or distribution) or to remove an arranged subview directly, while a caller of `HorizontalStackView` cannot. Recorded here rather than smoothed over, since the two types would otherwise read as interchangeable except for orientation.
**Approved**: pending

**Decision**: `addArrangedSubview(_:)` is the only mutation method the source defines; no counterpart method for removing an arranged subview is exposed (though, unlike `HorizontalStackView`, the public `stackView` property gives a caller an indirect path to one).
**Rationale**: Not explained in source comments. This is consistent with the ComposableSettingsWindow pattern of assembling a settings row or panel once, at construction time, rather than mutating it afterward. Recorded here as a known limitation of the public method surface rather than an intended, documented contract, since nothing in the source states it was deliberate.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | passed | Accessibility |
| [text-expansion-tolerance](agenticdevelopercookbook://compliance/internationalization#text-expansion-tolerance) | passed | Internationalization |

Notes: separation-of-concerns passes trivially because `VerticalStackView`, like its horizontal sibling, contains no business logic — it only wraps and pins an `NSStackView` and forwards one method call. unit-test-coverage fails because no test file exists for this type (`git ls-files` under this repo shows no `VerticalStackViewTests.swift` or equivalent). dynamic-type-support passes because the component sets no min/max size of its own and is sized entirely by its arranged subviews' intrinsic content size (see Appearance), so a child's text growing under a larger system font size is never fought or clipped by this container. text-expansion-tolerance passes for the same reason: the flush-pinned, unconstrained-size layout accommodates a translated child label expanding without truncation or overflow at this container's own level.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: downgraded ignores-explicit-frame to SHOULD with a strengthened Design Decision rationale; deduped the repeated stackView-visibility note into Design Decisions with cross-references elsewhere; replaced the repeated 20.0pt literal with the groupSpacing token reference in Appearance, States, Edge Cases, and test vector 004; added the missing 1.0.0 Change History row; fixed the Design Decisions `**Approved**:` formatting; shortened the summary; unquoted the created/modified dates; removed a stray WinUI 3 sentence; made test vectors 001, 007, and 009 independently checkable; cited SettingsLayout's Observable/@Published declaration in Edge Cases; cleaned up the Compliance table to cite only catalog checks |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Compliance section rewritten as linked checks against the compliance catalog |
