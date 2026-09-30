<!-- leaf: implement-general-view-1/conditional-view · source: conditional-view.md -->

**Rules** (cite as `implement-general-view-1/conditional-view#<slug>`):

- `adds-child-as-only-subview` MUST
- `fills-container-with-child` MUST
- `evaluates-initial-visibility` MUST
- `reevaluates-visibility-on-setting-change` MUST
- `hides-when-predicate-returns-false` MUST
- `shows-when-predicate-returns-true` MUST
- `skips-redundant-visibility-writes` MUST
- `notifies-visibility-change-once` MUST
- `reflects-setting-change-asynchronously` MUST
- `exposes-child-property` MUST
- `exposes-visibility-change-callback` MUST
- `restricts-construction-to-designated-initializer` MUST
- `confines-to-main-actor` MUST

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

- **adds-child-as-only-subview**: Component MUST add `child` as its only
  subview during initialization.
- **fills-container-with-child**: Component MUST make `child` fill
  `ConditionalView`'s bounds edge-to-edge, with no additional inset, for as
  long as the view exists.
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
- **reflects-setting-change-asynchronously**: Component MUST NOT reflect a
  changed setting value in `isHidden` synchronously, within the same call
  frame that changed the setting: `UserSettingObserver.onChange` delivers
  via `.receive(on: DispatchQueue.main)`, so the visibility update lands on
  the following main-queue turn, not before.
- **exposes-child-property**: Component MUST expose `child` as a public,
  directly-accessible, read-only property.
- **exposes-visibility-change-callback**: Component MUST expose
  `onVisibilityChange` as a public, settable `(() -> Void)?` property so a
  hosting container can be told when the view's own visibility changes.
- **restricts-construction-to-designated-initializer**: Component MUST NOT
  be constructible without a `setting`, `child`, and `isVisible` predicate:
  both the inherited `init(coder:)` and the inherited frame-only
  `init(frame:)` MUST trigger a fatal error, leaving
  `observing:child:isVisible:` as the only usable initializer.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.

## Appearance

Draws nothing of its own — no corner radius, font, background,
foreground/text, border, shadow, or min/max size is set anywhere in
`ConditionalView.swift`; the only thing it contributes to `child`'s
presentation is layout (see **fills-container-with-child**), and all visible
appearance belongs to `child`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `setting` | `UserSetting<Value>` | — (required) | The setting whose live value is observed through an internally-created `UserSettingObserver<Value>`; visibility re-evaluates whenever this setting's value changes. |
| `child` | `NSView` | — (required) | The view shown or hidden based on `isVisible`. Added as the sole subview and pinned to `ConditionalView`'s edges with no additional padding. |
| `isVisible` | `@escaping @MainActor (Value) -> Bool` | — (required) | Predicate evaluated against the setting's current value, at construction and on every subsequent change, to decide whether `child` (and `ConditionalView` itself) is shown. |

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
  anchors with the `pinToEdges` helper; `restricts-construction-to-designated-initializer`
  is implemented by overriding both `init(frame:)` and `init(coder:)` to
  `fatalError`, leaving `observing:child:isVisible:` as the only usable
  initializer. There is no UIKit code path in source; a UIKit port would
  replace `NSView.isHidden` with `UIView.isHidden` (the same
  removal-from-layout semantics apply) and would have no `NSCoder`-vs-frame
  initializer split to fatal-error on, the way
  restricts-construction-to-designated-initializer does here.
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

**Decision**: Force a fatal error from both `init(coder:)` and the
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
