<!-- leaf: implement-extension-host-vs-1/code-api-diagnostic-types--logging · source: extension-host-vs-code-api-diagnostic-types.md -->

# DiagnosticTypes

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `VSCodeAPI` (the shared logger declared once in `VSCodeAPI.swift` and reused by every `VSCodeAPI` extension file, including this one)

| Event | Level | Message |
|-------|-------|---------|
| `context.evaluateScript(diagnosticClassesSource)` returns `nil` or a non-object | error | `Could not install the 'vscode.DiagnosticSeverity'/'vscode.DiagnosticTag'/'vscode.DiagnosticRelatedInformation'/'vscode.Diagnostic' classes in context '<name>'; they stay the shim's not-implemented stub` |
| The evaluated result carries a non-undefined `installedError` | error | `Could not install the 'vscode.DiagnosticSeverity'/'vscode.DiagnosticTag'/'vscode.DiagnosticRelatedInformation'/'vscode.Diagnostic' classes in context '<name>': '<installedError>'; they stay the shim's not-implemented stub` |
| The installed container is missing one of the four expected members | error | `The 'vscode' diagnostic-types container in context '<name>' is missing one of 'DiagnosticSeverity', 'DiagnosticTag', 'DiagnosticRelatedInformation' or 'Diagnostic'; all four stay the shim's not-implemented stub` |
| An array passed to `VSCodeAPI.arrayLength(of:)` (via `diagnosticRelatedInformationArray`/`diagnosticTagArray`) reports a length over 100,000 | error | (logged inside `VSCodeAPI.swift`'s shared `arrayLength(of:)`, not inside this file): `refusing an array of <count> elements: longer than the 100000 this host decodes` |

No other event in this file is logged: neither a constructor's `TypeError` nor a reader's `nil` return for a malformed field is logged at the point it occurs — both are facts the code surfaces to the caller (as a thrown JS error, or as a `nil` Swift value) instead of a log line, per **diagnostic-constructor-validates-range**/**diagnostic-constructor-validates-message** and **diagnostic-decode-optional-field-malformed-refuses-whole-value**.
