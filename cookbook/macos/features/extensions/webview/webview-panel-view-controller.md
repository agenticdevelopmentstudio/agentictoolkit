---
id: 60b5767d-3cf5-4373-b2fc-074aa6b62fec
title: WebviewPanelViewController
domain: agentictoolkit://cookbook/macos/features/extensions/webview/webview-panel-view-controller
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AppKit view controller wrapping one extension's sandboxed WKWebView panel,
  its resource-root containment, and its postMessage/setState bridge.
platforms:
- swift
- macos
tags:
- appkit
- view-controller
- pane
- extensions
- webview
depends-on: []
related:
- agentictoolkit://cookbook/macos/features/extensions/webview/extension-webview-view-controller
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# WebviewPanelViewController

## Overview

**Source**: `packages/apple/AgenticToolkit/macOS/Features/Extensions/Webview/WebviewPanelViewController.swift`

`WebviewPanelViewController` is the `NSViewController` behind one `vscode.window.createWebviewPanel` call, or a resolved webview view: it *is* the panel an extension holds, its `title` *is* the pane's title, and disposing it *is* closing the pane. It owns a single `WKWebView`, sandboxed behind a per-panel custom URL scheme (`agentic-webview://<panel id>/...`) served only by a `WebviewSchemeHandler` that honors the extension's declared resource roots; it injects the `acquireVsCodeApi()` bridge ahead of the extension's own markup so `postMessage`/`setState` work before the extension's first script runs; and it answers both the pieces of the `vscode` webview API a presenter needs (`ExtensionWebviewPanel`) and this app's own pane-hosting protocols (`PaneTitleProviding`, `PaneContentTeardown`). A reveal or a removal request that arrives before its presenter has installed a listener is captured and replayed exactly once, because an extension's own `deserializeWebviewPanel` can call `panel.reveal()` or dispose the panel before this app has anywhere to route that call.

## Behavioral Requirements

- **panel-id-generated-at-init**: The component MUST assign `panelID` a freshly generated UUID string in `init(viewType:title:options:localResourceRoots:)`, distinct per instance.
- **init-applies-scheme-handler-and-relay**: `init(viewType:title:options:localResourceRoots:)` MUST construct the scheme handler keyed to `panelID`, seed its `localResourceRoots` and `contentSecurityPolicy` from the given `options`, and set `relay.delegate` to itself, before returning.
- **restoring-init-seeds-prior-state**: `init(restoring:localResourceRoots:)` MUST initialize from the given `WebviewPanelState`'s `viewType`, `title`, and `options`, and MUST set `state` to that `WebviewPanelState`'s stored `state` text.
- **coder-init-unsupported**: `init(coder:)` MUST fatalError rather than returning a usable instance.
- **main-actor-confined**: The class, its `WKNavigationDelegate` conformance, and its private `WebviewMessageRelay` MUST run isolated to the main actor.
- **title-change-notifies-listeners**: Assigning `title` a value different from its current one MUST invoke `onTitleChanged` and then `onRestorationStateChanged`.
- **title-unchanged-suppresses-notification**: Assigning `title` its current value MUST NOT invoke `onTitleChanged` or `onRestorationStateChanged`.
- **html-change-reloads-document**: Assigning `html` a value different from its current one MUST reload the host document.
- **html-unchanged-suppresses-reload**: Assigning `html` its current value MUST NOT reload the host document.
- **load-view-configures-webkit-sandbox**: `loadView()` MUST register the scheme handler for the `agentic-webview` scheme, add the relay as the message handler named `agenticWebview`, set `allowsContentJavaScript` from `options.enableScripts`, and use a non-persistent website data store.
- **load-view-disables-back-forward-gestures**: `loadView()` MUST set the web view's `allowsBackForwardNavigationGestures` to `false`.
- **load-view-tracks-theme-surface-color**: `loadView()` MUST set the web view's `underPageBackgroundColor` from the active theme's `.surface` palette color immediately, and MUST update it again on every subsequent theme change.
- **load-view-loads-host-document**: `loadView()` MUST call the host-document load after constructing the web view.
- **load-host-document-noop-after-disposal**: The host-document load MUST do nothing when `isDisposed` is `true` or before `loadView()` has run (no web view yet).
- **load-host-document-wraps-extension-html**: The host-document load MUST set the scheme handler's document to the wrapped form of the current `html` and `state`, and MUST load the panel's host-document URL into the web view.
- **host-document-bootstrap-precedes-extension-markup**: The wrapped host document MUST place the `acquireVsCodeApi()` bootstrap script ahead of the extension's own markup, so `postMessage`/`setState` work before the extension's first script runs.
- **host-document-nil-state-as-undefined**: The wrapped host document MUST encode a `nil` `state` as the JavaScript value `undefined`, not `null`, so the page can tell a first run from a restore.
- **local-resource-roots-proxy-to-scheme-handler**: `localResourceRoots` MUST read and write directly through to the scheme handler's own `localResourceRoots`, with no separate stored copy.
- **options-change-updates-content-security-policy**: Assigning `options` a value different from its current one MUST update the scheme handler's `contentSecurityPolicy` to the new options' policy.
- **content-security-policy-floor**: The content security policy served through the scheme handler (`options.contentSecurityPolicy`, defined by `WebviewPanelOptions`) MUST always include `object-src 'none'`, `base-uri 'none'`, and `frame-ancestors 'none'`, and MUST include `form-action 'none'` unless the extension's options enable forms.
- **options-change-notifies-restoration-listeners**: Assigning `options` a value different from its current one MUST invoke `onRestorationStateChanged`.
- **options-change-reloads-loaded-document**: Assigning `options` a value different from its current one MUST reload the host document when the web view already exists and the panel is not disposed.
- **options-unchanged-suppresses-all-effects**: Assigning `options` a value equal to its current one MUST NOT update the content security policy, invoke `onRestorationStateChanged`, or reload the document.
- **post-rejects-unbridgeable-values**: `post(message:)` MUST return `false` and log an error, without touching the web view, for a value that cannot be passed to a page.
- **post-returns-false-when-unavailable**: `post(message:)` MUST return `false` when the web view does not yet exist or the panel is disposed, even for an otherwise-postable value.
- **post-dispatches-message-event**: `post(message:)` MUST dispatch the message to the page as a `message` event carrying the value as `data`, and MUST return `true` when it does.
- **postable-scalar-types-accepted**: The postability check MUST accept `null`, a number, a string, and a date, and MUST reject any other scalar type.
- **postable-dictionary-requires-string-keys**: The postability check MUST accept a dictionary only when every key is a string and every value is itself postable, recursively.
- **postable-array-recurses**: The postability check MUST accept an array only when every element is itself postable, recursively.
- **received-message-ignored-after-disposal**: A message the page sends MUST be ignored once the panel is disposed.
- **post-message-forwarded-verbatim**: A `postMessage` the page sends MUST be forwarded to `onDidReceiveMessage` with its body unchanged.
- **set-state-persists-valid-json**: A `setState` the page sends MUST update `state` to that value's JSON text and MUST invoke `onRestorationStateChanged`, when the value can be encoded as JSON.
- **set-state-drops-invalid-json-without-erasing**: A `setState` the page sends MUST leave the existing `state` value unchanged and MUST NOT invoke `onRestorationStateChanged`, when the value cannot be encoded as JSON; the component MUST log the failure rather than silently discard it.
- **relay-holds-delegate-weakly**: The message relay MUST hold its delegate weakly, so the panel is not retained through the chain of objects the web view's configuration owns.
- **relay-drops-unrecognized-messages**: The message relay MUST drop, without forwarding, a script message whose body is not a dictionary with a `kind` of `postMessage` or `setState` — the only two kinds `WebviewHostDocument.MessageKind` defines, carrying the page's `postMessage` value or `setState` value respectively as `body`.
- **relay-defaults-missing-body-to-null**: The message relay MUST forward a `null` body when the incoming message's payload has no `body` entry.
- **javascript-permission-reevaluated-per-navigation**: The script-execution preferences MUST be computed from the current value of `options.enableScripts` on every navigation, not cached from an earlier value.
- **own-scheme-navigation-allowed**: The navigation policy MUST allow a navigation whose URL uses the panel's own custom scheme.
- **unmatched-navigation-cancelled**: The navigation policy MUST cancel a navigation that has no URL, or whose URL scheme is neither the panel's own scheme nor `http`/`https`, or whose navigation type is not link activation.
- **link-activation-opens-externally-not-in-place**: The navigation policy MUST cancel in-place navigation and instead hand the URL to the external-open handler for a link-activated navigation to an `http`/`https` URL, provided the panel is not currently rate-limited.
- **external-open-rate-limited**: The navigation policy MUST cancel and drop, without queuing, an external-open request that arrives less than the configured interval after the panel's last external open, and MUST log that drop.
- **external-open-state-scoped-per-panel**: The external-open rate limit MUST be tracked independently per panel instance, not shared across panels.
- **reveal-forwards-when-listener-present**: `reveal(preserveFocus:)` MUST call the installed reveal listener directly with the given value, when a listener is installed and the panel is not disposed.
- **reveal-deferred-before-first-placement**: `reveal(preserveFocus:)` MUST retain the request for later replay, without calling anything, when no reveal listener has ever been installed.
- **reveal-deferred-request-overwritten**: A `reveal(preserveFocus:)` call made before any listener has ever been installed MUST overwrite any previously retained request, so only the most recently requested `preserveFocus` value replays once a listener is installed.
- **reveal-after-unplacement**: `reveal(preserveFocus:)` MUST do nothing and MUST NOT retain the request when a reveal listener was installed at some point but is not installed now.
- **reveal-noop-once-disposed**: `reveal(preserveFocus:)` MUST do nothing, and MUST NOT retain the request, once the panel is disposed.
- **installing-reveal-listener-replays-deferred-reveal**: Installing a reveal listener MUST invoke it once, immediately, with the retained request's value, when a reveal request is pending from before any listener existed — including when the panel was disposed in the meantime, since `dispose()` does not clear a retained reveal request.
- **dispose-idempotent**: The second and later calls to `dispose()` MUST perform no further WebKit teardown action and MUST NOT invoke the removal listener again; see `dispose-fires-did-dispose-once` for the `onDidDispose` call count.
- **dispose-tears-down-webkit-state**: `dispose()` MUST clear the web view's navigation delegate, remove its script message handler, and load empty content into it.
- **dispose-fires-did-dispose-once**: `dispose()` MUST invoke `onDidDispose` exactly once, on its first call only.
- **deferred-removal**: `dispose()`, when no removal listener is installed, MUST retain a removal request for later replay only if no removal listener has ever been installed; it MUST NOT retain one if a listener was installed and later cleared.
- **dispose-forwards-removal-when-listener-present**: `dispose()` MUST call the installed removal listener directly, when one is installed.
- **installing-removal-listener-replays-deferred-removal**: Installing a removal listener MUST invoke it once, immediately, when a removal request is pending from before any listener existed.
- **restoration-state-snapshots-current-values**: The restoration snapshot MUST reflect the current `viewType`, `title` (or empty string if unset), `state`, and `options` at the moment it is read.
- **panel-title-defaults-empty-string**: The `ExtensionWebviewPanel` title accessor's getter MUST return `title`, or an empty string when `title` is unset.
- **panel-title-setter-assigns-through**: The `ExtensionWebviewPanel` title accessor's setter MUST assign its new value directly to `title`.
- **pane-title-defaults-to-view-type**: The `PaneTitleProviding` title accessor MUST return `viewType` when `title` is unset.
- **pane-title-change-callback-aliases-title-callback**: The `PaneTitleProviding` title-change callback MUST read and write the same storage as the title-change callback used internally, so installing one and triggering a title change fires the other.
- **teardown-disposes-panel**: `paneContentWillBeDiscarded()` MUST call `dispose()`.
- **debug-only-occlusion-detection-disabled**: In a DEBUG build only, when `QuietWindowPresentation.isEnabled` is `true`, `loadView()` MUST attempt to disable window-occlusion-based paint suppression on the web view by invoking the private selector `_setWindowOcclusionDetectionEnabled:` (looked up by name, since it is not public API) with `false`, and MUST silently skip that attempt when the running WebKit does not respond to that selector; this code path MUST NOT exist in a release build.

## Appearance

- **Corner radius**: Not applicable — the view this controller shows is a plain `WKWebView` with no corner radius set anywhere in this file; any rounding a rendered page's own CSS applies is the extension's content, out of this file's scope.
- **Padding**: Not applicable — the web view is constructed at `NSRect(x: 0, y: 0, width: 480, height: 320)` in `loadView()` and becomes `view` directly, with no inset around it; this initial frame is discarded once the containing pane's Auto Layout takes over sizing.
- **Font**: Not applicable — this file sets no font of its own; all text belongs to the extension's rendered page.
- **Background**: The web view's `underPageBackgroundColor` is set from the active theme's `.surface` role, resolved through `observeTheme`, applied immediately in `loadView()` and reapplied on every subsequent theme change (traced: `webView.observeTheme { view, palette in view.underPageBackgroundColor = palette.nsColor(.surface) }`).
- **Foreground/Text**: Not applicable — no foreground or text color is set in this file; text color belongs to the rendered page.
- **Border**: Not applicable — no border is set anywhere in this file.
- **Shadow**: Not applicable — no shadow is set anywhere in this file.
- **Min/Max size**: Not applicable — no width/height constraint is installed on the web view in this file; the constructor's `480×320` frame is an initial value only, superseded by the pane host's Auto Layout.

## States

| State | Appearance change |
|-------|------------------|
| Default | The bare `WKWebView` surface: no corner radius, border, or shadow, and a background derived from the active theme's `.surface` color (see Appearance) |
| Pressed | Not applicable: this component has no pressed state; it hosts a web document rather than drawing an interactive control of its own. |
| Disabled | Not applicable: neither this file nor `WebviewPanelOptions` expose a disabled state for the panel as a whole. |
| Focused | Not applicable: this file installs no explicit first-responder or focus-ring handling; the web view's own standard AppKit focus behavior is unmodified. |
| Loading | Not applicable: no loading indicator exists in this file; the web view shows its own default content while a page loads, and this controller does not visually distinguish that interval. |
| Unloaded | Before `loadView()` runs, the web view is `nil`; assigning `html` or `options` in this state stores the new value but performs no reload, since there is nothing to reload. |
| Displaying host document | The web view exists and is showing the wrapped extension markup, loaded from the panel's host-document URL; further `html`/`options` changes reload it in place. |
| Awaiting placement | No reveal/removal listener has ever been installed; a `reveal(preserveFocus:)` call or a `dispose()` call is captured for one-time replay rather than acted on. |
| Placed | A reveal/removal listener is installed; further `reveal(preserveFocus:)` and `dispose()` calls forward directly to it. |
| Disposed | The web view's navigation delegate and message handler are torn down and its content cleared; `post(message:)` returns `false`, `html`/`options` writes no longer reload, and messages from the page are ignored. |

## Accessibility

- **Role/trait**: Not applicable — no explicit accessibility role is set anywhere in this file; the on-screen view is a `WKWebView`, which supplies its own accessibility tree for whatever content it renders.
- **Label requirements**: Satisfied by `title` — the one label this file owns is the pane's chrome-visible name, which the extension sets and this class re-titles the pane on every change (see `title-change-notifies-listeners`). Labeling of anything *inside* the rendered page is the extension's own HTML, out of this file's scope.
- **Announce state changes**: Not applicable — the only two changes this file makes to what is on screen are a title update (already surfaced through the standard AppKit title mechanism pane chrome reads) and a document reload triggered by `html`/`options` changes (a live DOM update inside the web view, which is WebKit's own accessibility-tree responsibility, not a native view swap this controller performs itself). Unlike a component that swaps between two distinct native view hierarchies with no notification at all, there is no such swap in this file to flag.
- **Minimum tap target**: Not applicable — this view controller draws no discrete tappable control of its own; the entire view is the web view's surface, and any interactive element within the rendered page is the extension's own content, out of this file's scope.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wpvc-001 | panel-id-generated-at-init | Construct two panels with identical constructor arguments | Their `panelID` values are non-empty UUID strings and differ from each other |
| wpvc-002 | init-applies-scheme-handler-and-relay | Construct a panel with a known `localResourceRoots` and `options` | Immediately after `init` returns, the scheme handler's `localResourceRoots` and `contentSecurityPolicy` match the given values, before `loadView()` ever runs |
| wpvc-003 | restoring-init-seeds-prior-state | Construct via `init(restoring: WebviewPanelState(viewType: "v", title: "T", state: "{\"a\":1}", options: opts), localResourceRoots: roots)` | `viewType == "v"`, `title == "T"`, `state == "{\"a\":1}"`, `options == opts` |
| wpvc-004 | coder-init-unsupported | Call `init(coder:)` | The process traps; no instance is returned |
| wpvc-005 | main-actor-confined | Attempt, from a non-main-actor context, to call a method or read a property of the class, the relay, or the navigation delegate conformance | Compilation fails — Swift's actor-isolation checker rejects the access, confirming every declaration requires the main actor |
| wpvc-006 | title-change-notifies-listeners | Install spies on both callbacks, set `title` from `"Old"` to `"New"` | Both spies fire exactly once, in order |
| wpvc-007 | title-unchanged-suppresses-notification | With `title == "Same"`, set `title = "Same"` again | Neither spy fires |
| wpvc-008 | html-change-reloads-document | After `loadView()`, assign a new `html` value | The host document reloads |
| wpvc-009 | html-unchanged-suppresses-reload | After `loadView()`, assign `html` its current value | No reload occurs |
| wpvc-010 | load-view-configures-webkit-sandbox | Call `loadView()` with `options.enableScripts == false` | The scheme handler is registered for `agentic-webview`, the relay is the `agenticWebview` message handler, `allowsContentJavaScript == false`, and the data store is non-persistent |
| wpvc-011 | load-view-disables-back-forward-gestures | Call `loadView()` | The web view's `allowsBackForwardNavigationGestures == false` |
| wpvc-012 | load-view-tracks-theme-surface-color | Call `loadView()` under theme A, read the background color, then switch to theme B | The color equals theme A's `.surface` color after load and theme B's after the switch, with no further action |
| wpvc-013 | load-view-loads-host-document | Call `loadView()` | The web view's loaded request URL equals the panel's host-document URL |
| wpvc-014 | load-host-document-noop-after-disposal | Call `dispose()`, then assign a new `html` value | No further load reaches the web view |
| wpvc-015 | load-host-document-wraps-extension-html | Set `html` and `state` to known values around `loadView()` | The scheme handler's document equals the wrapped form of that `html` and `state` |
| wpvc-016 | local-resource-roots-proxy-to-scheme-handler | Set `localResourceRoots = [dirA, dirB]` | Reading `localResourceRoots` and the scheme handler's own roots both return `[dirA, dirB]` |
| wpvc-017 | options-change-updates-content-security-policy | Change `options.enableForms` from `false` to `true` | The scheme handler's `contentSecurityPolicy` no longer contains `form-action 'none'` |
| wpvc-018 | options-change-notifies-restoration-listeners | Install a spy, assign a different `options` value | The spy fires exactly once |
| wpvc-019 | options-change-reloads-loaded-document | After `loadView()`, assign a different `options` value | The host document reloads |
| wpvc-020 | options-unchanged-suppresses-all-effects | Assign `options` a value equal to the current one | No CSP change, no callback, no reload occurs |
| wpvc-021 | post-rejects-unbridgeable-values | After `loadView()`, call `post(message:)` with an unbridgeable value (e.g. a raw URL object) | Returns `false`; no script is dispatched; the failure is logged as an error |
| wpvc-022 | post-returns-false-when-unavailable | Call `post(message:)` before `loadView()`, and again after `dispose()` | Both calls return `false` |
| wpvc-023 | post-dispatches-message-event | After `loadView()`, call `post(message: ["a": 1])` | Returns `true`; the value is dispatched as a `message` event's `data` |
| wpvc-024 | postable-scalar-types-accepted | Check postability of null, a number, a string, and a date | All four are accepted |
| wpvc-025 | postable-dictionary-requires-string-keys | Check postability of a string-keyed dictionary and of a number-keyed dictionary | First accepted, second rejected |
| wpvc-026 | postable-array-recurses | Check postability of an array containing one non-postable element | Rejected |
| wpvc-027 | received-message-ignored-after-disposal | Call `dispose()`, then deliver a page message | `onDidReceiveMessage` does not fire |
| wpvc-028 | post-message-forwarded-verbatim | Install a spy, deliver a `postMessage` with a known payload | The spy receives that payload unchanged |
| wpvc-029 | set-state-persists-valid-json | Install a spy, deliver a `setState` with a JSON-representable value | `state` updates to that value's JSON text; the spy fires once |
| wpvc-030 | set-state-drops-invalid-json-without-erasing | With a known `state`, install a spy, deliver a `setState` with a non-JSON value | `state` is unchanged; the spy does not fire; the failure is logged as an error |
| wpvc-031 | relay-holds-delegate-weakly | Assign a panel as the relay's delegate, then release every other strong reference to the panel | The panel deallocates; the relay's delegate reads `nil` afterward |
| wpvc-032 | relay-drops-unrecognized-messages | Deliver a script message whose body is not a dictionary | The panel's message handler is never called |
| wpvc-033 | relay-defaults-missing-body-to-null | Deliver a script message dictionary with a valid `kind` and no `body` entry | The panel's message handler is called with a null body |
| wpvc-035 | javascript-permission-reevaluated-per-navigation | Compute preferences with `enableScripts == true`, flip to `false`, compute again | First result allows scripts; second does not |
| wpvc-036 | own-scheme-navigation-allowed | Evaluate policy for a navigation whose URL uses the panel's own scheme | Allowed |
| wpvc-037 | unmatched-navigation-cancelled | Evaluate policy for (a) no URL, (b) an unrelated scheme, (c) an `https://` URL not from link activation | All three cancelled |
| wpvc-038 | link-activation-opens-externally-not-in-place | Evaluate policy for a link-activated `https://` navigation, with a spy external-open handler | Cancelled in place; the spy is called once with that URL |
| wpvc-039 | external-open-rate-limited | With a long rate-limit interval, trigger two link activations back to back | First opens externally; second is cancelled without opening, and logs the drop |
| wpvc-040 | external-open-state-scoped-per-panel | Rate-limit one panel, then immediately trigger a link activation on a second, independent panel | The second panel's external-open handler is still called |
| wpvc-041 | reveal-forwards-when-listener-present | Install a reveal listener, call `reveal(preserveFocus: true)` | The listener is called once with `true` |
| wpvc-042 | reveal-deferred-before-first-placement | With no reveal listener ever installed, call `reveal(preserveFocus: false)` | No crash, no callback; the request is retained (see wpvc-045) |
| wpvc-043 | reveal-after-unplacement | Install then clear the reveal listener, call `reveal(preserveFocus: true)` | No crash, no callback, and nothing is retained for replay |
| wpvc-044 | reveal-noop-once-disposed | Call `dispose()`, then call `reveal(preserveFocus: true)` | No callback fires and nothing is retained |
| wpvc-045 | installing-reveal-listener-replays-deferred-reveal | Call `reveal(preserveFocus: true)` before any listener exists, then install a listener | The newly installed listener is invoked once, immediately, with `true` |
| wpvc-046 | dispose-idempotent | Install a removal listener, call `dispose()` twice | The removal listener is invoked once (from the first call); the second call performs no further WebKit teardown and does not call the removal listener again |
| wpvc-047 | dispose-tears-down-webkit-state | Call `dispose()` after `loadView()` | The navigation delegate is cleared, the message handler is removed, and empty content is loaded |
| wpvc-048 | dispose-fires-did-dispose-once | Install a spy, call `dispose()` | The spy fires exactly once |
| wpvc-049 | deferred-removal | (a) Call `dispose()` with no removal listener ever installed; (b) install then clear a removal listener, then call `dispose()` | (a) a removal is retained for replay; (b) none is retained |
| wpvc-050 | dispose-forwards-removal-when-listener-present | Install a removal listener, call `dispose()` | The listener is called once |
| wpvc-051 | installing-removal-listener-replays-deferred-removal | Call `dispose()` before any removal listener exists, then install a listener | The newly installed listener is invoked once, immediately |
| wpvc-052 | restoration-state-snapshots-current-values | Set `viewType`, `title`, `state` (via `setState`), and `options` to known values, read the restoration snapshot | All four match the current values |
| wpvc-053 | panel-title-defaults-empty-string | With `title` unset, read the `ExtensionWebviewPanel` title accessor | Returns an empty string |
| wpvc-054 | pane-title-defaults-to-view-type | With `title` unset and a known `viewType`, read the `PaneTitleProviding` title accessor | Returns `viewType` |
| wpvc-055 | pane-title-change-callback-aliases-title-callback | Install a closure on the `PaneTitleProviding` callback, then change `title` | That closure fires |
| wpvc-056 | teardown-disposes-panel | Call `paneContentWillBeDiscarded()` | The panel becomes disposed and `onDidDispose` fires, identically to a direct `dispose()` call |
| wpvc-057 | debug-only-occlusion-detection-disabled | In a DEBUG build, with the automation flag enabled, call `loadView()` | The web view's window-occlusion paint suppression is disabled when the running WebKit supports the check, and the attempt is silently skipped otherwise; this path does not exist in a Release build |
| wpvc-058 | load-host-document-noop-after-disposal | Assign a new `html` value before `loadView()` has ever run | No load reaches any web view (none exists yet), and no crash occurs |
| wpvc-059 | host-document-bootstrap-precedes-extension-markup | Set `html` to a known extension markup string and call `loadView()` | The wrapped host document's `acquireVsCodeApi()` bootstrap script appears before that markup in document order |
| wpvc-060 | host-document-nil-state-as-undefined | Construct a panel with no restored state and call `loadView()` | The wrapped host document embeds the initial state as the literal `undefined`, not `null` |
| wpvc-061 | content-security-policy-floor | With `options.enableForms == false`, read the scheme handler's `contentSecurityPolicy` | It contains `object-src 'none'`, `base-uri 'none'`, `frame-ancestors 'none'`, and `form-action 'none'` |
| wpvc-062 | content-security-policy-floor | With `options.enableForms == true`, read the scheme handler's `contentSecurityPolicy` | It contains `object-src 'none'`, `base-uri 'none'`, and `frame-ancestors 'none'`, and omits `form-action 'none'` |
| wpvc-063 | reveal-deferred-request-overwritten | With no reveal listener ever installed, call `reveal(preserveFocus: true)` then `reveal(preserveFocus: false)`, then install a listener | The listener is invoked once, immediately, with `false` |
| wpvc-064 | installing-reveal-listener-replays-deferred-reveal | Call `reveal(preserveFocus: true)` before any listener exists, then `dispose()`, then install a reveal listener | The listener is still invoked once, immediately, with `true`, even though the panel is now disposed |
| wpvc-065 | panel-title-setter-assigns-through | Set the `ExtensionWebviewPanel` title accessor (`panelTitle`) to a new string value | `title` equals that value afterward |
| wpvc-066 | relay-drops-unrecognized-messages | Deliver a script message whose body is a dictionary with an unrecognized `kind` string | The panel's message handler is never called |

## Edge Cases

- **Null/empty input**: An empty `html` string is the initial value and loads as an empty extension page; a `nil` `state` is the ordinary "the page never called `setState`" case, and the injected bootstrap embeds it as `undefined` rather than `null` so an extension can tell a first run from a restore. Empty `viewType`/`title` strings are accepted verbatim — this class never validates them, since they are the extension's own declared values.
- **Boundary values**: An `externalOpenInterval` of `0` disables the external-open rate limit entirely, since elapsed time is never negative; the value is not clamped, because it exists only for tests to shorten and production code never assigns it. A second `reveal(preserveFocus:)` call before any listener exists overwrites the first — only the most recent value replays (`reveal-deferred-request-overwritten`) — and a reveal retained this way survives `dispose()`, since `dispose()` does not clear it; installing a listener afterward still replays it once even though the panel is already disposed (`installing-reveal-listener-replays-deferred-reveal`).
- **Concurrent access**: The whole class is main-actor isolated (MUST, see `main-actor-confined`), which serializes every read and write of `state`, `isDisposed`, the placement flags, and every callback. A message the page sends arrives through the relay's `WKScriptMessageHandler` callback, which the relay re-enters onto the main actor explicitly rather than trusting the delegate call's own isolation, so a page message cannot race the actor even if WebKit were to deliver it from an unexpected queue.
- **Error states**: A `post(message:)` value WebKit cannot bridge (for example, a URL object) is dropped with a logged error and a `false` return, never a crash. A `setState` value that cannot be encoded as JSON (for example, a JavaScript `Date`) is dropped with a logged error, leaving the previously persisted state untouched and firing no restoration callback — a message is lost, not a state erased. A script message whose shape the relay does not recognize is dropped silently, treated as a hostile or malformed page rather than a bug to surface. Calling `reveal(preserveFocus:)` or relying on `dispose()`'s deferred-removal path with no listener ever installed, and none pending, does nothing — matching the upstream behavior for a panel whose presenting window is already gone. Calling `dispose()` a second time is a no-op, not an error.
- **Offline or disconnected state**: Not applicable to this file directly — it is not a network layer. Whatever the extension's rendered page does over the network happens entirely inside the page's own JavaScript, outside this controller. The one network-adjacent behavior this file owns, opening an `http`/`https` link in the user's external browser, does not depend on this app's own connectivity.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewType` | `String` | required at init | The type this panel was created under, and the key its serializer is registered against. |
| `title` | `String` | required at init | What the pane's chrome calls the panel to begin with. |
| `options` | `WebviewPanelOptions` | required at init | What the extension asked for (`enableScripts`, `enableForms`, declared resource roots), with defaults applied. |
| `localResourceRoots` | `[URL]` | required at init | The directories this panel may read files from, already resolved by the caller. |
| `externalOpenInterval` | `TimeInterval` | `0.5` | Minimum seconds between two external link opens from this panel; settable so a test can assert the rate limit without waiting real time, and never changed in production. |
| `openExternalURL` | `(URL) -> Void` | hands the URL to the system's default handler | Injectable so a test can observe external-open calls without opening real browser windows. |

## Deep Linking

Not applicable: this component is built entirely from constructor arguments (`viewType`, `title`, `options`, `localResourceRoots`) and messages exchanged over its custom `agentic-webview://` scheme, which is an internal resource-loading mechanism, not an app-level deep-link entry point. No URL scheme, universal link, or `NSUserActivity` handling appears anywhere in this file.

## Localization

Not applicable: no user-facing string literal is authored anywhere in this file. `title` arrives from the caller (an extension-declared name), not as a literal here, and `html` is the extension's own markup, passed through unchanged. The only string literals this file declares are log messages (`Logger.error`/`.notice`), which are developer diagnostics, not user-facing text.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no motion (movement, scaling, sliding, zooming, parallax, or a looping pulse) exists anywhere in this file; document reloads and content updates are immediate, not animated. |
| Increase Contrast | Not observed in this file: the one color it sets, `underPageBackgroundColor`, is resolved through the theme/palette system (`palette.nsColor(.surface)`), so contrast adaptation belongs to the theme system, out of this ingredient's scope. |
| Differentiate Without Color | Not applicable: this file draws no state that is distinguished by color alone; its only color use is a single background fill. |

## Feature Flags

Not applicable: no `{{app_prefix}}`-style feature-flag or remote-config lookup exists anywhere in this file. The one runtime switch it reads, an automation flag gating a DEBUG-only window-occlusion override, is a test/screenshot-tooling switch guarded by `#if DEBUG`, not a shipped feature flag.

## Analytics

Not applicable: no analytics event is emitted anywhere in this file.

## Privacy

- **Data collected**: The rendered page's own state, whatever it last passed to `setState`, carried as opaque JSON text; this file does not interpret it or add data of its own.
- **Storage**: None persisted by this file. `state` is held only in memory for the life of this instance; `configuration.websiteDataStore = .nonPersistent()` means the web view's own cookies, `localStorage`, and cache do not survive the app quitting. Whatever survives an app restart is entirely the responsibility of a separate serializer that reads this panel's restoration snapshot, out of this file's scope.
- **Transmission**: None over a network by this file directly. The rendered page may make its own network requests as part of the extension's content, out of scope here. Locally, messages cross the WebKit/AppKit boundary through the script message handler and `callAsyncJavaScript`, never leaving the device.
- **Retention**: `state` lives exactly as long as this view controller instance does; `dispose()` clears the web view's content but does not clear `state` itself.

## Logging

Subsystem: `{{bundle_id}}` | Category: `WebviewPanelViewController`

| Event | Level | Message |
|-------|-------|---------|
| A page's `post(message:)` value cannot be bridged to WebKit | error | `A webview message held a value WebKit cannot pass to a page; dropping it` |
| A page's `setState` value cannot be encoded as JSON | error | `A webview's setState value was not JSON; dropping it` |
| An external-open request arrives while rate-limited | notice | `A webview asked to open links faster than a person can click; dropping one` |

## Platform Notes

- **SwiftUI**: The payload is still an AppKit `WKWebView`, so wrap this controller in an `NSViewControllerRepresentable` rather than reimplementing it; expose a small `@Observable` model holding `html`, `options`, `state`, and the message callbacks, and drive `updateNSViewController` from its published changes instead of reaching into the wrapped controller's imperative setters directly.
- **Compose**: There is no desktop-webview equivalent; on Android, wrap a sandboxed `android.webkit.WebView` behind the same `postMessage`/`setState` bridge shape (`addJavascriptInterface` with an explicit type allow-list mirroring the postability check), enforce the custom-scheme-plus-declared-roots containment through `WebViewAssetLoader` in place of `file://` access, and drive scripts/forms enablement from the same resolved options via `WebSettings`.
- **React/Web**: The nearest analog is a sandboxed `<iframe>`, not a same-origin `<webview>`: use `postMessage`/`window.addEventListener('message', ...)` for the bridge exactly as the injected bootstrap script does, `sandbox` attributes in place of the custom-scheme containment, and a `Content-Security-Policy` response header matching this file's CSP floor (see **content-security-policy-floor**).
- **AppKit/UIKit**: This recipe's own platform: `WebviewPanelViewController.swift` is macOS/AppKit-only (`NSViewController`, `WKWebView`, `NSWorkspace`). A UIKit port would swap `NSViewController` for `UIViewController` and `NSWorkspace.shared.open` for `UIApplication.shared.open`, and would need its own theming hook in place of `observeTheme`/`palette.nsColor(.surface)`, since neither exists for iOS in this codebase today.
- **WinUI 3**: Recreate this as a `UserControl` ("WebviewPanelControl") hosting a single `WebView2` in a one-cell `Grid`. Map `html` assignment to `WebView2.NavigateToString` (or a reload from a virtual host mapping) triggered from a `DependencyProperty`-changed callback mirroring the source's change-guarded setters; map `options.enableScripts` to `CoreWebView2Settings.IsScriptEnabled` (there is no direct forms toggle — enforce that half through the injected bootstrap and CSP instead, as the source does); replace the custom `agentic-webview://` scheme and root containment with `CoreWebView2.SetVirtualHostNameToFolderMapping` scoped to one virtual host name per `panelID` (mirroring the per-panel WebKit origin), backed by a `WebResourceRequested` handler that re-checks containment on every request the way the scheme handler does; implement the bridge with `CoreWebView2.PostWebMessageAsJson`/`WebMessageReceived`, applying the same JSON-validity gate before posting that this source's postability and JSON checks enforce, since `WebView2` marshals differently and can throw on unsupported types; implement navigation policy in `CoreWebView2.NavigationStarting` (cancel or redirect exactly as this source's policy method does, including the same per-panel external-open rate limit); implement the reveal/dispose deferral with two nullable events (`Revealed`, `RemovalRequested`) that replay exactly once on first subscription, mirroring this source's deferred-reveal and deferred-removal fields; and give up non-persistent storage by constructing the `CoreWebView2Environment` with a temporary, cleaned-up user-data folder, since `WebView2` has no built-in "in-memory only" profile flag the way `WKWebsiteDataStore.nonPersistent()` provides.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/Webview/WebviewPanelViewController.swift` |

## Design Decisions

**Decision**: One class combines the panel model and its view controller, rather than a model and a view controller behind a shared protocol.
**Rationale**: The panel is the pane's content, its title is the pane's title, and disposing it is closing the pane; splitting them would add a protocol between two objects with one lifetime that nothing else would ever implement.
**Approved**: pending

**Decision**: The reveal and removal callbacks each replay exactly one deferred call the moment they are first installed, keyed by whether the panel has ever been placed.
**Rationale**: An extension's own restore path can call `panel.reveal()` or dispose the panel before its presenter has had any chance to install these callbacks, because that call runs to completion first; dropping the call would silently strand a reveal or a removal the caller genuinely asked for.
**Approved**: pending

**Decision**: The script-execution flag is set on a freshly created `WKWebViewConfiguration` in `loadView()` and re-evaluated per navigation, rather than written to the web view's `configuration` after construction.
**Rationale**: `WKWebView.configuration` is `@NSCopying` — its getter returns a copy — so a later write there is silently discarded and never reaches WebKit; this was a real defect the source's own comments describe (turning scripts off on a running panel used to do nothing at all).
**Approved**: pending

**Decision**: The web view's website data store is non-persistent, and no second, app-level persistence path exists for a page's own `localStorage`.
**Rationale**: `setState`/`getState` is the one persistence contract a webview author writes against; a second, half-working persistence mechanism that survives some restarts and not others is worse than none.
**Approved**: pending

**Decision**: `post(message:)` validates the message against a postability check before dispatching it, rather than relying on error-trapping around the dispatch call.
**Rationale**: WebKit raises an uncatchable exception for an unbridgeable argument, which would take the whole process down; validating first turns a crash into a dropped message and a `false` return.
**Approved**: pending

**Decision**: The JSON-validity rule `setState` uses is stricter, and different, than the postability rule `post(message:)` uses.
**Rationale**: The two values go to different places — `setState`'s value is serialized to text for storage, while `post`'s value goes straight to a JavaScript engine — so a page calling `setState` with a date is silently dropped (JSON has no date type) while the identical value passed to `post(message:)` succeeds. This is an intentional asymmetry traceable to what each value is for, not an inconsistency to fix.
**Approved**: pending

**Decision**: A link click to `http`/`https` is redirected to the user's external browser rather than allowed to navigate the panel in place, and is rate-limited per panel.
**Rationale**: Navigating in place would replace the extension's page with a web page holding the panel's own origin; and link activation is reported identically for a script-triggered click and a real one, so an unthrottled page could open unbounded external windows with no user action able to stop it.
**Approved**: pending

**Decision**: The `ExtensionWebviewPanel` title accessor falls back to an empty string when `title` is unset, while the `PaneTitleProviding` title accessor falls back to `viewType` in the same circumstance.
**Rationale**: The two protocols serve different callers — the former answers the extension API's own title property, which upstream treats as a plain string, while the latter answers this app's pane chrome, which needs a non-empty placeholder rather than a blank tab label before a title has ever been set.
**Approved**: pending

**Decision**: The DEBUG-only window-occlusion override pokes a private selector by name, guarded by a compile-time check and a runtime `responds(to:)` check, rather than shipping it unconditionally.
**Rationale**: WebKit stops painting into a window the window server reports occluded, which automation deliberately does to every window during screenshot capture; a real user's occluded window should keep that battery-saving behavior, so this private-API use is confined to debug builds and skipped outright wherever the selector does not exist.
**Approved**: pending

**Decision**: The script message handler is a separate relay object holding the panel weakly, rather than the panel registering itself as its own handler.
**Rationale**: The user content controller retains its handlers, the configuration retains the controller, the web view retains the configuration, and the panel retains the web view; a panel that was its own handler would never deallocate, holding an entire web content process past its pane's lifetime.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | passed | Platform Compliance |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |

These all rest on this file's own code: the theme-tracking closure installed in `loadView()` (`platform-theming`), the `responds(to:)` fallback around the private occlusion selector and the drop-not-crash handling of unbridgeable `post`/`setState` values (`graceful-degradation`), the `guard !isDisposed` early return in `dispose()` (`idempotent-operations`), and the postability and JSON-validity checks applied to every value before it reaches WebKit or storage (`input-sanitization`).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: named the host-document bootstrap contract and CSP floor as requirements, named the private occlusion selector and the relay's accepted message kinds, narrowed dispose-idempotent to avoid overlap with dispose-fires-did-dispose-once, corrected the references/tags/compliance frontmatter, renamed sentence-form requirements to subject-only names, reformatted Design Decisions, removed template residue and a brittle file path, filled in the default state and deferred-reveal edge cases, and fixed test-vector gaps |
| 1.1.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
