<!-- leaf: implement-general-view-2/permission-row-view · source: permission-row-view.md -->

**Rules** (cite as `implement-general-view-2/permission-row-view#<slug>`):

- `renders-title-from-permission` MUST
- `renders-description-from-permission` MUST
- `renders-icon-from-permission` MUST
- `initial-status-is-checking` MUST
- `refresh-queries-checker` MUST
- `cancelled-refresh-does-not-apply` MUST
- `granted-status-appearance` MUST
- `denied-status-appearance` MUST
- `undetermined-status-appearance` MUST
- `status-conveyed-by-text-and-color` MUST
- `granted-button-title` MUST
- `ungranted-button-title` MUST
- `button-width-fits-widest-title` MUST
- `action-carries-displayed-status` MUST
- `pre-refresh-action-enabled` MUST
- `keyboard-activates-action` MUST
- `test-observable-surface` MUST
- `action-button-has-stable-identifier` MUST
- `row-has-no-accessibility-identifier` MUST
- `minimum-row-height` MUST
- `card-appearance` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `permission` | `Permission` | none (required) | Which permission this row displays and acts on; drives the title, icon, description, and accessibility identifier. |
| `checker` | `any PermissionChecking` | none (required) | Supplies the async grant-status read that `refresh()` calls. |
| `onAction` | `(Permission, PermissionStatus) -> Void` | none (required) | Invoked when the action button is pressed, carrying the permission and the status shown at press time. |

