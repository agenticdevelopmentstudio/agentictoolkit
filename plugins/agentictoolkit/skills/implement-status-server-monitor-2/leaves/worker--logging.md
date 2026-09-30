<!-- leaf: implement-status-server-monitor-2/worker--logging · source: status-server-monitor-worker.md -->

# Status Server Monitor Worker

## Logging

This file itself contains no `console.*` call and defines no logger of its own — none of the three boot-time `Error` messages are separately logged here; they propagate as thrown exceptions (see Error states). A cycle failure is communicated only through the `CycleReply.error` field, not a log line from this file. Running a cycle on this thread can indirectly cause a log line from a collaborator external to this file — `runMonitorCycle`'s own `[maintenance]` line (`cycle-runner.ts`) on a full sync, and `provider-cooldown.ts`'s `console.error` `[cooldown] ...` line if a provider fetch reached through this cycle hits a 429 — but neither line is emitted by `worker.ts` itself.

| Event | Level | Message |
|-------|-------|---------|
| n/a — this file emits no log line of its own | n/a | n/a |
