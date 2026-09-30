<!-- leaf: implement-status-server-monitor-1/issues--logging · source: status-server-monitor-issues.md -->

# Status Server Monitor Issues

## Logging

This file uses plain `console.warn`/`console.error` calls with a literal `[ledger]` prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| A shadow row retired for a target that already had a canonical open row | warn (`console.warn`) | `[ledger] retired duplicate open issue #<id> for <target> — uniq_open_issue_per_target should have prevented it` |
| A storage write (insert, update, or resolve) threw for one target | error (`console.error`) | `[ledger] write failed for <target> — skipped, the next cycle re-derives it: <error message>` |

A successful open, update, or recovered/unmonitored resolve produces no log output at all, at any level.
