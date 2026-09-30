<!-- leaf: implement-extension-host-vs-2/code-api-main-thread-window--logging · source: extension-host-vs-code-api-main-thread-window.md -->

# MainThreadWindow

## Logging

`MainThreadWindow` conforms to `Loggable`, giving it a logger, but as of this source no member on this type calls through it. Every failure this adaptor detects reports itself to the extension directly, by rejecting or never settling the promise it returned, and nothing here yet fails in a way only a log line could report. The conformance is kept for the same reason `NotImplementedLedger` is injected rather than constructed locally: a future member that can fail in a way invisible to the extension (for example, a presenter throwing where none of the current contracts allow it) has a logger ready without another migration.
