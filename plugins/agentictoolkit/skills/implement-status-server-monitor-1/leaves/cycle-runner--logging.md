<!-- leaf: implement-status-server-monitor-1/cycle-runner--logging · source: status-server-monitor-cycle-runner.md -->

# Status Server Monitor Cycle Runner

## Logging

This file uses a plain `console.log` call with a literal `[maintenance]` string prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| Retention prune deleted at least one row on a full sync | log (`console.log`) | `[maintenance] pruned <deleted> retention rows` (plus ` — more next cycle` when `done` is `false`) |

This is the only log line this file emits directly; a full sync whose prune deletes nothing produces no log output from this file at all, and a probe-only tick never reaches this line regardless of outcome.
