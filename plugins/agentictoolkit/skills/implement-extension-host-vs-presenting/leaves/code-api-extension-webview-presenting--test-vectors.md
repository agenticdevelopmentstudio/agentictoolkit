<!-- leaf: implement-extension-host-vs-presenting/code-api-extension-webview-presenting--test-vectors · source: extension-host-vs-code-api-extension-webview-presenting.md -->

# ExtensionWebviewPresenting

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-webview-presenting-001 | presenter-wired-before-revealed, request-value-semantics | A request with given `viewType`/`title`/`options`/`localResourceRoots`, and a `place` closure that returns a placement → `presentWebviewPanel(_:)` | The built panel mirrors the request's `viewType`, `title`, `options`, and `localResourceRoots` — `PaneWebviewPresenterTests.thePanelIsBuiltFromTheRequest` |
| extension-webview-presenting-002 | presenter-single-panel-per-call | A `place` closure that returns a placement → `presentWebviewPanel(_:)` | The panel `place` was called with is the same panel instance `presentWebviewPanel(_:)` returns — `PaneWebviewPresenterTests.thePanelPlacedIsThePanelReturned` |
| extension-webview-presenting-003 | presenter-nil-on-no-placement | A `place` closure that returns `nil` (no project window open) → `presentWebviewPanel(_:)` | Returns `nil` — `PaneWebviewPresenterTests.aPlacementThatFailsAnswersNil` |
| extension-webview-presenting-004 | presenter-failed-placement-reveals-nothing | Same nil-placement `place` closure → `presentWebviewPanel(_:)` | `reveal` is never called on any panel — `PaneWebviewPresenterTests.aPlacementThatFailsRevealsNothing` |
| extension-webview-presenting-005 | presenter-reveals-once, panel-reveal-preserve-focus | A request with `preserveFocus` set to a given value, successful placement → `presentWebviewPanel(_:)` | `reveal(preserveFocus:)` is called exactly once, carrying that same `preserveFocus` value, as part of the `presentWebviewPanel(_:)` call — `PaneWebviewPresenterTests.theCreateCallRevealsOnceCarryingPreserveFocus` |
| extension-webview-presenting-006 | presenter-wired-before-revealed | Successful placement → `presentWebviewPanel(_:)` | The placement's `reveal`/`remove` callbacks are installed on the panel before `reveal` is called — `PaneWebviewPresenterTests.thePanelIsWiredBeforeItIsRevealed` |
| extension-webview-presenting-007 | panel-dispose-idempotent | `dispose()` called twice on the same panel | The removal callback fires only once; the second call is a no-op — `PaneWebviewPresenterTests.aSecondDisposeDoesNotRemoveTwice` |
| extension-webview-presenting-008 | panel-disposed-flag | A `TestWebviewPanel` with `isDisposed == true` handed to the `restore` path | The hand-over is refused rather than adopted — `MainThreadWebviewsTests.restoringAPanelThatWasAlreadyClosedIsRefused` |
| extension-webview-presenting-009 | panel-disposed-flag | A `TestWebviewPanel` with `isDisposed == false` handed to `resolveWebviewView` | The hand-over succeeds and the live panel is adopted — `MainThreadWebviewsTests.resolvingAContributedViewHandsOverTheLivePanel` |
