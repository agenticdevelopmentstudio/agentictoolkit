---
id: 4ed891c0-4e4f-4955-8314-d143c45490ec
title: Health Classification (status-web)
domain: agentictoolkit://recipes/status-web-src-lib-health
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure rule mapping one HTTP probe result to healthy, degraded or down, plus
  the probe timeout and latency threshold constants
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://recipes/status-server-monitor-health
- agentictoolkit://recipes/status-server-monitor-probe
references: []
approved-by: ''
approved-date: ''
---

# Health Classification (status-web)

## Overview

`health.ts` (`packages/web/packages/status-web/src/lib/health.ts`) defines the status dashboard's three-valued endpoint verdict and the rule that produces it. It exports:

- `HealthStatus`, the string union `"healthy" | "degraded" | "down"`.
- `HEALTH_CHECK_TIMEOUT_MS` (10 000) and `DEGRADED_THRESHOLD_MS` (2 000).
- `ClassifyInput`, the facts one HTTP probe observed.
- `classify(input)`, a pure function that maps a `ClassifyInput` to a `HealthStatus`.

The file is a byte-identical copy of `packages/web/packages/status-server/src/monitor/health.ts` ([status-server health](agentictoolkit://recipes/status-server-monitor-health)). There the probe ([status-server probe](agentictoolkit://recipes/status-server-monitor-probe)) calls `classify` with every endpoint result. Inside status-web only the `HealthStatus` type is imported: by `src/types.ts` (which re-exports it and uses it for endpoint `status` fields), `src/lib/uptime.ts` (`dayStatus`) and `src/lib/overall.ts` (`computeOverall`). No status-web runtime code calls `classify` or reads either constant. They are exercised only by `health.test.ts`. The module has no state, no I/O and no side effects.

## Behavioral Requirements

### Types and constants

- **health-status-union**: `HealthStatus` MUST be exactly the string union `"healthy" | "degraded" | "down"`. It has no `"unknown"` member. Consumers that need one (the `status` fields in `src/types.ts`) widen it to `HealthStatus | "unknown"` themselves.
- **timeout-constant**: `HEALTH_CHECK_TIMEOUT_MS` MUST equal 10 000 ms. `classify` does not read it. It is the default probe timeout that the status-server probe reads as `opts.timeoutMs ?? HEALTH_CHECK_TIMEOUT_MS`.
- **degraded-threshold-constant**: `DEGRADED_THRESHOLD_MS` MUST equal 2 000 ms.
- **classify-input-shape**: `ClassifyInput` MUST carry the required fields `statusCode: number`, `responseTimeMs: number` and `expectedStatus: number`, plus the optional fields `isHealthKind?: boolean`, `bodyText?: string` and `bodyMarkerMissing?: boolean`.
- **body-marker-meaning**: Per its doc comment, `bodyMarkerMissing` MUST be `true` only when the endpoint's configured `expectBody` marker was NOT found in the response body. The caller computes it. `classify` never searches the body for a marker itself.

### classify

- **classify-signature**: `classify` MUST take one `ClassifyInput` and synchronously return a `HealthStatus`.
- **success-gate**: `classify` MUST treat a response as a success candidate when `statusCode` is in the range 200 to 299 inclusive, or when `statusCode` strictly equals `expectedStatus`.
- **non-success-down**: `classify` MUST return `"down"` when `statusCode` is outside 200 to 299 and does not equal `expectedStatus`. It does so regardless of latency, body or marker.
- **health-body-gate**: `classify` MUST inspect `bodyText` only when all three of these hold: `statusCode` is 2xx, `isHealthKind` is truthy, and `bodyText` is a non-empty string. A non-2xx `statusCode` that matches `expectedStatus` never has its body inspected.
- **health-body-not-ok-down**: When the health-body gate holds and `bodyText` parses as JSON to a non-null object with a `status` key, `classify` MUST return `"down"` if `String(status).toLowerCase()` is not `"ok"`.
- **health-body-ok-case-insensitive**: The `status` comparison MUST be case-insensitive, so `"ok"`, `"OK"` and `"Ok"` all pass the body check.
- **health-body-only-status-key**: The body check MUST read only the `status` key. Other keys, such as an `"ok": false` field beside `"status": "down"`, MUST NOT influence the verdict.
- **health-body-fallthrough-unparseable**: When `bodyText` is not valid JSON (for example an HTML page), `classify` MUST discard the parse failure and continue to the marker and latency checks. Per the source comment this is deliberate: "Non-JSON body (e.g. HTML page) — fall through to the marker/latency checks."
- **health-body-fallthrough-unknown-shape**: When the parsed JSON is not a non-null object with a `status` key (for example `{"result":"ok"}`, a JSON array, a string, a number or `null`), `classify` MUST continue to the marker and latency checks without returning `"down"`.
- **marker-missing-down**: For any success candidate that the body check did not already mark `"down"`, `classify` MUST return `"down"` when `bodyMarkerMissing` is `true`. This applies to a custom `expectedStatus` match as well as to a 2xx.
- **marker-absent-neutral**: When `bodyMarkerMissing` is `false` or `undefined`, the marker MUST NOT change the verdict.
- **latency-degraded**: For a success candidate that passed the body and marker checks, `classify` MUST return `"degraded"` when `responseTimeMs` is strictly greater than `DEGRADED_THRESHOLD_MS`.
- **latency-healthy**: For a success candidate that passed the body and marker checks, `classify` MUST return `"healthy"` when `responseTimeMs` is less than or equal to `DEGRADED_THRESHOLD_MS`.
- **check-order**: `classify` MUST apply its checks in this order: status gate, then health body, then marker, then latency. A `"down"` from an earlier check MUST short-circuit, so a slow response that fails the body or marker check is `"down"`, not `"degraded"`.
- **no-input-validation**: `classify` MUST NOT validate its numeric inputs. A non-finite `statusCode` fails the status gate and yields `"down"`. A `NaN` `responseTimeMs` fails the greater-than comparison and yields `"healthy"`. A negative `responseTimeMs` also yields `"healthy"`.

### Purity and concurrency

- **pure-function**: `classify` MUST be pure. It MUST NOT perform I/O, log, mutate its input, or throw on any input of the declared types. The only exception it can raise internally, from `JSON.parse`, is caught locally.
- **single-threaded**: The module holds no state and runs on the single JavaScript thread, so concurrent calls cannot interleave and need no ordering rule.
- **server-copy-identity**: This file MUST stay identical to `status-server/src/monitor/health.ts`, because the dashboard's `HealthStatus` type describes values the server's `classify` produced. No parity test enforces this. status-web has parity tests for `deploy-status` and `board-types`, but none for `health`, so drift between the two copies would go undetected.

## Appearance

Not applicable — this is a pure health-classification module, not a visual component.

## States

Not applicable — this is a pure health-classification module, not a visual component.

## Accessibility

Not applicable — this is a pure health-classification module, not a visual component.

## Conformance Test Vectors

Vectors 001 to 018 are traced to the assertions in `health.test.ts`. Vectors 019 to 026 are traced to the `classify` body (the `is2xx` gate, the `isHealthKind && bodyText` guard, the `toLowerCase()` comparison, and the strict `>` comparison). Rows that omit `expectedStatus` use `expectedStatus: 200`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| health-001 | timeout-constant, degraded-threshold-constant | Read `HEALTH_CHECK_TIMEOUT_MS` and `DEGRADED_THRESHOLD_MS` | 10 000 and 2 000 |
| health-002 | success-gate, latency-healthy | `statusCode: 200, responseTimeMs: 100, expectedStatus: 200` | `"healthy"` |
| health-003 | latency-degraded | `statusCode: 200, responseTimeMs: 2001, expectedStatus: 200` | `"degraded"` |
| health-004 | non-success-down | `statusCode: 500, responseTimeMs: 50, expectedStatus: 200` | `"down"` |
| health-005 | success-gate | `statusCode: 403, responseTimeMs: 50, expectedStatus: 403` | `"healthy"` |
| health-006 | health-body-not-ok-down | `statusCode: 200, responseTimeMs: 50, expectedStatus: 200, isHealthKind: true, bodyText: {"status":"degraded"}` | `"down"` |
| health-007 | health-body-gate, latency-healthy | Same as 006 with `bodyText: {"status":"ok"}` | `"healthy"` |
| health-008 | check-order, latency-degraded | `statusCode: 200, responseTimeMs: 2001, isHealthKind: true, bodyText: {"status":"ok"}` | `"degraded"` |
| health-009 | health-body-only-status-key | `statusCode: 200, responseTimeMs: 50, isHealthKind: true, bodyText: {"status":"down","ok":false}` | `"down"` |
| health-010 | health-body-fallthrough-unparseable | `statusCode: 200, responseTimeMs: 50, isHealthKind: true, bodyText: <html><body>OK</body></html>` | `"healthy"` |
| health-011 | health-body-fallthrough-unknown-shape | `statusCode: 200, responseTimeMs: 50, isHealthKind: true, bodyText: {"result":"ok"}` | `"healthy"` |
| health-012 | success-gate, latency-degraded | `statusCode: 403, responseTimeMs: 2001, expectedStatus: 403` | `"degraded"` |
| health-013 | marker-missing-down | `statusCode: 200, responseTimeMs: 100, expectedStatus: 200, bodyMarkerMissing: true` | `"down"` |
| health-014 | marker-absent-neutral, latency-healthy | Same as 013 with `bodyMarkerMissing: false` | `"healthy"` |
| health-015 | marker-absent-neutral, latency-degraded | `statusCode: 200, responseTimeMs: 5000, bodyMarkerMissing: false` | `"degraded"` |
| health-016 | marker-missing-down | `statusCode: 401, expectedStatus: 401, responseTimeMs: 100, bodyMarkerMissing: true` | `"down"` |
| health-017 | marker-absent-neutral | `statusCode: 401, expectedStatus: 401, responseTimeMs: 100, bodyMarkerMissing: false` | `"healthy"` |
| health-018 | marker-absent-neutral | `statusCode: 200, responseTimeMs: 100, expectedStatus: 200` (no marker field) | `"healthy"` |
| health-019 | latency-healthy | `statusCode: 200, responseTimeMs: 2000, expectedStatus: 200` | `"healthy"` (the threshold itself is not degraded) |
| health-020 | health-body-gate | `statusCode: 403, expectedStatus: 403, responseTimeMs: 50, isHealthKind: true, bodyText: {"status":"down"}` | `"healthy"` (the body is not inspected for a non-2xx match) |
| health-021 | health-body-gate | `statusCode: 200, responseTimeMs: 50, isHealthKind: true, bodyText: ""` | `"healthy"` (an empty body skips the check) |
| health-022 | health-body-ok-case-insensitive | `statusCode: 200, responseTimeMs: 50, isHealthKind: true, bodyText: {"status":"OK"}` | `"healthy"` |
| health-023 | health-body-gate | `statusCode: 200, responseTimeMs: 50, isHealthKind: false, bodyText: {"status":"down"}` | `"healthy"` |
| health-024 | check-order, marker-missing-down | `statusCode: 200, responseTimeMs: 5000, bodyMarkerMissing: true` | `"down"` (not `"degraded"`) |
| health-025 | non-success-down, check-order | `statusCode: 301, expectedStatus: 200, responseTimeMs: 50, bodyMarkerMissing: false` | `"down"` |
| health-026 | no-input-validation | `statusCode: 200, responseTimeMs: NaN, expectedStatus: 200` | `"healthy"` |

## Edge Cases

- **Status code just outside 2xx**: `statusCode` 199 or 300 with a different `expectedStatus` MUST return `"down"`. 200 and 299 MUST be success candidates.
- **`expectedStatus` inside 2xx**: When `expectedStatus` is 204 and the response is 200, the response MUST still be a success candidate, because any 2xx passes the gate. `expectedStatus` only widens the gate. It never narrows it.
- **Latency at the threshold**: `responseTimeMs` of exactly 2 000 MUST return `"healthy"`. 2 001 MUST return `"degraded"`.
- **Empty or missing `bodyText` on a health-kind endpoint**: The body check MUST be skipped, and the verdict falls to the marker and latency checks.
- **Malformed JSON body**: The `JSON.parse` exception MUST be caught and discarded, and classification continues. This is the documented fall-through, not a lost error. The caller still receives a verdict.
- **JSON `null`, array, string or number body**: The body check MUST be skipped, because only a non-null object with a `status` key is judged.
- **Non-string `status` value**: `status` is stringified before comparison, so `{"status": null}` (`"null"`), `{"status": true}` (`"true"`) and `{"status": 1}` MUST all return `"down"`.
- **Marker flag on a non-success response**: When the status gate fails, `bodyMarkerMissing` MUST have no effect, and the result is `"down"` either way.
- **Non-finite or negative `responseTimeMs`**: `NaN` and negative values MUST return `"healthy"` for a success candidate, because only a strict greater-than comparison against 2 000 is made. `Infinity` MUST return `"degraded"`. The only production caller (status-server's probe) computes the value from wall-clock differences, which keeps it finite and non-negative.
- **Timeout**: `classify` has no timeout and performs no waiting. A timed-out probe never reaches `classify`. The status-server probe enforces `HEALTH_CHECK_TIMEOUT_MS` and reports the timeout on its own `catch` path.
- **Concurrent access**: Not applicable. The module is stateless and runs on single-threaded JavaScript.
- **Network errors and offline**: Not applicable. The module performs no I/O. The caller receives the response and measures latency before it calls `classify`.
- **Copy drift**: If `status-server/src/monitor/health.ts` gains a fourth status and this copy does not, the dashboard's `HealthStatus` would not describe server values. No test catches this (see server-copy-identity).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `statusCode` | `number` | none (required) | The HTTP status code the probe received. |
| `responseTimeMs` | `number` | none (required) | The measured response latency in milliseconds. |
| `expectedStatus` | `number` | none (required) | The endpoint's configured expected status. A match passes the gate even outside 2xx. |
| `isHealthKind` | `boolean` | `undefined` (falsy) | True for a health-kind endpoint whose JSON `status` has to read `"ok"`. |
| `bodyText` | `string` | `undefined` | The response body, only needed for the health-kind check. |
| `bodyMarkerMissing` | `boolean` | `undefined` (falsy) | True when the configured `expectBody` marker was not found in the body. |
| `HEALTH_CHECK_TIMEOUT_MS` | constant | 10 000 | The default probe timeout, compiled in. `classify` does not read it. |
| `DEGRADED_THRESHOLD_MS` | constant | 2 000 | The latency above which a success candidate is degraded, compiled in. |

The module reads no environment variables and no settings keys, and takes no injected dependencies. It has no imports.

## Deep Linking

Not applicable: the module exports a pure function, a type and two constants, and has no navigable surface.

## Localization

Not applicable: `classify` returns fixed string-union tokens (`"healthy"`, `"degraded"`, `"down"`), not user-facing text. The error strings shown to operators are built by the status-server probe, not here.

## Accessibility Options

Not applicable: the module renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: the source reads no flag. Every check applies whenever its input field is supplied.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module reads a status code, a latency, flags and an optional response body in memory. It stores and transmits nothing.

## Logging

Not applicable: the module makes no log calls. The discarded `JSON.parse` failure is deliberate and is not logged.

## Platform Notes

- **SwiftUI**: Port as a caseless `enum Health` namespace with `static let healthCheckTimeoutMs = 10_000`, `degradedThresholdMs = 2_000`, an `enum HealthStatus: String, Codable, Sendable { case healthy, degraded, down }`, and a `struct ClassifyInput: Sendable` with optional `isHealthKind`, `bodyText` and `bodyMarkerMissing`. Decode the body with `JSONSerialization.jsonObject(with:options: .fragmentsAllowed)` and cast it to `[String: Any]`. A thrown error or a failed cast falls through, as `catch` does in the source. `String(describing:)` on an `NSNull` gives `"<null>"`, not `"null"`, which still fails the `"ok"` check. Model `bodyText` absent or empty with `guard let body = bodyText, !body.isEmpty`.
- **Compose**: Use a Kotlin `object Health` with `const val` constants, an `enum class HealthStatus`, and a `data class ClassifyInput` with nullable optionals. Parse with `kotlinx.serialization.json.Json.parseToJsonElement` inside `runCatching`, check `is JsonObject`, and read `jsonPrimitive.content` for `status`. A `JsonNull` has to stringify to `"null"` to keep the source's result. Use `in 200..299` for the gate.
- **React/Web**: This is the source: `src/lib/health.ts`, tested by `src/lib/health.test.ts` (Vitest). In status-web only the `HealthStatus` type is consumed (`src/types.ts`, `src/lib/uptime.ts`, `src/lib/overall.ts`). The runtime caller is status-server's `src/monitor/probe.ts`, which imports its own identical copy. The fall-through relies on `JSON.parse` throwing `SyntaxError` and on the `"status" in parsed` operator, which is also true for an inherited or `undefined`-valued `status` key.
- **AppKit / UIKit**: Use the same pure Swift code as the SwiftUI port, in a shared framework target. Nothing in it is UI-bound. A `URLSession` probe would pass `(response as? HTTPURLResponse)?.statusCode` and the measured latency.
- **WinUI 3**: Port as a `public static class Health` in C# with `public const int HealthCheckTimeoutMs = 10_000;`, `public const int DegradedThresholdMs = 2_000;`, a `public enum HealthStatus { Healthy, Degraded, Down }` (serialised lower-case through `System.Text.Json` with `JsonStringEnumConverter(JsonNamingPolicy.CamelCase)`), and a `public sealed record ClassifyInput(int StatusCode, double ResponseTimeMs, int ExpectedStatus, bool? IsHealthKind = null, string? BodyText = null, bool? BodyMarkerMissing = null)`. Parse the body with `JsonDocument.Parse` inside `try { } catch (JsonException) { }`, and check `root.ValueKind == JsonValueKind.Object && root.TryGetProperty("status", out var s)`. To match `String(status)`, map `JsonValueKind.Null` to `"null"`, `True`/`False` to `"true"`/`"false"`, a string to `s.GetString()`, and anything else to `s.GetRawText()`. Then compare with `string.Equals(v, "ok", StringComparison.OrdinalIgnoreCase)`. `classify` stays synchronous, with no `Task`. The probe that feeds it would use `HttpClient` with `Timeout = TimeSpan.FromMilliseconds(HealthCheckTimeoutMs)` (or a `CancellationTokenSource`), `(int)response.StatusCode`, and a `Stopwatch` for latency. A view model exposing the verdict would raise `INotifyPropertyChanged` when it changes. A C# `double.NaN > 2000` is also `false`, so NaN latency keeps the source's `Healthy` result.

## Design Decisions

**Decision**: A health-kind endpoint returning 2xx is down unless its JSON `status` reads `"ok"`.
**Rationale**: A health endpoint can answer 200 while reporting itself unhealthy (`{"status":"degraded"}`, `{"status":"down","ok":false}`). Only the `status` key is read, so a sibling `"ok"` token cannot trip the check (per the test named 'not tripped by the "ok" token').
**Approved**: pending

**Decision**: An unparseable or unknown-shape health body falls through instead of failing down.
**Rationale**: The source comment says a non-JSON body such as an HTML page falls through to the marker and latency checks. A health-kind URL serving HTML is judged by status, marker and latency, not treated as an outage.
**Approved**: pending

**Decision**: A missing `expectBody` marker makes any success candidate down.
**Rationale**: The source comment says "A success status serving the WRONG content (broken shell, takeover page, empty app) is an outage the status code can't see — the marker can." It applies to custom `expectedStatus` matches too.
**Approved**: pending

**Decision**: `expectedStatus` widens the success gate rather than replacing the 2xx rule.
**Rationale**: The gate is `is2xx || statusCode === expectedStatus`. An endpoint expected to return 401 or 403 (an auth-walled page) can be healthy, while any 2xx stays a success candidate for every endpoint.
**Approved**: pending

**Decision**: Latency degrades only above 2 000 ms, using a strict comparison.
**Rationale**: `responseTimeMs > DEGRADED_THRESHOLD_MS`, and the test uses `DEGRADED_THRESHOLD_MS + 1` as the first degraded value. Latency never makes an endpoint down. Down comes only from status, body or marker.
**Approved**: pending

**Decision**: Keep a vendored copy of the server's `health.ts` in status-web instead of importing it.
**Rationale**: status-web is the server's embedded web app and mirrors server vocabularies locally, as it does for `deploy-status` and `board-types`. Unlike those two, this copy has no parity test.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | passed | reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | reliability |

**Separation of concerns.** The module holds only the classification rule and its thresholds. Fetching, timing, body capping and error-message wording live in the status-server probe.

**Unit test coverage.** `health.test.ts` covers the constants, every branch of `classify` (2xx, expected-status match, non-match, health body ok, not ok, non-JSON and unknown shape, marker present, missing and absent) and the latency threshold on both sides.

**Explicit error handling.** Partial. The `JSON.parse` failure is caught and deliberately discarded with a documented comment, and the caller always receives a verdict. There is no signal to tell "body was HTML" apart from "body was healthy".

**Health observability.** The module defines the three-valued verdict the dashboard shows for every endpoint, and it separates slow (degraded) from broken (down).

**Data integrity.** Partial. The numeric inputs are not validated, so a `NaN` latency classifies as healthy. The web copy is also kept identical to the server copy only by convention, with no parity test.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation from source |
