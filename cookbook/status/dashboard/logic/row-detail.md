---
id: d76fe59c-9633-4d9f-82c7-4091c5e7f54e
title: Row Detail
domain: agentictoolkit://cookbook/status/dashboard/logic/row-detail
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure mapping from a status-board row to the labeled row detail the details
  pane renders, plus its plaintext serialization for copy
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status/dashboard/logic/deploy-display
references: []
approved-by: ''
approved-date: ''
---

# Row Detail

## Overview

This logic turns one status-board row (specified in [Status Row Model](agentictoolkit://cookbook/status/dashboard/logic/row-model)) into the fields the details pane shows for a selected row, and turns those fields into plaintext for the pane's "copy" button. Its callers are the activity panel view and the activity details view.

It provides one data shape and two pure functions:

- **The row detail** is the shape of labeled, nullable fields the details pane renders.
- **The detail-building function** maps a row to a row detail. Its documented intent is that it "mirrors the row's own link derivations so the row and the details pane always agree on titles/links", and it renders the status word exactly as the server sent it.
- **The serialization function** turns a row detail into "a clean, labeled plaintext block" so "the whole problem ... can be pasted straight into an LLM without opening the provider dashboard".

This logic depends on a host-extraction helper, which returns a URL's host or the input unchanged when parsing fails, and on the platform label function specified in [Deploy Display](agentictoolkit://cookbook/status/dashboard/logic/deploy-display). It has no state, no I/O and no side effects.

## Behavioral Requirements

### Data shapes

- **row-input-shape**: The detail-building function MUST accept a row with these fields (named as in [Status Row Model](agentictoolkit://cookbook/status/dashboard/logic/row-model)): `key`, `source`, `platform` (string or absent), `name`, `environment` (string or absent), `statusWord`, `tone` (one of `good`, `bad`, `progress`, `neutral`, `stale`), `sha`, `commitUrl`, `message`, `detail`, `at` (an ISO timestamp), `sourceUrl`, `liveUrl`, plus the optional `commitBody`, `statusCode`, `responseTimeMs`, `lastCheckedAt`, `downSince`, `branch` and `errorText`.
- **row-detail-shape**: The row detail MUST hold exactly these fields: `title` (a string), and the following, each nullable: `titleUrl`, `environment`, `platformText`, `platformLink`, `problem`, `problemLink`, `statusCode` (a number or null), `responseTime`, `branch`, `since`, `lastChecked`, `sha`, `commitSubject`, `commitUrl`, `commitBody`, `errorText`, and `deployOutcome` (one of `success`, `failed`, or null).
- **optional-fields-null**: Every optional row field that is absent MUST become `null` in the row detail. This covers `statusCode`, `branch`, `lastChecked`, `commitBody` and `errorText`.

### The detail-building function: row classification

- **endpoint-classification**: A row MUST be treated as an endpoint row when its `platform` is exactly `"http"` or `"dns"`, and as a deploy row otherwise.
- **resolved-classification**: A row MUST be treated as resolved when its `statusWord` starts with the character `[`, as in `"[deploy failed] resolved"`.
- **platform-name**: The platform name MUST be the platform label (see Deploy Display) of the row's platform, lower-cased, when the row is not an endpoint, the platform is truthy, and the row is not resolved. Otherwise it MUST be absent. For example, `vercel` yields `vercel` and `cloudflare-pages` yields `cloudflare`.

### The detail-building function: title and links

- **endpoint-title-url**: For an endpoint row, `titleUrl` MUST be the row's `liveUrl`, falling back to `sourceUrl`, then `null`. The documented reasoning is "an endpoint IS its checked url".
- **deploy-title-url**: For a deploy row, `titleUrl` MUST be the row's `sourceUrl`, falling back to `liveUrl`, then `null`. The documented reasoning is "a deploy's title links to its deployment page".
- **endpoint-title-host**: For an endpoint row with a truthy `titleUrl`, `title` MUST be the host of `titleUrl`, via the host-extraction helper.
- **title-name-fallback**: For a deploy row, or an endpoint row whose `titleUrl` is null or empty, `title` MUST be the row's `name`.
- **platform-text**: `platformText` MUST be the row's `statusWord` followed by the literal text `" on "` followed by the platform name, when a platform name exists (for example `built on vercel`), and `null` otherwise. Endpoint rows and resolved rows therefore get `null`.
- **platform-link**: `platformLink` MUST be the row's `sourceUrl` when a platform name exists, and `null` otherwise. Only the specific deployment URL is stored, so "platform" links to the deployment page.

### The detail-building function: problem

- **problem-dedupe**: `problem` MUST be the row's `detail` when `detail` is truthy and differs from `message`. It MUST be `null` when `detail` is null, empty, or equal to `message`. Deploy-status issues set `detail` to the commit's first line, which the commit field already shows.
- **problem-link**: `problemLink` MUST be the row's `sourceUrl` when `problem` is non-null, and `null` otherwise.

### The detail-building function: diagnostics and commit

- **environment-passthrough**: `environment` MUST equal the row's `environment`.
- **status-code**: `statusCode` MUST equal the row's `statusCode`, or `null` when it is absent.
- **response-time-format**: `responseTime` MUST be the row's `responseTimeMs` followed by the literal text `"ms"` (for example `1200ms`) when `responseTimeMs` is neither null nor absent, and `null` otherwise. A value of `0` yields `0ms`.
- **branch**: `branch` MUST equal the row's `branch`, or `null` when it is absent.
- **since-precedence**: `since` MUST be the row's `downSince`, falling back to `at`, then `null`. The server-truth down-since wins so "the pane always shows WHEN, absolute".
- **last-checked**: `lastChecked` MUST equal the row's `lastCheckedAt`, or `null` when it is absent.
- **commit-fields**: `sha` MUST equal the row's `sha`, `commitSubject` MUST equal the row's `message`, and `commitUrl` MUST equal the row's `commitUrl`, each copied unchanged.
- **commit-body**: `commitBody` MUST equal the row's `commitBody`, or `null` when it is absent. It holds the full commit message, subject included.
- **error-text**: `errorText` MUST equal the row's `errorText` verbatim, or `null` when it is absent. It is the provider's build failure reason and may be multi-line.
- **status-word-as-given**: The status word used in `platformText` MUST be the row's `statusWord` unchanged. The function applies no client-side freshness demotion and takes no clock argument.

### The detail-building function: deploy outcome

- **deploy-outcome-failed**: `deployOutcome` MUST be `"failed"` when a platform name exists, the row's platform is not in the non-deploy platform set, and the row's tone is `"bad"`.
- **deploy-outcome-success**: `deployOutcome` MUST be `"success"` under the same conditions when the row's tone is `"good"`.
- **deploy-outcome-unsettled**: `deployOutcome` MUST be `null` when the row's tone is `"progress"`, `"neutral"` or `"stale"`. In-flight (progress) and canceled (neutral) rows stay null.
- **deploy-outcome-no-platform**: `deployOutcome` MUST be `null` for endpoint rows, resolved rows, and rows whose platform is null or empty.
- **non-deploy-platforms**: `deployOutcome` MUST be `null` when the row's platform is `"crunchy"` or `"glitchtip"`, whatever the tone. Rows on those platforms report database-cluster health or application errors mapped onto deploy phases, so a "build / deploy FAILED" headline would name an event that did not happen. The set is explicit because the platform name is truthy for every registered source.

### The serialization function

- **text-line-format**: Each emitted field MUST be one line of the form `<label>: <value>`, and lines MUST be joined with a single line feed and no trailing newline.
- **text-populated-only**: A field MUST be emitted only when its value is neither null, absent, nor the empty string. A numeric `0` is emitted.
- **text-field-order**: The labeled lines MUST appear in this order, each only when populated: `endpoint` (from `title`), `url` (from `titleUrl`), `environment`, `platform` (from `platformText`), `problem`, `http status` (from `statusCode`), `response` (from `responseTime`), `branch`, `since`, `last check` (from `lastChecked`), `commit`, `commit url`, `link`.
- **text-endpoint-label**: The `title` MUST be labeled `endpoint` for every row, deploy rows included.
- **text-url-distinct**: The `url` line MUST be emitted only when `titleUrl` is truthy and differs from `title`.
- **text-commit-line**: The `commit` line MUST be emitted when `sha` or `commitSubject` is truthy. Its value MUST be the truthy ones among `sha` and `commitSubject`, in that order, joined by one space.
- **text-link-precedence**: The `link` line MUST carry `platformLink`, falling back to `problemLink`, then `titleUrl`. The fallback treats only null or absent as missing, so an empty-string `platformLink` stops the chain and the line is omitted. This is documented as "where the actual build logs live".
- **text-error-block**: When `errorText` is truthy, the text MUST append an empty line, then the line `error:`, then `errorText` verbatim, after the labeled lines.
- **text-commit-body**: When `commitBody` is truthy and differs from `commitSubject`, the text MUST append an empty line and then `commitBody` verbatim, after the error block.
- **text-omits-fields**: The text MUST NOT include `deployOutcome` or `problemLink` as their own lines. `problemLink` appears only through the `link` fallback.

### Contract-wide

- **pure-functions**: Both functions MUST be synchronous and side-effect free. Each MUST return a new value and MUST NOT mutate its argument.
- **no-throw**: Neither function throws for a well-formed argument. The host-extraction helper catches URL parse failures and returns its input, so a malformed `liveUrl` becomes the title unchanged.
- **concurrency**: The functions MAY be called from any context. They hold no state and cannot interleave.
- **module-private-set**: The non-deploy platform set MUST stay private to this logic. It is not exposed externally and nothing mutates it.

## Appearance

Not applicable — this is a pure data-mapping and serialization module, not a visual component.

## States

Not applicable — this is a pure data-mapping and serialization module, not a visual component.

## Accessibility

Not applicable — this is a pure data-mapping and serialization module, not a visual component.

## Conformance Test Vectors

Vectors 001 to 013 are derived from the implementation's test suite (see Platform Notes). The rest are traced to the function bodies. The base row is the test helper's default: `platform: "vercel"`, `name: "adh"`, `environment: "production"`, `statusWord: "deployed"`, `tone: "good"`, `at: "2026-06-04T18:00:00.000Z"`, every other field null.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| row-detail-001 | deploy-title-url, title-name-fallback, platform-text, platform-link, commit-fields, commit-body, problem-dedupe | base row with `statusWord: "built"`, `sourceUrl: "https://vercel.com/team/adh/dpl"`, `liveUrl: "https://adh.app"`, `message: "fix login"`, `commitBody: "fix login\n\nlonger body"` | `title` `"adh"`, `titleUrl` and `platformLink` `"https://vercel.com/team/adh/dpl"`, `platformText` `"built on vercel"`, `commitSubject` `"fix login"`, `commitBody` unchanged, `problem` null |
| row-detail-002 | endpoint-title-host, endpoint-title-url, platform-text, problem-link | `platform: "http"`, `statusWord: "down"`, `detail: "HTTP 503"`, `liveUrl` and `sourceUrl` `"https://x.example.com/health"` | `title` `"x.example.com"`, `platformText` null, `problem` `"HTTP 503"`, `problemLink` `"https://x.example.com/health"` |
| row-detail-003 | resolved-classification, platform-text | `statusWord: "[deploy failed] resolved"` | `platformText` null |
| row-detail-004 | problem-dedupe | `detail: "fix login"`, `message: "fix login"` | `problem` null, `commitSubject` `"fix login"` |
| row-detail-005 | status-code, response-time-format, since-precedence, last-checked | endpoint row with `statusCode: 503`, `responseTimeMs: 1200`, `downSince: "2026-06-04T17:00:00.000Z"`, `lastCheckedAt: "2026-06-04T18:05:00.000Z"` | `statusCode` 503, `responseTime` `"1200ms"`, `since` `"2026-06-04T17:00:00.000Z"`, `lastChecked` `"2026-06-04T18:05:00.000Z"` |
| row-detail-006 | branch | `branch: "main"` | `branch` `"main"` |
| row-detail-007 | since-precedence, optional-fields-null | base row, no diagnostics | `since` `"2026-06-04T18:00:00.000Z"`; `statusCode`, `responseTime`, `branch`, `lastChecked`, `errorText` all null |
| row-detail-008 | error-text | `errorText: "[buildStep] next build exited 1"` | `errorText` unchanged |
| row-detail-009 | deploy-outcome-failed, deploy-outcome-success, deploy-outcome-unsettled | `tone` `"bad"`, `"good"`, `"progress"` on the base row | `"failed"`, `"success"`, null |
| row-detail-010 | deploy-outcome-no-platform, non-deploy-platforms | `platform: "http"`, `tone: "bad"`; `statusWord: "[deploy failed] resolved"`, `tone: "good"`; `platform: "crunchy"`, `statusWord: "suspended"`, `tone: "bad"` | `deployOutcome` null in all three |
| row-detail-011 | text-line-format, text-commit-line, text-link-precedence, text-commit-body | deploy row `statusWord: "build failed"`, `branch: "production"`, `sourceUrl: "https://vercel.com/team/olylo/dpl123"`, `sha: "9f952c9"`, `message: "restructure repo"`, `commitBody: "restructure repo\n\nlonger detail"`, passed through the detail-building function then the serialization function | text contains `platform: build failed on vercel`, `environment: production`, `branch: production`, `commit: 9f952c9 restructure repo`, `link: https://vercel.com/team/olylo/dpl123` and `longer detail` |
| row-detail-012 | text-populated-only | endpoint row `platform: "http"`, `statusWord: "down"`, no diagnostics, serialized | text contains none of `branch:`, `http status:`, `response:`, `error:` |
| row-detail-013 | text-error-block | `errorText` with two lines, serialized | text contains `\nerror:\n` followed by the first error line, and contains the second line |
| row-detail-014 | non-deploy-platforms, platform-text | `platform: "glitchtip"`, `statusWord: "new"`, `tone: "bad"` | `deployOutcome` null; `platformText` `"new on glitchtip"` |
| row-detail-015 | deploy-outcome-unsettled | base row with `tone: "stale"`, then `tone: "neutral"` | `deployOutcome` null for both |
| row-detail-016 | text-url-distinct, text-field-order | a row detail with `title: "x.example.com"`, `titleUrl: "https://x.example.com/health"`, other fields null | text is exactly `endpoint: x.example.com\nurl: https://x.example.com/health\nlink: https://x.example.com/health` |
| row-detail-017 | no-throw, endpoint-title-host, text-url-distinct | endpoint row with `liveUrl: "not a url"` | `title` `"not a url"` (from the host-extraction fallback); serialized text has no `url:` line |
| row-detail-018 | text-populated-only, response-time-format | `statusCode: 0`, `responseTimeMs: 0`, serialized | `responseTime` `"0ms"`; text contains `http status: 0` and `response: 0ms` |
| row-detail-019 | text-commit-line | a row detail with `sha: null`, `commitSubject: "fix"` | text contains `commit: fix` |
| row-detail-020 | text-commit-body | `commitSubject: "fix"`, `commitBody: "fix"` | text contains no empty line; the body is not repeated |
| row-detail-021 | pure-functions | call the detail-building function twice on one row | results are deep-equal, and the input row is unchanged |

## Edge Cases

- **Null platform**: A row with `platform: null` MUST be treated as a deploy row with no platform name. `platformText`, `platformLink` and `deployOutcome` MUST be null.
- **Empty platform string**: `platform: ""` MUST behave like null, because the platform-name test is a truthiness check.
- **Unknown platform**: A platform the platform label function does not know MUST still produce a platform name, its own key lower-cased (for example `fly-io`). A tone of `bad` or `good` then yields a deploy outcome.
- **Endpoint with no URL**: An endpoint row with both `liveUrl` and `sourceUrl` null MUST use the row's `name` as the title and `null` as `titleUrl`.
- **Empty-string URLs**: The title and link fallbacks treat only null or absent as missing, not empty strings. An empty `liveUrl` on an endpoint row MUST give `titleUrl` `""` and title equal to the row's `name`. The serializer then omits both the `url` and `link` lines.
- **Malformed endpoint URL**: A `liveUrl` that cannot be parsed as a URL MUST become the title unchanged. Because title and `titleUrl` are then equal, the `url` line MUST be omitted.
- **Empty `at`**: `at` is a required string. An empty `at` with no `downSince` MUST give `since` `""`, since the fallback does not skip an empty string. The serializer then omits the `since` line.
- **Empty detail**: `detail: ""` MUST give `problem` null and `problemLink` null.
- **Zero values**: `statusCode: 0` and `responseTimeMs: 0` MUST be kept. They appear as `0` and `0ms` in both the detail and the text.
- **Resolved deploy row**: A status word starting with `[` MUST suppress `platformText`, `platformLink` and `deployOutcome`, even when the tone is `good`.
- **Commit body equal to subject**: A `commitBody` equal to `commitSubject` MUST NOT be appended to the text.
- **Multi-line error text**: `errorText` MUST be emitted verbatim, including its internal newlines, with no escaping or truncation.
- **Error states, offline, timeouts, cancellation**: Not applicable. The logic performs no I/O, has no dependency that can fail, and cannot be cancelled or time out.
- **Concurrent calls**: Not applicable. The functions are pure and hold no shared state.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|--------------|
| input row | a row (see Status Row Model) | none (required) | The status-board row passed to the detail-building function. |
| input row detail | the row detail shape | none (required) | The detail passed to the serialization function. |
| non-deploy platform set | a fixed set of platform strings | `crunchy`, `glitchtip` | Platforms that never get a deploy outcome. Changing it requires a source edit. |
| platform label function | dependency | specified in Deploy Display | Supplies the platform name before lower-casing. |
| host-extraction function | dependency | see Platform Notes | Supplies the endpoint title from its URL. |

This logic reads no environment variables and no settings keys, and takes no other injected dependencies.

## Deep Linking

Not applicable: this logic maps data and defines no route or URL of its own. It only copies URLs the row already carries.

## Localization

The serializer's labels are hardcoded English and this logic has no localization layer. The copied text is meant for pasting into an LLM, and the labels are part of that format.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; hardcoded) | `endpoint` | Label for the row title |
| (none; hardcoded) | `url` | Label for the title URL |
| (none; hardcoded) | `environment` | Label for the environment |
| (none; hardcoded) | `platform` | Label for the platform phrase |
| (none; hardcoded) | `problem` | Label for the problem text |
| (none; hardcoded) | `http status` | Label for the last probe's HTTP status |
| (none; hardcoded) | `response` | Label for the last probe's latency |
| (none; hardcoded) | `branch` | Label for the deploy branch |
| (none; hardcoded) | `since` | Label for the onset time |
| (none; hardcoded) | `last check` | Label for the last probe time |
| (none; hardcoded) | `commit` | Label for the SHA and subject |
| (none; hardcoded) | `commit url` | Label for the commit URL |
| (none; hardcoded) | `link` | Label for the provider dashboard or logs link |
| (none; hardcoded) | `error:` | Header line of the error block |
| (none; hardcoded) | `{statusWord} on {platform}` | Platform phrase, for example `built on vercel` |

## Accessibility Options

Not applicable: this logic returns data and plaintext only, and responds to no display option.

## Feature Flags

Not applicable: this logic reads no flag, and every mapping is unconditional.

## Analytics

Not applicable: this logic emits no events.

## Privacy

Not applicable: this logic stores and transmits nothing. It copies commit messages, URLs and provider error text from the row into a string, and the caller owns what happens to that string.

## Logging

Not applicable: this logic has no logging calls and no failure path to log.

## Platform Notes

- **SwiftUI**: Port `RowDetail` as a `struct RowDetail: Sendable, Equatable` with optionals, and `deployOutcome` as `enum DeployOutcome: String, Sendable { case success, failed }?`. Write the two functions as a `static func` on `RowDetail` or as an initializer `RowDetail(row:)`. Use `URL(string:)?.host()` for `hostOf`, falling back to the raw string when it returns nil. Note that `URL.host` omits the port while the web `URL.host` includes it. Swift's `??` treats an empty string as a value, as JavaScript's does, but the truthiness checks (`row.detail && ...`, `d.titleUrl && ...`) become explicit `isEmpty` tests. Build the text with `[String]` and `joined(separator: "\n")`.
- **Compose**: Use a Kotlin `data class RowDetail` with nullable fields and an `enum class DeployOutcome`. Write the functions as top-level pure functions. Use `java.net.URI(url).host` in a `runCatching`, falling back to the input, and add the port to match the web behavior. Kotlin's `?:` matches `??`, and truthiness checks become `!isNullOrEmpty()`. Build the text with `buildList { }` and `joinToString("\n")`.
- **React/Web**: This is the source, `src/lib/row-detail.ts`, with tests in `src/lib/row-detail.test.ts` (Vitest). `ActivityPanel.tsx` and `ActivityDetails.tsx` call it. It relies on JavaScript truthiness (empty string, `0` and `null` are falsy) for the platform, problem, URL and commit tests, and on `??` for the fallbacks. It imports `hostOf` from `./url` and `platformLabel` from `./deploy-display`. A port must reproduce which test uses which.
- **AppKit / UIKit**: Use the same Swift value type and functions as the SwiftUI port. Nothing is UI-bound, so the code belongs in a shared framework target. The copy action writes the returned string to `NSPasteboard.general` or `UIPasteboard.general`.
- **WinUI 3**: Port `RowDetail` as a C# `public sealed record RowDetail` with nullable reference types (`string?`, `int?`) and `DeployOutcome?` as an `enum` with `JsonStringEnumConverter` if it is serialized with `System.Text.Json`. Write the functions as a `public static class RowDetailMapper` with `ToDetail(Row row)` and `ToText(RowDetail d)`. Use `Uri.TryCreate(url, UriKind.Absolute, out var u) ? u.Authority : url` for `hostOf`, because `Uri.Authority` includes a non-default port as the web `URL.host` does. C#'s `??` matches JavaScript's, but truthiness tests become `!string.IsNullOrEmpty(...)`, and the numeric `0` must stay emitted. Use `HashSet<string>` with `StringComparer.Ordinal` (or `FrozenSet`) for the non-deploy set. Build the text with `StringBuilder` or `string.Join("\n", lines)`, and never `Environment.NewLine`, because the source joins with `\n`. The functions are synchronous: no `Task`. A view model that exposes the selected row's detail raises `INotifyPropertyChanged` for its own property, and the copy button calls `DataPackage.SetText` then `Clipboard.SetContent`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/row-detail.ts` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [good-test-properties](agenticdevelopercookbook://compliance/best-practices#good-test-properties) | passed | best-practices |

**Separation of concerns.** The module only maps a `Row` to display fields and serializes them. Platform labels come from `deploy-display.ts`, host parsing comes from `url.ts`, and rendering and the clipboard write belong to the calling components.

**Unit test coverage.** `row-detail.test.ts` exercises both exports: the deploy and endpoint mappings, resolved rows, problem de-duplication, the diagnostics, the `since` fallback, error text, every settled and unsettled deploy outcome including the Crunchy carve-out, and the serializer's populated-only, link and error-block behavior. The GlitchTip carve-out, the `url` line and the empty-string fallbacks are not asserted directly.

**Explicit error handling.** The only failure path is URL parsing inside `hostOf`, which falls back to the raw input by design. Every other input maps to a defined value.

**Good test properties.** The tests build rows from one `row()` helper with explicit overrides, assert observable fields, and depend on no clock, network or shared state.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/logic/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from source |
