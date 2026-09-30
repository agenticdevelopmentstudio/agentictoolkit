<!-- leaf: implement-general-controller/webview-panel-view-controller--test-vectors-part-2 · source: webview-panel-view-controller.md -->

# WebviewPanelViewController — Conformance Test Vectors (part 2)

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
