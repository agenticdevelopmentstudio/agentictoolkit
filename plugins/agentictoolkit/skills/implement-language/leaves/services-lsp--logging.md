<!-- leaf: implement-language/services-lsp--logging · source: language-services-lsp.md -->

# Language Services LSP

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via the `Loggable` protocol's
default) | Category: the conforming type's name

| Event | Level | Message |
|-------|-------|---------|
| Diagnostic/document forwarding failure while the session is not running | debug | `.notRunning` operation failure (`DocumentSyncPipeline.swift`) |
| Any other diagnostic/document forwarding failure | error | `record(_:operation:uri:)`'s default path (`DocumentSyncPipeline.swift`) |
| Channel forwarding-task failure | error | `LanguageServerChannel`'s stream-end handling (`LanguageServerChannel.swift`) |
| A second concurrent observation of a live session's state | fault | `observeState(of:id:)`'s refusal (`LanguageServerRegistry.swift`) |
| Session start/stop/teardown failures | error | `LanguageServerSession`'s failure-diagnosis pipeline (`LanguageServerSession.swift`) |

`DiagnosticStore.swift` and `LanguageServerDocumentSync.swift` conform to no
logging protocol and emit no log calls of their own — a plain fact about
these two files, not a gap; their failure signal is a ledger write
(`UpstreamDivergenceLedger`) or the observable state they publish, not a
log line.
