---
id: 5e9843b1-cc8d-4048-97e7-21991bf5830c
title: Horizontal Stack View
domain: agentictoolkit://cookbook/ui/settings/layout/horizontal-stack-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A thin wrapper view that arranges a row of sibling views left-to-right
  in a settings layout, pinned flush to all four edges, forwarding added-view
  calls to its internal horizontal stack.
platforms:
- swift
- macos
tags:
- ui
- stack-view
- settings
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/layout/vertical-stack-view
- agentictoolkit://cookbook/ui/settings/layout/divider-view
references: []
approved-by: ''
approved-date: ''
---

# Horizontal Stack View

## Overview

The Horizontal Stack View is a thin wrapper used to arrange a row of
sibling views left-to-right within a settings layout. It fulfills the same
settings-row-view contract as its siblings in this system; the sibling
Vertical Stack View recipe is its vertical counterpart, differing only in
orientation and in that its inner stack is exposed as a public property
rather than kept private. The Horizontal Stack View has no
caller-configurable options: it takes no construction parameters, its
inter-item spacing is fixed to the standard group-spacing value, and its
only other public operation adds a view to the arranged row.

## Behavioral Requirements

- **confines-to-ui-thread**: The component MUST be usable only on the UI
  thread.
- **arranges-children-horizontally**: The component MUST arrange its
  children in a horizontal row.
- **group-spacing**: The component MUST set the spacing between arranged
  children to the standard group-spacing value (20.0pt) at initialization.
- **adds-stack-view-as-subview**: The internal stack view MUST be a child
  of the component itself (see Platform Notes for how the source wires
  this).
- **pins-stack-view-to-container-edges**: The component MUST activate
  constraints pinning the internal stack view's top, leading, trailing,
  and bottom edges to the component's corresponding edges (see Platform
  Notes for the helper the source uses).
- **rejects-deserializing-construction**: A deserializing/decoding-based
  construction path MUST NOT produce a usable instance; it MUST trap or
  fail instead (see Platform Notes for the source's trap message).
- **forwards-added-views-to-inner-stack-view**: The component's public
  add-view operation MUST forward its argument to the internal stack view
  (see Platform Notes for the call the source uses).

## Appearance

- **Corner radius**: None; the component has no layer or shape of its own.
- **Padding**: None of its own. The internal stack view is pinned flush to
  all four edges of the component with zero additional inset (see
  **pins-stack-view-to-container-edges**); the only spacing the component
  introduces is the group-spacing gap between arranged children (see
  **group-spacing**).
- **Font**: Not applicable — the component renders no text or other
  font-dependent content of its own.
- **Background**: None; the component sets no fill of its own — it is
  fully transparent, showing whatever sits behind it.
- **Foreground/Text**: Not applicable — the component has no text or
  foreground content; it only positions its arranged children.
- **Border**: None; the component draws no border of its own.
- **Shadow**: None; the component sets no shadow of its own.
- **Min/Max size**: No explicit min/max width or height constraints of its
  own. Because the internal stack view is pinned flush to all four edges
  with zero inset, the component's size is driven entirely by its arranged
  children's intrinsic content sizes plus the group-spacing gap between
  them (see **group-spacing**).

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders as an invisible layout container, arranging its arranged children horizontally with group-spacing between them (see **group-spacing**); there is no other state. |
| Pressed | Not applicable: the component sets no target/action, gesture recognizer, or tracking area on itself — it cannot receive or respond to a press. (An arranged child may itself be pressable; that is the child's own concern, not this wrapper's.) |
| Disabled | Not applicable: the source never reads or sets an enabled state or any dimmed appearance — the component has no enabled/disabled concept. |
| Focused | Not applicable: the component never accepts keyboard focus and participates in no focus/key-view loop — it cannot become focused or show a focus ring. |
| Loading | Not applicable: the component performs no asynchronous work and defines no loading indicator. |

## Accessibility

- **Role/trait**: Not applicable — the component is a transparent layout
  container; the source sets no accessibility role, label, or
  element-visibility override. It exists only to lay out its arranged
  children, each of which owns its own accessibility properties (and,
  where relevant, its own recipe).
- **Label requirements**: Not applicable — the component renders no text
  and carries no semantic content of its own to name.
- **Announce state changes**: Not applicable — the component defines no
  state that changes (see States); there is nothing for an announcement to
  report.
- **Minimum tap target**: Not applicable — the component is not an
  interactive control; the source wires no target/action or gesture
  recognizer to it, so it has no tap target to size.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| horizontal-stack-view-001 | confines-to-ui-thread | Attempt to construct or mutate the component from off the UI thread | Rejected by the platform's UI-thread confinement enforcement (compile-time on platforms with static isolation checking such as Swift's `@MainActor`, runtime-checked otherwise). This is a static/compile-time check on such platforms, not one a runtime conformance suite executes. |
| horizontal-stack-view-003 | arranges-children-horizontally | Inspect the internal stack view of any initialized component | Its orientation is horizontal |
| horizontal-stack-view-004 | group-spacing | Inspect the internal stack view of any initialized component | Its spacing equals the standard group-spacing value (20.0pt) |
| horizontal-stack-view-006 | adds-stack-view-as-subview | Any initialized component | The internal stack view is the component's only child |
| horizontal-stack-view-007 | pins-stack-view-to-container-edges | Inspect the internal stack view of any initialized component, laid out in a container with a non-zero frame | The stack view's resolved bounds exactly match the component's bounds (top/leading/trailing/bottom edges resolve equal) |
| horizontal-stack-view-010 | rejects-deserializing-construction | Attempt to construct the component via a deserializing/decoding-based construction path | Construction traps or fails; no usable instance is produced (any trap message satisfies the requirement; the source's is `init(coder:) has not been implemented`, see Platform Notes) |
| horizontal-stack-view-011 | forwards-added-views-to-inner-stack-view | Construct the component, obtain its internal stack view, then add a child view through the component's public add-view operation | The child view appears among the internal stack view's arranged children, in the order it was added |

Three implementation-only construction-rule checks (disabling autoresizing-
mask translation on the component and its internal stack view, discarding
an explicit frame at construction, and the parameterless constructor's
use of a zero frame) and the platform's marker-interface conformance are
framework mechanics rather than portable behavior; see Platform Notes for how the source verifies them there.

## Edge Cases

- **Null/empty input**: Not applicable — the add-view operation's parameter
  is a non-optional view; the type system rejects a missing argument at
  compile time. The parameterless construction path and the frame-based
  construction path (whose argument is discarded, see Platform Notes) leave no other caller-supplied value that could be null or
  empty. Calling the add-view operation zero times is a valid,
  un-special-cased path: the internal stack view's arranged children stay
  empty and the component collapses to whatever intrinsic size an empty
  stack view resolves to.
- **Boundary values**: The standard group-spacing value (see
  **group-spacing**) is read exactly once, into the internal stack view's
  spacing property, at construction time. The settings-layout constants are
  observable for change, but the component never subscribes to updates, so
  if a caller mutates the underlying value after a component instance
  already exists, that instance's spacing does not update — it stays at
  whatever the group-spacing value was when it was constructed. This is the
  same staleness pattern documented for the sibling Divider View and
  Vertical Stack View wrappers.
- **Concurrent access**: Not applicable — the component is confined to the
  UI thread, so construction and every mutation path (adding a child) are
  serialized to that thread.
- **Error states**: Not applicable — the component has no dependency on
  network, database, or file-system access, and the source shows no error
  path of any kind.
- **Offline/disconnected state**: Not applicable — the component performs
  no networking.
- **No removal API**: Adding a view is the only mutation entry point the
  source exposes; there is no corresponding operation for removing an
  arranged child. Once a view is added, the source itself provides no
  supported way to remove it again through this wrapper — a caller cannot
  reach the internal stack view's arranged children directly, since it is
  not exposed, and would instead have to remove the child view from its
  parent directly.

## Configuration

Not applicable: the component exposes no caller-configurable options. It
takes no construction parameters; a frame-based construction path accepts
but discards its argument (see Platform Notes), and a
deserializing/decoding-based construction path fails unconditionally.
Orientation and spacing are fixed at construction and are not exposed as
settable properties.

## Deep Linking

Not applicable: the component is a layout container with no navigable
identity of its own — it has no route, screen, or resource that a deep
link could target.

## Localization

Not applicable: the component renders no text and defines no string keys
of its own.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the component applies no animation, transition, or motion effect of its own — it assigns its layout once, at initialization, with no animation wrapping any of it. |
| Increase Contrast | Not applicable: the component has no layer and sets no color of its own; it has no visual surface for Increase Contrast to affect. |
| Differentiate Without Color | Not applicable: the component conveys no state or meaning through color — it renders no color at all. |

## Feature Flags

Not applicable: the source contains no feature-flag check; the component
always constructs and wires itself up unconditionally.

## Analytics

Not applicable: the source emits no analytics, tracking, or telemetry
calls, and the component has no user interaction of its own to report.

## Privacy

- **Data collected**: None. The component's only stored property is its
  internal stack view; it holds no caller-supplied data of its own.
- **Storage**: Not applicable — the component performs no persistence of
  any kind.
- **Transmission**: Not applicable — the component performs no network or
  IPC calls.
- **Retention**: Not applicable — nothing is retained beyond the
  component's own lifetime.

## Logging

Not applicable: the source contains no logging calls.

## Platform Notes

- **SwiftUI**: `HStack(spacing:)` is the direct equivalent, with `spacing` sourced from the equivalent of the group-spacing token. Unlike this AppKit type, which takes children imperatively via repeated add-view calls after construction, an `HStack` takes its children declaratively as trailing-closure content at the call site — there is no separate "add a child later" step to port.
- **Compose**: `Row(horizontalArrangement = Arrangement.spacedBy(...))`, with the spacing value sourced from the equivalent of the `groupSpacing` token. As with SwiftUI, Compose children are declared inline rather than appended imperatively after construction, so a port drops the imperative add-view-style API entirely.
- **React/Web**: A `<div>` with `display: flex; flex-direction: row; gap: <groupSpacing>px;` (a CSS Flexbox row). The `gap` property supplies the equivalent of the stack's spacing directly, with no manual spacer elements needed; children are ordinary DOM children in document order, corresponding to the order arranged children are added.
- **AppKit / UIKit (source)**: `HorizontalStackView.swift` (`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/HorizontalStackView.swift`) is macOS-only (`import AppKit`) — there is no iOS/UIKit counterpart in this file. It is nested in the `ComposableSettings` namespace and conforms to `SettingsViewProtocol`, a marker protocol with no requirements of its own that every settings-row view in this system adopts. It constructs a single `NSStackView` (`orientation = .horizontal`), sets `translatesAutoresizingMaskIntoConstraints = false` on both itself and that internal stack view, adds the stack view via `addSubview(_:)`, then pins it to all four edges of the outer `NSView` via `Self.pinToEdges(_:of:)` (`ViewLayout.swift`), and exposes exactly one mutating method, `addArrangedSubview(_:)`, that forwards to the wrapped stack view via `stackView.addArrangedSubview(view)`; the outer `NSView` itself renders nothing. The designated `init(frame frameRect: NSRect)` initializer discards its `frameRect` argument and always calls `super.init(frame: .zero)`, since the component positions itself entirely through the constraints described above; the public parameterless `convenience init()` calls `self.init(frame: .zero)`. `init?(coder:)` traps with the message `init(coder:) has not been implemented`, satisfying `rejects-deserializing-construction`. A UIKit port would use `UIStackView` directly (no wrapping `UIView` needed, since `UIStackView` is itself a `UIView`), making this wrapper layer unnecessary on that platform.
- **WinUI 3**: Use a `StackPanel` with `Orientation="Horizontal"` and `Spacing` bound to the app's equivalent of the `GroupSpacing` layout token (WinUI's `StackPanel.Spacing` is the direct analog of `NSStackView.spacing` — no manual spacer elements needed, matching the React/Web note above). `StackPanel` has no `IsEnabled`-driven visual states of its own to define in a `VisualStateManager` group, since — like the source — it is a pure layout container with no interactive states (see States). Children are added via `panel.Children.Add(view)`, mirroring the add-view operation; there is no WinUI equivalent needed for the source's edge-pinning step, since a `StackPanel` placed directly in its parent (e.g. via `Grid` row/column stretch, or `HorizontalAlignment="Stretch"`/`VerticalAlignment="Stretch"`) already fills its allotted space without the source's separate `pinToEdges` constraint-activation call:
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

**Decision** (AppKit): `init(frame frameRect: NSRect)` discards its
`frameRect` argument and always calls `super.init(frame: .zero)`.
**Rationale**: The component positions itself entirely through Auto Layout (`translatesAutoresizingMaskIntoConstraints = false` plus the activated edge-pinning constraints). The inherited frame-based initializer exists only so the type can still be constructed through it at all; the source ignores the caller-supplied rect rather than reconciling it with the Auto Layout constraints that take over immediately afterward. This is the same pattern used by the sibling `VerticalStackView` and `DividerView`.
**Approved**: pending

**Decision**: The add-view operation is the only public mutation entry
point; no counterpart for removing an arranged child is exposed.
**Rationale**: Not explained in source comments. This is consistent with the ComposableSettingsWindow pattern of assembling a settings row or panel once, at construction time, rather than mutating it afterward. Recorded here as a known limitation of the public API rather than an intended, documented contract, since nothing in the source states it was deliberate.
**Approved**: pending

**Decision** (AppKit): `stackView` is declared `private`, unlike the
otherwise structurally identical `VerticalStackView`, whose `stackView`
property is `public`.
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
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/layout/. |
