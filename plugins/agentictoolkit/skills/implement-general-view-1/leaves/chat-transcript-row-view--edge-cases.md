<!-- leaf: implement-general-view-1/chat-transcript-row-view--edge-cases · source: chat-transcript-row-view.md -->

# Chat Transcript Row View

**Rules** (cite as `implement-general-view-1/chat-transcript-row-view--edge-cases#<slug>`):

- `null-empty-attribution` MUST — message.attribution is nil. Expected: the view substitutes an empty attribution (sourceID: "", context: [], name: "", …
- `empty-failure-reason` MUST — message.delivery == .failed(""). Not explicitly branched on in source; the label is created with whatever string is …
- `boundary-row-width-at-or-below-the-floor-threshold` MUST — Row width ≤ 168pt — the point at which rowWidth - 88 no longer exceeds the 80pt floor. Expected: …
- `boundary-exact-168pt-vs-169pt-row-width` MUST — maxBubbleWidth(forRowWidth: 168) returns max(80, 80) = 80 — the floor still applies exactly at this width; …
- `error-states-delivery-failure` MUST — message.delivery == .failed(reason) is the component's one built-in error-state rendering path; it always shows the …
- `double-click-landing-on-the-bubble-vs-the-row-s-own-margin` MUST — A double click on the bubble's text is handled by the bubble's own onDoubleClick (wired only when actions.onOpen != …
- `actions-onopen-and-actions-onselect-both-nil` MUST — Expected: the row shows no hover fill, no pointing-hand cursor, invokes neither callback, but still forwards every …

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
