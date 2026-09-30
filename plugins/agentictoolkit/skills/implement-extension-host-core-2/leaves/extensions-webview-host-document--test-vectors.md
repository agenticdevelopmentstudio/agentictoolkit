<!-- leaf: implement-extension-host-core-2/extensions-webview-host-document--test-vectors · source: extension-host-core-extensions-webview-host-document.md -->

# WebviewHostDocument

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| webview-host-document-001 | bootstrap-injection-point, head-tag-closing-detection | `wrapping: "<html><head><title>x</title></head><body>hi</body></html>", initialState: nil` | Bootstrap script text appears strictly between `<head>` and `</head>` (`bootstrapGoesInsideHead`) |
| webview-host-document-002 | bootstrap-injection-point | `wrapping: "<html><head><script>acquireVsCodeApi()</script></head><body></body></html>", initialState: nil` | The bootstrap's occurrence of `messageHandlerName` precedes the extension's own `acquireVsCodeApi()` text (`bootstrapPrecedesTheExtensionsScripts`) |
| webview-host-document-003 | bootstrap-prepend-fallback | `wrapping: "<p>hi</p>", initialState: nil` | Bootstrap precedes `<p>hi</p>` in the returned document (`bootstrapSurvivesAMissingHead`, arg 1) |
| webview-host-document-004 | bootstrap-prepend-fallback | `wrapping: "<html><body>hi</body></html>", initialState: nil` | Bootstrap precedes the given markup in the returned document (`bootstrapSurvivesAMissingHead`, arg 2) |
| webview-host-document-005 | bootstrap-prepend-fallback | `wrapping: "", initialState: nil` | Returned document contains the bootstrap's `messageHandlerName` occurrence; nothing else is present to compare against (`bootstrapSurvivesAMissingHead`, arg 3) |
| webview-host-document-006 | head-tag-match-case-insensitive, head-tag-closing-detection | `wrapping: "<HTML><HEAD></HEAD><BODY>hi</BODY></HTML>", initialState: nil` | Bootstrap injected strictly between `<HEAD>` and `</HEAD>` (`headIsMatchedCaseInsensitively`) |
| webview-host-document-007 | extension-markup-passthrough | `wrapping: "<html><head></head><body><p>café &amp; crème</p><img src=\"a#b.png\"></body></html>", initialState: nil` | Returned document contains the given `<body>...</body>` substring unchanged (`markupIsCarriedThroughUnchanged`) |
| webview-host-document-008 | initial-state-undefined-vs-value | `wrapping: "<html><head></head><body></body></html>", initialState: "{\"scrollTop\":42}"` | Returned document contains `42` (`stateIsEmbedded`) |
| webview-host-document-009 | script-close-tag-neutralized | `initialState: "{\"note\":\"</script><script>alert(1)</script>\"}"` | Returned document does not contain `<script>alert(1)` literally and does not contain the raw payload unescaped (`stateCannotBreakOutOfTheScriptElement`) |
| webview-host-document-010 | html-comment-open-neutralized | `initialState` note field containing each of `<!--`, `-->`, `<!--<script>`, `</SCRIPT >` in turn | Returned document does not contain that raw payload unescaped, for every one of the four inputs (`stateCannotOpenAComment`) |
| webview-host-document-011 | initial-state-undefined-vs-value | `wrapping: "<html><head></head><body></body></html>", initialState: nil` | Returned document contains the bare token `undefined` (`absentStateIsUndefined`) |
| webview-host-document-012 | message-handler-name-constant | `WebviewHostDocument.messageHandlerName` | Equals `"agenticWebview"`; first character is a letter; every character is a letter or digit (`messageHandlerNameIsStable`) |
| webview-host-document-013 | message-kind-closed-set | `MessageKind.allCases` against a rendered bootstrap | Every case's `rawValue` appears in the rendered document (`messageKindsAreClosed`) |
| webview-host-document-014 | quoted-attribute-ambiguity-bailout | `wrapping: "<p>x</p><head data-x=\">oops\">content</head>"` (a quoted attribute containing `>`) | `headStartTagEnd(in:)` returns `nil`; the bootstrap is prepended before `<p>x</p>` rather than inserted mid-attribute (derived directly from the source; not exercised by a named test in the given source) |
| webview-host-document-015 | head-vs-header-disambiguation | `wrapping: "<header>nav</header><head></head>"` | The bootstrap is inserted inside the real `<head></head>`, not before `<header>` (derived directly from the source; not exercised by a named test in the given source) |
| webview-host-document-016 | acquire-once-guard | The literal text of `bootstrapScript(initialState:)`'s generated string | Contains the exact substring `already been acquired` guarded by an `if (acquired)` check (derived directly from the source; the Swift test suite asserts only that the resulting document contains this JavaScript text, not that a JS engine actually throws on a second call) |
