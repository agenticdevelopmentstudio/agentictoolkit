<!-- leaf: implement-extension-host-core-2/extensions-webview-resource-url--test-vectors · source: extension-host-core-extensions-webview-resource-url.md -->

# WebviewResourceURL

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wru-001 | resource-url-naming-only, percent-encoding-round-trip, candidate-canonicalization, containment-delegation, first-matching-root-wins | `url(forFile: root/"media/style.css", panelID: "panel-1")`, then `target(of:, panelID: "panel-1", localResourceRoots: [root])` | `.file(root/"media/style.css")`, canonicalized (source: `fileURLRoundTrips`) |
| wru-002 | percent-encoding-round-trip | the same round trip for the relative paths `"media/my style.css"`, `"media/a#b.css"`, `"media/100%.css"`, and `"média/ü.css"` | each round-trips to `.file(<that same file>)` (source: `awkwardPathsRoundTrip`) |
| wru-003 | host-document-url, host-document-detection | `hostDocumentURL(panelID: "panel-1")`, then `target(of:, panelID: "panel-1", localResourceRoots: [])` | `.hostDocument` (source: `hostDocumentIsDistinctFromAFile`) |
| wru-004 | host-document-detection, empty-roots-refuses-every-file | `target(of: hostDocumentURL(panelID: "panel-1"), panelID: "panel-1", localResourceRoots: [])` | `.hostDocument`, unaffected by an empty `localResourceRoots` (source: `hostDocumentNeedsNoRoots`) |
| wru-005 | empty-roots-refuses-every-file | `target(of: url(forFile: root/"style.css", panelID: "panel-1"), panelID: "panel-1", localResourceRoots: [])` | throws `WebviewResourceURLError` (source: `noRootsRefusesEveryFile`) |
| wru-006 | containment-delegation, containment-failure-payload | a file inside `elsewhere` looked up with `localResourceRoots: [allowed]`, where `elsewhere` is not `allowed` | throws `WebviewResourceURLError` (source: `outsideEveryRootIsRefused`) |
| wru-007 | containment-delegation, first-matching-root-wins | a file inside `second`, looked up with `localResourceRoots: [first, second]` | `.file(<that file>)`, allowed because the second root contains it (source: `anyDeclaredRootAllows`) |
| wru-008 | candidate-canonicalization, containment-delegation | `url(forFile: root/"../../../etc/passwd", panelID: "panel-1")` looked up against `localResourceRoots: [root]` | throws `WebviewResourceURLError` (source: `traversalOutOfTheRootIsRefused`) |
| wru-009 | containment-delegation | a file inside a directory named `"ext-evil"`, looked up against `localResourceRoots: [<the sibling directory "ext">]` | throws `WebviewResourceURLError`, even though `"ext-evil"` has `"ext"` as a string prefix (source: `siblingNamePrefixIsRefused`) |
| wru-010 | candidate-canonicalization, containment-delegation | `url(forFile: root, panelID: "panel-1")` (the root directory itself) looked up against `localResourceRoots: [root]` | throws `WebviewResourceURLError`; the root is not contained in itself (source: `theRootItselfIsRefused`) |
| wru-011 | panel-validation-second | a URL built with `panelID: "panel-2"`, looked up with `target(of:, panelID: "panel-1", localResourceRoots: [root])` | throws `WebviewResourceURLError.unexpectedPanel(declared: "panel-2", expected: "panel-1")` (source: `anotherPanelsURLIsRefused`) |
| wru-012 | scheme-validation-first | `target(of:, panelID:, localResourceRoots:)` for the raw URLs `"file:///etc/passwd"`, `"https://example.com/x.js"`, and `"data:text/html,<b>x</b>"` | each throws `WebviewResourceURLError` (source: `anotherSchemeIsRefused`) |
| wru-013 | scheme-constant | `WebviewResourceURL.scheme` | equals `"agentic-webview"`; is not one of `http`, `https`, `file`, `data`, `blob`, `about`, `ws`, `wss`, `ftp`, `javascript`; starts with a letter; and every character is a lowercase letter, digit, `+`, `-`, or `.` (source: `schemeIsStable`) |
| wru-014 | stateless-re-derivation, no-actor-isolation | call `target(of:panelID:localResourceRoots:)` concurrently from many detached tasks with different URLs and root arrays against the shared `WebviewResourceURL` namespace | every call returns the outcome its own arguments imply, with no crash and no result influenced by another concurrent call (traced to the absence of any stored property, actor, or `@MainActor` annotation, and to every parameter being passed by value) |
