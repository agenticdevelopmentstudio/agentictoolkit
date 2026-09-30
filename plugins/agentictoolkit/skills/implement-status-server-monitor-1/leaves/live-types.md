<!-- leaf: implement-status-server-monitor-1/live-types · source: status-server-monitor-live-types.md -->

**Rules** (cite as `implement-status-server-monitor-1/live-types#<slug>`):

- `producer-consumer-value-honor-route-fan-out` MUST — live-types.ts declares the /api/live wire contract: LiveSnapshot, "one self-contained snapshot of everything the client …
- `type-only-no-runtime` MUST
- `live-service-dto-extends-service-status` MUST
- `dns-ok-semantics` MUST
- `down-since-is-server-truth` MUST
- `stale-prod-dto-shape` MUST
- `provider-key-closed-set` MUST
- `provider-health-independent-fields` MUST
- `providers-map-is-total` MUST
- `live-snapshot-bundles-the-full-picture` MUST
- `generated-at-is-read-time` MUST
- `last-cycle-at-is-data-freshness-clock` MUST
- `last-cycle-at-distinct-from-health-clock` MUST
- `probe-interval-ms-scales-staleness` MUST
- `monitor-version-is-railway-commit-or-null` MUST
- `config-degraded-flag` MUST
- `config-reason-nullable-and-unconstrained-when-degraded` MUST
- `all-fields-required` MUST

# Status Server Monitor Live Types

## Overview

`live-types.ts` declares the `/api/live` wire contract: `LiveSnapshot`, "one self-contained snapshot of everything the client displays, pulled live from providers + HTTP probes," together with the four members it bundles — `LiveServiceDTO` (a per-endpoint health row extending the sibling `./types` module's `ServiceStatusDTO` with `dnsOk` and `downSince`), `StaleProdDTO` (an already-stale Vercel production deployment), `ProviderKey` (the closed set of platforms the monitor polls) and `ProviderHealth` (one provider's configured/reachable pair). The file's own header states it is a "type-only module (shared by the route and the client store); no DB imports" — it declares `export interface`/`export type` only, with no function, no value export, and no side effect of its own. `LiveSnapshot` is built once per read by `buildLiveSnapshot` in `routes/reads.ts` (outside this file) and handed unchanged to both the `GET /live` route and the `live-events.ts` SSE fan-out (`status-server-live` recipe); this recipe specifies the shape and field-level invariants that any producer or consumer of that value MUST honor, not the route or fan-out logic that builds or delivers it.

## Behavioral Requirements

- **type-only-no-runtime**: The module MUST export only types and interfaces (`export interface`, `export type`); it MUST NOT export a function, a class, or any other value, and MUST NOT import a database or storage module, so the same declarations are safe to import from both the server route and the client store.
- **live-service-dto-extends-service-status**: `LiveServiceDTO` MUST carry every field `ServiceStatusDTO` declares in the sibling `./types` module (`slug`, `group`, `name`, `url`, `environment`, `platform`, `deployProject`, `status`, `responseTimeMs`, `statusCode`, `error`, `lastCheckedAt`) plus its own `dnsOk` and `downSince`.
- **dns-ok-semantics**: `LiveServiceDTO.dnsOk` MUST be `false` exactly when the endpoint's current problem is DNS-sourced, and MUST be `true` when there is no open problem or the open problem is HTTP-sourced — per the field's own comment, "false → a `dns`-source problem, not `http`."
- **down-since-is-server-truth**: `LiveServiceDTO.downSince` MUST be the ISO-8601 time the endpoint's current HTTP-or-DNS issue opened, and MUST be `null` when the endpoint is not currently down — per the field's own comment, "durable across browsers (unlike the client store's per-tab onset)," naming it as the server-truth "down since" clock rather than a client-local one.
- **stale-prod-dto-shape**: `StaleProdDTO` MUST represent one Vercel project whose current production deployment is errored or behind, carrying `projectName`, `environment` as plain strings and `detail`, `sourceUrl`, `liveUrl` as nullable strings; the type itself carries no field that marks a value as stale or not-stale — per the interface's own comment, "already filtered to stale" — so a conformant producer MUST apply that filtering before constructing a value of this type, not encode the filter in the shape.
- **provider-key-closed-set**: `ProviderKey` MUST be exactly one of the four literal strings `"vercel"`, `"cloudflare-pages"`, `"railway"`, or `"crunchy"`; no other string value is a valid `ProviderKey`.
- **provider-health-independent-fields**: `ProviderHealth.configured` MUST reflect only whether an active, token-bearing integration exists for that provider, and MUST NOT be derived from `ok`; `ProviderHealth.ok` MUST reflect only whether the latest poll reached that provider's API, and MUST NOT be derived from `configured` — per the two fields' own comments, "whether we actually poll this platform" versus "whether the latest poll reached the provider API."
- **providers-map-is-total**: `LiveSnapshot.providers` MUST be a `Record<ProviderKey, ProviderHealth>` carrying an entry for every one of the four `ProviderKey` values; it MUST NOT be a partial map that omits a configured-or-not provider.
- **live-snapshot-bundles-the-full-picture**: `LiveSnapshot` MUST bundle `services: LiveServiceDTO[]`, `deployments: DeploymentDTO[]` (the sibling `./types` module's type), and `staleProd: StaleProdDTO[]` into one object, per the file's header comment describing it as "one self-contained snapshot of everything the client displays."
- **generated-at-is-read-time**: `LiveSnapshot.generatedAt` MUST be the ISO server-clock time the snapshot was produced — "the client's event-time reference" — and is always current by construction; it MUST NOT be treated as evidence that the underlying data is fresh.
- **last-cycle-at-is-data-freshness-clock**: `LiveSnapshot.lastCycleAt` MUST be the ISO time of the newest persisted probe, or `null` before the first probe has ever been written, and MUST be treated as distinct from `generatedAt` — per the field's own comment, it is "the data-freshness clock for what's on screen," not a read-time stamp.
- **last-cycle-at-distinct-from-health-clock**: `lastCycleAt` MUST be treated as distinct from the scheduler's cycle-completion clock exposed at a separate `/health` endpoint (outside this file): `lastCycleAt` advances only when a probe is WRITTEN, while `/health`'s clock advances only when a cycle stage COMPLETES, so a downstream cycle stage that hangs after probes are written is caught by `/health` while the on-screen data referenced by `lastCycleAt` is still current — per the field's own comment, this distinction exists precisely "so a wedged / never-redeployed poller can't masquerade as live data."
- **probe-interval-ms-scales-staleness**: `LiveSnapshot.probeIntervalMs` MUST carry the backend's probe interval in milliseconds so that a consumer's staleness window is computed as a function of this value rather than a hardcoded constant, per the field's own comment, "so the client's staleness window scales with it (mirroring the scheduler's own `staleAfterMs`)."
- **monitor-version-is-railway-commit-or-null**: `LiveSnapshot.monitorVersion` MUST be the git commit SHA the running monitor process was built from, read from Railway's `RAILWAY_GIT_COMMIT_SHA`, and MUST be `null` when the process is not running on Railway.
- **config-degraded-flag**: `LiveSnapshot.configDegraded` MUST be `true` exactly when the config read that produced this snapshot's `services`/`deployments`/`staleProd`/`providers` fell back to a static list because the database was unreachable, and MUST be `false` otherwise — per the field's own comment, "True when the config read fell back to the static list (DB unreachable)."
- **config-reason-nullable-and-unconstrained-when-degraded**: `LiveSnapshot.configReason` MUST be a nullable string; the type declares no comment constraining what it MUST contain when `configDegraded` is `true`, so the content of a non-null `configReason` is a producer's choice, not part of this file's contract.
- **all-fields-required**: No field on `LiveServiceDTO`, `StaleProdDTO`, `ProviderHealth`, or `LiveSnapshot` is declared optional (none carries a `?`); a conformant value MUST supply an explicit value for every field, including an explicit `null` where the field's type permits it, rather than omitting the property.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `RAILWAY_GIT_COMMIT_SHA` | environment variable | none (yields `null`) | Read by the producer to populate `LiveSnapshot.monitorVersion`; present only when the monitor process runs on Railway, per **monitor-version-is-railway-commit-or-null**. |
| probe interval | producer-supplied number (ms) | none — always supplied | Surfaced verbatim as `LiveSnapshot.probeIntervalMs`; this file declares the field but supplies no default of its own, per **probe-interval-ms-scales-staleness**. |
| `ProviderKey` set | fixed literal union | `"vercel"` \| `"cloudflare-pages"` \| `"railway"` \| `"crunchy"` | Not caller-configurable; the four keys are declared in this file and MUST be exhaustive per **provider-key-closed-set**. |

## Platform Notes

- **SwiftUI**: not applicable to this file's own source — `live-types.ts` is a TypeScript type-only module with no SwiftUI or Apple-platform dependency of any kind.
- **AppKit / UIKit**: this is the source. `packages/web/packages/status-server/src/monitor/live-types.ts` is a TypeScript file in the `status-server` web package; it has no Apple-platform target of its own. A macOS/iOS port would model `LiveSnapshot` and its members as `Codable`, `Sendable` `struct`s decoded from the same `/api/live` JSON response — `ProviderKey` as a `String`-backed `enum` with the same four cases, `ProviderHealth`/`StaleProdDTO`/`LiveServiceDTO` as `struct`s with `Optional` in place of TypeScript's `| null`, and `LiveServiceDTO` composed by embedding a `ServiceStatusDTO` value (or flattening its fields) rather than by structural inheritance, since Swift `struct`s do not support the interface-extension TypeScript uses here.
- **Compose**: model `LiveSnapshot` and its members as Kotlin `data class`es annotated for the project's JSON serializer (e.g. `kotlinx.serialization`'s `@Serializable`), with `ProviderKey` as a `String`-backed `enum class` (or a sealed value class) enumerating the same four cases, and nullable Kotlin types (`String?`) in place of `| null`. `LiveServiceDTO` composes `ServiceStatusDTO`'s fields via Kotlin interface delegation or straightforward field duplication, since Kotlin `data class`es cannot extend another data class either.
- **React/Web**: this is closest to the actual runtime shape — a React/Web client already consumes `LiveSnapshot` as plain JSON decoded from `GET /api/live`, and can import these same TypeScript declarations directly if it shares this package, or mirror them field-for-field in its own type file when it does not.
- **WinUI 3**: model `LiveSnapshot` and its members as C# `record`s deserialized with `System.Text.Json.JsonSerializer`, using nullable reference types (`string?`) in place of `| null` and an `enum ProviderKey { Vercel, CloudflarePages, Railway, Crunchy }` with a `[JsonStringEnumConverter]` (or explicit `JsonPropertyName` attributes) to preserve the exact wire strings `"vercel"`/`"cloudflare-pages"`/`"railway"`/`"crunchy"` per **provider-key-closed-set**. `LiveServiceDTO` inherits from a `ServiceStatusDTO` base `record` (C# records DO support inheritance, unlike Kotlin/Swift), giving a direct analogue of this file's `extends ServiceStatusDTO`. `Record<ProviderKey, ProviderHealth>`'s "always all four keys present" contract (**providers-map-is-total**) has no built-in enforcement in a plain `Dictionary<ProviderKey, ProviderHealth>`; model it as a small `ProviderHealthMap` type whose constructor requires all four values, or validate completeness in the `JsonSerializer` converter, so a partial deserialize is caught rather than silently accepted.

