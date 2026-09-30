<!-- leaf: implement-extension-host-vs-presenting/code-api-extension-status-bar-presenting--edge-cases · source: extension-host-vs-code-api-extension-status-bar-presenting.md -->

# ExtensionStatusBarPresenting

**Rules** (cite as `implement-extension-host-vs-presenting/code-api-extension-status-bar-presenting--edge-cases#<slug>`):

- `null-empty-input` MUST — ExtensionStatusBarItemRequest.text == "" MUST be accepted and passed to putOrUpdateStatusBarItem(_:) unchanged; the …
- `null-empty-input-2` MUST — name, tooltip, color, backgroundColor, command, accessibilityLabel, and accessibilityRole MAY all be nil simultaneously …
- `boundary-values` MUST — priority MAY carry Double.infinity or -Double.infinity unchanged — the caller performs no infinity clamping across this …
- `boundary-values-2` MUST — priority == nil (undefined) and priority == 0 (an explicit zero the extension supplied) MUST remain distinguishable on …
- `concurrent-access` MUST — because both MainThreadWindow and ExtensionStatusBarPresenting are @MainActor, calls into one conformer instance MUST …
- `concurrent-access-2` MUST — internalID uniqueness is guaranteed by the caller alone — MainThreadWindow.statusBarItemCounter, a static ordinal …
- `repeated-removal` MUST — removeStatusBarItem(internalID:) MUST remain safe if it is ever called more than once for the same internalID, or for …

## Edge Cases

- **Null/empty input**: `ExtensionStatusBarItemRequest.text == ""` MUST be accepted and passed to `putOrUpdateStatusBarItem(_:)` unchanged; the type enforces no minimum length (MUST).
- **Null/empty input**: `name`, `tooltip`, `color`, `backgroundColor`, `command`, `accessibilityLabel`, and `accessibilityRole` MAY all be `nil` simultaneously on one request; a conformer MUST accept that combination rather than requiring any of them (MUST).
- **Boundary values**: `priority` MAY carry `Double.infinity` or `-Double.infinity` unchanged — the caller performs no infinity clamping across this seam, because `MainThreadWindow` and its presenter share one process and one actor with no JSON boundary between them (MUST).
- **Boundary values**: `priority == nil` (undefined) and `priority == 0` (an explicit zero the extension supplied) MUST remain distinguishable on every request; the type never collapses the two (MUST).
- **Concurrent access**: because both `MainThreadWindow` and `ExtensionStatusBarPresenting` are `@MainActor`, calls into one conformer instance MUST be strictly serialized in the order the caller's own method calls and property writes occur; no two calls into the same instance can race (MUST). See **serialized-calls**.
- **Concurrent access**: `internalID` uniqueness is guaranteed by the caller alone — `MainThreadWindow.statusBarItemCounter`, a `static` ordinal incremented only under `@MainActor` — and this protocol's contract does not itself check or enforce that uniqueness; a conformer MUST trust the `internalID` it is given (MUST).
- **Error states**: not applicable — the protocol declares no `throws` and no `Result`/optional failure return on either method; see **void-return-no-failure-channel**.
- **Offline or disconnected state**: not applicable — this seam has no network dependency; every call is a same-process, same-actor method call between `MainThreadWindow` and its presenter.
- **Cancellation and timeouts**: not applicable — both methods are synchronous with no `async` gap, so there is nothing for a caller to cancel or time out; see **synchronous-no-await**.
- **Repeated removal**: `removeStatusBarItem(internalID:)` MUST remain safe if it is ever called more than once for the same `internalID`, or for an `internalID` already removed, on the same terms as **remove-tolerates-unknown-id** — an already-removed id and a never-shown id are the same case from the conformer's point of view (MUST).
