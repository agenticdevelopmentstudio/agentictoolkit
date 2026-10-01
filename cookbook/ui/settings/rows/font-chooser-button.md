---
id: 3e548aa3-1103-4b3f-96ff-d2e7ff564810
title: Font Chooser Button
domain: agentictoolkit://cookbook/ui/settings/rows/font-chooser-button
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A button that draws a chosen font's name in that font at a fixed sample
  size and opens the platform's font-selection UI to pick a new one.
platforms:
- swift
- macos
tags:
- settings
- font
- picker
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/rows/color-picker-view
- agentictoolkit://cookbook/ui/settings/rows/button-view
references: []
approved-by: ''
approved-date: ''
---

# Font Chooser Button

## Overview

The font chooser button is itself the font sample: it draws a
caller-supplied font's name in that font, at one fixed legible size, and
opens the platform's font-selection UI when clicked. It receives the font
the user picks there and forwards it through a change callback. It
records nothing durable of its own — the caller (the row or view model
that owns the setting) decides what the picked font means, persists it if
appropriate, and hands the button back whatever it actually recorded,
including a clamped size or an edit a locked theme refused outright.

## Behavioral Requirements

- **system-placeholder**: On construction, the component MUST initialize
  itself with no font selected: `title` set to `"System"`, `selectedFont`
  set to `nil`, and `font` set to the system font at the sample size.
- **rounded-momentary-style**: On construction, the component MUST render
  with rounded corners and behave as a momentary push control — depressing
  while pressed and returning to normal on release, taking no other action
  itself.
- **title-alignment**: On construction, the component MUST left-align its
  title text.
- **tail-truncation**: On construction, the component MUST truncate
  overflowing title text at the tail (end), with the omission shown there.
- **yields-width-under-compression**: On construction, the component MUST
  be configured to readily give up width when horizontal space is
  constrained, rather than resisting the squeeze.
- **expands-to-fill-remaining-width**: On construction, the component MUST
  be configured to expand into available horizontal space rather than
  hugging its title's intrinsic width tightly.
- **fixed-width-constraint**: WHEN constructed with an explicit, non-nil
  fixed width, the component MUST activate a width constraint equal to
  that width.
- **no-width-constraint**: WHEN constructed with an explicit `nil` width,
  or via the plain default constructor, the component MUST NOT add any
  width constraint of its own.
- **coder-init**: The component MUST reject construction via a
  serialization/decoding-based construction path.
- **sample-size**: WHEN the component is given a non-nil font, it MUST
  render the title using that font converted to the sample size (12pt),
  regardless of the font's own point size.
- **system-font-fallback**: WHEN the component is given a `nil` font, it
  MUST render the title in the system font at the sample size.
- **selected-font-size**: WHEN the component is given a font, it MUST
  record that exact font, at its own unconverted size, as the selected
  font — not the sample-size font drawn on the button.
- **caller-supplied-title**: WHEN the component is given a title, it MUST
  display exactly that title verbatim.
- **font-persistence**: The component MUST NOT write the recorded selected
  font to any store of its own (a default, a theme, a file); it exists
  only in memory for the component's own lifetime, and only until the next
  time it is given a new font and title.
- **opens-font-picker**: WHEN the button is activated, the component MUST
  open the platform's font-selection UI, seeded with the currently
  selected font if one exists (otherwise the system font at the platform's
  default size), and bring that UI to the front.
- **panel-modes**: The component MUST restrict the font-selection UI it
  opens to font family, face, and size choices only, excluding color and
  text-effect options where the platform's font-selection UI offers them.
- **font-change-forwarding**: WHEN the platform reports a font-selection
  change, the component MUST invoke its change callback (if set) with the
  selected font as it stands at that moment (or the system font at the
  platform's default size if no font is selected yet) — not necessarily
  the font the picker was originally opened on, since giving the component
  a new font and title while the picker is still open replaces the
  selected font before the change is reported.
- **nil-sender**: WHEN the platform reports a font-selection change with
  no accompanying context, the component MUST NOT invoke its change
  callback and MUST take no other action.
- **releases-picker-registration-on-removal**: WHEN the component is
  removed from its window and it is still the active recipient of
  font-picker selections, it MUST release that registration.
- **confines-to-ui-thread**: The component MUST be usable only on the UI
  thread.
- **selected-font-access**: The component MUST expose the selected font as
  a public, externally-read-only property.
- **change-callback-access**: The component MUST expose the change
  callback as a public, externally-settable property.

## Appearance

- **Corner radius**: Not set directly; the rounded corners come entirely
  from the component's stock rounded-button chrome (see
  **rounded-momentary-style**). No custom drawing code appears in source.
- **Padding**: Not set; the component adds no internal padding of its own
  beyond its stock control's default content insets.
- **Font**: Dynamic rather than fixed. `font` is always the font last given
  to the component (or `nil`) converted to the sample size (12pt), or the
  system font at 12pt when no font was chosen. Not theme-driven.
- **Background**: Not set; the component draws no background of its own —
  its stock rounded-button chrome.
- **Foreground/Text**: Not set; no tint or attributed-title customization
  appears in source, so the title renders in the control's stock default
  text color.
- **Border**: Not set; the border is the control's own default, unmodified
  by source.
- **Shadow**: Not set; no shadow customization appears anywhere in source.
- **Min/Max size**: No explicit width or height constraint is set by
  default (see **yields-width-under-compression** and
  **expands-to-fill-remaining-width**), so the button gives up width first
  under compression and does not hug its content horizontally. An explicit
  fixed width optionally activates one width constraint (see
  **fixed-width-constraint**); no height constraint is ever added — height
  is intrinsic to the control at the drawn font's line height.

## States

| State | Appearance change |
|-------|------------------|
| Default | Draws the title in the current font (the current selection converted to the sample size, or the system font if none is chosen). |
| Pressed | Not styled by the component itself beyond its stock momentary-push feedback (see **rounded-momentary-style**); on release, the platform's font-selection UI opens (see **opens-font-picker**). |
| Disabled | Not implemented: source never reads or sets an enabled flag. A caller may set one directly through the inherited control property, at which point the platform's native disabled dimming applies. |
| Focused | Not styled by the component; any focus ring is the control's own native focus appearance. |
| Loading | Not applicable: the component performs no asynchronous work of its own and defines no loading state. |

## Accessibility

- **Role**: Button, inherited from the underlying control; the component
  sets no custom accessibility role.
- **Label**: The accessible name is the title, set by the caller. The
  caller owns the wording because only it knows what the font means where
  it is stored — the source's own doc comment gives `"System"` for a role
  with no family of its own and `"Menlo — 14 pt (not installed)"` for a
  face the machine lacks, so the accessible name already carries
  availability information when the caller supplies it.
- **Announce state changes**: Not applicable — the component defines no
  disabled or loading state of its own (see States); if a caller disables
  the button directly, the enabled/disabled announcement is the platform
  control's native behavior, not something this component implements.
- **Keyboard navigation**: Inherited from the underlying control — the
  primary activation key activates the button through the wiring set up
  at construction; the component sets no secondary key equivalent, so a
  confirm/return key does not activate it. Tab/Shift-Tab-style focus
  movement onto and off the button follows the platform's own keyboard-
  navigation defaults. The resulting font-selection UI is a separate,
  standard platform surface; its own keyboard navigation is not
  implemented in this file.
- **Minimum tap target**: This is a pointer/trackpad-driven control on its
  source platform; source sets no size override, so the click target is
  the regular-size control sized to its title, per that platform's design
  guidance for pointer-driven controls. Ports to touch platforms MUST give
  the equivalent control at least the platform minimum: 44 by 44 pt on
  iOS, 48 by 48 dp on Android, 40 by 40 effective pixels on WinUI 3.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| font-chooser-button-001 | system-placeholder | Construct the button with no further calls | Title is `"System"`, no font is selected, and the drawn font's point size equals the sample size |
| font-chooser-button-002 | rounded-momentary-style | Construct the button | The button renders with rounded corners and reports a momentary-push control type |
| font-chooser-button-003 | title-alignment | Construct the button | Title text is left-aligned |
| font-chooser-button-004 | tail-truncation | Construct the button | Overflowing title text is truncated at the tail |
| font-chooser-button-005 | yields-width-under-compression | Construct the button | Horizontal compression priority is configured to give up width readily |
| font-chooser-button-006 | expands-to-fill-remaining-width | Construct the button | Horizontal hugging priority is configured to expand into available width |
| font-chooser-button-007 | fixed-width-constraint | Construct the button with an explicit width of 200, laid out | An active constraint pins width to exactly 200pt |
| font-chooser-button-008 | no-width-constraint | Construct the button with an explicit `nil` width, and separately with the plain default constructor | Neither instance has a width constraint added by the component itself |
| font-chooser-button-009 | coder-init | Attempt construction via a serialization/decoding-based construction path | The call traps with a fatal error; no instance is returned (a platform-level runtime trap, not an ordinary in-process assertion) |
| font-chooser-button-010 | sample-size | Give the button a Menlo font at 48pt, titled "Menlo — 48 pt" | The drawn font's point size equals the sample size and its family is Menlo |
| font-chooser-button-011 | system-font-fallback | Give the button a `nil` font, titled "System" | The drawn font's point size equals the sample size and it is the system font |
| font-chooser-button-012 | selected-font-size | Give the button a Menlo font at 48pt, titled "Menlo — 48 pt" | The recorded selected font's point size is 48 (unchanged by the sample-size drawing) |
| font-chooser-button-013 | caller-supplied-title | Give the button a `nil` font, titled "Custom Title" | Title is "Custom Title" |
| font-chooser-button-014 | font-persistence | Static/source review: search for any store write anywhere in the type | No such call exists anywhere in the type; giving the button a new font and title only assigns its own in-memory selected font, drawn font, and title |
| font-chooser-button-015 | opens-font-picker | Activate the button with no font selected yet | The platform's font-selection UI opens, seeded with the system default font, and is brought to the front |
| font-chooser-button-016 | opens-font-picker | Give the button a Menlo font at 48pt, then activate it | The platform's font-selection UI opens seeded with Menlo at 48pt (not the sample size) and is brought to the front |
| font-chooser-button-017 | panel-modes | Query the modes the font-selection UI restricts itself to | Result contains family, face, and size choices, and none of color, underline, strikethrough, or other text-effect choices |
| font-chooser-button-018 | font-change-forwarding | Give the button a Menlo font at 48pt, activate it, then simulate the platform reporting a size change to 60pt picked in the font-selection UI | The change callback is invoked with the button's own selected font (Menlo at 48pt) carrying the newly-picked 60pt size, not a value substituted directly from the platform's own picker state |
| font-chooser-button-019 | nil-sender | Set the change callback to a closure that flips a flag; simulate the platform reporting a font-selection change with no accompanying context | The flag remains unflipped; no crash |
| font-chooser-button-020 | releases-picker-registration-on-removal | Add the button to a window, register it as the active recipient of font-picker selections, then remove it from its window | It is no longer registered as the active recipient afterward |
| font-chooser-button-021 | confines-to-ui-thread | Attempt to construct or mutate the button from off the UI thread | Rejected by the platform's UI-thread confinement enforcement (compile-time on platforms with static isolation checking such as Swift's `@MainActor`, runtime-checked otherwise) |
| font-chooser-button-022 | selected-font-access | Construct the button, give it a font and title, then read the selected font from outside the type | The property is externally readable and reflects the last font given to it; it has no externally-accessible setter |
| font-chooser-button-023 | change-callback-access | Assign a closure to the change callback from outside the type | The assignment succeeds and the closure is the one invoked in font-chooser-button-018 |

Vector font-chooser-button-021 is a static, code-inspection check (a
compile-/runtime-enforced thread confinement), not a vector observed by
running the program; a port lacking equivalent enforcement should document
the gap rather than fabricate a runtime trap.

## Edge Cases

- **Null/empty input**: The font parameter given to the component is
  optional and `nil` is an explicit, handled case (falls back to the
  system font — see **system-font-fallback**). The title parameter is a
  non-optional string; an empty string is drawn as an empty title with no
  crash — already covered by **caller-supplied-title**, which sets the
  title to whatever is passed verbatim, empty or not.
- **Boundary values**: An explicit fixed width is an unconstrained numeric
  value passed straight into the width constraint with no clamping or
  validation. A zero or negative width is passed through unchanged and
  produces a zero-width or layout-unsatisfiable constraint; this is not
  validated (current behavior) — the component performs no
  bounds-checking of its own on the width.
- **Concurrent access**: Not applicable — the component is confined to the
  UI thread, so all construction and mutation is serialized to that
  thread; there is no code path by which two threads mutate the same
  instance simultaneously.
- **Error states**: Not applicable for giving the component a font/title
  or for the picker wiring — every operation in this file is a
  synchronous, non-throwing call; no error-producing path appears in
  source.
- **Offline/disconnected state**: Not applicable — the component performs
  no networking of its own.
- **Multiple instances sharing one active recipient**: The platform's
  font-picker registration holds one active recipient at a time. WHEN two
  instances of this component exist and both have opened the picker, the
  most recently opened one owns that registration; the earlier one's later
  removal is guarded by an identity check against the current registration
  and so correctly does nothing, leaving the picker's current registration
  untouched — already covered by
  **releases-picker-registration-on-removal**, whose "still the active
  recipient" condition is exactly this identity check.
- **Picker opened before any font is ever chosen**: Opening the
  font-selection UI on a freshly-constructed, never-given-a-font button
  does not crash and seeds the picker with the system font at the
  platform's default point size (which is not the sample size) — already
  covered by **opens-font-picker**'s fallback-seed behavior.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `width` | optional numeric value | none (plain default construction) | Fixes the button to this width via one layout constraint, for a button that must line up with others in a grid column. Omitted (or absent), the button takes the width its title wants and gives it up first when its row is squeezed (see **yields-width-under-compression**). |
| `font` (given to the component) | optional font value | none (drawn at construction) | The face to draw the title in and what the font-selection UI opens on; a `nil` value draws the title in the system font. |
| `title` (given to the component) | string | `"System"` (drawn at construction) | What the button reads; the caller owns the wording (see **Label**, above). |
| change callback | function reference (optional) | none | Invoked with the font the user picked in the font-selection UI. |

## Deep Linking

Not applicable: the font chooser button is a settings-row control with no
navigable identity of its own — it has no route, screen, or resource that
a deep link could target.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded literal) | `System` | The button's initial title, set unconditionally at construction, before any caller-supplied title is applied. |

`"System"` is a title assignment from a string literal — an unlocalized
literal — and no localization key or string-catalog mechanism wraps it
anywhere in this file. Every other title the button ever shows is
caller-supplied, so localizing that text is the caller's responsibility,
not this component's; only the one built-in `"System"` default is this
component's own literal, and it is not wrapped in any localization
mechanism — a caller that never gives the button its own title sees this
hardcoded English text regardless of the system's locale.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source performs no animation or transition call anywhere — every state change (font, title, selected font) is an instantaneous property assignment. |
| Increase Contrast | Not applicable: the source sets no custom color anywhere; all coloring is the control's default chrome, which already tracks the system's Increase Contrast setting. |
| Differentiate Without Color | Not applicable: the component conveys no state through color; its one visual presentation is the title drawn in the current font, and font choice itself is not a color-coded status signal. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in source; the button always constructs and wires itself unconditionally.

## Analytics

Not applicable: the source contains no analytics or telemetry call. Any
tracking of a font change is the caller's responsibility inside its change
callback.

## Privacy

- **Data collected**: None of its own. The component holds only the font
  last given to it and an optional change-callback reference supplied by
  the caller.
- **Storage**: Not applicable — source performs no read/write to disk or
  any other store (see **font-persistence**); persistence, if any, is
  entirely the caller's responsibility.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: The component retains its selected font and change
  callback only for its own in-memory lifetime, and only until the next
  time it is given a new font, which replaces the selected font.

## Logging

Not applicable: the source contains no logging call.

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
  `NSFontChanging`. On construction it also sets
  `translatesAutoresizingMaskIntoConstraints = false` (the mechanism behind
  **fixed-width-constraint** and **no-width-constraint** being expressible
  as Auto Layout constraints at all) and sets `NSFontManager.shared.target`
  to itself when opening the panel (the mechanism behind
  **font-change-forwarding** receiving picks at all). There is no UIKit
  code path in source. A UIKit port would present
  `UIFontPickerViewController` (a full-screen modal list, not a floating
  always-on-top panel like `NSFontPanel`) and receive the pick through
  `UIFontPickerViewControllerDelegate`, rather than through the
  target-managed `NSFontManager`/`NSFontChanging` pairing this file uses;
  the target-release workaround in
  **releases-picker-registration-on-removal** has no UIKit equivalent to
  port, since a presented view controller is dismissed rather than leaked
  at a shared singleton. `NSFontManager.target` is declared
  `unowned(unsafe)` (per the source's own test suite comment), so a button
  deallocated together with its entire window — rather than first removed
  from it — can leave the manager writing into freed memory;
  `viewDidMoveToWindow()`'s target-release only fires on individual window
  removal, not on `deinit` (see Design Decisions for the accepted residual
  risk).
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
  **releases-picker-registration-on-removal**'s intent without its
  mechanism.
  On the dialog's confirm/selection-changed event, invoke a caller-supplied
  callback (mirroring `onChange`) with the chosen `FontFamily` and size,
  and let the caller call an equivalent of `show(fontFamily:title:)` back
  on the button afterward to update its own displayed sample and title —
  mirroring the source's "stores nothing itself" design. `Button`'s default
  `VisualStateManager` groups (`Normal`, `PointerOver`, `Pressed`,
  `Disabled`) already cover pressed/disabled visuals without custom state
  XAML, matching the source's own lack of custom pressed/disabled styling.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/FontChooserButton.swift` |

## Design Decisions

**Decision (AppKit)**: `init(frame:)` is a fully working initializer (it calls
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

**Decision (AppKit)**: `validModesForFontPanel(_:)` restricts the font panel to
`.collection`, `.face`, and `.size`, excluding color and text-effect modes.
**Rationale**: Per the source's own comment: "Only the parts of the panel
that pick a font — the color and underline effects would write nothing
anyone reads back."
**Approved**: pending

**Decision (AppKit)**: `viewDidMoveToWindow()` clears `NSFontManager.shared.target`
when the button leaves its window and still owns that target.
**Rationale**: `NSFontManager.target` is `unowned(unsafe)` (confirmed by
the component's own test suite comment); leaving it pointing at a
since-freed button would have the shared font manager write into freed
memory rather than fail safely. This is a workaround for that unsafe
AppKit API, not a feature of the component's own design.
**Approved**: pending

**Decision (AppKit)**: The component accepts the residual risk that
`NSFontManager.shared.target` can be left pointing at freed memory if a
`FontChooserButton` is deallocated together with its entire window (rather
than first removed from it): `viewDidMoveToWindow()` (see
**releases-picker-registration-on-removal**) is the only target-release
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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | internationalization |

The `native-controls-preference` and `platform-design-language` checks pass
because the component defers to macOS's own `NSFontPanel` rather than
building a second font browser (per the source's own doc comment,
`native-controls`). `keyboard-navigable` and `screen-reader-support` pass on
`NSButton`'s inherited Space/Tab handling and the caller-supplied,
availability-aware `title` (see **Label** under Accessibility).
`idempotent-operations` passes because repeated `show(_:title:)` calls with
the same arguments always leave the button in the same observable state,
and repeated presses that re-run `openFontPanel(_:)` are likewise
idempotent: reassigning `NSFontManager.shared.target` and re-seeding
`setSelectedFont` to the same values are no-ops, and calling
`orderFrontFontPanel(_:)` again on an already-frontmost panel leaves it in
the same state. `separation-of-concerns` passes because the component
stores no font of its own beyond the in-memory `selectedFont` (see
#requirements/font-persistence). `string-externalization` fails because
the built-in `"System"` initial title is a hardcoded literal with no
localization key (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for FontChooserButton, covering the two-initializer setup, the draw-size/store-size split, the NSFontChanging panel lifecycle, and the unlocalized "System" default title. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed all 26 requirements from verb phrases to subject-noun kebab-case and updated every citation; switched in-document cross-references to `#requirements/<name>` fragment form; added `related` entries for sibling ColorPickerView and ButtonView recipes; reworded the zero/negative-width edge case from a MUST to "not validated (current behavior)"; downgraded three Edge Cases MUSTs (empty title, shared-target identity guard, nil-selection panel seed) to descriptive text citing the existing requirements that already cover them; corrected the keyboard-navigation description (Space activates, Return does not, Tab requires Full Keyboard Access); clarified font-change-forwarding's behavior when `show(_:title:)` is called while the panel is still open; sharpened test vectors 015, 019, and 021 to be a static/source assertion, a spied-font-manager assertion, and a concrete font/size setup respectively; dropped the WinUI 3 bullet's editorial aside; broadened the idempotent-operations compliance justification to cover the panel/target path; removed the 26-vs-7 requirement-count Design Decision (folded into this summary) and added pending Design Decisions accepting the dealloc-without-window-removal residual risk and tracking the "System" localization open question; and ran the compliance-catalog fixer, which remapped the `meaningful-labels` Compliance row (and its prose reference) to the catalog's `screen-reader-support` check. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
