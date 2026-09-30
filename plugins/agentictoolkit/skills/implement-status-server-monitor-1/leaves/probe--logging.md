<!-- leaf: implement-status-server-monitor-1/probe--logging · source: status-server-monitor-probe.md -->

# Status Server Monitor Probe

## Logging

This file uses one plain `console.error` call with a literal `[probe]` message prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| A capped body read fails mid-stream for a reason other than the timeout/abort signal firing | error (`console.error`) | `[probe] body read failed after headers: <message>` |

This is the only log line this file emits directly; every other outcome (DNS failure, HTTP error status, timeout, marker mismatch) is communicated purely through the returned `Probe` value, with no log call of its own.
