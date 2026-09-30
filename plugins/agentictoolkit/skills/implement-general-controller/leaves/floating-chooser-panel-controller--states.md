<!-- leaf: implement-general-controller/floating-chooser-panel-controller--states · source: floating-chooser-panel-controller.md -->

# FloatingChooserPanelController

## States

| State | Appearance change |
|-------|------------------|
| Default | Newly initialized, not yet shown (window not visible); `isDismissing == false`. |
| Pressed | Not applicable — the controller renders no pressable surface of its own; per-press visuals belong to whatever `contentController` a subclass hosts. |
| Disabled | Not applicable — no enabled/disabled state exists for this window controller in source. |
| Focused | Window is key (`makeKeyAndOrderFront` ran in `show()`); first responder is whatever `takeInitialFocus()` set, per subclass. |
| Loading | Not applicable — `show()` is synchronous; no loading/spinner state exists in source. |
| Dismissing | `isDismissing == true`, from entry into `close()` until its call to `super.close()` returns; a nested `close()` call or a `windowDidResignKey` notification arriving during this interval MUST have no effect. |
| Focus lost, `dismissesOnFocusLoss == true` | Panel closes (`windowDidResignKey` calls `close()`). |
| Focus lost, `dismissesOnFocusLoss == false` | Panel remains open and visible; only key-window status is lost. |
