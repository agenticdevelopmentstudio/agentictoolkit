<!-- leaf: implement-extension-host-vs-2/code-api-main-thread-window--part-4 · source: extension-host-vs-code-api-main-thread-window.md -->

# MainThreadWindow — continued (part 4)

**Rules** (cite as `implement-extension-host-vs-2/code-api-main-thread-window--part-4#<slug>`):

- `returned-item-show-forward-presenter-show-call` MUST — Calling the returned item's show() MUST forward to the presenter's show call for that item's internal identifier; …
- `returned-item-dispose-forward-presenter-dispose-call` MUST — Calling the returned item's dispose() MUST forward to the presenter's dispose call for that identifier and MUST remove …
- `status-bar-item-applied-presenter-immediately-synchronously` MUST — Every property mutation on a returned status bar item MUST be applied to the presenter immediately, synchronously, on …
- `teardown-entry-point-mark-promisesettlementbox-instance-still` MUST — MainThreadWindow's own dispose() (or equivalent teardown entry point) MUST mark every PromiseSettlementBox this …
- `promise-returning-member-run-mainactor-suspend-across` MUST — Every promise-returning member MUST run on the @MainActor and MUST NOT suspend across an actor boundary other than the …

- Calling the returned item's `show()` MUST forward to the presenter's show call for that item's internal identifier; calling `hide()` MUST forward to the presenter's hide call for that identifier unconditionally, even when the item was never shown, rather than checking a local shown/hidden flag first.
- Calling the returned item's `dispose()` MUST forward to the presenter's dispose call for that identifier and MUST remove any bookkeeping this adaptor keeps for that identifier (so a later mutation of a disposed item's properties does not resurrect it in the presenter), and MUST perform the presenter-facing dispose call before discarding this adaptor's own bookkeeping for that identifier, not after.
- Every property mutation on a returned status bar item MUST be applied to the presenter immediately, synchronously, on the calling `@MainActor` context, with no debouncing or coalescing of rapid repeated writes (e.g. setting `text` many times in a tight loop) into a single presenter call.
- `MainThreadWindow`'s own `dispose()` (or equivalent teardown entry point) MUST mark every `PromiseSettlementBox` this instance still holds as disposed, so that any `show*Message`, `showQuickPick` or `showInputBox` promise still pending at teardown is left permanently unsettled rather than rejected or resolved after disposal.
- Every promise-returning member MUST run on the `@MainActor` and MUST NOT suspend across an actor boundary other than the single `await` of the corresponding presenter call.
## Configuration

| Parameter | Type | Required | Description |
|---|---|---|---|
| `messagePresenter` | `ExtensionMessagePresenting` | Yes, no default | Presents `showInformationMessage`/`showWarningMessage`/`showErrorMessage` calls. |
| `quickPickPresenter` | `ExtensionQuickPickPresenting` | Yes, no default | Presents `showQuickPick` calls. |
| `inputBoxPresenter` | `ExtensionInputBoxPresenting` | Yes, no default | Presents `showInputBox` calls. |
| `statusBarPresenter` | `ExtensionStatusBarPresenting` | Yes, no default | Presents `createStatusBarItem` items and their live mutations. |
| `notImplementedLedger` | `NotImplementedLedger` | Yes, no default | Receives one record per unsupported `tooltip`/`command` shape set on a status bar item. |
| `extensionIdentifier` | `String` | Yes, no default | Attributed on every ledger record this instance makes. |

## Localization

This adaptor is not itself a rendered surface, but every rejection and validation message it produces is a hardcoded English literal handed to the extension (and, in several presenter-facing test assertions, to a person debugging the extension), so it is a genuine localization surface, not one this recipe can mark "Not applicable." None of these strings route through any localization mechanism (no `String(localized:)`, no string catalog entry); they are `String(format:)`/interpolation-built English sentences. Representative examples, each traced to source:

| String (representative) | Where |
|---|---|
| `"<memberPath> requires a message argument."` | `show*Message` zero-argument rejection |
| `"<memberPath>'s argument 0 could not be converted to a string."` | `show*Message` message-coercion failure |
| `"<memberPath>'s argument <index> is neither a string nor an object with a string 'title'."` | `show*Message` item-shape rejection |
| `"vscode.window.showQuickPick requires an items argument."` | `showQuickPick` zero-argument rejection |
| `"vscode.window.showQuickPick's argument 0 is neither an array nor a promise of one."` | `showQuickPick` items-shape rejection |
| `"vscode.window.showQuickPick's argument 0 is an array of more than <max> items, or reports a length this host cannot read."` | `showQuickPick` array-length rejection |
| `"vscode.window.showQuickPick's items[<index>] is neither a string nor an object with a string 'label'."` | `showQuickPick` per-item rejection |
| `"vscode.window.showQuickPick's argument 1 is neither an options object nor undefined."` | `showQuickPick` options-shape rejection |
| `"vscode.window.showInputBox's argument 0 is neither an options object nor undefined."` | `showInputBox` options-shape rejection |
| `"...options.valueSelection is neither a two-element array nor undefined/null."` and its four sibling `valueSelection` messages (element count, element types, negative start, end-before-start, end-past-value-length, offset-inside-character) | `showInputBox` `valueSelection` validation |
| `"vscode.window.createStatusBarItem is unavailable: this extension's host has been torn down."` | `createStatusBarItem` raised after teardown |

Any UI surface presenting one of these strings to an end user, rather than to the extension that triggered them, would need its own localization pass; this adaptor itself has none.

## Privacy

This adaptor does not persist or transmit anything itself, but it is a conduit for user- and extension-authored content: message text and button titles (`show*Message`), quick-pick item labels/descriptions/details (`showQuickPick`), typed input values including a `password: true` field's contents (`showInputBox`), and status bar item text/tooltip/color values all pass through this instance's memory for the duration of a single call or for the lifetime of a live status bar item object, then are discarded when the promise settles or the item is disposed. None of it is written to disk, logged, or sent anywhere by this adaptor; `NotImplementedLedger`'s records carry only a member-path string and the caller's `extensionIdentifier`, never the message, item, or input content itself. A `password: true` input box's typed value is held in process memory identically to a non-password value — this adaptor applies no additional in-memory protection for it, and masking that value on screen is the presenter's responsibility, not this adaptor's.

