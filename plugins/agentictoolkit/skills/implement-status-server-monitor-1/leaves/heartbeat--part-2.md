<!-- leaf: implement-status-server-monitor-1/heartbeat--part-2 · source: status-server-monitor-heartbeat.md -->

# Status Server Monitor Heartbeat — continued (part 2)

## Design Decisions

- **Decision**: check the resolved `Response`'s `ok` flag explicitly and log a distinct message when it is `false`, rather than treating any resolved (non-rejected) `fetch` call as a successful check-in.
  **Rationale**: stated directly in the source comment on `pingHeartbeat` — `fetch()` only REJECTS on a network-level failure; a 404 from a typo'd or deleted check-in URL resolves happily. Without this check, every cycle would believe it checked in while the external dead-man service never saw a valid ping — silently defeating the entire purpose of the file.
  **Approved**: pending
- **Decision**: catch every rejection from the `fetch` call — both a genuine network failure and the 5,000ms `AbortSignal.timeout` firing — with one `catch` block that logs and resolves normally, rather than letting either propagate.
  **Rationale**: the function's own doc comment states the constraint directly — "a slow or failing heartbeat endpoint must never fail (or stall) the cycle that is trying to report its own success." The health-check mechanism itself must never become the reason the monitor cycle it is reporting on appears to fail.
  **Approved**: pending
- **Decision**: hardcode the 5,000ms timeout (`HEARTBEAT_TIMEOUT_MS`) and the literal `User-Agent` string as module constants, rather than exposing either as a parameter or an environment-configurable value.
  **Rationale**: not spelled out beyond the constant's own name; recorded here as an observed, deliberate fact rather than an invented rationale. The module's header comment notes full syncs run "every ~5min," so a fixed several-second budget for one outbound GET leaves ample margin without needing to be tunable per deployment, and a single hardcoded identifying `User-Agent` is enough for an operator to recognize the caller in the receiving service's logs.
  **Approved**: pending
- **Decision**: take no default for `url` and read no environment variable directly, leaving both "which endpoint" and "on vs. off" entirely to the caller.
  **Rationale**: stated directly in the function's own doc comment — "`url` is `config.heartbeatUrl` — this module takes no default and never reads env itself." This keeps `pingHeartbeat` a pure, side-effect-parameterized function that unit tests can call directly with any `url` value, with no need to stub `process.env`, matching how `heartbeat.int.test.ts` exercises it.
  **Approved**: pending
