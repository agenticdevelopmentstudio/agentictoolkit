<!-- leaf: implement-extension/webview-view-controller--states · source: extension-webview-view-controller.md -->

# ExtensionWebviewViewController

## States

| State | Appearance change |
|-------|------------------|
| Default | — |
| Pressed | Not applicable: this component has no pressed state; it hosts other view controllers rather than drawing an interactive control of its own. |
| Disabled | Not applicable: neither this component nor the placeholder it shows can be disabled in this file; any disabled treatment inside a resolved webview panel's page is the extension's concern. |
| Focused | Not applicable: this component sets no explicit focus or first-responder behavior of its own; whichever child is on screen manages its own focus. |
| Loading | Not applicable: no loading indicator or spinner exists anywhere in this file. The interval between construction and a resolved panel is not visually distinguished from the initial placeholder. |
| Placeholder (unresolved) | Default content: `ExtensionViewPlaceholderViewController`, shown from `loadView()` until the extension's provider resolves. |
| Resolved (webview panel) | Content: the `WebviewPanelViewController` `resolve` returned, adopted once its completion closure has fired. |
| Reverted to placeholder | Content: a freshly built `ExtensionViewPlaceholderViewController`, shown when the previously adopted panel's `onRemovalRequested` fires and the component is not itself being discarded. |
