<!-- leaf: implement-status-web-src-lib-1/board-types--part-2 · source: status-web-src-lib-board-types.md -->

# Board Wire Types — continued (part 2)

## Platform Notes

- **SwiftUI**: Model each interface as a `struct` conforming to `Codable, Sendable, Hashable`; each union as a `String`-raw-value `enum` conforming to `Codable`. Nullable fields become optionals, decoded with `JSONDecoder` (keys already camelCase). Unlike TypeScript, decoding validates at runtime: an unknown `IssueSource` or `state` member fails decode, so decide per field whether to add an `unknown` fallback case. `ActivityRow.id` is the natural `Identifiable.id`.
- **Compose**: Kotlin `@Serializable data class` per interface with `kotlinx.serialization`; unions as `enum class` with `@SerialName` for hyphenated members (`"cloudflare-pages"`). Set `Json { ignoreUnknownKeys = true }` if the server may add fields; an unknown enum value throws unless `coerceInputValues` or a custom serializer handles it.
- **React/Web**: Source platform. `src/lib/board-types.ts` is the type-only mirror; `src/lib/board-types-parity.test.ts` holds the `Exact<A, B>` mutual-assignability guard against `@agentic-toolkit/status-server/board` plus the `indicatorFromProblems` versus `indicatorFor` agreement tests. Types are erased, so a port that wants runtime safety adds a schema (for example zod) at the fetch site.
- **AppKit / UIKit**: Same `Codable` structs as the SwiftUI note, in a UI-free module shared by both; no framework types are involved.
- **WinUI 3**: Declare C# `record` types (`public sealed record Problem(...)`) with `string?`/`int?`/`long?` for nullable fields and `IReadOnlyList<T>` for arrays, deserialized with `System.Text.Json` (`JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }`). Map unions to C# `enum`s with `JsonStringEnumConverter` plus `[JsonStringEnumMemberName("cloudflare-pages")]` (.NET 9) for hyphenated members, or keep them `string` to mirror TypeScript's lenient behavior. Epoch-ms fields (`dataAsOfMs`, `atMs`, `probeIntervalMs`, `activityFromMs`) are `long`; ISO fields may be `DateTimeOffset`, but keep `ActivityRow.id` a `string`. For binding, project `Board.problems` and `Board.activity` into an `ObservableCollection<T>` keyed by `target` / `id` in a view model that implements `INotifyPropertyChanged`. There is no compile-time parity check against the server; a shared contract assembly or a JSON-schema test replaces `board-types-parity.test.ts`.

## Design Decisions

**Decision**: Hand-mirror the server's board types instead of importing them.
**Rationale**: The header comment states the web app "cannot import at runtime" the server tree; there is no shared package between the backend and its embedded web app. Drift is caught by the parity test's `Exact<A, B>` checks, compiled by two typechecks.
**Approved**: pending

**Decision**: Carry `tone` and `verb` on the wire instead of deriving them in the client.
**Rationale**: "the server owns what a row SAYS, exactly as it owns whether the row exists"; `ActivityTone` matches `RowTone` one-for-one so the pane renders it directly, and `kind` is never recomputed from `tone` (the doc comment cites that exact mistake as defect #1 in the spec).
**Approved**: pending

**Decision**: Platform-health targets use two segments, `platform-health|<source>`, not `boardTargetKey()` output.
**Rationale**: That spelling already exists in the `issues` table; "a provider is not a deploy target, and giving it a third segment would orphan every live platform-health row for no gain."
**Approved**: pending

**Decision**: Deploy row ids exclude target and timestamp.
**Rationale**: Those deployment fields are corrected after first render, and the client cannot distinguish a renamed row from a replaced one, so ids must use only immutable components.
**Approved**: pending

**Decision**: Paging cursor is the `(atMs, id)` pair.
**Rationale**: Build and deploy rows of one deployment share a `createdAtMs`; a time-only cursor would re-serve or skip one of them.
**Approved**: pending

**Decision**: `Board` carries `probeIntervalMs`, `activityFromMs` and `monitoredTargets`.
**Rationale**: The cadence previously arrived only on the SSE stream and was null for non-stream consumers; the activity boundary is read rather than re-derived; `monitoredTargets` replaces `/live`'s `deployTargets` so the ledger writer can tell recovery from de-configuration, since `resolveIssue` alerts on the first and stays silent on the second.
**Approved**: pending
