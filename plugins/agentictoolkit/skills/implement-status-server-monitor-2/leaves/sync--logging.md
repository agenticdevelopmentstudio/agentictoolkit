<!-- leaf: implement-status-server-monitor-2/sync--logging · source: status-server-monitor-sync.md -->

# Status Server Monitor Sync

## Logging

This file uses plain `console.log`/`console.error` calls with a literal `[sync]` prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| A doomed endpoint's `retireEndpoint` call succeeded | log (`console.log`) | `[sync] removed monitor <name> (<url>) — <reason>` |
| A doomed endpoint's `retireEndpoint` call rejected | error (`console.error`) | `[sync] failed to remove monitor <slug> (<reason>): <err>` |
| `endpointsClaimedByNothing` withheld a verdict | log (`console.log`) | `[sync] not removing monitors — <reason>` (once per withheld reason) |
| A provider is under an active rate-limit cooldown | error (`console.error`) | `[sync] <label> is rate-limited — skipping until <ISO>` |
| A provider poll exceeded the 20s cap | error (`console.error`) | `[sync] <label> poll exceeded 20000ms — treating as unreachable` |
| A provider poll threw | error (`console.error`) | `[sync] <label> poll threw — treating as unreachable: <err>` |
| Every configured deploy fetcher returned `ok:false` this cycle | error (`console.error`) | `[sync] all deploy fetchers failed — skipping prune` |
| `enumerateDeployProjects` rejected | error (`console.error`) | `[sync] deploy-project enumeration failed — skipping monitor removal: <err>` |
