<!-- leaf: implement-language/services-editor--test-vectors-part-3 · source: language-services-editor.md -->

# LanguageServicesEditor — Conformance Test Vectors (part 3)

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| language-services-editor-057 | document-read-failure-unsignaled | See OpenDocumentReloader.swift's `reloadIfNeeded`: the read-error catch has no dedicated test asserting silence, since the gap is the absence of a log call, not a return-value difference; the buffer-left-untouched behavior on read failure is exercised by "a deleted file leaves the buffer intact" (OpenDocumentReloaderTests.swift). | The buffer is untouched on a read failure; no test can observe that the failure is also unlogged. |
