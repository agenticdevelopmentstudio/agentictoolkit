<!-- leaf: implement-status-web-src-lib-1/live-types · source: status-web-src-lib-live-types.md -->

**Rules** (cite as `implement-status-web-src-lib-1/live-types#<slug>`):

- `type-only-module` MUST
- `no-db-imports` MUST
- `no-runtime-validation` MUST
- `live-service-extends` MUST
- `live-service-status-values` MUST
- `dns-ok-field` MUST
- `dns-ok-source-meaning` MUST
- `down-since-field` MUST
- `down-since-null` MUST
- `down-since-server-truth` MUST
- `stale-prod-fields` MUST
- `stale-prod-prefiltered` MUST
- `provider-key-members` MUST
- `provider-health-fields` MUST
- `provider-configured-meaning` MUST
- `provider-ok-meaning` MUST
- `providers-complete` MUST
- `snapshot-required-fields` MUST
- `snapshot-optional-fields` MUST
- `generated-at-meaning` MUST
- `generated-at-identity` MUST
- `last-cycle-at-meaning` MUST
- `last-cycle-at-distinct` MUST
- `last-cycle-at-absent` MUST
- `probe-interval-meaning` MUST
- `probe-interval-absent` MUST
- `monitor-version-meaning` MUST
- `monitor-version-absent` MUST
- `config-degraded-meaning` MUST
- `config-reason-field` MUST
- `no-side-effects` MUST

# Live Snapshot Wire Types

## Overview

`packages/web/packages/status-web/src/lib/live-types.ts` declares the `/api/live` contract: in its header's words, "one self-contained snapshot of everything the client displays, pulled live from providers + HTTP probes. Type-only module (shared by the route and the client store); no DB imports."

It exports one string union (`ProviderKey`) and five interfaces (`LiveServiceDTO`, `StaleProdDTO`, `ProviderHealth`, `LiveSnapshot`) built on `ServiceStatusDTO` and `DeploymentDTO` from `../types`. It emits no runtime code.

Consumers in the web package: `use-live-snapshot.ts` types every SSE frame and every `/api/live` poll response as `LiveSnapshot` and compares frames with `isSameSnapshot`; `stale-monitors.ts` selects retire candidates from `LiveServiceDTO[]` using `downSince` and `dnsOk`; `SnapshotStaleBanner` compares `lastCycleAt` against `generatedAt` scaled by `probeIntervalMs`; `Dashboard`, `DetailPanel` and `DeployList` forward `probeIntervalMs`; `OverviewTab` shows `monitorVersion`. `live-snapshot.fixture.ts` builds the default test snapshot. The status server holds its own copy of these types in `status-server/src/monitor/live-types.ts` and produces the payload in `routes/reads.ts`.

## Behavioral Requirements

### Module shape

- **type-only-module**: The module MUST export only types; importing it MUST produce no runtime value or side effect.
- **no-db-imports**: The module MUST NOT import database or storage code; its only import MUST be the type-only import of `ServiceStatusDTO` and `DeploymentDTO` from `../types`.
- **no-runtime-validation**: The module MUST NOT validate a payload at runtime; `use-live-snapshot.ts` casts `JSON.parse(data) as LiveSnapshot` and `(await r.json()) as LiveSnapshot` unchecked, so a mismatched payload reaches consumers as-is.
- **server-parity**: The header comment says the module is "shared by the route and the client store", but the text is duplicated verbatim in a separate server copy (`status-server/src/monitor/live-types.ts`), and that copy is what the route uses. No parity test pins the two copies, unlike `board-types-parity.test.ts` and `deploy-status-parity.test.ts`, so a field changed in only one copy still compiles in both packages. A port keeps one definition of these types for both server and client, or adds a parity test.

### LiveServiceDTO

- **live-service-extends**: `LiveServiceDTO` MUST carry every field of `ServiceStatusDTO` (`slug`, `group`, `name`, `url`, `environment`, `platform`, `deployProject`, `status`, `responseTimeMs`, `statusCode`, `error`, `lastCheckedAt`) plus `dnsOk` and `downSince`.
- **live-service-status-values**: `LiveServiceDTO.status` MUST be one of `"healthy"`, `"degraded"`, `"down"` or `"unknown"` (`HealthStatus | "unknown"`).
- **dns-ok-field**: `dnsOk` MUST be a required `boolean` stating whether the hostname resolved in DNS.
- **dns-ok-source-meaning**: `dnsOk: false` MUST denote a `dns`-source problem, not an `http`-source one.
- **down-since-field**: `downSince` MUST be a required `string | null`: the ISO time the endpoint's current http/dns issue opened.
- **down-since-null**: `downSince` MUST be `null` when the endpoint is not down.
- **down-since-server-truth**: `downSince` MUST be the server's durable onset, identical across browsers, and consumers MUST NOT substitute a per-tab onset for it.

### StaleProdDTO

- **stale-prod-fields**: `StaleProdDTO` MUST carry exactly `projectName: string`, `environment: string`, `detail: string | null`, `sourceUrl: string | null`, `liveUrl: string | null`.
- **stale-prod-prefiltered**: Every entry in `LiveSnapshot.staleProd` MUST already be a Vercel project whose live production deploy is errored or behind; consumers MUST NOT re-filter it for staleness.

### Providers

- **provider-key-members**: `ProviderKey` MUST be exactly `"vercel" | "cloudflare-pages" | "railway" | "crunchy"`.
- **provider-health-fields**: `ProviderHealth` MUST carry exactly `configured: boolean` and `ok: boolean`.
- **provider-configured-meaning**: `configured` MUST be `true` only when the platform is actually polled: an active integration that has a token.
- **provider-ok-meaning**: `ok` MUST state whether the latest poll reached the provider API.
- **providers-complete**: `LiveSnapshot.providers` MUST be a `Record<ProviderKey, ProviderHealth>` holding an entry for every one of the four `ProviderKey` members.

### LiveSnapshot

- **snapshot-required-fields**: `LiveSnapshot` MUST carry the required fields `generatedAt: string`, `services: LiveServiceDTO[]`, `deployments: DeploymentDTO[]`, `staleProd: StaleProdDTO[]`, `providers: Record<ProviderKey, ProviderHealth>`, `configDegraded: boolean`, `configReason: string | null`.
- **snapshot-optional-fields**: `LiveSnapshot` MUST declare `lastCycleAt?: string | null`, `probeIntervalMs?: number` and `monitorVersion?: string | null` as optional, so a payload from an older backend that omits them still typechecks.
- **generated-at-meaning**: `generatedAt` MUST be an ISO timestamp from the server clock, stamped at read time, and MUST serve as the client's event-time reference.
- **generated-at-identity**: `generatedAt` MUST identify a delivery: two snapshots with equal `generatedAt` are the same frame (`isSameSnapshot` returns `true` for them).
- **last-cycle-at-meaning**: `lastCycleAt` MUST be the ISO time of the newest persisted probe, and `null` before the first probe.
- **last-cycle-at-distinct**: `lastCycleAt` MUST NOT be treated as the scheduler's cycle-completion clock served at `/health`.
- **last-cycle-at-absent**: An absent or `null` `lastCycleAt` MUST yield no staleness warning; `snapshotFreshness` returns `"fresh"` and `SnapshotStaleBanner` renders nothing.
- **probe-interval-meaning**: `probeIntervalMs` MUST be the backend's probe interval in milliseconds, so the client's staleness window scales with it.
- **probe-interval-absent**: An absent `probeIntervalMs` MUST fall back to the client's floor; `snapshotStaleMs` returns `max(probeIntervalMs * 5, 300000)`, which is 300000 ms when the field is missing.
- **monitor-version-meaning**: `monitorVersion` MUST be the git commit the monitor itself is running, or `null` when there is none (locally).
- **monitor-version-absent**: An absent or `null` `monitorVersion` MUST cause the board to show no version.
- **config-degraded-meaning**: `configDegraded` MUST be `true` only when the server's config read fell back to the static list because the database was unreachable.
- **config-reason-field**: `configReason` MUST be a `string | null` carried beside `configDegraded`; the module gives no further meaning to it.

### Concurrency and side effects

- **no-side-effects**: The module MUST perform no I/O, hold no state and have no ordering or concurrency behavior; it is erased at compile time.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| — | — | — | None. The module takes no parameters, environment variables or injected dependencies. `probeIntervalMs` reflects the server's `PROBE_INTERVAL_SECONDS` and `monitorVersion` its Railway build environment, but both are set by the server, not by this module. |

## Platform Notes

- **SwiftUI**: Model each interface as a `struct` conforming to `Codable, Sendable, Equatable` and `ProviderKey` as a `String` raw-value `enum` with `case cloudflarePages = "cloudflare-pages"`. Decode `providers` as `[ProviderKey: ProviderHealth]` (a `Codable` dictionary keyed by a `String` enum needs `CodingKeyRepresentable`) and check all four keys are present. Optional fields become Swift optionals with `decodeIfPresent`. Unlike TypeScript, `JSONDecoder` rejects an unknown enum member, so add an `unknown` fallback if tolerance is wanted.
- **Compose**: Kotlin `@Serializable data class` per interface with `kotlinx.serialization`; `ProviderKey` as an `enum class` with `@SerialName("cloudflare-pages")`; `providers` as `Map<ProviderKey, ProviderHealth>`. Give optional fields defaults (`val lastCycleAt: String? = null`, `val probeIntervalMs: Long? = null`) so an older backend decodes; set `Json { ignoreUnknownKeys = true }`.
- **React/Web**: Source platform. `src/lib/live-types.ts` is the type-only contract, `src/lib/live-snapshot.fixture.ts` the default test snapshot, and `src/hooks/use-live-snapshot.ts` the only producer of typed values (by cast). Types are erased, so a port wanting runtime safety adds a schema (for example zod) at the fetch and SSE parse sites.
- **AppKit / UIKit**: Same `Codable` structs as the SwiftUI note, in a UI-free module shared by both; no framework types are involved.
- **WinUI 3**: Declare C# `record` types (`public sealed record LiveSnapshot(...)`) with `string?`, `long?` and `bool` properties and `IReadOnlyList<T>` for arrays, deserialized with `System.Text.Json` using `JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }`. `LiveServiceDTO` extends a `ServiceStatusDTO` record by record inheritance. `providers` becomes `IReadOnlyDictionary<string, ProviderHealth>` (a C# enum key would need a custom converter for `"cloudflare-pages"`); validate the four keys after deserializing. The optional fields are nullable properties that stay `null` when absent. `generatedAt` and `lastCycleAt` may be `DateTimeOffset?`, but keep `generatedAt`'s raw string if frame identity comparison is ported. Surface the snapshot through a view model implementing `INotifyPropertyChanged`, projecting `services` and `deployments` into `ObservableCollection<T>`; there is no compile-time parity check against the server, so a shared contract assembly or JSON-schema test is the equivalent guard.

## Design Decisions

**Decision**: Mark `lastCycleAt`, `probeIntervalMs` and `monitorVersion` optional on the client although the server copy declares them required.
**Rationale**: The doc comments say each is optional "so an older backend degrades" to no warning, the client's floor, or no version shown; the client must tolerate backends that predate the fields.
**Approved**: pending

**Decision**: Carry `downSince` as server truth rather than the client's per-tab onset.
**Rationale**: The doc comment calls it "durable across browsers (unlike the client store's per-tab onset)"; the retire-stale-monitor surface judges a 7-day outage and needs an onset that survives reloads.
**Approved**: pending

**Decision**: Carry `lastCycleAt` separately from `generatedAt`.
**Rationale**: `generatedAt` "is read-time and always looks fresh", so only the newest-persisted-probe clock can expose a wedged or never-redeployed poller.
**Approved**: pending

**Decision**: Keep the module type-only with no DB imports.
**Rationale**: The header states it is shared by the route and the client store; a DB import would drag server code into the browser bundle.
**Approved**: pending
