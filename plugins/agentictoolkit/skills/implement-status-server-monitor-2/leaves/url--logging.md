<!-- leaf: implement-status-server-monitor-2/url--logging · source: status-server-monitor-url.md -->

# Status Server Monitor URL

## Logging

This file makes no logging or console call of any kind; the log lines that end up quoting a
`hostOf` result (for example `sync.ts`'s `[sync] not removing monitors — …` and
`[sync] removed monitor … — …` reasons) are built and logged by the calling module, not by
this file.

| Event | Level | Message |
|-------|-------|---------|
| n/a | n/a | This file emits no log line at any level; `hostOf` and `projectPageUrl` produce no observable output beyond their own return values. |
