<!-- leaf: implement-general-view-1/chat-view--edge-cases · source: chat-view.md -->

# ChatView

**Rules** (cite as `implement-general-view-1/chat-view--edge-cases#<slug>`):

- `null-empty-input` MUST — When viewModel.messages is empty, the transcript stack contains only its leading spacer — no day banner, no rows or …
- `null-empty-input-2` MUST — Whitespace-only or empty composer text disables the send button, and both Return and a send-button click are no-ops …
- `boundary-values` MUST — While the transcript's clip width is 0 or less (the view is off-screen or mid-teardown), layout()'s width > 0 guard …
- `boundary-values-2` MUST — "At the bottom" is exactly distanceFromNewest() < 30; a reader exactly 30pt from the newest message counts as *not* at …
- `rapid-message-arrival` MUST — Several deltas to viewModel.messages arriving within one run-loop tick collapse into a single rebuild (see …
- `reader-mid-selection-when-a-message-arrives` SHOULD — The reader keeps their selection, but does not see the new message until they release it (deselect, or click elsewhere) …
- `window-resize-mid-scroll` MUST — A resize wide enough to change the clip width by more than 1pt rebuilds the transcript and reflows bubble widths; if …

## Edge Cases

- **Null/empty input (empty transcript)**: When `viewModel.messages` is empty, the transcript stack contains only its leading spacer — no day banner, no rows or bubbles. MUST.
- **Null/empty input (empty composer text)**: Whitespace-only or empty composer text disables the send button, and both Return and a send-button click are no-ops (see **send-ignored-when-empty**). MUST.
- **Boundary values (zero/negative transcript width)**: While the transcript's clip width is 0 or less (the view is off-screen or mid-teardown), `layout()`'s `width > 0` guard skips both the width-constant update and any rebuild; the transcript keeps whatever width it last had until the width turns positive again. MUST.
- **Boundary values (narrow window, plain-bubble floor)**: The 200pt floor on a plain bubble's max width (`max(scrollWidth * 0.75, 200)`) can exceed the transcript's own available width once that width drops below roughly 267pt; the source applies the floor unconditionally, with no special-casing below that point (see the Design Decision on the plain-bubble floor).
- **Boundary values ("at the bottom" threshold)**: "At the bottom" is exactly `distanceFromNewest() < 30`; a reader exactly 30pt from the newest message counts as *not* at the bottom and takes the anchor-preservation path rather than the follow-newest path. MUST.
- **Concurrent access**: Not applicable in the strict sense — this source carries no explicit `@MainActor` annotation on `ChatView` itself, but as an `NSView` subclass its AppKit-driven entry points (`layout()`, `keyDown(with:)`, the `NSTextFieldDelegate` callbacks) run on the main thread by platform contract, and both Combine subscriptions that trigger rebuilds are explicitly received on the main queue or run loop (`.receive(on: DispatchQueue.main)`, `.receive(on: RunLoop.main)`). Nothing in this source mutates `expandedMessageIDs`, `isRebuilding`, `rendered`, or the transcript stack from any other thread.
- **Error states (session-level failure)**: A view-model `state` of `.failed(ChatError)` produces no distinct UI in this file (see the Design Decision on failed-session-state rendering); the source neither displays the failure's message nor offers a retry from `ChatView` itself.
- **Error states (per-message failure)**: A message with `delivery = .failed(String)` is always routed to the transcript-row path (see **inflight-or-attributed-uses-row**); what that row draws for the failure reason is that row's own concern and is not specified in this source.
- **Offline/disconnected state**: Not applicable — `ChatView` performs no networking of its own; it only reflects whatever `ChatMessage`/`ChatSessionState` values its `AIChatViewModel` publishes. Connectivity handling belongs to the `ChatSession` behind that view model.
- **Rapid message arrival**: Several deltas to `viewModel.messages` arriving within one run-loop tick collapse into a single rebuild (see **rebuild-coalesced-per-tick**); a rebuild already deferred for an active text selection accumulates no further work beyond "rebuild once, the next time the selection clears." MUST.
- **Reader mid-selection when a message arrives**: The reader keeps their selection, but does not see the new message until they release it (deselect, or click elsewhere) — see **rebuild-deferred-during-text-selection** and the corresponding Design Decision. SHOULD — a deliberate trade-off favoring an uninterrupted text selection over immediacy of the newest message.
- **Window resize mid-scroll**: A resize wide enough to change the clip width by more than 1pt rebuilds the transcript and reflows bubble widths; if the reader was not at the bottom when it happened, the anchor-preservation path (see **preserve-scroll-position-otherwise**) keeps the same message on screen through the reflow. MUST.
