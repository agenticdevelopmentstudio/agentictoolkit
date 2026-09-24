---
id: 537cf2a7-6be6-4a09-9a6c-8f8ecc6012da
title: ConditionalView
domain: agentictoolkit://recipes/conditional-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings container that shows or hides a child view based
  on an observed UserSetting's live value, collapsing its card row when hidden.
platforms:
- swift
- macos
tags:
- settings
- layout
- macos
- appkit
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# ConditionalView

## Overview

`ConditionalView` is a macOS `ComposableSettings` container
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ConditionalView.swift`):
it shows or hides a single caller-supplied `child` view based on the live
value of an observed `UserSetting<Value>`, re-evaluating a caller-supplied
`isVisible` predicate every time the setting's value changes. Per the
source's own doc comment, it exists to show a settings group only when
another setting takes a particular value — for example, showing a
"Custom Command" group only when a click-action setting equals
`custom_command`. It conforms to `SelfHidingSettingsView`, exposing
`onVisibilityChange` so a hosting `GroupView` can collapse the padding and
hairline around a card row whose content has hidden itself, rather than
leaving an empty band behind.

## Behavioral Requirements

- **adds-child-as-only-subview**: Component MUST add `child` as its subview
  during initialization.
- **disables-autoresizing-mask**: Component MUST set
  `translatesAutoresizingMaskIntoConstraints = false` on both itself and on
  `child`.
- **pins-child-to-edges**: Component MUST pin `child`'s top, leading,
  trailing, and bottom anchors to its own corresponding edges with no
  additional constant (`pinToEdges`).
- **evaluates-initial-visibility**: Component MUST evaluate `isVisible`
  against the observed setting's current value at the end of
  initialization, before the view is ever displayed.
- **reevaluates-visibility-on-setting-change**: Component MUST re-evaluate
  `isVisible` against the setting's new value whenever the observed
  `UserSettingObserver`'s `onChange` fires.
- **hides-when-predicate-returns-false**: Component MUST set `isHidden =
  true` when `isVisible(value)` returns `false` for the value being
  evaluated.
- **shows-when-predicate-returns-true**: Component MUST set `isHidden =
  false` when `isVisible(value)` returns `true` for the value being
  evaluated.
- **skips-redundant-visibility-writes**: Component MUST NOT write to
  `isHidden` and MUST NOT invoke `onVisibilityChange` when the newly
  computed hidden value equals the view's current `isHidden` value.
- **notifies-visibility-change-once**: Component MUST invoke
  `onVisibilityChange` exactly once, after `isHidden` has been reassigned,
  each time the computed hidden value differs from the previous `isHidden`
  value.
- **exposes-child-property**: Component MUST expose `child` as a public,
  directly-accessible, read-only property.
- **exposes-visibility-change-callback**: Component MUST expose
  `onVisibilityChange` as a public, settable `(() -> Void)?` property so a
  hosting container can be told when the view's own visibility changes.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.

## Appearance

- **Corner radius**: Not applicable — the component draws nothing of its
  own; it adds no custom layer or drawing code, only `child` pinned to its
  edges.
- **Padding**: `pinToEdges` pins `child`'s top/leading/trailing/bottom
  directly to `ConditionalView`'s edges with no additional constant, so the
  component contributes 0pt of its own padding; any visible padding belongs
  to `child`.
- **Font**: Not applicable — `ConditionalView` renders no text of its own;
  any typography belongs to `child`.
- **Background**: Not applicable — no background color or layer is set on
  `ConditionalView` itself anywhere in source.
- **Foreground/Text**: Not applicable — the same reasoning as Font; the
  component has no text or tint of its own to color.
- **Border**: Not applicable — no border is drawn or configured anywhere in
  `ConditionalView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `ConditionalView.swift`.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in `ConditionalView.swift`; because `child` is pinned to
  all four edges, the container's size is exactly `child`'s own
  constraint-driven size.

## States

| State | Appearance change |
|-------|------------------|
| Default | `child` is added as the only subview and pinned to edges; `isHidden` is set from `applyVisibility(for: observer.value)` before the view is ever displayed, so there is no unevaluated frame. |
| Visible | `isHidden == false`; set whenever `isVisible(value)` returns `true` for the setting's current value. |
| Hidden | `isHidden == true`; set whenever `isVisible(value)` returns `false` for the setting's current value. `onVisibilityChange` fires once on the transition into this state. |
| Pressed | Not applicable: `ConditionalView` is a plain container view — it defines no target/action and receives no press interaction of its own. |
| Disabled | Not implemented in `ConditionalView`; `isEnabled` is never read or set anywhere in source. |
| Focused | Not styled by `ConditionalView`; any focus ring belongs to `child`, not to this container. |
| Loading | Not applicable: the component performs no asynchronous operation and shows no loading indicator in source. |

## Accessibility

- **Role/trait**: Not applicable — `ConditionalView` sets no accessibility
  role of its own anywhere in source; VoiceOver interacts with `child`,
  whose accessibility behavior belongs to `child`'s own recipe.
- **Label requirements**: Not applicable — `ConditionalView` carries no
  label of its own; it is a transparent visibility container around a
  caller-supplied `child`.
- **Announce state changes (e.g., loading, disabled)**: Not applicable
  beyond AppKit's own default behavior — setting `isHidden` removes the
  view, and `child` with it, from the accessibility tree automatically;
  `ConditionalView` performs no additional VoiceOver announcement in
  source.
- **Minimum tap target**: Not applicable — `ConditionalView` is a
  pass-through layout container, not a control; it defines no tap target of
  its own for source to constrain.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| conditional-view-001 | adds-child-as-only-subview | Construct `ConditionalView` with any `setting`, `child`, `isVisible` | `child` is a subview of the constructed view; it is the only subview added by `ConditionalView` |
| conditional-view-002 | disables-autoresizing-mask | Construct `ConditionalView` | `view.translatesAutoresizingMaskIntoConstraints == false` and `child.translatesAutoresizingMaskIntoConstraints == false` |
| conditional-view-003 | pins-child-to-edges | Construct `ConditionalView` | Active constraints pin `child`'s top/leading/trailing/bottom anchors to the container's corresponding anchors, each with constant `0` |
| conditional-view-004 | evaluates-initial-visibility | Construct with `setting.currentValue` such that `isVisible(value) == false` | Immediately after `init` returns, `view.isHidden == true` — no change notification required |
| conditional-view-005 | evaluates-initial-visibility | Construct with `setting.currentValue` such that `isVisible(value) == true` | Immediately after `init` returns, `view.isHidden == false` |
| conditional-view-006 | reevaluates-visibility-on-setting-change | After construction, change the observed setting's value so `isVisible` now returns a different result, then allow the observer's `onChange` to deliver | `view.isHidden` reflects the new `isVisible` result after `onChange` fires |
| conditional-view-007 | hides-when-predicate-returns-false | Construct visible (`isHidden == false`), then change the setting to a value where `isVisible(value) == false` | After `onChange` delivers, `view.isHidden == true` |
| conditional-view-008 | shows-when-predicate-returns-true | Construct hidden (`isHidden == true`), then change the setting to a value where `isVisible(value) == true` | After `onChange` delivers, `view.isHidden == false` |
| conditional-view-009 | skips-redundant-visibility-writes | With `view.isHidden == true`, change the setting to a different value for which `isVisible(value)` is still `false` | `isHidden`'s setter is not invoked again and `onVisibilityChange` is not called for this change |
| conditional-view-010 | notifies-visibility-change-once | Register `onVisibilityChange`, then change the setting so `isVisible(value)` flips from `true` to `false` | `onVisibilityChange` is called exactly once, after `view.isHidden` has already become `true` |
| conditional-view-011 | exposes-child-property | Construct the component, then read `.child` from outside the type | Returns the same `NSView` instance passed into the initializer |
| conditional-view-012 | exposes-visibility-change-callback | Assign a closure to `.onVisibilityChange` from outside the type, then trigger a visibility change | The assigned closure is the one invoked |
| conditional-view-013 | requires-designated-initializer | Attempt `ConditionalView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| conditional-view-014 | rejects-frame-only-initialization | Attempt `ConditionalView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| conditional-view-015 | confines-to-main-actor | Attempt to construct or mutate a `ConditionalView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |

## Edge Cases

- Null/empty input: `setting` (`UserSetting<Value>`), `child` (`NSView`),
  and `isVisible` (`@escaping @MainActor (Value) -> Bool`) are all
  non-optional, typed constructor parameters; Swift's type system rules out
  `nil` for any of the three. This is a MUST: the initializer needs no
  nil-handling path because none of its parameters can be `nil`.
- Boundary values: Not applicable in general — `Value` is a caller-chosen
  `Codable & Sendable` type (a `String`, a `Bool`, an enum, etc.) with no
  minimum/maximum intrinsic to `ConditionalView` itself; whatever boundary a
  particular `Value` type has belongs to the caller's `isVisible` predicate,
  not to this component.
- Concurrent access: Not applicable — the class is declared `@MainActor`
  (see **confines-to-main-actor**), and `UserSettingObserver`'s own
  `onChange` delivery is scheduled on the main dispatch queue, so every
  read of `observer.value` and every write to `isHidden` is serialized on
  the main actor.
- Error states: Not applicable — every operation in
  `ConditionalView.swift` (evaluating `isVisible`, comparing `isHidden`,
  calling `onVisibilityChange`) is a synchronous, non-throwing call; no
  `try`, `Result`, or error-producing API appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads an in-process `UserSetting` value
  through `UserSettingObserver`.
- Asynchronous delivery of external setting changes: `UserSettingObserver`
  delivers `onChange` via `.receive(on: DispatchQueue.main)`, one main-queue
  turn after the setting's underlying value has actually changed, not
  synchronously within the call that changed it (see `UserSetting.swift`).
  This is a MUST-level, source-traceable consequence of the dependency
  `ConditionalView` observes through: a caller that changes the setting and
  immediately inspects `isHidden` in the same call frame will still see the
  *previous* visibility state; the update lands on the following main-queue
  turn, not before.
- Malformed frame-only-initializer trap message: the `init(frame:)`
  override's `fatalError` message string in source,
  `init(frame frameRect: NSRect`, is missing its closing parenthesis. The
  initializer still traps unconditionally on every call; only the trap's
  message text is affected, not the requires-designated-initializer or
  rejects-frame-only-initialization behavior itself.
- Use outside a `SelfHidingSettingsView`-aware container: `ConditionalView`
  conforms to `SelfHidingSettingsView` specifically so `GroupView`'s
  `addSettingSubview` can subscribe to `onVisibilityChange` and collapse a
  card row's padding and hairline. A `ConditionalView` placed in a container
  that never reads `onVisibilityChange` still hides `child`'s content
  correctly, but any space that container reserves around the row is
  unaffected — closing up that space is the responsibility of the hosting
  container, not of `ConditionalView` itself.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `setting` | `UserSetting<Value>` | — (required) | The setting whose live value is observed through an internally-created `UserSettingObserver<Value>`; visibility re-evaluates whenever this setting's value changes. |
| `child` | `NSView` | — (required) | The view shown or hidden based on `isVisible`. Added as the sole subview and pinned to `ConditionalView`'s edges with no additional padding. |
| `isVisible` | `@escaping @MainActor (Value) -> Bool` | — (required) | Predicate evaluated against the setting's current value, at construction and on every subsequent change, to decide whether `child` (and `ConditionalView` itself) is shown. |

## Deep Linking

Not applicable: `ConditionalView` is a conditional container inside a
composable settings window, not a navigable screen; no URL scheme, route,
or deep-link handler appears anywhere in `ConditionalView.swift`.

## Localization

Not applicable: the file contains no user-facing string literals of its
own (the only string literal in source is the frame-only initializer's
fatal-error message, which is diagnostic, not user-facing). Any localizable
text belongs to `child`.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, or `NSAnimationContext` call; the visibility change is an instantaneous `isHidden` assignment. |
| Increase Contrast | Not applicable: `ConditionalView.swift` sets no custom `NSColor` or drawing of its own; it has no appearance to adjust for contrast. |
| Differentiate Without Color | Not applicable: visibility is communicated by the view's presence or absence (`isHidden`), a structural state, not a color-only signal. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `ConditionalView.swift`; visibility is driven entirely by the caller's
`isVisible` predicate over the observed setting's value, not by a flag
system.

## Analytics

Not applicable: `ConditionalView.swift` contains no analytics or telemetry
call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only reads the already-stored value of a caller-supplied
  `UserSetting`.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store directly; persistence is owned by
  `UserSetting`/`UserSettingObserver`, which are not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only `child`, its
  `UserSettingObserver`, and the `isVisible` closure for its own lifetime;
  it persists nothing beyond that.

## Logging

Not applicable: `ConditionalView.swift` contains no logging call (no
`print`, `os_log`, or logger reference anywhere in source).

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
  to mirror skips-redundant-visibility-writes; still expose a
  `Modifier`-level `onGloballyPositioned`/callback if a hosting container
  needs to know a child left the composition, mirroring
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
  wrapping a caller-supplied `UserSetting<Value>`. There is no UIKit code
  path in source; a UIKit port would replace `NSView.isHidden` with
  `UIView.isHidden` (the same removal-from-layout semantics apply) and
  would have no `NSCoder`-vs-frame initializer split to fatal-error on, the
  way requires-designated-initializer and
  rejects-frame-only-initialization do here.
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

## Design Decisions

- Decision: Evaluate `isVisible` synchronously against the setting's
  current value at the end of `init`, in addition to subscribing to future
  changes through `UserSettingObserver.onChange`.
  Rationale: without a synchronous initial evaluation, the view would
  render in `NSView`'s default (visible) state until the observer's first,
  asynchronously-delivered change notification arrived, producing a
  visible flash of a `child` that should have opened hidden.
  Approved: pending
- Decision: Guard `applyVisibility` with `hidden != self.isHidden` before
  writing `isHidden` or invoking `onVisibilityChange`.
  Rationale: without the guard, a hosting `GroupView`'s separator/padding
  recompute (`updateSeparators`) would run on every value the observed
  setting publishes, even one that leaves this view's own visibility
  unchanged, doing redundant layout work on every unrelated settings
  interaction.
  Approved: pending
- Decision: Force a fatal error from both `init(coder:)` and the
  frame-only `init(frame:)`, leaving the `observing:child:isVisible:`
  initializer as the only usable one.
  Rationale: `ConditionalView` has no meaningful default state — it cannot
  decide a visibility without a `setting`, a `child`, and an `isVisible`
  predicate — so both inherited `NSView` initializers that could construct
  one without them are intentionally disabled rather than left to produce a
  half-configured view.
  Approved: pending
- Decision: Conform to `SelfHidingSettingsView` and expose
  `onVisibilityChange`, rather than keeping visibility purely internal to
  the view.
  Rationale: per the source's own doc comment, the callback is "told to
  whoever placed this view — a group's card closes up over a row whose
  content has taken itself off screen." The callback exists for a hosting
  container's benefit, not for any need of `ConditionalView`'s own.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
