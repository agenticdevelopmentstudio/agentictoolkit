<!-- leaf: implement-general-view-1/chat-view--test-vectors · source: chat-view.md -->

# ChatView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| chat-view-001 | viewmodel-required-at-init, renders-initial-transcript-synchronously | A view model already holding 3 messages, used to construct `ChatView` | The view's first drawn frame already shows 3 rows/bubbles, not an empty transcript |
| chat-view-002 | coder-init-unavailable | Attempt `ChatView(coder:)` (e.g. storyboard/XIB unarchiving) | Compile error (`@available(*, unavailable)`); if reached at runtime regardless, the process terminates via `fatalError` |
| chat-view-003 | transcript-above-footer, transcript-minimum-height | View given a 400×400 frame | The transcript scroll view's frame sits directly above the footer's frame with no gap; its height is ≥ 200pt |
| chat-view-004 | transcript-explicit-width, transcript-rebuild-on-width-change | View resized from 400pt to 600pt wide | The transcript rebuilds and bubbles reflow to the new proportional width; the window remains resizable narrower afterward (no bubble's measured width raises the window's minimum) |
| chat-view-005 | transcript-content-insets | A transcript with at least one item | The first/last item sits 20pt from the scroll content's top/bottom and 16pt from its leading/trailing edges; adjacent items are 12pt apart |
| chat-view-006 | footer-full-width-rows, footer-divider | Any view width | The status row, divider, and input row each span the footer's full width; the divider is a 1pt-tall hairline in the theme's divider color |
| chat-view-007 | input-row-insets-and-spacing | Any view | The input row's content insets and inter-item spacing match the specified point values |
| chat-view-008 | composer-placeholder | Empty composer field, default theme | The field shows the literal `Type a message...` in the theme's body font and placeholder color |
| chat-view-009 | composer-prompt-optional | `composerPrompt = "$"`, then `composerPrompt = nil` | The prompt label shows `$` and is visible; then it is hidden |
| chat-view-010 | composer-enabled-by-default | A freshly constructed `ChatView` | `isComposerEnabled == true`; the composer field is enabled (given `state != .responding`) |
| chat-view-011 | composer-disabled-while-responding | `isComposerEnabled = true`, `state = .responding` | The composer field's `isEnabled == false` |
| chat-view-012 | send-button-requires-text | Composer enabled; field text empty, then `"hi"` | Send button disabled while empty; enabled once `"hi"` is entered |
| chat-view-013 | send-button-glyph | Any state | The send button shows `arrow.up.circle.fill` at 18pt regular weight, borderless, with accessibility description `Send` |
| chat-view-014 | send-button-tint-reflects-enablement | Send button enabled, then disabled | `contentTintColor` equals the theme's accent color when enabled; `nil` when disabled |
| chat-view-015 | return-key-sends, send-clears-composer | Composer text `"hello"`, Return pressed | `viewModel.sendMessage("hello")` is invoked and the field is emptied immediately afterward |
| chat-view-016 | send-ignored-when-empty | Composer text is only whitespace; send button activated (or Return pressed) | `sendMessage` is not invoked; the field is left unchanged |
| chat-view-017 | composer-reevaluated-on-edit | A character typed into an empty, enabled composer | The send button transitions from disabled to enabled within the same edit |
| chat-view-018 | focus-input-api | View attached to a window; `focusInput()` called | Returns `true`; the composer field becomes `window.firstResponder` |
| chat-view-019 | composer-field-exposed-for-tab-order, composer-focus-query | `composerField` read; composer field made first responder | `composerField` is the actual `NSTextField` instance; `isComposerFocused == true` |
| chat-view-020 | status-row-hidden-when-nil | `setStatus(nil, icon: nil)` | Status row's `isHidden == true` |
| chat-view-021 | status-row-shows-text-and-tooltip | `setStatus("Thinking…", icon: nil)` | Status row visible; label text and tooltip both equal `Thinking…` |
| chat-view-022 | status-icon-swap-only-on-change | `setStatus("A", icon: spinner)` then `setStatus("B", icon: spinner)` (same instance) | `spinner` is not removed/re-added between the two calls |
| chat-view-023 | day-banner-per-calendar-day | Messages timestamped 2026-06-03 09:00, 2026-06-03 18:00, 2026-06-04 09:00 | Exactly two day banners, immediately before the first and third messages |
| chat-view-024 | inflight-or-attributed-uses-row | An unattributed message with `delivery = .sending` | Rendered via the transcript-row path, not the plain-bubble path |
| chat-view-025 | user-messages-right-aligned | A settled, unattributed `.user` message | Preceded by a ≥60pt flexible spacer that pushes the bubble to the trailing edge |
| chat-view-026 | notice-messages-centered | A settled `.notice` message | Flanked by two equal-width spacers, centering the bubble |
| chat-view-027 | assistant-error-left-aligned, role-differentiated-by-position | One settled `.assistant` and one settled `.error` message, both unattributed | Both sit at the stack's natural leading edge, distinguishable from a `.user` message by position alone |
| chat-view-028 | plain-bubble-width-cap | Transcript width 800pt, a long plain assistant message | The bubble's max width is capped at 600pt (800 × 0.75) |
| chat-view-029 | row-bubble-width-derivation | Transcript width 800pt, an attributed message | The row's bubble-width cap is computed from (800 − 32), not from 800 × 0.75 |
| chat-view-030 | plain-bubbles-not-line-limited | `bubbleLineLimit = 3`; one plain settled message and one attributed message, both 10 lines long | The plain bubble shows all 10 lines; the attributed row truncates to 3 with an expand affordance |
| chat-view-031 | typing-indicator-while-responding | `state` transitions to `.responding`, then back to `.ready` | A typing indicator appears and animates while `.responding`; it is absent once `.ready` |
| chat-view-032 | rebuild-skipped-when-inputs-unchanged | The render trigger fires twice with no change to width/messages/state/etc. | The transcript stack's arranged subviews are not torn down and rebuilt the second time |
| chat-view-033 | rebuild-deferred-during-text-selection | A non-empty selection exists in a transcript text view; a new message arrives | The transcript does not rebuild until the selection clears, then rebuilds once it does |
| chat-view-034 | rebuild-coalesced-per-tick | Five rapid delta updates to `viewModel.messages` within one run-loop tick | Exactly one transcript rebuild occurs |
| chat-view-035 | font-setting-change-forces-rebuild | The terminal font size setting changes while every other transcript input is unchanged | The transcript rebuilds anyway (bubbles re-measure at the new font) |
| chat-view-036 | expansion-carried-to-replacement-message | Reader expands an in-flight `.sending` message; it later arrives back `.settled` with the same role and whitespace-normalized text under a new id | The new row starts expanded; if no matching replacement arrives, the expansion is simply dropped |
| chat-view-037 | follow-newest-when-at-bottom | Reader scrolled within 30pt of the newest message; a new message arrives | After the rebuild, the transcript is scrolled to show the newest message |
| chat-view-038 | preserve-scroll-position-otherwise | Reader scrolled more than 30pt from the newest message, reading an older one; a new message arrives | After the rebuild, the same message the reader was reading sits at the same on-screen offset |
| chat-view-039 | row-selection-opt-in, disabling-selection-clears-it | `isRowSelectionEnabled = false`, down arrow pressed; then enabled, a row selected, then disabled again | No selection change in the first case; selection is cleared when disabled in the second |
| chat-view-040 | select-syncs-without-rebuild, select-moves-keyboard-focus | `select(id:)` called on a visible row | Only that row's `isSelected` becomes `true` (others `false`) with no transcript teardown; the window's first responder becomes the chat view |
| chat-view-041 | select-reveal-flag | `select(id, reveal: true)` on a row below the fold, vs. `select(id, reveal: false)` on the same row | The first call scrolls the row into view from its top edge; the second does not scroll |
| chat-view-042 | accepts-first-responder-only-when-selectable | `isRowSelectionEnabled` false, then true | `acceptsFirstResponder` is `false`, then `true` |
| chat-view-043 | arrow-key-selection | Three selectable rows, nothing selected; down, down, down (at the last row) | Selection moves row 1 → row 2 → row 3 → stays at row 3 (no wrap) |
| chat-view-044 | return-opens-shift-return-jumps | A row selected, `rowActions.onOpen`/`onJump` wired; Return pressed, then Shift-Return | `onOpen` fires first; `onJump` fires second |
| chat-view-045 | letter-shortcuts-unmodified-only | A row selected; `c` pressed plain, then Cmd-C | Plain `c` invokes `onOpen`; Cmd-C is not intercepted (handed to the system) |
| chat-view-046 | letter-m-requires-expandable | A selected row whose message fits within the line limit; `m` pressed | No expansion toggle occurs (`isExpandable == false` for that row) |
| chat-view-047 | keydown-falls-through | `isRowSelectionEnabled = false`; down arrow pressed | The event is passed to `super.keyDown(with:)` rather than consumed |
