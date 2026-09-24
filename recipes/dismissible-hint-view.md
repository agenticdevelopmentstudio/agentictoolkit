---
id: f3d7adbb-ece4-4b00-97af-f7e3db9d5999
title: DismissibleHintView
domain: agentictoolkit://recipes/dismissible-hint-view
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings row pairing a hint label with a "Got It" button
  that persists a UserSetting<Bool> and hides itself once dismissed.
platforms:
- swift
- macos
tags:
- settings
- macos
- appkit
- onboarding
depends-on: []
related:
- agentictoolkit://recipes/conditional-view
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
approved-by: ''
approved-date: ''
---

# DismissibleHintView

## Overview

`DismissibleHintView`
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/DismissibleHintView.swift`)
is a macOS `ComposableSettings` container: an `NSView` pairing a wrapping hint
label with a small "Got It" button. Per the source's own doc comment, it is a
"coachmark-style hint" that "hides itself once the backing `UserSetting<Bool>`
flips to `true`," intended for one-time onboarding prompts such as "enable
launch at login so you never miss a session." It conforms to
`SelfHidingSettingsView`, exposing `onVisibilityChange` so a hosting
`GroupView` can collapse the padding and hairline around a card row whose
content has hidden itself, rather than leaving an empty band behind — the same
protocol the sibling `ConditionalView` recipe
(`agentictoolkit://recipes/conditional-view`) conforms to for the same reason.

## Behavioral Requirements

- **self-hiding-conformance**: Component MUST conform to
  `SelfHidingSettingsView` (and `SettingsViewProtocol`), exposing
  `onVisibilityChange` so a hosting `GroupView` can collapse a card row's
  padding and hairline once this view's content has hidden itself.
- **text-label**: Component MUST create `textLabel` as
  `NSTextField(wrappingLabelWithString: text)`, using the caller-supplied
  hint text; the label wraps rather than truncates.
- **text-label-theming**: Component MUST set `textLabel`'s text color to the
  current theme's secondary text color (`palette.secondaryTextColor`) and its
  font to the current theme's caption text role (`palette.font(.caption)`),
  applied immediately at construction and re-applied on every subsequent
  theme change (via `observeTheme`).
- **dismiss-button-title**: Component MUST create `dismissButton` as an
  `NSButton` whose title is `buttonTitle`.
- **dismiss-button-title-default**: Component MUST default `buttonTitle` to
  `"Got It"` when the caller does not supply one.
- **dismiss-button-style**: Component MUST set `dismissButton.bezelStyle =
  .rounded` and `dismissButton.controlSize = .small`.
- **dismiss-button-action**: Component MUST set `dismissButton`'s target to
  itself and its action to the internal dismiss handler after construction,
  so that clicking the button invokes it.
- **stack-arrangement**: Component MUST arrange `textLabel` above
  `dismissButton` in a vertical `NSStackView` with leading alignment.
- **stack-spacing**: Component MUST set the vertical stack's `spacing` to
  `SettingsLayout.default[.rowSpacing]`, which resolves to 8pt
  (`ViewLayout.swift`).
- **dismissed-setting-observation**: Component MUST wrap the caller-supplied
  `dismissedSetting` (`UserSetting<Bool>`) in an internal
  `UserSettingObserver<Bool>` at construction.
- **initial-visibility**: Component MUST set `isHidden` to the observed
  setting's current value (`observer.value`) at the end of initialization,
  before the view is ever displayed, without invoking `onVisibilityChange`.
- **visibility-update**: Component MUST set `isHidden` to the new value
  whenever the observed `UserSettingObserver`'s `onChange` fires with a value
  different from the view's current `isHidden`.
- **visibility-write-guard**: Component MUST NOT write to `isHidden` and MUST
  NOT invoke `onVisibilityChange` when the value delivered by `onChange`
  equals the view's current `isHidden` value.
- **visibility-change-notification**: Component MUST invoke
  `onVisibilityChange` exactly once, after `isHidden` has been reassigned,
  each time `onChange` delivers a value that differs from the previous
  `isHidden` value.
- **visibility-change-callback**: Component MUST expose `onVisibilityChange`
  as a public, settable `(() -> Void)?` property.
- **dismiss-persistence**: Component MUST set the observed setting's value to
  `true` (`observer.value = true`) whenever `dismissButton` is clicked,
  unconditionally, regardless of the setting's current value.
- **main-actor-confinement**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.

## Appearance

- **Corner radius**: Not applicable — the component draws no shape of its
  own; no layer or corner radius is configured anywhere in
  `DismissibleHintView.swift`.
- **Padding**: 0pt of the component's own — the stack's top/leading/trailing/
  bottom are pinned directly to the view's edges with no additional constant
  (see `#platforms/swift` for the pinning mechanism). The internal gap
  between `textLabel` and `dismissButton` is 8pt
  (`SettingsLayout.default[.rowSpacing]`, `ViewLayout.swift`).
- **Font**: `textLabel` tracks the current theme's caption text role
  (`palette.font(.caption)`); weight/size are not literal in
  `DismissibleHintView.swift` — they come from the theme's `.caption`
  definition (`ThemeTypography.swift`). `dismissButton`'s font is `NSButton`'s
  own default system control font for a `.rounded`/`.small` bezel; no font is
  set explicitly on it in source.
- **Background**: Not applicable — no background color or layer is set on
  `DismissibleHintView` itself anywhere in source.
- **Foreground/Text**: `textLabel` uses `palette.secondaryTextColor`, a
  theme-resolved semantic color; `dismissButton`'s title color is `NSButton`'s
  default system coloring for a rounded bezel, not set explicitly in source.
- **Border**: Not applicable — no border is drawn or configured anywhere in
  `DismissibleHintView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `DismissibleHintView.swift`.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set on the view itself in source; because the stack is pinned
  to all four edges, the component's size follows the stack's own
  constraint-driven size (`textLabel`'s wrapping width and `dismissButton`'s
  intrinsic size).

## States

| State | Appearance change |
|-------|------------------|
| Default | `textLabel` and `dismissButton` are added inside the pinned stack; `isHidden` is set from `observer.value` before the view is ever displayed, so there is no unevaluated frame. |
| Visible (not yet dismissed) | `isHidden == false`. |
| Hidden (dismissed) | `isHidden == true`, set once the observed setting's value becomes `true` and is delivered through `onChange`; `onVisibilityChange` fires once on the transition. |
| Pressed | Not applicable to the composite view: `dismissButton`'s own pressed-bezel highlight is `NSButton`'s default system behavior, not custom-drawn by `DismissibleHintView`. |
| Disabled | Not implemented in `DismissibleHintView`; `isEnabled` is never read or set anywhere in source. |
| Focused | Not styled by `DismissibleHintView`; any focus ring belongs to `dismissButton`'s own default first-responder appearance — no custom focus handling appears in source. |
| Loading | Not applicable: the component performs no asynchronous operation and shows no loading indicator in source. |

## Accessibility

- **Role**: `textLabel` is `NSTextField(wrappingLabelWithString:)`, AppKit's
  standard read-only multi-line label, exposed to assistive technology as
  static text by default; `dismissButton` is a plain `NSButton`, exposed as a
  `button`. `DismissibleHintView` sets no custom accessibility role of its
  own.
- **Label requirements**: `textLabel`'s accessible content is exactly the
  `text` string passed at construction (`text-label`); `dismissButton`'s
  accessible name is `buttonTitle` (`dismiss-button-title`, default
  `"Got It"`). Neither carries an additional accessibility-label assignment
  in source.
- **Announce state changes**: Not applicable beyond AppKit's own default —
  setting `isHidden` removes the view, and its children, from the
  accessibility tree automatically; no custom VoiceOver announcement call
  appears in `DismissibleHintView.swift`.
- **Keyboard navigation**: Inherited from `NSButton` — Tab/Shift-Tab moves
  focus onto and off `dismissButton`, and Space or Return activates it
  through the target/action wired in `dismiss-button-action`.
  `DismissibleHintView` adds no custom key handling.
- **Minimum tap target**: `dismissButton` is explicitly sized `.small` with a
  `.rounded` bezel — smaller than AppKit's default "regular" push button (see
  `dismiss-button-style`); `DismissibleHintView.swift` sets no click-target
  override beyond `controlSize`, and macOS applies no touch-target minimum to
  a pointer-driven control at this size. Ports to touch platforms MUST give
  the equivalent control at least the platform minimum (44×44pt on iOS,
  48×48dp on Android, 40×40epx on WinUI 3).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| dismissible-hint-view-001 | text-label | `DismissibleHintView(text: "Enable launch at login", dismissedSetting: setting)` | `textLabel.stringValue == "Enable launch at login"`; `textLabel` wraps rather than truncates |
| dismissible-hint-view-002 | #platforms/swift | Construct the component, then read `.textLabel` from outside the type | Returns the same `NSTextField` instance the view displays |
| dismissible-hint-view-003 | text-label-theming | Construct the component, then trigger a theme change | `textLabel.textColor` and `textLabel.font` update to the new theme's secondary-text color and `.caption` font, both immediately at construction and again after the change |
| dismissible-hint-view-004 | dismiss-button-title | `DismissibleHintView(text: "…", dismissedSetting: setting, buttonTitle: "Dismiss")` | `dismissButton.title == "Dismiss"` |
| dismissible-hint-view-005 | dismiss-button-title-default | `DismissibleHintView(text: "…", dismissedSetting: setting)` (no `buttonTitle`) | `dismissButton.title == "Got It"` |
| dismissible-hint-view-006 | #platforms/swift | Construct the component, then read `.dismissButton` from outside the type | Returns the same `NSButton` instance the view displays |
| dismissible-hint-view-007 | dismiss-button-style | Construct the component | `dismissButton.bezelStyle == .rounded`; `dismissButton.controlSize == .small` |
| dismissible-hint-view-008 | dismiss-button-action | Construct the component, then simulate a click on `dismissButton` | The dismiss handler runs (verified by `dismiss-persistence`'s effect) |
| dismissible-hint-view-009 | stack-arrangement | Construct the component | The internal stack's `orientation == .vertical`, `alignment == .leading`, with `textLabel` before `dismissButton` in `arrangedSubviews` |
| dismissible-hint-view-010 | stack-spacing | Construct the component | The internal stack's `spacing == SettingsLayout.default[.rowSpacing]` (8pt) |
| dismissible-hint-view-011 | #platforms/swift | Construct the component | Active constraints pin the stack's top/leading/trailing/bottom anchors to the view's corresponding anchors, each with constant `0` |
| dismissible-hint-view-012 | #platforms/swift | Construct the component | `view.translatesAutoresizingMaskIntoConstraints == false` and the internal stack's is also `false` |
| dismissible-hint-view-013 | dismissed-setting-observation | Construct with a given `dismissedSetting` | The view's internal observer wraps that exact `UserSetting<Bool>` instance |
| dismissible-hint-view-014 | initial-visibility | Construct with `dismissedSetting.currentValue == true` | Immediately after `init` returns, `view.isHidden == true`, with no `onVisibilityChange` call |
| dismissible-hint-view-015 | initial-visibility | Construct with `dismissedSetting.currentValue == false` | Immediately after `init` returns, `view.isHidden == false` |
| dismissible-hint-view-016 | visibility-update | After construction with `isHidden == false`, change the setting's value to `true` and allow `onChange` to deliver | `view.isHidden == true` after delivery |
| dismissible-hint-view-017 | visibility-write-guard | With `view.isHidden == true` and a KVO observer registered on `isHidden`, cause `onChange` to redeliver `true` again | The KVO observer receives zero notifications for this delivery, and `onVisibilityChange`'s call count stays at zero |
| dismissible-hint-view-018 | visibility-change-notification | Register `onVisibilityChange`, then change the setting from `false` to `true` | `onVisibilityChange` is called exactly once, after `view.isHidden` has already become `true` |
| dismissible-hint-view-019 | visibility-change-callback | Assign a closure to `.onVisibilityChange` from outside the type, then trigger a visibility change | The assigned closure is the one invoked |
| dismissible-hint-view-020 | dismiss-persistence | Click `dismissButton` | `dismissedSetting`'s persisted value becomes `true` |
| dismissible-hint-view-021 | #platforms/swift | Attempt `DismissibleHintView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| dismissible-hint-view-022 | #platforms/swift | Attempt `DismissibleHintView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| dismissible-hint-view-023 | main-actor-confinement | Attempt to construct or mutate a `DismissibleHintView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| dismissible-hint-view-024 | self-hiding-conformance | Construct the component, then inspect its static type | `DismissibleHintView` conforms to both `SelfHidingSettingsView` and `SettingsViewProtocol` |

Vector `dismissible-hint-view-023` is a static/compile-time type check (Swift's
`@MainActor` isolation checking), not a runtime conformance assertion; vector
`dismissible-hint-view-024` is likewise a static/type-check vector (protocol
conformance), not a runtime behavior assertion.

## Edge Cases

- Null/empty input: `text` (`String`), `dismissedSetting`
  (`UserSetting<Bool>`), and `buttonTitle` (`String`, defaulted) are all
  non-optional, typed constructor parameters; Swift's type system rules out
  `nil` for any of them (MUST — the initializer needs no nil-handling path
  because none of its parameters can be `nil`).
- Empty `text` (`""`): renders an empty wrapping label; the row still lays
  out with its stack spacing and pinned edges around a zero-content label
  (MUST, per `text-label` — the source has no guard against an empty
  string).
- Very long `text`: `NSTextField(wrappingLabelWithString:)` wraps rather than
  truncates, and no maximum width is configured by `DismissibleHintView`
  itself; the label's width follows whatever width the pinned stack is given
  by its container (MUST, per `text-label`; the stack's own edge-pinning that
  determines the width it's given is documented under `#platforms/swift`).
- Boundary values: Not applicable — the component's only inputs are strings
  and a `UserSetting<Bool>`; it has no caller-configurable numeric range of
  its own (the 8pt row spacing is a fixed source constant, not a
  caller-supplied boundary).
- Concurrent access: Not applicable — the class is `@MainActor` (see
  `main-actor-confinement`), and `UserSettingObserver`'s `onChange` delivery
  is scheduled on the main dispatch queue, so every read of `observer.value`
  and every write to `isHidden` is serialized on the main actor.
- Error states: Not applicable — every operation in
  `DismissibleHintView.swift` (comparing `isHidden`, wiring target/action,
  reading/writing `observer.value`) is a synchronous, non-throwing call; no
  `try`, `Result`, or error-producing API appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads and writes an in-process
  `UserSetting` through `UserSettingObserver`.
- Delayed dismissal (asynchronous setting round-trip): tapping
  `dismissButton` sets `observer.value = true`, which writes through to
  `dismissedSetting.value`, persists via the underlying settings store, and
  only reaches this view's own `onChange` handler one main-queue turn later
  — through `UserSettingObserver`'s `.dropFirst().receive(on:
  DispatchQueue.main)` subscription (see `UserSetting.swift`) — not
  synchronously within the button-click call frame. A caller that taps and
  immediately inspects `isHidden` in the same call frame still sees the view
  visible; the hide happens on the following main-queue turn. This is a
  MUST-level, source-traceable consequence of the dependency this component
  observes through — the same underlying mechanism the sibling
  `ConditionalView` recipe (`agentictoolkit://recipes/conditional-view`)
  documents for its own observed setting.
- Repeated taps on `dismissButton`: each tap unconditionally sets
  `observer.value = true` again, with no read-back of the setting's current
  value first (MUST, per `dismiss-persistence`); the guard against a
  redundant *visibility* write lives in the `onChange` handler
  (`visibility-write-guard`), not in the tap handler itself, so a repeated or
  already-dismissed tap harmlessly re-assigns the same `true`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `text` | `String` | — (required) | The hint's message, rendered as `textLabel`'s wrapping label content. |
| `dismissedSetting` | `UserSetting<Bool>` | — (required) | The persisted flag this view reads and writes; the view hides itself once the setting's value becomes `true`. |
| `buttonTitle` | `String` | `"Got It"` | The dismiss button's title. |

## Deep Linking

Not applicable: `DismissibleHintView` is an inline hint row inside a
composable settings window, not a navigable screen; no URL scheme, route, or
deep-link handler appears anywhere in `DismissibleHintView.swift`.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — (no key; literal default parameter value) | "Got It" | `buttonTitle`'s default value when a caller constructs `DismissibleHintView` without supplying one |

NEEDS REVIEW: `buttonTitle`'s default value, the English literal `"Got It"`,
carries no localization key or lookup in source — `text` and any explicit
`buttonTitle` argument are the caller's responsibility to localize (the same
treatment as the sibling `Badge` recipe (`agentictoolkit://recipes/badge`)
gives fully caller-supplied text), but this one default value ships baked
directly into `DismissibleHintView.swift` itself. Whether every call site is
expected to always override `buttonTitle` explicitly (making the English
default effectively dead in a non-English build), or whether the framework
needs a localization convention for baked-in default control titles, cannot
be determined from this file alone; settled by the app's localization/i18n
owner auditing whether any call site relies on the default outside an
English locale.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source performs no animation, transition, or `NSAnimationContext` call; the `isHidden` change is an instantaneous assignment. |
| Increase Contrast | Not applicable to this component directly: `DismissibleHintView.swift` reads no system contrast setting; `textLabel`'s color is a theme-resolved semantic role (`palette.secondaryTextColor`) and `dismissButton`'s coloring is `NSButton`'s own system chrome, neither of which this file adjusts for contrast itself. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone — dismissal is structural (`isHidden`) and driven by a labeled button tap, not a color-only cue. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `DismissibleHintView.swift`; the view renders unconditionally whenever
constructed, subject only to `dismissedSetting`'s value.

## Analytics

Not applicable: `DismissibleHintView.swift` contains no analytics or
telemetry call. If impression or dismissal analytics are desired for a
specific onboarding hint, that instrumentation belongs to the caller
assembling the settings screen, not to this reusable leaf view.

## Privacy

- **Data collected**: None of its own — the component holds only the
  caller-supplied `text` and `buttonTitle` values and reads/writes the
  already-existing `dismissedSetting`'s value.
- **Storage**: Not applicable to this file — `DismissibleHintView` performs
  no read/write to disk, `UserDefaults`, or any other store directly;
  persistence of the dismissed flag is owned by `UserSetting`/
  `UserSettingObserver` (not part of this file), backed by whatever storage
  provider the app's `UserSettings.shared` is configured with.
- **Transmission**: Not applicable — no networking call appears anywhere in
  `DismissibleHintView.swift`; whether the configured storage provider syncs
  the setting elsewhere (e.g. iCloud) is a property of the app's settings
  configuration, not of this component.
- **Retention**: Not applicable — the view retains only `textLabel`,
  `dismissButton`, and its `UserSettingObserver` for its own lifetime; it
  persists nothing beyond that itself.

## Logging

Not applicable: `DismissibleHintView.swift` contains no logging call (no
`print`, `os_log`, or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: Bind `dismissedSetting`'s `@Published` value into `@State` (or
  observe it via a Combine publisher) and use structural conditional
  inclusion, `if !dismissed { VStack(alignment: .leading) { Text(text).font(.caption).foregroundStyle(.secondary); Button(buttonTitle) { dismissed = true } } }`,
  rather than `.hidden()` — SwiftUI removes the branch not taken from the
  view hierarchy the same way a hidden `NSView` drops out of an
  `NSStackView`, which is what `initial-visibility` and `visibility-update`
  ultimately exist to drive for a hosting container. Persist the tap through
  the same setting-backed store before flipping local state, mirroring
  `dismiss-persistence`. Because the `if` branch removes the view from the
  hierarchy structurally, the hosting container's own body re-evaluates and
  lays out around the gap automatically on the next diff — no
  `onVisibilityChange`-equivalent callback is needed for a SwiftUI-hosted
  container the way a fixed-layout `NSStackView`/`GroupView` needs the
  AppKit source's explicit notification.
- **Compose**: Collect the setting as `State<Boolean>` via `collectAsState()`
  and wrap the `Column { Text(...); Button(...) }` composition in `if
  (!dismissed) { ... }`. Persist the dismissal through the same
  `DataStore`/`SharedPreferences`-backed setting the composable observes,
  mirroring the durable, restart-surviving nature of `dismiss-persistence`;
  Compose's own recomposition already skips redundant redraws for an
  unchanged `State` value, so no extra guard is needed to mirror
  `visibility-write-guard`. Because `if (!dismissed)` removes the composable
  from composition, the hosting container recomposes and reflows around the
  gap on its own — Compose's declarative recomposition is itself the
  container-collapse signal, so no explicit `onVisibilityChange` analog is
  required the way the AppKit source's fixed-layout hosting `GroupView`
  needs one.
- **React/Web**: Subscribe to the setting's store with a hook (e.g.
  `useSyncExternalStore`) and render conditionally,
  `{!dismissed && <div className="hint"><p>{text}</p><button onClick={() => setDismissed(true)}>{buttonTitle}</button></div>}`.
  Route the click handler through the same persisted store the subscription
  reads, so a page reload still respects a prior dismissal, mirroring
  `dismiss-persistence` and the durability documented under Privacy. Because
  `{!dismissed && …}` removes the element from the rendered tree, React's own
  re-render lays out the surrounding flow around the gap automatically — the
  DOM's normal flow layout is the container-collapse signal, so no explicit
  `onVisibilityChange`-equivalent callback is required the way the AppKit
  source's fixed-layout hosting `GroupView` needs one.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/DismissibleHintView.swift`,
  with layout constants from `ViewLayout.swift`, the `SelfHidingSettingsView`
  contract from `GroupView.swift`/`SettingsViewProtocol.swift`, the
  persisted-setting plumbing from `UserSetting.swift`, and the theme
  synchronization from `ThemeBinding.swift`'s `observeTheme`. A macOS-only
  (`import AppKit`) `NSView` subclass, `@MainActor`, inside the
  `ComposableSettings` namespace. Beyond the cross-platform behavior in
  Behavioral Requirements, the AppKit implementation: exposes `textLabel` and
  `dismissButton` as public, read-only properties (`NSTextField`/`NSButton`)
  so a caller can inspect the exact instances the view displays; disables
  `translatesAutoresizingMaskIntoConstraints` on itself and on the internal
  stack; pins the stack's top/leading/trailing/bottom anchors to its own
  corresponding edges with no additional constant (`pinToEdges`); and traps
  with a fatal error on both `init(coder:)` and the frame-only
  `init(frame:)`, since the only supported construction path is the
  designated `init(text:dismissedSetting:buttonTitle:)`. There is no UIKit
  code path in source; a UIKit port would replace
  `NSTextField`/`NSButton`/`NSStackView` with `UILabel`/`UIButton`/
  `UIStackView`, use `UIView.isHidden` (the same removal-from-layout
  semantics apply within a `UIStackView`), would still need its own
  `translatesAutoresizingMaskIntoConstraints`/pinning equivalent, and would
  have no `NSCoder`-vs-frame initializer split to fatal-error on the way this
  source's designated-initializer-only construction does.
- **WinUI 3** (the reason this recipe exists): Prefer an inline `InfoBar`
  (`IsOpen` bound one-way to the observed setting via a converter,
  `IsClosable="False"`, `Severity="Informational"`) or a `StackPanel` whose
  `Visibility` is bound the same way, over `TeachingTip` — a `TeachingTip` is
  a light-dismiss popup that floats outside the layout flow and can't
  collapse a card row's own padding and hairline the way
  `self-hiding-conformance`/`onVisibilityChange` needs to, and its own
  light-dismiss/close paths would fall out of sync with a one-way
  `IsOpen`/`Visibility` binding driven solely by the setting. Bind
  `IsOpen`/`Visibility` one-way, via `x:Bind`, to a value converter over the
  observed setting (`IsOpen="{x:Bind Setting.Value, Converter={StaticResource
  IsDismissedToIsOpenConverter}, Mode=OneWay}"`), guarding the converter so it
  only flips the bound value when the resolved value actually differs from
  the current one — the WinUI analog of
  `visibility-write-guard`/`visibility-change-notification`. Set the
  `InfoBar`'s `Message` (or the `StackPanel`'s child `TextBlock.Text`) to the
  hint text (mirroring `text-label-theming`'s theme-styled caption text), and
  bind the dismiss control's content/title to `buttonTitle` — never hardcode
  `"Got It"` — with its click handler writing the observed setting's
  persisted value to `true` — the same write-through-the-store-first pattern
  `dismiss-persistence` uses, rather than setting `IsOpen`/`Visibility` to
  closed/collapsed directly in the click handler — so a restart still
  respects a prior dismissal (see Privacy) and the async round trip
  documented in Edge Cases has a direct analog.

## Design Decisions

- **Decision**: Copy the observed setting's current value directly into
  `isHidden` at the end of `init` (`self.isHidden = self.observer.value`),
  rather than routing the initial state through the same `onChange`
  guard/notify path used for later changes.
  **Rationale**: A synchronous initial assignment prevents the view from
  rendering visible-by-default until the observer's first,
  asynchronously-delivered change notification arrives, and avoids firing
  `onVisibilityChange` for a hosting `GroupView` before that view has even
  finished adding this row — the same reasoning the sibling `ConditionalView`
  recipe (`agentictoolkit://recipes/conditional-view`) documents for its own
  initial-visibility evaluation.
  **Approved**: pending
- **Decision**: Guard the `onChange` handler with `dismissed != self.isHidden`
  before writing `isHidden` or invoking `onVisibilityChange`.
  **Rationale**: Without the guard, any redelivery of the observed setting's
  value would re-trigger a hosting `GroupView`'s separator/padding recompute
  even when this view's own visibility hasn't actually changed.
  **Approved**: pending
- **Decision**: `dismissTapped` unconditionally sets `observer.value = true`,
  with no check of the setting's current value first.
  **Rationale**: The visible-to-dismissed transition only runs one way —
  there is no "undismiss" affordance on the view — so an unconditional write
  costs nothing extra even if tapped on an already-dismissed hint; the
  visibility guard lives in the `onChange` handler, not in the tap handler.
  **Approved**: pending
- **Decision**: Route dismissal through the persisted `dismissedSetting` and
  its `UserSettingObserver`'s asynchronous `onChange` delivery, rather than
  setting `isHidden = true` directly inside `dismissTapped`.
  **Rationale**: This makes "dismissed" a durable, app-restart-surviving fact
  (see Privacy: Storage) instead of transient view state, at the cost of the
  one-main-queue-turn delay between the tap and the view actually hiding
  documented under Edge Cases.
  **Approved**: pending
- **Decision**: Default `buttonTitle` to the English literal `"Got It"`
  rather than requiring every call site to supply a title.
  **Rationale**: Keeps single-hint call sites terse for the common case; see
  Localization for the open question this default creates for call sites
  that never override it.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | passed | Platform Compliance |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | partial | Internationalization |

Statuses rest on `DismissibleHintView.swift`: `NSTextField`/`NSButton`/
`NSStackView` are native, unmodified system controls with default
accessibility support (screen-reader-support, keyboard-navigable,
native-controls-preference); `observeTheme` re-applies theme-resolved
color/font on every appearance change (platform-theming); `dismissTapped`
writes `true` unconditionally regardless of the setting's current value
(idempotent-operations); and `buttonTitle`'s default parameter value
`"Got It"` is a literal baked into the initializer while `text` and any
caller-supplied `buttonTitle` are not (no-hardcoded-strings: partial).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial recipe — extracted from the Apple `DismissibleHintView` (AppKit, macOS) source. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: moved AppKit-only mechanics (property exposure, Auto Layout pinning/autoresizing, coder/frame traps) from Behavioral Requirements to Platform Notes; renamed every requirement to subject-noun form and updated all citations; added the self-hiding-conformance requirement and test vector; rewrote the WinUI 3 bullet from TeachingTip to a binding-driven InfoBar/StackPanel with a bound (not hardcoded) button title; fixed the spacing test vector to compare against the layout token, the redundant-write vector to use an observable KVO signal, and marked the main-actor and conformance vectors as static checks; dropped the uncited HIG claim and the malformed-trap-message edge case; reformatted Design Decisions to the bolded three-line form; rebuilt Compliance with real catalog checks in Title Case categories; added full agentictoolkit:// URLs to sibling-recipe cross-references. |
