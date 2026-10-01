---
id: 537cf2a7-6be6-4a09-9a6c-8f8ecc6012da
title: Conditional View
domain: agentictoolkit://cookbook/ui/settings/layout/conditional-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings container that shows or hides a child view based on an
  observed setting's live value, collapsing its card row when hidden.
platforms:
- swift
- macos
tags:
- settings
- layout
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/layout/group-view
references: []
approved-by: ''
approved-date: ''
---

# Conditional View

## Overview

The conditional view is a settings container that shows or hides a single
caller-supplied child view based on the live value of an observed setting,
re-evaluating a caller-supplied visibility predicate every time the
setting's value changes. It exists to show a settings group only when
another setting takes a particular value — for example, showing a
"Custom Command" group only when a click-action setting equals
`custom_command`. It self-reports visibility changes so a hosting group
view can collapse the padding and hairline around a card row whose content
has hidden itself, rather than leaving an empty band behind.

## Behavioral Requirements

- **adds-child-as-only-subview**: Component MUST add the child view as its
  only content during initialization.
- **fills-container-with-child**: Component MUST make the child view fill
  the container's bounds edge-to-edge, with no additional inset, for as
  long as the container exists.
- **evaluates-initial-visibility**: Component MUST evaluate the visibility
  predicate against the observed setting's current value at the end of
  initialization, before the view is ever displayed.
- **reevaluates-visibility-on-setting-change**: Component MUST re-evaluate
  the visibility predicate against the setting's new value whenever the
  observed setting reports a change.
- **hides-when-predicate-returns-false**: Component MUST hide itself when
  the visibility predicate returns `false` for the value being evaluated.
- **shows-when-predicate-returns-true**: Component MUST show itself when
  the visibility predicate returns `true` for the value being evaluated.
- **skips-redundant-visibility-writes**: Component MUST NOT change its
  shown/hidden state and MUST NOT invoke the visibility-change callback
  when the newly computed visibility equals the component's current
  visibility.
- **notifies-visibility-change-once**: Component MUST invoke the
  visibility-change callback exactly once, after its shown/hidden state
  has changed, each time the computed visibility differs from the
  previous visibility.
- **reflects-setting-change-asynchronously**: Component MUST NOT reflect a
  changed setting value in its shown/hidden state synchronously, within
  the same call frame that changed the setting: the change delivers
  asynchronously, on the main thread, so the visibility update lands on a
  following turn of the main run loop, not before.
- **exposes-child-property**: Component MUST expose the child view as a
  public, directly-accessible, read-only property.
- **exposes-visibility-change-callback**: Component MUST expose a
  visibility-change callback as a public, settable, optional property so a
  hosting container can be told when the component's own visibility
  changes.
- **requires-full-configuration-at-construction**: Component MUST NOT be
  constructible without a setting, a child view, and a visibility
  predicate; only full construction with all three together is supported.

## Appearance

Draws nothing of its own — no corner radius, font, background,
foreground/text, border, shadow, or min/max size is set by the container
itself; the only thing it contributes to the child view's presentation is
layout (see **fills-container-with-child**), and all visible appearance
belongs to the child view.

## States

| State | Appearance change |
|-------|------------------|
| Default | The child view is added as the only content and pinned to the container's edges; the shown/hidden state is set from the current visibility evaluation before the view is ever displayed, so there is no unevaluated frame. |
| Visible | Shown; set whenever the visibility predicate returns `true` for the setting's current value. The visibility-change callback fires once on a transition into this state from Hidden — never during the initial evaluation at construction, because no caller has had the chance to assign the callback at that point. |
| Hidden | Hidden; set whenever the visibility predicate returns `false` for the setting's current value. The visibility-change callback fires once on a transition into this state from Visible, for the same reason the Visible row's initial-evaluation exception applies. |
| Pressed | Not applicable: the component is a plain container — it defines no target/action and receives no press interaction of its own. |
| Disabled | Not implemented; an enabled/disabled concept is never read or set. |
| Focused | Not styled by the container; any focus ring belongs to the child view, not to this container. |
| Loading | Not applicable: the component performs no asynchronous operation and shows no loading indicator. |

## Accessibility

Not applicable beyond the platform's own default behavior: the container
sets no role, label, or announcement of its own — assistive technology
interacts with the child view, whose accessibility behavior belongs to the
child view's own recipe — and, as a pass-through layout container rather
than a control, it defines no tap target to constrain. Hiding the
component removes the child view from the accessibility tree
automatically.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| conditional-view-001 | adds-child-as-only-subview | Construct the component with any setting, child view, and visibility predicate | The child view is content of the constructed component; it is the only content added by the component |
| conditional-view-002 | fills-container-with-child | Construct the component | The component and the child view both opt out of any implicit frame-based sizing |
| conditional-view-003 | fills-container-with-child | Construct the component | Active layout constraints pin the child view's top/leading/trailing/bottom edges to the container's corresponding edges, each with a zero offset |
| conditional-view-004 | evaluates-initial-visibility | Construct with the setting's current value such that the visibility predicate returns `false` | Immediately after construction, the component is hidden — no change notification required |
| conditional-view-005 | evaluates-initial-visibility | Construct with the setting's current value such that the visibility predicate returns `true` | Immediately after construction, the component is shown |
| conditional-view-006 | reevaluates-visibility-on-setting-change | After construction, change the observed setting's value so the visibility predicate now returns a different result, then allow the change to deliver | The component's shown/hidden state reflects the new visibility-predicate result after the change delivers |
| conditional-view-007 | hides-when-predicate-returns-false | Construct shown, then change the setting to a value where the visibility predicate returns `false`, then allow the change to deliver | After the change delivers, the component is hidden |
| conditional-view-008 | shows-when-predicate-returns-true | Construct hidden, then change the setting to a value where the visibility predicate returns `true`, then allow the change to deliver | After the change delivers, the component is shown |
| conditional-view-009 | skips-redundant-visibility-writes | With the component hidden, change the setting to a different value for which the visibility predicate is still `false`, then allow the change to deliver | The visibility-change callback is not called for this change, and the component's shown/hidden state is confirmed not reassigned |
| conditional-view-010 | notifies-visibility-change-once | Register the visibility-change callback, then change the setting so the visibility predicate flips from `true` to `false`, then allow the change to deliver | The callback is called exactly once, after the component has already become hidden |
| conditional-view-011 | exposes-child-property | Construct the component, then read its child-view property from outside the type | Returns the same view instance passed into construction |
| conditional-view-012 | exposes-visibility-change-callback | Assign a callback to the visibility-change property from outside the type, then trigger a visibility change | The assigned callback is the one invoked |
| conditional-view-013 | requires-full-configuration-at-construction | Attempt to construct the component with only a subset of its required inputs (see Platform Notes for the exact construction paths this blocks) | Construction is refused; no usable instance is produced |
| conditional-view-014 | reflects-setting-change-asynchronously | Change the observed setting's value, then synchronously — in the same call frame, before the change has had a chance to deliver — read the component's shown/hidden state | The component's shown/hidden state still reflects the pre-change visibility; only after the change delivers, on a following turn, does the state reflect the new value |

## Edge Cases

- Null/empty input: the setting, the child view, and the visibility
  predicate are all required, non-optional inputs to construction, so
  there is no null/empty case for any of the three to handle; the
  constructor needs no nil-handling path because none of its inputs can be
  absent.
- Boundary values: Not applicable in general — the setting's value type is
  a caller-chosen type (a string, a boolean, an enumerated value, etc.)
  with no minimum/maximum intrinsic to the component itself; whatever
  boundary a particular value type has belongs to the caller's visibility
  predicate, not to this component.
- Concurrent access: Not applicable — the component is confined to a
  single UI thread (see Platform Notes), and the observed setting's
  change delivery is scheduled on that same thread, so every read of the
  setting's value and every visibility write is serialized.
- Error states: Not applicable — every operation (evaluating the
  visibility predicate, comparing shown/hidden state, invoking the
  visibility-change callback) is a synchronous, non-throwing call; no
  error-producing path exists.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads an in-process setting value through
  its observer.
- Asynchronous delivery of external setting changes: see
  **reflects-setting-change-asynchronously**.
- Use outside a visibility-aware hosting container: the component reports
  its own visibility changes specifically so a hosting group view's
  content layout can subscribe and collapse a card row's padding and
  hairline. A conditional view placed in a container that never reads that
  notification still hides the child view's content correctly, but any
  space that container reserves around the row is unaffected — closing up
  that space is the responsibility of the hosting container, not of this
  component.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `setting` | observed setting | — (required) | The setting whose live value is observed through an internally-created observer; visibility re-evaluates whenever this setting's value changes. |
| `child` | view | — (required) | The view shown or hidden based on the visibility predicate. Added as the sole content and pinned to the container's edges with no additional padding. |
| `isVisible` | predicate | — (required) | Predicate evaluated against the setting's current value, at construction and on every subsequent change, to decide whether the child view (and the container itself) is shown. |

## Deep Linking

Not applicable: the component is a conditional container inside a settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
applies.

## Localization

Not applicable: the component contributes no user-facing string of its
own (the only string literal in the source implementation is a
diagnostic, not user-facing, message — see Platform Notes). Any
localizable text belongs to the child view.

## Accessibility Options

Not applicable: the component performs no animation or drawing of its
own, and conveys no color-only cue — visibility is communicated
structurally, by the child view's presence or absence, not by motion,
contrast, or color.

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate applies;
visibility is driven entirely by the caller's visibility predicate over
the observed setting's value, not by a flag system.

## Analytics

Not applicable: the component performs no analytics or telemetry of its
own.

## Privacy

Not applicable: the component collects, stores, transmits, and retains
nothing of its own beyond the already-stored value of a caller-supplied
setting, which it only reads through its observer; no disk or networking
access occurs, and it retains nothing beyond the child view, the observer,
and the visibility predicate for its own lifetime.

## Logging

Not applicable: the component performs no logging of its own.

## Platform Notes

- **SwiftUI**: Bind the setting's `@Published` value into `@State` (or
  observe it via a Combine publisher) and use structural conditional
  inclusion, `if isVisible(value) { child }`, rather than `.hidden()` —
  SwiftUI removes the branch not taken from the view hierarchy the same way
  a hidden `NSView` drops out of an `NSStackView`, which is what
  `evaluates-initial-visibility`/`hides-when-predicate-returns-false`
  ultimately exist to drive for a hosting `GroupView`-equivalent stack.
  Evaluate the predicate once for the initial `@State` and again in the
  publisher's `sink`/`onReceive`, mirroring
  reevaluates-visibility-on-setting-change.
- **Compose**: Collect the setting as `State` via `collectAsState()` (or
  equivalent `Flow` collection) and wrap the child composable in `if
  (isVisible(value)) { child() }`. Compose already skips recomposition for
  an unchanged `State` value, so no extra "skip redundant" guard is needed
  to mirror skips-redundant-visibility-writes; still call an
  `onVisibilityChange` callback from a `LaunchedEffect(visible)` block (or
  `snapshotFlow { visible }.distinctUntilChanged()`) when a hosting
  container needs to know the child entered or left the composition —
  `onGloballyPositioned` is a layout callback, not a composition-membership
  signal, so it cannot drive this — mirroring
  exposes-visibility-change-callback.
- **React/Web**: Subscribe to the setting's store with a hook (e.g.
  `useSyncExternalStore`) and render conditionally, `{isVisible(value) &&
  child}`. Guard the store subscription's callback so it only triggers a
  re-render when the *computed visibility*, not just the underlying value,
  changes, mirroring skips-redundant-visibility-writes; call an optional
  `onVisibilityChange` prop from a `useEffect` keyed on that computed
  boolean, mirroring notifies-visibility-change-once.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ConditionalView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, generic
  over `Value: Codable & Sendable`, inside the `ComposableSettings`
  namespace, conforming to `SettingsViewProtocol` and
  `SelfHidingSettingsView`. It wraps one `child` view, pins it via
  `pinToEdges`, and drives `isHidden` from a `UserSettingObserver<Value>`
  wrapping a caller-supplied `UserSetting<Value>`. `fills-container-with-child`
  is implemented by setting `translatesAutoresizingMaskIntoConstraints =
  false` on both itself and `child` and pinning `child`'s
  top/leading/trailing/bottom anchors to the container's corresponding
  anchors with the `pinToEdges` helper; `requires-full-configuration-at-construction`
  (formerly named `restricts-construction-to-designated-initializer`) is
  implemented by overriding both `init(frame:)` and `init(coder:)` to
  `fatalError`, leaving `observing:child:isVisible:` as the only usable
  initializer — attempting either inherited path traps with a fatal error
  rather than returning a usable instance. The class's `@MainActor`
  declaration is the source's implementation of thread-confinement:
  construction and mutation are restricted to the main actor, enforced at
  compile time by Swift's isolation checking. There is no UIKit code path
  in source; a UIKit port would replace `NSView.isHidden` with
  `UIView.isHidden` (the same removal-from-layout semantics apply) and
  would have no `NSCoder`-vs-frame initializer split to fatal-error on, the
  way requires-full-configuration-at-construction does here.
- **WinUI 3** (the reason this recipe exists): Wrap `child` in a
  `ContentControl` (or host it directly in the parent `Grid`/`StackPanel`
  cell) and bind its `Visibility` with a one-way `x:Bind` through a value
  converter over the observed setting, e.g. `Visibility="{x:Bind
  Setting.Value, Converter={StaticResource IsVisibleToVisibilityConverter},
  Mode=OneWay}"`, where the converter is the WinUI analog of the
  `isVisible` predicate. Use `Visibility.Collapsed`, not `Hidden`, so the
  hosting `StackPanel` (the WinUI analog of `GroupView`'s card
  `NSStackView`) actually closes up the row's space — `Hidden` keeps the
  layout slot reserved and would silently violate
  hides-when-predicate-returns-false's intent of the row disappearing, not
  merely going invisible. `FrameworkElement` has no built-in
  visibility-changed event, so expose a small
  `RegisterPropertyChangedCallback` on the `Visibility` dependency property
  (or a custom `VisibilityChanged` event) as the analog of
  `onVisibilityChange`, guarding it so it only fires when the resolved
  `Visibility` actually differs from the previous one, mirroring
  skips-redundant-visibility-writes, so a hosting card panel can collapse
  its own padding and divider around the row the way `GroupView` does.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ConditionalView.swift` |

## Design Decisions

**Decision**: Evaluate `isVisible` synchronously against the setting's
current value at the end of `init`, in addition to subscribing to future
changes through `UserSettingObserver.onChange`.
**Rationale**: without a synchronous initial evaluation, the view would
render in `NSView`'s default (visible) state until the observer's first,
asynchronously-delivered change notification arrived, producing a visible
flash of a `child` that should have opened hidden.
**Approved**: pending

**Decision**: Guard `applyVisibility` with `hidden != self.isHidden` before
writing `isHidden` or invoking `onVisibilityChange`.
**Rationale**: without the guard, a hosting `GroupView`'s separator/padding
recompute (`updateSeparators`) would run on every value the observed
setting publishes, even one that leaves this view's own visibility
unchanged, doing redundant layout work on every unrelated settings
interaction.
**Approved**: pending

**Decision** (AppKit): Force a fatal error from both `init(coder:)` and the
frame-only `init(frame:)`, leaving the `observing:child:isVisible:`
initializer as the only usable one.
**Rationale**: `ConditionalView` has no meaningful default state — it cannot
decide a visibility without a `setting`, a `child`, and an `isVisible`
predicate — so both inherited `NSView` initializers that could construct
one without them are intentionally disabled rather than left to produce a
half-configured view.
**Approved**: pending

**Decision**: Conform to `SelfHidingSettingsView` and expose
`onVisibilityChange`, rather than keeping visibility purely internal to
the view.
**Rationale**: per the source's own doc comment, the callback is "told to
whoever placed this view — a group's card closes up over a row whose
content has taken itself off screen." The callback exists for a hosting
container's benefit, not for any need of `ConditionalView`'s own.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

`native-controls-preference` and `screen-reader-support` pass because
`ConditionalView` is a plain `NSView` that relies entirely on AppKit's own
`isHidden` to remove `child` from both the view and accessibility trees;
`idempotent-operations` passes via the `hidden != self.isHidden` guard in
`applyVisibility`; `separation-of-concerns` passes because `ConditionalView`
manages only visibility, delegating all appearance and accessibility to
`child`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: merged AppKit-mechanic requirements into cross-platform behavioral ones and moved the mechanics to the AppKit/UIKit platform note, promoted async setting-change delivery to a named requirement with a vector, fixed onVisibilityChange's transition semantics in States, fixed test-vector observability and run-loop wording, corrected the Compose platform note's composition-membership signal, reformatted Design Decisions to the bold three-line form, trimmed Compliance to applicable checks, collapsed boilerplate Appearance/Accessibility/Privacy/Accessibility-Options sections, added the GroupView cross-reference, removed a source-typo edge case, and added the initial Change History row |
| 1.1.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/layout/. |
</content>
