<!-- leaf: implement-status-server-monitor-2/provider-conn--logging · source: status-server-monitor-provider-conn.md -->

# Status Server Monitor Provider Conn

## Logging

Neither `providerConn` nor `enumerateDeployProjects` calls `console.*` or any other logger at any point in the given source. A failure from either surfaces only as a rejected `Promise` to the caller (see Edge Cases: Error states) — there is no log line emitted by this file itself, in contrast to `enumerateDeployProjectsFrom` (external), which does log via `console.error` on a Railway domain-lookup timeout that fires with its box already aborted.
