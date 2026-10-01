---
id: c3269cfa-a8ec-4ba9-bc68-9cdf98e7e1fc
title: Permission Row View
domain: agentictoolkit://cookbook/system/permissions/permission-row-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A card row that shows one permission's live grant status, with a trailing
  action button that opens the platform's permission settings or triggers an in-app
  consent prompt.
platforms:
- swift
- macos
tags:
- ui
- permissions
- async
depends-on:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
related: []
references: []
approved-by: ''
approved-date: ''
---

# Permission Row View

## Overview

The permission row is a self-contained card that renders one permission's
live grant status: an icon, a title, a one-line explanation, a status dot
plus label, and a trailing action button that either opens the platform's
permission settings or, for a permission with no settings pane, triggers the
host app's own consent dialog. It has no dependency on any settings
framework. It is composed by the panel that lists all permissions, which
stacks one row per permission and drives a refresh on appear, on app
reactivation, and after an action completes.

## Behavioral Requirements

- **renders-title-from-permission**: The component MUST set its title
  label's text to the permission's display name, except for the Automation
  permission, where it MUST append `" — "` plus the target's resolved
  application name (or the raw bundle identifier when that resolution
  fails).
- **renders-description-from-permission**: The component MUST set its
  description label's text to the permission's explanation, resolving an
  Automation target's name the same way as the title.
- **renders-icon-from-permission**: The component MUST show an icon view
  with the symbol named by the permission's icon name, at point size 16,
  weight regular, tinted the secondary label color.
- **initial-status-is-checking**: The component MUST display `"Checking…"`
  in the status label before a refresh completes for the first time.
- **refresh-queries-checker**: Refreshing MUST call the injected status
  checker for the permission and, unless the underlying asynchronous work
  was cancelled while awaiting the result, MUST update the status dot's
  color, the status label's text and color, and the action button's title
  from the result.
- **cancelled-refresh-does-not-apply**: If a refresh's underlying
  asynchronous work is cancelled before the status checker returns, the
  component MUST leave its displayed status, dot color, and button title
  unchanged.
- **granted-status-appearance**: The component MUST show the status dot
  colored with the success color and the status label reading `"Granted"`
  in the success color when the status checker resolves to granted.
- **denied-status-appearance**: The component MUST show the status dot
  colored with the warning color and the status label reading
  `"Not Granted"` in the warning color when the status checker resolves to
  denied.
- **undetermined-status-appearance**: The component MUST show the status
  dot colored with the secondary label color and the status label reading
  `"Unknown"` in the secondary label color when the status checker resolves
  to undetermined.
- **status-conveyed-by-text-and-color**: The component MUST convey grant
  status through the status label's text in addition to the status dot's
  color, in every one of the three states above, so status is never
  communicated by color alone.
- **granted-button-title**: The component MUST set the action button's
  title to `"Open Settings"` whenever the most recently applied status is
  granted.
- **ungranted-button-title**: The component MUST set the action button's
  title to the permission's own action title whenever the most recently
  applied status is denied or undetermined.
- **button-width-fits-widest-title**: The component MUST size the action
  button to a fixed width equal to the widest fitting width across every
  possible action title, measured once per process with a sizing probe
  matching the real action button's own style and size.
- **action-carries-displayed-status**: Pressing the action button MUST
  invoke the configured action handler with the permission and whatever
  status was applied by the most recent status-apply call, not a freshly
  re-read status.
- **pre-refresh-action-enabled**: The component MUST NOT disable the
  action button before the first refresh completes; the component's
  layout-building step never disables it, so pressing it before that point
  MUST invoke the action handler with the permission and the displayed
  status's initial value, undetermined.
- **keyboard-activates-action**: The action control MUST be reachable by
  keyboard focus and activatable with the primary activation keys
  (Space/Return).
- **test-observable-surface**: Beyond a small, deliberately exposed set of
  test seams (the displayed status text, the displayed action-button
  title, and a test-only trigger for the action), no other internal state
  of the component is exposed for testing. A test MUST reach the title,
  description, icon, and status-dot views by walking the component's own
  public view hierarchy, or by reading its publicly inherited visual layer
  for card-appearance assertions.
- **action-button-has-stable-identifier**: The action button MUST set its
  accessibility identifier to a value derived from the permission's own
  stable identifier token, in the form `"permission.<token>.action"`.
- **row-has-no-accessibility-identifier**: The row view itself MUST NOT set
  an accessibility identifier and MUST NOT become an accessibility element;
  the action button is the only per-permission accessibility handle.
- **minimum-row-height**: The component MUST maintain a height of at least
  72pt.
- **card-appearance**: The component MUST render with a backing layer, an
  8pt corner radius, a background of white at 3% opacity, and a 0.5pt
  border of white at 6% opacity.

## Appearance

- **Corner radius**: 8pt
- **Padding**: icon leading 12pt from the row's leading edge, top 12pt; the
  title/description/status column's leading edge sits 10pt from the icon's
  trailing edge; the action button's trailing edge sits 12pt from the row's
  trailing edge; the status row's bottom edge sits 10pt from the row's
  bottom edge; description-to-button gap is 12pt; title-to-description gap
  is 2pt; description-to-status-row gap is 6pt
- **Font**: title 13pt medium; description 11pt regular; status label 11pt
  medium; drawn with the platform's system font
- **Background**: white at 3% opacity, rendered with a backing layer
- **Foreground/Text**: title uses the platform's default label text color
  (unset by source); description uses the secondary label color; status
  label color tracks the current status (success color / warning color /
  secondary label color)
- **Border**: 0.5pt, white at 6% opacity
- **Shadow**: none — not set anywhere in source
- **Min/Max size**: row height `>= 72pt` (no maximum); icon fixed 24×24pt;
  status dot fixed 8×8pt; action button fixed width equal to the widest of
  `"Open Settings"` and `"Allow…"`, measured once by the sizing probe
  described above

## States

| State | Appearance change |
|-------|------------------|
| Default (constructed, before first refresh) | The status label reads `"Checking…"` (its initial value); the status dot has no color assigned yet (only a status-apply call sets one); the action button's title already reads the permission's own action title, set unconditionally during layout, independent of any status read. |
| Granted | Status dot color becomes the success color; status label reads `"Granted"` in the success color; action button title becomes `"Open Settings"`. |
| Denied | Status dot color becomes the warning color; status label reads `"Not Granted"` in the warning color; action button title becomes the permission's own action title. |
| Undetermined | Status dot color becomes the secondary label color; status label reads `"Unknown"` in the secondary label color; action button title becomes the permission's own action title. |
| Pressed | Not applicable to the row itself: the row is not a control. The action button's own pressed appearance is the platform's default button-press highlight, unstyled by this component. |
| Disabled | Not implemented in source: the action button, the row, or any subview is never disabled. The button stays interactive in every status, including before the first refresh completes — pressing it then reports undetermined, the displayed status's initial value. |
| Focused | Not styled by this component: any focus ring on the action button when focused is the platform's own native focus appearance. |
| Loading | Same as "Default (constructed, before first refresh)" above — this component has one pre-refresh state, shown as `"Checking…"`, not a distinct spinner or progress indicator. |

## Accessibility

- Role/trait: the row itself is a plain view; the component deliberately
  never marks it as an accessibility element (documented in source as an
  intentional omission). The action button is a standard button (role
  button), the only accessibility element this component contributes per
  row.
- Label requirements: the action button's accessible label comes from its
  own title (the permission's action title, or `"Open Settings"`); the
  component sets no separate accessibility label on the button, the row,
  or the status text.
- Identifier: the action button's accessibility identifier is set to a
  value derived from the permission's own stable identifier token (see
  action-button-has-stable-identifier), so a UI test can address it per
  permission; the row and its other subviews (icon, title, description,
  status dot/label) receive no accessibility identifier.
- Announce state changes: a status-apply call updates the status label's
  displayed text with a plain assignment; this component never explicitly
  posts an accessibility change notification anywhere in source, so it
  does not itself announce a status change to assistive technology.
- Minimum tap target: not applicable in the touch sense — this is a
  pointer-driven control on a desktop platform, and touch minimum-target
  guidance does not apply here. The action button's compact sizing is the
  platform's own system-determined click target, not measured or floored
  by this component.
- **contrast**: NEEDS REVIEW: Not implemented in source. Title, description, and status text sit over the card's near-transparent white overlay (3%/6% alpha), which is itself composited over whatever background the host window supplies; whether that combination meets a 4.5:1 (or 3:1 large-text) contrast ratio per `agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages` cannot be determined from source alone, since the effective background color is not fixed, and it needs an accessibility audit against the actual host background.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| permission-row-001 | renders-title-from-permission | Construct with the Accessibility permission | Title label text is exactly `"Accessibility"`. |
| permission-row-002 | renders-title-from-permission | Construct with the Automation permission targeting a bundle identifier for which no matching app is installed (`"com.googlecode.iterm2"`) | Title label text is `"Automation — com.googlecode.iterm2"` (falls back to the raw bundle identifier). |
| permission-row-003 | renders-description-from-permission | Construct with the Keychain permission for the service `"Claude Code-credentials"` | Description label text reads `Lets this app read the "Claude Code-credentials" item in your keychain directly, instead of asking another tool for it.` |
| permission-row-004 | renders-icon-from-permission | Construct with the Microphone permission | The icon view found among the row's subviews resolves the symbol named `mic`, reports a configuration of point size 16 / weight regular, and has its tint color set to the secondary label color. |
| permission-row-005 | initial-status-is-checking | Construct a row, do not refresh it | The displayed status text reads `"Checking…"`. |
| permission-row-006 | refresh-queries-checker | Stub the status checker to return granted; refresh the row | The displayed status text reads `"Granted"`. |
| permission-row-007 | cancelled-refresh-does-not-apply | Start a refresh, cancel its underlying asynchronous work before the status checker returns, then await its completion | The displayed status text remains `"Checking…"`. |
| permission-row-008 | granted-status-appearance | The status checker returns granted; refresh the row | The displayed status text reads `"Granted"`; the status dot's color is the success color. |
| permission-row-009 | denied-status-appearance | The status checker returns denied; refresh the row | The displayed status text reads `"Not Granted"`; the status dot's color is the warning color. |
| permission-row-010 | undetermined-status-appearance | The status checker returns undetermined; refresh the row | The displayed status text reads `"Unknown"`; the status dot's color is the secondary label color. |
| permission-row-011 | status-conveyed-by-text-and-color | Refresh a row through all three statuses in turn | For each status, both the displayed text and the status dot's color differ from the other two statuses — no two statuses share the same text or the same color. |
| permission-row-012 | granted-button-title | The Keychain permission; the status checker returns granted; refresh the row | The displayed action-button title reads `"Open Settings"`. |
| permission-row-013 | ungranted-button-title | The Keychain permission for service `"Claude Code-credentials"`; the status checker returns denied, then separately undetermined; refresh the row on each | Both rows' displayed action-button title reads `"Allow…"`. |
| permission-row-014 | button-width-fits-widest-title | Construct two rows with different permissions | Both rows' action buttons report the same width, equal to the fitting width of the longer of `"Open Settings"` / `"Allow…"`. |
| permission-row-015 | action-carries-displayed-status | The status checker returns denied; refresh the row; trigger the action via its test-only trigger | The action handler is invoked with the permission and denied. |
| permission-row-016 | action-button-has-stable-identifier | Construct with the Location permission | The action button's accessibility identifier is `"permission.location.action"`. |
| permission-row-017 | row-has-no-accessibility-identifier | Construct any row | The row itself is not an accessibility element and has no accessibility identifier set. |
| permission-row-018 | minimum-row-height | Construct any row and let its layout resolve | Resolved height is `>= 72` points. |
| permission-row-019 | card-appearance | Construct any row | The row is rendered with a backing layer; its corner radius is `8`; its border width is `0.5`; its background color is white at 3% opacity; its border color is white at 6% opacity. |
| permission-row-020 | keyboard-activates-action | Construct any row, move keyboard focus to the action button, then perform its primary activation key (Space/Return) | The action handler is invoked the same way it is by the test-only trigger or a pointer click, since the action control is an unmodified standard button. |
| permission-row-021 | pre-refresh-action-enabled | Construct a row, do not refresh it, then trigger the action via its test-only trigger | The action button remains enabled throughout, and the action handler is invoked with the permission and undetermined. |

## Edge Cases

- **Null/empty input** (MUST): the Automation permission targeting an empty
  bundle identifier — the platform's own app-name resolution returns
  nothing for the empty string, so the target-name lookup's fallback
  returns the bundle identifier string itself (here, empty). The title
  MUST render as `"Automation — "` and the Automation sentence in the
  description MUST render with an empty target name, rather than crashing.
  The Keychain permission for an empty service takes a different path: the
  title-building logic only special-cases Automation, so the title MUST
  still render as plain `"Keychain"` (the permission's display name),
  unaffected by the empty service; the description MUST render as the
  literal sentence with an empty quoted service name (`Lets this app read
  the "" item in your keychain directly, instead of asking another tool for
  it.`), rather than crashing or omitting the quotes.
- **Boundary values** (MUST): an unusually long explanation string MUST
  wrap across multiple lines in the description label (a wrapping text
  field with no line limit set), and the row MUST grow taller than the
  72pt floor to fit it, since its height constraint is a minimum, not a
  fixed height.
- **Concurrent access** (SHOULD): two overlapping refresh calls on the same
  row, neither cancelling the other — the component performs no internal
  serialization of overlapping refreshes, so which call's status result
  resolves last, and therefore which result the displayed state ends up
  showing, is left undefined by this component itself; each status-apply
  call simply overwrites whatever the previous one set. Coordinating that
  ordering SHOULD be the caller's responsibility (as the panel that
  composes these rows does with its own single refresh task), not this
  component's.
- **Error states**: Not applicable — the status-checking contract is
  declared non-throwing and returns a status value directly; undetermined
  already exists to mean "can't currently tell" (for example, an
  Automation target that isn't running), so there is no separate
  failure/error path for this component to render beyond the three states
  already specified.
- **Offline/disconnected state**: Not applicable — this component and its
  status checker read only local system authorization state; the component
  makes no network call, so connectivity has no defined effect on it.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| permission | a permission value | none (required) | Which permission this row displays and acts on; drives the title, icon, description, and accessibility identifier. |
| checker | a status-checking dependency | none (required) | Supplies the asynchronous grant-status read that a refresh calls. |
| action handler | a callback taking a permission and a status | none (required) | Invoked when the action button is pressed, carrying the permission and the status shown at press time. |

## Deep Linking

Not applicable: this component is an embedded row, not a navigable
destination. It defines no URL scheme, route, or deep-link handling.
Opening a permission's system settings pane is decided and performed by
whatever consumes the action handler, not by this component.

## Localization

None of the strings below are passed through a localization mechanism
anywhere in this component; every user-facing string is a hardcoded English
literal, or a fixed mapping from a status/permission value to a literal
string.

Every string below reaches the UI unlocalized; a port should decide whether
to route them through its own string catalog, since the source gives no
keys to carry over.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded, unlocalized) | `Checking…` | Initial status label text, before the first refresh completes. |
| (none — hardcoded, unlocalized) | `Granted` | Status label text when the status checker returns granted. |
| (none — hardcoded, unlocalized) | `Not Granted` | Status label text when the status checker returns denied. |
| (none — hardcoded, unlocalized) | `Unknown` | Status label text when the status checker returns undetermined. |
| (none — hardcoded, unlocalized) | `Open Settings` | Action button title when granted, or when the permission has a settings pane and is not yet granted. |
| (none — hardcoded, unlocalized) | `Allow…` | Action button title for a permission with no settings pane (Keychain) and not yet granted. |
| (none — hardcoded, unlocalized) | The permission's display-name values, e.g. `Accessibility`, `Notifications`, `Automation`, `Location`, `Microphone`, `Screen Capture`, `Keychain` | Row title, from the permission's display name. |
| (none — hardcoded, unlocalized) | The permission's explanation sentences | Row description text. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: this component performs no animation of any kind — every state change (the status label's text, the status dot's color, the action button's title) is an instantaneous property assignment. There is no explicit animation call anywhere in source for Reduce Motion to affect. |
| Increase Contrast | The status dot, status label, and action-button title color use semantic dynamic colors (the success color, the warning color, the secondary label color) that adjust automatically under Increase Contrast, but the card's fixed background/border colors do not, and the component does not respond to Increase Contrast for them. |
| Differentiate Without Color | Grant status is always communicated by the status dot's color together with the status label's text (`Granted` / `Not Granted` / `Unknown`) and the action button's title — never by color alone — so no additional adjustment is required. |


## Feature Flags

Not applicable: this component contains no feature-flag or remote-config
check; a row is unconditionally built and shown for whatever permission its
caller supplies.

## Analytics

Not applicable: this component contains no analytics or event-tracking call
of any kind.

## Privacy

- **Data collected**: None collected or persisted by this view; it only
  displays a status value handed to it by the injected status checker.
- **Storage**: The most recently applied status is held in memory for the
  lifetime of the component instance only; nothing is written to disk by
  this component.
- **Transmission**: None. This component makes no network call; the status
  checker reads local system authorization state, which is not something
  this component itself performs.
- **Retention**: For the lifetime of the view instance; discarded on
  deallocation, with no persistence layer in this component.

## Logging

Not applicable: this component contains no logging call at any level.

## Platform Notes

- **SwiftUI**: compose a `HStack` with an `Image(systemName: permission.systemImageName)`,
  a `VStack(alignment: .leading)` of two `Text` views for title and
  description, a `Spacer()`, a small `HStack` pairing a `Circle().fill(...)`
  8×8 status dot with `Text(statusText)`, and a `Button(actionTitle,
  action:)`. Replace Auto Layout constraints with stack spacing/padding
  modifiers; drive `displayedStatus` and `statusText` from `@State`; drive
  `refresh()` from a `.task(id:)` modifier, which SwiftUI cancels and
  restarts automatically the way the source's own `Task.isCancelled` guard
  does by hand. `Color(nsColor: .systemGreen)` etc. map the same semantic
  colors. Give the button a fixed `.frame(minWidth:)` sized to the wider
  title rather than re-deriving `widestActionWidth`'s probe-measurement
  trick, which has no direct SwiftUI equivalent.
- **Compose**: a `Row` with an `Icon`/`Image` (vector asset matching
  `permission.systemImageName`'s meaning), a `Column` of two `Text`
  composables for title and description, a `Spacer`, a small `Row` pairing
  an 8dp `Box` (circular shape, `background(color)`) with a `Text`, and a
  `Button`/`TextButton` for the action. Hold `displayedStatus` in
  `remember { mutableStateOf(...) }`, and run `refresh()` from a
  `LaunchedEffect` keyed on the permission, which Compose cancels the same
  way `Task` cancellation is checked in source. Map status colors through
  `MaterialTheme.colorScheme` roles rather than hardcoded greens/oranges.
  Unlike this macOS source, Android's Material 3 guidance expects a minimum
  48dp touch target on the action button; size it accordingly even though
  the AppKit source imposes no such floor.
- **React/Web**: a flex row `div` containing an icon (`svg`/`img`), a text
  column (title + description), a small status indicator (a colored `span`
  dot plus a text `span`), and a `button` element. Hold status in
  `useState`, and run the refresh in a `useEffect` with an `AbortController`
  whose `signal` mirrors the source's `Task.isCancelled` guard. Wrap the
  status text in an element with `aria-live="polite"` (or `role="status"`)
  so assistive tech is notified on update automatically — the gap the
  source's own "Announce state changes" item above leaves open. Style
  focus with `:focus-visible` on the button; convey status with both the
  dot's `background-color` and the text, matching the source's non-color-only
  behavior.
- **AppKit / UIKit**: this is the source platform —
  `packages/apple/AgenticToolkit/PermissionsUI/PermissionRowView.swift`
  builds the whole row from `NSImageView`, `NSTextField` (label and
  wrapping-label variants), a plain `NSView` for the status dot, an
  `NSStackView` for the status row, and an `NSButton`, laid out with
  `NSLayoutConstraint.activate`. Icons render via SF Symbols
  (`permission.systemImageName`). The action button's fixed width is
  measured once per process using an `NSButton` probe with
  `bezelStyle: .rounded` and `controlSize: .small`, matching the real
  button's own style (button-width-fits-widest-title). Keyboard activation
  (keyboard-activates-action) requires no special handling here: the
  action control is an unmodified `NSButton`, and `buildLayout()` never
  overrides key handling or `acceptsFirstResponder`, so AppKit's native
  keyboard support for a standard button applies unchanged. Beyond the
  three seams marked `// Test seam:` in source — `statusText`
  (`statusLabel.stringValue`), `actionTitle` (`actionButton.title`), and
  `performActionForTesting()` (invokes `actionTapped()`) — no other member
  of `PermissionRowView` is `internal` or `public`; a test reaches the
  title, description, icon, and status-dot views by walking the public
  `NSView.subviews`/`NSStackView.views` hierarchy `buildLayout()` builds,
  or by reading the publicly inherited `layer` for card-appearance
  assertions (test-observable-surface). There is no UIKit counterpart in
  this codebase; a UIKit port would replace `NSView`/`NSButton`/`NSStackView`
  with `UIView`/`UIButton`/`UIStackView`, `NSColor` with `UIColor`, and the
  `@MainActor` `Task`-cancellation guard carries over unchanged since it is
  Swift Concurrency, not an AppKit-specific mechanism.
- **WinUI 3**: build the row as a `Border` (`CornerRadius="8"`,
  `Background`/`BorderBrush` set to `SolidColorBrush`s approximating the
  3%/6% white-alpha overlay, or a `{ThemeResource CardBackgroundFillColorDefaultBrush}`
  if the app already has one) hosting a `Grid` or `RelativePanel`. Use a
  `FontIcon` (a Segoe Fluent glyph chosen to match the meaning of
  `permission.systemImageName`) at the leading edge; a `TextBlock` with
  `Style="BodyStrongTextBlockStyle"` for the title; a `TextBlock` with
  `Style="CaptionTextBlockStyle"` and
  `Foreground="{ThemeResource TextFillColorSecondaryBrush}"` for the
  description; a `StackPanel Orientation="Horizontal"` pairing an 8×8
  `Ellipse` (`Fill` bound to a status brush) with a `TextBlock` for the
  status row; and a `Button` docked to the trailing edge. Model the three
  statuses as a `VisualStateGroup` (`Granted` / `Denied` / `Undetermined`)
  whose `VisualState.Setters` retarget the `Ellipse.Fill` and status
  `TextBlock.Text`/`Foreground` — `{ThemeResource SystemFillColorSuccessBrush}`
  for granted, `{ThemeResource SystemFillColorCautionBrush}` for denied, and
  `{ThemeResource TextFillColorSecondaryBrush}` for undetermined — mirroring
  the source's `systemGreen`/`systemOrange`/`secondaryLabelColor` switch in
  `apply(status:)`, and drive transitions with
  `VisualStateManager.GoToState`. WinUI has no equivalent of AppKit's
  content-hugging probe measurement, so give the `Button` a fixed
  `MinWidth` sized to the longer of the two title strings (measured once in
  code-behind, or simply hardcoded) rather than trying to reproduce
  `widestActionWidth`'s runtime measurement. Set
  `AutomationProperties.AutomationId` on the `Button` to
  `"permission." + permission.IdentifierToken + ".action"` to mirror the
  source's accessibility identifier, and drive the async refresh with a
  `Task`/`CancellationTokenSource` pair mirroring Swift's `Task` and
  `Task.isCancelled`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/PermissionsUI/PermissionRowView.swift` |

## Design Decisions

- **Decision**: hand the pressed action the status displayed at press time
  (`displayedStatus`), not a freshly re-read one.
  **Rationale**: per the source's own doc comment, the display and live TCC
  state can disagree — the user can revoke a permission in System Settings
  while the panel is open — and re-reading at press time would turn a
  button that offered to open System Settings into a live consent prompt
  for a different state than what the user saw and pressed.
  **Approved**: pending
- **Decision**: measure `widestActionWidth` once as a static, process-wide
  probe rather than sizing each button to its own content.
  **Rationale**: per the source's own doc comment, this keeps every row's
  button the same fixed width, so a title change (for example Denied to
  Granted) never reflows the button or the card around it, and the
  measurement is the same for every row since it depends only on the
  titles and the system font.
  **Approved**: pending
- **Decision**: give the row itself no accessibility identifier and no
  accessibility-element status; only the action button is addressable.
  **Rationale**: per the source's own comment, a plain `NSView` is not
  published to accessibility clients by default, and turning the container
  into an accessibility group would add a VoiceOver stop nothing here asks
  for; the button is the real, per-permission handle both tests and
  VoiceOver need.
  **Approved**: pending
- **Decision**: resolve an Automation target's application name via
  `NSWorkspace` inside `PermissionRowView` rather than inside `Permission`.
  **Rationale**: per the source's own comment, `Permission` is
  Foundation-only so a permission-checking daemon process can link it;
  resolving a bundle id to a display name needs `NSWorkspace`, which only
  exists where AppKit is available, so the resolving happens here and is
  handed into `explanation(namingAutomationTarget:)` and `rowTitle(for:)`.
  **Approved**: pending
- **Decision**: ship `card-appearance`'s overlay (3% white background, 6%
  white border) as a fixed, non-semantic color pair rather than an
  appearance-adaptive token.
  **Rationale**: `buildLayout()` sets `layer?.backgroundColor` and
  `layer?.borderColor` to `NSColor.white.withAlphaComponent(...)` with no
  Light Mode or Increase Contrast variant, which only reads as intended
  over a dark host background; recording this as an accepted dark-only
  assumption is more accurate than either calling it done or inventing a
  semantic replacement the source does not have.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | partial | Platform Compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |

`native-controls-preference` is `passed` because every element is a stock
`NSButton`/`NSTextField`/`NSImageView`/`NSStackView`; `platform-design-language`
and `contrast-ratio` are `partial` because `buildLayout()` fills and borders
the card with fixed, non-semantic `NSColor.white.withAlphaComponent(...)`
values (see the dark-only Design Decision above and the open question on
contrast) rather than an appearance-adaptive token, so neither HIG
conformance nor a 4.5:1 contrast ratio can be confirmed for every host
background; `keyboard-navigable` is `passed` because the action button is an
unmodified `NSButton`, which keeps AppKit's native keyboard focus and
activation (see **keyboard-activates-action**).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation, extracted from `PermissionRowView.swift`. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: added pre-refresh-action, keyboard-activation, and test-observable-surface requirements with vectors; reworded concurrent-access as caller-owned/undefined ordering; detailed the empty-keychain edge case; fixed vector 013 to use `.keychain` and extended vectors 004/019 with icon/card-color assertions; bolded Design Decisions and added one for the dark-only card overlay; marked `platform-design-language`/`contrast-ratio` partial, title-cased Compliance categories, and dropped two checks with no catalog match. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to system/permissions/. |
