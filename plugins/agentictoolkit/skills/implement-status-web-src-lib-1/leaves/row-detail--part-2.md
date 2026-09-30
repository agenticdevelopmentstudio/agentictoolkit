<!-- leaf: implement-status-web-src-lib-1/row-detail--part-2 · source: status-web-src-lib-row-detail.md -->

# Row Detail — continued (part 2)

## Localization

The serializer's labels are hardcoded English and the module has no localization layer. The copied text is meant for pasting into an LLM, and the labels are part of that format.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `rowDetailToText.endpoint` | `endpoint` | Label for the row title |
| `rowDetailToText.url` | `url` | Label for the title URL |
| `rowDetailToText.environment` | `environment` | Label for the environment |
| `rowDetailToText.platform` | `platform` | Label for the platform phrase |
| `rowDetailToText.problem` | `problem` | Label for the problem text |
| `rowDetailToText.httpStatus` | `http status` | Label for the last probe's HTTP status |
| `rowDetailToText.response` | `response` | Label for the last probe's latency |
| `rowDetailToText.branch` | `branch` | Label for the deploy branch |
| `rowDetailToText.since` | `since` | Label for the onset time |
| `rowDetailToText.lastCheck` | `last check` | Label for the last probe time |
| `rowDetailToText.commit` | `commit` | Label for the SHA and subject |
| `rowDetailToText.commitUrl` | `commit url` | Label for the commit URL |
| `rowDetailToText.link` | `link` | Label for the provider dashboard or logs link |
| `rowDetailToText.error` | `error:` | Header line of the error block |
| `rowToDetailProps.platformText` | `{statusWord} on {platform}` | Platform phrase, for example `built on vercel` |

## Platform Notes

- **SwiftUI**: Port `RowDetail` as a `struct RowDetail: Sendable, Equatable` with optionals, and `deployOutcome` as `enum DeployOutcome: String, Sendable { case success, failed }?`. Write the two functions as a `static func` on `RowDetail` or as an initializer `RowDetail(row:)`. Use `URL(string:)?.host()` for `hostOf`, falling back to the raw string when it returns nil. Note that `URL.host` omits the port while the web `URL.host` includes it. Swift's `??` treats an empty string as a value, as JavaScript's does, but the truthiness checks (`row.detail && ...`, `d.titleUrl && ...`) become explicit `isEmpty` tests. Build the text with `[String]` and `joined(separator: "\n")`.
- **Compose**: Use a Kotlin `data class RowDetail` with nullable fields and an `enum class DeployOutcome`. Write the functions as top-level pure functions. Use `java.net.URI(url).host` in a `runCatching`, falling back to the input, and add the port to match the web behavior. Kotlin's `?:` matches `??`, and truthiness checks become `!isNullOrEmpty()`. Build the text with `buildList { }` and `joinToString("\n")`.
- **React/Web**: This is the source, `src/lib/row-detail.ts`, with tests in `src/lib/row-detail.test.ts` (Vitest). `ActivityPanel.tsx` and `ActivityDetails.tsx` call it. It relies on JavaScript truthiness (empty string, `0` and `null` are falsy) for the platform, problem, URL and commit tests, and on `??` for the fallbacks. A port must reproduce which test uses which.
- **AppKit / UIKit**: Use the same Swift value type and functions as the SwiftUI port. Nothing is UI-bound, so the code belongs in a shared framework target. The copy action writes the returned string to `NSPasteboard.general` or `UIPasteboard.general`.
- **WinUI 3**: Port `RowDetail` as a C# `public sealed record RowDetail` with nullable reference types (`string?`, `int?`) and `DeployOutcome?` as an `enum` with `JsonStringEnumConverter` if it is serialized with `System.Text.Json`. Write the functions as a `public static class RowDetailMapper` with `ToDetail(Row row)` and `ToText(RowDetail d)`. Use `Uri.TryCreate(url, UriKind.Absolute, out var u) ? u.Authority : url` for `hostOf`, because `Uri.Authority` includes a non-default port as the web `URL.host` does. C#'s `??` matches JavaScript's, but truthiness tests become `!string.IsNullOrEmpty(...)`, and the numeric `0` must stay emitted. Use `HashSet<string>` with `StringComparer.Ordinal` (or `FrozenSet`) for the non-deploy set. Build the text with `StringBuilder` or `string.Join("\n", lines)`, and never `Environment.NewLine`, because the source joins with `\n`. The functions are synchronous: no `Task`. A view model that exposes the selected row's detail raises `INotifyPropertyChanged` for its own property, and the copy button calls `DataPackage.SetText` then `Clipboard.SetContent`.

## Design Decisions

**Decision**: `rowToDetailProps` copies StatusRow's title-link precedence exactly.
**Rationale**: The doc comment says the row and the details pane must "always agree on titles/links". An endpoint is its checked URL (`liveUrl` first), and a deploy's title links to its deployment page (`sourceUrl` first).
**Approved**: pending

**Decision**: The status word is rendered exactly as the server sent it, and the function takes no clock.
**Rationale**: The doc comment says the client-side freshness demotion this function used to apply is gone, and its `nowMs` parameter with it. The server's verdict is the only verdict.
**Approved**: pending

**Decision**: The problem field is dropped when it equals the commit subject.
**Rationale**: Deploy-status issues set `detail` to the commit's first line. Showing it twice adds nothing, because the commit field already shows it.
**Approved**: pending

**Decision**: `platformLink` points at the deployment page.
**Rationale**: The source comment says only the specific deployment URL is stored and no project-level dashboard URL can be derived from the provider metadata, so the deployment page is the closest deployments context available.
**Approved**: pending

**Decision**: `since` prefers `downSince` and falls back to the row's event time.
**Rationale**: The list only carries a relative label. The pane always shows an absolute time, and the server-truth down-since is durable across browsers.
**Approved**: pending

**Decision**: An explicit set (`crunchy`, `glitchtip`) is excluded from the deploy outcome.
**Rationale**: Crunchy rows are database-cluster health mapped onto deploy phases, and GlitchTip rows are application errors. Neither built nor deployed anything, so a "build / deploy FAILED" headline would name an event that did not happen, and the pane's `logs` label would present an exception list as a build log. The platform name cannot tell them apart, because it is truthy for every registered source.
**Approved**: pending

**Decision**: The copy text puts the error text in its own block and ends with the full commit body.
**Rationale**: The source comment says the error text is "the whole point of the copy (paste straight into an LLM) and may be multi-line", so it gets a labeled block. The body is appended only when it adds to the subject.
**Approved**: pending
