<!-- leaf: implement-general-view-1/chat-view--part-5 · source: chat-view.md -->

# ChatView — continued (part 5)

## Design Decisions

**Decision**: The transcript content's width is set as an explicit constant on every layout pass, rather than as an equality constraint to the scroll view's clip width.
**Rationale**: A bubble bakes the width it was measured at into a constraint of its own; through an equality constraint those baked widths become a width the scroll view — and, transitively, the window — must be. `NSWindow` derives its minimum size from the content's fitting size, computed from constraints of any priority, so the window could be dragged wider and never narrower again. Setting the constant explicitly (`transcriptWidthConstraint.constant = width`, per the class's own doc comment) breaks that relation instead of trying to lower its priority.
**Approved: pending**

**Decision**: The reader's scroll position is preserved across a full rebuild by remembering the topmost visible message's id and its offset from the viewport's top, rather than remembering a raw scroll offset.
**Rationale**: A rebuild empties and refills the entire transcript stack, so a raw offset would land on whatever row now happens to occupy that position. Anchoring to a message id (`scrollAnchor()`/`restore(_:)`) keeps the reader on the same message they were reading regardless of how many rows above it changed height.
**Approved: pending**

**Decision**: A transcript rebuild is deferred while the reader has an active, non-empty text selection inside it, and resumes once the selection collapses.
**Rationale**: A rebuild discards every row's text view along with any selection or pending copy inside it. A watched feed polls every few seconds and would otherwise interrupt a reader mid-selection; deferring the rebuild, and re-running it the moment the selection collapses (via a `didChangeSelectionNotification` observer), avoids that at the cost of the reader not seeing new messages until they let go.
**Approved: pending**

**Decision**: A message with a non-`.settled` delivery is always rendered as a transcript row, even in an ordinary one-to-one chat with no attribution — the row is built against a synthesized, empty `Attribution` in that case.
**Rationale**: Only the transcript row draws a message's delivery status (sending / failed); a plain bubble has no such affordance. Routing on delivery as well as attribution means an in-flight or failed message always gets that treatment, regardless of whether the chat it is in ever produces attributed rows otherwise.
**Approved: pending**

**Decision**: `bubbleLineLimit` is threaded through to transcript rows only, never to the plain bubbles used in an ordinary one-to-one chat.
**Rationale**: Line-limiting with an "open the rest" affordance addresses a merged-feed problem — one long reply among many short ones. This source constructs plain bubbles with no line limit at all, so a one-to-one chat's messages are never truncated regardless of `bubbleLineLimit`'s value.
**Approved: pending**

**Decision**: Expansion state is tracked by message id on the view, and carried forward across a rebuild by matching role plus whitespace-normalized text, rather than by id alone.
**Rationale**: Per the class's own doc comment on `expandedMessageIDs`, a watched feed rebuilds its whole transcript every few seconds, and a message written under one id can arrive back under a different one once it settles. Matching on normalized text is what lets a message the reader opened out stay open through that id change; a message that disappears without a matching replacement simply loses its expanded state.
**Approved: pending**

**Decision**: A plain bubble's width cap floors at 200pt (`max(scrollWidth * 0.75, 200)`) with no special-casing once the transcript's own available width drops below that floor (roughly 267pt of scroll width).
**Rationale**: Not documented in source beyond the formula itself; below that width the floor can make a bubble's cap exceed the space actually available, which reads as a narrow-window bug rather than an intended minimum. Left open rather than assumed: whether the floor should shrink to fit, or the source is fine leaving it as is, is not decided here.
**Approved: pending**

**Decision**: A `.failed` session state renders no distinct banner, alert, or composer state of its own; the composer's enablement is governed only by `isComposerEnabled` and whether `state == .responding`, exactly as in `.ready`.
**Rationale**: The source conditions composer enablement solely on `.responding` (`applyComposerEnablement`); no other branch in this file reads `.failed`. Whether a failure state should surface its own affordance (a banner, a retry action) is left open rather than assumed here.
**Approved: pending**
