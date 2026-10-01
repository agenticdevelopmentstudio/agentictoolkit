---
id: 765b853f-36a2-4e4f-b8aa-2cd15714a67f
title: Vertical Stack View
domain: agentictoolkit://cookbook/ui/settings/layout/vertical-stack-view
type: ingredient
version: 1.2.0
status: review
language: en
created: 2026-09-23
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A thin wrapper view arranging a column of sibling views
  top-to-bottom in a settings layout, pinned flush to all four edges,
  forwarding added-view calls to its internal vertical stack.
platforms:
- swift
- macos
tags:
- ui
- stack-view
- settings
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/layout/horizontal-stack-view
references: []
approved-by: ''
approved-date: ''
---

# Vertical Stack View

## Overview

This component is a thin wrapper view around an internal vertical stack,
used to arrange a column of sibling views top-to-bottom within a settings
layout. It conforms to the same marker role every settings-row view in
this system adopts (its sibling horizontal stack view is the horizontal
counterpart, differing only in orientation and in whether its internal
stack is reachable by callers — see Design Decisions). The component has
no caller-configurable options: its only public constructor takes no
parameters, its inter-item spacing is fixed to the standard group-spacing
value, its internal stack view is exposed as a public, read-only
property, and its only other public member is an add-arranged-view
operation, which forwards to that same internal stack view.

## Behavioral Requirements

- **confines-to-ui-thread**: The component MUST be usable only on the UI
  thread.
- **arranges-children-vertically**: The component MUST construct an
  internal stack oriented vertically.
- **sets-arranged-subview-spacing-from-group-spacing-token**: The
  component MUST set the internal stack's spacing to the standard
  group-spacing value (20.0pt) at construction.
- **adds-stack-view-as-subview**: The component MUST add the internal
  stack view to itself as a child view.
- **pins-stack-view-to-container-edges**: The component MUST activate
  constraints pinning the internal stack view's top, leading, trailing,
  and bottom edges to the corresponding edges of the component itself.
- **exposes-stack-view-as-public-property**: The component MUST expose
  its internal stack view as a public, read-only property.
- **rejects-deserializing-construction**: A deserializing/decoding-based
  construction path MUST fail with the message `init(coder:) has not been
  implemented`.
- **forwards-added-views-to-inner-stack-view**: The add-arranged-view
  operation MUST forward its argument to the internal stack view.

## Appearance

- **Corner radius**: None; the component is not given a compositing
  layer or a corner radius of its own.
- **Padding**: None of its own. The internal stack view is pinned flush
  to all four edges of the component with zero additional inset (see
  **pins-stack-view-to-container-edges**); the only spacing the component
  introduces is the gap between arranged subviews set from the standard
  group-spacing value (see **sets-arranged-subview-spacing-from-group-spacing-token**).
- **Font**: Not applicable — the component renders no text or other
  font-dependent content of its own.
- **Background**: None; the component paints no background color of its
  own — it is fully transparent, showing whatever sits behind it.
- **Foreground/Text**: Not applicable — the component has no text or
  foreground content; it only positions its arranged subviews.
- **Border**: None; the component draws no border of its own.
- **Shadow**: None; the component draws no shadow of its own.
- **Min/Max size**: No explicit min/max width or height constraints of
  its own. Because the internal stack view is pinned flush to all four
  edges with zero inset, the component's size is driven entirely by its
  arranged subviews' natural content sizes plus the inter-item spacing
  (see **sets-arranged-subview-spacing-from-group-spacing-token**).

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders as an invisible layout container, arranging its arranged subviews vertically with the spacing set from the standard group-spacing value (see **sets-arranged-subview-spacing-from-group-spacing-token**); there is no other state. |
| Pressed | Not applicable: the component sets no target/action, gesture recognizer, or tracking area on itself — it cannot receive or respond to a press. (An arranged subview may itself be pressable; that is the subview's own concern, not this wrapper's.) |
| Disabled | Not applicable: the component never reads or sets an enabled state or any dimmed appearance — it has no enabled/disabled concept. |
| Focused | Not applicable: the component never accepts keyboard focus and participates in no key view loop — it cannot become focused or show a focus ring. |
| Loading | Not applicable: the component performs no asynchronous work and defines no loading indicator. |

## Accessibility

- **Role/trait**: Not applicable — the component is a transparent layout
  container; it sets no accessibility role, label, or element override of
  its own. It exists only to lay out its arranged subviews, each of which
  owns its own accessibility properties (and, where relevant, its own
  recipe).
- **Label requirements**: Not applicable — the component renders no text
  and carries no semantic content of its own to name.
- **Announce state changes**: Not applicable — the component defines no
  state that changes (see States); there is nothing for an announcement
  to report.
- **Minimum tap target**: Not applicable — the component is not an
  interactive control; it wires no target/action or gesture recognizer to
  itself, so it has no tap target to size.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| vertical-stack-view-001 | confines-to-ui-thread | (Static/compile-time check) Attempt to construct or mutate the component from off the UI thread | Rejected by the platform's UI-thread confinement enforcement (compile-time on platforms with static isolation checking, runtime-checked otherwise) |
| vertical-stack-view-003 | arranges-children-vertically | Any initialized component | The internal stack's orientation is vertical |
| vertical-stack-view-004 | sets-arranged-subview-spacing-from-group-spacing-token | Any initialized component | The internal stack's spacing equals the standard group-spacing value |
| vertical-stack-view-006 | adds-stack-view-as-subview | Any initialized component | The internal stack view is present among the component's child views |
| vertical-stack-view-007 | pins-stack-view-to-container-edges | Any initialized component, laid out in a window with a non-zero frame | Active constraints link the internal stack view's top/leading/trailing/bottom edges to the corresponding edges of the component, and (after layout) the internal stack view's frame exactly matches the component's bounds |
| vertical-stack-view-008 | exposes-stack-view-as-public-property | From outside the type, read the exposed stack-view property | The property is accessible, and returns the same internal stack-view instance the add-arranged-view operation forwards to |
| vertical-stack-view-009 | see Design Decisions | Construct via the frame-accepting initializer with an explicit non-zero frame | The resulting view's frame is zero, immediately after construction, before any layout pass runs |
| vertical-stack-view-011 | rejects-deserializing-construction | Attempt to construct the component via a deserializing/decoding-based construction path | Execution fails with the message `init(coder:) has not been implemented` |
| vertical-stack-view-012 | forwards-added-views-to-inner-stack-view | Construct the component, then call the add-arranged-view operation with a child view | The child view appears among the internal stack view's arranged children, in the order it was added |

Three implementation-only construction-rule checks (disabling the legacy
autoresizing-mask/frame system on the component and on its internal stack,
and a parameterless construction path that forwards to a zero frame) and
one marker-role conformance check are framework mechanics rather than
portable behavior; see Platform Notes for how the
source implements them.

## Edge Cases

- **Null/empty input**: Not applicable — the add-arranged-view
  operation's parameter is a non-optional view; the type system rejects a
  missing argument at compile time. The parameterless constructor and the
  frame-accepting constructor (whose argument is discarded, see Design
  Decisions) leave no other caller-supplied value that could be null or
  empty. Calling the add-arranged-view operation zero times is a valid,
  un-special-cased path: the internal stack's arranged children stay
  empty and the component collapses to whatever natural size an empty
  internal stack resolves to.
- **Boundary values**: The standard group-spacing value is read exactly
  once, into the internal stack's spacing, at construction time (see
  **sets-arranged-subview-spacing-from-group-spacing-token**). The shared
  layout-metrics source is a live, observable value, but the component
  never subscribes to it, so if a caller mutates that underlying value
  after a component instance already exists, that instance's spacing does
  not update — it stays at whatever the group-spacing value was when it
  was constructed. This is the same staleness pattern documented for the
  sibling divider and horizontal-stack-view wrappers.
- **Concurrent access**: Not applicable — the component is confined to
  the UI thread (see **confines-to-ui-thread**), so construction and every
  mutation path (the add-arranged-view operation, or direct manipulation
  of the exposed internal stack view) are serialized to that thread.
- **Error states**: Not applicable — the component has no dependency on
  network, database, or file-system access, and shows no error path of
  any kind.
- **Offline/disconnected state**: Not applicable — the component performs
  no networking.
- **No dedicated removal operation, but the internal stack view is
  directly reachable**: The add-arranged-view operation is the only
  mutation method the component exposes; there is no remove-arranged-view
  or equivalent operation on the component itself. Because the internal
  stack view is public (see Design Decisions), a caller CAN reach it
  directly and remove an arranged child, reorder its arranged children, or
  change its alignment/distribution without going through this wrapper's
  API.

## Configuration

Not applicable: the component exposes no caller-configurable options
through its own constructor or setters. Its only public constructor takes
no parameters; the frame-accepting constructor accepts but discards its
argument (see Design Decisions), and a deserializing/decoding-based
construction path fails unconditionally. Orientation and spacing are
fixed at construction and are not exposed as settable properties on the
component itself. The public internal-stack-view property (see
**exposes-stack-view-as-public-property**) does let a caller reconfigure
the internal stack view directly after construction (see Design
Decisions) — but this is a consequence of that property's visibility, not
a formal configuration option this component defines.

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
| Reduce Motion | Not applicable: the component applies no animation, transition, or motion effect of its own — it assigns layout constraints once, at initialization, with no transition wrapping any of it. |
| Increase Contrast | Not applicable: the component paints no color of its own; it has no visual surface for Increase Contrast to affect. |
| Differentiate Without Color | Not applicable: the component conveys no state or meaning through color — it renders no color at all. |

## Feature Flags

Not applicable: no feature-flag check gates the component; it always
constructs and wires itself up unconditionally.

## Analytics

Not applicable: the component emits no analytics, tracking, or telemetry
calls, and has no user interaction of its own to report.

## Privacy

- **Data collected**: None. The component's only stored property is the
  public internal stack view; it holds no caller-supplied data of its
  own.
- **Storage**: Not applicable — the component performs no persistence of
  any kind.
- **Transmission**: Not applicable — the component performs no network or
  IPC calls.
- **Retention**: Not applicable — nothing is retained beyond the view
  instance's own lifetime.

## Logging

Not applicable: the component contains no logging calls.

## Platform Notes

- **SwiftUI**: `VStack(spacing:)` is the direct equivalent, with `spacing`
  sourced from the equivalent of the group-spacing token. Unlike this
  component, which takes children imperatively via repeated
  add-arranged-view calls after construction, a `VStack` takes its
  children declaratively as trailing-closure content at the call site —
  there is no separate "add a child later" step to port, and no
  equivalent of a publicly exposed internal stack view is needed since
  `VStack` has no such wrapped sub-object.
- **Compose**: `Column(verticalArrangement = Arrangement.spacedBy(...))`,
  with the spacing value sourced from the equivalent of the group-spacing
  token. As with SwiftUI, Compose children are declared inline rather
  than appended imperatively after construction, so a port drops the
  add-arranged-view-style API entirely.
- **React/Web**: A `<div>` with `display: flex; flex-direction: column;
  gap: <groupSpacing>px;` (a CSS Flexbox column). The `gap` property
  supplies the equivalent of the internal stack's spacing directly, with
  no manual spacer elements needed; children are ordinary DOM children in
  document order, corresponding to the order arranged subviews are added.
- **AppKit / UIKit (source)**: `VerticalStackView.swift`
  (`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/VerticalStackView.swift`)
  is a macOS-only (`import AppKit`), `@MainActor` `NSView` subclass
  conforming to `SettingsViewProtocol` (a marker protocol with no
  requirements of its own, backing **conforms-to-settings-view-protocol**,
  covered here rather than as a normative requirement). It sets
  `translatesAutoresizingMaskIntoConstraints = false` on itself and on its
  internal `NSStackView` (`orientation = .vertical`) — a pure Auto Layout
  framework construction rule with no equivalent step needed on a
  platform that never had a legacy autoresizing-mask/frame layout system
  to opt out of. It pins that stack view to all four edges of the outer
  `NSView` via `Self.pinToEdges(_:of:)` (`ViewLayout.swift`), exposes that
  wrapped stack view publicly as `stackView` (see Design Decisions), and
  exposes exactly one mutating method, `addArrangedSubview(_:)`, that
  forwards to it; the outer `NSView` itself renders nothing. The public
  `convenience init()` forwards to `init(frame: .zero)` with no
  parameters of its own; the designated `init(frame frameRect: NSRect)`
  discards the caller-supplied `frameRect` and always calls
  `super.init(frame: .zero)` (see Design Decisions); `required init?(coder:)`
  fatal-errors with the message `init(coder:) has not been implemented`
  (**rejects-deserializing-construction**). A UIKit port would use
  `UIStackView` directly (no wrapping `UIView` needed, since `UIStackView`
  is itself a `UIView`), making this wrapper layer unnecessary on that
  platform.
- **WinUI 3**: Use a `StackPanel` with `Orientation="Vertical"` and
  `Spacing` bound to the app's equivalent of the group-spacing layout
  token (WinUI's `StackPanel.Spacing` is the direct analog of the
  internal stack's spacing — no manual spacer elements needed, matching
  the React/Web note above). `StackPanel` has no enabled-driven visual
  states of its own to define in a visual-state group, since — like the
  source — it is a pure layout container with no interactive states (see
  States). Children are added via `panel.Children.Add(view)`, mirroring
  the add-arranged-view operation; because `StackPanel.Children` is
  already a public property on the framework type itself, a WinUI port
  gets the equivalent of this component's public internal-stack-view
  exposure for free, with no separate wrapper property needed. There is
  no WinUI equivalent needed for the source's edge-pinning step either,
  since a `StackPanel` placed directly in its parent (e.g. via `Grid`
  row/column stretch, or `HorizontalAlignment="Stretch"`/
  `VerticalAlignment="Stretch"`) already fills its allotted space without
  a separate constraint-activation step:
  ```xml
  <StackPanel Orientation="Vertical"
              Spacing="{StaticResource GroupSpacing}"
              HorizontalAlignment="Stretch"
              VerticalAlignment="Stretch"/>
  ```

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/VerticalStackView.swift` |

## Design Decisions

**Decision** (AppKit): The frame-accepting initializer discards its
argument and always constructs with a zero frame.
**Rationale**: The component positions itself entirely through Auto
Layout (disabling autoresizing-mask/frame translation, plus the activated
edge-pinning constraints). The inherited frame-based initializer exists
only so the type can still be constructed through it at all; the source
ignores the caller-supplied rect rather than reconciling it with the Auto
Layout constraints that take over immediately afterward. This is the same
pattern used by the sibling horizontal stack view and divider components,
so a port SHOULD keep discarding the caller's rect for parity with those
siblings rather than reconcile it with the constraints that immediately
override it.
**Approved**: pending

**Decision** (AppKit): The internal stack view is exposed publicly, unlike
the otherwise structurally identical horizontal stack view, whose
internal stack view is private.
**Rationale**: Not explained in source comments. This is a genuine
asymmetry between the two sibling wrappers: a caller of this component
can reach the internal stack view to reconfigure it (e.g. alignment or
distribution) or to remove an arranged subview directly, while a caller
of the horizontal sibling cannot. Recorded here rather than smoothed
over, since the two types would otherwise read as interchangeable except
for orientation.
**Approved**: pending

**Decision**: The add-arranged-view operation is the only mutation method
the component defines; no counterpart operation for removing an arranged
subview is exposed (though, unlike the horizontal sibling, the public
internal-stack-view property gives a caller an indirect path to one).
**Rationale**: Not explained in source comments. This is consistent with
the broader pattern of assembling a settings row or panel once, at
construction time, rather than mutating it afterward. Recorded here as a
known limitation of the public method surface rather than an intended,
documented contract, since nothing in the source states it was
deliberate.
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
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/layout/. |
