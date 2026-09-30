<!-- leaf: implement-extension-host-vs-2/code-api-ns-alert-message-presenter--edge-cases · source: extension-host-vs-code-api-ns-alert-message-presenter.md -->

# NSAlertMessagePresenter

**Rules** (cite as `implement-extension-host-vs-2/code-api-ns-alert-message-presenter--edge-cases#<slug>`):

- `null-empty-input` MUST — request.itemTitles == [] MUST make presentMessage(_:) add a single OK button and return nil unconditionally, per …
- `null-empty-input-2` MUST — request.detail == nil MUST be treated as "assign nothing to informativeText," not coerced to an empty string, per …
- `null-empty-input-3` MUST — request.message == "" MUST be accepted and assigned to messageText unchanged; the code performs no non-empty …
- `boundary-values` MUST — itemTitles of exactly one entry, unflagged, MUST make buttonPlan(for:) return a two-entry plan ([0, nil]), and …
- `boundary-values-2` MUST — itemTitles of exactly one entry, flagged isCloseAffordance, MUST make buttonPlan(for:) return a one-entry plan ([0]) …
- `boundary-values-3` MUST — every entry in itemTitles flagged (two or more items) MUST make buttonPlan(for:) return a one-entry plan holding only …
- `concurrent-access` MUST — because NSAlertMessagePresenter declares no Sendable conformance, an instance MUST NOT be called from outside its main …
- `error-states` MUST — sheetWindow() returning nil (no window anywhere in the app) MUST cause the message to be logged at error level and MUST …
- `error-states-2` MUST — a buttonIndex computed from the sheet's response that does not index into buttonItemIndices MUST resolve to nil rather …
- `cancellation-and-timeouts` MUST — presentMessage(_:) defines no timeout of its own and does not observe Task cancellation; a caller whose enclosing Task …
- `concurrent-presentation-ordering` MAY

## Edge Cases

- **Null/empty input**: `request.itemTitles == []` MUST make `presentMessage(_:)` add a single `OK` button and return `nil` unconditionally, per **empty-items-single-ok** (MUST).
- **Null/empty input**: `request.detail == nil` MUST be treated as "assign nothing to `informativeText`," not coerced to an empty string, per **detail-text-conditional** (MUST).
- **Null/empty input**: `request.message == ""` MUST be accepted and assigned to `messageText` unchanged; the code performs no non-empty validation, so a caller MUST NOT assume `message` is non-empty before this presenter is reached (MUST NOT).
- **Boundary values**: `itemTitles` of exactly one entry, unflagged, MUST make `buttonPlan(for:)` return a two-entry plan (`[0, nil]`), and `escapeKeyEquivalentPosition(in:)` MUST then assign Escape to the second (cancel) slot, since `plan.count > 1` (MUST).
- **Boundary values**: `itemTitles` of exactly one entry, flagged `isCloseAffordance`, MUST make `buttonPlan(for:)` return a one-entry plan (`[0]`) holding that item's own index, and `escapeKeyEquivalentPosition(in:)` MUST return `nil` for it, leaving that sole button's default Return key equivalent untouched, per the source's own rationale for why a one-entry plan is the exception (MUST).
- **Boundary values**: every entry in `itemTitles` flagged (two or more items) MUST make `buttonPlan(for:)` return a one-entry plan holding only the *last* flagged index; every other flagged item's button MUST NOT be added (MUST / MUST NOT).
- **Concurrent access**: `@MainActor` isolation serializes the synchronous portion of each `presentMessage(_:)` call on a given instance, but does not by itself serialize the calls across the `await` inside `presentedResponse(for:)` — see **concurrent-presentation-ordering** below.
- **Concurrent access**: because `NSAlertMessagePresenter` declares no `Sendable` conformance, an instance MUST NOT be called from outside its main actor's isolation domain except by `await`ing across that boundary (MUST NOT).
- **Error states**: `sheetWindow()` returning `nil` (no window anywhere in the app) MUST cause the message to be logged at `error` level and MUST resolve `presentMessage(_:)` to `nil` rather than crash, throw, or block the caller, per **drop-when-no-window** and **dropped-message-logged** (MUST).
- **Error states**: a `buttonIndex` computed from the sheet's response that does not index into `buttonItemIndices` MUST resolve to `nil` rather than trap on an out-of-bounds array subscript, per **out-of-range-response-resolves-nil** (MUST).
- **Cancellation and timeouts**: `presentMessage(_:)` defines no timeout of its own and does not observe `Task` cancellation; a caller whose enclosing `Task` is cancelled while awaiting `presentMessage(_:)` MUST NOT assume the sheet is dismissed or the underlying continuation is resumed early, because the source implements no cancellation-handling path for this call (MUST NOT).
- **Offline or disconnected state**: not applicable — the source imports only `AppKit`, `Foundation`, `OSLog`, and `AgenticToolkitCore`, and performs no network access of its own.
- **Missing file or unreachable server**: not applicable — the source opens no file and makes no network or process call of its own.

- **concurrent-presentation-ordering**: `NSAlertMessagePresenter` is `@MainActor`, so each `presentMessage(_:)` call's synchronous portion runs serially, but the actor is reentrant at the `await` inside `presentedResponse(for:)`: a second call MAY reach `beginSheetModal(for:completionHandler:)` before the first sheet is dismissed. The presenter adds no queuing or coalescing of its own; a second sheet on the same window is ordered by AppKit's own sheet queue, and each call's continuation resumes independently with its own sheet's response.
