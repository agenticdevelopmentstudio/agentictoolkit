<!-- leaf: implement-status-web-src-lib-1/health · source: status-web-src-lib-health.md -->

**Rules** (cite as `implement-status-web-src-lib-1/health#<slug>`):

- `health-status-union` MUST
- `timeout-constant` MUST
- `degraded-threshold-constant` MUST
- `classify-input-shape` MUST
- `body-marker-meaning` MUST
- `classify-signature` MUST
- `success-gate` MUST
- `non-success-down` MUST
- `health-body-gate` MUST
- `health-body-not-ok-down` MUST
- `health-body-ok-case-insensitive` MUST
- `health-body-only-status-key` MUST
- `health-body-fallthrough-unparseable` MUST
- `health-body-fallthrough-unknown-shape` MUST
- `marker-missing-down` MUST
- `marker-absent-neutral` MUST
- `latency-degraded` MUST
- `latency-healthy` MUST
- `check-order` MUST
- `no-input-validation` MUST
- `pure-function` MUST
- `server-copy-identity` MUST

# Health Classification (status-web)

## Overview

`health.ts` (`packages/web/packages/status-web/src/lib/health.ts`) defines the status dashboard's three-valued endpoint verdict and the rule that produces it. It exports:

- `HealthStatus`, the string union `"healthy" | "degraded" | "down"`.
- `HEALTH_CHECK_TIMEOUT_MS` (10 000) and `DEGRADED_THRESHOLD_MS` (2 000).
- `ClassifyInput`, the facts one HTTP probe observed.
- `classify(input)`, a pure function that maps a `ClassifyInput` to a `HealthStatus`.

The file is a byte-identical copy of `packages/web/packages/status-server/src/monitor/health.ts` (status-server health). There the probe (status-server probe) calls `classify` with every endpoint result. Inside status-web only the `HealthStatus` type is imported: by `src/types.ts` (which re-exports it and uses it for endpoint `status` fields), `src/lib/uptime.ts` (`dayStatus`) and `src/lib/overall.ts` (`computeOverall`). No status-web runtime code calls `classify` or reads either constant. They are exercised only by `health.test.ts`. The module has no state, no I/O and no side effects.

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

## Platform Notes

- **SwiftUI**: Port as a caseless `enum Health` namespace with `static let healthCheckTimeoutMs = 10_000`, `degradedThresholdMs = 2_000`, an `enum HealthStatus: String, Codable, Sendable { case healthy, degraded, down }`, and a `struct ClassifyInput: Sendable` with optional `isHealthKind`, `bodyText` and `bodyMarkerMissing`. Decode the body with `JSONSerialization.jsonObject(with:options: .fragmentsAllowed)` and cast it to `[String: Any]`. A thrown error or a failed cast falls through, as `catch` does in the source. `String(describing:)` on an `NSNull` gives `"<null>"`, not `"null"`, which still fails the `"ok"` check. Model `bodyText` absent or empty with `guard let body = bodyText, !body.isEmpty`.
- **Compose**: Use a Kotlin `object Health` with `const val` constants, an `enum class HealthStatus`, and a `data class ClassifyInput` with nullable optionals. Parse with `kotlinx.serialization.json.Json.parseToJsonElement` inside `runCatching`, check `is JsonObject`, and read `jsonPrimitive.content` for `status`. A `JsonNull` has to stringify to `"null"` to keep the source's result. Use `in 200..299` for the gate.
- **React/Web**: This is the source: `src/lib/health.ts`, tested by `src/lib/health.test.ts` (Vitest). In status-web only the `HealthStatus` type is consumed (`src/types.ts`, `src/lib/uptime.ts`, `src/lib/overall.ts`). The runtime caller is status-server's `src/monitor/probe.ts`, which imports its own identical copy. The fall-through relies on `JSON.parse` throwing `SyntaxError` and on the `"status" in parsed` operator, which is also true for an inherited or `undefined`-valued `status` key.
- **AppKit / UIKit**: Use the same pure Swift code as the SwiftUI port, in a shared framework target. Nothing in it is UI-bound. A `URLSession` probe would pass `(response as? HTTPURLResponse)?.statusCode` and the measured latency.
- **WinUI 3**: Port as a `public static class Health` in C# with `public const int HealthCheckTimeoutMs = 10_000;`, `public const int DegradedThresholdMs = 2_000;`, a `public enum HealthStatus { Healthy, Degraded, Down }` (serialised lower-case through `System.Text.Json` with `JsonStringEnumConverter(JsonNamingPolicy.CamelCase)`), and a `public sealed record ClassifyInput(int StatusCode, double ResponseTimeMs, int ExpectedStatus, bool? IsHealthKind = null, string? BodyText = null, bool? BodyMarkerMissing = null)`. Parse the body with `JsonDocument.Parse` inside `try { } catch (JsonException) { }`, and check `root.ValueKind == JsonValueKind.Object && root.TryGetProperty("status", out var s)`. To match `String(status)`, map `JsonValueKind.Null` to `"null"`, `True`/`False` to `"true"`/`"false"`, a string to `s.GetString()`, and anything else to `s.GetRawText()`. Then compare with `string.Equals(v, "ok", StringComparison.OrdinalIgnoreCase)`. `classify` stays synchronous, with no `Task`. The probe that feeds it would use `HttpClient` with `Timeout = TimeSpan.FromMilliseconds(HealthCheckTimeoutMs)` (or a `CancellationTokenSource`), `(int)response.StatusCode`, and a `Stopwatch` for latency. A view model exposing the verdict would raise `INotifyPropertyChanged` when it changes. A C# `double.NaN > 2000` is also `false`, so NaN latency keeps the source's `Healthy` result.

