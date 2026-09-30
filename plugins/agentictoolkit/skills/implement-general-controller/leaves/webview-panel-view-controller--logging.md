<!-- leaf: implement-general-controller/webview-panel-view-controller--logging · source: webview-panel-view-controller.md -->

# WebviewPanelViewController

## Logging

Subsystem: `{{bundle_id}}` | Category: `WebviewPanelViewController`

| Event | Level | Message |
|-------|-------|---------|
| A page's `post(message:)` value cannot be bridged to WebKit | error | `A webview message held a value WebKit cannot pass to a page; dropping it` |
| A page's `setState` value cannot be encoded as JSON | error | `A webview's setState value was not JSON; dropping it` |
| An external-open request arrives while rate-limited | notice | `A webview asked to open links faster than a person can click; dropping one` |
