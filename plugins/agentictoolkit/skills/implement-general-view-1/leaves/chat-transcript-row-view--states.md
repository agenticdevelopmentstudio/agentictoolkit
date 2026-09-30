<!-- leaf: implement-general-view-1/chat-transcript-row-view--states · source: chat-transcript-row-view.md -->

# Chat Transcript Row View

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
