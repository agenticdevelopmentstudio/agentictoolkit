---
id: 2c8b4572-3851-4111-97d6-a42792fb7150
title: Status Server Monitor Live Types
domain: agentictoolkit://cookbook/status-server/monitor/live-types
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "The type-only /api/live contract: LiveSnapshot and its LiveServiceDTO, StaleProdDTO, ProviderKey and ProviderHealth members, shared by the route and the client store."
platforms:
- typescript
- web
tags:
- monitor
- live
- types
- dto
- server
depends-on: []
related:
- agentictoolkit://cookbook/status-server/live/live-events
references:
- packages/web/packages/status-server/src/monitor/live-types.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/types.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/reads.ts (agentictoolkit)
- packages/web/packages/status-server/test/reads.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/helpers/snapshot.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/reads.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a type-only DTO contract module, not a visual component.

## States

Not applicable — this is a type-only DTO contract module, not a visual component. Its only lifecycle-shaped concept, the freshness relationship between `generatedAt`, `lastCycleAt` and a separate `/health` cycle clock, is captured under Behavioral Requirements (**last-cycle-at-is-data-freshness-clock**, **last-cycle-at-distinct-from-health-clock**) rather than as a visual-state table.

## Accessibility

Not applicable — this is a type-only DTO contract module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| live-types-001 | providers-map-is-total | `GET /live` against a database with no configured integrations | `providers` carries `vercel`, `cloudflare-pages`, `railway`, and `crunchy` keys, matching the default fixture in `test/helpers/snapshot.ts`'s `liveSnapshot()` — `reads.int.test.ts`'s `'returns a LiveSnapshot with a token (empty DB does not error)'` |
| live-types-002 | dns-ok-semantics | An endpoint whose latest persisted health check is `status: 'healthy'` | The corresponding `LiveServiceDTO` matches `{ status: 'healthy', responseTimeMs: 42, dnsOk: true }` — `reads.int.test.ts`'s `'/live + /status surface a service derived from the latest health check'` |
| live-types-003 | dns-ok-semantics | An endpoint whose latest persisted health check row has `dnsOk: false` | The corresponding `LiveServiceDTO.dnsOk` is `false` — `reads.int.test.ts`'s `'/live marks a service dnsOk=false when its latest check failed DNS'` |
| live-types-004 | down-since-is-server-truth | An endpoint with an open http/dns issue whose `openedAt` is a known timestamp | `LiveServiceDTO.downSince` equals that issue's `openedAt.toISOString()` — `reads.int.test.ts`'s `'/live stamps downSince from the open http/dns issue openedAt (server-truth "down since")'` |
| live-types-005 | down-since-is-server-truth | A second, healthy endpoint with no open issue | That endpoint's `LiveServiceDTO.downSince` is `null` — same test, second assertion (`live2.services.find(...).downSince` is `null`) |
| live-types-006 | config-degraded-flag, config-reason-nullable-and-unconstrained-when-degraded | `GET /live` against an empty but reachable database | `configDegraded` is `false` and `configReason` is `null` — `reads.int.test.ts`'s `'returns a LiveSnapshot with a token (empty DB does not error)'` |
| live-types-007 | last-cycle-at-is-data-freshness-clock | A fresh database with no health check ever persisted | `LiveSnapshot.lastCycleAt` is `null` — same test |
| live-types-008 | last-cycle-at-is-data-freshness-clock | A database with at least one recently-persisted health check | `LiveSnapshot.lastCycleAt` is an ISO string less than 60 seconds old — `reads.int.test.ts`'s `'/live + /status surface a service derived from the latest health check'` |
| live-types-009 | stale-prod-dto-shape | A persisted `vercelProdState` row for a project an OWNED site monitors | `LiveSnapshot.staleProd` has one entry matching `{ projectName: 'adh', environment: 'production', liveUrl: 'https://adh.example.com' }` — `reads.int.test.ts`'s `'/live derives staleProd from a persisted vercelProdState row for an OWNED project'` |
| live-types-010 | stale-prod-dto-shape | A stale-Vercel issue for a project no live site currently owns | `LiveSnapshot.staleProd` maps to an empty `projectName` list — `reads.int.test.ts`'s `'/live drops a vercel-stale issue for a project NO live site owns'` |

## Edge Cases

- **Null and empty input**: an endpoint that has never been probed MUST report `lastCheckedAt: null` (inherited from `ServiceStatusDTO`) and — per **down-since-is-server-truth** — `downSince: null`, since there is no open issue to have a `since`. (MUST)
- **Null and empty input**: a monitor process running outside Railway MUST report `monitorVersion: null`, per **monitor-version-is-railway-commit-or-null**. (MUST)
- **Null and empty input**: a fresh database with no persisted probe ever written MUST report `LiveSnapshot.lastCycleAt: null`, per **last-cycle-at-is-data-freshness-clock** — traced to `reads.int.test.ts`'s `toHaveProperty('lastCycleAt', null)` assertion. (MUST)
- **Boundary values**: `ProviderKey` admits exactly four literal values; a fifth provider key is not a valid `ProviderKey` and `LiveSnapshot.providers` MUST NOT carry an entry for one, per **provider-key-closed-set** and **providers-map-is-total**. (MUST)
- **Concurrent access**: not applicable to this file — it declares no mutable state and no function; the module's only property is the shape it declares, which cannot be entered concurrently. The concurrency of the process that builds a `LiveSnapshot` value (`buildLiveSnapshot` in `routes/reads.ts`) is outside this file's contract.
- **Error states**: not applicable to a producer failure in the sense of this file raising one — this file declares no function that can throw. **config-degraded-flag** is this contract's error-state signal: a producer that could not reach the database MUST still return a fully-shaped `LiveSnapshot` with `configDegraded: true`, rather than omit fields or fail the read outright, so every field declared in this file remains present per **all-fields-required** even in the degraded case.
- **Offline or disconnected state**: not applicable — this file makes no network call of its own; it only declares the shape of a value that is already the RESULT of the monitor's own network probing, described from the client's perspective by `generatedAt`/`lastCycleAt`/`probeIntervalMs` (per **generated-at-is-read-time**, **last-cycle-at-is-data-freshness-clock**, **probe-interval-ms-scales-staleness**), which exist specifically so a consumer can detect that the underlying poller has gone quiet without this file needing any network awareness itself.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `RAILWAY_GIT_COMMIT_SHA` | environment variable | none (yields `null`) | Read by the producer to populate `LiveSnapshot.monitorVersion`; present only when the monitor process runs on Railway, per **monitor-version-is-railway-commit-or-null**. |
| probe interval | producer-supplied number (ms) | none — always supplied | Surfaced verbatim as `LiveSnapshot.probeIntervalMs`; this file declares the field but supplies no default of its own, per **probe-interval-ms-scales-staleness**. |
| `ProviderKey` set | fixed literal union | `"vercel"` \| `"cloudflare-pages"` \| `"railway"` \| `"crunchy"` | Not caller-configurable; the four keys are declared in this file and MUST be exhaustive per **provider-key-closed-set**. |

## Deep Linking

Not applicable: `live-types.ts` declares data shapes only — no URL, route, or navigable destination originates from this file.

## Localization

Not applicable: this file contains no string literal of any kind — every text-carrying field (`error`, `configReason`, `detail`, `sourceUrl`, `liveUrl`) is a `string | null` type declaration, not a value, so there is no user-facing string for this file itself to localize.

## Accessibility Options

Not applicable: `live-types.ts` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic of any kind.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; it declares data shapes only.

## Privacy

Not applicable: `live-types.ts` declares data shapes only — it collects, stores, and transmits nothing itself. None of its fields is a token or credential; the URLs, project names, commit-adjacent identifiers and error strings the bundled DTOs carry are operational monitoring data already produced elsewhere, and this file neither reads nor writes them.

## Logging

Not applicable: the source contains no log call of any kind — it declares data shapes only, with no function to log from.

## Platform Notes

- **SwiftUI**: not applicable to this file's own source — `live-types.ts` is a TypeScript type-only module with no SwiftUI or Apple-platform dependency of any kind.
- **AppKit / UIKit**: this is the source. `packages/web/packages/status-server/src/monitor/live-types.ts` is a TypeScript file in the `status-server` web package; it has no Apple-platform target of its own. A macOS/iOS port would model `LiveSnapshot` and its members as `Codable`, `Sendable` `struct`s decoded from the same `/api/live` JSON response — `ProviderKey` as a `String`-backed `enum` with the same four cases, `ProviderHealth`/`StaleProdDTO`/`LiveServiceDTO` as `struct`s with `Optional` in place of TypeScript's `| null`, and `LiveServiceDTO` composed by embedding a `ServiceStatusDTO` value (or flattening its fields) rather than by structural inheritance, since Swift `struct`s do not support the interface-extension TypeScript uses here.
- **Compose**: model `LiveSnapshot` and its members as Kotlin `data class`es annotated for the project's JSON serializer (e.g. `kotlinx.serialization`'s `@Serializable`), with `ProviderKey` as a `String`-backed `enum class` (or a sealed value class) enumerating the same four cases, and nullable Kotlin types (`String?`) in place of `| null`. `LiveServiceDTO` composes `ServiceStatusDTO`'s fields via Kotlin interface delegation or straightforward field duplication, since Kotlin `data class`es cannot extend another data class either.
- **React/Web**: this is closest to the actual runtime shape — a React/Web client already consumes `LiveSnapshot` as plain JSON decoded from `GET /api/live`, and can import these same TypeScript declarations directly if it shares this package, or mirror them field-for-field in its own type file when it does not.
- **WinUI 3**: model `LiveSnapshot` and its members as C# `record`s deserialized with `System.Text.Json.JsonSerializer`, using nullable reference types (`string?`) in place of `| null` and an `enum ProviderKey { Vercel, CloudflarePages, Railway, Crunchy }` with a `[JsonStringEnumConverter]` (or explicit `JsonPropertyName` attributes) to preserve the exact wire strings `"vercel"`/`"cloudflare-pages"`/`"railway"`/`"crunchy"` per **provider-key-closed-set**. `LiveServiceDTO` inherits from a `ServiceStatusDTO` base `record` (C# records DO support inheritance, unlike Kotlin/Swift), giving a direct analogue of this file's `extends ServiceStatusDTO`. `Record<ProviderKey, ProviderHealth>`'s "always all four keys present" contract (**providers-map-is-total**) has no built-in enforcement in a plain `Dictionary<ProviderKey, ProviderHealth>`; model it as a small `ProviderHealthMap` type whose constructor requires all four values, or validate completeness in the `JsonSerializer` converter, so a partial deserialize is caught rather than silently accepted.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/live-types.ts` |

## Design Decisions

**Decision**: `StaleProdDTO` carries no field distinguishing a stale project from a non-stale one; the type's own comment states it represents a project "(already filtered to stale)."
**Rationale**: the filtering happens in the producer (`staleProdFromBoard` in `routes/reads.ts`, outside this file's given source), not in the type. This recipe states the filtering as a producer obligation (**stale-prod-dto-shape**) rather than inventing a status field the type does not declare, per source fidelity: the type's shape is the contract, and the filtering guarantee is a documented precondition on any value of this type, not something the shape itself enforces.
**Approved**: pending

**Decision**: `configReason`'s relationship to `configDegraded` is left undocumented in the source — no comment constrains whether a `true` `configDegraded` requires a non-null `configReason`, or whether `configReason` may carry detail while `configDegraded` is `false`.
**Rationale**: rather than inventing a pairing rule the source does not state, this recipe declares `configReason` as an independently nullable field (**config-reason-nullable-and-unconstrained-when-degraded**). The one producer among this package's sibling sources (`buildLiveSnapshot` in `routes/reads.ts`) currently always emits `configDegraded: false, configReason: null` together — "a successful DB read is never the static-fallback degraded path," per that function's own comment — so the degraded branch this type anticipates is not currently exercised by any given source, and no test vector for it exists.
**Approved**: pending

**Decision**: `LiveServiceDTO` is modeled as `ServiceStatusDTO` extended with `dnsOk` and `downSince`, rather than as a flat, independently-declared interface.
**Rationale**: this mirrors the source exactly (`export interface LiveServiceDTO extends ServiceStatusDTO`), and keeps the two added fields' documentation (both carry substantial doc comments explaining why each exists) visible as the distinguishing surface of the "live" variant over the base status row, rather than diluting them across a duplicated field list.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | passed | Reliability |

`separation-of-concerns` passes because this file declares only the `/api/live` wire shapes, with no DB import and no bridge to the route or SSE fan-out logic that builds or delivers a value of this shape — building belongs to `routes/reads.ts`'s `buildLiveSnapshot`, delivery belongs to `live/live-events.ts` (`status-server-live` recipe), and this file imports neither. `unit-test-coverage` is partial: no test file targets `live-types.ts` directly (it has no function to unit-test), but every field this recipe documents is exercised indirectly through `reads.int.test.ts`'s integration tests against `GET /live`, which is the traceability basis for every Conformance Test Vector above; there is no direct test of the type declarations' shape in isolation from that route. `data-integrity` passes because every field in every interface this file declares is non-optional (**all-fields-required**), so a value that omits a field fails structural typing at compile time rather than silently propagating a partial `LiveSnapshot` to a consumer. `health-observability` passes because `LiveSnapshot` itself is a health-observability surface: `lastCycleAt`, `probeIntervalMs`, and `monitorVersion` exist specifically so a long-running monitor process's staleness and running version are observable from the snapshot it produces, per **last-cycle-at-is-data-freshness-clock**, **last-cycle-at-distinct-from-health-clock**, and **probe-interval-ms-scales-staleness**.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
