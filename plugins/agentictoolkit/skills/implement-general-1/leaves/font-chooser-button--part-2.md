<!-- leaf: implement-general-1/font-chooser-button--part-2 · source: font-chooser-button.md -->

# FontChooserButton — continued (part 2)

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source performs no animation, transition, or `NSAnimationContext` call anywhere — every state change (`font`, `title`, `selectedFont`) is an instantaneous property assignment. |
| Increase Contrast | Not applicable: `FontChooserButton.swift` sets no custom `NSColor` anywhere; all coloring is the `.rounded` bezel's default AppKit chrome, which already tracks the system's Increase Contrast setting. |
| Differentiate Without Color | Not applicable: the component conveys no state through color; its one visual presentation is the title drawn in the current font, and font choice itself is not a color-coded status signal. |

## Privacy

- **Data collected**: None of its own. The component holds only the
  `NSFont?` last handed to it via `show(_:title:)` and an optional
  `onChange` closure reference supplied by the caller.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store (see #requirements/font-persistence);
  persistence, if any, is entirely the caller's responsibility.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: The component retains `selectedFont` and `onChange` only
  for its own in-memory lifetime, and only until the next `show(_:title:)`
  call replaces `selectedFont`.

## Platform Notes

- **SwiftUI**: There is no first-party SwiftUI API on macOS for presenting
  the system font panel. Wrap the same `NSFontManager`/`NSFontPanel`
  machinery behind an `NSViewRepresentable` (or an `NSViewController`-based
  representable) whose `Coordinator` conforms to `NSFontChanging`, mirroring
  `changeFont(_:)` and `validModesForFontPanel(_:)` exactly as this source
  does; expose the drawn font/title through `@Binding`s and forward panel
  picks through the coordinator the same way `onChange` does here.
- **Compose**: Android provides no system font panel or font-family
  picker; build a `Button` whose label is drawn with the currently selected
  `FontFamily` at a fixed sample size (mirroring `sampleSize`), and open a
  custom `AlertDialog`/`ModalBottomSheet` listing the app's own bundled
  font families and sizes on click (mirroring `openFontPanel`'s role),
  forwarding the picked family/size back through a callback (mirroring
  `onChange`) with no attempt at persistence of its own.
- **React/Web**: The web has no built-in font panel either. Compose a
  `<button>` whose `style.fontFamily` reflects the current selection at a
  fixed sample `font-size`, opening a custom popover/dialog listing
  available fonts (the CSS Font Loading API's `document.fonts`, or a
  fixed app-defined list) on click; forward the picked family/size through
  a callback prop, mirroring `onChange`, with the parent responsible for
  any persistence.
- **AppKit / UIKit (source)**: Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/FontChooserButton.swift`.
  A macOS-only (`import AppKit`) `NSButton` subclass, `@MainActor`, nested
  inside the `ComposableSettings` namespace, conforming to
  `NSFontChanging`. There is no UIKit code path in source. A UIKit port
  would present `UIFontPickerViewController` (a full-screen modal list, not
  a floating always-on-top panel like `NSFontPanel`) and receive the pick
  through `UIFontPickerViewControllerDelegate`, rather than through the
  target-managed `NSFontManager`/`NSFontChanging` pairing this file uses;
  the target-release workaround in #requirements/font-manager-target-release
  has no UIKit equivalent to port, since a presented view controller is
  dismissed rather than leaked at a shared singleton.
- **WinUI 3**: WinUI 3 ships no system-wide font panel window analogous to
  `NSFontPanel`. Build a `Button` whose `Content` is a `TextBlock` bound to
  the current font's display name, with the `TextBlock`'s `FontFamily`
  bound to the selected font and its `FontSize` fixed to a sample size
  constant (mirroring `sampleSize`, e.g. `12`), regardless of the font's
  own configured size — mirroring #requirements/sample-size. Wire `Click`
  to open a custom `ContentDialog` or `Flyout` hosting a
  `ListView`/`ComboBox` enumerating installed font families (via
  `Microsoft.UI.Xaml.Media.FontFamily` / `DWriteCore` font enumeration) and
  a `NumberBox`/`Slider` for point size, since there is no system dialog to
  defer to. Track "who currently owns the open font-choosing UI" explicitly
  in the dialog/flyout's own lifecycle (its `Closed` event), since WinUI
  has no shared, app-wide singleton target to release the way
  `viewDidMoveToWindow` releases `NSFontManager.shared.target` — mirroring
  #requirements/font-manager-target-release's intent without its mechanism.
  On the dialog's confirm/selection-changed event, invoke a caller-supplied
  callback (mirroring `onChange`) with the chosen `FontFamily` and size,
  and let the caller call an equivalent of `show(fontFamily:title:)` back
  on the button afterward to update its own displayed sample and title —
  mirroring the source's "stores nothing itself" design. `Button`'s default
  `VisualStateManager` groups (`Normal`, `PointerOver`, `Pressed`,
  `Disabled`) already cover pressed/disabled visuals without custom state
  XAML, matching the source's own lack of custom pressed/disabled styling.

## Design Decisions

**Decision**: `init(frame:)` is a fully working initializer (it calls
`show(nil, title: "System")` and configures the button), rather than the
`fatalError` trap that sibling row views in this directory carry on their
frame-only initializer.
**Rationale**: Per the source's own doc comment, `FontChooserButton()` is a
spelling Swift resolves to `NSObject.init()`, which AppKit funnels through
`initWithFrame:` — trapping there would crash a call site that looks like
it is using the initializer above (`init(width:)`), rather than a
deliberately-avoided one.
**Approved**: pending

**Decision**: The component records the last font it was shown
(`selectedFont`) but never writes it anywhere persistent; the caller is
solely responsible for storage.
**Rationale**: Per the source's own doc comment: the caller "records the
picked font wherever that font belongs and calls `show(_:title:)` back
with what it actually recorded" — `explicit-over-implicit`: the button
always displays exactly what its owner tells it to, including a clamped
size or an edit a locked theme refused outright.
**Approved**: pending

**Decision**: `validModesForFontPanel(_:)` restricts the font panel to
`.collection`, `.face`, and `.size`, excluding color and text-effect modes.
**Rationale**: Per the source's own comment: "Only the parts of the panel
that pick a font — the color and underline effects would write nothing
anyone reads back."
**Approved**: pending

**Decision**: `viewDidMoveToWindow()` clears `NSFontManager.shared.target`
when the button leaves its window and still owns that target.
**Rationale**: `NSFontManager.target` is `unowned(unsafe)` (confirmed by
the component's own test suite comment); leaving it pointing at a
since-freed button would have the shared font manager write into freed
memory rather than fail safely. This is a workaround for that unsafe
AppKit API, not a feature of the component's own design.
**Approved**: pending

**Decision**: The component accepts the residual risk that
`NSFontManager.shared.target` can be left pointing at freed memory if a
`FontChooserButton` is deallocated together with its entire window (rather
than first removed from it): `viewDidMoveToWindow()` (see
#requirements/font-manager-target-release) is the only target-release
guard in source, and it runs only when the view is individually removed
from its window, not on `deinit`.
**Rationale**: `NSFontManager.target` is declared `unowned(unsafe)`, so
nothing in AppKit enforces a cleanup call at deallocation time, and source
adds no `deinit` override of its own. Recording the gap here keeps the
recipe honest about the edge `viewDidMoveToWindow()` does not cover,
rather than implying it is a complete guarantee.
**Approved**: pending

**Decision**: The built-in `"System"` initial title stays a hardcoded
literal rather than moving to a `String(localized:)` key.
**Rationale**: Every title the button shows after construction is
caller-supplied and therefore the caller's own localization
responsibility; only the one built-in `"System"` literal set by
`init(frame:)` is this component's own, and it is the only string in this
file left unlocalized (see Localization).
**Approved**: pending
