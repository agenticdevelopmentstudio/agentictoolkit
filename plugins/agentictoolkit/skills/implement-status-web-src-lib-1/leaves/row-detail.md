<!-- leaf: implement-status-web-src-lib-1/row-detail · source: status-web-src-lib-row-detail.md -->

**Rules** (cite as `implement-status-web-src-lib-1/row-detail#<slug>`):

- `row-input-shape` MUST
- `row-detail-shape` MUST
- `optional-fields-null` MUST
- `endpoint-classification` MUST
- `resolved-classification` MUST
- `platform-name` MUST
- `endpoint-title-url` MUST
- `deploy-title-url` MUST
- `endpoint-title-host` MUST
- `title-name-fallback` MUST
- `platform-text` MUST
- `platform-link` MUST
- `problem-dedupe` MUST
- `problem-link` MUST
- `environment-passthrough` MUST
- `status-code` MUST
- `response-time-format` MUST
- `branch` MUST
- `since-precedence` MUST
- `last-checked` MUST
- `commit-fields` MUST
- `commit-body` MUST
- `error-text` MUST
- `status-word-as-given` MUST
- `deploy-outcome-failed` MUST
- `deploy-outcome-success` MUST
- `deploy-outcome-unsettled` MUST
- `deploy-outcome-no-platform` MUST
- `non-deploy-platforms` MUST
- `text-line-format` MUST
- `text-populated-only` MUST
- `text-field-order` MUST
- `text-endpoint-label` MUST
- `text-url-distinct` MUST
- `text-commit-line` MUST
- `text-link-precedence` MUST
- `text-error-block` MUST
- `text-commit-body` MUST
- `text-omits-fields` MUST
- `pure-functions` MUST
- `concurrency` MAY
- `module-private-set` MUST

# Row Detail

## Overview

`row-detail.ts` (`packages/web/packages/status-web/src/lib/row-detail.ts`) turns one status-board `Row` (from `./row-model`) into the fields the details pane shows for a selected row, and turns those fields into plaintext for the pane's "copy" button. Its callers are `ActivityPanel.tsx` and `ActivityDetails.tsx`.

It exports one type and two pure functions:

- `RowDetail` is the interface of labeled, nullable fields the details pane renders.
- `rowToDetailProps(row: Row): RowDetail` maps a row to those fields. Its doc comment says it "mirrors StatusRow's link derivations so the row and the details pane always agree on titles/links", and it renders the status word exactly as the server sent it.
- `rowDetailToText(d: RowDetail): string` serializes a `RowDetail` to "a clean, labeled plaintext block" so "the whole problem ... can be pasted straight into an LLM without opening the provider dashboard".

The module imports `hostOf` from `./url`, which returns `new URL(url).host` or the input unchanged when parsing throws. It also imports `platformLabel` from `./deploy-display`, specified in Deploy Display. It has no state, no I/O and no side effects.

## Behavioral Requirements

### Data shapes

- **row-input-shape**: `rowToDetailProps` MUST accept a `Row` with these fields as `row-model.ts` names them: `key`, `source`, `platform` (`string | null`), `name`, `environment` (`string | null`), `statusWord`, `tone` (`RowTone`: `"good" | "bad" | "progress" | "neutral" | "stale"`), `sha`, `commitUrl`, `message`, `detail`, `at` (ISO string), `sourceUrl`, `liveUrl`, plus the optional `commitBody`, `statusCode`, `responseTimeMs`, `lastCheckedAt`, `downSince`, `branch` and `errorText`.
- **row-detail-shape**: `RowDetail` MUST hold exactly these fields: `title: string`, and the nullable `titleUrl`, `environment`, `platformText`, `platformLink`, `problem`, `problemLink`, `statusCode` (`number | null`), `responseTime`, `branch`, `since`, `lastChecked`, `sha`, `commitSubject`, `commitUrl`, `commitBody`, `errorText`, and `deployOutcome` (`"success" | "failed" | null`).
- **optional-fields-null**: Every optional `Row` field that is `undefined` MUST become `null` in the `RowDetail`. This covers `statusCode`, `branch`, `lastChecked`, `commitBody` and `errorText`, each mapped with `?? null`.

### rowToDetailProps: row classification

- **endpoint-classification**: A row MUST be treated as an endpoint row when `row.platform` is exactly `"http"` or `"dns"`, and as a deploy row otherwise.
- **resolved-classification**: A row MUST be treated as resolved when `row.statusWord` starts with the character `[`, as in `"[deploy failed] resolved"`.
- **platform-name**: The platform name MUST be `platformLabel(row.platform).toLowerCase()` when the row is not an endpoint, `row.platform` is truthy and the row is not resolved. Otherwise it MUST be absent. For example, `vercel` yields `vercel` and `cloudflare-pages` yields `cloudflare`.

### rowToDetailProps: title and links

- **endpoint-title-url**: For an endpoint row, `titleUrl` MUST be `row.liveUrl`, falling back to `row.sourceUrl`, then `null`. The source comment says "an endpoint IS its checked url".
- **deploy-title-url**: For a deploy row, `titleUrl` MUST be `row.sourceUrl`, falling back to `row.liveUrl`, then `null`. The source comment says "a deploy's title links to its deployment page".
- **endpoint-title-host**: For an endpoint row with a truthy `titleUrl`, `title` MUST be `hostOf(titleUrl)`, the URL's host.
- **title-name-fallback**: For a deploy row, or an endpoint row whose `titleUrl` is null or empty, `title` MUST be `row.name`.
- **platform-text**: `platformText` MUST be `` `${row.statusWord} on ${platformName}` `` when a platform name exists (for example `built on vercel`), and `null` otherwise. Endpoint rows and resolved rows therefore get `null`.
- **platform-link**: `platformLink` MUST be `row.sourceUrl` when a platform name exists, and `null` otherwise. The source comment says only the specific deployment URL is stored, so "platform" links to the deployment page.

### rowToDetailProps: problem

- **problem-dedupe**: `problem` MUST be `row.detail` when `row.detail` is truthy and differs from `row.message`. It MUST be `null` when `row.detail` is null, empty, or equal to `row.message`. The source comment says deploy-status issues set `detail` to the commit's first line, which the commit field already shows.
- **problem-link**: `problemLink` MUST be `row.sourceUrl` when `problem` is non-null, and `null` otherwise.

### rowToDetailProps: diagnostics and commit

- **environment-passthrough**: `environment` MUST equal `row.environment`.
- **status-code**: `statusCode` MUST equal `row.statusCode`, or `null` when it is absent.
- **response-time-format**: `responseTime` MUST be `` `${row.responseTimeMs}ms` `` (for example `1200ms`) when `row.responseTimeMs` is neither `null` nor `undefined`, and `null` otherwise. A value of `0` yields `0ms`.
- **branch**: `branch` MUST equal `row.branch`, or `null` when it is absent.
- **since-precedence**: `since` MUST be `row.downSince`, falling back to `row.at`, then `null`. The source comment says the server-truth down-since wins so "the pane always shows WHEN, absolute".
- **last-checked**: `lastChecked` MUST equal `row.lastCheckedAt`, or `null` when it is absent.
- **commit-fields**: `sha` MUST equal `row.sha`, `commitSubject` MUST equal `row.message`, and `commitUrl` MUST equal `row.commitUrl`, each copied unchanged.
- **commit-body**: `commitBody` MUST equal `row.commitBody`, or `null` when it is absent. It holds the full commit message, subject included.
- **error-text**: `errorText` MUST equal `row.errorText` verbatim, or `null` when it is absent. It is the provider's build failure reason and may be multi-line.
- **status-word-as-given**: The status word used in `platformText` MUST be `row.statusWord` unchanged. The function applies no client-side freshness demotion and takes no clock argument.

### rowToDetailProps: deploy outcome

- **deploy-outcome-failed**: `deployOutcome` MUST be `"failed"` when a platform name exists, `row.platform` is not in the non-deploy set, and `row.tone` is `"bad"`.
- **deploy-outcome-success**: `deployOutcome` MUST be `"success"` under the same conditions when `row.tone` is `"good"`.
- **deploy-outcome-unsettled**: `deployOutcome` MUST be `null` when `row.tone` is `"progress"`, `"neutral"` or `"stale"`. The source comment says in-flight (progress) and canceled (neutral) rows stay null.
- **deploy-outcome-no-platform**: `deployOutcome` MUST be `null` for endpoint rows, resolved rows, and rows whose `platform` is null or empty.
- **non-deploy-platforms**: `deployOutcome` MUST be `null` when `row.platform` is `"crunchy"` or `"glitchtip"`, whatever the tone. The source comment says Crunchy rows are database-cluster health mapped onto deploy phases and GlitchTip rows are application errors, so a "build / deploy FAILED" headline would name an event that did not happen. The set is explicit because the platform name is truthy for every registered source.

### rowDetailToText

- **text-line-format**: Each emitted field MUST be one line of the form `<label>: <value>`, and lines MUST be joined with a single `\n` and no trailing newline.
- **text-populated-only**: A field MUST be emitted only when its value is neither `null`, `undefined` nor the empty string. A numeric `0` is emitted.
- **text-field-order**: The labeled lines MUST appear in this order, each only when populated: `endpoint` (from `title`), `url` (from `titleUrl`), `environment`, `platform` (from `platformText`), `problem`, `http status` (from `statusCode`), `response` (from `responseTime`), `branch`, `since`, `last check` (from `lastChecked`), `commit`, `commit url`, `link`.
- **text-endpoint-label**: The `title` MUST be labeled `endpoint` for every row, deploy rows included.
- **text-url-distinct**: The `url` line MUST be emitted only when `titleUrl` is truthy and differs from `title`.
- **text-commit-line**: The `commit` line MUST be emitted when `sha` or `commitSubject` is truthy. Its value MUST be the truthy ones among `sha` and `commitSubject`, in that order, joined by one space.
- **text-link-precedence**: The `link` line MUST carry `platformLink`, falling back to `problemLink`, then `titleUrl`. The fallback uses `??`, so an empty-string `platformLink` stops the chain and the line is omitted. The source comment says this is "where the actual build logs live".
- **text-error-block**: When `errorText` is truthy, the text MUST append an empty line, then the line `error:`, then `errorText` verbatim, after the labeled lines.
- **text-commit-body**: When `commitBody` is truthy and differs from `commitSubject`, the text MUST append an empty line and then `commitBody` verbatim, after the error block.
- **text-omits-fields**: The text MUST NOT include `deployOutcome` or `problemLink` as their own lines. `problemLink` appears only through the `link` fallback.

### Contract-wide

- **pure-functions**: Both functions MUST be synchronous and side-effect free. Each MUST return a new value and MUST NOT mutate its argument.
- **no-throw**: Neither function throws for a well-typed argument. `hostOf` catches URL parse failures and returns its input, so a malformed `liveUrl` becomes the title unchanged.
- **concurrency**: The functions MAY be called from any context. They run on the single JavaScript thread, hold no state and cannot interleave.
- **module-private-set**: The non-deploy set (`NON_DEPLOY_PLATFORMS`) MUST stay module-private. It is not exported and nothing mutates it.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `row` | `Row` | none (required) | The status-board row passed to `rowToDetailProps`. |
| `d` | `RowDetail` | none (required) | The detail passed to `rowDetailToText`. |
| `NON_DEPLOY_PLATFORMS` | `Set<string>` (module constant) | `crunchy`, `glitchtip` | Platforms that never get a deploy outcome. Changing it is a source edit. |
| `platformLabel` | imported function | from `./deploy-display` | Supplies the platform name before lower-casing. |
| `hostOf` | imported function | from `./url` | Supplies the endpoint title from its URL. |

The module reads no environment variables and no settings keys, and takes no injected dependencies.

