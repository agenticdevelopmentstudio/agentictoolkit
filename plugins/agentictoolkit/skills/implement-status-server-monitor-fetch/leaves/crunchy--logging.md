<!-- leaf: implement-status-server-monitor-fetch/crunchy--logging · source: status-server-monitor-fetch-crunchy.md -->

# Status Server Monitor Fetch Crunchy

## Logging

Subsystem: process `console` | Category: monitor

| Event | Level | Message |
|-------|-------|---------|
| The `/clusters` response's `ok` is `false` | error | `` Crunchy /clusters <status> `` |
| The `fetch` call, the abort, or the JSON parse threw | error | `` Crunchy /clusters fetch <err> `` |
