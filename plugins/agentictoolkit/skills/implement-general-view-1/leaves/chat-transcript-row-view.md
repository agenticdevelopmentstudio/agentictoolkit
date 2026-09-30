<!-- leaf: implement-general-view-1/chat-transcript-row-view · source: chat-transcript-row-view.md -->

**Rules** (cite as `implement-general-view-1/chat-transcript-row-view#<slug>`):

- `renders-header-line` MUST
- `shows-icon-only-with-attribution` MUST
- `icon-wired-only-when-jump-provided` MUST
- `jump-invokes-callback` MUST
- `renders-bubble-without-inline-timestamp` MUST
- `renders-own-timestamp` MUST
- `aligns-by-role` MUST
- `reserves-icon-column` MUST
- `caps-bubble-width` MUST
- `select-on-mouse-down` MUST
- `open-on-double-click` MUST
- `single-click-does-not-open` MUST
- `toggle-expand-delegates` MUST
- `bubble-text-selectable` MUST
- `row-is-primary-hit-target` MUST
- `hover-fill-when-pressable` MUST
- `hover-fill-clears-on-exit` MUST
- `pointing-cursor-when-pressable` MUST
- `selection-frame` MUST
- `delivery-sending-shows-indicator` MUST
- `delivery-failed-shows-reason` MUST
- `delivery-settled-no-extra-view` MUST
- `remeasure-failure-label-width` MUST
- `reflect-theme-live` MUST
- `expose-truncation-state` MUST
- `expose-expandable-state` MUST
- `expose-expanded-state` MUST
- `fixed-corner-radius` MUST
- `no-storyboard-init` MUST

# Chat Transcript Row View

## Overview

`ChatTranscriptRowView` (`AgenticToolkit`, AppKit, macOS) is one row of a *merged* transcript — several conversations interleaved on a single timeline, the way a group chat reads. Each row carries a header line (the source application's icon plus the session's breadcrumb trail), an embedded message bubble, and a timestamp; a row whose message is still in flight or failed to deliver additionally shows a typing indicator or a failure reason between the bubble and the timestamp. Both a user's messages and a persona's messages run between the same two margins; who is talking is said by the bubble's fill, by which side the header and timestamp sit on, and by which margin the icon sits against — not by moving the column. The row is rendered only for messages that carry a `ChatMessage.attribution`; an ordinary one-to-one chat uses the plain bubble instead (that decision belongs to the caller, outside this file). The whole row is a click target: a single click reports selection, a double click reports that the row should be opened, and the app icon (when wired) reports that the reader wants to jump to the source conversation.

## Behavioral Requirements

- **renders-header-line**: The component MUST render a header line above the bubble, built from `SessionHeaderView`, showing the session's breadcrumb trail (`attribution.context` and `attribution.name`).
- **shows-icon-only-with-attribution**: The component MUST include the source application's icon in the header only when `message.attribution` is non-nil; a message with no attribution MUST render the header with no icon.
- **icon-wired-only-when-jump-provided**: The component MUST set the app icon's target/action, tooltip, and accessibility label only when `actions.onJump` is non-nil; when `actions.onJump` is nil the icon MUST render with no target and no tooltip.
- **jump-invokes-callback**: Clicking the app icon, when wired, MUST invoke `actions.onJump` with the row's message.
- **renders-bubble-without-inline-timestamp**: The component MUST embed an `AIChatBubbleView` configured with `showsInlineTimestamp: false`, so the bubble never draws its own timestamp.
- **renders-own-timestamp**: The component MUST render the message's timestamp in its own label, on its own line below the bubble (or below the delivery indicator, when one is present).
- **aligns-by-role**: The component MUST align the header, bubble, and timestamp against the trailing edge when `message.role == .user`, and against the leading edge for any other role.
- **reserves-icon-column**: The component MUST reserve an outer margin of 44pt (8pt inset + 28pt icon + 8pt gap) on both sides for the icon column, regardless of which side's icon is actually filled.
- **caps-bubble-width**: The static `maxBubbleWidth(forRowWidth:)` helper MUST return `max(rowWidth - 88, 80)` (the row width minus both 44pt icon columns, floored at 80pt).
- **select-on-mouse-down**: The component MUST invoke `actions.onSelect` with the message on `mouseDown` when `actions.onSelect` is non-nil and the press location is within the row's bounds, and MUST also forward the event to `super.mouseDown` so a container behind the row still observes the press.
- **open-on-double-click**: The component MUST invoke `actions.onOpen` with the message on `mouseUp` when `actions.onOpen` is non-nil, `event.clickCount >= 2`, and the release location is within the row's bounds.
- **single-click-does-not-open**: The component MUST NOT invoke `actions.onOpen` on a `mouseUp` with `event.clickCount < 2`, and MUST instead forward that event to `super.mouseUp`.
- **toggle-expand-delegates**: The component MUST invoke `actions.onToggleExpanded` with the message whenever the embedded bubble's own expand/collapse toggle fires.
- **bubble-text-selectable**: The component MUST configure the embedded bubble with `isTextSelectable: true`.
- **row-is-primary-hit-target**: The component's `hitTest(_:)` MUST return the row itself for any point within its bounds, except a point that hits a descendant of the bubble, or (when `actions.onJump` is non-nil) a descendant of the app icon, in which case it MUST return that descendant; a point outside the row's bounds MUST return nil.
- **hover-fill-when-pressable**: On `mouseEntered`, the component MUST apply a hover fill (the theme's `.selection` color at 18% alpha) only when `actions.onOpen` is non-nil and `window.contentView?.hitTest(point)` — the event's `locationInWindow` converted into the content view — returns the row itself or a descendant of it.
- **hover-fill-clears-on-exit**: On `mouseExited`, the component MUST clear the hover fill unconditionally.
- **pointing-cursor-when-pressable**: `resetCursorRects` MUST add a pointing-hand cursor covering the full bounds when `actions.onOpen` is non-nil, and MUST add no cursor rect otherwise.
- **selection-frame**: Setting `isSelected` to `true` MUST draw a 2pt border in the theme's `.selection` color around the row; setting it to `false` MUST remove the border (width 0, color nil); setting it to its current value MUST be a no-op.
- **delivery-sending-shows-indicator**: When `message.delivery == .sending`, the component MUST insert an animated `TypingIndicatorView` between the bubble and the timestamp and MUST call `startAnimating()` on it.
- **delivery-failed-shows-reason**: When `message.delivery == .failed(reason)`, the component MUST insert a word-wrapping label between the bubble and the timestamp showing `reason`, using the theme's caption font and `.danger` color, and MUST NOT show a typing indicator.
- **delivery-settled-no-extra-view**: When `message.delivery == .settled`, the component MUST insert no view between the bubble and the timestamp, and the timestamp MUST attach directly below the bubble.
- **remeasure-failure-label-width**: The `layout()` override MUST re-set the failure label's `preferredMaxLayoutWidth` to the label's actual frame width, and invalidate its intrinsic content size, whenever the two differ and the frame has a non-zero width.
- **reflect-theme-live**: The component MUST observe active theme/palette changes and re-apply the header's theme, the timestamp's and failure label's font and color, the hover fill, and the selection frame whenever the palette changes.
- **expose-truncation-state**: The component's `isTruncated` property MUST reflect the embedded bubble's own `isTruncated` value.
- **expose-expandable-state**: The component's `isExpandable` property MUST reflect the embedded bubble's own `isExpandable` value.
- **expose-expanded-state**: The component's `isExpanded` property MUST get and set through to the embedded bubble's own `isExpanded` property.
- **fixed-corner-radius**: The row's own layer MUST have an 8pt corner radius, set once at initialization.
- **no-storyboard-init**: The component MUST NOT support `NSCoder`-based initialization; `init?(coder:)` is unavailable and calls `fatalError()`.

## Appearance

- **Corner radius**: 8pt (the row's own `CALayer`, clipping the hover fill and selection border)
- **Padding**: 8pt horizontal inset (`hInset`) from the row's outer edge to the header/bubble/timestamp content edge on the speaker's side; 6pt vertical inset (`vInset`) from the row's top to the header (plus 3pt extra, so 9pt total) and from the row's bottom to the timestamp
- **Font**: Caption font (theme palette `.caption`) for the timestamp and the failure label
- **Background**: Hover fill only — theme `.selection` color at 18% alpha when hovered and pressable; `NSColor.clear` otherwise. The row has no default fill.
- **Foreground/Text**: Timestamp uses the theme's `.timestampText` color; failure label uses the theme's `.danger` color
- **Border**: 2pt solid, theme `.selection` color, drawn only when `isSelected` is `true`; no border otherwise
- **Shadow**: None (not set in source)
- **Min/Max size**: Bubble width capped at `maxBubbleWidth(forRowWidth:)` = `max(rowWidth - 88, 80)`; app icon is a fixed 28×28pt with an 8pt gap to the bubble column

