<!-- leaf: implement-extension-host/extensions-host--logging · source: extension-host-extensions-host.md -->

# Extension Host

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (falls back to `"nil"` if unset, via the shared `Loggable` protocol) | Category: `ExtensionHost` and `ExtensionHostInstallation`/`ExtensionHostInstaller` respectively.

| Event | Level | Message |
|-------|-------|---------|
| A `console.*` call at any level (`.debug`/`.info`/`.warn`/`.error`/`.log`) | debug / info / warning / error / log (matching the console level) | `[<identifier>] <text>` |
| A `defineVSCodeMember` definition the shim refused, withdrawn from the replay queue | error | `Extension '<identifier>' withdrew the definition of '<name>' on '<namespacePath>', declared at <origin>: the shim refused it, so that member stays a not-implemented stub on every later activation` |
| `disposeSubscriptions()` could not call into the runtime at all | error | `Extension '<identifier>' could not dispose its context.subscriptions.` |
| One subscribed disposable threw while being disposed | error | `Extension '<identifier>' registered a disposable that threw while being disposed: <failure>` |
| `vscode.Uri` could not be installed on a fresh runtime | error | `Extension '<identifier>' could not have 'vscode.Uri' installed (<message>); it stays the shim's not-implemented stub` |
| An eagerly-installed `vscode.*` member (from `installVSCodeMembers`) failed to install | error | `Extension '<identifier>' could not have 'vscode.<memberName>' installed (<message>); it stays the shim's not-implemented stub` |
| The extension's module failed to compile | error | `Extension '<identifier>' would not compile: <message>` |
| The extension threw while its module was loading, or from a fired timer | error | `Extension '<identifier>' threw while loading: <message>` / `Extension '<identifier>' threw from a timer: <message>` |
| The extension threw from `activate()` | error | `Extension '<identifier>' threw from activate(): <message>` |
| An extension exports no `activate()` function | info | `Extension '<identifier>' exports no activate() function` |
| An unimplemented member reached for, first access only | notice | `Extension '<identifier>' reached for '<memberPath>', which is not implemented yet` |
| A negative feature-detection probe, first probe only | notice | `Extension '<identifier>' checked for '<memberPath>' and was told it does not exist` |
| A timer task finished that was never counted as running (an assertion failure in Debug) | fault | `Extension '<identifier>' finished a timer task that was never counted as running` |
| A restored webview panel or contributed view names an extension that is not installed | notice | `The contributed webview view '<viewID>' names extension '<identifier>', which is not installed; its pane keeps its placeholder` (and the tree-view/webview-panel equivalents) |
| More than one installed extension claims a restored webview panel's view type | error | `<count> installed extensions claim webview panel type '<viewType>'; '<identifier>' gets it` |
| An extension's `onCommand:` id is already registered by something else | notice | `Extension '<identifier>' declares 'onCommand:<id>', but '<id>' is already registered: that trigger will not activate it` |
| An extension activated without registering a command its manifest contributes | error | `Extension '<identifier>' activated without registering '<commandID>', a command its manifest contributes` |
| A status bar item's command failed to execute | error | `A status bar item's command '<command>' did not run: <error>` |
