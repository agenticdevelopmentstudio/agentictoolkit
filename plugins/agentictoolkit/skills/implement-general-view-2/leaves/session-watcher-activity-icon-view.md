<!-- leaf: implement-general-view-2/session-watcher-activity-icon-view · source: session-watcher-activity-icon-view.md -->

**Rules** (cite as `implement-general-view-2/session-watcher-activity-icon-view#<slug>`):

- `fixed-glyph-size` MUST
- `horizontal-compression-resistance` MUST
- `state-based-symbol-selection` MUST
- `idle-visibility-suppression` MUST
- `state-based-tint` MUST
- `pre-theme-tint-default` MUST
- `symbol-layer-distinction` MUST
- `unresolvable-symbol-fallback` MUST
- `in-place-state-update` MUST
- `redundant-update-guard` MUST
- `animation-restart-on-change` MUST
- `waiting-or-summarizing-pulse` MUST
- `working-state-spin` MUST
- `animation-install-idempotence` MUST
- `off-window-animation-removal` MUST
- `window-attach-animation-reinstall` MUST
- `appearance-change-rerender` MUST
- `display-scale-rerender` MUST
- `glyph-bounds-layout` MUST
- `image-accessibility-role` MUST
- `state-based-label-and-tooltip` MUST
- `state-based-accessibility-identifier` MUST
- `programmatic-construction-only` MUST

# SessionWatcherActivityIconView

## Overview

`SessionWatcherActivityIconView`, at
`packages/apple/AgenticToolkit/macOS/Features/SessionWatcher/SessionListWindow/SessionWatcherActivityIconView.swift`,
is a nested type — `SessionWatcher.SessionWatcherActivityIconView` — implemented
as a `final` `NSView` subclass conforming to `Themeable`. It is the single
glyph a session list row shows at the end of its header line to say what that
session is doing right now: chasing arrows while the agent is working, a
pulsing exclamation badge while it is waiting on the user, sparkles while a
summarization is running over the session, or nothing at all while the
session is simply idle. It owns a small, fixed-size (13×13pt) `CALayer`
sublayer that it recolors and animates in place as `update(activity:isSummarizing:)`
is called on every poll of the session list, rather than being torn down and
rebuilt, so a running spin or pulse survives repeated polling without
stuttering.

## Behavioral Requirements

- **fixed-glyph-size**: The component MUST constrain both its width and
  height to a fixed 13pt (`Self.side`), regardless of `activity` or
  `isSummarizing`.
- **horizontal-compression-resistance**: The component MUST set a required
  horizontal content-compression-resistance priority on itself
  (`setContentCompressionResistancePriority(.required, for: .horizontal)`).
- **state-based-symbol-selection**: The component MUST use the `sparkles` SF
  Symbol whenever `isSummarizing` is `true`, regardless of `activity`; and
  otherwise MUST use `arrow.triangle.2.circlepath` for `activity == .working`,
  `circle.fill` for `activity == .idle`, and `exclamationmark.circle.fill`
  for `activity == .waiting`.
- **idle-visibility-suppression**: The component MUST set
  `isHidden = true` only when `activity == .idle` and `isSummarizing ==
  false`, and MUST be visible (`isHidden = false`) for every other
  combination of `activity` and `isSummarizing`. This is the same
  condition under which **state-based-symbol-selection** selects
  `circle.fill`, **state-based-tint** selects the tertiary text color, and
  **state-based-label-and-tooltip** selects `"Idle"`; because the view is
  hidden whenever that combination holds, none of those three idle values
  is ever seen or announced by a user — they exist only so the glyph
  layer and accessibility state are well-defined (and inspectable in
  tests) while hidden, not because anyone perceives them.
- **state-based-tint**: The component MUST tint the glyph with the active
  theme's accent color when `isSummarizing` is `true` or `activity ==
  .working`, with the theme's tertiary text color when `activity == .idle`
  and `isSummarizing` is `false`, and with the theme's warning color when
  `activity == .waiting` and `isSummarizing` is `false`.
- **pre-theme-tint-default**: The component MUST use
  `NSColor.tertiaryLabelColor` as the glyph's tint until `applyTheme(_:)` is
  called for the first time.
- **symbol-layer-distinction**: When recoloring a multi-layer SF Symbol (for
  example `exclamationmark.circle.fill`), the component MUST keep the
  symbol's layers visually distinct from one another after tinting — the
  exclamation mark MUST stay visually distinct from its enclosing circle,
  rather than the tint collapsing every layer into a single flat-colored
  silhouette. See the AppKit / UIKit Platform Notes bullet and Design
  Decisions for the mechanism this source uses to satisfy it.
- **unresolvable-symbol-fallback**: The component MUST set the
  glyph layer's `contents` to `nil` when `NSImage(systemSymbolName:accessibilityDescription:)`
  returns `nil` for the currently selected symbol name.
- **in-place-state-update**: The component MUST update an existing instance's
  displayed state through `update(activity:isSummarizing:)` rather than
  requiring callers to construct a new instance for a state change.
- **redundant-update-guard**: The component MUST return from
  `update(activity:isSummarizing:)` without redrawing, re-describing
  accessibility, or touching any animation when neither `activity` nor
  `isSummarizing` differs from the view's current values.
- **animation-restart-on-change**: The component MUST stop any running
  glyph animation and, only if it is currently in a window, start the
  animation appropriate to the new state, whenever
  `update(activity:isSummarizing:)` is called with a value that actually
  changes `activity` or `isSummarizing`.
- **waiting-or-summarizing-pulse**: The component MUST animate the
  glyph layer's opacity from `1.0` to `0.25` and back (autoreversing) over
  0.7 seconds, repeating indefinitely, whenever `isSummarizing` is `true` or
  `activity == .waiting`.
- **working-state-spin**: The component MUST rotate the glyph layer one full
  turn clockwise on screen (`transform.rotation.z` from `0` to `-2π`) over
  1.1 seconds with a linear timing function, repeating indefinitely, when
  `activity == .working` and `isSummarizing == false`.
- **animation-install-idempotence**: The component MUST NOT add a new
  pulse or rotation animation for a key that already has an animation
  installed on the glyph layer.
- **off-window-animation-removal**: The component MUST remove both the
  rotation and the pulse animation from the glyph layer when the view moves
  to a `nil` window.
- **window-attach-animation-reinstall**: The component MUST re-render
  the glyph and start its state-appropriate animation whenever the view
  moves into a non-`nil` window.
- **appearance-change-rerender**: The component MUST re-render the glyph
  whenever the view's effective appearance changes, so that a dynamic tint
  color resolves against the new appearance.
- **display-scale-rerender**: The component MUST keep the rasterized glyph
  matching the display's current pixel density, re-rendering whenever that
  density changes, defaulting to a 2x density when it cannot otherwise be
  determined. See the AppKit / UIKit Platform Notes bullet for the API this
  source uses to read and react to that density.
- **glyph-bounds-layout**: The component MUST keep the glyph
  sublayer's `bounds` equal to the view's own `bounds` and its `position`
  centered in the view on every layout pass, with no animated transition
  for that resize/reposition. See the AppKit / UIKit Platform Notes bullet
  for the mechanism (disabling implicit layer actions) this source uses to
  suppress that animation.
- **image-accessibility-role**: The component MUST expose itself to
  assistive technology as an accessibility element with the `.image` role.
- **state-based-label-and-tooltip**: The component MUST set both its
  accessibility label and its `toolTip` to `"Working"`, `"Idle"`, `"Waiting
  for you"`, or `"Summarizing"`, selected by the exact same `isSummarizing`/
  `activity` logic as **state-based-symbol-selection**.
- **state-based-accessibility-identifier**: The component MUST set its accessibility
  identifier to `session-panel.activity.summarizing` when `isSummarizing` is
  `true`, or to `session-panel.activity.working` / `session-panel.activity.idle`
  / `session-panel.activity.waiting` otherwise, matching `activity`.
- **programmatic-construction-only**: The component MUST only be
  constructible through its programmatic initializer; it MUST NOT support
  instantiation from a serialized archive (for example, an Interface
  Builder storyboard or nib). See the AppKit / UIKit Platform Notes bullet
  for the API this source uses to enforce that.

## Appearance

- **Corner radius**: None — neither the view's own layer nor the glyph
  sublayer sets a `cornerRadius`.
- **Padding**: None — the glyph layer fills the view's bounds exactly (see
  **glyph-bounds-layout**); there is no internal inset.
- **Font**: Not applicable in the text sense — the component renders an SF
  Symbol image, not text. The symbol is rasterized at `NSImage.SymbolConfiguration(pointSize:
  11, weight: .semibold)`.
- **Background**: None/transparent — the view has `wantsLayer = true` but no
  `backgroundColor` is set on either its own layer or the glyph sublayer.
- **Foreground/Text**: The glyph's tint — the active theme's accent,
  tertiary-text, or warning color (see **state-based-tint**), or
  `NSColor.tertiaryLabelColor` before the first `applyTheme(_:)` call.
- **Border**: None — no `borderWidth`/`borderColor` is set on either layer.
- **Shadow**: None — no shadow-related layer property is set.
- **Min/Max size**: Fixed, not a range — both width and height are pinned to
  exactly 13pt (see **fixed-glyph-size**). The glyph layer's
  `contentsGravity` is `.resizeAspect`, so the rasterized symbol image scales
  to fit that fixed 13×13pt box without distortion.

## Accessibility

- **Role/trait**: `NSAccessibilityRole.image`, set explicitly via
  `setAccessibilityRole(.image)` alongside `setAccessibilityElement(true)` in
  `init`.
- **Label requirements**: Satisfied unconditionally — `describeState()` sets
  the accessibility label to `"Working"`, `"Idle"`, `"Waiting for you"`, or
  `"Summarizing"` (see **state-based-label-and-tooltip**) every time the
  state is established (`init`) or actually changed (`update`), so the
  label never describes a stale state. The same text is mirrored into
  `toolTip`.
- **Announce state changes**: `describeState()` reassigns the accessibility
  label, `toolTip`, and accessibility identifier whenever `activity` or
  `isSummarizing` actually changes, but no
  `NSAccessibility.post(element:notification:)` call (e.g. `.titleChanged` or
  `.valueChanged`) accompanies that reassignment anywhere in the source — the
  change reaches VoiceOver only through AppKit's own default handling of a
  reassigned accessibility label, never through an explicit posted
  notification.
- **Minimum tap target**: Not applicable in the iOS/touch sense — this is a
  macOS, pointer-driven `NSView` with no target/action, gesture recognizer,
  or click handling of any kind in the source; Apple's 44×44pt minimum
  applies to touch targets, not to a static AppKit image view.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The glyph's tint (theme accent/tertiary-text/warning color, or the `tertiaryLabelColor` system fallback) is rasterized as an opaque fill over whatever background sits behind this 13×13pt view — a session row in a list — with no contrast check against that background anywhere in this file; settling it needs a contrast audit of each tint against the session row background across the app's shipped themes.

