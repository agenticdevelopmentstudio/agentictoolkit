<!-- leaf: implement-status-server-monitor-1/health--part-2 · source: status-server-monitor-health.md -->

# Status Server Monitor Health — continued (part 2)

**Rules** (cite as `implement-status-server-monitor-1/health--part-2#<slug>`):

- `decision` MUST — return "down" from the health-kind JSON check before ever evaluating bodyMarkerMissing, rather than evaluating both …

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port would model `HealthStatus` as a `Sendable`, `String`-backed `enum` with cases `healthy`, `degraded`, and `down`, `ClassifyInput` as a `Sendable struct` mirroring the six fields (three non-optional, three `Optional`), and `classify` as a pure, non-isolated, synchronous top-level or static function — no `actor` or `@MainActor` isolation is needed because the function is stateless and takes no dependency.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models `HealthStatus` as an `enum class`, `ClassifyInput` as a `data class` with three nullable fields, and `classify` as a top-level function using a `when`/early-return chain in place of this file's nested `if`s; the JSON parse becomes `runCatching { Json.decodeFromString<JsonObject>(bodyText) }.getOrNull()` in place of the source's `try`/`catch`, preserving the same "parse failure falls through" contract.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/health.ts` as a plain ESM module on the Node status backend, imported by `probe.ts` for both `classify` and the `HEALTH_CHECK_TIMEOUT_MS` default; it has no test-adjacent sibling copy the way `endpoint-kinds.ts` or `deploy-status.ts` do, and no cross-package parity guard.
- **AppKit / UIKit**: same non-UI framing as SwiftUI; no windowing or view-layer concern applies, and this file's statelessness means there is nothing to duplicate per-window or per-controller either.
- **WinUI 3**: a .NET port models `HealthStatus` as a C# `enum` (`Healthy`, `Degraded`, `Down`), `ClassifyInput` as a `readonly record struct` with three required properties and three nullable properties (`bool?`, `string?`, `bool?`), and `Classify` as a `static` method (e.g. on a `HealthClassifier` class) using a C# `switch` expression or sequential early returns in place of the source's nested `if`s. The JSON check becomes `System.Text.Json.JsonDocument.Parse(bodyText)` wrapped in a `try`/`catch (JsonException)` that falls through exactly like the source's `catch`, reading the `status` property with `TryGetProperty` before comparing its `ToString()` against `"ok"` with `StringComparer.OrdinalIgnoreCase`. `HEALTH_CHECK_TIMEOUT_MS` and `DEGRADED_THRESHOLD_MS` become `public const int` fields; none of `HttpClient`, `Task`/`async`, `Windows.Storage`, or `ObservableCollection`/`INotifyPropertyChanged` is needed for this file specifically, since `Classify` itself performs no I/O and holds no observable state — those APIs belong to the port of `probe.ts`, external to this recipe's given source.

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
