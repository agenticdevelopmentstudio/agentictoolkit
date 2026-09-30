<!-- leaf: implement-general-view-2/permission-row-view--part-2 · source: permission-row-view.md -->

# PermissionRowView — continued (part 2)

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

