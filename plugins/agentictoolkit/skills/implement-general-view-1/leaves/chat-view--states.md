<!-- leaf: implement-general-view-1/chat-view--states · source: chat-view.md -->

# ChatView

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
