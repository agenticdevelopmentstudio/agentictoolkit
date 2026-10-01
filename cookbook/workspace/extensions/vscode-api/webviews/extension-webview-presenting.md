---
id: c4f76978-5aef-430c-a7e1-a20326da6709
title: Extension Webview Presenting
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api/webviews/extension-webview-presenting
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The extension host''s seam for turning a vscode.window.createWebviewPanel
  request into a placed, live webview panel handle, plus the panel handle''s own
  lifecycle contract.'
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- webview
- presenter
depends-on:
- agenticdevelopercookbook://principles/fail-fast
related:
- agentictoolkit://cookbook/workspace/extensions/vscode-api/webviews/webview-panel-options
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionWebviewPresenting.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Webview/PaneWebviewPresenter.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWebviews.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/WebviewPanelOptions.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/PaneWebviewPresenterTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/MainThreadWebviewsTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Extension Webview Presenting

## Overview

This is the extension host's seam for `vscode.window.createWebviewPanel`: a one-method presenting role that turns a fully-resolved webview panel request into a live panel handle, or into nothing when there is nowhere to put one. The same component declares the request value type its method consumes and the panel handle role its method returns — three pieces that together are the whole contract between the bridge that resolves a JavaScript `createWebviewPanel` call into a request (and translates a failed placement into a raised JS exception) and whatever actually builds and places a pane. One production implementation builds a webview view controller from the request, asks an app-supplied placement step where to put it, wires the placement's `reveal`/`remove` verbs onto the panel, and reveals the panel — honoring `preserveFocus` — before returning it. This presenting role is a fifth presenter beside four others the window bridge already takes (message, quick pick, input box, and status bar item), and it alone needs a window manager and a pane tree to do its job, which is why the placement decision is a step the app supplies rather than something this role or its production implementation performs itself.

The panel handle is what a caller receives back: a stable `panelID`, a settable `panelTitle` and `html`, settable `localResourceRoots` and `options`, a read-only `state` string mirroring the webview script's own persisted state, an `onDidReceiveMessage` callback for messages the webview's script posts, an `onDidDispose` callback fired exactly once on disposal, a read-only `isDisposed` flag, a `post(message:)` method that reports whether delivery succeeded, a `reveal(preserveFocus:)` method, and a `dispose()` method. The request is the plain value the resolving bridge builds after validating and resolving a JavaScript `createWebviewPanel` call's arguments: `viewType`, `title`, `options` (see the related recipe), the already-resolved `localResourceRoots`, `preserveFocus`, and `extensionIdentifier`.

## Behavioral Requirements

- **request-value-semantics**: The request MUST be a value type with a memberwise initializer, carrying `viewType: String`, `title: String`, `options: WebviewPanelOptions`, `localResourceRoots: [URL]`, `preserveFocus: Bool`, and `extensionIdentifier: String` verbatim from the caller that built it, and MUST be safe to compare for equality and to pass across concurrency boundaries.
- **request-resolved-roots-passthrough**: `localResourceRoots` on the request MUST be the already-resolved, absolute set of directories the webview may load local resources from; the presenting role's implementation MUST pass this value through unmodified rather than re-deriving it from `options.declaredLocalResourceRoots`.
- **request-extension-attribution**: `extensionIdentifier` MUST identify which extension asked for the panel, so a caller can attribute the panel without re-deriving that fact from elsewhere.
- **presenter-main-thread-confinement**: The presenting role MUST be confined to a single, consistent thread; presenting a webview panel and every read of state it depends on MUST execute on that thread.
- **presenter-nil-on-no-placement**: Presenting a webview panel MUST return nothing when there is nowhere to place the panel (for example, no project window is open), rather than raising an error or returning a partially-placed panel.
- **presenter-single-panel-per-call**: Presenting a webview panel MUST create and return exactly one new panel per call; it MUST NOT return a panel created by a previous call.
- **presenter-wired-before-revealed**: when placement succeeds, the returned panel's placement callbacks (the pane's `reveal`/`remove` verbs) MUST be installed on the panel before the panel is revealed, so a caller-initiated reveal during that same call always has a working placement behind it.
- **presenter-reveals-once**: a successful presenting call MUST reveal the returned panel exactly once, honoring the request's `preserveFocus`, as part of the same call — never as a separate step the caller must remember to invoke.
- **presenter-failed-placement-reveals-nothing**: when placement fails and presenting a webview panel returns nothing, `reveal` MUST NOT be called on any panel.
- **panel-main-thread-confinement**: The panel handle MUST be confined to a single, consistent thread; every member MUST be usable only on that thread, matching a native UI framework's own main-thread requirement for window and view mutation.
- **panel-identity**: `panelID` MUST be a stable, get-only identifier for the panel's entire lifetime.
- **panel-title-mutation**: `panelTitle` MUST be settable, and assigning it MUST change the panel's displayed title.
- **panel-html-mutation**: `html` MUST be settable, and assigning it MUST replace the panel's rendered content.
- **panel-resource-roots-mutation**: `localResourceRoots` MUST be settable, so a webview *view* provider (which receives an already-built panel) can change which local directories the panel's scheme handler may read from after creation.
- **panel-options-mutation**: `options` MUST be settable, so `enableScripts`, `enableForms`, and `declaredLocalResourceRoots` can change after creation.
- **panel-state-readback**: `state` MUST expose the most recent state the webview's own script serialized via `vscode.setState`/`getState`, or nothing when no state has ever been set.
- **panel-message-callback**: `onDidReceiveMessage` MUST be invoked for every message the webview's script posts via `acquireVsCodeApi().postMessage`.
- **panel-dispose-callback**: `onDidDispose` MUST be invoked exactly once when the panel is disposed, whether disposal was requested by the extension (`dispose()`) or driven by the user closing the pane.
- **panel-disposed-flag**: `isDisposed` MUST become `true` once the panel is disposed and MUST remain `true` afterward, so a caller can test disposal before acting on a handle that may have gone stale — the guard the resolving bridge performs, in both its restore-after-relaunch path and its contributed-view resolution path (`resolveWebviewView`), before adopting a hand-over.
- **panel-post-message-result**: `post(message:)` MUST return `false` when the panel is disposed or the message otherwise cannot be delivered, and MUST return `true` when the message was handed to the webview successfully.
- **panel-reveal-preserve-focus**: `reveal(preserveFocus:)` MUST bring the panel's pane forward and MUST leave keyboard focus wherever it already was when `preserveFocus` is `true`.
- **panel-dispose-idempotent**: `dispose()` MUST be safe to call more than once; a second call MUST NOT remove the pane a second time or fire `onDidDispose` again.

## Appearance

Not applicable — this is a webview-panel presenting protocol and its panel handle, not a visual component.

## States

Not applicable — this is a webview-panel presenting protocol and its panel handle, not a visual component. The one runtime state machine in scope, `isDisposed`/`onDidDispose`'s one-way transition from live to disposed, is captured under Behavioral Requirements (**panel-disposed-flag**, **panel-dispose-callback**, **panel-dispose-idempotent**) rather than as a visual-state table.

## Accessibility

Not applicable — this is a webview-panel presenting protocol and its panel handle, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-webview-presenting-001 | presenter-wired-before-revealed, request-value-semantics | A request with given `viewType`/`title`/`options`/`localResourceRoots`, and a placement step that succeeds; present the webview panel. | The built panel mirrors the request's `viewType`, `title`, `options`, and `localResourceRoots` — `PaneWebviewPresenterTests.thePanelIsBuiltFromTheRequest` |
| extension-webview-presenting-002 | presenter-single-panel-per-call | A placement step that succeeds; present the webview panel. | The panel the placement step was given is the same panel instance presenting returns — `PaneWebviewPresenterTests.thePanelPlacedIsThePanelReturned` |
| extension-webview-presenting-003 | presenter-nil-on-no-placement | A placement step that fails (no project window open); present the webview panel. | Returns nothing — `PaneWebviewPresenterTests.aPlacementThatFailsAnswersNil` |
| extension-webview-presenting-004 | presenter-failed-placement-reveals-nothing | Same failing placement step; present the webview panel. | `reveal` is never called on any panel — `PaneWebviewPresenterTests.aPlacementThatFailsRevealsNothing` |
| extension-webview-presenting-005 | presenter-reveals-once, panel-reveal-preserve-focus | A request with `preserveFocus` set to a given value, and a placement step that succeeds; present the webview panel. | `reveal(preserveFocus:)` is called exactly once, carrying that same `preserveFocus` value, as part of the same presenting call — `PaneWebviewPresenterTests.theCreateCallRevealsOnceCarryingPreserveFocus` |
| extension-webview-presenting-006 | presenter-wired-before-revealed | A placement step that succeeds; present the webview panel. | The placement's `reveal`/`remove` callbacks are installed on the panel before `reveal` is called — `PaneWebviewPresenterTests.thePanelIsWiredBeforeItIsRevealed` |
| extension-webview-presenting-007 | panel-dispose-idempotent | `dispose()` called twice on the same panel | The removal callback fires only once; the second call is a no-op — `PaneWebviewPresenterTests.aSecondDisposeDoesNotRemoveTwice` |
| extension-webview-presenting-008 | panel-disposed-flag | A panel handle already marked disposed (`isDisposed == true`), handed to the restore-after-relaunch path | The hand-over is refused rather than adopted — `MainThreadWebviewsTests.restoringAPanelThatWasAlreadyClosedIsRefused` |
| extension-webview-presenting-009 | panel-disposed-flag | A panel handle that is not disposed (`isDisposed == false`), handed to `resolveWebviewView` | The hand-over succeeds and the live panel is adopted — `MainThreadWebviewsTests.resolvingAContributedViewHandsOverTheLivePanel` |

## Edge Cases

- **Null/empty input**: an empty `localResourceRoots` array on the request MUST be passed through as-is and MUST grant the resulting panel no local resource access; this is not an error condition (MUST).
- **Repeated calls**: `dispose()` called a second time on an already-disposed panel MUST be a no-op — it MUST NOT remove the pane a second time and MUST NOT fire `onDidDispose` again, per **panel-dispose-idempotent** (MUST).
- **Repeated calls**: calling `presentWebviewPanel(_:)` twice with requests carrying the same `viewType` and `title` MUST create two independent panels; this protocol performs no identity de-duplication of its own (MUST).
- **No placement available**: presenting a webview panel when there is nowhere to place a panel (no project window open) MUST return nothing and MUST NOT reveal, wire, or otherwise partially construct a panel that is then discarded, per **presenter-nil-on-no-placement** and **presenter-failed-placement-reveals-nothing** (MUST).
- **Post after disposal**: calling `post(message:)` on a disposed panel MUST return `false` rather than throwing or silently discarding the message, per **panel-post-message-result** (MUST).
- **Stale handle re-use**: a caller holding a panel handle across a user-initiated close MUST observe `isDisposed == true` before the handle is used for a hand-over (restore or `resolveWebviewView`), which is the exact guard the resolving bridge performs, per **panel-disposed-flag** (MUST).
- **Concurrent access**: because both the presenting role and the panel handle are confined to a single thread, no method of either can be called concurrently with another from a different thread — the platform's own concurrency enforcement handles this rather than either needing its own locking (MUST).

## Configuration

| Parameter | Type | Source | Effect |
|-----------|------|--------|--------|
| `viewType` | `String` | Caller (the resolving bridge, from the JavaScript `createWebviewPanel` call) | Identifies the contributed view type the panel is built for; passed through unvalidated by this seam. |
| `title` | `String` | Caller | The panel's initial displayed title. |
| `options` | `WebviewPanelOptions` | Caller | Carries `enableScripts`, `enableForms`, and `declaredLocalResourceRoots`; see the related `WebviewPanelOptions` recipe. |
| `localResourceRoots` | `[URL]` | Caller, already resolved | The absolute set of directories the built panel's webview may load local resources from. |
| `preserveFocus` | `Bool` | Caller | Honored by `reveal(preserveFocus:)` as part of the same presenting call that creates the panel. |
| `extensionIdentifier` | `String` | Caller | Identifies the requesting extension; carried on the request for attribution by callers, but not read or acted on by this component itself. |
| `place` | placement step (function) | App, supplied to the production presenting implementation | Decides where (or whether) the built panel goes in the pane tree; this step lives in the app's production presenting implementation, not in the role this recipe describes. |

## Deep Linking

Not applicable: the given source declares no URL scheme, route, or navigable destination — a webview panel's own content and its navigation are the webview's script's concern, not this presenting seam's.

## Localization

Not applicable: the given source declares no user-facing string literal of its own — `panelTitle` and `html` are supplied by the caller (the extension) verbatim and carried through unmodified.

## Accessibility Options

Not applicable: the given source performs no accessibility-tree or assistive-technology work of its own — that is `WebviewPanelViewController`'s concern, a different component.

## Feature Flags

Not applicable: the given source reads no feature-flag key and contains no conditional feature-gating logic.

## Analytics

Not applicable: the given source emits no analytics or telemetry event of its own.

## Privacy

- **Data collected**: the given source collects no data of its own; `localResourceRoots` (file-system paths) and `extensionIdentifier` are carried through as opaque values, not inspected, logged, or transformed by this file.
- **Storage**: the given source performs no storage of its own; a panel's `state` string is held only in memory by whatever conforms to `ExtensionWebviewPanel` and is not persisted by this protocol.
- **Transmission**: the given source performs no network transmission of its own.
- **Retention**: the given source retains nothing beyond the lifetime of the panel handle itself.

## Logging

Not applicable: the given source contains no logging call of its own — diagnostic logging for a refused hand-over and similar events lives in the resolving bridge, a different component.

## Platform Notes

- **SwiftUI**: this is already Swift; a SwiftUI-hosted pane tree would keep `ExtensionWebviewPresenting` and `ExtensionWebviewPanel` unchanged and replace `PaneWebviewPresenter`'s `place` closure — which currently answers with an AppKit-facing `ExtensionWebviewPlacement` of `reveal`/`remove` closures — with one that drives a `NavigationSplitView`'s selection binding instead of an `NSSplitViewItem` pane tree.
- **Compose**: model `ExtensionWebviewPresenting`/`ExtensionWebviewPanel` as a Kotlin interface pair confined to the main/UI thread (`Dispatchers.Main`, in place of `@MainActor`); `ExtensionWebviewPanelRequest` becomes an immutable `data class` (Kotlin's `Sendable`-equivalent by construction); `presentWebviewPanel` becomes a plain function returning a nullable panel interface, and `reveal`/`dispose` become functions posted to the main dispatcher rather than assumed to already run there.
- **React/Web**: model the presenter as a factory function returning a panel "handle" object (`post`, `reveal`, `dispose` methods, an `isDisposed` getter) backed by an `iframe` or a Web Component; `onDidReceiveMessage` maps to a `window.addEventListener('message', ...)` bridge scoped to that `iframe`, and `isDisposed` maps to tracking whether the backing element has been removed from the DOM.
- **AppKit / UIKit**: this is the source's own home — `PaneWebviewPresenter` and `WebviewPanelViewController` are AppKit types in the `AgenticToolkitMacOS` framework. A UIKit port would keep `ExtensionWebviewPresenting`/`ExtensionWebviewPanel` unchanged and replace the AppKit-specific pane-tree placement closure with a `UISplitViewController` detail push or a `UINavigationController` push, since UIKit has no `NSSplitViewItem`-style pane tree to place into. Both protocols are declared `@MainActor` (**presenter-main-thread-confinement**, **panel-main-thread-confinement**), matching AppKit's own main-thread requirement for window and view mutation. `ExtensionWebviewPanel` is also constrained to `AnyObject` and deliberately does not conform to `Sendable`: because it is both `@MainActor`-isolated and a class-bound protocol, the compiler already prevents any instance from crossing an actor boundary, making a `Sendable` conformance unnecessary (**panel-not-sendable-by-design**).
- **WinUI 3**: model `ExtensionWebviewPresenting` as a C# interface `IExtensionWebviewPresenting` with `IExtensionWebviewPanel? PresentWebviewPanel(ExtensionWebviewPanelRequest request)`; `@MainActor` isolation becomes confinement to the UI thread, enforced by asserting `DispatcherQueue.GetForCurrentThread().HasThreadAccess` at entry. `ExtensionWebviewPanelRequest` becomes an immutable `record ExtensionWebviewPanelRequest(string ViewType, string Title, WebviewPanelOptions Options, IReadOnlyList<Uri> LocalResourceRoots, bool PreserveFocus, string ExtensionIdentifier)`. `IExtensionWebviewPanel` wraps a `Microsoft.UI.Xaml.Controls.WebView2` hosted inside a `TabViewItem`: `Html` is a settable `string` property whose setter calls `WebView2.NavigateToString(...)`; `OnDidReceiveMessage` is an `event Action<object>?` wired to `WebView2.WebMessageReceived`; `Reveal(bool preserveFocus)` selects the hosting `TabViewItem` in the owning `TabView` and conditionally calls `webView.Focus(FocusState.Programmatic)` only when `preserveFocus` is `false`; and `Dispose()` implements `IDisposable`, removing the `TabViewItem` from the `TabView.TabItems` collection and calling `WebView2.Close()`, guarded so a second call is a no-op.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionWebviewPresenting.swift` |

## Design Decisions

**Decision**: `ExtensionWebviewPresenting` is a single-method protocol (`presentWebviewPanel(_:) -> (any ExtensionWebviewPanel)?`) rather than separate create/place/reveal steps or a class hierarchy.
**Rationale**: the seam mirrors the four presenters `MainThreadWindow` already takes (message, quick pick, input box, status bar item) — a webview panel needs the same all-or-nothing "build it, place it, show it, hand back a handle" contract, with a `nil` return as the seam's only failure signal, matching the fail-fast style the other four presenters already use. Keeping the AppKit-specific placement decision out of this protocol (it lives in `PaneWebviewPresenter`'s `place` closure instead) keeps the framework layer that owns the protocol free of the app's own pane-tree concerns.
**Approved**: pending

**Decision**: `ExtensionWebviewPanel` exposes `isDisposed` as a synchronously readable property rather than relying on `onDidDispose` alone.
**Rationale**: two independent call sites in `MainThreadWebviews` — `restore` after a relaunch and `resolveWebviewView` for a contributed view — need to ask, before acting, whether a panel handed back to them is still alive. A callback fired once at disposal cannot answer a question asked after the fact; only a readable flag can.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |

`separation-of-concerns` passes because the given file declares only a request value type, a panel-handle protocol, and a one-method presenting protocol — it performs no placement, no rendering, and no JavaScript-bridge work of its own; those are `PaneWebviewPresenter`'s, `WebviewPanelViewController`'s, and `MainThreadWebviews`'s jobs respectively (see Overview). `unit-test-coverage` is partial: no test file in the given sources exercises `ExtensionWebviewPresenting`/`ExtensionWebviewPanel` directly by name, since they are protocols; coverage instead comes indirectly, through `PaneWebviewPresenterTests` (exercising the production conformer) and `MainThreadWebviewsTests` (exercising fake conformers, `TestWebviewPanel`/`TestWebviewPresenter`, wired through the adaptor) — real, traceable coverage of the contract, but never a test that names the protocols themselves. `explicit-error-handling` passes because the protocol's one failure mode — nowhere to place a panel — is an explicit, documented `nil` return that `MainThreadWebviews` turns into a raised JavaScript exception; nothing is swallowed silently.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/vscode-api/webviews/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
