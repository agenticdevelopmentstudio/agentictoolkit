<!-- leaf: implement-general-controller/webview-panel-view-controller · source: webview-panel-view-controller.md -->

# WebviewPanelViewController

## Overview

**Source**: `packages/apple/AgenticToolkit/macOS/Features/Extensions/Webview/WebviewPanelViewController.swift`

`WebviewPanelViewController` is the `NSViewController` behind one `vscode.window.createWebviewPanel` call, or a resolved webview view: it *is* the panel an extension holds, its `title` *is* the pane's title, and disposing it *is* closing the pane. It owns a single `WKWebView`, sandboxed behind a per-panel custom URL scheme (`agentic-webview://<panel id>/...`) served only by a `WebviewSchemeHandler` that honors the extension's declared resource roots; it injects the `acquireVsCodeApi()` bridge ahead of the extension's own markup so `postMessage`/`setState` work before the extension's first script runs; and it answers both the pieces of the `vscode` webview API a presenter needs (`ExtensionWebviewPanel`) and this app's own pane-hosting protocols (`PaneTitleProviding`, `PaneContentTeardown`). A reveal or a removal request that arrives before its presenter has installed a listener is captured and replayed exactly once, because an extension's own `deserializeWebviewPanel` can call `panel.reveal()` or dispose the panel before this app has anywhere to route that call.

