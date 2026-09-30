<!-- leaf: implement-general-controller/webview-panel-view-controller--part-3 · source: webview-panel-view-controller.md -->

# WebviewPanelViewController — continued (part 3)

**Rules** (cite as `implement-general-controller/webview-panel-view-controller--part-3#<slug>`):

- `installing-reveal-listener-replays-deferred-reveal` MUST
- `dispose-idempotent` MUST
- `dispose-tears-down-webkit-state` MUST
- `dispose-fires-did-dispose-once` MUST
- `deferred-removal` MUST
- `dispose-forwards-removal-when-listener-present` MUST
- `installing-removal-listener-replays-deferred-removal` MUST
- `restoration-state-snapshots-current-values` MUST
- `panel-title-defaults-empty-string` MUST
- `panel-title-setter-assigns-through` MUST
- `pane-title-defaults-to-view-type` MUST
- `pane-title-change-callback-aliases-title-callback` MUST
- `teardown-disposes-panel` MUST
- `debug-only-occlusion-detection-disabled` MUST

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

## Accessibility

- **Role/trait**: Not applicable — no explicit accessibility role is set anywhere in this file; the on-screen view is a `WKWebView`, which supplies its own accessibility tree for whatever content it renders.
- **Label requirements**: Satisfied by `title` — the one label this file owns is the pane's chrome-visible name, which the extension sets and this class re-titles the pane on every change (see `title-change-notifies-listeners`). Labeling of anything *inside* the rendered page is the extension's own HTML, out of this file's scope.
- **Announce state changes**: Not applicable — the only two changes this file makes to what is on screen are a title update (already surfaced through the standard AppKit title mechanism pane chrome reads) and a document reload triggered by `html`/`options` changes (a live DOM update inside the web view, which is WebKit's own accessibility-tree responsibility, not a native view swap this controller performs itself). Unlike a component that swaps between two distinct native view hierarchies with no notification at all, there is no such swap in this file to flag.
- **Minimum tap target**: Not applicable — this view controller draws no discrete tappable control of its own; the entire view is the web view's surface, and any interactive element within the rendered page is the extension's own content, out of this file's scope.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewType` | `String` | required at init | The type this panel was created under, and the key its serializer is registered against. |
| `title` | `String` | required at init | What the pane's chrome calls the panel to begin with. |
| `options` | `WebviewPanelOptions` | required at init | What the extension asked for (`enableScripts`, `enableForms`, declared resource roots), with defaults applied. |
| `localResourceRoots` | `[URL]` | required at init | The directories this panel may read files from, already resolved by the caller. |
| `externalOpenInterval` | `TimeInterval` | `0.5` | Minimum seconds between two external link opens from this panel; settable so a test can assert the rate limit without waiting real time, and never changed in production. |
| `openExternalURL` | `(URL) -> Void` | hands the URL to the system's default handler | Injectable so a test can observe external-open calls without opening real browser windows. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no motion (movement, scaling, sliding, zooming, parallax, or a looping pulse) exists anywhere in this file; document reloads and content updates are immediate, not animated. |
| Increase Contrast | Not observed in this file: the one color it sets, `underPageBackgroundColor`, is resolved through the theme/palette system (`palette.nsColor(.surface)`), so contrast adaptation belongs to the theme system, out of this ingredient's scope. |
| Differentiate Without Color | Not applicable: this file draws no state that is distinguished by color alone; its only color use is a single background fill. |

## Privacy

- **Data collected**: The rendered page's own state, whatever it last passed to `setState`, carried as opaque JSON text; this file does not interpret it or add data of its own.
- **Storage**: None persisted by this file. `state` is held only in memory for the life of this instance; `configuration.websiteDataStore = .nonPersistent()` means the web view's own cookies, `localStorage`, and cache do not survive the app quitting. Whatever survives an app restart is entirely the responsibility of a separate serializer that reads this panel's restoration snapshot, out of this file's scope.
- **Transmission**: None over a network by this file directly. The rendered page may make its own network requests as part of the extension's content, out of scope here. Locally, messages cross the WebKit/AppKit boundary through the script message handler and `callAsyncJavaScript`, never leaving the device.
- **Retention**: `state` lives exactly as long as this view controller instance does; `dispose()` clears the web view's content but does not clear `state` itself.

