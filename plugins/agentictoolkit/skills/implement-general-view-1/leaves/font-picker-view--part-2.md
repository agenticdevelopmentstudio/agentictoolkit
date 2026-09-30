<!-- leaf: implement-general-view-1/font-picker-view--part-2 · source: font-picker-view.md -->

# FontPickerView — continued (part 2)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `FontViewModel` | - (required) | Supplies the row's title and current font; receives committed font-panel picks via `viewModel.setFont(_:)`. The initializer also overwrites this view model's `onChange` closure with the component's own sync handler (see Edge Cases). |
| `isEnabled` | `Bool` | `true` | Dims and disables the row's `button` and `label` when set to `false` (see **dims-and-disables-the-row**). |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none - hardcoded literal fragments) | `" — %@ pt"` / `" (not installed)"` | Built by the private `describe(_:installed:)` helper and passed as `button`'s title on every `sync()` call. |

`label`'s text comes from `viewModel.title`, a value the caller provides, so
there is nothing for this component to localize there. The `" — "`, `" pt"`,
and `" (not installed)"` fragments inside `describe(_:installed:)`,
however, are hardcoded English string-interpolation literals assigned to
`button`'s AppKit `title` (a plain `String`, not a `LocalizedStringKey`) -
not wrapped in `String(localized:)` or any string-catalog key anywhere in
`FontPickerView.swift`.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, or `NSAnimationContext` call anywhere in `FontPickerView.swift`; the `isEnabled` dimming (`button.isEnabled` / `label.alphaValue`) is an instantaneous property assignment, not an animated transition. |
| Increase Contrast | Not applicable to this file directly: `FontPickerView.swift` reads no system contrast setting and sets no custom `NSColor`; `label`'s coloring comes from the active theme's `primaryText` role (tracks Increase Contrast automatically) and `button`'s title color is AppKit's own default control rendering. Whether the `0.4`-alpha disabled dimming remains sufficiently contrasted is tracked once under Accessibility above (the open question on minimum-contrast-ratio), not duplicated here. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone; `isEnabled` is communicated through both `button.isEnabled` (which changes the button's interactive/bezel appearance, not merely a color) and `label.alphaValue`, and the font name/installed-status is communicated through text (`describe(_:installed:)`), not color. |

## Privacy

- **Data collected**: Not applicable - the component collects no data of
  its own; it only displays a font supplied by `viewModel` and reports
  font-panel picks back through `viewModel.setFont(_:)`.
- **Storage**: Not applicable - source performs no read/write to disk,
  `UserDefaults`, or any other store; persistence, if any, is owned by
  `FontViewModel`/`UserSettingObserver`/`UserSetting`, which are not part of
  this file.
- **Transmission**: Not applicable - no networking call appears anywhere in
  source.
- **Retention**: The view retains only its own subviews and its reference
  to `viewModel` for its own lifetime; it persists nothing beyond that.

## Platform Notes

- **SwiftUI**: Compose an `HStack` with `Text(viewModel.title)` and a
  trailing font-sample button (an `NSViewRepresentable` wrapping
  `FontChooserButton`, per `agentictoolkit://recipes/font-chooser-button`'s
  own SwiftUI note, or an equivalent custom `Button` that opens a font
  picker) bound to a `Binding` that reads and writes through the same
  view-model font, mirroring **commits-picked-font-through-view-model** and
  **observes-external-view-model-changes**; drive both the label's opacity
  and the button's `disabled(_:)` from one `isEnabled` boolean, mirroring
  **dims-and-disables-the-row**.
- **Compose**: Use a `Row` with a leading `Text(title)` and a trailing
  sample `Button` whose label is drawn in the currently selected
  `FontFamily` at a fixed sample size, opening a custom
  `AlertDialog`/`ModalBottomSheet` listing available font families and
  sizes on click (there is no Android system font panel to defer to, per
  `agentictoolkit://recipes/font-chooser-button`'s Compose note); commit the
  picked family/size back to the view model unconditionally on selection,
  and gate both children's `enabled`/alpha from one boolean, mirroring
  **dims-and-disables-the-row**.
- **React/Web**: A flex row (`display: flex; align-items: center`)
  containing a `<span>` for the title and a trailing `<button>` styled with
  `style.fontFamily` set to the current selection at a fixed sample
  `font-size`, opening a custom popover/dialog listing available fonts (the
  CSS Font Loading API's `document.fonts`, or a fixed app-defined list) on
  click; forward the picked family/size through a callback prop mirroring
  **commits-picked-font-through-view-model**, and toggle a `disabled`
  attribute plus a reduced-opacity class on both children together,
  mirroring **dims-and-disables-the-row**.
- **AppKit / UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/FontPickerView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, inside the
  `ComposableSettings` namespace, conforming to `SettingsViewProtocol`. It
  composes two subviews - a `ThemedLabel` from
  `ComposableSettings.makeRowLabel` and a `FontChooserButton` - into one row
  via `ComposableSettings.makeRow` and `pinToEdges`. `button`'s title text is
  computed by a private static `describe(_:installed:)` helper, which formats
  `"<name> — <size> pt"` and appends `" (not installed)"` when the font is
  not installed - see **describes-font-name-and-rounded-point-size** and
  **flags-an-uninstalled-font-in-its-title**. There is no UIKit code
  path in source; a UIKit port has no `NSFontPanel` equivalent to defer to
  (see `agentictoolkit://recipes/font-chooser-button`'s own AppKit/UIKit
  note for the button's side of that gap) and would need its own
  `isEnabled`-driven dimming, since UIKit has no direct `alphaValue`
  analogue on `UILabel` beyond its inherited `UIView.alpha`.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `Auto,*`: a `TextBlock` bound to `viewModel.title`
  in column 0, and in column 1 the font-sample `Button` described in
  `agentictoolkit://recipes/font-chooser-button`'s own WinUI 3 note (its
  `Content` `TextBlock` bound to the selected font's family/size at a fixed
  sample `FontSize`, opening a `ContentDialog`/`Flyout` for selection since
  WinUI ships no system font panel). Wire that dialog's confirm/selection
  event to call an equivalent of `viewModel.setFont` unconditionally on
  every pick, then re-read the view model's current font/title back into
  both the `TextBlock` and the sample `Button` - mirroring
  **commits-picked-font-through-view-model** and
  **resyncs-synchronously-after-a-pick** in one step, since WinUI has no
  separate `UserSettingObserver` Combine hop to produce a second,
  asynchronous re-sync the way this source's `sizeObserver`/`nameObserver`
  do (see Edge Cases, "Repeated sync after a single font pick" - a WinUI
  port that binds both the `TextBlock` and the sample `Button`'s content to
  the same `INotifyPropertyChanged` font property gets the same
  eventually-consistent redraw without needing to replicate the double
  callback). Drive both children's `Opacity`/`IsEnabled` from one bound
  boolean to mirror **dims-and-disables-the-row**'s all-or-nothing row
  dimming, and append a not-installed qualifier to the `TextBlock`'s bound
  display string (via an `IValueConverter`) mirroring
  **flags-an-uninstalled-font-in-its-title**.

## Design Decisions

**Decision**: `viewModel.onChange` is overwritten unconditionally in `init`,
replacing any handler already registered on that `FontViewModel` instance.
**Rationale**: Mirrors the same closure-property-assignment pattern
documented at `agentictoolkit://recipes/color-picker-view#requirements/owns-on-change`;
the view provides no way to compose with an existing observer.
**Approved**: pending

**Decision**: A single font pick can trigger `sync()` up to three times (one
synchronous call from `button.onChange`, and up to two further asynchronous
calls from `FontViewModel`'s `nameObserver`/`sizeObserver`, each hopping to
the next main-queue turn) with no debouncing or deduplication.
**Rationale**: `sync()` always re-reads current state from `viewModel` rather
than accumulating deltas, so the repeated calls are redundant but
observably idempotent; the source accepts that redundancy rather than
adding a guard, consistent with `UserSettingObserver`'s own documented
choice to hop to the main queue for every mouse-drag-safe update rather than
coalescing them.
**Approved**: pending

**Decision**: The disabled-state dimming uses a hardcoded `0.4` alpha on
`label`, local to this file, rather than a shared "disabled alpha" token
used elsewhere in the row family.
**Rationale**: No other file under `ComposableSettingsWindow/Views` sets this
exact value or references a shared constant for it; this recipe documents
the value as-is rather than inventing a token the source does not use (see
the open question on minimum-contrast-ratio under Accessibility).
**Approved**: pending
