<!-- leaf: implement-extension-host-vs-2/code-api-main-thread-window · source: extension-host-vs-code-api-main-thread-window.md -->

## Overview

`MainThreadWindow` is the `@MainActor`-isolated adaptor that answers everything
an extension reaches for on `vscode.window`'s message, quick-pick, input-box
and status-bar surface: `showInformationMessage`, `showWarningMessage`,
`showErrorMessage`, `showQuickPick`, `showInputBox` and
`createStatusBarItem`. It is not a UI component itself — it holds no view,
draws nothing, and has no appearance. Every call it receives from the
embedded JavaScript engine is parsed, coerced and validated against the
extension's actual arguments, then handed to one of four injected presenter
protocols (`ExtensionMessagePresenting`, `ExtensionQuickPickPresenting`,
`ExtensionInputBoxPresenting`, `ExtensionStatusBarPresenting`) that do the
real presenting; this recipe documents the adaptor's own contract —
argument parsing, coercion, promise settlement, status-bar item bookkeeping
and teardown — not the four presenter protocols' own contracts, which each
already have their own recipe. A fifth collaborator, `NotImplementedLedger`,
receives a record whenever a status-bar item's `tooltip` or `command` is set
to a shape this host does not project (a `MarkdownString`-typed tooltip or a
`Command`-object-typed command).

The type is non-`Sendable` and `@MainActor`-isolated by design: every member
it exposes is called from JavaScriptCore's synchronous bridge, which itself
only ever calls in from the main actor, so there is no cross-actor hop to
document. It conforms to `Loggable` but, as of this source, none of its
members call through the logger — every failure this adaptor detects is
reported to the extension itself, by rejecting or never settling the promise
it returned, not by a log line.

