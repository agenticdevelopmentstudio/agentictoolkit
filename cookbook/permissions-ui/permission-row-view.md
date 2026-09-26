---
id: c3269cfa-a8ec-4ba9-bc68-9cdf98e7e1fc
title: PermissionRowView
domain: agentictoolkit://cookbook/permissions-ui/permission-row-view
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AppKit card row showing one Permission's grant status with a Settings/consent
  action button.
platforms:
- swift
- macos
tags:
- ui
- permissions
- macos
- appkit
- async
depends-on:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
related: []
references: []
approved-by: ''
approved-date: ''
---

# PermissionRowView

## Overview

`PermissionRowView` is a macOS-only, `@MainActor` AppKit `NSView`
(`packages/apple/AgenticToolkit/PermissionsUI/PermissionRowView.swift`) that
renders one `Permission`'s live grant status as a self-contained card row: an
icon, a title, a one-line explanation, a status dot plus label, and a trailing
button that either opens System Settings or, for `.keychain`, triggers the
app's own consent dialog. It has no dependency on any settings framework. It
is composed by `PermissionsPanelView`, which stacks one row per `Permission`
and drives `refresh()` on appear, on app reactivation, and after an action
completes.

## Behavioral Requirements

- **renders-title-from-permission**: The component MUST set its title label's
  text to `permission.displayName`, except for `.automation`, where it MUST
  append `" — "` plus the target's resolved application name (or the raw
  bundle identifier when `NSWorkspace` cannot resolve one), per
  `rowTitle(for:)`.
- **renders-description-from-permission**: The component MUST set its
  description label's text to
  `permission.explanation(namingAutomationTarget:)`, resolving an Automation
  target's name the same way as the title.
- **renders-icon-from-permission**: The component MUST show an `NSImageView`
  with the SF Symbol named by `permission.systemImageName`, at point size 16,
  weight regular, tinted `secondaryLabelColor`.
- **initial-status-is-checking**: The component MUST display `"Checking…"` in
  the status label before `refresh()` completes for the first time.
- **refresh-queries-checker**: `refresh()` MUST call `checker.status(permission)`
  and, unless its underlying `Task` was cancelled while awaiting the result,
  MUST update the status dot's color, the status label's text and color, and
  the action button's title from the result.
- **cancelled-refresh-does-not-apply**: If `refresh()`'s underlying `Task` is
  cancelled before `checker.status(permission)` returns, the component MUST
  leave its displayed status, dot color, and button title unchanged.
- **granted-status-appearance**: The component MUST show `statusDot` colored
  `.systemGreen` and `statusLabel` reading `"Granted"` in `.systemGreen` when
  `checker.status(permission)` resolves to `.granted`.
- **denied-status-appearance**: The component MUST show `statusDot` colored
  `.systemOrange` and `statusLabel` reading `"Not Granted"` in
  `.systemOrange` when `checker.status(permission)` resolves to `.denied`.
- **undetermined-status-appearance**: The component MUST show `statusDot`
  colored `.secondaryLabelColor` and `statusLabel` reading `"Unknown"` in
  `.secondaryLabelColor` when `checker.status(permission)` resolves to
  `.undetermined`.
- **status-conveyed-by-text-and-color**: The component MUST convey grant
  status through `statusLabel`'s text in addition to `statusDot`'s color, in
  every one of the three states above, so status is never communicated by
  color alone.
- **granted-button-title**: The component MUST set the action button's title
  to `"Open Settings"` (`Permission.ActionTitle.openSettings`) whenever the
  most recently applied status is `.granted`.
- **ungranted-button-title**: The component MUST set the action button's
  title to `permission.actionTitle` whenever the most recently applied
  status is `.denied` or `.undetermined`.
- **button-width-fits-widest-title**: The component MUST size the action
  button to a fixed width equal to the widest fitting width across
  `Permission.ActionTitle.all`, measured once per process with an `NSButton`
  probe using `bezelStyle: .rounded` and `controlSize: .small`.
- **action-carries-displayed-status**: Pressing the action button MUST invoke
  the `onAction` closure with `permission` and whatever `PermissionStatus`
  was applied by the most recent `apply(status:)` call, not a freshly
  re-read status.
- **pre-refresh-action-enabled**: The component MUST NOT disable the action
  button before the first `refresh()` completes; `buildLayout()` never sets
  `isEnabled` on it, so pressing it before that point MUST invoke `onAction`
  with `permission` and `displayedStatus`'s initial value, `.undetermined`.
- **keyboard-activates-action**: The action button MUST be reachable by
  keyboard focus and activatable with Space/Return, since it is an
  unmodified `NSButton` — `buildLayout()` never overrides key handling or
  `acceptsFirstResponder`, so AppKit's native keyboard support for a
  standard button applies unchanged.
- **test-observable-surface**: Beyond the three seams marked `// Test seam:`
  in source — `statusText` (`statusLabel.stringValue`), `actionTitle`
  (`actionButton.title`), and `performActionForTesting()` (invokes
  `actionTapped()`) — no other member of `PermissionRowView` is `internal`
  or `public`. A test MUST reach the title, description, icon, and
  status-dot views by walking the public `NSView.subviews` /
  `NSStackView.views` hierarchy `buildLayout()` builds, or by reading the
  publicly inherited `layer` for card-appearance assertions.
- **action-button-has-stable-identifier**: The action button MUST set its
  accessibility identifier to `"permission.\(permission.identifierToken).action"`.
- **row-has-no-accessibility-identifier**: The row view itself MUST NOT set
  an accessibility identifier and MUST NOT become an accessibility element;
  the action button is the only per-permission accessibility handle.
- **minimum-row-height**: The component MUST maintain a height of at least
  72pt.
- **card-appearance**: The component MUST render as a layer-backed view with
  an 8pt corner radius, a background of white at 3% opacity, and a 0.5pt
  border of white at 6% opacity.

## Appearance

- **Corner radius**: 8pt (`layer.cornerRadius`)
- **Padding**: icon leading 12pt from the row's leading edge, top 12pt; the
  title/description/status column's leading edge sits 10pt from the icon's
  trailing edge; the action button's trailing edge sits 12pt from the row's
  trailing edge; the status row's bottom edge sits 10pt from the row's
  bottom edge; description-to-button gap is 12pt; title-to-description gap
  is 2pt; description-to-status-row gap is 6pt
- **Font**: title 13pt medium; description 11pt regular; status label 11pt
  medium; all `NSFont.systemFont`
- **Background**: `NSColor.white.withAlphaComponent(0.03)`, layer-backed
- **Foreground/Text**: title uses `NSTextField`'s default label color
  (unset by source); description uses `.secondaryLabelColor`; status label
  color tracks the current status (`.systemGreen` / `.systemOrange` /
  `.secondaryLabelColor`)
- **Border**: 0.5pt, `NSColor.white.withAlphaComponent(0.06)`
- **Shadow**: none — not set anywhere in source
- **Min/Max size**: row height `>= 72pt` (no maximum); icon fixed 24×24pt;
  `statusDot` fixed 8×8pt; action button fixed width equal to
  `widestActionWidth`, the wider of `"Open Settings"` and `"Allow…"`
  measured once with the probe button described above

## States

| State | Appearance change |
|-------|------------------|
| Default (constructed, before first `refresh()`) | `statusLabel` reads `"Checking…"` (its initial `NSTextField(labelWithString:)` value); `statusDot`'s layer has no background color assigned yet (only `apply(status:)` sets one); `actionButton.title` already reads `permission.actionTitle`, set unconditionally in `buildLayout()` independent of any status read. |
| Granted | `statusDot.layer?.backgroundColor = NSColor.systemGreen.cgColor`; `statusLabel.stringValue = "Granted"`, `textColor = .systemGreen`; `actionButton.title = "Open Settings"`. |
| Denied | `statusDot.layer?.backgroundColor = NSColor.systemOrange.cgColor`; `statusLabel.stringValue = "Not Granted"`, `textColor = .systemOrange`; `actionButton.title = permission.actionTitle`. |
| Undetermined | `statusDot.layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor`; `statusLabel.stringValue = "Unknown"`, `textColor = .secondaryLabelColor`; `actionButton.title = permission.actionTitle`. |
| Pressed | Not applicable to the row itself: the row is not a control. The action button's own pressed appearance is `NSButton`'s default `.rounded` bezel highlight, unstyled by `PermissionRowView`. |
| Disabled | Not implemented in source: `isEnabled` is never set on `actionButton`, the row, or any subview. The button stays interactive in every status, including before the first `refresh()` completes — pressing it then reports `.undetermined`, `displayedStatus`'s initial value. |
| Focused | Not styled by `PermissionRowView`: any focus ring on the action button when tabbed to is `NSButton`'s own native `NSControl` focus appearance. |
| Loading | Same as "Default (constructed, before first `refresh()`)" above — `PermissionRowView` has one pre-refresh state, shown as `"Checking…"`, not a distinct spinner or progress indicator. |

## Accessibility

- Role/trait: the row itself is a plain `NSView`; source never calls
  `setAccessibilityElement(true)` on it, so — per the inline comment
  explaining the omission — it is deliberately not published as an
  accessibility element. The action button is a standard `NSButton` (role
  button), the only accessibility element `PermissionRowView` contributes
  per row.
- Label requirements: the action button's accessible label comes from its
  own `title` (`permission.actionTitle` or `"Open Settings"`);
  `PermissionRowView` sets no separate accessibility label on the button,
  the row, or the status text.
- Identifier: the action button's accessibility identifier is set to
  `"permission.\(permission.identifierToken).action"` in `buildLayout()`,
  so a UI test can address it per permission; the row and its other
  subviews (icon, title, description, status dot/label) receive no
  accessibility identifier.
- Announce state changes: `apply(status:)` updates `statusLabel.stringValue`
  with a plain assignment; `PermissionRowView.swift` never calls
  `NSAccessibility.post(element:notification:)` (for example `.valueChanged`
  or `.titleChanged`) anywhere in source, so it does not itself announce a
  status change to VoiceOver.
- Minimum tap target: Not applicable in the iOS/touch sense — this is a
  macOS, pointer-driven `NSButton`, and Apple's Human Interface Guidelines'
  44×44pt minimum touch target guidance applies to iOS/iPadOS/tvOS/watchOS,
  not to macOS AppKit controls. The action button's `bezelStyle: .rounded`
  plus `controlSize: .small` sizing is AppKit's own system-determined click
  target, not measured or floored by `PermissionRowView`.
- **contrast**: NEEDS REVIEW: Not implemented in source. Title, description, and status text sit over the card's near-transparent white overlay (3%/6% alpha), which is itself composited over whatever background the host window supplies; whether that combination meets a 4.5:1 (or 3:1 large-text) contrast ratio per `agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages` cannot be determined from source alone, since the effective background color is not fixed, and it needs an accessibility audit against the actual host background.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| permission-row-001 | renders-title-from-permission | Construct with `permission: .accessibility` | `titleLabel` text is exactly `"Accessibility"`. |
| permission-row-002 | renders-title-from-permission | Construct with `permission: .automation(targetBundleID: "com.googlecode.iterm2")` where no app with that bundle id is installed | `titleLabel` text is `"Automation — com.googlecode.iterm2"` (falls back to the raw bundle id). |
| permission-row-003 | renders-description-from-permission | Construct with `permission: .keychain(service: "Claude Code-credentials")` | Description label text reads `Lets this app read the "Claude Code-credentials" item in your keychain directly, instead of asking another tool for it.` |
| permission-row-004 | renders-icon-from-permission | Construct with `permission: .microphone` | The `NSImageView` found among the row's `subviews` resolves the SF Symbol named `mic`, reports a `symbolConfiguration` of point size 16 / weight regular, and has `contentTintColor == .secondaryLabelColor`. |
| permission-row-005 | initial-status-is-checking | Construct a row, do not call `refresh()` | `statusText == "Checking…"`. |
| permission-row-006 | refresh-queries-checker | Stub `checker.status(_:)` to return `.granted`; call `await row.refresh()` | `statusText == "Granted"`. |
| permission-row-007 | cancelled-refresh-does-not-apply | Start `row.refresh()` inside a `Task`, cancel the task before `checker.status(_:)` returns, then `await` the task | `statusText` remains `"Checking…"`. |
| permission-row-008 | granted-status-appearance | `checker.status(_:)` returns `.granted`; `await row.refresh()` | `statusText == "Granted"`; `statusDot.layer?.backgroundColor == NSColor.systemGreen.cgColor`. |
| permission-row-009 | denied-status-appearance | `checker.status(_:)` returns `.denied`; `await row.refresh()` | `statusText == "Not Granted"`; `statusDot.layer?.backgroundColor == NSColor.systemOrange.cgColor`. |
| permission-row-010 | undetermined-status-appearance | `checker.status(_:)` returns `.undetermined`; `await row.refresh()` | `statusText == "Unknown"`; `statusDot.layer?.backgroundColor == NSColor.secondaryLabelColor.cgColor`. |
| permission-row-011 | status-conveyed-by-text-and-color | Refresh a row through all three statuses in turn | For each status, both `statusText` and `statusDot`'s color differ from the other two statuses — no two statuses share the same text or the same color. |
| permission-row-012 | granted-button-title | `permission: .keychain(service:)`; `checker.status(_:)` returns `.granted`; `await row.refresh()` | `actionTitle == "Open Settings"`. |
| permission-row-013 | ungranted-button-title | `permission: .keychain(service: "Claude Code-credentials")`; `checker.status(_:)` returns `.denied`, then separately `.undetermined`; `await row.refresh()` on each | Both rows' `actionTitle == "Allow…"`. |
| permission-row-014 | button-width-fits-widest-title | Construct two rows with different permissions | Both rows' action buttons report the same `frame.width`, equal to the fitting width of the longer of `"Open Settings"` / `"Allow…"`. |
| permission-row-015 | action-carries-displayed-status | `checker.status(_:)` returns `.denied`; `await row.refresh()`; call `row.performActionForTesting()` | `onAction` is invoked with `(permission, .denied)`. |
| permission-row-016 | action-button-has-stable-identifier | Construct with `permission: .location` | The action button's accessibility identifier is `"permission.location.action"`. |
| permission-row-017 | row-has-no-accessibility-identifier | Construct any row | The row `NSView` itself is not an accessibility element and has no accessibility identifier set. |
| permission-row-018 | minimum-row-height | Construct any row and let Auto Layout resolve | Resolved height is `>= 72` points. |
| permission-row-019 | card-appearance | Construct any row | `wantsLayer == true`; `layer?.cornerRadius == 8`; `layer?.borderWidth == 0.5`; `layer?.backgroundColor == NSColor.white.withAlphaComponent(0.03).cgColor`; `layer?.borderColor == NSColor.white.withAlphaComponent(0.06).cgColor`. |
| permission-row-020 | keyboard-activates-action | Construct any row, move keyboard focus to the action button (for example via `makeFirstResponder`), then perform its key equivalent (Space/Return) | `onAction` is invoked the same way it is by `performActionForTesting()` or a mouse click, since `actionButton` is an unmodified `NSButton`. |
| permission-row-021 | pre-refresh-action-enabled | Construct a row, do not call `refresh()`, then call `row.performActionForTesting()` | `actionButton.isEnabled == true` throughout, and `onAction` is invoked with `(permission, .undetermined)`. |

## Edge Cases

- **Null/empty input** (MUST): `.automation(targetBundleID: "")` —
  `NSWorkspace.urlForApplication(withBundleIdentifier: "")` returns `nil`
  for the empty string, so `applicationName(for:)`'s guard fails and it
  falls back to returning the bundle id string itself (here, empty). The
  title MUST render as `"Automation — "` and the Automation sentence in the
  description MUST render with an empty target name, rather than crashing.
  Traced to `applicationName(for:)`'s guard-let/return-bundleID fallback.
  `.keychain(service: "")` takes a different path: `rowTitle(for:)` only
  special-cases `.automation`, so the title MUST still render as plain
  `"Keychain"` (`permission.displayName`), unaffected by the empty service;
  the description MUST render as the literal sentence with an empty quoted
  service name (`Lets this app read the "" item in your keychain directly,
  instead of asking another tool for it.`, from
  `explanation(namingAutomationTarget:)`'s `.keychain` case), rather than
  crashing or omitting the quotes.
- **Boundary values** (MUST): an unusually long `explanation` string MUST
  wrap across multiple lines in `descLabel` (a `wrappingLabelWithString:`
  field with no line limit set), and the row MUST grow taller than the 72pt
  floor to fit it, since `heightAnchor` is a `greaterThanOrEqualToConstant`,
  not a fixed height.
- **Concurrent access** (SHOULD): two overlapping calls to `refresh()` on
  the same row, neither cancelling the other — the view performs no
  internal serialization of overlapping refreshes, so which call's
  `checker.status(permission)` await resolves last, and therefore which
  result the displayed state ends up showing, is left undefined by
  `PermissionRowView` itself; each `apply(status:)` call simply overwrites
  whatever the previous one set. Coordinating that ordering SHOULD be the
  caller's responsibility (as `PermissionsPanelView` does with its own
  single `refreshTask`), not `PermissionRowView`'s.
- **Error states**: Not applicable — `PermissionChecking.status(_:)` is
  declared non-throwing and returns a `PermissionStatus` directly;
  `.undetermined` already exists to mean "can't currently tell" (for
  example, an Automation target that isn't running), so there is no
  separate failure/error path for `PermissionRowView` to render beyond the
  three states already specified.
- **Offline/disconnected state**: Not applicable — `PermissionRowView` and
  `PermissionChecking` read only local macOS system authorization state
  (TCC / Apple Events); `PermissionRowView.swift` makes no network call, so
  connectivity has no defined effect on this component.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `permission` | `Permission` | none (required) | Which permission this row displays and acts on; drives the title, icon, description, and accessibility identifier. |
| `checker` | `any PermissionChecking` | none (required) | Supplies the async grant-status read that `refresh()` calls. |
| `onAction` | `(Permission, PermissionStatus) -> Void` | none (required) | Invoked when the action button is pressed, carrying the permission and the status shown at press time. |

## Deep Linking

Not applicable: `PermissionRowView` is an embedded row, not a navigable
destination. `PermissionRowView.swift` defines no URL scheme, route, or
deep-link handling. Opening a permission's System Settings pane
(`Permission.settingsPaneURL`) is decided and performed by whatever consumes
the `onAction` closure, not by this file.

## Localization

None of the strings below are passed through a localization API
(`NSLocalizedString`, `String(localized:)`, or a `.strings`/`.stringsdict`
catalog) anywhere in `PermissionRowView.swift` or `Permission.swift`; every
user-facing string is a hardcoded English `String` literal, or a `switch`
returning literals.

Every string below reaches the UI unlocalized; a port should decide whether
to route them through its own string catalog, since the source gives no
keys to carry over.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded, unlocalized) | `Checking…` | Initial status label text, before the first `refresh()` completes. |
| (none — hardcoded, unlocalized) | `Granted` | Status label text when `checker.status(_:)` returns `.granted`. |
| (none — hardcoded, unlocalized) | `Not Granted` | Status label text when `checker.status(_:)` returns `.denied`. |
| (none — hardcoded, unlocalized) | `Unknown` | Status label text when `checker.status(_:)` returns `.undetermined`. |
| (none — hardcoded, unlocalized) | `Open Settings` | Action button title when granted, or when the permission has a Settings pane and is not yet granted. |
| (none — hardcoded, unlocalized) | `Allow…` | Action button title for a permission with no Settings pane (`.keychain`) and not yet granted. |
| (none — hardcoded, unlocalized) | `Permission.displayName` values, e.g. `Accessibility`, `Notifications`, `Automation`, `Location`, `Microphone`, `Screen Capture`, `Keychain` | Row title, from `Permission.displayName`. |
| (none — hardcoded, unlocalized) | `Permission.explanation(namingAutomationTarget:)` sentences | Row description text. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `PermissionRowView.swift` performs no animation of any kind — every state change (`statusLabel.stringValue =`, `statusDot.layer?.backgroundColor =`, `actionButton.title =`) is an instantaneous property assignment. There is no `animator()` call, `CATransaction`, or `NSAnimationContext` anywhere in source for Reduce Motion to affect. |
| Increase Contrast | `statusDot`, `statusLabel`, and the action button's title color use semantic dynamic colors (`.systemGreen`, `.systemOrange`, `.secondaryLabelColor`) that adjust automatically under Increase Contrast, but the card's fixed `layer?.backgroundColor`/`layer?.borderColor` do not and the component does not respond to Increase Contrast for them. |
| Differentiate Without Color | Grant status is always communicated by `statusDot`'s color together with `statusLabel`'s text (`Granted` / `Not Granted` / `Unknown`) and the action button's title — never by color alone, per `apply(status:)` — so no additional adjustment is required. |


## Feature Flags

Not applicable: `PermissionRowView.swift` contains no feature-flag or
remote-config check; a row is unconditionally built and shown for whatever
`Permission` its caller supplies.

## Analytics

Not applicable: `PermissionRowView.swift` contains no analytics or
event-tracking call of any kind.

## Privacy

- **Data collected**: None collected or persisted by this view; it only
  displays a `PermissionStatus` value handed to it by the injected
  `checker` (`any PermissionChecking`).
- **Storage**: `displayedStatus` is held in an in-memory `private var` for
  the lifetime of the `PermissionRowView` instance only; nothing is written
  to disk by this file.
- **Transmission**: None. `PermissionRowView.swift` makes no network call;
  `checker.status(_:)` reads local macOS authorization state (TCC / Apple
  Events), which is not something `PermissionRowView` itself performs.
- **Retention**: For the lifetime of the view instance; discarded on
  deallocation, with no persistence layer in this file.

## Logging

Not applicable: `PermissionRowView.swift` contains no `os.Logger`,
`os_log`, or `NSLog` call; the component performs no logging of its own.

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
  `NSLayoutConstraint.activate`. There is no UIKit counterpart in this
  codebase; a UIKit port would replace `NSView`/`NSButton`/`NSStackView`
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
