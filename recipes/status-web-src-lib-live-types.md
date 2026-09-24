---
id: 41f840c1-ea34-489d-9b9f-a61dec2a9402
title: Live Snapshot Wire Types
domain: agentictoolkit://recipes/status-web-src-lib-live-types
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Type-only wire contract for the status dashboard's /api/live snapshot, shared
  by the live store and its consumers.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://recipes/status-web-hooks-use-live-snapshot
- agentictoolkit://recipes/status-web-src-lib-board-types
- agentictoolkit://recipes/status-web-api
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a type-only wire contract, not a visual component.

## States

Not applicable — this is a type-only wire contract, not a visual component.

## Accessibility

Not applicable — this is a type-only wire contract, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| live-types-001 | snapshot-required-fields, providers-complete, snapshot-optional-fields | `liveSnapshot()` from the fixture: `generatedAt: "2026-06-30T00:00:00.000Z"`, empty `services`/`deployments`/`staleProd`, all four providers `{ configured: true, ok: true }`, `configDegraded: false`, `configReason: null`, no `lastCycleAt`/`probeIntervalMs`/`monitorVersion` | Typechecks as `LiveSnapshot`; removing any provider key or any required field fails to typecheck |
| live-types-002 | provider-key-members | Assign `"cloudflare"` as a `ProviderKey` | Fails to typecheck; `"cloudflare-pages"` typechecks |
| live-types-003 | generated-at-identity | `isSameSnapshot(a, b)` where `a` and `b` are distinct objects with `generatedAt: "2026-06-30T00:00:00.000Z"`; then with `b.generatedAt: "2026-06-30T00:01:00.000Z"`; then `isSameSnapshot(null, b)` | `true`, then `false`, then `false` |
| live-types-004 | down-since-field, down-since-server-truth, dns-ok-field | `selectStaleMonitors([svc({ status: "down", downSince: 30 days ago, statusCode: 500, error: null, dnsOk: true })], NOW)` | One row with `slug: "ep1"`, `dnsOk: true`, `detail: "HTTP 500"`, `ageMs: 2592000000` |
| live-types-005 | down-since-null | `selectStaleMonitors` over a `down` service with `downSince: null` and over `healthy`/`degraded` services | `[]` |
| live-types-006 | dns-ok-source-meaning | The same down-for-a-week services with `dnsOk: true` and with `dnsOk: false` | Same selected slugs either way; each row's `dnsOk` echoes the input |
| live-types-007 | last-cycle-at-absent | `snapshotFreshness(undefined, "2026-06-30T00:00:00.000Z", 60000)` and `snapshotFreshness(null, ...)` | `"fresh"` both times |
| live-types-008 | probe-interval-absent, probe-interval-meaning | `snapshotStaleMs(undefined)`; `snapshotStaleMs(120000)` | `300000`; `600000` |
| live-types-009 | live-service-extends, live-service-status-values | A `LiveServiceDTO` literal with every `ServiceStatusDTO` field, `status: "unknown"`, `dnsOk: true`, `downSince: null` | Typechecks; omitting `dnsOk` or `downSince`, or setting `status: "offline"`, fails |
| live-types-010 | stale-prod-fields | A `StaleProdDTO` with `projectName: "site"`, `environment: "production"`, and `detail`, `sourceUrl`, `liveUrl` all `null` | Typechecks; `environment: null` fails |
| live-types-011 | type-only-module, no-side-effects, no-db-imports | Import the module and inspect its runtime exports | No runtime values are exported |

## Edge Cases

- **Older backend**: A payload with no `lastCycleAt`, `probeIntervalMs` or `monitorVersion` MUST typecheck; the client MUST then show no staleness warning, use the 300000 ms floor, and show no version. MUST.
- **First probe not yet run**: `lastCycleAt: null` MUST mean no probe has run, and MUST NOT trigger a warning. MUST.
- **Empty snapshot**: `services`, `deployments` and `staleProd` MAY each be empty arrays (the fixture default). MUST.
- **Endpoint down with no onset**: A `down` service with `downSince: null` MUST NOT be treated as long-down; `selectStaleMonitors` skips it. MUST.
- **Malformed `downSince`**: A string that does not parse to a date yields a non-finite age, and `selectStaleMonitors` MUST skip that service rather than surface it. MUST.
- **Malformed `generatedAt` or `lastCycleAt`**: An unparseable date makes the age `NaN`, and `snapshotFreshness` MUST return `"fresh"` rather than warn. MUST.
- **Unknown union member at runtime**: A `status` or provider key outside the declared unions is not rejected (no runtime validation); it reaches consumers unchecked. MUST (fact of the contract).
- **Re-delivered frame**: A frame whose `generatedAt` equals the last ingested one MUST be treated as the same delivery. MUST.
- **Client and server copies drift**: A field renamed in only one copy compiles in both packages; see server-parity. No parity test exists to catch it.
- **Config fallback**: `configDegraded` MUST be `true` only on the static-list fallback; the server's successful-read path always sends `configDegraded: false` and `configReason: null`. MUST.
- **Concurrency, network, offline, cancellation, timeouts**: Not applicable; the module has no runtime behavior. Transport failures are owned by `use-live-snapshot.ts`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| — | — | — | None. The module takes no parameters, environment variables or injected dependencies. `probeIntervalMs` reflects the server's `PROBE_INTERVAL_SECONDS` and `monitorVersion` its Railway build environment, but both are set by the server, not by this module. |

## Deep Linking

Not applicable: the module declares data types and handles no URLs or routes.

## Localization

Not applicable: the module holds no strings; `configReason`, `StaleProdDTO.detail` and service `error` are server-supplied values.

## Accessibility Options

Not applicable: the module has no visual output.

## Feature Flags

Not applicable: the module reads no flags.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module stores and transmits nothing; the fields it types (service names, URLs, commit hashes, provider health) carry no credentials or personal data by declaration.

## Logging

Not applicable: the module has no runtime code and logs nothing.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |

The module holds only the wire contract, with transport, selection and rendering in other modules, so separation-of-concerns passes. Unit-test-coverage is partial: the fixture and the consumer tests (`use-live-snapshot.test.ts`, `stale-monitors.test.ts`) exercise the shapes, but no test pins these types to the server's copy. Data-integrity is partial for the same reason and because no runtime check rejects a mismatched payload. Graceful-degradation passes: the three newer fields are optional and each has a documented fallback for an older backend.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial recipe extracted from `live-types.ts` and its consumers |
