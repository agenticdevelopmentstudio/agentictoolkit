<!-- leaf: implement-extension-host-vs-presenting/code-api-extension-quick-pick-presenting--edge-cases · source: extension-host-vs-code-api-extension-quick-pick-presenting.md -->

# ExtensionQuickPickPresenting

**Rules** (cite as `implement-extension-host-vs-presenting/code-api-extension-quick-pick-presenting--edge-cases#<slug>`):

- `null-empty-input` MUST — ExtensionQuickPickRequest.items == [] is not forbidden by this contract; a conformer presents an empty list, and …
- `null-empty-input-2` MAY — title, placeHolder, and prompt MAY independently be nil; nothing in the contract requires any of the three to be …
- `boundary-values` MUST — a request with exactly one item is the minimum non-empty case; presenting-single-select-array-shape and …
- `boundary-values-2` MAY — an onHighlight index outside 0..<request.items.count is not addressed by this protocol — it MAY occur (the type …
- `concurrent-access` MAY — @MainActor isolation serializes each conformer's synchronous code, but this protocol places no constraint on whether a …
- `cancellation-and-timeouts` MUST — presentQuickPick declares no timeout parameter and no Task cancellation handling of its own; a caller wanting a …

## Edge Cases

- **Null/empty input**: `ExtensionQuickPickRequest.items == []` is not forbidden by this contract; a conformer presents an empty list, and `canPickMany`'s semantics are unaffected by the count (MUST — the protocol places no minimum-count constraint).
- **Null/empty input**: `title`, `placeHolder`, and `prompt` MAY independently be `nil`; nothing in the contract requires any of the three to be present (MAY).
- **Boundary values**: a request with exactly one item is the minimum non-empty case; `presenting-single-select-array-shape` and `presenting-index-based-answer` apply identically to it (MUST).
- **Boundary values**: an `onHighlight` index outside `0..<request.items.count` is not addressed by this protocol — it MAY occur (the type signature is a plain `(Int) -> Void`, with no bounds check declared here); the given sources' one consumer, `MainThreadWindow`, chooses to discard such a call rather than forward it to the extension, but that guard belongs to the consumer, not to this contract (MAY).
- **Concurrent access**: `@MainActor` isolation serializes each conformer's synchronous code, but this protocol places no constraint on whether a second `presentQuickPick` call MAY be issued to the same conformer instance before a prior call on that instance has returned; the production conformer `ExtensionPickerPresenter` resolves that overlap by dismissing the prior session (answering it `nil`) before presenting the new one, but that policy is the conformer's own decision, not part of this protocol's contract (MAY).
- **Error states**: not applicable — this file performs no I/O of its own (no network, database, or file-system access); every value it carries is data already supplied by the extension or a caller, and its one operation either returns a result or suspends, never throws.
- **Offline or disconnected state**: not applicable — `ExtensionQuickPickPresenting.swift` makes no network call and depends on no connectivity; a picker is presented entirely in-process.
- **Cancellation and timeouts**: `presentQuickPick` declares no timeout parameter and no `Task` cancellation handling of its own; a caller wanting a deadline or a cancellation path must implement it independently of this contract (MUST NOT be assumed present — it is an absent feature, not an unspecified one).
- **Malformed input**: not applicable to this file directly — turning a malformed extension-supplied item (a non-string `label`, a non-array `items` argument) into an error or a default is `MainThreadWindow.parseQuickPickItems(from:)`'s job, one layer up; this contract's types only ever hold values that have already passed that validation.
