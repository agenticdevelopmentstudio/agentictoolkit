<!-- leaf: implement-general-view-1/chat-transcript-row-view--test-vectors · source: chat-transcript-row-view.md -->

# Chat Transcript Row View

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
