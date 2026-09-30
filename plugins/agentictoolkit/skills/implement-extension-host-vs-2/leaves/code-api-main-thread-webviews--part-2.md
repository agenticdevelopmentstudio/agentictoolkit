<!-- leaf: implement-extension-host-vs-2/code-api-main-thread-webviews--part-2 · source: extension-host-vs-code-api-main-thread-webviews.md -->

# MainThreadWebviews — continued (part 2)

**Rules** (cite as `implement-extension-host-vs-2/code-api-main-thread-webviews--part-2#<slug>`):

- `main-actor-isolation` MUST
- `init-requires-every-collaborator-with-no-default` MUST
- `workspace-roots-are-read-fresh-not-snapshotted` MUST
- `panels-dictionary-is-the-sole-strong-reference` MUST
- `create-panel-raises-on-torn-down-adaptor` MUST
- `create-panel-requires-string-view-type` MUST
- `create-panel-requires-string-title` MUST
- `create-panel-parses-preserve-focus-from-third-argument` MUST
- `create-panel-parses-options-from-fourth-argument` MUST
- `create-panel-resolves-roots-before-presenting` MUST
- `create-panel-raises-when-no-window-is-open` MUST
- `create-panel-closes-and-raises-when-the-panel-object-cannot-be-built` MUST
- `create-panel-adopts-only-on-full-success` MUST
- `panel-model-events-use-immediate-delivery` MUST
- `view-state-changes-are-real-but-never-fired` MUST
- `wire-captures-the-panel-id-by-value` MUST
- `disposal-fires-before-forgetting` MUST
- `abandon-is-only-for-an-undelivered-hand-over` MUST
- `refused-hand-over-is-logged-not-silent` MUST
- `register-serializer-raises-on-torn-down-adaptor` MUST
- `register-serializer-requires-string-view-type` MUST
- `register-serializer-requires-a-callable-deserialize-method` MUST
- `register-serializer-last-registration-wins-and-is-logged` MUST
- `register-serializer-returns-a-token-guarded-disposable` MUST
- `has-serializer-false-when-disposed-or-missing` MUST
- `restore-refuses-when-disposed-or-unregistered` MUST
- `restore-refuses-an-already-closed-panel` MUST
- `restore-refuses-an-uncallable-deserializer` MUST
- `restore-closes-nothing-when-the-panel-object-cannot-be-built` MUST
- `restore-adopts-before-calling-deserialize` MUST

## Behavioral Requirements

- **main-actor-isolation**: `MainThreadWebviews` MUST be declared `@MainActor`; every stored property read and write and every method body MUST execute on the main actor.
- **init-requires-every-collaborator-with-no-default**: `init(presenter:notImplementedLedger:extensionIdentifier:extensionDirectory:workspaceRoots:)` MUST take all five parameters with no default value.
- **workspace-roots-are-read-fresh-not-snapshotted**: `resourceRoots(for:)` and `createWebviewPanel`'s request-building MUST read `workspaceRoots?.workspaceRootURLs` at call time, MUST NOT cache it at `init`, so a workspace folder opened after construction is reflected in the very next `createWebviewPanel` call's resolved roots.
- **panels-dictionary-is-the-sole-strong-reference**: `panels[panel.panelID]` MUST be the only strong reference this adaptor (or the JavaScript objects it builds) holds to an `ExtensionWebviewPanelModel`; dropping the dictionary entry (via `forget`) MUST be what makes every closure captured by that model's JS objects inert.
- **create-panel-raises-on-torn-down-adaptor**: `createWebviewPanel` MUST be built with `VSCodeAPI.member(..., whenTornDown: .raisedException, ...)`, and a call after `isDisposed` MUST raise `"vscode.window.createWebviewPanel is unavailable: this extension's host has been torn down."` rather than returning `undefined` or a non-functional panel object.
- **create-panel-requires-string-view-type**: `handleCreateWebviewPanel` MUST raise `"vscode.window.createWebviewPanel's first argument must be a view type string."` and present nothing when the first argument is missing or not a JavaScript string.
- **create-panel-requires-string-title**: `handleCreateWebviewPanel` MUST raise `"vscode.window.createWebviewPanel's second argument must be a title string."` and present nothing when the second argument is missing or not a JavaScript string.
- **create-panel-parses-preserve-focus-from-third-argument**: `handleCreateWebviewPanel` MUST derive `preserveFocus` by calling `parsePreserveFocus` on the third argument (or `nil` when absent), reading only that value's `preserveFocus` field and ignoring any `ViewColumn` the third argument might otherwise represent — this app's panes are a user-arranged tree with no numbered column for a `ViewColumn` to select.
- **create-panel-parses-options-from-fourth-argument**: `handleCreateWebviewPanel` MUST derive `WebviewPanelOptions` by calling `parseOptions` on the fourth argument (or `nil` when absent).
- **create-panel-resolves-roots-before-presenting**: `handleCreateWebviewPanel` MUST compute `localResourceRoots` via `resourceRoots(for: options)` and include the already-resolved list in the `ExtensionWebviewPanelRequest` handed to the presenter, so the presenter never has to know the extension's install directory or the open workspace folders itself.
- **create-panel-raises-when-no-window-is-open**: `handleCreateWebviewPanel` MUST log, at error level, that the extension asked for a panel with no window to put it in, and MUST raise `"vscode.window.createWebviewPanel could not open a panel for view type '<viewType>': this app's windows belong to open projects, and none is open."` when `presenter.presentWebviewPanel(request)` returns `nil`.
- **create-panel-closes-and-raises-when-the-panel-object-cannot-be-built**: when `makePanelObject` returns `nil` after a presenter has already put a panel on screen, `handleCreateWebviewPanel` MUST call `panel.dispose()` on the just-presented panel, MUST log the failure at error level, and MUST raise `"vscode.window.createWebviewPanel could not build a panel object for view type '<viewType>'."`, leaving no pane the extension can never address.
- **create-panel-adopts-only-on-full-success**: `handleCreateWebviewPanel` MUST call `adopt(model)` only after both `presentWebviewPanel` and `makePanelObject` succeed, and MUST return the built panel object as the member's result.
- **panel-model-events-use-immediate-delivery**: every `ExtensionEventEmitter` an `ExtensionWebviewPanelModel` constructs (for `onDidReceiveMessage`, `onDidDispose`, and the shared `viewStateChanges` behind `onDidChangeViewState`/`onDidChangeVisibility`) MUST be built with `ExtensionEventImmediateWindow(delay: 0)`, so a page's `postMessage` reaches the extension's `onDidReceiveMessage` listener in the same turn it was sent.
- **view-state-changes-are-real-but-never-fired**: `viewStateChanges` MUST remain a genuinely subscribable `ExtensionEventEmitter<Void>` (an extension's `Disposable` from subscribing to it MUST be valid and disposable), but nothing in this file MUST ever call `fire` on it, because panes here do not yet report view-state transitions.
- **wire-captures-the-panel-id-by-value**: the closure `wire(_:)` assigns to `panel.onDidDispose` MUST capture `panelID` by copy at wiring time, MUST NOT read `model.panel.panelID` after `forget` has removed the model from `panels`.
- **disposal-fires-before-forgetting**: the `onDidDispose` closure `wire(_:)` installs MUST call `model.markDisposed()` and `model.disposal.fire(())` before calling `forget(panelID)`, so every listener the extension registered on `onDidDispose` is still present in `model.disposal`'s registrations at the moment it fires.
- **abandon-is-only-for-an-undelivered-hand-over**: `abandon(_:)` MUST be called only when a hand-over (`restore` or `resolveWebviewView`) adopted a model and then could not deliver an object to the extension at all (a `VSCodeAPI.call` result of `.unavailable`); it MUST null the model's `onDidDispose` and `onDidReceiveMessage` and call `forget`, and MUST NOT be called for a hand-over whose extension received the object and then threw — a throwing extension MUST keep its panel.
- **refused-hand-over-is-logged-not-silent**: `logRefusedHandover(of:kind:)` MUST log, at notice level, that the panel or view named by `identifier` was closed before the extension could fill it and is not handed over, whenever `restore` or `resolveWebviewView` refuses an already-disposed panel.
- **register-serializer-raises-on-torn-down-adaptor**: `registerWebviewPanelSerializer` MUST be built with `whenTornDown: .raisedException`, raising `"vscode.window.registerWebviewPanelSerializer is unavailable: this extension's host has been torn down."` after `isDisposed`.
- **register-serializer-requires-string-view-type**: `handleRegisterWebviewPanelSerializer` MUST raise `"vscode.window.registerWebviewPanelSerializer's first argument must be a view type string."` when the first argument is missing or not a string.
- **register-serializer-requires-a-callable-deserialize-method**: `handleRegisterWebviewPanelSerializer` MUST test the second argument with `isObject` AND a callable `deserializeWebviewPanel` property (via `isFunction`), and MUST raise `"vscode.window.registerWebviewPanelSerializer's second argument must be an object with a deserializeWebviewPanel(panel, state) method."` when either check fails — checking the object alone (`isObject` true of `{}`) would let a mistyped method name register successfully and silently restore nothing, months later.
- **register-serializer-last-registration-wins-and-is-logged**: `handleRegisterWebviewPanelSerializer` MUST replace any existing `serializers[viewType]` with the new registration (last write wins, matching upstream's map assignment) and MUST log the replacement at error level when one already existed.
- **register-serializer-returns-a-token-guarded-disposable**: `handleRegisterWebviewPanelSerializer` MUST mint a fresh `UUID` token for the registration and return a `Disposable` whose `dispose()` removes `serializers[viewType]` only when the live entry's token still equals the token captured at registration time.
- **has-serializer-false-when-disposed-or-missing**: `hasSerializer(for:)` MUST return `false` when `isDisposed` is `true`, and MUST otherwise return whether `serializers[viewType]` is non-`nil`.
- **restore-refuses-when-disposed-or-unregistered**: `restore(_:viewType:state:)` MUST return `false` immediately, with no side effect, when `isDisposed` is `true` or no serializer is registered for `viewType`.
- **restore-refuses-an-already-closed-panel**: `restore(_:viewType:state:)` MUST return `false` and MUST call `logRefusedHandover` — MUST NOT call `adopt`, MUST NOT set `onDidDispose`/`onDidReceiveMessage` on the panel, MUST NOT call `deserializeWebviewPanel` — when the handed-over `panel.isDisposed` is already `true` at the moment of the call.
- **restore-refuses-an-uncallable-deserializer**: `restore(_:viewType:state:)` MUST log at error level and return `false` when the registered serializer's `context` is `nil` or `deserializeWebviewPanel` is not callable at call time.
- **restore-closes-nothing-when-the-panel-object-cannot-be-built**: `restore(_:viewType:state:)` MUST log at error level and return `false`, leaving the handed-over panel blank (and MUST NOT call `panel.dispose()`), when `makePanelObject` fails to build a JavaScript object for the restored panel.
- **restore-adopts-before-calling-deserialize**: `restore(_:viewType:state:)` MUST call `adopt(model)` before invoking `deserializeWebviewPanel`, so the panel is already wired for messages and disposal by the time the extension's own callback runs.
