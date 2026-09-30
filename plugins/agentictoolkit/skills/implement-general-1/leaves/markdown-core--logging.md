<!-- leaf: implement-general-1/markdown-core--logging · source: markdown-core.md -->

# MarkdownCore

## Logging

Subsystem: the app's bundle identifier, or the literal string `nil` when none is set | Category: `MarkdownStore`

| Event | Level | Message |
|-------|-------|---------|
| A listed document row has an unreadable timestamp | error | Names the marker table and the underlying parse error, both marked public for the system log |

`MarkdownStore.logger` is spelled out directly through the platform logging type rather than a shared logging protocol, because this target does not link the framework that protocol lives in.
