<!-- leaf: implement-extension-host-core-1/extensions-activation-event-matcher--test-vectors · source: extension-host-core-extensions-activation-event-matcher.md -->

# ActivationEventMatcher

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| aem-001 | event-kind-cases, glob-triage | `ActivationEvent(rawValue: "*")` | `kind == .any`; `rawValue == "*"` |
| aem-002 | entry-parsing-order | `ActivationEvent(rawValue: "onStartupFinished")` | `kind == .startupFinished` |
| aem-003 | prefixed-payload-extraction | `ActivationEvent(rawValue: "onLanguage:swift")` | `kind == .language("swift")` |
| aem-004 | prefixed-payload-extraction | `ActivationEvent(rawValue: "onCommand:foo.bar")` | `kind == .command("foo.bar")` |
| aem-005 | prefixed-payload-extraction | `ActivationEvent(rawValue: "onWebviewPanel:markdown.preview")` | `kind == .webviewPanel("markdown.preview")` |
| aem-006 | empty-payload-rejection | `ActivationEvent(rawValue: "onLanguage:")`, `"onCommand:"`, `"workspaceContains:"`, `"onWebviewPanel:"`, `"onView:"` | each is `nil` |
| aem-007 | empty-entry-rejection, unrecognized-entry-rejection | `ActivationEvent(rawValue: "")`, `"   "`, `"onDebug"` | each is `nil` |
| aem-008 | whitespace-trimming | `ActivationEvent(rawValue: "  onStartupFinished  ")` | `kind == .startupFinished`; `rawValue == "  onStartupFinished  "` |
| aem-009 | parse-triage, eager-activation-flag | manifest `activationEvents: ["onStartupFinished", "onDebug", "onLanguage:swift"]` | `events` holds the two recognized entries in order; `unrecognizedEvents == ["onDebug"]`; `activatesEagerly == false` |
| aem-010 | eager-activation-flag, eager-short-circuit | manifest `activationEvents: ["*"]` | `activatesEagerly == true`; `matches(.startupFinished)`, `matches(.documentOpened(languageID: "swift"))`, `matches(.commandInvoked("anything"))` and `matches(.workspaceScanned(WorkspaceScan(relativePaths: [])))` are all `true` |
| aem-011 | startup-match | manifest `activationEvents: ["onStartupFinished"]` | `matches(.startupFinished) == true`; `matches(.documentOpened(languageID: "swift")) == false` |
| aem-012 | document-opened-match | manifest `activationEvents: ["onLanguage:swift"]` | `matches(.documentOpened(languageID: "swift")) == true`; `matches(.documentOpened(languageID: "Swift")) == false` (case-sensitive) |
| aem-013 | command-match | manifest `activationEvents: ["onCommand:a.b"]` | `matches(.commandInvoked("a.b")) == true`; `matches(.commandInvoked("a")) == false` |
| aem-014 | empty-manifest-no-match | manifest with empty `activationEvents` and no `contributes.commands` | `activatesEagerly == false`; `matches(_:)` is `false` for `.startupFinished`, `.documentOpened(languageID: "swift")`, `.commandInvoked("x")` and `.workspaceScanned(WorkspaceScan(relativePaths: ["a"]))` |
| aem-015 | implicit-activation-floor, command-match | manifest with `engines.vscode: "^1.74.0"`, `contributes.commands: [{command: "x.run", ...}]`, no `onCommand:` entry | `implicitlyActivatingCommands == ["x.run"]`; `matches(.commandInvoked("x.run")) == true` |
| aem-016 | implicit-activation-floor | same manifest with `engines.vscode: "^1.73.0"` | `implicitlyActivatingCommands` is empty; `matches(.commandInvoked("x.run")) == false` |
| aem-017 | implicit-activation-floor | same manifest with `engines.vscode: "*"` | `implicitlyActivatingCommands == ["x.run"]` (an unconstrained engine takes the same branch as a modern floor, per the source's own note on `*` not being a declared minimum of 0.0.0) |
| aem-018 | implicit-activation-unparseable-engine | same manifest with `engines.vscode: "~1.74.0"` (a shape `VSCodeEngineRange` does not parse) | `implicitlyActivatingCommands` is empty; `matches(.commandInvoked("x.run")) == false` |
| aem-019 | command-match | manifest with `engines.vscode: "^1.60.0"`, `activationEvents: ["onCommand:x.run"]`, `contributes.commands: [{command: "x.run", ...}]` | `implicitlyActivatingCommands` is empty, yet `matches(.commandInvoked("x.run")) == true` (the explicit `onCommand:` entry matches independently of the implicit-activation floor) |
| aem-020 | glob-syntax-supported, glob-anchoring | pattern `"*.csproj"` vs path `"a.csproj"` | matches; vs path `"src/a.csproj"` | does not match (a single `*` never crosses a path separator) |
| aem-021 | glob-syntax-supported | pattern with a leading whole-segment double-`*` followed by a separator, then `*.csproj`, vs path `"a.csproj"` | matches; vs a deeply nested path ending in `.csproj` | matches (the whole-segment double-`*` crosses separators) |
| aem-022 | glob-syntax-supported | pattern `"?.txt"` vs path `"a.txt"` | matches; vs path `"ab.txt"` | does not match |
| aem-023 | glob-syntax-supported | a brace group of two comma-separated alternatives (for example `package.json` or `bower.json`) vs each alternative's exact filename | matches both; vs an unrelated filename | does not match |
| aem-024 | glob-syntax-unsupported | pattern `"[abc].txt"` | `GlobPattern.init` returns `nil`; the raw text `"[abc].txt"` is appended to `unsupportedPatterns`; `matches(.workspaceScanned(...))` never matches it |
| aem-025 | glob-syntax-unsupported | pattern beginning with `"!"` | `GlobPattern.init` returns `nil`; raw text appended to `unsupportedPatterns` |
| aem-026 | glob-anchoring | pattern `"a.txt"` vs path `"axtxt"` | does not match (no substring match) |
| aem-027 | workspace-scanned-match | pattern that parses, `WorkspaceScan(relativePaths: [])` (empty scan) | `matches(.workspaceScanned(scan)) == false` |
| aem-028 | backtracking-memoization | an adversarial pattern with several whole-segment double-`*` tokens separated by literal `a` characters and ending in a literal `b`, matched against a long run of `a` characters with no trailing `b` | resolves to `false` without an exponential increase in search time as more double-`*` segments are added |
| aem-029 | webview-panel-restored-match | manifest `activationEvents: ["onWebviewPanel:markdown.preview"]` | `matches(.webviewPanelRestored(viewType: "markdown.preview")) == true`; `matches(.webviewPanelRestored(viewType: "markdown.other")) == false` |
| aem-030 | webview-panel-ownership-exclusion | manifest `activationEvents: ["*"]` | `matches(.webviewPanelRestored(viewType: "markdown.preview")) == true`, but `declaresWebviewPanel(viewType: "markdown.preview") == false` |
| aem-031 | webview-panel-ownership-exclusion | manifest `activationEvents: ["onStartupFinished", "onWebviewPanel:markdown.preview"]` | `declaresWebviewPanel(viewType: "markdown.preview") == true`; `declaresWebviewPanel(viewType: "markdown.Preview") == false` (case-sensitive); `declaresWebviewPanel(viewType: "") == false` |
| aem-032 | view-shown-match | manifest `activationEvents: ["onView:explorer"]` | `matches(.viewShown(viewID: "explorer")) == true`; `matches(.viewShown(viewID: "other")) == false`. Source-only: `ActivationEventMatcherTests.swift` covers `onView:` parsing into `.view("explorer")` but has no dedicated `matches(.viewShown(_:))` assertion; this vector is traced to `ActivationEventMatcher.matches(_:)`'s `.viewShown` case, which follows the exact same pattern as the tested `.webviewPanelRestored` case. |
