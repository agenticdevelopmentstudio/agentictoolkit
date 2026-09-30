<!-- leaf: implement-extension-host-vs-2/code-api-main-thread-webviews--part-4 · source: extension-host-vs-code-api-main-thread-webviews.md -->

# MainThreadWebviews — continued (part 4)

**Rules** (cite as `implement-extension-host-vs-2/code-api-main-thread-webviews--part-4#<slug>`):

- `webview-html-accessor-round-trips-through-the-panel` MUST
- `webview-csp-source-is-scheme-and-panel-id` MUST
- `webview-as-webview-uri-requires-a-uri-argument` MUST
- `webview-post-message-resolves-false-without-posting-when-disposed` MUST
- `webview-post-message-resolves-the-panels-own-boolean` MUST
- `webview-on-did-receive-message-wraps-the-messages-emitter` MUST
- `webview-options-getter-omits-undeclared-roots` MUST
- `webview-options-setter-re-resolves-live-roots` MUST
- `webview-local-resource-roots-getter-reads-live-roots` MUST
- `webview-local-resource-roots-setter-refuses-unparseable-whole-values` MUST
- `install-accessor-and-getter-delegate-to-main-thread-window` MUST
- `dispose-is-idempotent` MUST
- `dispose-nulls-callbacks-before-disposing-each-panel` MUST
- `dispose-clears-every-registry` MUST
- `dispose-does-not-clear-on-removal-requested` MUST
- `logging-conformance` MUST

- **webview-html-accessor-round-trips-through-the-panel**: `makeWebviewObject`'s `html` accessor pair MUST read and write `model.panel.html` directly; assigning it MUST reload the page (the panel's own responsibility, not this file's).
- **webview-csp-source-is-scheme-and-panel-id**: `makeWebviewObject`'s `cspSource` readonly getter MUST answer `"<WebviewResourceURL.scheme>://<panelID>"`.
- **webview-as-webview-uri-requires-a-uri-argument**: `makeWebviewObject`'s `asWebviewUri` method MUST raise `"vscode.Webview.asWebviewUri needs a Uri."` when its argument is missing or does not parse as a `Uri`, and otherwise MUST build the result via `WebviewResourceURL.url(forFile:panelID:)` with no containment check performed at build time.
- **webview-post-message-resolves-false-without-posting-when-disposed**: `makeWebviewObject`'s `postMessage` method MUST resolve its returned promise with `false` — without calling `model.panel.post(message:)` at all — when `model` is already `nil` or `model.isDisposed`.
- **webview-post-message-resolves-the-panels-own-boolean**: when not disposed, `postMessage` MUST call `model.panel.post(message: message?.toObject() ?? NSNull())` and resolve the returned promise with that call's own boolean result.
- **webview-on-did-receive-message-wraps-the-messages-emitter**: `makeWebviewObject`'s `onDidReceiveMessage` method MUST subscribe the given listener to `model.messages`, delivered via the immediate window per **panel-model-events-use-immediate-delivery**.
- **webview-options-getter-omits-undeclared-roots**: `makeWebviewObject`'s `options` getter MUST include `localResourceRoots` in its answer only when the panel's `declaredLocalResourceRoots` is non-`nil`; it MUST omit the field entirely — not answer an empty array — when nothing was ever declared, matching `vscode.d.ts`'s optional-until-set semantics.
- **webview-options-setter-re-resolves-live-roots**: `makeWebviewObject`'s `options` setter MUST re-parse the assigned value via `parseOptions`, MUST assign the result to `model.panel.options`, and MUST also recompute and assign `model.panel.localResourceRoots = webviews.resourceRoots(for: options)`, so writing `options` re-resolves the live roots against the same extension-directory-plus-workspace defaulting used at creation.
- **webview-local-resource-roots-getter-reads-live-roots**: `makeWebviewObject`'s `localResourceRoots` getter MUST read `model.panel.localResourceRoots` directly (the resolved, live list), distinct from `options.localResourceRoots`'s declared-only view.
- **webview-local-resource-roots-setter-refuses-unparseable-whole-values**: `makeWebviewObject`'s `localResourceRoots` setter MUST be a no-op — leaving `model.panel.localResourceRoots` unchanged — when the assigned value cannot be parsed as a list of `Uri`s at all (including `undefined`/`null`), a deliberate divergence from `resourceRootsField`'s per-element-drop behavior, reasoned around the asymmetric security consequence of silently revoking file access versus silently keeping it.
- **install-accessor-and-getter-delegate-to-main-thread-window**: `installAccessor`/`installReadonlyGetter` MUST delegate to `MainThreadWindow`'s own static implementations rather than duplicating property-descriptor logic.
- **dispose-is-idempotent**: `dispose()` MUST be guarded by `isDisposed` and MUST do nothing on a second call.
- **dispose-nulls-callbacks-before-disposing-each-panel**: for every live panel, `dispose()` MUST null `onDidDispose` and `onDidReceiveMessage` before calling `panel.dispose()` and `model.removeListeners()`, so a mid-teardown callback cannot fire into a half-torn-down JavaScript context.
- **dispose-clears-every-registry**: `dispose()` MUST clear `panels`, `serializers`, and `viewProviders` entirely, so `hasSerializer` and `hasViewProvider` stop claiming any view type or view id afterward.
- **dispose-does-not-clear-on-removal-requested**: `dispose()` MUST NOT touch a panel's `onRemovalRequested` callback (the app's own pane-placement callback, not this adaptor's), at the stated cost that an `ExtensionHostInstaller.reconcile()` rescan without a serializer hand-off loses the open pane, unlike VS Code's own reload-through-serializer behavior for that case.
- **logging-conformance**: `MainThreadWebviews` MUST conform to `Loggable`, exposing a `nonisolated static let logger` built with `makeLogger()`.
- **restored-state-parse-failure-signal**: NEEDS REVIEW: Not implemented in source. `restoredStateValue(_:in:)` parses a non-`nil` saved `state` with `try? JSONSerialization.jsonObject(with:options:)`, and a parse failure falls into the same `guard` branch as a `nil` state, so a corrupt saved-state string reaches `deserializeWebviewPanel` as `undefined` with no log line and no error, indistinguishable from a panel that never called `setState`. What is missing: whether an unparseable saved state must be logged, surfaced to the extension, or deliberately treated as absent.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `presenter` | `any ExtensionWebviewPresenting` | none (required) | Puts a `createWebviewPanel` request on screen, or answers `nil` when no window is open. |
| `notImplementedLedger` | `NotImplementedLedger` | none (required) | Shared record of every webview member this host reaches for but does not honor. |
| `extensionIdentifier` | `String` | none (required) | The extension this adaptor instance belongs to; stamped on every ledger row and error log line. |
| `extensionDirectory` | `URL` | none (required) | This extension's install directory; the first entry in the default `localResourceRoots`. |
| `workspaceRoots` | `(any ExtensionWorkspaceRoots)?` | none (required, nullable) | Read fresh on every `createWebviewPanel` call to append the open project's folders to the default resource roots; `nil` when there is no workspace concept for this host. |

