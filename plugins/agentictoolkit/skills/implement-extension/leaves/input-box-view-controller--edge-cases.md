<!-- leaf: implement-extension/input-box-view-controller--edge-cases · source: extension-input-box-view-controller.md -->

# ExtensionInputBoxViewController

**Rules** (cite as `implement-extension/input-box-view-controller--edge-cases#<slug>`):

- `optional-prompt-label-2` MUST — Null/empty input — title/prompt: model.request.title/prompt being nil or "" suppresses that label entirely (see …
- `model-canaccept-true-invoke-onaccept-treated-nothing` MUST — Null/empty input — value: model.value may be "" (an empty pre-filled or typed value). Per …
- `cannot-resolve-focusfield-apply-whatever-range-returns` MUST — Boundary values — initial selection: model.initialSelectionUTF16Range() (called directly by focusField()) clamps an …
- `error-severity-extensioninputvalidation-always-render-via-validation` MUST — Error states: The only failure mode that reaches this file is a .error-severity ExtensionInputValidation, which it MUST …
- `field-longer-holds` MUST — Return held, then superseded by a further edit: a Return pressed while model.isValidating is true is held pending …
- `prefill-validation-once-2` MUST — Repeated viewDidAppear for one controller instance: the pre-filled value is validated once per controller instance, not …
- `model-has-effect-not-re-evaluate` MUST — isPassword cannot change mid-presentation: the field's class is fixed in init(model:) from model.request.isPassword; …
- `produces-observable-change-documented-known-quirk-reusing` MAY — Arrow keys (up/down) inside the field are consumed with no visible effect: control(_:textView:doCommandBy:) routes …

## Edge Cases

- Null/empty input — title/prompt: `model.request.title`/`prompt` being
  `nil` or `""` suppresses that label entirely (see
  `optional-title-label`/`optional-prompt-label`). MUST.
- Null/empty input — value: `model.value` may be `""` (an empty pre-filled
  or typed value). Per `ExtensionInputBoxModel.onAccept`'s own contract,
  "an empty string is a value, and Return accepts it" — Return with an
  empty field and `model.canAccept == true` MUST invoke `onAccept("")`,
  not be treated as "nothing entered." MUST.
- Boundary values — initial selection: `model.initialSelectionUTF16Range()`
  (called directly by `focusField()`) clamps an out-of-bounds
  `valueSelection` to the value's length, and falls back to a zero-length
  range at the very end of the value (`NSRange(location: value.utf16.count,
  length: 0)`) when the Character-offset-to-`String.Index` conversion
  cannot resolve. `focusField()` MUST apply whatever range this returns
  without additional validation of its own. MUST.
- Concurrent access: Not applicable — the class is `@MainActor`-isolated,
  so all field-delegate callbacks, keyboard dispatch, and validation
  replies are serialized on the main actor; there is no code path by
  which two threads mutate the controller's state simultaneously.
- Error states: The only failure mode that reaches this file is a
  `.error`-severity `ExtensionInputValidation`, which it MUST always
  render via `validation-message-shown` and MUST always block acceptance
  for via `model-gated-acceptance`/`return-drop-under-error`.
  This file calls no throwing or networked API itself; the extension's
  `validateInput` call and any failure within it are owned by
  `ExtensionPickerPresenter`/the `ExtensionInputBoxPresenting` conformer
  above this controller, not by `ExtensionInputBoxViewController`. MUST.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; validation answers arrive as already-resolved
  `ExtensionInputValidation` values passed into `showValidation(_:)`.
- Return held, then superseded by a further edit: a Return pressed while
  `model.isValidating` is `true` is held pending validation (see
  `acceptance-deferral`); if the user types again before the answer
  lands, `pending-acceptance-reset` discards that held Return, so it is
  never replayed against a value the field no longer holds. MUST.
- Repeated `viewDidAppear` for one controller instance: the pre-filled
  value is validated once per controller instance, not once per
  `viewDidAppear` call (see `prefill-validation-once`). MUST.
- `isPassword` cannot change mid-presentation: the field's class is fixed
  in `init(model:)` from `model.request.isPassword`; there is no code
  path in this file that rebuilds or reclasses the field afterward, so a
  hypothetical later change to that flag on the same model has no effect.
  MUST NOT re-evaluate.
- Arrow keys (up/down) inside the field are consumed with no visible
  effect: `control(_:textView:doCommandBy:)` routes every `doCommandBy:`
  selector through the shared `PickerKeyboardController.handle(_:)`, which
  also recognizes `moveUp`/`moveDown` and reports them handled
  (`onMoveSelection` is invoked and the selector is treated as consumed).
  This controller never assigns `onMoveSelection`, so pressing the up or
  down arrow while the field has focus is swallowed (marked handled, so it
  does not fall through to the field's default behavior) but produces no
  observable change. MAY — this is a documented known quirk of reusing the
  shared controller, not a contract this component defines; whether it is
  wanted is the open question in Design Decisions, not a requirement every
  port must reproduce.
