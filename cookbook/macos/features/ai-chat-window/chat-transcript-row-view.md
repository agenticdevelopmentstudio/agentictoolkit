---
id: 2f1d9160-a055-4aca-8dff-86d39cc0b76a
title: Chat Transcript Row View
domain: agentictoolkit://cookbook/macos/features/ai-chat-window/chat-transcript-row-view
type: ingredient
version: 1.1.3
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: One row of a merged, multi-conversation chat transcript, with a session header
  line, a message bubble, a timestamp, and a delivery indicator.
platforms:
- swift
- macos
tags:
- chat
- messaging
- transcript
depends-on:
- agentictoolkit://cookbook/macos/features/ai-chat-window/ai-chat-bubble-view
- agentictoolkit://cookbook/macos/features/ai-chat-window/typing-indicator-view
related:
- agentictoolkit://cookbook/macos/features/ai-chat-window/ai-chat-bubble-view
- agentictoolkit://cookbook/macos/features/ai-chat-window/typing-indicator-view
- agenticdevelopertoolkit://recipes/transcript
references: []
approved-by: ''
approved-date: ''
---

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

## States

| State | Appearance change |
|-------|------------------|
| Default | No fill, no border; header/bubble/timestamp laid out per role |
| Hovered | Background fills with `.selection` at 18% alpha — only when `actions.onOpen` is set and the row is frontmost under the pointer (see **hover-fill-when-pressable**) |
| Selected | 2pt `.selection`-colored border around the row; no fill change (see **selection-frame**) |
| Sending | An animated `TypingIndicatorView` appears between the bubble and the timestamp (see **delivery-sending-shows-indicator**) |
| Failed | A wrapping caption-font, danger-colored label with the failure reason appears between the bubble and the timestamp (see **delivery-failed-shows-reason**) |
| Pressed | Not applicable: `mouseDown` invokes `actions.onSelect` and forwards to `super`, but applies no visual change of its own; any highlight the reader sees is the Hovered state that was already showing, not a distinct pressed style. |
| Disabled | Not applicable: the source defines no disabled/enabled property or styling for this view; a row that should not respond simply receives `Actions()` with all callbacks nil, which the Hover/Cursor/Select/Open requirements above already handle by inaction. |
| Focused | Not applicable: this view never becomes first responder (no `acceptsFirstResponder` override, no key-view participation); the row's notion of "the keyboard is pointing at me" is `isSelected`, drawn as the Selected state above, not a separate focus ring. |

## Accessibility

- **Role**: The row itself sets no explicit accessibility role or `isAccessibilityElement` value; it is a generic `NSView` container. Its subviews carry their own accessibility: the header (`headerView.setAccessibilityLabel(attribution.headerLine)`, `accessibilityID("chat-row.header")`) and the app icon (`accessibilityID("chat-row.jump")` always; a target, tooltip ("Go to this conversation" or "Go to this conversation in \(appIdentity)"), and accessibility label ("Go to \(attribution.headerLine)") only when `actions.onJump` is non-nil). The bubble's own accessibility is that component's concern — see `agentictoolkit://cookbook/macos/features/ai-chat-window/ai-chat-bubble-view`.
- **Label requirements**: See **icon-wired-only-when-jump-provided** and **renders-header-line** above; both header and (wired) icon carry meaningful labels traceable to `attribution.headerLine`.
- **Announce state changes**: Theme changes repaint live (**reflect-theme-live**); no other state change in this view posts an accessibility notification.
- **Minimum tap target**: The app icon is 28×28pt, short of the 44×44pt Apple default this ingredient's touch-target concern is measured against. The source's own comment explains the choice (see Design Decisions); whether 28pt is acceptable for this control is not something the source settles.
  - **minimum-tap-target**: NEEDS REVIEW: Not implemented in source. Whether the app icon's 28×28pt hit area is an acceptable deviation from the 44×44pt default, given it is a real, always-clickable-when-wired control (not decorative), is a design call the source does not make — `SessionHeaderView` constrains the icon button's width and height to exactly `spec.side` with no additional hit-area inset around the artwork, and the `PointingHandButton`/`InertIconButton` classes it uses have a cursor rect and tracking area that are both just `bounds`, so there is no existing padding technique in this codebase to reuse. Resolve by having the accessibility/design owner confirm whether 28pt is acceptable here or whether the icon's tappable area should be padded to 44×44pt independent of its 28×28pt artwork.
- **Keyboard path for the open gesture**: `open-on-double-click` is reachable only via a two-click mouse gesture; there is no `keyDown` override, no `accessibilityPerformPress`, and no other method in this file by which a keyboard or switch-control user can trigger the same action. The source's own doc comment says selecting a row via `onSelect` "gives the arrow keys, Return and Shift-Return something to act on," and the enclosing container confirms it: `ChatView.swift` (`packages/apple/AgenticToolkit/macOS/Features/AIChatWindow/ChatView.swift`), which owns `Actions.onSelect`/`isSelected` when `isRowSelectionEnabled` is on, overrides `keyDown` and, on Return/Enter (`keyCode` 36 or 76) with a row selected, invokes `rowActions.onOpen?(message)` directly — the same callback this row's own double click invokes — with Shift-Return invoking `onJump` instead. A keyboard-only user does have an equivalent to `open-on-double-click`, supplied by that container rather than by this file, whenever the host wires row selection on.
- **Selection state announcement**: `isSelected` changes the row's visual border but posts no `NSAccessibility` notification and sets no accessibility "selected" trait; a screen reader user navigating the merged transcript by keyboard has no way to hear which row is currently selected, since selection is communicated only by that visual border.
- **Color dependence**: The Hovered state (see States) is communicated by a background fill alone, with no accompanying border or icon change; the Selected state adds a border shape in addition to (rather than instead of) color, so selection is not color-only, but hover is.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| chat-transcript-row-001 | renders-header-line | Row constructed for any message | `SessionHeaderView` is present, showing `attribution.context`/`attribution.name` |
| chat-transcript-row-002 | shows-icon-only-with-attribution | `message.attribution` is nil | Header renders with no app icon |
| chat-transcript-row-003 | shows-icon-only-with-attribution | `message.attribution` is non-nil | Header renders with the app icon sized 28×28pt |
| chat-transcript-row-004 | icon-wired-only-when-jump-provided | `actions.onJump` is nil, attribution present | Icon has no target/action, no tooltip, and default accessibility (only `accessibilityID` set) |
| chat-transcript-row-005 | icon-wired-only-when-jump-provided, jump-invokes-callback | `actions.onJump` is non-nil, `attribution.appIdentity` is "iTerm2" | Icon tooltip reads "Go to this conversation in iTerm2"; accessibility label reads "Go to \(attribution.headerLine)" |
| chat-transcript-row-006 | jump-invokes-callback | User clicks the wired app icon | `actions.onJump` is invoked once with the row's message |
| chat-transcript-row-007 | renders-bubble-without-inline-timestamp | Row constructed | Embedded `AIChatBubbleView` is configured with `showsInlineTimestamp: false` |
| chat-transcript-row-008 | renders-own-timestamp | `message.delivery == .settled` | A timestamp label appears directly below the bubble |
| chat-transcript-row-009 | aligns-by-role | `message.role == .user` | Header, bubble, and timestamp are anchored to the row's trailing edge |
| chat-transcript-row-010 | aligns-by-role | `message.role != .user` | Header, bubble, and timestamp are anchored to the row's leading edge |
| chat-transcript-row-011 | reserves-icon-column, caps-bubble-width | Row width = 400pt | `maxBubbleWidth(forRowWidth: 400)` returns 312 (400 − 88) |
| chat-transcript-row-012 | caps-bubble-width | Row width = 50pt | `maxBubbleWidth(forRowWidth: 50)` returns 80 (the floor, since 50 − 88 is negative) |
| chat-transcript-row-013 | select-on-mouse-down | `actions.onSelect` non-nil; user presses inside the row bounds | `actions.onSelect` is invoked once with the message; `super.mouseDown` also runs |
| chat-transcript-row-014 | select-on-mouse-down | `actions.onSelect` is nil; user presses inside the row bounds | `actions.onSelect` path is skipped; `super.mouseDown` still runs |
| chat-transcript-row-015 | open-on-double-click | `actions.onOpen` non-nil; user double-clicks inside the row bounds | `actions.onOpen` is invoked once with the message |
| chat-transcript-row-016 | single-click-does-not-open | `actions.onOpen` non-nil; user single-clicks (releases with `clickCount == 1`) inside the row bounds | `actions.onOpen` is NOT invoked; the event is forwarded to `super.mouseUp` |
| chat-transcript-row-017 | open-on-double-click | `actions.onOpen` non-nil; user double-clicks, but the release point is outside the row's bounds (dragged off) | `actions.onOpen` is NOT invoked; the event is forwarded to `super.mouseUp` |
| chat-transcript-row-018 | toggle-expand-delegates | User activates the bubble's expand/collapse toggle | `actions.onToggleExpanded` is invoked once with the message |
| chat-transcript-row-019 | bubble-text-selectable | Row constructed | Embedded bubble is configured with `isTextSelectable: true` |
| chat-transcript-row-020 | row-is-primary-hit-target | Point is over plain row background (not bubble, not icon) | `hitTest` returns the row itself |
| chat-transcript-row-021 | row-is-primary-hit-target | Point is over the bubble's text | `hitTest` returns the bubble (or its descendant), not the row |
| chat-transcript-row-022 | row-is-primary-hit-target | `actions.onJump` non-nil; point is over the app icon | `hitTest` returns the icon button, not the row |
| chat-transcript-row-023 | row-is-primary-hit-target | `actions.onJump` is nil; point is over the app icon's frame | `hitTest` returns the row (icon is not treated as interactive when unwired) |
| chat-transcript-row-024 | row-is-primary-hit-target | Point is outside the row's bounds | `hitTest` returns nil |
| chat-transcript-row-025 | hover-fill-when-pressable | `actions.onOpen` non-nil; pointer enters the row and the row is frontmost under it | Background fills with `.selection` at 18% alpha |
| chat-transcript-row-026 | hover-fill-when-pressable | `actions.onOpen` is nil; pointer enters the row | No hover fill is applied |
| chat-transcript-row-027 | hover-fill-when-pressable | `actions.onOpen` non-nil; pointer enters the row but another view (e.g. an opened conversation overlay) is frontmost at that point | No hover fill is applied |
| chat-transcript-row-028 | hover-fill-clears-on-exit | Row is hovered (fill applied); pointer exits | Hover fill is removed |
| chat-transcript-row-029 | pointing-cursor-when-pressable | `actions.onOpen` non-nil | `resetCursorRects` adds a pointing-hand cursor over the full row bounds |
| chat-transcript-row-030 | pointing-cursor-when-pressable | `actions.onOpen` is nil | `resetCursorRects` adds no cursor rect |
| chat-transcript-row-031 | selection-frame | `isSelected` set from `false` to `true` | A 2pt `.selection`-colored border appears around the row |
| chat-transcript-row-032 | selection-frame | `isSelected` set from `true` to `false` | The border is removed (width 0) |
| chat-transcript-row-033 | selection-frame | `isSelected` set to its current value (no change) | No redraw call occurs (the `didSet` guard short-circuits) |
| chat-transcript-row-034 | delivery-sending-shows-indicator | `message.delivery == .sending` | An animated `TypingIndicatorView` appears between the bubble and the timestamp |
| chat-transcript-row-035 | delivery-failed-shows-reason | `message.delivery == .failed("Network error")` | A wrapping label reading "Network error" in caption font, danger color, appears between the bubble and the timestamp; no typing indicator is shown |
| chat-transcript-row-036 | delivery-settled-no-extra-view | `message.delivery == .settled` | No view appears between the bubble and the timestamp; the timestamp attaches directly below the bubble |
| chat-transcript-row-037 | remeasure-failure-label-width | `message.delivery == .failed(<a reason long enough to wrap>)`; the row is narrower than the bubble's original max-width cap | `layout()` re-sets the failure label's `preferredMaxLayoutWidth` to the label's actual frame width and the label re-wraps to the correct number of lines |
| chat-transcript-row-038 | reflect-theme-live | Active theme palette changes while the row is on screen | Header, timestamp color/font, failure label color/font, hover fill, and selection frame all repaint immediately with the new palette's colors |
| chat-transcript-row-039 | expose-truncation-state, expose-expandable-state | Bubble's message exceeds the configured `lineLimit` | Row's `isTruncated` and `isExpandable` both report `true`, matching the bubble's own values |
| chat-transcript-row-040 | expose-expanded-state | Caller sets `row.isExpanded = true` | Embedded bubble's `isExpanded` becomes `true` and shows the full message |
| chat-transcript-row-041 | fixed-corner-radius | Row constructed | `layer.cornerRadius` is 8 |
| chat-transcript-row-042 | no-storyboard-init | Code attempts `ChatTranscriptRowView(coder:)` | Call is unavailable at compile time / `fatalError()` at runtime |
| chat-transcript-row-043 | select-on-mouse-down, open-on-double-click | `actions.onSelect` and `actions.onOpen` both non-nil; user double-clicks inside the row bounds | `actions.onSelect` is invoked on the first `mouseDown` (and again on the second `mouseDown`, per **select-on-mouse-down**), then `actions.onOpen` is invoked once on the second `mouseUp` (`clickCount == 2`) — select fires before open, never the reverse |
| chat-transcript-row-044 | caps-bubble-width | Row width = 168pt | `maxBubbleWidth(forRowWidth: 168)` returns 80 (`max(168 − 88, 80)` = `max(80, 80)`) — the floor first applies at this width |
| chat-transcript-row-045 | caps-bubble-width | Row width = 169pt | `maxBubbleWidth(forRowWidth: 169)` returns 81 (`max(169 − 88, 80)` = `max(81, 80)`) — one point above 168pt, the floor no longer applies |

## Edge Cases

- **Null/empty attribution**: `message.attribution` is nil. Expected: the view substitutes an empty attribution (`sourceID: "", context: [], name: "", iconSymbol: ""`) for internal layout purposes, but renders no icon (see **shows-icon-only-with-attribution**) and an empty breadcrumb trail. Behavior: MUST (chat-transcript-row-002).
- **Empty failure reason**: `message.delivery == .failed("")`. Not explicitly branched on in source; the label is created with whatever string is given, including an empty one, and would render as a blank wrapping label of some minimal height. Behavior: MUST render whatever `reason` string is given, verbatim (see **delivery-failed-shows-reason**); the source does not special-case an empty reason.
- **Boundary: row width at or below the floor threshold**: Row width ≤ 168pt — the point at which `rowWidth - 88` no longer exceeds the 80pt floor. Expected: `maxBubbleWidth(forRowWidth:)` floors at 80pt rather than continuing to shrink or going to zero or negative (see **caps-bubble-width**; chat-transcript-row-012, chat-transcript-row-044). Behavior: MUST.
- **Boundary: exact 168pt vs. 169pt row width**: `maxBubbleWidth(forRowWidth: 168)` returns `max(80, 80)` = 80 — the floor still applies exactly at this width; `maxBubbleWidth(forRowWidth: 169)`, one point wider, returns `max(81, 80)` = 81 — the first width where the floor no longer applies. Behavior: MUST (see chat-transcript-row-044, chat-transcript-row-045).
- **Concurrent access**: Not applicable. `ChatTranscriptRowView` is an `NSView` subclass; all its mutable state (`isHovered`, `isSelected`, the delivery views) is main-thread/main-actor UI state mutated only in response to AppKit event callbacks and the theme observer, which AppKit itself serializes on the main thread. There is no concurrent-write path in this file.
- **Error states — delivery failure**: `message.delivery == .failed(reason)` is the component's one built-in error-state rendering path; it always shows the given reason and never falls back to a generic message or hides the failure (see **delivery-failed-shows-reason**). Behavior: MUST.
- **Offline/disconnected state**: Not applicable. This view performs no networking of its own; it only renders whatever `ChatMessage.delivery` value it is constructed or updated with. Whether that value reflects an offline condition is decided upstream, outside this file.
- **Rapid re-hover during a drag-select**: The mouse enters and exits the row's tracking area in quick succession (e.g., while dragging a text selection across an adjacent bubble). Expected: each `mouseEntered`/`mouseExited` pair independently applies and clears the hover fill per **hover-fill-when-pressable**/**hover-fill-clears-on-exit**; there is no debounce in source, so rapid toggling produces rapid fill toggling.
- **Double click landing on the bubble vs. the row's own margin**: A double click on the bubble's text is handled by the bubble's own `onDoubleClick` (wired only when `actions.onOpen != nil`, selecting a word if not wired for open); a double click on the row's plain margin is handled by this view's `mouseUp` override. Both paths converge on the same `actions.onOpen` callback when it is set. Behavior: MUST route to the same callback from either origin, per **open-on-double-click** and the bubble's own recipe.
- **`actions.onOpen` and `actions.onSelect` both nil**: Expected: the row shows no hover fill, no pointing-hand cursor, invokes neither callback, but still forwards every mouse event to `super` so a container behind the row (e.g. a focus overlay) still observes presses. Behavior: MUST (see **hover-fill-when-pressable**, **pointing-cursor-when-pressable**, **select-on-mouse-down**, **single-click-does-not-open**).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `message` | `ChatMessage` | (required) | The message this row displays; supplies role, attribution, delivery status, and timestamp |
| `maxBubbleWidth` | `CGFloat` | (required) | Upper bound passed to the embedded bubble and to the failure label's wrap width; callers typically derive this per-row via the static `maxBubbleWidth(forRowWidth:)` helper, but the initializer takes it as a plain parameter |
| `actions` | `Actions` | (required) | Bundle of the row's four interaction callbacks: `onOpen`, `onJump`, `onToggleExpanded`, `onSelect` |
| `lineLimit` | `Int?` | `nil` | How many lines of the message the bubble shows before truncating and offering to expand (forwarded to `AIChatBubbleView`) |
| `bubbleStyle` | `AIChatBubbleView.Style` | `.speaker` | Which shape the bubble is drawn in (forwarded to `AIChatBubbleView`; see its own recipe) |
| `isExpanded` | `Bool` | `false` | Whether the row starts out showing the whole message rather than truncated |

## Deep Linking

Not applicable: `ChatTranscriptRowView.swift` contains no URL scheme, route, or navigation-state handling of its own; going anywhere as a result of interacting with the row (opening the conversation, jumping to its source) is entirely the caller's responsibility, expressed through the `Actions` closures.

## Localization

The three user-facing strings in this file are hardcoded English literals with no override option today; the table lists them as built.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a (literal) | "Go to this conversation" | Tooltip on the app icon when `attribution.appIdentity` is empty |
| n/a (literal) | "Go to this conversation in {appIdentity}" | Tooltip on the app icon when `attribution.appIdentity` is non-empty |
| n/a (literal) | "Go to {attribution.headerLine}" | Accessibility label on the app icon, set only when `actions.onJump` is wired |

None of the three literals — the two app-icon tooltips or `setAccessibilityLabel("Go to \(attribution.headerLine)")` (`ChatTranscriptRowView.swift`–`343`) — is routed through `String(localized:)` or `NSLocalizedString`, so none reaches a string catalog.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: this file animates nothing of its own — the hover fill and selection border are set as instantaneous `CALayer` property writes, not `CABasicAnimation`s or `.animator()` proxies. The embedded `TypingIndicatorView`'s own animation is that component's concern; see `agentictoolkit://cookbook/macos/features/ai-chat-window/typing-indicator-view`. |
| Increase Contrast | Not implemented in source: this view sets no independent high-contrast styling. All colors (`.selection`, `.timestampText`, `.danger`) are read from the active `SemanticPalette`; whatever contrast increase that palette provides on request is inherited automatically, and this file does nothing further. |
| Differentiate Without Color | Selection is differentiated by shape (a border), not color alone (see Accessibility, "Color dependence"); hover is differentiated by color alone, with no accompanying shape or icon change — the source provides no alternative cue for hover. |

## Feature Flags

Not applicable: `ChatTranscriptRowView.swift` contains no feature-flag checks; the component is always constructed and always renders the same way for a given `message`/`actions` configuration.

## Analytics

Not applicable: `ChatTranscriptRowView.swift` emits no analytics events. Callers MAY instrument the `Actions` closures (`onOpen`, `onJump`, `onToggleExpanded`, `onSelect`) themselves to track interaction, since every user action already passes through one of them.

## Privacy

- **Data collected**: None. The view holds the `ChatMessage` and its `attribution` it was constructed with, purely to render them; it does not read, copy, or forward that data anywhere beyond drawing it and the caller-supplied `Actions` closures.
- **Storage**: None. All state (`message`, `attribution`, `isHovered`, `isSelected`) is held in memory only, for as long as the `NSView` instance exists.
- **Transmission**: None. This view performs no networking; whatever happens after `onOpen`/`onJump`/`onSelect` fire is the caller's responsibility.
- **Retention**: None beyond the view's own lifetime — the message data is released when the row view is deallocated or replaced.

## Logging

Not applicable: `ChatTranscriptRowView.swift` contains no logging calls (no `os_log`, `Logger`, or debug `print` statements).

## Platform Notes

- **SwiftUI**: Compose a custom `View` mirroring this file's structure: a header (the session breadcrumb + icon, built the same way `SessionHeaderView` is used here), the bubble view, and a `Text` timestamp, stacked in a `VStack` whose `HorizontalAlignment` (`.leading`/`.trailing`) is chosen by `message.role`, exactly as `isFromUser` chooses anchors here. Use `.contentShape(Rectangle())` plus `.onTapGesture(count: 2)` for open and a plain `.onTapGesture` for select on the row's own background (SwiftUI, unlike AppKit's `NSEvent.clickCount`-based `mouseUp`, needs the two gesture recognizers arbitrated explicitly, e.g. with `.simultaneousGesture` or `.exclusively(before:)`), and `.onHover`/`.overlay` for the hover fill and selection border this file draws on its `CALayer`. Compute the bubble's max width from `GeometryReader` the way `maxBubbleWidth(forRowWidth:)` does here.
- **Compose**: Build a `Row`/`Column` composition — a header row (an app icon `Image`, clickable via its own `Modifier.clickable`, plus a breadcrumb `Text`), the bubble composable, and a timestamp `Text` — inside a parent `Box` using `Modifier.combinedClickable(onClick = onSelect, onDoubleClick = onOpen)`, which is Compose's direct equivalent of this file's single-click-select / double-click-open split. Use `Arrangement.End`/`Arrangement.Start` (mirroring `aligns-by-role`) and a `mutableStateOf` for a Compose-desktop hover fill; on Android there is no mouse hover to mirror, so that half of the behavior simply does not arise.
- **React/Web**: Render a flex column (header row, bubble, timestamp) inside a container `div` with `onClick` (select) and `onDoubleClick` (open) handlers — the DOM natively distinguishes single vs. double click the way this file's `NSEvent.clickCount` check does, so no extra arbitration is needed. Use CSS `:hover` for the fill, gated by a class or `data-` attribute mirroring `isPressable` so an unwired row (no `onOpen`) never shows it, and a `.selected` class applying `box-shadow`/`border` instead of `outline` to keep the "shape, not fill" cue this file uses. Compute the bubble's max width from a `ResizeObserver` on the row, mirroring `maxBubbleWidth(forRowWidth:)`.
- **AppKit / UIKit** (source platform): `ChatTranscriptRowView.swift`, an `NSView` subclass — this is a macOS/AppKit-only file with no UIKit counterpart in source. The header line reuses `SessionHeaderView`, the same control the Sessions window and Conversations shelf use, so its accessibility and layout are learned once across all three. Hover and selection are drawn as raw `CALayer` property writes (`backgroundColor`, `borderWidth`/`borderColor`) rather than `NSVisualEffectView` or a highlight subview. `hitTest(_:)` is overridden so the row remains the primary click target everywhere except over the bubble or the (wired) app-icon button, and `mouseUp`'s `event.clickCount` check is what separates single-click-select from double-click-open — a UIKit port has no `clickCount` on `UIView` touch events, so it would need a `UITapGestureRecognizer(numberOfTapsRequired: 2)` for open and a separate single-tap recognizer with `require(toFail:)` against it for select.
- **WinUI 3**: Start from a `UserControl` (or a `DataTemplate` inside a virtualizing `ItemsRepeater`/`ListView`, if the transcript is virtualized) containing a `Grid`: a header `StackPanel` (an `Image` or `PersonPicture` for the app icon, plus a breadcrumb `TextBlock`), the bubble content, and a `TextBlock` for the timestamp. Bind `HorizontalAlignment` between `Right` and `Left` to `message.role`, mirroring `aligns-by-role`. Drive hover and selection through `VisualStateManager` states (`PointerOver`, `Selected`) on the control's `ControlTemplate` rather than manually toggling layer properties — WinUI's built-in template states already express exactly the hover/selected distinction this file hand-codes. WinUI's `Tapped` and `DoubleTapped` events do not carry an AppKit-style `clickCount`; `Tapped` fires before a would-be `DoubleTapped` is recognized, so reconciling single-click-select against double-click-open requires either acting on `Tapped` only after `DoubleTapped`'s recognition window has elapsed, or accepting that select fires once before open also fires — which is in fact what this file itself does: `mouseDown` invokes `onSelect` unconditionally on every press, including the first press of a double click, and only `mouseUp`'s `clickCount >= 2` check decides open, so a double click here also fires select before it fires open (see **select-on-mouse-down**, **open-on-double-click**). The app icon becomes a `Button` (or `HyperlinkButton`) with `AutomationProperties.Name` bound to "Go to {headerLine}", mirroring the AppKit accessibility label, and `ToolTipService.ToolTip` for the hover tooltip. The 2px selection border becomes `BorderThickness="2"` on the template's `Border`, driven by the `Selected` visual state, rather than a manually toggled `CALayer` border.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/AIChatWindow/ChatTranscriptRowView.swift` |

## Design Decisions

**Decision**: The app icon is sized 28×28pt — short of the 44pt the Sessions window gives the identical control, but larger than the 24pt symbol it replaces.
**Rationale**: In the transcript, the icon heads one line of a timeline whose subject is what was said, not the row's whole identity the way it is in the Sessions window; 28pt keeps it recognizable as artwork (a picture to be recognised, not a glyph to be read) without claiming the row.
**Approved: pending**

**Decision**: The app icon's target, tooltip, and accessibility label are set only when `actions.onJump` is non-nil; an unwired icon renders with no target.
**Rationale**: The icon promises a link under the pointer wherever it is hovered; a promise kept by nothing is worse than no promise, so the promise is only made where it is actually kept.
**Approved: pending**

**Decision**: Hover fill and the pointing-hand cursor are gated on `actions.onOpen`, not on `actions.onSelect` or `actions.onJump`.
**Rationale**: They promise that pressing the row itself means something — specifically, that a press opens the conversation — so they track the row's own primary action rather than any closure being present.
**Approved: pending**

**Decision**: Selection is drawn as a 2pt border rather than a background fill.
**Rationale**: The hover fill already means "the mouse is here"; a second fill would leave a reader unable to tell a hovered row from a selected one, and a border leaves the bubble's own color — which encodes who is talking — untouched.
**Approved: pending**

**Decision**: Opening a row requires a double click; a single click is reserved for selection and for starting a text-selection drag inside the bubble.
**Rationale**: A single click is worth more where it already is — selecting text to copy it — and opening a conversation is deliberate enough to be worth two clicks instead of contesting that gesture.
**Approved: pending**

**Decision**: The row is laid out with hand-written `NSLayoutConstraint`s mirrored per role, rather than nested stack views, with the header line as the one exception (it stays a stack).
**Rationale**: The row mirrors about its own centre line, and "the same layout, flipped" is one set of anchors chosen per side, where stack views would need two separate hierarchies; the header line is the shared control used identically in the Sessions window and Conversations shelf, so it keeps its own internal arrangement regardless of which margin the whole line is pinned to.
**Approved: pending**

**Decision**: `showsInlineTimestamp: false` is passed to the embedded bubble, and the row draws its own timestamp label on its own line instead.
**Rationale**: The row's own timestamp is anchored to the same edge as the header's breadcrumb trail — the speaker's column — so it has to be a label this row positions itself; a timestamp the bubble drew inline would be part of the bubble's own shape and could not be pinned independently to that column (see `agentictoolkit://cookbook/macos/features/ai-chat-window/ai-chat-bubble-view`).
**Approved: pending**

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [reduced-motion](agenticdevelopercookbook://compliance/accessibility#reduced-motion) | partial | Accessibility |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |

`touch-target-size` is omitted: this is a pointer-driven macOS surface with no touch input, so the check's 44×44pt-touch/48×48dp-touch grounds do not transfer directly; the 28×28pt app icon's click-target size is instead the open question on minimum-tap-target, tracked under Accessibility above, not a pass/fail against a touch default. `passed` rows rest on the source directly: the row emits no logging at all, so none can leak PII; and the view holds only the caller-supplied `message`/`attribution` in memory purely to render them, collecting and storing nothing further. `partial` rows reflect what this file alone can't settle, or shares with something else: the header and (wired) icon carry real accessibility labels, but the row's own selection state has no accessibility exposure — `isSelected` posts no `NSAccessibility` notification and sets no accessibility "selected" trait (see Accessibility above) — so screen-reader-support is partial rather than passed; `keyboard-navigable` is partial because this file itself has no keyboard path of its own, but `ChatView.swift`, the container that owns row selection, does supply a Return-to-open and Shift-Return-to-jump equivalent when it wires `isRowSelectionEnabled` (see the keyboard-path note under Accessibility above) — a guarantee that holds only when hosted by that container; `reduced-motion` is partial because this view animates nothing of its own, but it is the one that decides to call `startAnimating()` on the embedded `TypingIndicatorView`, whose own reduced-motion compliance is `failed` (see `agentictoolkit://cookbook/macos/features/ai-chat-window/typing-indicator-view`); text sizing and color contrast are both delegated entirely to the active `SemanticPalette`, which this file neither reads for scaling nor independently verifies.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Claude Sonnet 5 | Initial creation from the macOS/AppKit source (ChatTranscriptRowView.swift) |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: corrected the WinUI 3 double-click note and added a select-then-open vector; gave the showsInlineTimestamp decision a real rationale; retargeted the bubble/typing-indicator links to this repo's own recipes and populated depends-on; fixed the bubble-width floor boundary from 88pt to 168pt with new vectors; corrected the user-facing-string count and vector 037's wording; reworded hover-fill-when-pressable to name the actual hit-test check; settled the keyboard-path-for-open accessibility question from ChatView.swift's Return handler and corrected the touch-target open question's false SessionHeaderView-padding claim; reclassified keyboard-navigable and reduced-motion as partial and dropped touch-target-size from Compliance |
| 1.1.1 | 2026-09-23 | Mike Fullerton | Recorded the unlocalized jump-control literals as an open question; replaced proposed localization keys with n/a (literal) |
| 1.1.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
