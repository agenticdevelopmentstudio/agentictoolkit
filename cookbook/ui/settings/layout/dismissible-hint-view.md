---
id: f3d7adbb-ece4-4b00-97af-f7e3db9d5999
title: Dismissible Hint View
domain: agentictoolkit://cookbook/ui/settings/layout/dismissible-hint-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings row pairing a hint label with a dismiss button that
  persists a setting and hides itself once dismissed.
platforms:
- swift
- macos
tags:
- settings
- onboarding
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/layout/conditional-view
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
approved-by: ''
approved-date: ''
---

# Dismissible Hint View

## Overview

The dismissible hint view is a settings row pairing a wrapping hint label
with a small dismiss button. It is a "coachmark-style hint" that hides
itself once its backing setting flips to `true`, intended for one-time
onboarding prompts such as "enable launch at login so you never miss a
session." It self-reports visibility changes so a hosting group view can
collapse the padding and hairline around a card row whose content has
hidden itself, rather than leaving an empty band behind — the same
mechanism the sibling conditional view recipe
(`agentictoolkit://cookbook/ui/settings/layout/conditional-view`) uses for
the same reason.

## Behavioral Requirements

- **self-hiding-conformance**: Component MUST self-report its own
  visibility so a hosting group view can collapse a card row's padding and
  hairline once this component's content has hidden itself.
- **text-label**: Component MUST create its hint label using the
  caller-supplied hint text; the label wraps rather than truncates.
- **text-label-theming**: Component MUST set the hint label's text color
  to the current theme's secondary text color and its font to the current
  theme's caption text role, applied immediately at construction and
  re-applied on every subsequent theme change.
- **dismiss-button-title**: Component MUST create its dismiss button with
  a title equal to the caller-supplied button title.
- **dismiss-button-title-default**: Component MUST default the button
  title to `"Got It"` when the caller does not supply one.
- **dismiss-button-style**: Component MUST render its dismiss button in a
  small, rounded button style.
- **dismiss-button-action**: Component MUST wire its dismiss button so
  that clicking it invokes the component's dismiss handling.
- **stack-arrangement**: Component MUST arrange the hint label above the
  dismiss button in a vertical stack with leading alignment.
- **stack-spacing**: Component MUST set the vertical stack's spacing to
  the standard row spacing, 8pt.
- **dismissed-setting-observation**: Component MUST observe the
  caller-supplied dismissed-setting for changes, beginning at
  construction.
- **initial-visibility**: Component MUST set its shown/hidden state to the
  observed setting's current value at the end of initialization, before
  the view is ever displayed, without invoking the visibility-change
  callback.
- **visibility-update**: Component MUST update its shown/hidden state to
  the new value whenever the observed setting reports a change different
  from the component's current state.
- **visibility-write-guard**: Component MUST NOT change its shown/hidden
  state and MUST NOT invoke the visibility-change callback when the
  delivered value equals the component's current state.
- **visibility-change-notification**: Component MUST invoke the
  visibility-change callback exactly once, after its shown/hidden state
  has changed, each time a delivered value differs from the previous
  state.
- **visibility-change-callback**: Component MUST expose a
  visibility-change callback as a public, settable, optional property.
- **dismiss-persistence**: Component MUST set the observed setting's
  value to `true` whenever the dismiss button is clicked, unconditionally,
  regardless of the setting's current value.

## Appearance

- **Corner radius**: Not applicable — the component draws no shape of its
  own; no layer or corner radius is configured.
- **Padding**: 0pt of the component's own — the stack's top/leading/
  trailing/bottom are pinned directly to the component's edges with no
  additional constant (see Platform Notes for the pinning mechanism). The
  internal gap between the hint label and the dismiss button is 8pt (the
  standard row-spacing token).
- **Font**: the hint label tracks the current theme's caption text role;
  weight/size are not literal here — they come from the theme's caption
  definition. The dismiss button's font is the platform's own default
  system control font for its compact rounded style; no font is set
  explicitly on it.
- **Background**: Not applicable — no background color or layer is set on
  the component itself.
- **Foreground/Text**: the hint label uses the theme's secondary text
  color, a theme-resolved semantic color; the dismiss button's title
  color is the platform's default system coloring for its style, not set
  explicitly.
- **Border**: Not applicable — no border is drawn or configured.
- **Shadow**: Not applicable — no shadow is drawn or configured.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set on the component itself; because the stack is pinned
  to all four edges, the component's size follows the stack's own
  constraint-driven size (the hint label's wrapping width and the dismiss
  button's intrinsic size).

## States

| State | Appearance change |
|-------|------------------|
| Default | The hint label and dismiss button are added inside the pinned stack; the shown/hidden state is set from the observed setting's value before the view is ever displayed, so there is no unevaluated frame. |
| Visible (not yet dismissed) | Shown. |
| Hidden (dismissed) | Hidden, set once the observed setting's value becomes `true` and is delivered through the observer; the visibility-change callback fires once on the transition. |
| Pressed | Not applicable to the composite view: the dismiss button's own pressed-state highlight is the platform's default system behavior, not custom-drawn by this component. |
| Disabled | Not implemented; an enabled/disabled concept is never read or set. |
| Focused | Not styled by the component; any focus ring belongs to the dismiss button's own default focus appearance — no custom focus handling applies. |
| Loading | Not applicable: the component performs no asynchronous operation and shows no loading indicator. |

## Accessibility

- **Role**: the hint label is a standard read-only, multi-line label,
  exposed to assistive technology as static text by default; the dismiss
  button is exposed as a button. The component sets no custom
  accessibility role of its own.
- **Label requirements**: the hint label's accessible content is exactly
  the text string passed at construction (text-label); the dismiss
  button's accessible name is the button title (dismiss-button-title,
  default `"Got It"`). Neither carries an additional accessibility-label
  assignment.
- **Announce state changes**: Not applicable beyond the platform's own
  default behavior — hiding the component removes it, and its children,
  from the accessibility tree automatically; no custom screen-reader
  announcement is made.
- **Keyboard navigation**: Inherited from the platform's standard button
  control — Tab/Shift-Tab moves focus onto and off the dismiss button, and
  Space or Return activates it through the action wired in
  dismiss-button-action. The component adds no custom key handling.
- **Minimum tap target**: the dismiss button is deliberately rendered
  small and compact (see dismiss-button-style) — smaller than the
  platform's default push-button size — and the pointer-driven source
  platform applies no touch-target minimum to a control at this size.
  Ports to touch platforms MUST give the equivalent control at least the
  platform minimum (44×44pt on iOS, 48×48dp on Android, 40×40epx on
  WinUI 3).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| dismissible-hint-view-001 | text-label | Construct the component with hint text `"Enable launch at login"` | The hint label's content equals `"Enable launch at login"`; the label wraps rather than truncates |
| dismissible-hint-view-002 | #platforms/swift | Construct the component, then read its hint-label property from outside the type | Returns the same view instance the component uses for its hint label |
| dismissible-hint-view-003 | text-label-theming | Construct the component, then trigger a theme change | The hint label's color and font update to the new theme's secondary-text color and caption font, both immediately at construction and again after the change |
| dismissible-hint-view-004 | dismiss-button-title | Construct the component with an explicit button title of `"Dismiss"` | The dismiss button's title equals `"Dismiss"` |
| dismissible-hint-view-005 | dismiss-button-title-default | Construct the component with no button title supplied | The dismiss button's title equals `"Got It"` |
| dismissible-hint-view-006 | #platforms/swift | Construct the component, then read its dismiss-button property from outside the type | Returns the same view instance the component uses for its dismiss button |
| dismissible-hint-view-007 | dismiss-button-style | Construct the component | The dismiss button renders in the component's small, rounded button style |
| dismissible-hint-view-008 | dismiss-button-action | Construct the component, then simulate a click on the dismiss button | The dismiss handling runs (verified by dismiss-persistence's effect) |
| dismissible-hint-view-009 | stack-arrangement | Construct the component | The internal stack is vertical, leading-aligned, with the hint label before the dismiss button |
| dismissible-hint-view-010 | stack-spacing | Construct the component | The internal stack's spacing equals the standard row spacing (8pt) |
| dismissible-hint-view-011 | #platforms/swift | Construct the component | Active layout constraints pin the stack's top/leading/trailing/bottom edges to the component's corresponding edges, each with a zero offset |
| dismissible-hint-view-012 | #platforms/swift | Construct the component | The component and its internal stack both opt out of any implicit frame-based sizing |
| dismissible-hint-view-013 | dismissed-setting-observation | Construct with a given dismissed-setting | The component's internal observer wraps that exact setting instance |
| dismissible-hint-view-014 | initial-visibility | Construct with the dismissed-setting's current value equal to `true` | Immediately after construction, the component is hidden, with no visibility-change callback invoked |
| dismissible-hint-view-015 | initial-visibility | Construct with the dismissed-setting's current value equal to `false` | Immediately after construction, the component is shown |
| dismissible-hint-view-016 | visibility-update | After construction while shown, change the setting's value to `true` and allow the change to deliver | The component becomes hidden after delivery |
| dismissible-hint-view-017 | visibility-write-guard | With the component hidden, cause the observed value to redeliver `true` again | The component's shown/hidden state is not reassigned for this delivery, and the visibility-change callback's call count stays at zero |
| dismissible-hint-view-018 | visibility-change-notification | Register the visibility-change callback, then change the setting from `false` to `true` | The callback is called exactly once, after the component has already become hidden |
| dismissible-hint-view-019 | visibility-change-callback | Assign a callback to the visibility-change property from outside the type, then trigger a visibility change | The assigned callback is the one invoked |
| dismissible-hint-view-020 | dismiss-persistence | Click the dismiss button | The dismissed-setting's persisted value becomes `true` |
| dismissible-hint-view-021 | self-hiding-conformance | Construct the component | The component exposes a visibility-change callback and identifies itself to a hosting container as capable of self-hiding |

Vector `dismissible-hint-view-021` is a static/type-check vector (verifying
the component identifies itself to hosting containers as self-hiding), not
a runtime behavior assertion.

## Edge Cases

- Null/empty input: the hint text, the dismissed-setting, and the button
  title (defaulted) are all required, non-optional inputs to construction,
  so there is no null/empty case for any of them to handle (MUST — the
  constructor needs no nil-handling path because none of its inputs can be
  absent).
- Empty text (`""`): renders an empty wrapping label; the row still lays
  out with its stack spacing and pinned edges around a zero-content label
  (MUST, per `text-label` — there is no guard against an empty string).
- Very long text: the hint label wraps rather than truncates, and no
  maximum width is configured by the component itself; the label's width
  follows whatever width the pinned stack is given by its container (MUST,
  per `text-label`; the stack's own edge-pinning that determines the
  width it's given is documented under Platform Notes).
- Boundary values: Not applicable — the component's only inputs are text
  values and a boolean-backed setting; it has no caller-configurable
  numeric range of its own (the 8pt row spacing is a fixed constant, not a
  caller-supplied boundary).
- Concurrent access: Not applicable — the component is confined to a
  single UI thread (see Platform Notes), and the observed setting's
  change delivery is scheduled on that same thread, so every read of the
  setting's value and every visibility write is serialized.
- Error states: Not applicable — every operation (comparing shown/hidden
  state, wiring the dismiss action, reading/writing the setting's value)
  is a synchronous, non-throwing call; no error-producing path exists.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads and writes an in-process setting
  through its observer.
- Delayed dismissal (asynchronous setting round-trip): tapping the dismiss
  button sets the observed setting's value to `true`, which persists via
  the underlying settings store, and only reaches the component's own
  change handler on a following turn of the main run loop — not
  synchronously within the button-click call frame. A caller that taps and
  immediately inspects the component's shown/hidden state in the same
  call frame still sees the component visible; the hide happens on the
  following turn. This is a MUST-level consequence of the mechanism this
  component observes through — the same underlying mechanism the sibling
  conditional view recipe
  (`agentictoolkit://cookbook/ui/settings/layout/conditional-view`)
  documents for its own observed setting.
- Repeated taps on the dismiss button: each tap unconditionally sets the
  setting's value to `true` again, with no read-back of the setting's
  current value first (MUST, per `dismiss-persistence`); the guard
  against a redundant visibility write lives in the change handler
  (`visibility-write-guard`), not in the tap handler itself, so a repeated
  or already-dismissed tap harmlessly re-assigns the same value.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `text` | text | — (required) | The hint's message, rendered as the hint label's wrapping content. |
| `dismissedSetting` | boolean setting | — (required) | The persisted flag this component reads and writes; the component hides itself once the setting's value becomes `true`. |
| `buttonTitle` | text | `"Got It"` | The dismiss button's title. |

## Deep Linking

Not applicable: the component is an inline hint row inside a settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
applies.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — (no key; literal default parameter value) | "Got It" | `buttonTitle`'s default value when a caller constructs the component without supplying one |

`buttonTitle`'s default value, the English literal `"Got It"`, carries no
localization key or lookup — `text` and any explicit `buttonTitle`
argument are the caller's responsibility to localize (the same treatment
as the sibling Badge recipe (`agentictoolkit://cookbook/ui/controls/badge`)
gives fully caller-supplied text), but this one default value ships baked
directly into the component itself; a call site that never overrides
`buttonTitle` ships this English literal regardless of the app's locale.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the component performs no animation or transition; the visibility change is an instantaneous assignment. |
| Increase Contrast | Not applicable to this component directly: it reads no system contrast setting; the hint label's color is a theme-resolved semantic role and the dismiss button's coloring comes from the platform's own default control chrome, neither of which the component adjusts for contrast itself. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone — dismissal is structural and driven by a labeled button tap, not a color-only cue. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate applies; the
component renders unconditionally whenever constructed, subject only to
the dismissed-setting's value.

## Analytics

Not applicable: the component performs no analytics or telemetry of its
own. If impression or dismissal analytics are desired for a specific
onboarding hint, that instrumentation belongs to the caller assembling
the settings screen, not to this reusable component.

## Privacy

- **Data collected**: None of its own — the component holds only the
  caller-supplied text and button-title values and reads/writes the
  already-existing dismissed-setting's value.
- **Storage**: Not applicable directly — the component performs no
  read/write to disk or any other store directly; persistence of the
  dismissed flag is owned by the setting/observer mechanism it reads
  through, backed by whatever storage provider the app's settings system
  is configured with.
- **Transmission**: Not applicable — the component performs no networking
  of its own; whether the configured storage provider syncs the setting
  elsewhere is a property of the app's settings configuration, not of
  this component.
- **Retention**: Not applicable — the component retains only its hint
  label, its dismiss button, and its setting observer for its own
  lifetime; it persists nothing beyond that itself.

## Logging

Not applicable: the component performs no logging of its own.

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
  `ComposableSettings` namespace. `dismiss-button-style` is implemented by
  setting `dismissButton.bezelStyle = .rounded` and `dismissButton.controlSize
  = .small`. Beyond the cross-platform behavior in Behavioral Requirements,
  the AppKit implementation: exposes `textLabel` and `dismissButton` as public,
  read-only properties (`NSTextField`/`NSButton`) so a caller can inspect the
  exact instances the view displays; disables
  `translatesAutoresizingMaskIntoConstraints` on itself and on the internal
  stack; pins the stack's top/leading/trailing/bottom anchors to its own
  corresponding edges with no additional constant (`pinToEdges`); traps with
  a fatal error on both `init(coder:)` and the frame-only `init(frame:)`,
  since the only supported construction path is the designated
  `init(text:dismissedSetting:buttonTitle:)`; and implements thread
  confinement via a `@MainActor` declaration, restricting construction and
  mutation to the main actor, enforced at compile time by Swift's isolation
  checking. There is no UIKit code path in source; a UIKit port would
  replace `NSTextField`/`NSButton`/`NSStackView` with `UILabel`/`UIButton`/
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/DismissibleHintView.swift` |

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
  recipe (`agentictoolkit://cookbook/ui/settings/layout/conditional-view`) documents for its own
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
  Localization for the unlocalized-default consequence this creates for call
  sites that never override it.
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
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/layout/. |
</content>
