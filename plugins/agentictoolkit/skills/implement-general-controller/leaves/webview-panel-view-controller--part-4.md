<!-- leaf: implement-general-controller/webview-panel-view-controller--part-4 · source: webview-panel-view-controller.md -->

# WebviewPanelViewController — continued (part 4)

## Platform Notes

- **SwiftUI**: The payload is still an AppKit `WKWebView`, so wrap this controller in an `NSViewControllerRepresentable` rather than reimplementing it; expose a small `@Observable` model holding `html`, `options`, `state`, and the message callbacks, and drive `updateNSViewController` from its published changes instead of reaching into the wrapped controller's imperative setters directly.
- **Compose**: There is no desktop-webview equivalent; on Android, wrap a sandboxed `android.webkit.WebView` behind the same `postMessage`/`setState` bridge shape (`addJavascriptInterface` with an explicit type allow-list mirroring the postability check), enforce the custom-scheme-plus-declared-roots containment through `WebViewAssetLoader` in place of `file://` access, and drive scripts/forms enablement from the same resolved options via `WebSettings`.
- **React/Web**: The nearest analog is a sandboxed `<iframe>`, not a same-origin `<webview>`: use `postMessage`/`window.addEventListener('message', ...)` for the bridge exactly as the injected bootstrap script does, `sandbox` attributes in place of the custom-scheme containment, and a `Content-Security-Policy` response header matching this file's CSP floor (see **content-security-policy-floor**).
- **AppKit/UIKit**: This recipe's own platform: `WebviewPanelViewController.swift` is macOS/AppKit-only (`NSViewController`, `WKWebView`, `NSWorkspace`). A UIKit port would swap `NSViewController` for `UIViewController` and `NSWorkspace.shared.open` for `UIApplication.shared.open`, and would need its own theming hook in place of `observeTheme`/`palette.nsColor(.surface)`, since neither exists for iOS in this codebase today.
- **WinUI 3**: Recreate this as a `UserControl` ("WebviewPanelControl") hosting a single `WebView2` in a one-cell `Grid`. Map `html` assignment to `WebView2.NavigateToString` (or a reload from a virtual host mapping) triggered from a `DependencyProperty`-changed callback mirroring the source's change-guarded setters; map `options.enableScripts` to `CoreWebView2Settings.IsScriptEnabled` (there is no direct forms toggle — enforce that half through the injected bootstrap and CSP instead, as the source does); replace the custom `agentic-webview://` scheme and root containment with `CoreWebView2.SetVirtualHostNameToFolderMapping` scoped to one virtual host name per `panelID` (mirroring the per-panel WebKit origin), backed by a `WebResourceRequested` handler that re-checks containment on every request the way the scheme handler does; implement the bridge with `CoreWebView2.PostWebMessageAsJson`/`WebMessageReceived`, applying the same JSON-validity gate before posting that this source's postability and JSON checks enforce, since `WebView2` marshals differently and can throw on unsupported types; implement navigation policy in `CoreWebView2.NavigationStarting` (cancel or redirect exactly as this source's policy method does, including the same per-panel external-open rate limit); implement the reveal/dispose deferral with two nullable events (`Revealed`, `RemovalRequested`) that replay exactly once on first subscription, mirroring this source's deferred-reveal and deferred-removal fields; and give up non-persistent storage by constructing the `CoreWebView2Environment` with a temporary, cleaned-up user-data folder, since `WebView2` has no built-in "in-memory only" profile flag the way `WKWebsiteDataStore.nonPersistent()` provides.

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
