<!-- leaf: implement-status-server-monitor-1/heartbeat--logging · source: status-server-monitor-heartbeat.md -->

# Status Server Monitor Heartbeat

## Logging

This file uses plain `console.error` calls with a literal `[heartbeat]` string prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| Response resolved with a non-2xx status | error (`console.error`) | `[heartbeat] check-in URL answered <status> — the dead-man ping is NOT registering; verify HEARTBEAT_URL` |
| `fetch` rejected (network failure or the 5,000ms abort) | error (`console.error`) | `[heartbeat] ping failed: <message>` |

These are the only two log lines this file emits — a successful `2xx` ping, and the `null`/empty-`url` no-op, each produce no log output at all, at any level.
