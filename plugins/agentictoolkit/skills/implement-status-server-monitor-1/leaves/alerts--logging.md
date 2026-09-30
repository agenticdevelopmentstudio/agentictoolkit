<!-- leaf: implement-status-server-monitor-1/alerts--logging · source: status-server-monitor-alerts.md -->

# Status Server Monitor Alerts

## Logging

This file uses a plain `console.error` call with a literal `[alerts]` string prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| Webhook delivery failure (network error or 5,000ms abort) | error (`console.error`) | `[alerts] webhook delivery failed (<n> alerts): <error message>` |

This is the only log line this file emits — a successful flush produces no log output at all, at any level.
