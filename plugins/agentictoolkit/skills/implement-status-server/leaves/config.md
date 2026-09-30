<!-- leaf: implement-status-server/config · source: status-server-config.md -->

# Status Server Config

## Overview

This is the status backend's configuration layer: three files under
`src/config/` (barreled through `index.ts`) that together define what the
rest of the package is allowed to know about the host it runs in.
`port.ts` is the configuration port: the `StatusConfig` interface every
other module reads, the `STATUS_CREDENTIAL_NAMES` registry of provider
credentials looked up by name, and three small pure functions derived from
a `StatusConfig` (`deploySyncIntervalMs`, `glitchtipConfigured`,
`posthogConfigured`). `env.ts` is `envConfig`, the one shipped adapter that
builds a `StatusConfig` from `process.env`-shaped input using the variable
names the host's `.env.example` documents; nothing else in this package
reads the environment directly. `seed.ts` is the seed-roster port: the
types (`SeedEnvironment`, `SeedEndpoint`, `SeedRoster`) describing the
host-supplied list of sites `POST /config/seed` turns into groups, sites,
and endpoints.

Both `StatusConfig` and `SeedRoster` are plain data by design — no method,
because a `StatusConfig` crosses into the monitor worker via
`worker_threads`' `workerData` (`MonitorWorkerData`, in
`src/monitor/worker-client.ts`, external to these three files), and
`structuredClone` drops any function it meets. The actual fan-out from a
`SeedRoster` into database rows (`runSeed` in `src/routes/config.ts`), the
consumers of `StatusConfig.credentials`/`secrets` (the provider auto-seed in
that same route, `glitchtipConfigured`/`posthogConfigured`'s callers in
`src/board/facts.ts` and `src/telemetry/server.ts`, and
`config.authDisabled`/`cookieSecure`/`peerToken`/`github` in
`status-server-auth`'s five files), and the credential-name self-check in
`src/monitor/integrations.ts` are all external to `env.ts`, `port.ts`, and
`seed.ts`; this recipe cites them only where the contract of these three
files depends on them, and specifies their internals nowhere.

