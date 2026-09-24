---
id: 3e548aa3-1103-4b3f-96ff-d2e7ff564810
title: FontChooserButton
domain: agentictoolkit://recipes/font-chooser-button
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS NSButton subclass that draws a chosen font's name in that font at
  a fixed sample size and opens the system font panel to pick a new one.
platforms:
- swift
- macos
tags:
- settings
- font
- picker
- macos
- appkit
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# FontChooserButton

## Overview

`FontChooserButton` (`ComposableSettings.FontChooserButton`) is a macOS
`NSButton` subclass from the ComposableSettingsWindow system integration
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/FontChooserButton.swift`)
that is itself the font sample: it draws a caller-supplied font's name in
that font, at one fixed legible size, and opens the system font panel
(`NSFontPanel`, via `NSFontManager`) when clicked. It conforms to
`NSFontChanging` to receive the font the user picks in that panel and
forwards it through its `onChange` callback. It records nothing durable of
its own — the caller (the row or view model that owns the setting) decides
what the picked font means, persists it if appropriate, and calls
`show(_:title:)` back with whatever it actually recorded, including a
clamped size or an edit a locked theme refused outright.

## Behavioral Requirements

- **initializes-with-system-placeholder**: On construction via
  `init(frame:)`, the component MUST call `show(nil, title: "System")`,
  which sets `selectedFont` to `nil`, `title` to `"System"`, and `font` to
  the system font at `sampleSize`.
- **configures-rounded-momentary-bezel**: On construction, the component
  MUST set `bezelStyle` to `.rounded` and its button type to
  `.momentaryPushIn`.
- **left-aligns-title**: On construction, the component MUST set
  `alignment` to `.left`.
- **truncates-title-at-tail**: On construction, the component MUST set its
  button cell's `lineBreakMode` to `.byTruncatingTail`.
- **yields-width-under-compression**: On construction, the component MUST
  set its horizontal content-compression-resistance priority to
  `.defaultLow`.
- **does-not-hug-its-horizontal-content**: On construction, the component
  MUST set its horizontal content-hugging priority to `.defaultLow`.
- **disables-autoresizing-mask-translation**: On construction, the
  component MUST set `translatesAutoresizingMaskIntoConstraints` to
  `false`.
- **applies-fixed-width-when-given**: WHEN constructed via `init(width:)`
  with a non-nil `width`, the component MUST activate a width constraint
  equal to `width`.
- **omits-width-constraint-when-none-given**: WHEN constructed via
  `init(width:)` with `width == nil`, or via the plain `init(frame:)`, the
  component MUST NOT add any width constraint of its own.
- **rejects-coder-initialization**: The component MUST fatal-error if
  constructed through `init?(coder:)`.
- **draws-sample-at-fixed-size**: WHEN `show(_:title:)` is called with a
  non-nil font, the component MUST set `font` to that font converted to
  `sampleSize` (12pt) via `NSFontManager.convert(_:toSize:)`, regardless of
  the font's own point size.
- **falls-back-to-system-font**: WHEN `show(_:title:)` is called with
  `font == nil`, the component MUST set `font` to
  `NSFont.systemFont(ofSize: sampleSize)`.
- **records-selected-font-at-its-own-size**: WHEN `show(_:title:)` is
  called, the component MUST set `selectedFont` to exactly the `font`
  argument passed in, at its own unconverted size — not the sample-size
  font drawn on the button.
- **displays-caller-supplied-title**: WHEN `show(_:title:)` is called, the
  component MUST set `title` to the given `title` argument verbatim.
- **does-not-persist-the-picked-font-itself**: The component MUST NOT write
  the font recorded in `selectedFont` to any store of its own (a default,
  a theme, a file); it exists only in memory for `FontChooserButton`'s own
  lifetime, and only until the next `show(_:title:)` call.
- **opens-font-panel-on-press**: WHEN the button is pressed, the component
  MUST invoke `openFontPanel(_:)` through the target/action wired at
  construction.
- **targets-itself-in-font-manager**: WHEN `openFontPanel(_:)` runs, the
  component MUST set `NSFontManager.shared.target` to itself.
- **seeds-panel-with-current-selection**: WHEN `openFontPanel(_:)` runs,
  the component MUST call `setSelectedFont` on the shared font manager with
  `selectedFont` if non-nil, or otherwise the system font at
  `NSFont.systemFontSize`, passing `isMultiple: false`.
- **orders-front-the-shared-font-panel**: WHEN `openFontPanel(_:)` runs,
  the component MUST call `orderFrontFontPanel(_:)` on the shared font
  manager.
- **limits-panel-to-font-selection-modes**: The component's
  `validModesForFontPanel(_:)` MUST return exactly
  `[.collection, .face, .size]`, excluding color and text-effect modes.
- **forwards-the-picked-font**: WHEN `changeFont(_:)` is called with a
  non-nil font manager, the component MUST invoke `onChange` (if set) with
  that font manager's conversion of the font the panel was opened on
  (`selectedFont`, or the system font at `NSFont.systemFontSize` if none
  was ever chosen).
- **ignores-a-nil-font-manager-in-callback**: WHEN `changeFont(_:)` is
  called with `sender == nil`, the component MUST NOT invoke `onChange` and
  MUST take no other action.
- **releases-font-manager-target-on-window-removal**: WHEN the component's
  `window` becomes `nil` AND `NSFontManager.shared.target` is still this
  instance, `viewDidMoveToWindow()` MUST set `NSFontManager.shared.target`
  to `nil`.
- **confines-to-main-actor**: The component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **exposes-selected-font-read-only**: The component MUST expose
  `selectedFont` as a public, externally-read-only property.
- **exposes-mutable-change-callback**: The component MUST expose `onChange`
  as a public, externally-settable property.

## Appearance

- **Corner radius**: Not set directly; the rounded corners come entirely
  from `bezelStyle = .rounded`'s stock AppKit chrome. No layer or custom
  drawing code appears in source.
- **Padding**: Not set; the component adds no internal padding of its own
  beyond the `.rounded` bezel's own default content insets.
- **Font**: Dynamic rather than fixed. `font` is always the font last
  passed to `show(_:title:)` (or `nil`) converted to `sampleSize` = 12pt
  (`NSFontManager.convert(_:toSize:)`), or `NSFont.systemFont(ofSize: 12)`
  when no font was chosen. Not theme-driven — no `ThemeTypography` or
  `ThemedLabel` reference appears in source.
- **Background**: Not set; the component draws no background of its own —
  the `.rounded` bezel's own AppKit chrome.
- **Foreground/Text**: Not set; no `contentTintColor` or `attributedTitle`
  customization appears in source, so the title renders in the `.rounded`
  bezel's stock default text color.
- **Border**: Not set; the border is the `.rounded` bezel's own default,
  unmodified by source.
- **Shadow**: Not set; no shadow customization appears anywhere in source.
- **Min/Max size**: No explicit width or height constraint is set by
  default. Horizontal compression-resistance and content-hugging are both
  `.defaultLow`, so the button gives up width first under compression and
  does not hug its content horizontally. `init(width:)` optionally
  activates one fixed-width constraint (see **applies-fixed-width-when-given**);
  no height constraint is ever added — height is intrinsic to the
  `.rounded` bezel at the drawn `font`'s line height.

## States

| State | Appearance change |
|-------|------------------|
| Default | Draws `title` in `font` (the current selection converted to `sampleSize`, or the system font if none is chosen). |
| Pressed | Not styled by `FontChooserButton` itself beyond `NSButton`'s native `.momentaryPushIn` bezel feedback; on release, `openFontPanel(_:)` runs and the system font panel opens (see **opens-font-panel-on-press**). |
| Disabled | Not implemented: source never reads or sets `isEnabled`. A caller may set it directly through the inherited `NSButton` property, at which point `NSButton`'s native disabled dimming applies. |
| Focused | Not styled by `FontChooserButton`; any focus ring is `NSButton`'s own native focus appearance. |
| Loading | Not applicable: the component performs no asynchronous work of its own and defines no loading state. |

## Accessibility

- **Role**: `button`, inherited from `NSButtonCell`; `FontChooserButton`
  sets no custom accessibility role.
- **Label**: The accessible name is `title`, set by the caller through
  `show(_:title:)`. The caller owns the wording because only it knows what
  the font means where it is stored — the source's own doc comment gives
  `"System"` for a role with no family of its own and
  `"Menlo — 14 pt (not installed)"` for a face the machine lacks, so the
  accessible name already carries availability information when the caller
  supplies it.
- **Announce state changes**: Not applicable — `FontChooserButton` defines
  no disabled or loading state of its own (see States); if a caller
  disables the button directly, the enabled/disabled announcement is
  `NSButton`'s native behavior, not something this component implements.
- **Keyboard navigation**: Inherited from `NSButton` — Tab/Shift-Tab move
  focus onto and off the button, and Space or Return activates it through
  the target/action wired in construction (`openFontPanel(_:)`). The
  resulting `NSFontPanel` is a separate, standard AppKit window; its own
  keyboard navigation is not implemented in this file.
- **Minimum tap target**: This is a macOS, pointer/trackpad-driven
  `NSButton`; source sets no `controlSize` override, so the click target is
  the regular-size rounded bezel sized to `title`, per the macOS Human
  Interface Guidelines for pointer-driven controls. Ports to touch
  platforms MUST give the equivalent control at least the platform
  minimum: 44 by 44 pt on iOS, 48 by 48 dp on Android, 40 by 40 effective
  pixels on WinUI 3.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| font-chooser-button-001 | initializes-with-system-placeholder | Construct `FontChooserButton()` with no further calls | `title == "System"`, `selectedFont == nil`, `font?.pointSize == FontChooserButton.sampleSize` |
| font-chooser-button-002 | configures-rounded-momentary-bezel | Construct `FontChooserButton()` | `bezelStyle == .rounded`; the button's cell reports `.momentaryPushIn` type |
| font-chooser-button-003 | left-aligns-title | Construct `FontChooserButton()` | `alignment == .left` |
| font-chooser-button-004 | truncates-title-at-tail | Construct `FontChooserButton()` | `(cell as? NSButtonCell)?.lineBreakMode == .byTruncatingTail` |
| font-chooser-button-005 | yields-width-under-compression | Construct `FontChooserButton()` | `contentCompressionResistancePriority(for: .horizontal) == .defaultLow` |
| font-chooser-button-006 | does-not-hug-its-horizontal-content | Construct `FontChooserButton()` | `contentHuggingPriority(for: .horizontal) == .defaultLow` |
| font-chooser-button-007 | disables-autoresizing-mask-translation | Construct `FontChooserButton()` | `translatesAutoresizingMaskIntoConstraints == false` |
| font-chooser-button-008 | applies-fixed-width-when-given | `FontChooserButton(width: 200)`, laid out | An active constraint pins width to exactly 200pt |
| font-chooser-button-009 | omits-width-constraint-when-none-given | `FontChooserButton(width: nil)` and `FontChooserButton()` | Neither instance has a width constraint added by the component itself |
| font-chooser-button-010 | rejects-coder-initialization | Attempt `FontChooserButton(coder: someCoder)` | The call traps via `fatalError`; no instance is returned |
| font-chooser-button-011 | draws-sample-at-fixed-size | `show(NSFont(name: "Menlo", size: 48), title: "Menlo — 48 pt")` | `font?.pointSize == FontChooserButton.sampleSize` and `font?.familyName == "Menlo"` |
| font-chooser-button-012 | falls-back-to-system-font | `show(nil, title: "System")` | `font?.pointSize == FontChooserButton.sampleSize` and `font` is the system font |
| font-chooser-button-013 | records-selected-font-at-its-own-size | `show(NSFont(name: "Menlo", size: 48), title: "Menlo — 48 pt")` | `selectedFont?.pointSize == 48` (unchanged by the sample-size drawing) |
| font-chooser-button-014 | displays-caller-supplied-title | `show(nil, title: "Custom Title")` | `title == "Custom Title"` |
| font-chooser-button-015 | does-not-persist-the-picked-font-itself | Call `show(font:title:)`, then inspect `UserDefaults`/any theme store the component has access to | No entry attributable to `FontChooserButton` is written anywhere |
| font-chooser-button-016 | opens-font-panel-on-press | Simulate a click on the button | `openFontPanel(_:)` runs (observable via its side effects in font-chooser-button-017 through -019) |
| font-chooser-button-017 | targets-itself-in-font-manager | Trigger `openFontPanel(_:)` | `NSFontManager.shared.target === button` |
| font-chooser-button-018 | seeds-panel-with-current-selection | `show(menlo48, title:)`, then trigger `openFontPanel(_:)` | `NSFontManager.shared.selectedFont` reflects `menlo48` at its own size (48pt), not the sample size |
| font-chooser-button-019 | orders-front-the-shared-font-panel | Trigger `openFontPanel(_:)` | `NSFontPanel.shared.isVisible == true` afterward |
| font-chooser-button-020 | limits-panel-to-font-selection-modes | Call `validModesForFontPanel(NSFontPanel.shared)` | Result contains `.face`, `.size`, `.collection` and none of `.shadowEffect`, `.underlineEffect`, `.strikethroughEffect`, `.textColorEffect` |
| font-chooser-button-021 | forwards-the-picked-font | Set `onChange` to a closure capturing its argument; call `changeFont(NSFontManager.shared)` after selecting a font in the manager | The closure is invoked with the newly converted font |
| font-chooser-button-022 | ignores-a-nil-font-manager-in-callback | Set `onChange` to a closure that flips a flag; call `changeFont(nil)` | The flag remains unflipped; no crash |
| font-chooser-button-023 | releases-font-manager-target-on-window-removal | Add the button to a window, set `NSFontManager.shared.target` to it, then `removeFromSuperview()` | `NSFontManager.shared.target == nil` afterward |
| font-chooser-button-024 | confines-to-main-actor | Attempt to construct or mutate a `FontChooserButton` from off the main actor | The compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| font-chooser-button-025 | exposes-selected-font-read-only | Construct the button, call `show(font:title:)`, then read `.selectedFont` from outside the type | The property is externally readable and reflects the last `show` call; it has no externally-accessible setter |
| font-chooser-button-026 | exposes-mutable-change-callback | Assign a closure to `.onChange` from outside the type | The assignment compiles and the closure is the one invoked in font-chooser-button-021 |

## Edge Cases

- **Null/empty input**: `show(_:title:)`'s `font` parameter is optional and
  `nil` is an explicit, handled case (falls back to the system font — see
  **falls-back-to-system-font**). `title` is a non-optional `String`; an
  empty string is drawn as an empty title with no crash — this is a MUST,
  traceable to `title`'s plain assignment with no validation.
- **Boundary values**: `init(width:)`'s `width` is an unconstrained
  `CGFloat` passed straight into
  `widthAnchor.constraint(equalToConstant: width)` with no clamping or
  validation. A zero or negative width is passed through unchanged and
  produces a zero-width or Auto-Layout-unsatisfiable constraint; this is a
  MUST — the component performs no bounds-checking of its own on `width`.
- **Concurrent access**: Not applicable — the class is `@MainActor`, so
  Swift's concurrency checker serializes all construction and mutation to
  the main actor; there is no code path by which two threads mutate the
  same instance simultaneously.
- **Error states**: Not applicable for `show`/panel wiring — every
  operation in this file is a synchronous, non-throwing call; no `try`,
  `Result`, or error-producing API appears in source. There is a related,
  documented memory-safety hazard rather than an error state:
  `NSFontManager.target` is declared `unowned(unsafe)` (per the test
  suite's own comment), so a `FontChooserButton` deallocated while still
  registered as the manager's target would leave the manager writing into
  freed memory. `viewDidMoveToWindow()`'s target-release (see
  **releases-font-manager-target-on-window-removal**) is the source's only
  guard against this, and it fires on window removal, not on `deinit`
  directly.
- **Offline/disconnected state**: Not applicable — the component performs
  no networking of its own.
- **Multiple instances sharing the font manager**: `NSFontManager.shared`
  has one `target` at a time. WHEN two `FontChooserButton` instances exist
  and both have opened the panel, the most recently opened one owns the
  target; the earlier one's later `removeFromSuperview()` is guarded by
  `NSFontManager.shared.target === self` (see
  **releases-font-manager-target-on-window-removal**) and so correctly
  does nothing, leaving the panel's current target untouched. This is a
  MUST, directly traceable to the `===` identity check in source.
- **Panel opened before any font is ever chosen**: `openFontPanel(_:)`'s
  `panelFont` falls back to `NSFont.systemFont(ofSize: NSFont.systemFontSize)`
  when `selectedFont` is `nil`, so opening the panel on a
  freshly-constructed, never-`show`-called button does not crash and seeds
  the panel with the system font at the system's default point size
  (which is not `sampleSize`). This is a MUST, traceable to `panelFont`'s
  nil-coalescing implementation.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `width` | `CGFloat?` | `nil` (plain `init(frame:)`) | Fixes the button to this width via one Auto Layout constraint, for a button that must line up with others in a grid column. Omitted (or `nil`), the button takes the width its title wants and gives it up first when its row is squeezed (see **yields-width-under-compression**). |
| `font` (via `show(_:title:)`) | `NSFont?` | `nil` (drawn at construction) | The face to draw the title in and what the font panel opens on; `nil` draws the title in the system font. |
| `title` (via `show(_:title:)`) | `String` | `"System"` (drawn at construction) | What the button reads; the caller owns the wording (see **Label**, above). |
| `onChange` | `((NSFont) -> Void)?` | `nil` | Invoked with the font the user picked in the font panel. |

## Deep Linking

Not applicable: `FontChooserButton` is a settings-row control with no
navigable identity of its own — it has no route, screen, or resource that a
deep link could target.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded literal) | `System` | The button's initial title, set unconditionally by `init(frame:)` calling `show(nil, title: "System")`, before any caller-supplied title is applied. |

`"System"` is an AppKit `title` assignment from a string literal — an
unlocalized literal, not a `LocalizedStringKey` — and no localization key
or `String(localized:)`/string-catalog mechanism wraps it anywhere in this
file. Every other title the button ever shows is caller-supplied through
`show(_:title:)`, so localizing that text is the caller's responsibility,
not this component's; only the one built-in `"System"` default is this
component's own literal. NEEDS REVIEW: the built-in `"System"` default is
unlocalized; whether it should move to a `String(localized:)` key (so a
caller that never calls `show(_:title:)` still gets localized text) is
an open question.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source performs no animation, transition, or `NSAnimationContext` call anywhere — every state change (`font`, `title`, `selectedFont`) is an instantaneous property assignment. |
| Increase Contrast | Not applicable: `FontChooserButton.swift` sets no custom `NSColor` anywhere; all coloring is the `.rounded` bezel's default AppKit chrome, which already tracks the system's Increase Contrast setting. |
| Differentiate Without Color | Not applicable: the component conveys no state through color; its one visual presentation is the title drawn in the current font, and font choice itself is not a color-coded status signal. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `FontChooserButton.swift`; the button always constructs and wires itself
unconditionally.

## Analytics

Not applicable: `FontChooserButton.swift` contains no analytics or
telemetry call. Any tracking of a font change is the caller's
responsibility inside its `onChange` closure.

## Privacy

- **Data collected**: None of its own. The component holds only the
  `NSFont?` last handed to it via `show(_:title:)` and an optional
  `onChange` closure reference supplied by the caller.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store (see
  **does-not-persist-the-picked-font-itself**); persistence, if any, is
  entirely the caller's responsibility.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: The component retains `selectedFont` and `onChange` only
  for its own in-memory lifetime, and only until the next `show(_:title:)`
  call replaces `selectedFont`.

## Logging

Not applicable: `FontChooserButton.swift` contains no logging call (no
`print`, `os_log`, or logger reference anywhere in source).

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
  the target-release workaround in **releases-font-manager-target-on-window-removal**
  has no UIKit equivalent to port, since a presented view controller is
  dismissed rather than leaked at a shared singleton.
- **WinUI 3** (the reason this recipe exists): WinUI 3 ships no
  system-wide font panel window analogous to `NSFontPanel`. Build a
  `Button` whose `Content` is a `TextBlock` bound to the current font's
  display name, with the `TextBlock`'s `FontFamily` bound to the selected
  font and its `FontSize` fixed to a sample size constant (mirroring
  `sampleSize`, e.g. `12`), regardless of the font's own configured size —
  mirroring **draws-sample-at-fixed-size**. Wire `Click` to open a custom
  `ContentDialog` or `Flyout` hosting a `ListView`/`ComboBox` enumerating
  installed font families (via `Microsoft.UI.Xaml.Media.FontFamily` /
  `DWriteCore` font enumeration) and a `NumberBox`/`Slider` for point size,
  since there is no system dialog to defer to. Track "who currently owns
  the open font-choosing UI" explicitly in the dialog/flyout's own
  lifecycle (its `Closed` event), since WinUI has no shared, app-wide
  singleton target to release the way `viewDidMoveToWindow` releases
  `NSFontManager.shared.target` — mirroring
  **releases-font-manager-target-on-window-removal**'s intent without its
  mechanism. On the dialog's confirm/selection-changed event, invoke a
  caller-supplied callback (mirroring `onChange`) with the chosen
  `FontFamily` and size, and let the caller call an equivalent of
  `show(fontFamily:title:)` back on the button afterward to update its own
  displayed sample and title — mirroring the source's "stores nothing
  itself" design. `Button`'s default `VisualStateManager` groups
  (`Normal`, `PointerOver`, `Pressed`, `Disabled`) already cover
  pressed/disabled visuals without custom state XAML, matching the
  source's own lack of custom pressed/disabled styling.

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

**Decision**: This recipe gives `FontChooserButton` more behavioral
requirements (26) than the structurally simpler settings-row siblings in
this directory, such as `ColorPickerView` (7) or `ButtonView` (18).
**Rationale**: `FontChooserButton` owns genuinely more distinct behavior
than a title-plus-control row composition: two initializer paths with
different constraint outcomes, a draw-size/store-size split
(**draws-sample-at-fixed-size** vs. **records-selected-font-at-its-own-size**),
and a full `NSFontChanging` panel lifecycle (target acquisition, seeding,
mode restriction, callback forwarding, and target release) — matching a
lower sibling's requirement count would omit behavior the source actually
has.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [meaningful-labels](agenticdevelopercookbook://compliance/accessibility#meaningful-labels) | passed | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | internationalization |

The `native-controls-preference` and `platform-design-language` checks pass
because the component defers to macOS's own `NSFontPanel` rather than
building a second font browser (per the source's own doc comment,
`native-controls`). `keyboard-navigable` and `meaningful-labels` pass on
`NSButton`'s inherited Tab/Space/Return handling and the caller-supplied,
availability-aware `title` (see **Label** under Accessibility).
`idempotent-operations` passes because repeated `show(_:title:)` calls with
the same arguments always leave the button in the same observable state.
`separation-of-concerns` passes because the component stores no font of
its own beyond the in-memory `selectedFont` (see
**does-not-persist-the-picked-font-itself**). `string-externalization`
fails because the built-in `"System"` initial title is a hardcoded literal
with no localization key (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for FontChooserButton, covering the two-initializer setup, the draw-size/store-size split, the NSFontChanging panel lifecycle, and the unlocalized "System" default title. |
