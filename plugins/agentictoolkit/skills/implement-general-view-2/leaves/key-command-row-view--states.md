<!-- leaf: implement-general-view-2/key-command-row-view--states · source: key-command-row-view.md -->

# KeyCommandRowView

## States

| State | Appearance change |
|-------|------------------|
| Default | The row shows the command's current binding at rest: the capture field displays the bound shortcut (or the "Click to record" placeholder when unbound), the toggle reflects the binding's enabled flag, the confirm/cancel pair is hidden, and the readout row is hidden. |
| Pressed | Not applicable to `KeyCommandRowView` itself: the row draws no pressable control of its own. The toggle's native press feedback, the capture field's click-to-focus, and the confirm/cancel pair's button-press feedback all belong to those subcomponents, not to this file. |
| Disabled | Implemented as **disables-toggle-without-a-bound-shortcut**: the toggle's enabled flag is set to `false` whenever the current binding has no shortcut, and `NSSwitch`'s native disabled dimming applies; `KeyCommandRowView` itself has no separate `isEnabled` of its own. |
| Focused | The capture field becoming first responder (recording) is surfaced at the row level: the row enters the mid-edit state, the confirm/cancel pair and readout row become visible, and the status label prompts `"press a key combination"` until a chord is captured (see **begins-editing-on-recording-start**). The capture field's own border color change while recording is that component's own appearance. |
| Loading | Not applicable: the component performs no asynchronous work of its own; every state transition in source is a synchronous property assignment. |
