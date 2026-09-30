<!-- leaf: implement-status-server/src--logging · source: status-server-src.md -->

# Status Server

## Logging

All logging is plain `console.error`; there is no logger subsystem or category.

| Event | Level | Message | When |
|-------|-------|---------|------|
| Cycle timeout exceeded | error | `cycle exceeded ${cycleTimeoutMs}ms — abandoning it and releasing the scheduler (self-heal)` | Watchdog timer fires during cycle execution |
| Cycle execution error | error | `cycle failed:` followed by the error as a second argument | The cycle callback throws an unhandled error |
| Unhandled HTTP error | error | Full error object logged to console | A non-HTTPException is caught by the global error handler |
