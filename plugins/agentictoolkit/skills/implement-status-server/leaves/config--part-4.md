<!-- leaf: implement-status-server/config--part-4 · source: status-server-config.md -->

# Status Server Config — continued (part 4)

## Platform Notes

- **React/Web** (source platform): the three files live under
  `packages/web/packages/status-server/src/config/`, barreled through
  `index.ts`. `env.ts` reads a plain `Readonly<Record<string, string | undefined>>`
  (`EnvSource`) rather than importing `process` directly, so it also runs
  against a test fixture object; `port.ts` and `seed.ts` import nothing
  outside this package. The monitor-worker boundary these files are shaped
  for (`workerData`/`structuredClone`) is Node's `worker_threads`, in
  `src/monitor/worker-client.ts` and `worker.ts`, external to this recipe's
  three files.
- **SwiftUI / AppKit / UIKit**: no UI surface to port. A Swift
  re-implementation of this CONFIG PORT for a companion backend (Vapor or
  Hummingbird) would model `EnvSource` as `[String: String]` read from
  `ProcessInfo.processInfo.environment`, `StatusConfig` as a `Sendable`
  `struct` whose fields are plain stored properties resolved once at
  construction — Swift has no cheap analogue to a JS getter closing over a
  captured dictionary, so lazy-field-evaluation's "read at access, not at
  build" behavior would need to be reproduced explicitly (e.g. a computed
  property reading a stored `[String: String]`) if that semantics is
  required. `STATUS_CREDENTIAL_NAMES` maps to a `static let` array of an
  enum with a `String` raw value.
- **Compose**: same non-UI relationship. A Kotlin backend (Ktor) would model
  `EnvSource` as `Map<String, String?>` from `System.getenv()`, and
  `StatusConfig` as a `data class` whose numeric fields use `String?.toIntOrNull()`
  / `toDoubleOrNull()` — which, unlike the source's bare `Number()`, already
  returns `null` on a malformed string, closing the numeric-env-validation
  gap for free in a Kotlin port.
- **WinUI 3**: a WinUI 3 desktop app is a client of this backend and does
  not reimplement this config port; if a future product needed a .NET
  companion backend (ASP.NET Core Minimal API) that DID reimplement it, the
  mapping is concrete: `EnvSource` becomes an `IConfiguration`
  (`Microsoft.Extensions.Configuration`, or plain
  `Environment.GetEnvironmentVariable`); `StatusConfig` becomes an immutable
  `record` whose numeric properties are expression-bodied
  (`public int Port => int.TryParse(Env("PORT"), out var p) ? p : 3000;`),
  which both preserves the source's per-access laziness AND gets
  `int.TryParse`/`double.TryParse`'s built-in validation for free — the
  exact gap flagged by numeric-env-validation does not reproduce in a
  faithful C# port unless someone deliberately drops the `TryParse` guard.
  `STATUS_CREDENTIAL_NAMES` becomes a `static readonly ImmutableArray<string>`;
  `SeedEnvironment` becomes an `enum { Production, Staging, Testing }`;
  `SeedRoster` becomes `IReadOnlyList<SeedEndpoint>` of an immutable
  `record SeedEndpoint(string Group, string Name, string BaseSlug, string Host, IReadOnlyList<SeedEnvironment> Envs, string Kind, string? Path = null, int? ExpectedStatus = null)`.
  Because a `StatusConfig` here would likewise need to cross a background
  `Task`/`AppService` boundary, it should stay `System.Text.Json`-serializable
  with no delegate members — the same "no method survives the boundary"
  constraint the source states for `structuredClone`.

## Design Decisions

- **Decision**: implement every `StatusConfig` field `envConfig` returns
  as a getter over the captured `env` reference, rather than snapshotting
  each value into a plain field at construction time.
  **Rationale**: the source's own doc comment states this directly — a
  host constructs one `StatusConfig` at module load, and a test that
  mutates `process.env` afterward (a common pattern in this test suite)
  still needs the config to see the new value; only a getter that reads
  `env` on each access can do that.
  **Approved**: pending
- **Decision**: strip at most one trailing slash from `publicBaseUrl`
  (`/\/$/`, not a global pattern), instead of normalizing away every
  trailing slash.
  **Rationale**: not stated in source; this is a plain fact about the
  code's actual behavior (see public-base-url-trailing-slash-strip), not
  an idealized rationale invented for this recipe. It differs from the
  fuller slash/case/port canonicalization `routes/config.ts` applies to a
  peer's `baseUrl` (external to these three files), which strips every
  trailing slash — the two call sites simply solve different problems.
  **Approved**: pending
- **Decision**: default `glitchtipProjects` to "every project the org
  returns" rather than "no project" when `GLITCHTIP_PROJECTS` is unset.
  **Rationale**: the source comment states this directly — a fleet with
  one GlitchTip project needs no configuration to work, and the allowlist
  exists for the second project to *require*, not for the first to wait on;
  an all-comma value (`",,"`) is treated as a mistake, not an instruction
  to silence the feature, for the same reason.
  **Approved**: pending
- **Decision**: leave `port` and `probeIntervalSeconds` as unvalidated
  `Number()` coercions while routing `deploySyncSeconds` and
  `github.fetchTimeoutMs` through the stricter `positiveNumber` helper —
  see the open question on numeric-env-validation.
  **Rationale**: not stated in source; the asymmetry is a plain fact about
  the code, not a defended design. It is flagged rather than resolved here
  because deciding whether to add validation, and where (this adapter vs.
  its HTTP-listen/probe-scheduler callers), is a call for whoever owns
  those callers, not something derivable from `env.ts`, `port.ts`, or
  `seed.ts` alone.
  **Approved**: pending
- **Decision**: gate the SEC-M5 production guard on `NODE_ENV` only, not on
  `RAILWAY_ENVIRONMENT_NAME` — see production-guard-environment-signal.
  **Rationale**: not stated in source. Recorded here rather than resolved
  because closing it requires knowing how this service's actual Railway
  deployment sets `NODE_ENV`, which is outside what these three files (or
  this recipe) can determine.
  **Approved**: pending
- **Decision**: this recipe carries roughly forty Behavioral Requirements
  against `status-server-auth`'s forty, despite `env.ts`/`port.ts`/`seed.ts`
  having far fewer conditional branches than the five auth files.
  **Rationale**: the count is comparable because most of this component's
  behavior is field-by-field derivation (one getter, one requirement) with
  only two real decision points (the SEC-M5 guard, `monitorLabel`'s
  qualification), not because the two components are equally complex; the
  per-field granularity keeps each requirement independently testable
  rather than bundling twenty getters into one compound statement.
  **Approved**: pending
- **Decision**: this recipe's `related` field links to
  `agentictoolkit://recipes/status-server-auth` one-directionally; the
  reverse link on `status-server-auth.md` was not added.
  **Rationale**: this recipe was authored under an explicit constraint to
  write only `recipes/status-server-config.md` and touch no other file;
  cross-recipe-consistency's own text allows a unidirectional reference
  ("acceptable but bidirectional is preferred"), so this is a known,
  intentional gap in the preferred state, not an oversight.
  **Approved**: pending
