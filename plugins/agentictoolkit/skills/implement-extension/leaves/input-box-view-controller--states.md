<!-- leaf: implement-extension/input-box-view-controller--states · source: extension-input-box-view-controller.md -->

# ExtensionInputBoxViewController

## States

| State | Appearance change |
|-------|------------------|
| Default | `titleLabel`/`promptLabel` shown per `model.request` (or omitted, per those requirements); field shows `model.value`; `validationLabel` starts `isHidden = true`. |
| Pressed | Not applicable — no `NSButton` or other pressable control appears anywhere in `ExtensionInputBoxViewController.swift`; the field is a text-entry control, not a press target. |
| Disabled | Not applicable — `isEnabled` is never set on the field (or on either label) anywhere in source; the field is always enabled once the panel is on screen. |
| Focused | The field can become first responder (via normal Tab/click focus, or via `focusField()`). No custom focus-ring styling is set in source — AppKit's default `NSTextField`/`NSSecureTextField` focus ring applies. `focusField()` additionally applies `model.initialSelectionUTF16Range()` as the field's text selection, but only when explicitly invoked — not automatically on every focus event. |
| Loading | No loading indication — `model.isValidating` (set true by `beginValidating()`, cleared by `recordValidation(_:)`) changes only the acceptance logic (Return is held and replayed — see `acceptance-deferral`); no view property (opacity, a spinner, a disabled state, or any other visual cue) is read from or set based on `model.isValidating` anywhere in `ExtensionInputBoxViewController.swift`. |
