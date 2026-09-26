---
id: 2871e97f-f971-46fe-a4d2-de57ad5c94c5
title: Status Server Monitor Health
domain: agentictoolkit://cookbook/status-server/monitor/health
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure function classifying one HTTP probe's status code, latency, and optional
  body checks into the healthy, degraded, or down verdict the monitor persists.
platforms:
- typescript
- web
tags:
- monitor
- health
- classification
- pure-function
- server
depends-on: []
related: []
references:
- packages/web/packages/status-server/src/monitor/health.ts (agentictoolkit)
- packages/web/packages/status-server/test/health.test.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/probe.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Health

## Overview

`health.ts` (`packages/web/packages/status-server/src/monitor/health.ts`) is the status backend's pure classification step for turning one HTTP probe's raw signal — a status code, an elapsed response time, the endpoint's declared expected status, and, for a `health`-kind endpoint, a snippet of the response body — into the three-value `HealthStatus` verdict (`healthy`, `degraded`, or `down`) that the rest of the monitor persists, alerts on, and displays. It exports the `HealthStatus` type, the `ClassifyInput` interface, the two tuning constants `HEALTH_CHECK_TIMEOUT_MS` (`10_000`) and `DEGRADED_THRESHOLD_MS` (`2_000`), and the single function `classify`. `classify` is synchronous and pure: it performs no network call, no database access, and no logging of its own, and every branch it can take is fully determined by the fields on its `ClassifyInput` argument. `classify` is the verdict step inside `probe()` (`probe.ts`, external to this file), which supplies it with the outcome of one live fetch, including a marker check (`bodyMarkerMissing`) that caller derives itself; per this file's own doc comment on `bodyMarkerMissing`, that field exists because "a 200 serving the wrong/broken page is DOWN" — an outage the status code alone cannot see.

## Behavioral Requirements

### Data Shape

- **health-status-values**: `HealthStatus` MUST be exactly one of `"healthy"`, `"degraded"`, or `"down"`.
- **classify-input-shape**: `ClassifyInput` MUST carry the three required fields `statusCode: number`, `responseTimeMs: number`, and `expectedStatus: number`, plus the three optional fields `isHealthKind?: boolean`, `bodyText?: string`, and `bodyMarkerMissing?: boolean`.
- **classify-purity**: `classify(input)` MUST be a synchronous, side-effect-free function that returns a `HealthStatus` computed only from its `input` argument; it MUST perform no I/O, no logging, and no mutation of `input`.

### Success Range and Non-2xx Handling

- **success-status-range**: `classify` MUST treat `statusCode` as a successful response ("2xx") if and only if `statusCode >= 200 && statusCode < 300`.
- **non-2xx-non-expected-is-down**: `classify` MUST return `"down"` whenever `statusCode` is not a 2xx response AND `statusCode !== expectedStatus`, regardless of `responseTimeMs`, `isHealthKind`, `bodyText`, or `bodyMarkerMissing`.
- **expected-non-2xx-status-not-down**: `classify` MUST NOT return `"down"` on the sole basis of `statusCode` when `statusCode` is not a 2xx response but does equal `expectedStatus` (e.g. an endpoint whose `expectedStatus` is `401`); that case MUST proceed to the same health-kind, body-marker, and latency evaluation as a 2xx response.

### Classification Order

- **classification-evaluation-order**: `classify` MUST evaluate, and return on the first matching step, in exactly this order: (1) `statusCode` is neither a 2xx response nor equal to `expectedStatus` → `"down"`; (2) `statusCode` is a 2xx response AND `isHealthKind` is `true` AND `bodyText` is a non-empty string AND the parsed JSON body has a `status` field whose lower-cased string form is not `"ok"` → `"down"`, without evaluating `bodyMarkerMissing` or `responseTimeMs`; (3) `bodyMarkerMissing` is `true` → `"down"`; (4) `responseTimeMs > DEGRADED_THRESHOLD_MS` → `"degraded"`; (5) otherwise → `"healthy"`.

### Health-Kind JSON Check

- **health-kind-check-skipped-without-body-text**: When `statusCode` is a 2xx response and `isHealthKind` is `true` but `bodyText` is `undefined` or the empty string, `classify` MUST skip the JSON parse entirely and proceed directly to the `bodyMarkerMissing` and latency evaluation.
- **health-kind-json-down-on-non-ok-status**: When `statusCode` is a 2xx response, `isHealthKind` is `true`, and `bodyText` is a non-empty string, `classify` MUST parse `bodyText` as JSON and, when the parsed value is a non-null object containing a `status` property whose value, converted with `String(...)` and lower-cased, is not exactly `"ok"`, MUST return `"down"`.
- **health-kind-json-parse-failure-falls-through**: When parsing `bodyText` as JSON throws (a non-JSON body, e.g. an HTML page), `classify` MUST NOT return `"down"` on that basis and MUST continue to the `bodyMarkerMissing` and latency evaluation.
- **health-kind-json-missing-status-field-falls-through**: When the parsed JSON value is `null`, is not an object, or is an object with no `status` property, `classify` MUST NOT return `"down"` on that basis and MUST continue to the `bodyMarkerMissing` and latency evaluation.
- **health-kind-status-field-string-coercion**: `classify` MUST compare the parsed `status` field's value against `"ok"` by converting it with `String(...)` and calling `.toLowerCase()` first, so a `status` field of `"OK"`, `"Ok"`, or a non-string value such as `200` or `true` is compared as `"ok"`, `"ok"`, `"200"`, and `"true"` respectively — only a case-insensitive `"ok"` MUST count as healthy for this check.

### Body-Marker Check

- **body-marker-missing-is-down**: When `statusCode` is a 2xx response or equals `expectedStatus`, and the health-kind JSON check did not already return `"down"`, `classify` MUST return `"down"` when `bodyMarkerMissing` is `true`, regardless of `responseTimeMs`.

### Latency Classification

- **degraded-latency-threshold**: When none of the preceding down conditions apply, `classify` MUST return `"degraded"` when `responseTimeMs > DEGRADED_THRESHOLD_MS`, and MUST return `"healthy"` when `responseTimeMs <= DEGRADED_THRESHOLD_MS`; the comparison MUST be strictly-greater-than, so a `responseTimeMs` exactly equal to `DEGRADED_THRESHOLD_MS` MUST classify as `"healthy"`.

### Exported Constants

- **degraded-threshold-constant**: `DEGRADED_THRESHOLD_MS` MUST be exported with the value `2_000` (2000 milliseconds), and `classify`'s latency comparison MUST read this constant rather than a separately hard-coded literal.
- **health-check-timeout-constant**: `HEALTH_CHECK_TIMEOUT_MS` MUST be exported with the value `10_000` (10000 milliseconds); `classify` itself MUST NOT reference this constant in any of its comparisons — it is a caller-facing default that a probe's own request-timeout configuration reads (per `probe.ts`, external to this file, where it is the fallback for `ProbeOptions.timeoutMs`).

## Appearance

Not applicable — this is a health-classification function, not a visual component.

## States

Not applicable — this is a health-classification function, not a visual component; the three values `classify` can return (`healthy`, `degraded`, `down`) are a return-value enumeration, specified above under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a health-classification function, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-health-001 | success-status-range, degraded-latency-threshold | `classify({ statusCode: 200, responseTimeMs: 100, expectedStatus: 200 })` | `'healthy'` — `health.test.ts` › "healthy on fast 2xx" |
| status-server-monitor-health-002 | degraded-latency-threshold | `classify({ statusCode: 200, responseTimeMs: 2500, expectedStatus: 200 })` | `'degraded'` — `health.test.ts` › "degraded when slow" |
| status-server-monitor-health-003 | non-2xx-non-expected-is-down | `classify({ statusCode: 503, responseTimeMs: 100, expectedStatus: 200 })` | `'down'` — `health.test.ts` › "down on 5xx" |
| status-server-monitor-health-004 | body-marker-missing-is-down | `classify({ statusCode: 200, responseTimeMs: 100, expectedStatus: 200, bodyMarkerMissing: true })` | `'down'` — `health.test.ts` › "down when the expected body marker is missing" |
| status-server-monitor-health-005 | health-kind-json-down-on-non-ok-status | `classify({ statusCode: 200, responseTimeMs: 100, expectedStatus: 200, isHealthKind: true, bodyText: '{"status":"degraded"}' })` | `'down'` — `health.test.ts` › "down when a health-kind JSON body reports non-ok status" |
| status-server-monitor-health-006 | expected-non-2xx-status-not-down | `classify({ statusCode: 401, responseTimeMs: 100, expectedStatus: 401 })` | `'healthy'` — `health.test.ts` › "honours a non-2xx expectedStatus match as not-down" |
| status-server-monitor-health-007 | health-kind-json-parse-failure-falls-through | `classify({ statusCode: 200, responseTimeMs: 100, expectedStatus: 200, isHealthKind: true, bodyText: "not json" })` | `'healthy'` — traced directly to the source's own comment on the `catch` branch ("Non-JSON body ... fall through to the marker/latency checks"); no test in `health.test.ts` exercises this branch directly |
| status-server-monitor-health-008 | health-kind-json-missing-status-field-falls-through | `classify({ statusCode: 200, responseTimeMs: 100, expectedStatus: 200, isHealthKind: true, bodyText: '{"ok":true}' })` | `'healthy'` — traced directly to the `"status" in parsed` guard; no test in `health.test.ts` exercises this branch directly |
| status-server-monitor-health-009 | health-kind-check-skipped-without-body-text | `classify({ statusCode: 200, responseTimeMs: 100, expectedStatus: 200, isHealthKind: true, bodyText: "" })` | `'healthy'` — traced directly to the `isHealthKind && bodyText` truthiness check; an empty string is falsy so the JSON parse never runs; no test in `health.test.ts` exercises this branch directly |
| status-server-monitor-health-010 | health-kind-status-field-string-coercion | `classify({ statusCode: 200, responseTimeMs: 100, expectedStatus: 200, isHealthKind: true, bodyText: '{"status":"OK"}' })` | `'healthy'` — traced directly to `String(status).toLowerCase() !== "ok"` matching case-insensitively; no test in `health.test.ts` exercises this branch directly |
| status-server-monitor-health-011 | health-kind-status-field-string-coercion | `classify({ statusCode: 200, responseTimeMs: 100, expectedStatus: 200, isHealthKind: true, bodyText: '{"status":200}' })` | `'down'` — traced directly to `String(200).toLowerCase()` producing the string `"200"`, which is not `"ok"`; no test in `health.test.ts` exercises this branch directly |
| status-server-monitor-health-012 | degraded-latency-threshold | `classify({ statusCode: 200, responseTimeMs: 2000, expectedStatus: 200 })` | `'healthy'` — traced directly to the strict `>` comparison; a `responseTimeMs` exactly equal to `DEGRADED_THRESHOLD_MS` is NOT degraded; no test in `health.test.ts` exercises this exact boundary |
| status-server-monitor-health-013 | classification-evaluation-order, health-kind-json-down-on-non-ok-status | `classify({ statusCode: 200, responseTimeMs: 100, expectedStatus: 200, isHealthKind: true, bodyText: '{"status":"degraded"}', bodyMarkerMissing: true })` | `'down'` — traced directly to the health-kind branch's early `return "down"`, which returns before the `bodyMarkerMissing` check ever runs; both conditions independently imply `'down'`, so this vector confirms evaluation order rather than the final value; no test in `health.test.ts` exercises this combination |

## Edge Cases

- **Null and empty input**: `bodyText: undefined` and `bodyText: ""` MUST both be treated as "no body to check" — `isHealthKind && bodyText` is falsy for either, so the JSON parse is skipped and evaluation proceeds to the `bodyMarkerMissing`/latency check (health-kind-check-skipped-without-body-text) — MUST. `isHealthKind: undefined` and `bodyMarkerMissing: undefined` MUST both be treated as `false` by the `&&`/`if` checks that read them, so an endpoint that never sets these optional fields gets the plain success/latency classification — MUST. `statusCode`, `responseTimeMs`, and `expectedStatus` are declared as required `number` fields on `ClassifyInput`; nothing inside `classify` validates that a caller actually supplied a finite number for any of them at runtime — this is a caller precondition enforced by the type signature, not unvalidated input the function's purpose calls for validating, since `classify` has exactly one caller in this codebase (`probe()` in `probe.ts`, external), which always supplies `res.status` and a computed millisecond duration.
- **Boundary values**: `responseTimeMs` exactly equal to `DEGRADED_THRESHOLD_MS` (`2000`) MUST classify as `"healthy"`, and `2001` MUST classify as `"degraded"` (degraded-latency-threshold, status-server-monitor-health-012) — MUST. `statusCode` at `199` MUST NOT be treated as a 2xx response, `200` and `299` MUST both be treated as 2xx, and `300` MUST NOT be treated as 2xx (success-status-range) — MUST.
- **Concurrent access**: `classify` is a synchronous, pure computation over its single `input` argument with no shared mutable state and no `await` of its own, so any number of concurrent callers MUST NOT interleave in a way that changes any single call's result — MUST.
- **Error states**: this file has no dependency of its own — no network call, no database access, no file I/O — so its only possible thrown error is `JSON.parse(bodyText)` inside the health-kind check; that throw MUST be caught and MUST NOT propagate out of `classify`, per health-kind-json-parse-failure-falls-through — MUST. `classify` never returns a value other than one of the three `HealthStatus` literals; there is no error return value or thrown error visible to a caller under any input this file's own logic can produce.
- **Offline / disconnected state**: not applicable — `classify` makes no network connection of its own to lose; it consumes the outcome of a fetch that its caller (`probe()`, external to this file) already completed or failed before calling `classify`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `statusCode` (field of `ClassifyInput`) | `number` | none — required | The HTTP response status code the caller's probe observed. |
| `responseTimeMs` (field of `ClassifyInput`) | `number` | none — required | The elapsed milliseconds the caller's probe measured for the response. |
| `expectedStatus` (field of `ClassifyInput`) | `number` | none — required | The status code the caller configured the endpoint to expect (may be non-2xx). |
| `isHealthKind` (field of `ClassifyInput`) | `boolean \| undefined` | `undefined` (treated as `false`) | Whether the endpoint is configured as a `health`-kind endpoint, gating the JSON-body status check. |
| `bodyText` (field of `ClassifyInput`) | `string \| undefined` | `undefined` (treated as "no body") | The response body text the caller's probe read, when it read one. |
| `bodyMarkerMissing` (field of `ClassifyInput`) | `boolean \| undefined` | `undefined` (treated as `false`) | Whether the caller determined the endpoint's configured `expectBody` marker was absent from the response body. |
| `DEGRADED_THRESHOLD_MS` (exported constant) | `number` | `2_000` | The latency, in milliseconds, above which a successful response is classified `"degraded"` rather than `"healthy"`. |
| `HEALTH_CHECK_TIMEOUT_MS` (exported constant) | `number` | `10_000` | A caller-facing default request-timeout, in milliseconds; not read by `classify` itself, and used by `probe.ts` (external) as the fallback for `ProbeOptions.timeoutMs`. |

## Deep Linking

Not applicable: this file defines no application route or URL pattern of its own — it exports only a type, an interface, two numeric constants, and a pure classification function.

## Localization

Not applicable: this file emits no user-facing string; `classify` returns only the internal `HealthStatus` literals (`"healthy"`, `"degraded"`, `"down"`), never displayed text — any operator-facing message built from a classification result (e.g. `probe.ts`'s `markerError`/`error` strings) is composed by callers external to this file.

## Accessibility Options

Not applicable: this file has no user interface and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system of any kind; `classify`'s behavior is unconditional for every input.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind.

## Privacy

- **Data collected**: none of this file's own. `classify` receives an already-fetched HTTP probe's status code, response time, expected status, and, optionally, a snippet of the probed endpoint's own response body, as plain function arguments from a caller (`probe()` in `probe.ts`, external to this file); it collects nothing itself.
- **Storage**: none. `classify` holds no state between calls and writes nothing; it returns a `HealthStatus` value to its caller and retains no reference to `bodyText` or any other field afterward.
- **Transmission**: none. This file makes no network or database call of its own; whether or how a `bodyText` snippet or a classification result travels anywhere is entirely the concern of callers external to this file.
- **Retention**: not applicable — this file holds no data across calls to retain.

## Logging

Not applicable: this file contains no logging or console call of any kind; `classify` is a pure synchronous function with no side effects of its own.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port would model `HealthStatus` as a `Sendable`, `String`-backed `enum` with cases `healthy`, `degraded`, and `down`, `ClassifyInput` as a `Sendable struct` mirroring the six fields (three non-optional, three `Optional`), and `classify` as a pure, non-isolated, synchronous top-level or static function — no `actor` or `@MainActor` isolation is needed because the function is stateless and takes no dependency.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models `HealthStatus` as an `enum class`, `ClassifyInput` as a `data class` with three nullable fields, and `classify` as a top-level function using a `when`/early-return chain in place of this file's nested `if`s; the JSON parse becomes `runCatching { Json.decodeFromString<JsonObject>(bodyText) }.getOrNull()` in place of the source's `try`/`catch`, preserving the same "parse failure falls through" contract.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/health.ts` as a plain ESM module on the Node status backend, imported by `probe.ts` for both `classify` and the `HEALTH_CHECK_TIMEOUT_MS` default; it has no test-adjacent sibling copy the way `endpoint-kinds.ts` or `deploy-status.ts` do, and no cross-package parity guard.
- **AppKit / UIKit**: same non-UI framing as SwiftUI; no windowing or view-layer concern applies, and this file's statelessness means there is nothing to duplicate per-window or per-controller either.
- **WinUI 3**: a .NET port models `HealthStatus` as a C# `enum` (`Healthy`, `Degraded`, `Down`), `ClassifyInput` as a `readonly record struct` with three required properties and three nullable properties (`bool?`, `string?`, `bool?`), and `Classify` as a `static` method (e.g. on a `HealthClassifier` class) using a C# `switch` expression or sequential early returns in place of the source's nested `if`s. The JSON check becomes `System.Text.Json.JsonDocument.Parse(bodyText)` wrapped in a `try`/`catch (JsonException)` that falls through exactly like the source's `catch`, reading the `status` property with `TryGetProperty` before comparing its `ToString()` against `"ok"` with `StringComparer.OrdinalIgnoreCase`. `HEALTH_CHECK_TIMEOUT_MS` and `DEGRADED_THRESHOLD_MS` become `public const int` fields; none of `HttpClient`, `Task`/`async`, `Windows.Storage`, or `ObservableCollection`/`INotifyPropertyChanged` is needed for this file specifically, since `Classify` itself performs no I/O and holds no observable state — those APIs belong to the port of `probe.ts`, external to this recipe's given source.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/health.ts` |

## Design Decisions

- **Decision**: return `"down"` from the health-kind JSON check before ever evaluating `bodyMarkerMissing`, rather than evaluating both independently and combining the results.
  **Rationale**: not stated in an inline comment; recorded here as a fact of the code per this recipe's authoring rules. The two checks happen to agree whenever both would fire (status-server-monitor-health-013), so the ordering is not currently observable in practice, but it is the exact sequence a future port MUST reproduce to stay behaviorally identical if the two checks are ever changed to disagree.
  **Approved**: pending
- **Decision**: on a JSON parse failure or a parsed body with no `status` field, fall through to the marker/latency checks rather than treating either case as `"down"` or as `"healthy"`.
  **Rationale**: stated directly in the source's own comment on the `catch` branch — "Non-JSON body (e.g. HTML page) — fall through to the marker/latency checks." A non-JSON or status-less body is not itself evidence of an outage; the marker and latency checks remain the deciding signal.
  **Approved**: pending
- **Decision**: let `bodyMarkerMissing` force `"down"` unconditionally, overriding what would otherwise be a `"healthy"` or `"degraded"` latency-based verdict.
  **Rationale**: stated directly in the source's own comment above the check — "A success status serving the WRONG content (broken shell, takeover page, empty app) is an outage the status code can't see — the marker can." A fast, well-formed-looking response serving the wrong page is still an outage regardless of how quickly it answered.
  **Approved**: pending
- **Decision**: use a strict `>` rather than `>=` for the degraded-latency comparison, so a response exactly at `DEGRADED_THRESHOLD_MS` classifies as `"healthy"`.
  **Rationale**: not stated in an inline comment; recorded here as a fact of the code per this recipe's authoring rules (degraded-latency-threshold, status-server-monitor-health-012).
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |

`unit-test-coverage` is `partial`: `health.test.ts` gives `classify` six assertions with meaningful expectations, covering fast/slow 2xx, a 5xx, a missing body marker, a non-ok health-kind JSON body, and a non-2xx `expectedStatus` match — but four branches this recipe traces directly to the source (a non-JSON body falling through, a JSON body with no `status` field falling through, the exact `DEGRADED_THRESHOLD_MS` latency boundary, and the case-insensitive/non-string `status` coercion) have no assertion of their own anywhere in `health.test.ts`. `separation-of-concerns` passes: this file's only responsibility is turning an already-observed probe outcome into a `HealthStatus` verdict; it performs no I/O, no persistence, and no HTTP/DNS work of its own, leaving fetching, timing, and body-reading to `probe.ts` (external). `explicit-error-handling` passes: the one error `classify` can encounter — `JSON.parse` throwing on a non-JSON `bodyText` — is caught by an explicit `try`/`catch` whose empty body is documented by an inline comment explaining the fall-through is deliberate, not an unhandled or silently-ignored exception path. `fault-tolerance` passes: `classify` accepts an arbitrary `bodyText` string (malformed JSON, HTML, or any other content) and an arbitrary `status` field shape (string, number, boolean, object) without throwing or crashing, per health-kind-json-parse-failure-falls-through and health-kind-status-field-string-coercion.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
