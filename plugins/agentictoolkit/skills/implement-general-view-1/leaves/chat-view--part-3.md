<!-- leaf: implement-general-view-1/chat-view--part-3 · source: chat-view.md -->

# ChatView — continued (part 3)

**Rules** (cite as `implement-general-view-1/chat-view--part-3#<slug>`):

- `select-syncs-without-rebuild` MUST
- `select-moves-keyboard-focus` MUST
- `select-reveal-flag` MUST
- `accepts-first-responder-only-when-selectable` MUST
- `arrow-key-selection` MUST
- `return-opens-shift-return-jumps` MUST
- `letter-shortcuts-unmodified-only` MUST
- `letter-m-requires-expandable` MUST
- `keydown-falls-through` MUST
- `toggle-expansion-in-place` MUST
- `bubble-style-uniform` MUST
- `background-fill-toggle` MUST
- `accessibility-identifiers` MUST
- `theme-responsive-controls` MUST

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

## Accessibility

- **Role/trait**: Not applicable — unlike a single-purpose control, `ChatView` sets no accessibility role on itself; it is a container whose subviews (`NSTextField`, `NSButton`, `NSScrollView`) carry AppKit's own default roles.
- **Label requirements**: The prompt label, status label, composer field, and send button carry the accessibility identifiers `ai-chat.prompt`, `ai-chat.status`, `ai-chat.input`, and `ai-chat.send-button` respectively (see **accessibility-identifiers**), and the send button's SF Symbol image carries the accessibility description `Send`. The composer field itself has no `setAccessibilityLabel` call and no programmatic association with the prompt label; its only textual cues are an accessibility *identifier* (a UI-test hook, not a spoken label) and a placeholder string, which AppKit does not guarantee VoiceOver treats as the field's accessible name.
- **Announce state changes**: The typing indicator's appearance/disappearance and a row's selection change are drawn visually (see States) but no `NSAccessibility.post(element:notification:)` call accompanies either in this source. Row selection has a real keyboard path (arrow keys, Return, letters — see **arrow-key-selection**): a VoiceOver user moving the selection with the keyboard has no source-confirmed way to hear which row is now selected.
- **Minimum tap target**: Not applicable in the iOS/touch sense — this is a macOS, pointer-driven `NSView`; Apple's 44×44pt minimum applies to touch targets, not to mouse-driven AppKit controls. The send button's own clickable area is whatever `NSButton` derives from its 18pt symbol content plus its default button metrics; no explicit minimum-size constraint is set on it in this source.

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

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a (literal) | `Type a message...` | Composer placeholder text shown while the field is empty |
| n/a (literal) | `Send` | Accessibility description on the send button's SF Symbol image |

Both listed strings are plain `String` literals in source — the composer placeholder `"Type a message..."` (ChatView.swift) and the send image's accessibility description `"Send"` (:292) — and neither is routed through `String(localized:)` or `NSLocalizedString`, so neither reaches a string catalog.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Delegated: this view's only motion is the typing indicator, which it starts with `indicator.startAnimating()` while `state == .responding` and stops otherwise. Whether that pulse honors Reduce Motion is `TypingIndicatorView`'s behavior and is specified in agentictoolkit://recipes/typing-indicator-view; this view adds no animation of its own. |
| Increase Contrast | Not applicable in this file: every color comes from the active `SemanticPalette` (`.primaryText`, `.secondaryText`, `.placeholderText`, `.accent`, `.divider`, `.chatSurface`); if Increase Contrast should raise these colors' contrast, that is the palette's responsibility, not this view's. |
| Differentiate Without Color | Supported: a message's role is conveyed by horizontal position — right-aligned for `.user`, left-aligned for `.assistant`/`.error`, centered for `.notice` (see **role-differentiated-by-position**) — in addition to whatever color the bubble fill itself uses, so role remains legible without relying on color alone. |

