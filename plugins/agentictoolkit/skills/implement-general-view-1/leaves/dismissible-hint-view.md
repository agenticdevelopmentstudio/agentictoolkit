<!-- leaf: implement-general-view-1/dismissible-hint-view · source: dismissible-hint-view.md -->

**Rules** (cite as `implement-general-view-1/dismissible-hint-view#<slug>`):

- `self-hiding-conformance` MUST
- `text-label` MUST
- `text-label-theming` MUST
- `dismiss-button-title` MUST
- `dismiss-button-title-default` MUST
- `dismiss-button-style` MUST
- `dismiss-button-action` MUST
- `stack-arrangement` MUST
- `stack-spacing` MUST
- `dismissed-setting-observation` MUST
- `initial-visibility` MUST
- `visibility-update` MUST
- `visibility-write-guard` MUST
- `visibility-change-notification` MUST
- `visibility-change-callback` MUST
- `dismiss-persistence` MUST
- `main-actor-confinement` MUST
- `minimum-tap-target` MUST — dismissButton is explicitly sized .small with a .rounded bezel — smaller than AppKit's default "regular" push button …

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `text` | `String` | — (required) | The hint's message, rendered as `textLabel`'s wrapping label content. |
| `dismissedSetting` | `UserSetting<Bool>` | — (required) | The persisted flag this view reads and writes; the view hides itself once the setting's value becomes `true`. |
| `buttonTitle` | `String` | `"Got It"` | The dismiss button's title. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — (no key; literal default parameter value) | "Got It" | `buttonTitle`'s default value when a caller constructs `DismissibleHintView` without supplying one |

`buttonTitle`'s default value, the English literal `"Got It"`, carries no
localization key or lookup in source — `text` and any explicit `buttonTitle`
argument are the caller's responsibility to localize (the same treatment as
the sibling `Badge` recipe (`agentictoolkit://recipes/badge`) gives fully
caller-supplied text), but this one default value ships baked directly into
`DismissibleHintView.swift` itself; a call site that never overrides
`buttonTitle` ships this English literal regardless of the app's locale.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source performs no animation, transition, or `NSAnimationContext` call; the `isHidden` change is an instantaneous assignment. |
| Increase Contrast | Not applicable to this component directly: `DismissibleHintView.swift` reads no system contrast setting; `textLabel`'s color is a theme-resolved semantic role (`palette.secondaryTextColor`) and `dismissButton`'s coloring is `NSButton`'s own system chrome, neither of which this file adjusts for contrast itself. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone — dismissal is structural (`isHidden`) and driven by a labeled button tap, not a color-only cue. |

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

