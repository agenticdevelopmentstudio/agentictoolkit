---
id: f3d7adbb-ece4-4b00-97af-f7e3db9d5999
title: DismissibleHintView
domain: agentictoolkit://recipes/dismissible-hint-view
type: ingredient
version: 1.0.0
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
protocol the sibling `ConditionalView` conforms to for the same reason.

## Behavioral Requirements

- **builds-text-label-from-wrapping-field**: Component MUST create `textLabel`
  as `NSTextField(wrappingLabelWithString: text)`, using the caller-supplied
  hint text.
- **exposes-text-label-property**: Component MUST expose `textLabel` as a
  public, read-only property.
- **styles-text-label-from-theme**: Component MUST set `textLabel`'s text
  color to the current theme's secondary text color
  (`palette.secondaryTextColor`) and its font to the current theme's caption
  text role (`palette.font(.caption)`), applied immediately at construction
  and re-applied on every subsequent theme change (via `observeTheme`).
- **creates-dismiss-button-with-caller-title**: Component MUST create
  `dismissButton` as an `NSButton` whose title is `buttonTitle`.
- **defaults-dismiss-button-title**: Component MUST default `buttonTitle` to
  `"Got It"` when the caller does not supply one.
- **exposes-dismiss-button-property**: Component MUST expose `dismissButton`
  as a public, read-only property.
- **styles-dismiss-button-as-small-rounded**: Component MUST set
  `dismissButton.bezelStyle = .rounded` and `dismissButton.controlSize =
  .small`.
- **wires-dismiss-button-action**: Component MUST set `dismissButton`'s
  target to itself and its action to the internal dismiss handler after
  construction, so that clicking the button invokes it.
- **arranges-label-and-button-vertically**: Component MUST arrange
  `textLabel` above `dismissButton` in a vertical `NSStackView` with leading
  alignment.
- **spaces-stack-by-row-spacing**: Component MUST set the vertical stack's
  `spacing` to `SettingsLayout.default[.rowSpacing]`, which resolves to 8pt
  (`ViewLayout.swift`).
- **pins-stack-to-edges**: Component MUST pin the stack's top, leading,
  trailing, and bottom anchors to its own corresponding edges with no
  additional constant (`pinToEdges`).
- **disables-autoresizing-mask**: Component MUST set
  `translatesAutoresizingMaskIntoConstraints = false` on itself and on the
  internal stack.
- **observes-dismissed-setting**: Component MUST wrap the caller-supplied
  `dismissedSetting` (`UserSetting<Bool>`) in an internal
  `UserSettingObserver<Bool>` at construction.
- **hides-initially-when-already-dismissed**: Component MUST set `isHidden`
  to the observed setting's current value (`observer.value`) at the end of
  initialization, before the view is ever displayed, without invoking
  `onVisibilityChange`.
- **updates-hidden-state-on-setting-change**: Component MUST set `isHidden`
  to the new value whenever the observed `UserSettingObserver`'s `onChange`
  fires with a value different from the view's current `isHidden`.
- **skips-redundant-visibility-writes**: Component MUST NOT write to
  `isHidden` and MUST NOT invoke `onVisibilityChange` when the value
  delivered by `onChange` equals the view's current `isHidden` value.
- **notifies-visibility-change-once**: Component MUST invoke
  `onVisibilityChange` exactly once, after `isHidden` has been reassigned,
  each time `onChange` delivers a value that differs from the previous
  `isHidden` value.
- **exposes-visibility-change-callback**: Component MUST expose
  `onVisibilityChange` as a public, settable `(() -> Void)?` property.
- **marks-setting-dismissed-on-tap**: Component MUST set the observed
  setting's value to `true` (`observer.value = true`) whenever
  `dismissButton` is clicked, unconditionally, regardless of the setting's
  current value.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.

## Appearance

- **Corner radius**: Not applicable — the component draws no shape of its
  own; no layer or corner radius is configured anywhere in
  `DismissibleHintView.swift`.
- **Padding**: 0pt of the component's own — `pinToEdges` pins the stack's
  top/leading/trailing/bottom directly to the view's edges with no additional
  constant. The internal gap between `textLabel` and `dismissButton` is 8pt
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
  `text` string passed at construction (`builds-text-label-from-wrapping-field`);
  `dismissButton`'s accessible name is `buttonTitle`
  (`creates-dismiss-button-with-caller-title`, default `"Got It"`). Neither
  carries an additional accessibility-label assignment in source.
- **Announce state changes**: Not applicable beyond AppKit's own default —
  setting `isHidden` removes the view, and its children, from the
  accessibility tree automatically; no custom VoiceOver announcement call
  appears in `DismissibleHintView.swift`.
- **Keyboard navigation**: Inherited from `NSButton` — Tab/Shift-Tab moves
  focus onto and off `dismissButton`, and Space or Return activates it
  through the target/action wired in `wires-dismiss-button-action`.
  `DismissibleHintView` adds no custom key handling.
- **Minimum tap target**: `dismissButton` is explicitly sized `.small` with a
  `.rounded` bezel — smaller than AppKit's default "regular" push button —
  matching the macOS Human Interface Guidelines' system metrics for
  pointer-driven controls; `DismissibleHintView.swift` sets no click-target
  override beyond `controlSize`. Ports to touch platforms MUST give the
  equivalent control at least the platform minimum (44×44pt on iOS, 48×48dp
  on Android, 40×40epx on WinUI 3).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| dismissible-hint-view-001 | builds-text-label-from-wrapping-field | `DismissibleHintView(text: "Enable launch at login", dismissedSetting: setting)` | `textLabel.stringValue == "Enable launch at login"`; `textLabel` wraps rather than truncates |
| dismissible-hint-view-002 | exposes-text-label-property | Construct the component, then read `.textLabel` from outside the type | Returns the same `NSTextField` instance the view displays |
| dismissible-hint-view-003 | styles-text-label-from-theme | Construct the component, then trigger a theme change | `textLabel.textColor` and `textLabel.font` update to the new theme's secondary-text color and `.caption` font, both immediately at construction and again after the change |
| dismissible-hint-view-004 | creates-dismiss-button-with-caller-title | `DismissibleHintView(text: "…", dismissedSetting: setting, buttonTitle: "Dismiss")` | `dismissButton.title == "Dismiss"` |
| dismissible-hint-view-005 | defaults-dismiss-button-title | `DismissibleHintView(text: "…", dismissedSetting: setting)` (no `buttonTitle`) | `dismissButton.title == "Got It"` |
| dismissible-hint-view-006 | exposes-dismiss-button-property | Construct the component, then read `.dismissButton` from outside the type | Returns the same `NSButton` instance the view displays |
| dismissible-hint-view-007 | styles-dismiss-button-as-small-rounded | Construct the component | `dismissButton.bezelStyle == .rounded`; `dismissButton.controlSize == .small` |
| dismissible-hint-view-008 | wires-dismiss-button-action | Construct the component, then simulate a click on `dismissButton` | The dismiss handler runs (verified by `marks-setting-dismissed-on-tap`'s effect) |
| dismissible-hint-view-009 | arranges-label-and-button-vertically | Construct the component | The internal stack's `orientation == .vertical`, `alignment == .leading`, with `textLabel` before `dismissButton` in `arrangedSubviews` |
| dismissible-hint-view-010 | spaces-stack-by-row-spacing | Construct the component | The internal stack's `spacing == 8.0` |
| dismissible-hint-view-011 | pins-stack-to-edges | Construct the component | Active constraints pin the stack's top/leading/trailing/bottom anchors to the view's corresponding anchors, each with constant `0` |
| dismissible-hint-view-012 | disables-autoresizing-mask | Construct the component | `view.translatesAutoresizingMaskIntoConstraints == false` and the internal stack's is also `false` |
| dismissible-hint-view-013 | observes-dismissed-setting | Construct with a given `dismissedSetting` | The view's internal observer wraps that exact `UserSetting<Bool>` instance |
| dismissible-hint-view-014 | hides-initially-when-already-dismissed | Construct with `dismissedSetting.currentValue == true` | Immediately after `init` returns, `view.isHidden == true`, with no `onVisibilityChange` call |
| dismissible-hint-view-015 | hides-initially-when-already-dismissed | Construct with `dismissedSetting.currentValue == false` | Immediately after `init` returns, `view.isHidden == false` |
| dismissible-hint-view-016 | updates-hidden-state-on-setting-change | After construction with `isHidden == false`, change the setting's value to `true` and allow `onChange` to deliver | `view.isHidden == true` after delivery |
| dismissible-hint-view-017 | skips-redundant-visibility-writes | With `view.isHidden == true`, cause `onChange` to redeliver `true` again | `isHidden`'s setter is not invoked again and `onVisibilityChange` is not called for this delivery |
| dismissible-hint-view-018 | notifies-visibility-change-once | Register `onVisibilityChange`, then change the setting from `false` to `true` | `onVisibilityChange` is called exactly once, after `view.isHidden` has already become `true` |
| dismissible-hint-view-019 | exposes-visibility-change-callback | Assign a closure to `.onVisibilityChange` from outside the type, then trigger a visibility change | The assigned closure is the one invoked |
| dismissible-hint-view-020 | marks-setting-dismissed-on-tap | Click `dismissButton` | `dismissedSetting`'s persisted value becomes `true` |
| dismissible-hint-view-021 | requires-designated-initializer | Attempt `DismissibleHintView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| dismissible-hint-view-022 | rejects-frame-only-initialization | Attempt `DismissibleHintView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| dismissible-hint-view-023 | confines-to-main-actor | Attempt to construct or mutate a `DismissibleHintView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |

## Edge Cases

- Null/empty input: `text` (`String`), `dismissedSetting`
  (`UserSetting<Bool>`), and `buttonTitle` (`String`, defaulted) are all
  non-optional, typed constructor parameters; Swift's type system rules out
  `nil` for any of them (MUST — the initializer needs no nil-handling path
  because none of its parameters can be `nil`).
- Empty `text` (`""`): renders an empty wrapping label; the row still lays
  out with its stack spacing and pinned edges around a zero-content label
  (MUST, per `builds-text-label-from-wrapping-field` — the source has no
  guard against an empty string).
- Very long `text`: `NSTextField(wrappingLabelWithString:)` wraps rather than
  truncates, and no maximum width is configured by `DismissibleHintView`
  itself; the label's width follows whatever width the pinned stack is given
  by its container (MUST, per `builds-text-label-from-wrapping-field` and
  `pins-stack-to-edges`).
- Boundary values: Not applicable — the component's only inputs are strings
  and a `UserSetting<Bool>`; it has no caller-configurable numeric range of
  its own (the 8pt row spacing is a fixed source constant, not a
  caller-supplied boundary).
- Concurrent access: Not applicable — the class is `@MainActor` (see
  `confines-to-main-actor`), and `UserSettingObserver`'s `onChange` delivery
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
  `ConditionalView` recipe documents for its own observed setting.
- Malformed frame-only-initializer trap message: the `init(frame:)`
  override's `fatalError` message string in source,
  `init(frame frameRect: NSRect`, is missing its closing parenthesis. The
  initializer still traps unconditionally on every call; only the trap's
  message text is affected, not `rejects-frame-only-initialization` itself.
- Repeated taps on `dismissButton`: each tap unconditionally sets
  `observer.value = true` again, with no read-back of the setting's current
  value first (MUST, per `marks-setting-dismissed-on-tap`); the guard against
  a redundant *visibility* write lives in the `onChange` handler
  (`skips-redundant-visibility-writes`), not in the tap handler itself, so a
  repeated or already-dismissed tap harmlessly re-assigns the same `true`.

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
treatment as the sibling `Badge` recipe gives fully caller-supplied text),
but this one default value ships baked directly into
`DismissibleHintView.swift` itself. Whether every call site is expected to
always override `buttonTitle` explicitly (making the English default
effectively dead in a non-English build), or whether the framework needs a
localization convention for baked-in default control titles, cannot be
determined from this file alone; settled by the app's localization/i18n
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
  `NSStackView`, which is what `hides-initially-when-already-dismissed` and
  `updates-hidden-state-on-setting-change` ultimately exist to drive for a
  hosting container. Persist the tap through the same setting-backed store
  before flipping local state, mirroring `marks-setting-dismissed-on-tap`.
- **Compose**: Collect the setting as `State<Boolean>` via `collectAsState()`
  and wrap the `Column { Text(...); Button(...) }` composition in `if
  (!dismissed) { ... }`. Persist the dismissal through the same
  `DataStore`/`SharedPreferences`-backed setting the composable observes,
  mirroring the durable, restart-surviving nature of
  `marks-setting-dismissed-on-tap`; Compose's own recomposition already
  skips redundant redraws for an unchanged `State` value, so no extra guard
  is needed to mirror `skips-redundant-visibility-writes`.
- **React/Web**: Subscribe to the setting's store with a hook (e.g.
  `useSyncExternalStore`) and render conditionally,
  `{!dismissed && <div className="hint"><p>{text}</p><button onClick={() => setDismissed(true)}>{buttonTitle}</button></div>}`.
  Route the click handler through the same persisted store the subscription
  reads, so a page reload still respects a prior dismissal, mirroring
  `marks-setting-dismissed-on-tap` and the durability documented under
  Privacy.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/DismissibleHintView.swift`,
  with layout constants from `ViewLayout.swift`, the `SelfHidingSettingsView`
  contract from `GroupView.swift`/`SettingsViewProtocol.swift`, the
  persisted-setting plumbing from `UserSetting.swift`, and the theme
  synchronization from `ThemeBinding.swift`'s `observeTheme`. A macOS-only
  (`import AppKit`) `NSView` subclass, `@MainActor`, inside the
  `ComposableSettings` namespace. There is no UIKit code path in source; a
  UIKit port would replace `NSTextField`/`NSButton`/`NSStackView` with
  `UILabel`/`UIButton`/`UIStackView`, use `UIView.isHidden` (the same
  removal-from-layout semantics apply within a `UIStackView`), and would have
  no `NSCoder`-vs-frame initializer split to fatal-error on the way
  `requires-designated-initializer` and `rejects-frame-only-initialization`
  do here.
- **WinUI 3** (the reason this recipe exists): Start from a `TeachingTip` —
  the WinUI control purpose-built for a coachmark-style, dismissible hint
  with an action button, matching the source's own doc comment almost
  exactly. Bind `IsOpen` one-way, via `x:Bind`, to a value converter over the
  observed setting (`IsOpen="{x:Bind Setting.Value, Converter={StaticResource
  IsDismissedToIsOpenConverter}, Mode=OneWay}"`), guarding the converter so it
  only flips `IsOpen` when the resolved value actually differs from the
  current one — the WinUI analog of
  `skips-redundant-visibility-writes`/`notifies-visibility-change-once`. Set
  `Subtitle` (or `Content`) to the hint text (mirroring
  `builds-text-label-from-wrapping-field`'s theme-styled caption text), and
  set `ActionButtonContent="Got It"` with `ActionButtonClick` writing the
  observed setting's persisted value to `true` — the same
  write-through-the-store-first pattern `marks-setting-dismissed-on-tap`
  uses, rather than setting `IsOpen = false` directly in the click handler —
  so a restart still respects a prior dismissal (see Privacy) and the async
  round trip documented in Edge Cases has a direct analog. Suppress
  `TeachingTip`'s own default close (`X`) button
  (`CloseButtonContent=x:Null`) if the design calls for the single "Got It"
  affordance the source exposes, since `DismissibleHintView` itself defines
  only one dismiss control.

## Design Decisions

- Decision: Copy the observed setting's current value directly into
  `isHidden` at the end of `init` (`self.isHidden = self.observer.value`),
  rather than routing the initial state through the same `onChange`
  guard/notify path used for later changes.
  Rationale: A synchronous initial assignment prevents the view from
  rendering visible-by-default until the observer's first,
  asynchronously-delivered change notification arrives, and avoids firing
  `onVisibilityChange` for a hosting `GroupView` before that view has even
  finished adding this row — the same reasoning the sibling `ConditionalView`
  recipe documents for its own initial-visibility evaluation.
  Approved: pending
- Decision: Guard the `onChange` handler with `dismissed != self.isHidden`
  before writing `isHidden` or invoking `onVisibilityChange`.
  Rationale: Without the guard, any redelivery of the observed setting's
  value would re-trigger a hosting `GroupView`'s separator/padding recompute
  even when this view's own visibility hasn't actually changed.
  Approved: pending
- Decision: `dismissTapped` unconditionally sets `observer.value = true`,
  with no check of the setting's current value first.
  Rationale: The visible-to-dismissed transition only runs one way — there
  is no "undismiss" affordance on the view — so an unconditional write costs
  nothing extra even if tapped on an already-dismissed hint; the visibility
  guard lives in the `onChange` handler, not in the tap handler.
  Approved: pending
- Decision: Route dismissal through the persisted `dismissedSetting` and its
  `UserSettingObserver`'s asynchronous `onChange` delivery, rather than
  setting `isHidden = true` directly inside `dismissTapped`.
  Rationale: This makes "dismissed" a durable, app-restart-surviving fact
  (see Privacy: Storage) instead of transient view state, at the cost of the
  one-main-queue-turn delay between the tap and the view actually hiding
  documented under Edge Cases.
  Approved: pending
- Decision: Default `buttonTitle` to the English literal `"Got It"` rather
  than requiring every call site to supply a title.
  Rationale: Keeps single-hint call sites terse for the common case; see
  Localization for the open question this default creates for call sites
  that never override it.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [theme-driven-typography](agenticdevelopercookbook://compliance/ui-tokens#theme-driven-typography) | passed | ui-tokens |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | architecture |
| [localizable-strings](agenticdevelopercookbook://compliance/i18n#localizable-strings) | needs-review | i18n |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial recipe — extracted from the Apple `DismissibleHintView` (AppKit, macOS) source. |
