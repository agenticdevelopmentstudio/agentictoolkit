<!-- leaf: implement-general-controller/webview-panel-view-controller--states · source: webview-panel-view-controller.md -->

# WebviewPanelViewController

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
