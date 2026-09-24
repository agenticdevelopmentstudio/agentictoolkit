---
id: aa828b9b-925a-4f73-9073-12aab359aba6
title: MainThreadWebviews
domain: agentictoolkit://recipes/extension-host-vs-code-api-main-thread-webviews
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The extension host's vscode.window adaptor for webview panels and
  contributed webview views — createWebviewPanel, registerWebviewPanelSerializer,
  registerWebviewViewProvider, restore and resolveWebviewView — owning the
  sole strong reference that keeps each panel's JavaScript surface alive.
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- webviews
- disposable
- javascriptcore
- mainactor
depends-on: []
related:
- agentictoolkit://recipes/extension-host-vs-code-api-extension-webview-presenting
- agentictoolkit://recipes/extension-host-vs-code-api-extension-event
- agentictoolkit://recipes/extension-host-core-extensions-webview-panel-options
- agentictoolkit://recipes/extension-host-core-extensions-webview-resource-url
- agentictoolkit://recipes/extension-host-vs-code-api-main-thread-commands
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWebviews.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionWebviewPresenting.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/WebviewPanelOptions.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/WebviewResourceURL.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionEvent.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/VSCodeAPI.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Host/NotImplementedLedger.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/MainThreadWebviewsTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

# MainThreadWebviews

## Overview

`MainThreadWebviews.swift` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWebviews.swift`) is the extension host's `vscode.window` adaptor for the webview surface: `createWebviewPanel`, `registerWebviewPanelSerializer`, `registerWebviewViewProvider`, plus the two hand-over entry points `restore(_:viewType:state:)` and `resolveWebviewView(_:viewID:)` that `ExtensionHostInstaller` calls when a pane the project remembers is rebuilt before its extension has necessarily activated. The class is `@MainActor`-isolated, matching every other `MainThread*` adaptor and `ExtensionHost` itself, because `JSValue` is not `Sendable` and every member is called by JavaScriptCore on the thread that made the call.

`panels: [String: ExtensionWebviewPanelModel]` is the sole strong reference keeping a panel's JavaScript-exposed callbacks alive — `adopt`/`abandon`/`wire`/`forget` are the four moves of that lifecycle, and every path through `createWebviewPanel`, `restore` and `resolveWebviewView` funnels through them. `serializers` and `viewProviders` are token-guarded registries (`SerializerRegistration`/`ViewProviderRegistration`, each `{token: UUID, registration: JSValue}`) so that a stale `Disposable` captured before a later registration under the same key cannot unregister it. `workspaceRoots` is read fresh on every `createWebviewPanel` call rather than snapshotted at `init`, mirroring `MainThreadWorkspace`'s own stated rule, so a project folder opened after the extension activated is still a resource root a new panel can read from. `notImplementedLedger` records every VS Code webview member this host does not honor — `enableCommandUris`, `portMapping`, `WebviewPanel.iconPath`, `onDidChangeViewState`/`onDidChangeVisibility` subscriptions, and a contributed view's `resolveContext.state` — so the extension report (task 5.8) can name what an extension quietly lost rather than an operator discovering it by accident.

The type collaborates with, but does not itself implement: `ExtensionWebviewPresenting` (puts a panel on screen; `MainThreadWebviews` never touches AppKit or WebKit directly), `WebviewPanelOptions` (resolves declared-versus-default `localResourceRoots` and builds the floor Content-Security-Policy — the CSP construction is a collaborator fact this file never invokes), `WebviewResourceURL` (mints the `agentic-webview://<panelID>/<path>` scheme URL `asWebviewUri` returns, with the containment check against `localResourceRoots` happening elsewhere, in a WebKit scheme handler, not in this file), `ExtensionEventEmitter<Payload>` (the coalescing pub/sub relay behind `onDidReceiveMessage`, `onDidDispose`, `onDidChangeViewState`/`onDidChangeVisibility`, every one of them built with `ExtensionEventImmediateWindow(delay: 0)` for synchronous, same-turn delivery), `VSCodeAPI` (the shared `member`/`raise`/`call`/`disposable`/`resolvedPromise` ceremony every `MainThread*` adaptor uses instead of its own copy), and `NotImplementedLedger` (the deduplicated-by-member-path record described above).

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
- **restore-parses-saved-state-as-json-or-undefined**: `restoredStateValue(_:in:)` MUST parse a non-`nil` `state` string as JSON with `.fragmentsAllowed` and pass the decoded value to `deserializeWebviewPanel`, and MUST pass `JSValue(undefinedIn:)` — never JavaScript `null` — when `state` is `nil`, because an extension's `state ?? defaults` and `if (state === undefined)` read the two differently.
- **restore-returns-true-on-successful-deserialize**: `restore(_:viewType:state:)` MUST return `true` when `VSCodeAPI.call(deserialize, ...)` answers `.returned`.
- **restore-keeps-the-panel-adopted-when-deserialize-throws**: `restore(_:viewType:state:)` MUST log the exception at error level and return `false`, but MUST NOT call `abandon` — the model MUST stay adopted — when `VSCodeAPI.call` answers `.threw`.
- **restore-abandons-only-on-dispatch-unavailable**: `restore(_:viewType:state:)` MUST call `abandon(model)`, log at error level, and return `false` when `VSCodeAPI.call` answers `.unavailable`.
- **register-view-provider-mirrors-the-serializer-contract**: `handleRegisterWebviewViewProvider` MUST apply the same torn-down check, string-view-id check, and object-with-callable-`resolveWebviewView`-method check as `handleRegisterWebviewPanelSerializer` applies to view types and `deserializeWebviewPanel`, with the corresponding messages naming `vscode.window.registerWebviewViewProvider`, a view id string, and a `resolveWebviewView(webviewView, context, token)` method.
- **register-view-provider-drops-the-retain-context-hint-silently**: `handleRegisterWebviewViewProvider` MUST read and discard the third argument's `webviewOptions.retainContextWhenHidden` field without recording a `NotImplementedLedger` row, because every pane here already retains its view controller regardless of front-most state, so a ledger row would report a limitation that does not exist.
- **register-view-provider-does-not-throw-on-duplicate**: `handleRegisterWebviewViewProvider` MUST NOT raise or refuse a second registration for a view id already in `viewProviders`; it MUST log the replacement at error level and let the later registration win, deliberately diverging from upstream VS Code's throw — the "second" registration here is typically a post-reload registration, and honoring the app's earlier registration over the extension's would wire a live pane to a dead JavaScript context.
- **has-view-provider-false-when-disposed-or-missing**: `hasViewProvider(for:)` MUST return `false` when `isDisposed` is `true`, and MUST otherwise return whether `viewProviders[viewID]` is non-`nil`.
- **resolve-view-refuses-when-disposed-or-unregistered**: `resolveWebviewView(_:viewID:)` MUST return `false` immediately when `isDisposed` is `true` or no provider is registered for `viewID`.
- **resolve-view-refuses-an-already-closed-panel**: `resolveWebviewView(_:viewID:)` MUST refuse (return `false`, call `logRefusedHandover`, adopt nothing) a panel whose `isDisposed` is already `true`, mirroring **restore-refuses-an-already-closed-panel** exactly.
- **resolve-context-state-is-always-undefined-and-ledgered**: `resolveContextValue(of:in:)` MUST build a `WebviewViewResolveContext` whose `state` field is always `undefined`, and MUST record a `NotImplementedLedger` row for `vscode.WebviewViewResolveContext.state` the first time it is read, because a contributed view's state does not persist across a quit the way a serializer-backed panel's does.
- **resolve-view-token-never-cancels**: `uncancelledToken(in:)` MUST return a `CancellationToken` whose `isCancellationRequested` is always `false` and whose `onCancellationRequested` returns a real, never-fired `Disposable`; this degraded argument MUST NOT be recorded in the ledger, unlike a genuinely absent capability, because it is a real (if permanently unfired) token rather than a missing member.
- **resolve-view-returns-true-on-successful-resolve**: `resolveWebviewView(_:viewID:)` MUST return `true` when `VSCodeAPI.call(resolve, ...)` answers `.returned`, and MUST log-and-return-`false` without abandoning on `.threw`, matching `restore`'s throw handling.
- **resolve-view-abandons-only-on-dispatch-unavailable**: `resolveWebviewView(_:viewID:)` MUST call `abandon(model)`, log at error level, and return `false` when `VSCodeAPI.call` answers `.unavailable`.
- **boolean-field-requires-an-actual-boolean**: `booleanField(_:)` MUST return `nil` for any JavaScript value that is not a boolean (no truthy coercion of a number, string, or object).
- **is-truthy-flag-requires-boolean-true**: `isTruthyFlag(_:)` MUST return `true` only when the JavaScript value `isBoolean` and equals `true`; every other value, including a truthy non-boolean, MUST answer `false`.
- **resource-roots-field-distinguishes-absent-from-empty**: `resourceRootsField(_:in:)` MUST return `nil` when the value is absent, `undefined`, or `null` (letting `WebviewPanelOptions.resourceRoots` apply its extension-directory-plus-workspace default), and MUST return `[]` when the value is an explicit, empty JavaScript array (renouncing every default root).
- **resource-roots-field-drops-unparseable-entries**: `resourceRootsField(_:in:)` MUST drop any array element that does not parse as a `Uri` via `compactMap`, rather than substituting a default for the whole list, because a partially-unreadable declared list is still the extension's explicit declaration.
- **ledger-records-a-reach-only-when-truthy-or-non-empty**: `parseOptions` MUST record a `vscode.WebviewOptions.enableCommandUris` ledger row only when that field is present and truthy, and a `vscode.WebviewOptions.portMapping` row only when that field is a non-empty array; an explicit `false` or `[]` MUST record nothing, because a decline is not a reach for something missing.
- **panel-webview-getter-builds-a-fresh-object-every-access**: `makePanelObject`'s `webview` readonly getter MUST construct a new `Webview` JavaScript object on every access via `makeWebviewObject`, MUST NOT cache one on the model, honoring the no-capture contract that nothing stores a `JSValue` or `JSContext` on `ExtensionWebviewPanelModel`.
- **panel-title-is-an-accessor-pair-over-the-panel**: `makePanelObject`'s `title` accessor pair MUST read and write `model.panel.panelTitle` directly, with no local cache.
- **panel-options-getter-answers-fixed-values**: `makePanelObject`'s `options` readonly getter MUST always answer `{retainContextWhenHidden: true, enableFindWidget: false}`, regardless of what the extension requested at creation.
- **panel-icon-path-is-write-only-into-the-ledger**: `makePanelObject`'s `iconPath` getter MUST always answer `undefined`/`null`; its setter MUST record a `vscode.WebviewPanel.iconPath` ledger row only when assigned a non-`undefined`, non-`null` value.
- **panel-view-column-is-always-undefined**: `makePanelObject`'s `viewColumn` readonly getter MUST always answer `undefined`, with no ledger row, since there is no numbered column for it to name.
- **panel-active-and-visible-mirror-is-disposed**: `makePanelObject`'s `active` and `visible` readonly getters MUST both answer `!model.isDisposed`, an acknowledged approximation that never corrects itself while a panel is open, because `onDidChangeViewState` never fires.
- **panel-view-state-subscription-is-ledgered-every-call**: `makePanelObject`'s `onDidChangeViewState` method MUST record a `vscode.WebviewPanel.onDidChangeViewState` ledger row on every call before subscribing the listener to `model.viewStateChanges`.
- **panel-reveal-reads-its-second-argument-as-preserve-focus**: `makePanelObject`'s `reveal` method MUST read its second argument as `preserveFocus` (defaulting to `false`), MUST ignore its first argument (the dropped `ViewColumn`), and MUST call `model.panel.reveal(preserveFocus:)`.
- **panel-dispose-delegates-to-the-underlying-panel**: `makePanelObject`'s `dispose` method MUST call `model.panel.dispose()` and rely on that call's own idempotence.
- **view-title-mirrors-the-panels-title**: `makeWebviewViewObject`'s `title` accessor pair MUST read and write `model.panel.panelTitle`, answering the pane's current chrome name rather than `undefined`.
- **view-description-and-badge-are-write-only-into-the-ledger**: `makeWebviewViewObject`'s `description` and `badge` accessor pairs MUST both have no-op getters (always `undefined`/`null`) and setters that record a `vscode.WebviewView.description` or `vscode.WebviewView.badge` ledger row only for a non-`undefined`, non-`null` assigned value.
- **view-has-no-dispose-method**: `makeWebviewViewObject` MUST NOT install a `dispose` method on the JavaScript object it builds, matching upstream's `WebviewView`, because a contributed view's lifetime belongs to its manifest-declared pane, not to the extension.
- **view-visible-mirrors-is-disposed**: `makeWebviewViewObject`'s `visible` readonly getter MUST answer `!model.isDisposed`.
- **view-visibility-subscription-is-ledgered-every-call**: `makeWebviewViewObject`'s `onDidChangeVisibility` method MUST record a `vscode.WebviewView.onDidChangeVisibility` ledger row on every call before subscribing to `model.viewStateChanges`.
- **view-show-reads-its-first-argument-as-preserve-focus**: `makeWebviewViewObject`'s `show` method MUST read its first argument as `preserveFocus` (there being no `ViewColumn` to occupy that position for a contributed view).
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

## Appearance

Not applicable — this is the extension host's `vscode.window` webview adaptor, not a visual component.

## States

Not applicable — this is the extension host's `vscode.window` webview adaptor, not a visual component. Its only lifecycle-shaped behavior is each panel's adopted-versus-forgotten and disposed-versus-live status, captured under Behavioral Requirements (`panels-dictionary-is-the-sole-strong-reference`, `disposal-fires-before-forgetting`, `dispose-is-idempotent`) rather than as a visual-state table.

## Accessibility

Not applicable — this is the extension host's `vscode.window` webview adaptor, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| main-thread-webviews-001 | create-panel-requires-string-view-type | `vscode.window.createWebviewPanel(42, 'T', {})` — first argument is a number, not a string | The call throws synchronously and the presenter receives no request — `MainThreadWebviewsTests.createWebviewPanelWithoutAViewTypeStringThrowsAndPresentsNothing` |
| main-thread-webviews-002 | create-panel-raises-when-no-window-is-open | `createWebviewPanel('t', 'T', {})` with the presenter's `canPresent` set `false` | The call throws synchronously and `presenter.requests.count == 1` (the request was made and refused, not skipped) — `MainThreadWebviewsTests.createWebviewPanelWithNowhereToPutThePanelThrows` |
| main-thread-webviews-003 | create-panel-resolves-roots-before-presenting, resource-roots-field-distinguishes-absent-from-empty | `createWebviewPanel('t', 'T', {}, {})` with no `localResourceRoots` declared, extension directory and one workspace root both set | The presenter's request carries `localResourceRoots == [extensionDirectory] + [workspaceRoot]` — `MainThreadWebviewsTests.createWebviewPanelWithNoDeclaredRootsResolvesToTheExtensionDirectoryAndWorkspace` |
| main-thread-webviews-004 | resource-roots-field-distinguishes-absent-from-empty | `createWebviewPanel('t', 'T', {}, {localResourceRoots: []})` | The presenter's request carries an empty `localResourceRoots`, with no fallback to the default — `MainThreadWebviewsTests.createWebviewPanelWithAnEmptyLocalResourceRootsArrayGrantsNothing` |
| main-thread-webviews-005 | panel-reveal-reads-its-second-argument-as-preserve-focus | `panel.reveal(undefined, true)` then `panel.reveal()` on the same panel object | The test double records `revealCalls == [true, false]` — `MainThreadWebviewsTests.panelRevealPassesItsSecondArgumentAsPreserveFocus` |
| main-thread-webviews-006 | webview-as-webview-uri-requires-a-uri-argument | `panel.webview.asWebviewUri(vscode.Uri.file('/tmp/mtw-media/app.css'))` | The returned string equals `WebviewResourceURL.url(forFile:panelID:)`'s own `absoluteString` for that file and the panel's id — `MainThreadWebviewsTests.webviewAsWebviewUriRewritesAFileUriIntoTheWebviewScheme` |
| main-thread-webviews-007 | webview-post-message-resolves-false-without-posting-when-disposed | `panel.dispose()` from outside JavaScript, then `webview.postMessage({})` on the same, now-disposed panel's `webview` handle | The promise resolves `false` and `panel.postedMessages.isEmpty` stays true (post is never attempted) — `MainThreadWebviewsTests.webviewPostMessageAfterDisposalResolvesFalse` |
| main-thread-webviews-008 | webview-options-getter-omits-undeclared-roots, webview-options-setter-re-resolves-live-roots | Read `panel.webview.options.localResourceRoots` with none declared, then read-modify-write `options` back with `enableScripts: true` | `localResourceRoots` on the read object `isUndefined`; after the write-back the live panel's resolved roots still contain both the extension directory and the workspace root — `MainThreadWebviewsTests.readingOptionsBackAndWritingThemDoesNotFreezeTheDefaultRoots` |
| main-thread-webviews-009 | ledger-records-a-reach-only-when-truthy-or-non-empty | `createWebviewPanel('t', 'T', {}, {enableCommandUris: true, portMapping: [{webviewPort: 3000, extensionHostPort: 3000}]})`, then `panel.iconPath = Uri`, then `panel.onDidChangeViewState(fn)` | The ledger for the extension contains `vscode.WebviewOptions.enableCommandUris`, `vscode.WebviewOptions.portMapping`, `vscode.WebviewPanel.iconPath`, and `vscode.WebviewPanel.onDidChangeViewState` — `MainThreadWebviewsTests.optionsAndMembersThisHostDoesNotHonourAreRecordedInTheLedger` |
| main-thread-webviews-010 | ledger-records-a-reach-only-when-truthy-or-non-empty | `createWebviewPanel('t', 'T', {}, {enableCommandUris: false, portMapping: []})` | The ledger for the extension stays empty — `MainThreadWebviewsTests.anExplicitlyFalseEnableCommandUrisRecordsNothing` |
| main-thread-webviews-011 | dispose-nulls-callbacks-before-disposing-each-panel, dispose-clears-every-registry | Create two panels, then call `webviews.dispose()` | Both test panels report `disposeCount == 1` — `MainThreadWebviewsTests.disposingTheAdaptorDisposesEveryLivePanel` |
| main-thread-webviews-012 | register-serializer-returns-a-token-guarded-disposable | `registerWebviewPanelSerializer('markdown.preview', {...})`, capture the returned `Disposable`, call its `dispose()` | `hasSerializer(for: "markdown.preview")` is `true` before the dispose call and `false` after — `MainThreadWebviewsTests.disposingTheRegistrationGivesTheViewTypeUp` |
| main-thread-webviews-013 | register-serializer-requires-a-callable-deserialize-method | `registerWebviewPanelSerializer('t', {})` (object with no `deserializeWebviewPanel` at all) | The call throws synchronously and `hasSerializer(for: "t")` stays `false` — `MainThreadWebviewsTests.aMalformedRegistrationIsRefused` |
| main-thread-webviews-014 | restore-parses-saved-state-as-json-or-undefined, restore-adopts-before-calling-deserialize | `restore(panel, viewType: "markdown.preview", state: #"{"scrollTop":420}"#)` against a registered serializer that records the `state.scrollTop` and `panel.viewType` it receives | `deserializeWebviewPanel` sees `state.scrollTop == 420` and `panel.viewType == "markdown.preview"`; the call returns `true` — `MainThreadWebviewsTests.restoreCallsTheSerializerWithAPanelObjectAndTheSavedState` |
| main-thread-webviews-015 | restore-parses-saved-state-as-json-or-undefined | `restore(panel, viewType: "markdown.preview", state: nil)` | The serializer's `state` parameter is `undefined`, not `null` — `MainThreadWebviewsTests.aPanelWithNoSavedStateIsDeserializedWithUndefined` |
| main-thread-webviews-016 | restore-refuses-an-already-closed-panel | `restore(alreadyDisposedPanel, viewType: "markdown.preview", state: nil)` where the test panel's `dispose()` was called before `restore` | `restore` returns `false`; the panel is never adopted — `onDidDispose == nil` and `onDidReceiveMessage == nil` afterward, and `deserializeWebviewPanel` is never called — `MainThreadWebviewsTests.restoringAPanelThatWasAlreadyClosedIsRefused` |
| main-thread-webviews-017 | resolve-view-refuses-an-already-closed-panel | `resolveWebviewView(alreadyDisposedPanel, viewID: "acme.view")` against a registered provider | `resolveWebviewView` returns `false`; `resolveWebviewView` on the provider is never called, mirroring vector 016 — `MainThreadWebviewsTests.resolvingAContributedViewWhosePaneClosedIsRefused` |
| main-thread-webviews-018 | resolve-view-returns-true-on-successful-resolve | `resolveWebviewView(livePanel, viewID: "acme.view")` where the provider assigns `webviewView.webview.html = '<p>...</p>'` | `resolveWebviewView` returns `true` and the live test panel's `html` equals the assigned string — `MainThreadWebviewsTests.resolvingAContributedViewHandsOverTheLivePanel` |
| main-thread-webviews-019 | create-panel-raises-on-torn-down-adaptor | `webviews.dispose()`, then `createWebviewPanel('t', 'T', {})` on the same, now-disposed adaptor | The call throws synchronously and `presenter.requests.isEmpty` stays true — `MainThreadWebviewsTests.createWebviewPanelAfterDisposalThrowsAndPresentsNothing` |
| main-thread-webviews-020 | init-requires-every-collaborator-with-no-default, create-panel-resolves-roots-before-presenting | Call the public `resourceRoots(for:)` directly with undeclared roots, and again with an explicit empty declaration | Undeclared answers `[extensionDirectory.path, workspace.path]`; explicit `[]` answers an empty list — `MainThreadWebviewsTests.resourceRootsResolveAgainstTheExtensionDirectoryAndTheWorkspace` |

## Edge Cases

- **Null/empty input**: `createWebviewPanel()` called with zero arguments MUST fail the string-view-type guard (since the first argument is missing) and MUST raise the same message as a non-string first argument, per **create-panel-requires-string-view-type** (MUST).
- **Null/empty input**: `createWebviewPanel('t')` called with only one argument MUST fail the string-title guard and raise `"vscode.window.createWebviewPanel's second argument must be a title string."`, per **create-panel-requires-string-title** (MUST).
- **Null/empty input**: `restore(panel, viewType: "x", state: nil)` where no `deserializeWebviewPanel` has been registered for `"x"` MUST return `false` with no log line at all, per **restore-refuses-when-disposed-or-unregistered** — this is the ordinary "not yet activated" case, not a failure (MUST, `MainThreadWebviewsTests.restoringAViewTypeNobodyRegisteredIsRefused`).
- **Boundary values**: a `viewType` or `viewID` equal to the empty string is a valid `String` and reaches the duplicate-registration and lookup logic exactly as any other id would; nothing in this file rejects it (MUST, per the string-type checks, which check only that the value is a string).
- **Boundary values**: `createWebviewPanel('t', 'T', 1)` (a `ViewColumn` number where `showOptions` is expected) is not an object, so `parsePreserveFocus` returns `false` for it and the panel is still created — a degraded argument, not a refusal (MUST, per **create-panel-parses-preserve-focus-from-third-argument**, `MainThreadWebviewsTests.createWebviewPanelWithAViewColumnNumberForShowOptionsStillCreatesThePanel`).
- **Concurrent access**: `MainThreadWebviews` is `@MainActor`-isolated with no additional locking; `panels`, `serializers`, and `viewProviders` are read and mutated only on the main actor, so there is no data race to define behavior for (MUST).
- **Concurrent access**: a pane the user closes while its extension is still waking up MUST be seen as already-disposed by whichever of `restore` or `resolveWebviewView` runs once activation completes, and MUST be refused rather than adopted, per **restore-refuses-an-already-closed-panel** / **resolve-view-refuses-an-already-closed-panel** (MUST).
- **Error states**: `deserializeWebviewPanel` or `resolveWebviewView` throwing MUST leave the model adopted (the extension keeps its panel) and MUST log the exception, while `VSCodeAPI.call` answering `.unavailable` MUST abandon the model instead, per **restore-keeps-the-panel-adopted-when-deserialize-throws** / **restore-abandons-only-on-dispatch-unavailable** (MUST).
- **Error states**: a serializer or provider registered under a mistyped or non-callable method name MUST be refused at the `register*` call itself, never accepted and left silently unusable, per **register-serializer-requires-a-callable-deserialize-method** (MUST).
- **Cancellation or timeout**: `resolveWebviewView`'s `CancellationToken` argument never signals cancellation — `isCancellationRequested` is permanently `false` — because nothing in this host can currently interrupt a `resolveWebviewView` call in progress (fact, per **resolve-view-token-never-cancels**).
- **Missing or unreachable resource**: a `localResourceRoots` array entry that does not parse as a `Uri` is dropped from the resolved list rather than substituted with a default, per **resource-roots-field-drops-unparseable-entries** (MUST).
- **Missing or unreachable resource**: a `webview.localResourceRoots` assignment that cannot be parsed as a list of `Uri`s at all is refused outright, leaving the panel's live roots unchanged, per **webview-local-resource-roots-setter-refuses-unparseable-whole-values** (MUST) — a stricter rule than the per-element drop above, applied here because narrowing file access silently is a materially different risk from silently keeping it.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `presenter` | `any ExtensionWebviewPresenting` | none (required) | Puts a `createWebviewPanel` request on screen, or answers `nil` when no window is open. |
| `notImplementedLedger` | `NotImplementedLedger` | none (required) | Shared record of every webview member this host reaches for but does not honor. |
| `extensionIdentifier` | `String` | none (required) | The extension this adaptor instance belongs to; stamped on every ledger row and error log line. |
| `extensionDirectory` | `URL` | none (required) | This extension's install directory; the first entry in the default `localResourceRoots`. |
| `workspaceRoots` | `(any ExtensionWorkspaceRoots)?` | none (required, nullable) | Read fresh on every `createWebviewPanel` call to append the open project's folders to the default resource roots; `nil` when there is no workspace concept for this host. |

## Deep Linking

Not applicable: `MainThreadWebviews.swift` defines no URL, route, or navigable destination of its own — `asWebviewUri` mints an in-process `agentic-webview://` resource URL for a webview's own page to load, not a link the host navigates to.

## Localization

`MainThreadWebviews` raises and logs hardcoded English string literals; none carries a localization key, `String(localized:)` call, or String Catalog entry. Every raised message reaches the extension as a thrown JavaScript error, so an extension author sees the literal English text regardless of locale; every logged message reaches only the host's own log.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `vscode.window.createWebviewPanel is unavailable: this extension's host has been torn down.` | Raised by `createWebviewPanel` after the adaptor is disposed. |
| (none — literal only) | `vscode.window.createWebviewPanel's first argument must be a view type string.` | Raised when the first argument is missing or not a string. |
| (none — literal only) | `vscode.window.createWebviewPanel's second argument must be a title string.` | Raised when the second argument is missing or not a string. |
| (none — literal only) | `vscode.window.createWebviewPanel could not open a panel for view type '<viewType>': this app's windows belong to open projects, and none is open.` | Raised when the presenter has nowhere to put the panel. |
| (none — literal only) | `vscode.window.createWebviewPanel could not build a panel object for view type '<viewType>'.` | Raised when a presented panel could not be given a JavaScript object. |
| (none — literal only) | `vscode.window.registerWebviewPanelSerializer is unavailable: this extension's host has been torn down.` | Raised by `registerWebviewPanelSerializer` after disposal. |
| (none — literal only) | `vscode.window.registerWebviewPanelSerializer's first argument must be a view type string.` | Raised when the first argument is not a string. |
| (none — literal only) | `vscode.window.registerWebviewPanelSerializer's second argument must be an object with a deserializeWebviewPanel(panel, state) method.` | Raised when the second argument lacks a callable `deserializeWebviewPanel`. |
| (none — literal only) | `vscode.window.registerWebviewViewProvider is unavailable: this extension's host has been torn down.` | Raised by `registerWebviewViewProvider` after disposal. |
| (none — literal only) | `vscode.window.registerWebviewViewProvider's first argument must be a view id string.` | Raised when the first argument is not a string. |
| (none — literal only) | `vscode.window.registerWebviewViewProvider's second argument must be an object with a resolveWebviewView(webviewView, context, token) method.` | Raised when the second argument lacks a callable `resolveWebviewView`. |
| (none — literal only) | `vscode.Webview.asWebviewUri needs a Uri.` | Raised when `asWebviewUri`'s argument is missing or unparseable. |
| (none — literal only, log only) | `<extension> asked for a webview panel of type <viewType>, but there is no window to put it in` | Logged at error level alongside the "no window open" raise. |
| (none — literal only, log only) | `A panel of view type <viewType> for <extension> could not be given a JavaScript object; it was closed again` | Logged at error level alongside the "could not build a panel object" raise. |
| (none — literal only, log only) | `The <panel-or-view kind> <identifier> was closed before <extension> could fill it; it is not handed over` | Logged at notice level by `logRefusedHandover`. |
| (none — literal only, log only) | `<extension> registered a second webview panel serializer for view type <viewType>; the later one wins` | Logged at error level on a duplicate serializer registration. |
| (none — literal only, log only) | `<extension> registered a second webview view provider for view id <viewID>; the later one wins` | Logged at error level on a duplicate provider registration. |
| (none — literal only, log only) | `<extension>'s deserializeWebviewPanel threw for view type <viewType>: <reason>` / `could not be invoked for view type <viewType>` | Logged at error level on `restore`'s throw/unavailable outcomes. |
| (none — literal only, log only) | `<extension>'s resolveWebviewView threw for view id <viewID>: <reason>` / `could not be invoked for view id <viewID>` | Logged at error level on `resolveWebviewView`'s throw/unavailable outcomes. |

## Accessibility Options

Not applicable: `MainThreadWebviews.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own; every visual concern belongs to the presenter and the pane's own view controller.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; `createWebviewPanel`, `registerWebviewPanelSerializer`, `registerWebviewViewProvider`, `restore`, and `resolveWebviewView` are always available once a `MainThreadWebviews` is constructed.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; its only telemetry-adjacent output is the `OSLog` lines covered under Logging and the `NotImplementedLedger` rows covered under Behavioral Requirements, both diagnostic rather than analytics events.

## Privacy

- **Data collected**: `MainThreadWebviews` collects no data of its own; `panels` holds, for each live panel, the extension-supplied panel handle and (indirectly, through the JavaScript objects built over it) the extension's `JSContext` and every callback it registered. `postMessage` payloads and posted messages pass through untouched — never copied, stored, or inspected beyond the `Any`-to-`JSValue` bridging `VSCodeAPI` performs. `NotImplementedLedger` rows carry only member-path strings and the extension identifier — no message content, no page content, no file paths beyond what an extension itself declared as a resource root.
- **Storage**: `MainThreadWebviews` itself performs no storage; `panels`, `serializers`, and `viewProviders` are in-memory only, for the adaptor's lifetime. A panel's persisted state (`WebviewPanelState`) is a collaborator's responsibility, not this file's — `restore` only reads a `state` string handed to it.
- **Transmission**: nothing here leaves the process; `postMessage`, `onDidReceiveMessage`, and every registration round-trip stay within one process between the host and a `JSContext` it owns. A webview's own page content may load resources over the `agentic-webview://` scheme or the network, but that is the page's own traffic, not this adaptor's.
- **Retention**: a panel's model and every callback it wired are retained in `panels` until `forget` runs — on disposal from either side or on `dispose()` — per **panels-dictionary-is-the-sole-strong-reference** and **dispose-clears-every-registry**.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `MainThreadWebviews` (via `Loggable`'s default, derived from the type name)

| Event | Level | Message |
|-------|-------|---------|
| `createWebviewPanel` presented against no open window | error | `<extension> asked for a webview panel of type <viewType>, but there is no window to put it in` |
| A presented panel could not be given a JavaScript object | error | `A panel of view type <viewType> for <extension> could not be given a JavaScript object; it was closed again` |
| A restored panel or contributed view could not be given a JavaScript object | error | `A restored panel of view type <viewType> could not be given a JavaScript object; it stays blank` / `The contributed view <viewID> could not be given a JavaScript object; it stays empty` |
| A hand-over panel was already closed | notice | `The <kind> <identifier> was closed before <extension> could fill it; it is not handed over` |
| A second serializer or provider registered under the same key | error | `<extension> registered a second webview panel serializer for view type <viewType>; the later one wins` / the provider equivalent |
| A registered serializer or provider has no callable method to invoke | error | `<extension> has a serializer for view type <viewType> but no deserializeWebviewPanel to call` / the provider equivalent |
| `deserializeWebviewPanel` or `resolveWebviewView` threw | error | `<extension>'s deserializeWebviewPanel threw for view type <viewType>: <reason>` / the `resolveWebviewView` equivalent |
| `deserializeWebviewPanel` or `resolveWebviewView` could not be dispatched | error | `<extension>'s deserializeWebviewPanel could not be invoked for view type <viewType>` / the `resolveWebviewView` equivalent |

No other event in this file is logged: every `createWebviewPanel`, `registerWebviewPanelSerializer`, and `registerWebviewViewProvider` argument-validation refusal is surfaced directly to the extension as a raised exception instead of being logged, per the corresponding Behavioral Requirements above.

## Platform Notes

- **SwiftUI**: not applicable to this file — `MainThreadWebviews.swift` imports `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing in this component renders a view.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWebviews.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is `@MainActor`-isolated per its class declaration; the concrete `ExtensionWebviewPanel` it addresses is an `NSViewController`-backed WebKit host outside this file's own scope.
- **Compose**: model `MainThreadWebviews` as a Kotlin `class MainThreadWebviews(...)` confined to the main dispatcher, with `panels`/`serializers`/`viewProviders` as plain `MutableMap`s guarded by that confinement (no `Mutex` needed, matching the source's own single-actor argument). The webview surface itself becomes a `WebView` (or an Android `WebView`)-backed handle conforming to a `ExtensionWebviewPanel`-equivalent interface, and the extension callback's `JSValue` becomes whatever function-reference type the host's own JavaScript engine binding exposes.
- **React/Web**: this component's own upstream is VS Code's real `MainThreadWebviews` (`mainThreadWebviewViews.ts`/`mainThreadWebviewPanels.ts`), already TypeScript, so a web port is closer to restoring the original than translating it — including its own `Disposable`-returning registration and native `Promise`-returning `postMessage`, rather than the settled-synchronously `Thenable` this host constructs by hand.
- **WinUI 3**: model `MainThreadWebviews` as a class whose every member runs on a captured `DispatcherQueue` (the `@MainActor` equivalent — WinUI 3 has no compiler-enforced actor isolation, so every entry point MUST assert `DispatcherQueue.HasThreadAccess` or marshal via `DispatcherQueue.TryEnqueue`). The webview surface is a `WebView2`-backed control; `asWebviewUri`'s custom scheme becomes a `WebView2.AddWebResourceRequestedFilter` handler keyed the same way (panel id as authority), and the extension callback becomes whatever the chosen JavaScript engine binding uses (ClearScript's `ScriptObject`/`dynamic`, or Jint's `JsValue`) standing in for `JavaScriptCore.JSValue`.

## Design Decisions

**Decision**: `panels[panel.panelID]` is the sole strong reference to an `ExtensionWebviewPanelModel`, and `forget` (dropping that dictionary entry) is what makes a disposed panel's JavaScript surface go inert, rather than a per-block `isDisposed` flag check inside every closure.
**Rationale**: a webview holds a whole web content process, so its lifetime has to be answerable in one place, not re-derived by every closure that captures the model. Making the dictionary entry the single point of truth means `dispose()`'s job is exactly "drop every entry," and every closure that captures `model` weakly (or captures `panelID` by value, per **wire-captures-the-panel-id-by-value**) simply stops finding anything to call once its entry is gone — there is no second flag that could drift out of sync with the dictionary's own state.
**Approved**: pending

**Decision**: a hand-over (`restore` or `resolveWebviewView`) whose panel is already `isDisposed` at the moment of the call is refused outright — never adopted, never wired, never handed the object — rather than adopted and immediately torn down.
**Rationale**: `onDidDispose` has already fired for a panel that closed while its extension was still waking up, so adopting it would wire a disposal callback that can never fire again: the model, the panel, its page, and the JavaScript object the extension is holding would stay alive — retained by `panels` — until the whole extension is unloaded, while the extension goes on believing it has a live panel to post messages to. Refusing leaves exactly what closing a pane should leave: nothing.
**Approved**: pending

**Decision**: an extension whose `deserializeWebviewPanel` or `resolveWebviewView` throws keeps its adopted panel; only a dispatch that could not be invoked at all (`.unavailable`) triggers `abandon`.
**Rationale**: a throw is the extension's own bug in code that already received a live, wired panel — closing that panel out from under it would compound the bug into a second failure (a pane vanishing) the extension never asked for and cannot recover from. A dispatch that could never be invoked at all never gave the extension anything to hold, so there is nothing to protect by leaving it adopted, and abandoning frees the blank pane instead of leaking it.
**Approved**: pending

**Decision**: `webview.options`'s getter answers only the roots the extension explicitly declared (omitting the field when nothing was declared), while `webview.localResourceRoots`'s getter answers the live, resolved roots.
**Rationale**: `options` is the read-modify-write surface (`vscode.d.ts:11667`) — an extension reads it, flips a field, and writes it back, and if the getter answered the *resolved* defaults, that write-back would freeze the extension directory and the workspace folders open at read time into an explicit declaration, so a workspace folder opened afterward would stop reaching the page. `localResourceRoots` has no such round trip to protect and exists specifically to answer what the panel can read from right now.
**Approved**: pending

**Decision**: `webview.localResourceRoots`'s setter refuses the whole assignment when the value cannot be parsed as a list of `Uri`s at all, while `resourceRootsField`'s array-element parsing drops only the unparseable entries of a value that *is* a list.
**Rationale**: the two failure shapes carry opposite security consequences. A value that is not a list at all (an extension bug, or a nullish assignment) refusing outright keeps the panel's current, working roots in place; substituting an empty list instead would silently revoke file access the extension never asked to give up. A list that is mostly valid dropping only its bad entries keeps as much of the extension's explicit declaration intact as can be honored, which is the opposite risk (granting less than declared, never more).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because the file's own responsibilities are limited to the five `vscode.window` webview members' argument validation, the panel-adoption lifecycle, and the JavaScript object shapes it builds; presentation is delegated to `ExtensionWebviewPresenting`, resource-root and CSP derivation to `WebviewPanelOptions`, URL scheme construction to `WebviewResourceURL`, coalesced event delivery to `ExtensionEventEmitter`, and JavaScript call/promise/disposable ceremony to `VSCodeAPI`. `unit-test-coverage` is partial: the given `MainThreadWebviewsTests.swift` suite thoroughly covers panel creation, resource-root resolution and defaulting, the accessor pairs, the message/disposal wiring, both hand-over paths and their already-closed-panel refusal, the ledger's truthy-only recording rule, and adaptor-wide teardown — but no test in the given sources exercises `registerWebviewPanelSerializer`'s or `registerWebviewViewProvider`'s duplicate-registration logging branch directly (only the malformed-registration and view-type-scoping branches), nor the `webview.localResourceRoots` setter's whole-value-refusal branch. `explicit-error-handling` is partial: every raised, rejected, or logged failure path is explicit and traceable — except **restored-state-parse-failure-signal**, where a corrupted (not merely absent) saved-state string is silently treated identically to no saved state at all, with no log line distinguishing the two. `secure-log-output` passes because no credential or secret value is ever read or logged by this file; the values logged are extension identifiers, view types and view ids, and an exception's or rejection's own `toString()`. `input-sanitization` passes: every extension-supplied argument this file accepts is type-checked before use — `viewType`/`title`/view id MUST be strings, a serializer or provider MUST be an object with a callable named method, `booleanField`/`isTruthyFlag` require an actual JavaScript boolean rather than coercing one, and `resourceRootsField` parses each declared root as a `Uri`, dropping (rather than substituting for) any entry that fails to parse. `no-hardcoded-strings` fails because every raised and logged message this file constructs directly (see Localization) is an English literal with no localization mechanism.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
