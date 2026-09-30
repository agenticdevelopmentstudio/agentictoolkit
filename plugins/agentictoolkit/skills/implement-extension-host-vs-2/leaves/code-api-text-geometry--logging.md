<!-- leaf: implement-extension-host-vs-2/code-api-text-geometry--logging · source: extension-host-vs-code-api-text-geometry.md -->

# TextGeometry

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `VSCodeAPI` (the shared logger declared once in `VSCodeAPI.swift` and reused by every `VSCodeAPI` extension file, including this one)

| Event | Level | Message |
|-------|-------|---------|
| `context.evaluateScript(textGeometryClassesSource)` returns `nil` or a non-object | error | `Could not install the 'vscode.Position'/'vscode.Range'/'vscode.Location' classes in context '<name>'; they stay the shim's not-implemented stub` |
| The evaluated result carries a non-`undefined` `installedError` | error | `Could not install the 'vscode.Position'/'vscode.Range'/'vscode.Location' classes in context '<name>': '<message>'; they stay the shim's not-implemented stub` |
| The resolved container is missing `Position`, `Range`, or `Location` | error | `The 'vscode' text-geometry container in context '<name>' is missing 'Position', 'Range' or 'Location'; all three stay the shim's not-implemented stub` |

No other event in this file is logged: the failed cache-write `Object.defineProperty` inside `textGeometryClassesSource` is caught and silently ignored (per **cache-write-optional**), and `positionValue(for:in:)`/`rangeValue(for:in:)`/`locationValue(for:in:)` each clear a construction-time exception without logging it (per their respective **-clears-exception-on-throw** requirements).
