---
id: aa828b9b-925a-4f73-9073-12aab359aba6
title: VS Code Webviews Bridge
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api/webviews/main-thread-webviews
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
depends-on: []
related:
- agentictoolkit://cookbook/workspace/extensions/vscode-api/webviews/extension-webview-presenting
- agentictoolkit://cookbook/workspace/extensions/host/extension-event
- agentictoolkit://cookbook/workspace/extensions/vscode-api/webviews/webview-panel-options
- agentictoolkit://cookbook/workspace/extensions/vscode-api/webviews/webview-resource-url
- agentictoolkit://cookbook/workspace/extensions/vscode-api/commands/main-thread-commands
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

# VS Code Webviews Bridge

## Overview

This adaptor is the extension host's `vscode.window` surface for webviews:
`createWebviewPanel`, `registerWebviewPanelSerializer`,
`registerWebviewViewProvider`, plus two hand-over entry points, `restore` and
`resolveWebviewView`, that the host's extension installer calls when a pane
the project remembers is rebuilt before its extension has necessarily
activated. The adaptor MUST run confined to a single, serialized execution
context, matching every other such adaptor and the extension host itself,
because the values it holds are not safe to share across concurrent contexts
and every member below is invoked on the thread that made the call.

The panel record is the sole strong reference keeping a panel's
script-exposed callbacks alive — adopting, abandoning, wiring, and
forgetting a panel are the four moves of that lifecycle, and every path
through `createWebviewPanel`, `restore`, and `resolveWebviewView` funnels
through them. The serializer registry and the view-provider registry are
token-guarded — each entry pairs a registration token with the registered
callback — so that a stale disposable captured before a later registration
under the same key cannot unregister it. The workspace roots provider is
read fresh on every `createWebviewPanel` call rather than snapshotted at
construction, mirroring the workspace adaptor's own stated rule, so a
project folder opened after the extension activated is still a resource
root a new panel can read from. The shared not-implemented ledger records
every VS Code webview member this host does not honor — `enableCommandUris`,
`portMapping`, `WebviewPanel.iconPath`, `onDidChangeViewState`/
`onDidChangeVisibility` subscriptions, and a contributed view's
`resolveContext.state` — so the extension report (task 5.8) can name what
an extension quietly lost rather than an operator discovering it by
accident.

The adaptor collaborates with, but does not itself implement: the presenter
(puts a panel on screen; this adaptor never touches the platform's own
rendering layer directly), the options resolver (resolves
declared-versus-default `localResourceRoots` and builds the floor
Content-Security-Policy — the CSP construction is a collaborator fact this
adaptor never invokes), the resource URL builder (mints the
`agentic-webview://<panelID>/<path>` scheme URL `asWebviewUri` returns, with
the containment check against `localResourceRoots` happening elsewhere, in a
resource scheme handler, not in this adaptor), the coalescing event emitter
(the pub/sub relay behind `onDidReceiveMessage`, `onDidDispose`,
`onDidChangeViewState`/`onDidChangeVisibility`, every one of them built for
synchronous, same-turn delivery), the shared script call/promise/disposable
ceremony every such adaptor uses instead of its own copy, and the shared
not-implemented ledger (the deduplicated-by-member-path record described
above).

## Behavioral Requirements

- **thread-confined-access**: The adaptor MUST be confined to a single,
  serialized execution context; every stored value read and write and every
  method body MUST execute on that same confined context.
- **init-requires-every-collaborator-with-no-default**: Constructing the
  adaptor MUST take the presenter, the not-implemented ledger, the extension
  identifier, the extension directory, and the workspace roots provider as
  five required parameters with no default value.
- **workspace-roots-are-read-fresh-not-snapshotted**: Resolving local
  resource roots and building a create-webview-panel request MUST read the
  workspace roots provider's own workspace-root locations at call time, MUST
  NOT cache them at construction, so a workspace folder opened after
  construction is reflected in the very next `createWebviewPanel` call's
  resolved roots.
- **panel-record-is-the-sole-strong-reference**: The panel record MUST be
  the only strong reference this adaptor (or the script objects it builds)
  holds to a panel model; forgetting a panel (removing its entry) MUST be
  what makes every callback captured by that model's script objects inert.
- **create-panel-raises-on-torn-down-adaptor**: `createWebviewPanel` MUST be
  built with the raised-exception teardown response, and a call after the
  adaptor has been torn down MUST raise `"vscode.window.createWebviewPanel
  is unavailable: this extension's host has been torn down."` rather than
  returning `undefined` or a non-functional panel object.
- **create-panel-requires-string-view-type**: Handling a create-webview-panel
  call MUST raise `"vscode.window.createWebviewPanel's first argument must
  be a view type string."` and present nothing when the first argument is
  missing or not a string.
- **create-panel-requires-string-title**: Handling a create-webview-panel
  call MUST raise `"vscode.window.createWebviewPanel's second argument must
  be a title string."` and present nothing when the second argument is
  missing or not a string.
- **create-panel-parses-preserve-focus-from-third-argument**: Handling a
  create-webview-panel call MUST derive `preserveFocus` from the third
  argument (or treat it as absent when no third argument was supplied),
  reading only that value's `preserveFocus` field and ignoring any
  `ViewColumn` the third argument might otherwise represent — this app's
  panes are a user-arranged tree with no numbered column for a `ViewColumn`
  to select.
- **create-panel-parses-options-from-fourth-argument**: Handling a
  create-webview-panel call MUST derive `WebviewPanelOptions` from the
  fourth argument (or treat it as absent when no fourth argument was
  supplied).
- **create-panel-resolves-roots-before-presenting**: Handling a
  create-webview-panel call MUST compute `localResourceRoots` by resolving
  local resource roots for the given options and include the
  already-resolved list in the request handed to the presenter, so the
  presenter never has to know the extension's install directory or the
  open workspace folders itself.
- **create-panel-raises-when-no-window-is-open**: Handling a
  create-webview-panel call MUST log, at error level, that the extension
  asked for a panel with no window to put it in, and MUST raise
  `"vscode.window.createWebviewPanel could not open a panel for view type
  '<viewType>': this app's windows belong to open projects, and none is
  open."` when the presenter answers no request.
- **create-panel-closes-and-raises-when-the-panel-object-cannot-be-built**:
  when building the panel object fails after a presenter has already put a
  panel on screen, handling a create-webview-panel call MUST dispose the
  just-presented panel, MUST log the failure at error level, and MUST raise
  `"vscode.window.createWebviewPanel could not build a panel object for
  view type '<viewType>'."`, leaving no pane the extension can never
  address.
- **create-panel-adopts-only-on-full-success**: Handling a
  create-webview-panel call MUST adopt the model only after both presenting
  and building the panel object succeed, and MUST return the built panel
  object as the member's result.
- **panel-model-events-use-immediate-delivery**: Every event emitter a panel
  model constructs (for `onDidReceiveMessage`, `onDidDispose`, and the
  shared view-state-change emitter behind `onDidChangeViewState`/
  `onDidChangeVisibility`) MUST be built for synchronous, same-turn
  delivery, so a page's `postMessage` reaches the extension's
  `onDidReceiveMessage` listener in the same turn it was sent.
- **view-state-changes-are-real-but-never-fired**: The shared
  view-state-change emitter MUST remain a genuinely subscribable emitter (an
  extension's `Disposable` from subscribing to it MUST be valid and
  disposable), but nothing in this adaptor MUST ever fire it, because panes
  here do not yet report view-state transitions.
- **wire-captures-the-panel-id-by-value**: Wiring a panel's `onDidDispose`
  callback MUST capture the panel id by copy at wiring time, MUST NOT read
  the model's own panel id after forgetting has removed the model from the
  panel record.
- **disposal-fires-before-forgetting**: The `onDidDispose` callback that
  wiring installs MUST mark the model disposed and fire its disposal event
  before forgetting the panel, so every listener the extension registered
  on `onDidDispose` is still present in the model's disposal registrations
  at the moment it fires.
- **abandon-is-only-for-an-undelivered-hand-over**: Abandoning a model MUST
  happen only when a hand-over (`restore` or `resolveWebviewView`) adopted a
  model and then could not deliver an object to the extension at all (a
  dispatch result of "unavailable"); it MUST null the model's
  `onDidDispose` and `onDidReceiveMessage` callbacks and forget the panel,
  and MUST NOT happen for a hand-over whose extension received the object
  and then threw — a throwing extension MUST keep its panel.
- **refused-hand-over-is-logged-not-silent**: Logging a refused hand-over
  MUST log, at notice level, that the panel or view named by the identifier
  was closed before the extension could fill it and is not handed over,
  whenever `restore` or `resolveWebviewView` refuses an already-disposed
  panel.
- **register-serializer-raises-on-torn-down-adaptor**:
  `registerWebviewPanelSerializer` MUST be built with the raised-exception
  teardown response, raising `"vscode.window.registerWebviewPanelSerializer
  is unavailable: this extension's host has been torn down."` after the
  adaptor is torn down.
- **register-serializer-requires-string-view-type**: Handling a
  register-webview-panel-serializer call MUST raise
  `"vscode.window.registerWebviewPanelSerializer's first argument must be a
  view type string."` when the first argument is missing or not a string.
- **register-serializer-requires-a-callable-deserialize-method**: Handling a
  register-webview-panel-serializer call MUST test the second argument for
  being an object with a callable `deserializeWebviewPanel` property, and
  MUST raise `"vscode.window.registerWebviewPanelSerializer's second
  argument must be an object with a deserializeWebviewPanel(panel, state)
  method."` when either check fails — checking the object alone (being an
  object, true of `{}`) would let a mistyped method name register
  successfully and silently restore nothing, months later.
- **register-serializer-last-registration-wins-and-is-logged**: Handling a
  register-webview-panel-serializer call MUST replace any existing
  registration for the view type with the new one (last write wins,
  matching upstream's own behavior) and MUST log the replacement at error
  level when one already existed.
- **register-serializer-returns-a-token-guarded-disposable**: Handling a
  register-webview-panel-serializer call MUST mint a fresh registration
  token and return a `Disposable` whose `dispose()` removes the
  registration only when the live entry's token still equals the token
  captured at registration time.
- **has-serializer-false-when-disposed-or-missing**: Checking whether a
  serializer is registered MUST answer `false` when the adaptor is torn
  down, and MUST otherwise answer whether a registration exists for that
  view type.
- **restore-refuses-when-disposed-or-unregistered**: `restore` MUST return
  `false` immediately, with no side effect, when the adaptor is torn down
  or no serializer is registered for the view type.
- **restore-refuses-an-already-closed-panel**: `restore` MUST return
  `false` and MUST log a refused hand-over — MUST NOT adopt the model, MUST
  NOT wire `onDidDispose`/`onDidReceiveMessage` on the panel, MUST NOT call
  `deserializeWebviewPanel` — when the handed-over panel is already
  disposed at the moment of the call.
- **restore-refuses-an-uncallable-deserializer**: `restore` MUST log at
  error level and return `false` when the registered serializer has no
  callable `deserializeWebviewPanel` at call time.
- **restore-closes-nothing-when-the-panel-object-cannot-be-built**:
  `restore` MUST log at error level and return `false`, leaving the
  handed-over panel blank (and MUST NOT dispose it), when building a panel
  object for the restored panel fails.
- **restore-adopts-before-calling-deserialize**: `restore` MUST adopt the
  model before invoking `deserializeWebviewPanel`, so the panel is already
  wired for messages and disposal by the time the extension's own callback
  runs.
- **restore-parses-saved-state-as-json-or-undefined**: Parsing the restored
  state value MUST parse a non-absent saved state string as JSON and pass
  the decoded value to `deserializeWebviewPanel`, and MUST pass `undefined`
  — never JavaScript `null` — when the saved state is absent, because an
  extension's `state ?? defaults` and `if (state === undefined)` read the
  two differently.
- **restore-returns-true-on-successful-deserialize**: `restore` MUST return
  `true` when dispatching `deserializeWebviewPanel` answers "returned".
- **restore-keeps-the-panel-adopted-when-deserialize-throws**: `restore`
  MUST log the exception at error level and return `false`, but MUST NOT
  abandon the model — it MUST stay adopted — when dispatching
  `deserializeWebviewPanel` answers "threw".
- **restore-abandons-only-on-dispatch-unavailable**: `restore` MUST abandon
  the model, log at error level, and return `false` when dispatching
  `deserializeWebviewPanel` answers "unavailable".
- **register-view-provider-mirrors-the-serializer-contract**: Handling a
  register-webview-view-provider call MUST apply the same torn-down check,
  string-view-id check, and object-with-callable-`resolveWebviewView`-method
  check that handling a register-webview-panel-serializer call applies to
  view types and `deserializeWebviewPanel`, with the corresponding messages
  naming `vscode.window.registerWebviewViewProvider`, a view id string, and
  a `resolveWebviewView(webviewView, context, token)` method.
- **register-view-provider-drops-the-retain-context-hint-silently**:
  Handling a register-webview-view-provider call MUST read and discard the
  third argument's `webviewOptions.retainContextWhenHidden` field without
  recording a not-implemented-ledger row, because every pane here already
  retains its view regardless of front-most state, so a ledger row would
  report a limitation that does not exist.
- **register-view-provider-does-not-throw-on-duplicate**: Handling a
  register-webview-view-provider call MUST NOT raise or refuse a second
  registration for a view id already registered; it MUST log the
  replacement at error level and let the later registration win,
  deliberately diverging from upstream VS Code's throw — the "second"
  registration here is typically a post-reload registration, and honoring
  the app's earlier registration over the extension's would wire a live
  pane to a dead script context.
- **has-view-provider-false-when-disposed-or-missing**: Checking whether a
  view provider is registered MUST answer `false` when the adaptor is torn
  down, and MUST otherwise answer whether a registration exists for that
  view id.
- **resolve-view-refuses-when-disposed-or-unregistered**:
  `resolveWebviewView` MUST return `false` immediately when the adaptor is
  torn down or no provider is registered for the view id.
- **resolve-view-refuses-an-already-closed-panel**: `resolveWebviewView`
  MUST refuse (return `false`, log a refused hand-over, adopt nothing) a
  panel whose disposal has already happened, mirroring
  **restore-refuses-an-already-closed-panel** exactly.
- **resolve-context-state-is-always-undefined-and-ledgered**: Building the
  resolve context value MUST build a `WebviewViewResolveContext` whose
  `state` field is always `undefined`, and MUST record a
  not-implemented-ledger row for `vscode.WebviewViewResolveContext.state`
  the first time it is read, because a contributed view's state does not
  persist across a quit the way a serializer-backed panel's does.
- **resolve-view-token-never-cancels**: Building the never-cancelled
  cancellation token MUST return a `CancellationToken` whose
  `isCancellationRequested` is always `false` and whose
  `onCancellationRequested` returns a real, never-fired `Disposable`; this
  degraded argument MUST NOT be recorded in the ledger, unlike a genuinely
  absent capability, because it is a real (if permanently unfired) token
  rather than a missing member.
- **resolve-view-returns-true-on-successful-resolve**: `resolveWebviewView`
  MUST return `true` when dispatching `resolveWebviewView` (the extension's
  own provider method) answers "returned", and MUST log-and-return-`false`
  without abandoning on "threw", matching `restore`'s throw handling.
- **resolve-view-abandons-only-on-dispatch-unavailable**:
  `resolveWebviewView` MUST abandon the model, log at error level, and
  return `false` when dispatching the provider's `resolveWebviewView`
  answers "unavailable".
- **boolean-field-requires-an-actual-boolean**: Reading a boolean field MUST
  answer absent for any value that is not a boolean (no truthy coercion of
  a number, string, or object).
- **is-truthy-flag-requires-boolean-true**: Reading a truthy flag MUST
  answer `true` only when the value is a boolean equal to `true`; every
  other value, including a truthy non-boolean, MUST answer `false`.
- **resource-roots-field-distinguishes-absent-from-empty**: Parsing the
  declared resource-roots field MUST answer absent when the value is
  missing, `undefined`, or `null` (letting the options resolver's own
  extension-directory-plus-workspace default apply), and MUST answer an
  empty list when the value is an explicit, empty array (renouncing every
  default root).
- **resource-roots-field-drops-unparseable-entries**: Parsing the declared
  resource-roots field MUST drop any array element that does not parse as
  a `Uri`, rather than substituting a default for the whole list, because a
  partially-unreadable declared list is still the extension's explicit
  declaration.
- **ledger-records-a-reach-only-when-truthy-or-non-empty**: Parsing options
  MUST record a `vscode.WebviewOptions.enableCommandUris` ledger row only
  when that field is present and truthy, and a
  `vscode.WebviewOptions.portMapping` row only when that field is a
  non-empty array; an explicit `false` or `[]` MUST record nothing, because
  a decline is not a reach for something missing.
- **panel-webview-getter-builds-a-fresh-object-every-access**: The panel
  object's `webview` readonly property MUST construct a new `Webview`
  script object on every access, MUST NOT cache one on the model, honoring
  the no-capture contract that nothing stores a script value or script
  execution context on the panel model.
- **panel-title-is-an-accessor-pair-over-the-panel**: The panel object's
  `title` accessor pair MUST read and write the panel's own title directly,
  with no local cache.
- **panel-options-getter-answers-fixed-values**: The panel object's
  `options` readonly property MUST always answer
  `{retainContextWhenHidden: true, enableFindWidget: false}`, regardless of
  what the extension requested at creation.
- **panel-icon-path-is-write-only-into-the-ledger**: The panel object's
  `iconPath` getter MUST always answer `undefined`/`null`; its setter MUST
  record a `vscode.WebviewPanel.iconPath` ledger row only when assigned a
  non-`undefined`, non-`null` value.
- **panel-view-column-is-always-undefined**: The panel object's
  `viewColumn` readonly property MUST always answer `undefined`, with no
  ledger row, since there is no numbered column for it to name.
- **panel-active-and-visible-mirror-is-disposed**: The panel object's
  `active` and `visible` readonly properties MUST both answer whether the
  panel is not disposed, an acknowledged approximation that never corrects
  itself while a panel is open, because `onDidChangeViewState` never fires.
- **panel-view-state-subscription-is-ledgered-every-call**: The panel
  object's `onDidChangeViewState` method MUST record a
  `vscode.WebviewPanel.onDidChangeViewState` ledger row on every call
  before subscribing the listener to the shared view-state-change emitter.
- **panel-reveal-reads-its-second-argument-as-preserve-focus**: The panel
  object's `reveal` method MUST read its second argument as
  `preserveFocus` (defaulting to `false`), MUST ignore its first argument
  (the dropped `ViewColumn`), and MUST reveal the panel with that value.
- **panel-dispose-delegates-to-the-underlying-panel**: The panel object's
  `dispose` method MUST dispose the underlying panel and rely on that
  call's own idempotence.
- **view-title-mirrors-the-panels-title**: The webview-view object's
  `title` accessor pair MUST read and write the panel's own title,
  answering the pane's current chrome name rather than `undefined`.
- **view-description-and-badge-are-write-only-into-the-ledger**: The
  webview-view object's `description` and `badge` accessor pairs MUST both
  have no-op getters (always `undefined`/`null`) and setters that record a
  `vscode.WebviewView.description` or `vscode.WebviewView.badge` ledger row
  only for a non-`undefined`, non-`null` assigned value.
- **view-has-no-dispose-method**: The webview-view object MUST NOT expose a
  `dispose` method, matching upstream's `WebviewView`, because a
  contributed view's lifetime belongs to its manifest-declared pane, not to
  the extension.
- **view-visible-mirrors-is-disposed**: The webview-view object's `visible`
  readonly property MUST answer whether the panel is not disposed.
- **view-visibility-subscription-is-ledgered-every-call**: The webview-view
  object's `onDidChangeVisibility` method MUST record a
  `vscode.WebviewView.onDidChangeVisibility` ledger row on every call
  before subscribing to the shared view-state-change emitter.
- **view-show-reads-its-first-argument-as-preserve-focus**: The
  webview-view object's `show` method MUST read its first argument as
  `preserveFocus` (there being no `ViewColumn` to occupy that position for
  a contributed view).
- **webview-html-accessor-round-trips-through-the-panel**: The webview
  object's `html` accessor pair MUST read and write the panel's own HTML
  directly; assigning it MUST reload the page (the panel's own
  responsibility, not this adaptor's).
- **webview-csp-source-is-scheme-and-panel-id**: The webview object's
  `cspSource` readonly property MUST answer `"<scheme>://<panelID>"` using
  the resource URL builder's own scheme.
- **webview-as-webview-uri-requires-a-uri-argument**: The webview object's
  `asWebviewUri` method MUST raise `"vscode.Webview.asWebviewUri needs a
  Uri."` when its argument is missing or does not parse as a `Uri`, and
  otherwise MUST build the result via the resource URL builder, with no
  containment check performed at build time.
- **webview-post-message-resolves-false-without-posting-when-disposed**:
  The webview object's `postMessage` method MUST resolve its returned
  promise with `false` — without posting to the panel at all — when the
  model is already gone or disposed.
- **webview-post-message-resolves-the-panels-own-boolean**: When not
  disposed, `postMessage` MUST post the message — converted to its native
  representation, substituting a null placeholder when the message itself
  is absent — to the panel, and MUST resolve the returned promise with
  that call's own boolean result.
- **webview-on-did-receive-message-wraps-the-messages-emitter**: The
  webview object's `onDidReceiveMessage` method MUST subscribe the given
  listener to the model's messages emitter, delivered via the same-turn
  immediate window per **panel-model-events-use-immediate-delivery**.
- **webview-options-getter-omits-undeclared-roots**: The webview object's
  `options` getter MUST include `localResourceRoots` in its answer only
  when the panel's declared local resource roots are non-absent; it MUST
  omit the field entirely — not answer an empty array — when nothing was
  ever declared, matching `vscode.d.ts`'s optional-until-set semantics.
- **webview-options-setter-re-resolves-live-roots**: The webview object's
  `options` setter MUST re-parse the assigned value, MUST assign the
  result to the panel's own options, and MUST also recompute and assign the
  panel's live local resource roots by resolving them again, so writing
  `options` re-resolves the live roots against the same
  extension-directory-plus-workspace defaulting used at creation.
- **webview-local-resource-roots-getter-reads-live-roots**: The webview
  object's `localResourceRoots` getter MUST read the panel's own resolved,
  live roots directly, distinct from `options.localResourceRoots`'s
  declared-only view.
- **webview-local-resource-roots-setter-refuses-unparseable-whole-values**:
  The webview object's `localResourceRoots` setter MUST be a no-op —
  leaving the panel's live roots unchanged — when the assigned value cannot
  be parsed as a list of `Uri`s at all (including `undefined`/`null`), a
  deliberate divergence from the resource-roots field's per-element-drop
  behavior, reasoned around the asymmetric security consequence of
  silently revoking file access versus silently keeping it.
- **install-accessor-and-getter-delegate-to-main-thread-window**: Installing
  a property accessor or getter on a webview-related object MUST reuse the
  shared window adaptor's own property-installation helpers rather than
  duplicating property-descriptor logic.
- **dispose-is-idempotent**: Disposing the adaptor MUST be guarded against
  re-entry and MUST do nothing on a second call.
- **dispose-nulls-callbacks-before-disposing-each-panel**: Disposing the
  adaptor, for every live panel, MUST null `onDidDispose` and
  `onDidReceiveMessage` before disposing the panel and removing its
  listeners, so a mid-teardown callback cannot fire into a
  half-torn-down script context.
- **dispose-clears-every-registry**: Disposing the adaptor MUST clear the
  panel record, the serializer registry, and the view-provider registry
  entirely, so checking for a serializer or a view provider stops claiming
  any view type or view id afterward.
- **dispose-does-not-clear-on-removal-requested**: Disposing the adaptor
  MUST NOT touch a panel's own removal-requested callback (the app's own
  pane-placement callback, not this adaptor's), at the stated cost that a
  reconcile pass without a serializer hand-off loses the open pane, unlike
  VS Code's own reload-through-serializer behavior for that case.
- **logging-conformance**: The adaptor MUST participate in the host's
  logging convention, exposing a logger built from its own name.
- **restored-state-parse-failure-signal**: NEEDS REVIEW: Not implemented in
  source. Parsing the restored state value parses a non-absent saved state
  string as JSON with a best-effort decode, and a parse failure falls into
  the same branch as an absent state, so a corrupt saved-state string
  reaches `deserializeWebviewPanel` as `undefined` with no log line and no
  error, indistinguishable from a panel that never called `setState`. What
  is missing: whether an unparseable saved state must be logged, surfaced
  to the extension, or deliberately treated as absent.

## Appearance

Not applicable — this is the extension host's `vscode.window` webview adaptor, not a visual component.

## States

Not applicable — this is the extension host's `vscode.window` webview adaptor, not a visual component. Its only lifecycle-shaped behavior is each panel's adopted-versus-forgotten and disposed-versus-live status, captured under Behavioral Requirements (`panel-record-is-the-sole-strong-reference`, `disposal-fires-before-forgetting`, `dispose-is-idempotent`) rather than as a visual-state table.

## Accessibility

Not applicable — this is the extension host's `vscode.window` webview adaptor, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| main-thread-webviews-001 | create-panel-requires-string-view-type | `vscode.window.createWebviewPanel(42, 'T', {})` — first argument is a number, not a string | The call throws synchronously and the presenter receives no request |
| main-thread-webviews-002 | create-panel-raises-when-no-window-is-open | `createWebviewPanel('t', 'T', {})` with the presenter's `canPresent` set `false` | The call throws synchronously and the presenter records exactly one request (the request was made and refused, not skipped) |
| main-thread-webviews-003 | create-panel-resolves-roots-before-presenting, resource-roots-field-distinguishes-absent-from-empty | `createWebviewPanel('t', 'T', {}, {})` with no `localResourceRoots` declared, extension directory and one workspace root both set | The presenter's request carries `localResourceRoots == [extensionDirectory] + [workspaceRoot]` |
| main-thread-webviews-004 | resource-roots-field-distinguishes-absent-from-empty | `createWebviewPanel('t', 'T', {}, {localResourceRoots: []})` | The presenter's request carries an empty `localResourceRoots`, with no fallback to the default |
| main-thread-webviews-005 | panel-reveal-reads-its-second-argument-as-preserve-focus | `panel.reveal(undefined, true)` then `panel.reveal()` on the same panel object | The reveal calls are recorded as `[true, false]`, in that order |
| main-thread-webviews-006 | webview-as-webview-uri-requires-a-uri-argument | `panel.webview.asWebviewUri(vscode.Uri.file('/tmp/mtw-media/app.css'))` | The returned string equals the resource URL builder's own result for that file and the panel's id |
| main-thread-webviews-007 | webview-post-message-resolves-false-without-posting-when-disposed | `panel.dispose()` from outside the script, then `webview.postMessage({})` on the same, now-disposed panel's `webview` handle | The promise resolves `false` and no post is ever attempted on the panel |
| main-thread-webviews-008 | webview-options-getter-omits-undeclared-roots, webview-options-setter-re-resolves-live-roots | Read `panel.webview.options.localResourceRoots` with none declared, then read-modify-write `options` back with `enableScripts: true` | `localResourceRoots` on the read object is undefined; after the write-back the live panel's resolved roots still contain both the extension directory and the workspace root |
| main-thread-webviews-009 | ledger-records-a-reach-only-when-truthy-or-non-empty | `createWebviewPanel('t', 'T', {}, {enableCommandUris: true, portMapping: [{webviewPort: 3000, extensionHostPort: 3000}]})`, then `panel.iconPath = Uri`, then `panel.onDidChangeViewState(fn)` | The ledger for the extension contains `vscode.WebviewOptions.enableCommandUris`, `vscode.WebviewOptions.portMapping`, `vscode.WebviewPanel.iconPath`, and `vscode.WebviewPanel.onDidChangeViewState` |
| main-thread-webviews-010 | ledger-records-a-reach-only-when-truthy-or-non-empty | `createWebviewPanel('t', 'T', {}, {enableCommandUris: false, portMapping: []})` | The ledger for the extension stays empty |
| main-thread-webviews-011 | dispose-nulls-callbacks-before-disposing-each-panel, dispose-clears-every-registry | Create two panels, then tear the adaptor down | Both test panels report exactly one dispose call each |
| main-thread-webviews-012 | register-serializer-returns-a-token-guarded-disposable | `registerWebviewPanelSerializer('markdown.preview', {...})`, capture the returned `Disposable`, call its `dispose()` | Checking for a `"markdown.preview"` serializer answers `true` before the dispose call and `false` after |
| main-thread-webviews-013 | register-serializer-requires-a-callable-deserialize-method | `registerWebviewPanelSerializer('t', {})` (object with no `deserializeWebviewPanel` at all) | The call throws synchronously and checking for a `"t"` serializer stays `false` |
| main-thread-webviews-014 | restore-parses-saved-state-as-json-or-undefined, restore-adopts-before-calling-deserialize | `restore(panel, viewType: "markdown.preview", state: '{"scrollTop":420}')` against a registered serializer that records the `state.scrollTop` and `panel.viewType` it receives | `deserializeWebviewPanel` sees `state.scrollTop == 420` and `panel.viewType == "markdown.preview"`; the call returns `true` |
| main-thread-webviews-015 | restore-parses-saved-state-as-json-or-undefined | `restore(panel, viewType: "markdown.preview", state: absent)` | The serializer's `state` parameter is `undefined`, not `null` |
| main-thread-webviews-016 | restore-refuses-an-already-closed-panel | `restore(alreadyDisposedPanel, viewType: "markdown.preview", state: absent)` where the test panel's `dispose()` was called before `restore` | `restore` returns `false`; the panel is never adopted — no `onDidDispose`/`onDidReceiveMessage` are wired afterward, and `deserializeWebviewPanel` is never called |
| main-thread-webviews-017 | resolve-view-refuses-an-already-closed-panel | `resolveWebviewView(alreadyDisposedPanel, viewID: "acme.view")` against a registered provider | `resolveWebviewView` returns `false`; the provider's `resolveWebviewView` is never called, mirroring vector 016 |
| main-thread-webviews-018 | resolve-view-returns-true-on-successful-resolve | `resolveWebviewView(livePanel, viewID: "acme.view")` where the provider assigns `webviewView.webview.html = '<p>...</p>'` | `resolveWebviewView` returns `true` and the live test panel's `html` equals the assigned string |
| main-thread-webviews-019 | create-panel-raises-on-torn-down-adaptor | Tear the adaptor down, then `createWebviewPanel('t', 'T', {})` on the same, now-torn-down adaptor | The call throws synchronously and the presenter records no request |
| main-thread-webviews-020 | init-requires-every-collaborator-with-no-default, create-panel-resolves-roots-before-presenting | Resolve local resource roots directly with undeclared roots, and again with an explicit empty declaration | Undeclared answers `[extensionDirectory.path, workspace.path]`; explicit `[]` answers an empty list |

## Edge Cases

- **Null/empty input**: `createWebviewPanel()` called with zero arguments MUST fail the string-view-type guard (since the first argument is missing) and MUST raise the same message as a non-string first argument, per **create-panel-requires-string-view-type** (MUST).
- **Null/empty input**: `createWebviewPanel('t')` called with only one argument MUST fail the string-title guard and raise `"vscode.window.createWebviewPanel's second argument must be a title string."`, per **create-panel-requires-string-title** (MUST).
- **Null/empty input**: `restore(panel, viewType: "x", state: absent)` where no `deserializeWebviewPanel` has been registered for `"x"` MUST return `false` with no log line at all, per **restore-refuses-when-disposed-or-unregistered** — this is the ordinary "not yet activated" case, not a failure (MUST).
- **Boundary values**: a `viewType` or `viewID` equal to the empty string is a valid string and reaches the duplicate-registration and lookup logic exactly as any other id would; nothing in this adaptor rejects it (MUST, per the string-type checks, which check only that the value is a string).
- **Boundary values**: `createWebviewPanel('t', 'T', 1)` (a `ViewColumn` number where `showOptions` is expected) is not an object, so deriving `preserveFocus` answers `false` for it and the panel is still created — a degraded argument, not a refusal (MUST, per **create-panel-parses-preserve-focus-from-third-argument**).
- **Concurrent access**: the adaptor is confined to a single execution context with no additional locking; the panel record, the serializer registry, and the view-provider registry are read and mutated only on that confined context, so there is no data race to define behavior for (MUST).
- **Concurrent access**: a pane the user closes while its extension is still waking up MUST be seen as already-disposed by whichever of `restore` or `resolveWebviewView` runs once activation completes, and MUST be refused rather than adopted, per **restore-refuses-an-already-closed-panel** / **resolve-view-refuses-an-already-closed-panel** (MUST).
- **Error states**: `deserializeWebviewPanel` or `resolveWebviewView` throwing MUST leave the model adopted (the extension keeps its panel) and MUST log the exception, while a dispatch answering "unavailable" MUST abandon the model instead, per **restore-keeps-the-panel-adopted-when-deserialize-throws** / **restore-abandons-only-on-dispatch-unavailable** (MUST).
- **Error states**: a serializer or provider registered under a mistyped or non-callable method name MUST be refused at the register call itself, never accepted and left silently unusable, per **register-serializer-requires-a-callable-deserialize-method** (MUST).
- **Cancellation or timeout**: `resolveWebviewView`'s `CancellationToken` argument never signals cancellation — `isCancellationRequested` is permanently `false` — because nothing in this host can currently interrupt a `resolveWebviewView` call in progress (fact, per **resolve-view-token-never-cancels**).
- **Missing or unreachable resource**: a `localResourceRoots` array entry that does not parse as a `Uri` is dropped from the resolved list rather than substituted with a default, per **resource-roots-field-drops-unparseable-entries** (MUST).
- **Missing or unreachable resource**: a `webview.localResourceRoots` assignment that cannot be parsed as a list of `Uri`s at all is refused outright, leaving the panel's live roots unchanged, per **webview-local-resource-roots-setter-refuses-unparseable-whole-values** (MUST) — a stricter rule than the per-element drop above, applied here because narrowing file access silently is a materially different risk from silently keeping it.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `presenter` | a presenter | none (required) | Puts a `createWebviewPanel` request on screen, or answers nothing when no window is open. |
| `notImplementedLedger` | a shared not-implemented ledger | none (required) | Shared record of every webview member this host reaches for but does not honor. |
| `extensionIdentifier` | a string | none (required) | The extension this adaptor instance belongs to; stamped on every ledger row and error log line. |
| `extensionDirectory` | a file location | none (required) | This extension's install directory; the first entry in the default `localResourceRoots`. |
| `workspaceRoots` | a workspace roots provider (optional) | none (required, nullable) | Read fresh on every `createWebviewPanel` call to append the open project's folders to the default resource roots; absent when there is no workspace concept for this host. |

## Deep Linking

Not applicable: this adaptor defines no URL, route, or navigable destination of its own — `asWebviewUri` mints an in-process `agentic-webview://` resource URL for a webview's own page to load, not a link the host navigates to.

## Localization

This adaptor raises and logs hardcoded English string literals; none carries a localization key, `String(localized:)` call, or String Catalog entry. Every raised message reaches the extension as a thrown JavaScript error, so an extension author sees the literal English text regardless of locale; every logged message reaches only the host's own log.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `vscode.window.createWebviewPanel is unavailable: this extension's host has been torn down.` | Raised by `createWebviewPanel` after the adaptor is torn down. |
| (none — literal only) | `vscode.window.createWebviewPanel's first argument must be a view type string.` | Raised when the first argument is missing or not a string. |
| (none — literal only) | `vscode.window.createWebviewPanel's second argument must be a title string.` | Raised when the second argument is missing or not a string. |
| (none — literal only) | `vscode.window.createWebviewPanel could not open a panel for view type '<viewType>': this app's windows belong to open projects, and none is open.` | Raised when the presenter has nowhere to put the panel. |
| (none — literal only) | `vscode.window.createWebviewPanel could not build a panel object for view type '<viewType>'.` | Raised when a presented panel could not be given a script object. |
| (none — literal only) | `vscode.window.registerWebviewPanelSerializer is unavailable: this extension's host has been torn down.` | Raised by `registerWebviewPanelSerializer` after teardown. |
| (none — literal only) | `vscode.window.registerWebviewPanelSerializer's first argument must be a view type string.` | Raised when the first argument is not a string. |
| (none — literal only) | `vscode.window.registerWebviewPanelSerializer's second argument must be an object with a deserializeWebviewPanel(panel, state) method.` | Raised when the second argument lacks a callable `deserializeWebviewPanel`. |
| (none — literal only) | `vscode.window.registerWebviewViewProvider is unavailable: this extension's host has been torn down.` | Raised by `registerWebviewViewProvider` after teardown. |
| (none — literal only) | `vscode.window.registerWebviewViewProvider's first argument must be a view id string.` | Raised when the first argument is not a string. |
| (none — literal only) | `vscode.window.registerWebviewViewProvider's second argument must be an object with a resolveWebviewView(webviewView, context, token) method.` | Raised when the second argument lacks a callable `resolveWebviewView`. |
| (none — literal only) | `vscode.Webview.asWebviewUri needs a Uri.` | Raised when `asWebviewUri`'s argument is missing or unparseable. |
| (none — literal only, log only) | `<extension> asked for a webview panel of type <viewType>, but there is no window to put it in` | Logged at error level alongside the "no window open" raise. |
| (none — literal only, log only) | `A panel of view type <viewType> for <extension> could not be given a script object; it was closed again` | Logged at error level alongside the "could not build a panel object" raise. |
| (none — literal only, log only) | `The <panel-or-view kind> <identifier> was closed before <extension> could fill it; it is not handed over` | Logged at notice level when logging a refused hand-over. |
| (none — literal only, log only) | `<extension> registered a second webview panel serializer for view type <viewType>; the later one wins` | Logged at error level on a duplicate serializer registration. |
| (none — literal only, log only) | `<extension> registered a second webview view provider for view id <viewID>; the later one wins` | Logged at error level on a duplicate provider registration. |
| (none — literal only, log only) | `<extension>'s deserializeWebviewPanel threw for view type <viewType>: <reason>` / `could not be invoked for view type <viewType>` | Logged at error level on `restore`'s throw/unavailable outcomes. |
| (none — literal only, log only) | `<extension>'s resolveWebviewView threw for view id <viewID>: <reason>` / `could not be invoked for view id <viewID>` | Logged at error level on `resolveWebviewView`'s throw/unavailable outcomes. |

## Accessibility Options

Not applicable: this adaptor renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own; every visual concern belongs to the presenter and the pane's own view.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; `createWebviewPanel`, `registerWebviewPanelSerializer`, `registerWebviewViewProvider`, `restore`, and `resolveWebviewView` are always available once this adaptor is constructed.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; its only telemetry-adjacent output is the diagnostic log lines covered under Logging and the not-implemented ledger rows covered under Behavioral Requirements, both diagnostic rather than analytics events.

## Privacy

- **Data collected**: this adaptor collects no data of its own; the panel record holds, for each live panel, the extension-supplied panel handle and (indirectly, through the script objects built over it) the extension's script execution context and every callback it registered. `postMessage` payloads and posted messages pass through untouched — never copied, stored, or inspected beyond the native-value bridging the shared script call ceremony performs. Not-implemented-ledger rows carry only member-path strings and the extension identifier — no message content, no page content, no file locations beyond what an extension itself declared as a resource root.
- **Storage**: this adaptor itself performs no storage; the panel record, the serializer registry, and the view-provider registry are in-memory only, for the adaptor's lifetime. A panel's persisted state is a collaborator's responsibility, not this adaptor's — `restore` only reads a state string handed to it.
- **Transmission**: nothing here leaves the process; `postMessage`, `onDidReceiveMessage`, and every registration round-trip stay within one process between the host and the script execution context it owns. A webview's own page content may load resources over the `agentic-webview://` scheme or the network, but that is the page's own traffic, not this adaptor's.
- **Retention**: a panel's model and every callback it wired are retained in the panel record until it is forgotten — on disposal from either side or on adaptor teardown — per **panel-record-is-the-sole-strong-reference** and **dispose-clears-every-registry**.

## Logging

Subsystem: the host's own logging subsystem | Category: this adaptor's own category

| Event | Level | Message |
|-------|-------|---------|
| `createWebviewPanel` presented against no open window | error | `<extension> asked for a webview panel of type <viewType>, but there is no window to put it in` |
| A presented panel could not be given a script object | error | `A panel of view type <viewType> for <extension> could not be given a script object; it was closed again` |
| A restored panel or contributed view could not be given a script object | error | `A restored panel of view type <viewType> could not be given a script object; it stays blank` / `The contributed view <viewID> could not be given a script object; it stays empty` |
| A hand-over panel was already closed | notice | `The <kind> <identifier> was closed before <extension> could fill it; it is not handed over` |
| A second serializer or provider registered under the same key | error | `<extension> registered a second webview panel serializer for view type <viewType>; the later one wins` / the provider equivalent |
| A registered serializer or provider has no callable method to invoke | error | `<extension> has a serializer for view type <viewType> but no deserializeWebviewPanel to call` / the provider equivalent |
| `deserializeWebviewPanel` or `resolveWebviewView` threw | error | `<extension>'s deserializeWebviewPanel threw for view type <viewType>: <reason>` / the `resolveWebviewView` equivalent |
| `deserializeWebviewPanel` or `resolveWebviewView` could not be dispatched | error | `<extension>'s deserializeWebviewPanel could not be invoked for view type <viewType>` / the `resolveWebviewView` equivalent |

No other event in this file is logged: every `createWebviewPanel`, `registerWebviewPanelSerializer`, and `registerWebviewViewProvider` argument-validation refusal is surfaced directly to the extension as a raised exception instead of being logged, per the corresponding Behavioral Requirements above.

## Platform Notes

- **SwiftUI**: not applicable to this file — `MainThreadWebviews.swift` imports `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing in this component renders a view.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWebviews.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is `@MainActor`-isolated per its class declaration (satisfying "thread-confined access" above because `JSValue` is not `Sendable` and JavaScriptCore always calls an installed block on the thread that made the call), matching every other `MainThread*` adaptor and `ExtensionHost` itself. The panel record is the stored property `panels: [String: ExtensionWebviewPanelModel]`; the serializer and view-provider registries are `serializers`/`viewProviders`, each entry a `SerializerRegistration`/`ViewProviderRegistration` struct pairing a `token: UUID` with a `registration: JSValue`. The workspace roots provider is the `workspaceRoots: (any ExtensionWorkspaceRoots)?` parameter. The shared not-implemented ledger is `NotImplementedLedger`. The presenter is `ExtensionWebviewPresenting`; the options resolver is `WebviewPanelOptions`; the resource URL builder is `WebviewResourceURL`; the coalescing event emitter is `ExtensionEventEmitter<Payload>`, built with `ExtensionEventImmediateWindow(delay: 0)` for the same-turn delivery every panel-model event requires. `adopt`/`abandon`/`wire`/`forget` are this type's four lifecycle methods. Handling the create-webview-panel/register-webview-panel-serializer/register-webview-view-provider calls are, respectively, `handleCreateWebviewPanel`, `handleRegisterWebviewPanelSerializer`, and `handleRegisterWebviewViewProvider`; the panel/webview/webview-view objects are built by `makePanelObject`, `makeWebviewObject`, and `makeWebviewViewObject`. Installing a property accessor or getter delegates to `MainThreadWindow`'s own static `installAccessor`/`installReadonlyGetter`. `NSNull()` is the null placeholder substituted for an absent `postMessage` payload. The concrete `ExtensionWebviewPanel` this adaptor addresses is an `NSViewController`-backed WebKit host outside this file's own scope.
- **Compose**: model this adaptor as a Kotlin `class MainThreadWebviews(...)` confined to the main dispatcher, with the panel record, the serializer registry, and the view-provider registry as plain `MutableMap`s guarded by that confinement (no `Mutex` needed, matching the source's own single-actor argument). The webview surface itself becomes a `WebView` (or an Android `WebView`)-backed handle conforming to a `ExtensionWebviewPanel`-equivalent interface, and the extension callback's `JSValue` becomes whatever function-reference type the host's own JavaScript engine binding exposes.
- **React/Web**: this component's own upstream is VS Code's real `MainThreadWebviews` (`mainThreadWebviewViews.ts`/`mainThreadWebviewPanels.ts`), already TypeScript, so a web port is closer to restoring the original than translating it — including its own `Disposable`-returning registration and native `Promise`-returning `postMessage`, rather than the settled-synchronously `Thenable` this host constructs by hand.
- **WinUI 3**: model this adaptor as a class whose every member runs on a captured `DispatcherQueue` (the `@MainActor` equivalent — WinUI 3 has no compiler-enforced actor isolation, so every entry point MUST assert `DispatcherQueue.HasThreadAccess` or marshal via `DispatcherQueue.TryEnqueue`). The webview surface is a `WebView2`-backed control; `asWebviewUri`'s custom scheme becomes a `WebView2.AddWebResourceRequestedFilter` handler keyed the same way (panel id as authority), and the extension callback becomes whatever the chosen JavaScript engine binding uses (ClearScript's `ScriptObject`/`dynamic`, or Jint's `JsValue`) standing in for `JavaScriptCore.JSValue`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWebviews.swift` |

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
**Rationale**: `options` is the read-modify-write surface (`vscode.d.ts`) — an extension reads it, flips a field, and writes it back, and if the getter answered the *resolved* defaults, that write-back would freeze the extension directory and the workspace folders open at read time into an explicit declaration, so a workspace folder opened afterward would stop reaching the page. `localResourceRoots` has no such round trip to protect and exists specifically to answer what the panel can read from right now.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/vscode-api/webviews/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
