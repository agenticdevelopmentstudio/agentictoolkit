---
id: 4d0c6859-ed34-46ca-bfe4-ca87234ad684
title: ChatView
domain: agentictoolkit://recipes/chat-view
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'macOS AppKit chat view: transcript with day banners/typing indicator, composer, send button, and row selection.'
platforms:
- swift
- macos
tags:
- chat
- messaging
- ui-component
- composer
- transcript
depends-on:
- agentictoolkit://recipes/chat-day-banner-view
- agentictoolkit://recipes/chat-transcript-row-view
- agentictoolkit://recipes/ai-chat-bubble-view
- agentictoolkit://recipes/typing-indicator-view
related: []
references: []
approved-by: ''
approved-date: ''
---

# ChatView

## Overview

`ChatView` is a macOS, AppKit `NSView` subclass (`NSTextFieldDelegate`) that combines a scrollable message transcript — with per-day banners and an animated typing indicator — with a footer holding an optional status line, an optional composer prompt, a text-entry composer field, and a send button. It is driven by an injected `AIChatViewModel`, which publishes the message list and session state; the view coalesces those updates into batched, equality-guarded transcript rebuilds, preserves the reader's scroll position and any messages they have opened out ("expanded") across a rebuild, and — when `isRowSelectionEnabled` is turned on for a merged, multi-conversation feed — supports keyboard-driven row selection, expansion, and navigation back to a row's originating conversation.

## Behavioral Requirements

- **viewmodel-required-at-init**: The component MUST be constructed with an `AIChatViewModel`; there is no parameterless initializer.
- **coder-init-unavailable**: The component MUST NOT support construction from a coder; `init(coder:)` MUST be unavailable at compile time and MUST terminate the process via `fatalError` if invoked.
- **renders-initial-transcript-synchronously**: The component MUST rebuild and render the transcript synchronously during `init`, before the view model's asynchronous bindings deliver their first values, so a view model already holding a conversation draws it on the very first frame.
- **transcript-above-footer**: The component MUST pin the scrollable transcript to the view's top, leading, and trailing edges, and MUST pin a footer to the view's leading, trailing, and bottom edges directly below the transcript, with no gap between them.
- **transcript-minimum-height**: The component MUST constrain the transcript's scroll view to a height of at least 200pt.
- **transcript-explicit-width**: The component MUST NOT let a bubble's measured width become a floor under the window's minimum width; after the window is dragged wider, it MUST still be resizable narrower again (see Design Decisions for how this is achieved).
- **transcript-rebuild-on-width-change**: The component MUST rebuild the transcript whenever the transcript's visible width changes by more than 1pt from the width it was last rebuilt for.
- **transcript-content-insets**: The component MUST inset the transcript's contents 20pt from the top and bottom and 16pt from the leading and trailing edges, with 12pt of spacing between adjacent transcript items.
- **footer-full-width-rows**: The component MUST stretch the status row, the divider, and the input row to the footer's full width.
- **footer-divider**: The component MUST draw a 1pt hairline, filled with the theme's divider color, spanning the footer's full width between the status row and the input row.
- **input-row-insets-and-spacing**: The component MUST inset the input row 14pt top and bottom and 16pt leading and trailing, with 10pt of spacing between the prompt, the composer field, and the send button, narrowed to 6pt between the prompt and the composer field.
- **composer-placeholder**: The component MUST show the placeholder text `Type a message...` in the composer field whenever it is empty, styled in the active theme's body font and placeholder-text color.
- **composer-prompt-optional**: The component MUST show `composerPrompt`'s text in a leading prompt label immediately in front of the composer field when it is non-nil, and MUST hide that label entirely when `composerPrompt` is nil.
- **composer-enabled-by-default**: The component MUST accept input by default (`isComposerEnabled` defaults to `true`).
- **composer-disabled-while-responding**: The component MUST disable the composer field whenever `isComposerEnabled` is `false` or the view model's `state` is `.responding`.
- **send-button-requires-text**: The component MUST additionally require non-empty, whitespace-trimmed composer text before enabling the send button, even while the composer itself is enabled.
- **send-button-glyph**: The component MUST render the send button as a borderless button showing the SF Symbol `arrow.up.circle.fill` at 18pt, regular weight, with an accessibility description of `Send`.
- **send-button-tint-reflects-enablement**: The component MUST tint the send button with the theme's accent color while it is enabled, and MUST clear its tint (falling back to AppKit's own disabled template-image rendering) while it is disabled.
- **return-key-sends**: The component MUST send the composer's trimmed text when the reader presses Return/Enter in the composer field.
- **send-ignored-when-empty**: The component MUST take no action, on either a send-button activation or a Return key press, while the trimmed composer text is empty.
- **send-clears-composer**: The component MUST clear the composer field's text immediately after sending a non-empty message.
- **composer-reevaluated-on-edit**: The component MUST re-evaluate the send button's enabled state every time the composer's text changes.
- **focus-input-api**: The component MUST expose a `focusInput()` method that makes the composer field the window's first responder and reports whether that succeeded.
- **composer-field-exposed-for-tab-order**: The component MUST expose the composer's text field as `composerField` so a host can splice it into its own key-view (Tab) loop.
- **composer-focus-query**: The component MUST expose `isComposerFocused`, true only when the window's first responder is the composer field itself or a descendant of it (its field editor).
- **status-row-hidden-when-nil**: The component MUST hide the status row entirely when `setStatus(_:icon:)` is called with `nil` text.
- **status-row-shows-text-and-tooltip**: The component MUST show the given text as both the status label's string and its tooltip when `setStatus(_:icon:)` is called with non-nil text.
- **status-icon-swap-only-on-change**: The component MUST leave an already-installed status icon view in place, without removing or re-adding it, when `setStatus(_:icon:)` is called again with the same icon view instance.
- **day-banner-per-calendar-day**: The component MUST insert a day-banner view, spanning the transcript's width, immediately before the first message of each calendar day (per `Calendar.current`), and MUST NOT insert one before any later message on the same day.
- **inflight-or-attributed-uses-row**: The component MUST render a message as a transcript row rather than a plain bubble whenever it carries a non-nil `attribution`, or whenever its `delivery` is not `.settled` — including a `.sending` or `.failed` message in an ordinary, unattributed one-to-one chat.
- **user-messages-right-aligned**: The component MUST right-align a settled, unattributed message with role `.user` by placing it after a flexible leading spacer of at least 60pt.
- **notice-messages-centered**: The component MUST center a settled, unattributed message with role `.notice` between two spacers of equal width.
- **assistant-error-left-aligned**: The component MUST leave a settled, unattributed message with role `.assistant` or `.error` at the transcript's natural leading alignment, with no spacer.
- **role-differentiated-by-position**: The component MUST convey a message's role through horizontal position (right for `.user`, left for `.assistant`/`.error`, centered for `.notice`) in addition to whatever color the bubble fill itself uses.
- **plain-bubble-width-cap**: The component MUST cap a plain (non-row) bubble's width at 75% of the transcript's visible width, with a 200pt floor below which the cap does not shrink further (`max(visibleWidth * 0.75, 200)`).
- **row-bubble-width-derivation**: The component MUST derive a transcript row's bubble-width cap from the row's own available width (the transcript's visible width minus 32pt), not from the 75% plain-bubble fraction.
- **plain-bubbles-not-line-limited**: The component MUST NOT apply `bubbleLineLimit` to a plain (non-row) bubble; only a transcript row (an attributed or in-flight message) receives it.
- **typing-indicator-while-responding**: The component MUST append an animated typing indicator to the end of the transcript, and start its animation, whenever the view model's `state` is `.responding`, and MUST NOT show one otherwise.
- **rebuild-skipped-when-inputs-unchanged**: The component MUST skip rebuilding the transcript when the transcript's width, line limit, selection mode, current selection, action set, session state, message list, and bubble style are all unchanged since the last rebuild.
- **rebuild-deferred-during-text-selection**: The component MUST defer a pending transcript rebuild while the reader has a non-empty text selection inside the transcript, and MUST perform it once that selection collapses to a caret or moves elsewhere.
- **rebuild-coalesced-per-tick**: The component MUST coalesce any number of rebuild requests arriving within one run-loop tick into a single rebuild.
- **font-setting-change-forces-rebuild**: The component MUST discard its rebuild-skip cache and force a fresh transcript rebuild whenever the reader's terminal font name or size setting changes.
- **expansion-carried-to-replacement-message**: The component MUST carry an opened-out ("expanded") message's expanded state forward to a still-unsettled message's later, settled replacement that shares its role and whitespace-normalized text, and MUST drop the expanded state for a message that disappears without such a replacement.
- **follow-newest-when-at-bottom**: The component MUST scroll to show the newest message after a rebuild when the reader was within 30pt of the newest message before that rebuild.
- **preserve-scroll-position-otherwise**: The component MUST, when the reader was not within 30pt of the newest message, re-locate the message that was topmost before the rebuild and restore the same visual offset from the top after it.
- **row-selection-opt-in**: The component MUST leave row selection and its keyboard handling inactive unless `isRowSelectionEnabled` is `true`.
- **disabling-selection-clears-it**: The component MUST clear any current row selection the moment `isRowSelectionEnabled` is set to `false`.
- **select-syncs-without-rebuild**: The component MUST apply a selection change made through `select(_:reveal:)` directly to the affected rows' `isSelected` flags, without triggering a full transcript rebuild.
- **select-moves-keyboard-focus**: The component MUST make the chat view itself the window's first responder whenever a selection is made through `select(_:reveal:)`.
- **select-reveal-flag**: The component MUST scroll the selected row into view, from the row's own top edge, when `reveal` is `true` (the default, used for a keyboard move), and MUST NOT scroll when `reveal` is `false` (used for a row already visible under a click).
- **accepts-first-responder-only-when-selectable**: The component MUST report `acceptsFirstResponder` as `true` only while `isRowSelectionEnabled` is `true`.
- **arrow-key-selection**: The component MUST move the selection to the next or previous row in transcript order on the down or up arrow key, MUST select the first row on down (or the last row on up) when nothing is selected, and MUST NOT wrap past either end.
- **return-opens-shift-return-jumps**: When the chat view itself (not the composer field) holds keyboard focus, the component MUST invoke the selected row's "open" action on a plain Return key press, and its "jump to source" action on Shift-Return; **return-key-sends** governs Return while the composer field holds focus instead.
- **letter-shortcuts-unmodified-only**: The component MUST treat the bare letters `c` (open), `g` (jump to source), and `m` (toggle expansion) as row-selection shortcuts only when no Command, Control, or Option modifier is held, and MUST hand the key event to the system otherwise.
- **letter-m-requires-expandable**: The component MUST ignore the `m` shortcut on a row whose message does not exceed the current line limit.
- **keydown-falls-through**: The component MUST forward an unhandled key event — row selection off, or a key that is none of the handled arrow/Return/letter cases — to `super.keyDown(with:)`.
- **toggle-expansion-in-place**: The component MUST toggle a message's expanded state by updating its on-screen row directly, without rebuilding the transcript.
- **bubble-style-uniform**: The component MUST apply a `bubbleStyle` change to every bubble and row in the transcript through a full rebuild.
- **background-fill-toggle**: The component MUST fill the view with the theme's chat-surface color while `drawsBackground` is `true`, and MUST leave it transparent while `drawsBackground` is `false`.
- **accessibility-identifiers**: The component MUST assign the accessibility identifiers `ai-chat.prompt`, `ai-chat.status`, `ai-chat.input`, and `ai-chat.send-button` to the prompt label, status label, composer field, and send button respectively.
- **theme-responsive-controls**: The component MUST re-derive the composer field's font, text, and placeholder colors, the prompt and status labels' fonts and colors, the send button's tint, and the view's own background fill from the active theme palette whenever it changes.

## Appearance

- **Corner radius**: None on the view itself; children (bubbles, the typing indicator) set their own and are out of this component's scope.
- **Padding**: Transcript content: 20pt top/bottom, 16pt leading/trailing (see **transcript-content-insets**). Input row: 14pt top/bottom, 16pt leading/trailing (see **input-row-insets-and-spacing**). Status row: 6pt top/bottom, 16pt leading/trailing.
- **Font**: Composer field and prompt label use the active theme's body font (`palette.font(.body)`); the status label uses the theme's caption font (`palette.font(.caption)`).
- **Background**: The theme's `chatSurface` color fill while `drawsBackground` is `true`; transparent otherwise (see **background-fill-toggle**). Composer field itself has no background fill (`drawsBackground = false`, bordered = false, no focus ring).
- **Foreground/Text**: Composer field text uses `primaryText`; its placeholder uses `placeholderText`. Prompt and status labels use `secondaryText` when the composer is enabled, `placeholderText` when it is disabled.
- **Border**: A 1pt hairline in the theme's `divider` color, spanning the footer's full width, between the status row and the input row (see **footer-divider**). No border on the view itself or on the composer field.
- **Shadow**: None declared anywhere in this source.
- **Min/Max size**: Transcript scroll view has a minimum height of 200pt (see **transcript-minimum-height**); no maximum width or height is declared on the view. The view's own minimum width is deliberately *not* pinned to any bubble's measured width (see Design Decisions).

## States

| State | Appearance change |
|-------|------------------|
| Default | Composer enabled, empty; send button disabled (no text); status row hidden; no typing indicator. |
| Composer disabled (`isComposerEnabled = false` or session `.responding`) | Composer field greyed (AppKit disabled rendering), prompt tint drops to `placeholderText`, send button loses its accent tint. |
| Responding (session `state == .responding`) | Composer disabled as above; an animated typing indicator is appended to the transcript (see **typing-indicator-while-responding**). |
| Row selected (`isRowSelectionEnabled == true`) | The selected `ChatTranscriptRowView` draws a selection frame; the chat view itself becomes the window's first responder. |
| Pressed | Not applicable: the view's own subviews (`NSButton`, `NSTextField`) own their pressed/hover visuals; `ChatView` sets no pressed state of its own. |
| Focused | The composer field can be the window's first responder (`isComposerFocused`); when row selection is on, the chat view itself can be, governing arrow/Return/letter key handling. |
| Loading | See "Responding" above — the typing indicator is this component's only loading affordance. |

## Accessibility

- **Role/trait**: Not applicable — unlike a single-purpose control, `ChatView` sets no accessibility role on itself; it is a container whose subviews (`NSTextField`, `NSButton`, `NSScrollView`) carry AppKit's own default roles.
- **Label requirements**: The prompt label, status label, composer field, and send button carry the accessibility identifiers `ai-chat.prompt`, `ai-chat.status`, `ai-chat.input`, and `ai-chat.send-button` respectively (see **accessibility-identifiers**), and the send button's SF Symbol image carries the accessibility description `Send`. **NEEDS REVIEW: Not implemented in source. Behavior undefined.** The composer field itself has no `setAccessibilityLabel` call and no programmatic association with the prompt label; its only textual cues are an accessibility *identifier* (a UI-test hook, not a spoken label) and a placeholder string, which AppKit does not guarantee VoiceOver treats as the field's accessible name. Settling this needs either an explicit `inputField.setAccessibilityLabel(...)` call in source, or confirmation from a VoiceOver pass over the built app that the placeholder is announced as the field's name.
- **Announce state changes**: The typing indicator's appearance/disappearance and a row's selection change are drawn visually (see States) but no `NSAccessibility.post(element:notification:)` call accompanies either in this source. **NEEDS REVIEW: Not implemented in source. Behavior undefined.** Row selection has a real keyboard path (arrow keys, Return, letters — see **arrow-key-selection**), so this is a genuine gap rather than an inapplicable concern: a VoiceOver user moving the selection with the keyboard has no source-confirmed way to hear which row is now selected. Settling this needs either an `NSAccessibility.post(element:notification: .selectedChildrenChanged)` call in `select(_:reveal:)`, or a VoiceOver-pass confirmation that AppKit's default `NSView` accessibility tree already surfaces the change.
- **Minimum tap target**: Not applicable in the iOS/touch sense — this is a macOS, pointer-driven `NSView`; Apple's 44×44pt minimum applies to touch targets, not to mouse-driven AppKit controls. The send button's own clickable area is whatever `NSButton` derives from its 18pt symbol content plus its default button metrics; no explicit minimum-size constraint is set on it in this source.

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
| chat-view-048 | toggle-expansion-in-place | `m` pressed on an expandable, selected row | That row's `isExpanded` flips without the transcript stack being torn down and rebuilt |
| chat-view-049 | bubble-style-uniform | `bubbleStyle` changed from `.speaker` to `.terminal` with an existing transcript on screen | Every bubble/row in the transcript re-renders in the new style after one rebuild |
| chat-view-050 | background-fill-toggle | `drawsBackground = true`, then `false` | The view's layer background is the theme's chat-surface color, then transparent |
| chat-view-051 | accessibility-identifiers | Any constructed `ChatView` | The four named subviews carry exactly the four specified accessibility identifiers |
| chat-view-052 | theme-responsive-controls | The active theme changes | Composer field colors/font, prompt/status label colors/fonts, send-button tint, and background fill all update without the view being re-created |
| chat-view-054 | letter-shortcuts-unmodified-only | A row selected; `g` pressed plain, then Cmd-G | Plain `g` invokes `onJump`; Cmd-G is not intercepted (handed to the system) |
| chat-view-055 | letter-shortcuts-unmodified-only, letter-m-requires-expandable | A row selected whose message exceeds the line limit; `m` pressed with Option held | The modified `m` is not intercepted as the expansion shortcut (handed to the system); no expansion toggle occurs |

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `AIChatViewModel` | required, no default | The session/state source the transcript is folded from; supplied once, at init |
| `isComposerEnabled` | `Bool` | `true` | Whether the composer accepts input at all; `false` greys the field but keeps it in place |
| `composerPrompt` | `String?` | `nil` | Text drawn in front of the composer field (e.g. a shell prompt); `nil` hides the prompt label entirely |
| `rowActions` | `ChatTranscriptRowView.Actions` | all-`nil` `Actions()` | The open / jump-to-source / toggle-expand / select callbacks wired to merged-feed transcript rows |
| `isRowSelectionEnabled` | `Bool` | `false` | Whether transcript rows can be picked by click or by arrow key |
| `bubbleLineLimit` | `Int?` | `nil` | Lines a transcript row shows before truncating and offering the rest; `nil` shows the whole message. Not applied to plain (non-row) bubbles |
| `bubbleStyle` | `AIChatBubbleView.Style` | `.speaker` | The shape every bubble/row in the transcript is drawn in |
| `drawsBackground` | `Bool` | `true` | Whether the view paints the theme's chat-surface fill behind the transcript |

## Deep Linking

Not applicable: `ChatView` contains no URL scheme or deep-link handling in source. Navigation between conversations, where it exists at all (`rowActions.onJump`), is a caller-supplied closure whose destination is the host's concern, not a route this view resolves itself.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `chat.composer.placeholder` (proposed; source hardcodes the literal with no key) | `Type a message...` | Composer placeholder text shown while the field is empty |
| `chat.send.accessibility` (proposed; source hardcodes the literal with no key) | `Send` | Accessibility description on the send button's SF Symbol image |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Delegated: this view's only motion is the typing indicator, which it starts with `indicator.startAnimating()` while `state == .responding` and stops otherwise. Whether that pulse honors Reduce Motion is `TypingIndicatorView`'s behavior and is specified in agentictoolkit://recipes/typing-indicator-view; this view adds no animation of its own. |
| Increase Contrast | Not applicable in this file: every color comes from the active `SemanticPalette` (`.primaryText`, `.secondaryText`, `.placeholderText`, `.accent`, `.divider`, `.chatSurface`); if Increase Contrast should raise these colors' contrast, that is the palette's responsibility, not this view's. |
| Differentiate Without Color | Supported: a message's role is conveyed by horizontal position — right-aligned for `.user`, left-aligned for `.assistant`/`.error`, centered for `.notice` (see **role-differentiated-by-position**) — in addition to whatever color the bubble fill itself uses, so role remains legible without relying on color alone. |

## Feature Flags

Not applicable: the source contains no feature-flag conditional; `ChatView` is unconditionally constructed and shown by its caller.

## Analytics

Not applicable: the source contains no analytics or event-tracking calls.

## Privacy

- **Data collected**: None beyond what the caller already supplies. `ChatView` holds the `ChatMessage` array handed to it by `AIChatViewModel` and its own transient UI state (`expandedMessageIDs`, `selectedMessageID`, `lastTranscriptWidth`, the cached `rendered` inputs); it originates no data of its own.
- **Storage**: In-memory only, for the lifetime of the `ChatView` instance; nothing in this source persists to disk.
- **Transmission**: None. `ChatView` performs no networking; sending a message delegates entirely to `viewModel.sendMessage(_:)`.
- **Retention**: The view's transient selection/expansion state is discarded when the view is deallocated; message content retention is the view model/session's concern, not this view's.

## Logging

Not applicable: the source contains no logging calls (no `os_log`, `Logger`, or `print` statements) in this file. (`AIChatViewModel`, which this view is constructed with, does conform to `Loggable` elsewhere, but that is outside this source.)

## Platform Notes

- **SwiftUI**: Compose a `VStack` of a `ScrollViewReader`-wrapped `ScrollView` (transcript) over a footer `VStack` (status line, a `Divider()`, and an `HStack` for prompt/`TextField`/send `Button`). Drive the day-banner insertion and role-based alignment (`.frame(maxWidth: ..., alignment: .trailing/.leading)`, or a centered `HStack` with two `Spacer()`s for `.notice`) from a view model computed property rather than from view-layer state, since SwiftUI already diffs its own tree — the equality-guarded rebuild-skip and scroll-anchor bookkeeping this AppKit source hand-rolls are largely what SwiftUI's own diffing and `ScrollViewReader.scrollTo(_:anchor:)` replace. Reproduce row selection with a `List`/`ForEach` selection binding and `.onMoveCommand`/`.onKeyPress` for the arrow/Return/letter shortcuts, and a Reduce-Motion check via `@Environment(\.accessibilityReduceMotion)` before animating the typing indicator (the indicator's own concern, delegated per Accessibility Options; see agentictoolkit://recipes/typing-indicator-view).
- **Compose**: Use a `Column` of a `LazyColumn` (transcript, driven by a single `LazyListState` that plays the role of `isAtBottom`/`scrollAnchor`) over a footer `Column` (status `Text`, a `HorizontalDivider`, and a `Row` for prompt/`TextField`/send `IconButton`). Alignment by role maps to `Arrangement.End`/`Arrangement.Start`/`Arrangement.Center` on each message's row. Coalesce transcript updates the way this source's equality-guarded rebuild-skip does, using `derivedStateOf` or a `distinctUntilChanged()` flow operator, so a merged feed's frequent polling does not force a recomposition (and a blink) on every unchanged emission. `LocalAccessibilityManager` has no reduce-motion property of its own; read the system animator duration scale (`Settings.Global.ANIMATOR_DURATION_SCALE`) or an app-level reduce-motion setting before starting the typing indicator's pulse.
- **React/Web**: Render a flex column: a scrollable transcript `<div>` (tracking its own "at bottom" scroll-distance threshold, mirroring the 30pt constant) over a footer containing a status line, an `<hr>`-style divider, and a composer row (prompt span, `<input>`, send `<button>`). Role alignment maps to `justify-content: flex-end/flex-start/center` per message row. Implement the "defer rebuild while the reader is selecting text" rule with the `Selection` API (`document.getSelection()`) guarding a re-render, and gate the typing indicator's CSS animation behind `@media (prefers-reduced-motion: reduce)` — mirroring how `TypingIndicatorView` itself should honor Reduce Motion (see agentictoolkit://recipes/typing-indicator-view), not a gap in this view's own behavior.
- **AppKit / UIKit**: Source: `packages/apple/AgenticToolkit/macOS/Features/AIChatWindow/ChatView.swift`. Implemented as a `final` `NSView` subclass (no explicit `@MainActor`) composing an `NSScrollView`/`NSStackView` transcript with an `NSStackView` footer, using `NSTextFieldDelegate` for the composer and manual `keyDown(with:)` handling for row navigation — see Design Decisions for why the transcript's width is set as an explicit constant rather than an equality constraint. This file is macOS-only (`NSView`, `NSTextField`, `NSScrollView`); an iOS port has no direct equivalent here and would need its own composition of `UIScrollView`/`UIStackView`, `UITextField`/`UITextView`, and `UIKeyCommand`-based row navigation, plus its own Reduce-Motion check (`UIAccessibility.isReduceMotionEnabled`).
- **WinUI 3**: Compose a root `Grid` with two `RowDefinition`s (`*` for the transcript, `Auto` for the footer). The transcript is a `ScrollViewer` wrapping an `ItemsRepeater` (or `ListView` with `SelectionMode="Single"` if row selection is wanted, giving `arrow-key-selection` and `return-opens-shift-return-jumps` almost for free via `ListView`'s own keyboard handling) bound to the message collection, with a `DataTemplateSelector` choosing a plain bubble template vs. a "feed row" template per **inflight-or-attributed-uses-row**, and a day-banner header inserted via `CollectionViewSource.IsSourceGrouped="True"` grouped by calendar day (WinUI's native analogue of **day-banner-per-calendar-day**, replacing this source's manual per-message day-boundary tracking). Role alignment maps to `HorizontalAlignment="Right"/"Left"/"Center"` on each item's container, mirroring **role-differentiated-by-position**. The footer is a `StackPanel` with a status `TextBlock`, a 1px `Border`/`Rectangle` filled with a theme brush (thin, theme-brush-bound, mirroring **footer-divider** — WinUI 3 has no built-in `Divider` control), and a `Grid` composer row (prompt `TextBlock`, a `TextBox` with `PlaceholderText="Type a message..."`, and an `AppBarButton`/`Button` with a `FontIcon` glyph for send, `IsEnabled` bound to `!string.IsNullOrWhiteSpace(ComposerText)` for **send-button-requires-text**). Bind `TextBox.KeyDown` to submit on `VirtualKey.Enter` (**return-key-sends**) without `Shift` held. Drive the "follow newest vs. preserve scroll position" behavior with `ScrollViewer.ViewChanging`/`ChangeView(...)` rather than this source's manual anchor-message bookkeeping — WinUI's `ItemsRepeater`/`ScrollViewer` combination exposes bring-into-view APIs (`UIElement.StartBringIntoView`) that cover **follow-newest-when-at-bottom** and **preserve-scroll-position-otherwise** without hand-rolled offset math. For the typing indicator, use a `Storyboard` on three `Ellipse`s gated by `UISettings.AnimationsEnabled` or the app's own "reduce motion" setting — mirroring how `TypingIndicatorView` itself should honor Reduce Motion (see agentictoolkit://recipes/typing-indicator-view), not a gap in this view's own behavior. Bind all colors (accent, divider, primary/secondary/placeholder text, chat surface) to `ThemeResource`s in a resource dictionary that mirrors this source's `ThemeRole` cases, updated on the app's theme-changed event, matching **theme-responsive-controls**.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [semantic-markup](agenticdevelopercookbook://compliance/accessibility#semantic-markup) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [locale-aware-formatting](agenticdevelopercookbook://compliance/internationalization#locale-aware-formatting) | passed | Internationalization |
| [unicode-support](agenticdevelopercookbook://compliance/internationalization#unicode-support) | passed | Internationalization |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [text-expansion-tolerance](agenticdevelopercookbook://compliance/internationalization#text-expansion-tolerance) | partial | Internationalization |
| [rtl-layout-support](agenticdevelopercookbook://compliance/internationalization#rtl-layout-support) | passed | Internationalization |
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | passed | Platform Compliance |

Statuses rest on: the accessibility identifiers present throughout but the two source-confirmed gaps noted under Accessibility — no explicit label on the composer field and no assistive-technology announcement of a row-selection change (screen-reader-support, semantic-markup); every color being resolved from the active `SemanticPalette`, which this source neither defines nor can verify for contrast or Dynamic Type scaling (contrast-ratio, dynamic-type-support); the day banner's date text and the message timestamps deferring to `Calendar`/formatter machinery outside this file, which is locale-aware by construction (locale-aware-formatting); message text flowing through `NSTextField`/the bubble views without special-casing, so arbitrary Unicode renders normally (unicode-support); two literal, unlocalized English strings hardcoded in this file — the composer placeholder `"Type a message..."` and the send button's accessibility description `"Send"` — with no string-catalog key for either (no-hardcoded-strings); the status label's single-line, truncating configuration (`lineBreakMode = .byTruncatingTail`) tolerating overflow gracefully, while the prompt label's required compression-resistance priority could push a very long localized prompt into crowding the composer field instead of wrapping or truncating (text-expansion-tolerance); the layout using `leadingAnchor`/`trailingAnchor` throughout rather than fixed left/right anchors (rtl-layout-support); and the `observeTheme` registrations on every color-bearing subview plus the view's own background fill, all re-applied on every theme change (platform-theming).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: recast the plain-bubble floor and failed-session-state behavior as pending Design Decisions instead of MUSTs; rephrased transcript-explicit-width as observable resize behavior; stated the 200pt floor in plain-bubble-width-cap; filled depends-on with the composed child recipes; trimmed the summary; clarified Return's composer-vs-selection ambiguity; added modifier-guard test vectors for `g` and modified `m`; corrected WinUI 3 (`Divider`, `SystemAnimationsAreEnabled`) and Compose (`LocalAccessibilityManager`) platform-note inaccuracies; removed internal-symbol leakage from the SwiftUI, Compose, and WinUI 3 notes; reconciled the Reduce Motion cross-references with the delegated status in Accessibility Options; and proposed localization keys |
