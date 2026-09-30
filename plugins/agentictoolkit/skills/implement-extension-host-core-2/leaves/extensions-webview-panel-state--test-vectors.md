<!-- leaf: implement-extension-host-core-2/extensions-webview-panel-state--test-vectors · source: extension-host-core-extensions-webview-panel-state.md -->

# WebviewPanelState

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| whps-001 | round-trip-fidelity, sorted-key-encoding | `WebviewPanelState(viewType: "markdown.preview", title: "Preview README.md", state: #"{"scrollTop":420}"#, options: defaultOptions).encoded()`, then `init(json:)` on the result | the restored value equals the original (source: `roundTripsThroughText`) |
| whps-002 | absent-state-omits-key | `WebviewPanelState(viewType: "markdown.preview", title: "Preview", state: nil, options: defaultOptions).encoded()`, then `init(json:)` on the result | `restored.state == nil` (source: `absentStateStaysAbsent`) |
| whps-003 | state-carried-verbatim | encode then decode a state value of `{"note":"line\nbreak \"quoted\" café"}` | `restored.state` equals that exact string, unchanged (source: `theExtensionsStateIsCarriedVerbatim`) |
| whps-004 | state-carried-verbatim | encode then decode a state value of the literal text `null` (a two-character string, not JSON `null`) | `restored.state == "null"` as a string value, distinct from an absent state (source: `theExtensionsStateIsCarriedVerbatim`) |
| whps-005 | unknown-fields-ignored | `init(json: #"{"viewType":"markdown.preview","title":"Preview","iconPath":"a.png"}"#)` | decodes successfully; `restored.viewType == "markdown.preview"` and `restored.title == "Preview"`; the unknown `iconPath` key causes no error (source: `unknownFieldsAreIgnored`) |
| whps-006 | missing-view-type-refused | `init(json: #"{"title":"Preview"}"#)` | throws (source: `aMissingViewTypeIsRefused`) |
| whps-007 | malformed-text-refused | `init(json: "")`, `init(json: "not json")`, `init(json: "{")`, `init(json: "[]")`, `init(json: #""markdown.preview""#)` | each call throws (source: `malformedTextIsRefused`) |
| whps-008 | round-trip-fidelity | `WebviewPanelState(viewType: "vendor.view-type_2", title: #"Preview "a"b.md — café"#, state: nil, options: defaultOptions)` encoded then decoded | the restored value equals the original, including the quote and em-dash in the title (source: `awkwardTitlesSurvive`) |
| whps-009 | missing-options-default-safe, sendable-value-type | `options: WebviewPanelOptions(enableScripts: true, enableForms: nil, localResourceRoots: nil)` encoded then decoded | `restored.options.enableScripts == true` and `restored.options.enableForms == true` (source: `scriptsSurviveTheRoundTrip`) |
| whps-010 | round-trip-fidelity | `options: WebviewPanelOptions(enableScripts: true, enableForms: nil, localResourceRoots: [])` (an explicit empty-array declaration) encoded then decoded | `restored.options.resourceRoots(extensionDirectory:workspaceRoots:)` returns an empty array — the renounced-file-access declaration is not decoded back into the default roots (source: `anEmptyRootDeclarationSurvives`) |
| whps-011 | round-trip-fidelity | `options: WebviewPanelOptions(enableScripts: nil, enableForms: nil, localResourceRoots: [<two URLs>])` encoded then decoded | `restored.options.resourceRoots(...)` returns exactly those two directories, in the same order (source: `declaredRootsSurvive`) |
| whps-012 | missing-options-default-safe | `init(json: #"{"viewType":"markdown.preview","title":"Preview"}"#)` (no `options` key at all) | `restored.options.enableScripts == false`, `restored.options.enableForms == false`, and `resourceRoots(extensionDirectory:workspaceRoots:)` returns the extension directory followed by the workspace root (source: `absentOptionsDecodeToTheSafePosture`) |
| whps-013 | missing-title-defaults-empty | `init(json: #"{"viewType":"v"}"#)` (no `title` key) | decodes successfully with `restored.title == ""` (traced to the `decodeIfPresent(String.self, forKey: .title) ?? ""` line; not a named test in the source) |
