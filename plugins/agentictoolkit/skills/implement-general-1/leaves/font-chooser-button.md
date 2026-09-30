<!-- leaf: implement-general-1/font-chooser-button · source: font-chooser-button.md -->

**Rules** (cite as `implement-general-1/font-chooser-button#<slug>`):

- `system-placeholder` MUST
- `rounded-momentary-bezel` MUST
- `title-alignment` MUST
- `tail-truncation` MUST
- `compression-resistance` MUST
- `content-hugging` MUST
- `autoresizing-mask-translation` MUST
- `fixed-width-constraint` MUST
- `no-width-constraint` MUST
- `coder-init` MUST
- `sample-size` MUST
- `system-font-fallback` MUST
- `selected-font-size` MUST
- `caller-supplied-title` MUST
- `font-persistence` MUST
- `font-panel-trigger` MUST
- `font-manager-target` MUST
- `panel-seed` MUST
- `panel-order-front` MUST
- `panel-modes` MUST
- `font-change-forwarding` MUST
- `nil-sender` MUST
- `font-manager-target-release` MUST
- `main-actor-confinement` MUST
- `selected-font-access` MUST
- `change-callback-access` MUST
- `minimum-tap-target` MUST — This is a macOS, pointer/trackpad-driven NSButton; source sets no controlSize override, so the click target is the …

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

- **system-placeholder**: On construction via `init(frame:)`, the
  component MUST call `show(nil, title: "System")`, which sets
  `selectedFont` to `nil`, `title` to `"System"`, and `font` to the system
  font at `sampleSize`.
- **rounded-momentary-bezel**: On construction, the component MUST set
  `bezelStyle` to `.rounded` and its button type to `.momentaryPushIn`.
- **title-alignment**: On construction, the component MUST set `alignment`
  to `.left`.
- **tail-truncation**: On construction, the component MUST set its button
  cell's `lineBreakMode` to `.byTruncatingTail`.
- **compression-resistance**: On construction, the component MUST set its
  horizontal content-compression-resistance priority to `.defaultLow`.
- **content-hugging**: On construction, the component MUST set its
  horizontal content-hugging priority to `.defaultLow`.
- **autoresizing-mask-translation**: On construction, the component MUST
  set `translatesAutoresizingMaskIntoConstraints` to `false`.
- **fixed-width-constraint**: WHEN constructed via `init(width:)` with a
  non-nil `width`, the component MUST activate a width constraint equal to
  `width`.
- **no-width-constraint**: WHEN constructed via `init(width:)` with
  `width == nil`, or via the plain `init(frame:)`, the component MUST NOT
  add any width constraint of its own.
- **coder-init**: The component MUST fatal-error if constructed through
  `init?(coder:)`.
- **sample-size**: WHEN `show(_:title:)` is called with a non-nil font, the
  component MUST set `font` to that font converted to `sampleSize` (12pt)
  via `NSFontManager.convert(_:toSize:)`, regardless of the font's own
  point size.
- **system-font-fallback**: WHEN `show(_:title:)` is called with
  `font == nil`, the component MUST set `font` to
  `NSFont.systemFont(ofSize: sampleSize)`.
- **selected-font-size**: WHEN `show(_:title:)` is called, the component
  MUST set `selectedFont` to exactly the `font` argument passed in, at its
  own unconverted size — not the sample-size font drawn on the button.
- **caller-supplied-title**: WHEN `show(_:title:)` is called, the
  component MUST set `title` to the given `title` argument verbatim.
- **font-persistence**: The component MUST NOT write the font recorded in
  `selectedFont` to any store of its own (a default, a theme, a file); it
  exists only in memory for `FontChooserButton`'s own lifetime, and only
  until the next `show(_:title:)` call.
- **font-panel-trigger**: WHEN the button is pressed, the component MUST
  invoke `openFontPanel(_:)` through the target/action wired at
  construction.
- **font-manager-target**: WHEN `openFontPanel(_:)` runs, the component
  MUST set `NSFontManager.shared.target` to itself.
- **panel-seed**: WHEN `openFontPanel(_:)` runs, the component MUST call
  `setSelectedFont` on the shared font manager with `selectedFont` if
  non-nil, or otherwise the system font at `NSFont.systemFontSize`, passing
  `isMultiple: false`.
- **panel-order-front**: WHEN `openFontPanel(_:)` runs, the component MUST
  call `orderFrontFontPanel(_:)` on the shared font manager.
- **panel-modes**: The component's `validModesForFontPanel(_:)` MUST return
  exactly `[.collection, .face, .size]`, excluding color and text-effect
  modes.
- **font-change-forwarding**: WHEN `changeFont(_:)` is called with a
  non-nil font manager, the component MUST invoke `onChange` (if set) with
  that font manager's conversion of `selectedFont` as it stands at the
  moment `changeFont(_:)` runs (or the system font at
  `NSFont.systemFontSize` if `selectedFont` is still `nil`) — not
  necessarily the font the panel was originally opened on, since a
  `show(_:title:)` call made while the panel is still open replaces
  `selectedFont` before `changeFont(_:)` fires.
- **nil-sender**: WHEN `changeFont(_:)` is called with `sender == nil`, the
  component MUST NOT invoke `onChange` and MUST take no other action.
- **font-manager-target-release**: WHEN the component's `window` becomes
  `nil` AND `NSFontManager.shared.target` is still this instance,
  `viewDidMoveToWindow()` MUST set `NSFontManager.shared.target` to `nil`.
- **main-actor-confinement**: The component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **selected-font-access**: The component MUST expose `selectedFont` as a
  public, externally-read-only property.
- **change-callback-access**: The component MUST expose `onChange` as a
  public, externally-settable property.

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
  activates one fixed-width constraint (see #requirements/fixed-width-constraint);
  no height constraint is ever added — height is intrinsic to the
  `.rounded` bezel at the drawn `font`'s line height.

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
- **Keyboard navigation**: Inherited from `NSButton` — Space activates the
  button through the target/action wired at construction
  (`openFontPanel(_:)`); the component sets no `\r` key equivalent, so
  Return does not activate it. Tab/Shift-Tab only move focus onto and off
  the button when Full Keyboard Access is enabled — macOS's default key-view
  loop otherwise skips buttons. The resulting `NSFontPanel` is a separate,
  standard AppKit window; its own keyboard navigation is not implemented in
  this file.
- **Minimum tap target**: This is a macOS, pointer/trackpad-driven
  `NSButton`; source sets no `controlSize` override, so the click target is
  the regular-size rounded bezel sized to `title`, per the macOS Human
  Interface Guidelines for pointer-driven controls. Ports to touch
  platforms MUST give the equivalent control at least the platform
  minimum: 44 by 44 pt on iOS, 48 by 48 dp on Android, 40 by 40 effective
  pixels on WinUI 3.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `width` | `CGFloat?` | `nil` (plain `init(frame:)`) | Fixes the button to this width via one Auto Layout constraint, for a button that must line up with others in a grid column. Omitted (or `nil`), the button takes the width its title wants and gives it up first when its row is squeezed (see #requirements/compression-resistance). |
| `font` (via `show(_:title:)`) | `NSFont?` | `nil` (drawn at construction) | The face to draw the title in and what the font panel opens on; `nil` draws the title in the system font. |
| `title` (via `show(_:title:)`) | `String` | `"System"` (drawn at construction) | What the button reads; the caller owns the wording (see **Label**, above). |
| `onChange` | `((NSFont) -> Void)?` | `nil` | Invoked with the font the user picked in the font panel. |

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
component's own literal, and it is not wrapped in `String(localized:)` or
any string-catalog key — a caller that never calls `show(_:title:)` sees
this hardcoded English text regardless of the system's locale.

