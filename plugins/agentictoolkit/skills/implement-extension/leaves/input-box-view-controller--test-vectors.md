<!-- leaf: implement-extension/input-box-view-controller--test-vectors · source: extension-input-box-view-controller.md -->

# ExtensionInputBoxViewController

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-input-box-view-controller-001 | optional-title-label | `model.request.title = "Enter API Key"` | `titleLabel` is created, non-nil, `role == .primaryText`, `textRole == .heading`, `stringValue == "Enter API Key"` |
| extension-input-box-view-controller-002 | optional-title-label | `model.request.title = nil` (and, separately, `= ""`) | `titleLabel` is `nil`; no title view is added to `root`'s subviews |
| extension-input-box-view-controller-003 | optional-prompt-label | `model.request.prompt = "Used only for this session."` | `promptLabel` is created, non-nil, `role == .secondaryText`, `textRole == .caption`, `stringValue` matches |
| extension-input-box-view-controller-004 | optional-prompt-label | `model.request.prompt = nil` | `promptLabel` is `nil`; no prompt view is added to `root`'s subviews |
| extension-input-box-view-controller-005 | secure-field-selection | Construct with `model.request.isPassword = true` | `field` is an `NSSecureTextField` instance |
| extension-input-box-view-controller-006 | secure-field-selection | Construct with `model.request.isPassword = false` | `field` is a plain `NSTextField` instance, not `NSSecureTextField` |
| extension-input-box-view-controller-007 | field-placeholder-seed | `model.request.placeHolder = "org/repo"` | `field.placeholderString == "org/repo"` after `loadView` |
| extension-input-box-view-controller-008 | field-placeholder-seed | `model.request.placeHolder = nil` | `field.placeholderString == ""` after `loadView` |
| extension-input-box-view-controller-009 | initial-field-value | `model.value = "prefilled"` | After `viewDidLoad`, `field.stringValue == "prefilled"` |
| extension-input-box-view-controller-010 | prefill-validation-once | Call `viewDidAppear()` twice in succession on a fresh instance | `model.beginValidating()`/`onValueChanged(model.value)` fire exactly once, on the first call only |
| extension-input-box-view-controller-011 | value-commit-and-revalidation | Set `field.stringValue = "abc"` and invoke `controlTextDidChange(_:)` | `model.value == "abc"`; `model.isValidating == true`; `onValueChanged` is invoked once with `"abc"` |
| extension-input-box-view-controller-012 | pending-acceptance-reset, acceptance-deferral | `model.isValidating == true`; press Return (deferring acceptance); then set `field.stringValue` and invoke `controlTextDidChange(_:)` (an edit); then call `showValidation` with a validation that makes `model.canAccept == true` | `onAccept` is not invoked — the edit discarded the held Return before validation landed |
| extension-input-box-view-controller-013 | model-gated-acceptance | `model.canAccept == true`; invoke `control(_:textView:doCommandBy: #selector(NSResponder.insertNewline(_:)))` | `onAccept` is invoked exactly once, with `model.value` |
| extension-input-box-view-controller-014 | model-gated-acceptance | `model.canAccept == false`; invoke the same Return command | `onAccept` is not invoked |
| extension-input-box-view-controller-015 | acceptance-deferral | `model.isValidating == true`; press Return; then call `showValidation(nil)`, which invokes `model.recordValidation(nil)` internally, clearing `model.isValidating` and making `model.canAccept == true` | `onAccept(model.value)` is not invoked on the Return press itself; it fires exactly once, inside the `showValidation(nil)` call, once validation lands |
| extension-input-box-view-controller-016 | return-drop-under-error | `model.isValidating == false`, `model.canAccept == false` (standing `.error`); press Return | `onAccept` is not invoked, and a validation that subsequently lands with `model.canAccept == true` does not retroactively invoke it either — the Return was dropped, not deferred |
| extension-input-box-view-controller-017 | escape-cancellation | With the monitor started (`viewDidAppear` ran) and the view's window key, dispatch a `keyDown` with `keyCode == 53` for that window | `onCancel()` is invoked exactly once |
| extension-input-box-view-controller-018 | validation-message-shown | Call `showValidation(ExtensionInputValidation(message: "Required", severity: .error))` | `validationLabel.isHidden == false`; `stringValue == "Required"`; `role == .danger` |
| extension-input-box-view-controller-019 | validation-message-shown | Call `showValidation(ExtensionInputValidation(message: "Heads up", severity: .warning))` (and, separately, `.information`) | `role == .warning` for `.warning` (and `role == .secondaryText` for `.information`) |
| extension-input-box-view-controller-020 | validation-message-hidden | Call `showValidation(nil)` | `validationLabel.isHidden == true` |
| extension-input-box-view-controller-021 | focus-then-initial-selection | Call `focusField()` with `model.initialSelectionUTF16Range()` resolving to `NSRange(location: 2, length: 3)` | The field is first responder, and `field.currentEditor()?.selectedRange == NSRange(location: 2, length: 3)` |
| extension-input-box-view-controller-022 | panel-size-from-fitted-layout | Load the view with content whose fitted Auto Layout height is 40pt (below the 72pt floor) | `preferredContentSize == NSSize(width: 480, height: 72)` |
| extension-input-box-view-controller-023 | panel-size-from-fitted-layout | Load the view with content whose fitted Auto Layout height is 160pt | `preferredContentSize == NSSize(width: 480, height: 160)` |
| extension-input-box-view-controller-024 | model-gated-acceptance | `model.value == ""`, `model.canAccept == true`; invoke the Return command | `onAccept("")` is invoked exactly once — an empty value is still accepted, not treated as nothing entered |
| extension-input-box-view-controller-025 | escape-cancellation | With the monitor started (`viewDidAppear` ran), dispatch a `keyDown` with `keyCode == 53` for a window that is not the view's window | `onCancel()` is not invoked |
