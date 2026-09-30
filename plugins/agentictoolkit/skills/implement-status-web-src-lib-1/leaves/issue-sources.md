<!-- leaf: implement-status-web-src-lib-1/issue-sources · source: status-web-src-lib-issue-sources.md -->

**Rules** (cite as `implement-status-web-src-lib-1/issue-sources#<slug>`):

- `source-union` MUST
- `source-spelling` MUST
- `source-glitchtip-separate` MUST
- `label-map-total` MUST
- `label-values` MUST
- `label-non-empty` MUST
- `label-unguarded-index` MUST
- `order-members` MUST
- `order-canonical` MUST
- `order-mutable-type` MUST
- `guard-signature` MUST
- `guard-true` MUST
- `guard-false` MUST
- `guard-no-normalization` MUST
- `guard-no-throw` MUST
- `guard-order-source` MUST
- `stuck-threshold-value` MUST
- `stuck-threshold-mirror` MUST
- `stuck-not-client-derived` MUST
- `queued-never-stuck` MUST
- `platform-debounce-server-side` MUST
- `mirror-union` MUST
- `mirror-labels` MUST
- `mirror-order` MUST
- `mirror-hand-synced` MUST
- `pure-module` MUST

# Issue Sources

## Overview

`issue-sources.ts` (`packages/web/packages/status-web/src/lib/issue-sources.ts`) declares where a status-board row or Problem came from: DNS resolution, the HTTP probe, the GlitchTip error tracker, or one of four deploy providers. Its doc comment explains why `glitchtip` is a separate source: "the other sources answer 'is the thing reachable', it answers 'is the thing THROWING'".

It exports five things:

- `IssueSource`, a string-literal union of the seven source identifiers.
- `SOURCE_LABEL`, a `Record<IssueSource, string>` of display labels for the source filter and badges.
- `ISSUE_SOURCES`, an `IssueSource[]` giving the canonical order for the source filter UI.
- `isIssueSource(s)`, a type guard that narrows a raw platform or source string to `IssueSource`.
- `STUCK_DEPLOY_MS`, the number of milliseconds a build may sit BUILDING before the backend counts it as stuck.

The module is a client-side MIRROR of `status-server/src/monitor/issue-sources.ts`: "same union, same labels, same order". The server file also holds the judgment functions (`httpIsBad`, `deployIsBad`, `deployIsStuck`, `nextPlatformStreak` and others). The client copies only the vocabulary and the threshold constant. It has no state, no I/O and no side effects.

Consumers in status-web: `hooks/use-source-filter.ts` seeds its selection from `ISSUE_SOURCES` (useSourceFilter); `lib/board-types.ts` types board rows with `IssueSource` (Board Types); `lib/row-model.ts`, `components/ActivityPanel.tsx`, `components/OverviewTab.tsx` and `components/GlobalPanel.tsx` read the labels, order and guard.

## Behavioral Requirements

### IssueSource

- **source-union**: `IssueSource` MUST be exactly the union `"dns" | "http" | "glitchtip" | "vercel" | "cloudflare-pages" | "railway" | "crunchy"`.
- **source-spelling**: The Cloudflare source MUST be spelled `"cloudflare-pages"`, not `"cloudflare"`. A row whose source is `"cloudflare"` is not an `IssueSource`.
- **source-glitchtip-separate**: `glitchtip` MUST be a distinct member from `http`, so an error-tracker Problem can be open on a site that every probe reports as up. The doc comment calls carrying it here "rather than folding it into `http`" the whole point.

### SOURCE_LABEL

- **label-map-total**: `SOURCE_LABEL` MUST have exactly one entry for every `IssueSource` member and no other keys. Its `Record<IssueSource, string>` type makes a missing key a type error.
- **label-values**: `SOURCE_LABEL` MUST map `dns` to `"DNS"`, `http` to `"HTTP"`, `glitchtip` to `"GlitchTip"`, `vercel` to `"Vercel"`, `cloudflare-pages` to `"Cloudflare"`, `railway` to `"Railway"` and `crunchy` to `"Crunchy Bridge"`.
- **label-non-empty**: Every value in `SOURCE_LABEL` MUST be a non-empty string.
- **label-unguarded-index**: Indexing `SOURCE_LABEL` with a string that is not an `IssueSource` MUST yield `undefined` at runtime. The module does not supply a fallback label; the doc comment warns that such a source "renders `undefined` in the filter and the badge". Callers holding a plain string narrow it with `isIssueSource` first (`row-model.ts` falls back to the raw string when the guard fails).

### ISSUE_SOURCES

- **order-members**: `ISSUE_SOURCES` MUST contain each `IssueSource` member exactly once, seven entries in all.
- **order-canonical**: `ISSUE_SOURCES` MUST list the sources in the order `dns`, `http`, `glitchtip`, `vercel`, `cloudflare-pages`, `railway`, `crunchy`. Consumers render filter checkboxes and group lists by filtering this array, so this order is the display order.
- **order-mutable-type**: `ISSUE_SOURCES` MUST be typed `IssueSource[]`, a mutable array, not a readonly tuple. The module never mutates it. Nothing in the type system ties its members to the union, so a member missing from `ISSUE_SOURCES` would still compile.

### isIssueSource

- **guard-signature**: `isIssueSource` MUST take one argument `s: string` and MUST return a `boolean` that the type system treats as the predicate `s is IssueSource`.
- **guard-true**: `isIssueSource` MUST return `true` when `s` is exactly equal (strict comparison, as `Array.prototype.includes` does for strings) to a member of `ISSUE_SOURCES`.
- **guard-false**: `isIssueSource` MUST return `false` for every other string, including the empty string, a member with different casing (`"DNS"`), a member with surrounding whitespace, and the integration spelling `"cloudflare"`.
- **guard-no-normalization**: `isIssueSource` MUST NOT trim, lowercase or otherwise normalize `s` before comparing. (The server's separate `platformHealthSource` trims and lowercases, and maps `"cloudflare"` to `"cloudflare-pages"`; this client guard does neither.)
- **guard-no-throw**: `isIssueSource` MUST NOT throw for any string argument.
- **guard-order-source**: `isIssueSource` MUST decide membership from `ISSUE_SOURCES`, so the guard and the filter order agree by construction.

### STUCK_DEPLOY_MS

- **stuck-threshold-value**: `STUCK_DEPLOY_MS` MUST equal `1800000` (30 × 60 × 1000, thirty minutes).
- **stuck-threshold-mirror**: `STUCK_DEPLOY_MS` MUST equal the server's `STUCK_DEPLOY_MS` in `status-server/src/monitor/issue-sources.ts`, which drives the backend's stuck issues and alerts.
- **stuck-not-client-derived**: The client MUST NOT derive stuck Problems from `STUCK_DEPLOY_MS`. The doc comment records this as an owner call dated 2026-07-10: an in-flight `building` row is activity, never a Problem. No module in status-web reads the constant.
- **queued-never-stuck**: A `queued` deploy MUST NOT count as stuck at any age. The doc comment gives the reason: "a long queue is almost always an INTENTIONAL hold, not a wedge".
- **platform-debounce-server-side**: The client MUST NOT implement the platform-unreachable debounce. The module's closing note says the debounce lives server-side (`applyPlatformIssues` and the `platform_health_state` table) and reaches the board as a `platform-health|<source>` Problem, which the client renders directly with no client-side streak or threshold.

### Mirror contract

- **mirror-union**: The client `IssueSource` union MUST contain the same members as the server's `IssueSource`.
- **mirror-labels**: The client `SOURCE_LABEL` MUST hold the same key-to-label pairs as the server's `SOURCE_LABEL`.
- **mirror-order**: The client `ISSUE_SOURCES` MUST list the same members in the same order as the server's `ISSUE_SOURCES`.
- **mirror-hand-synced**: The two files restate the vocabulary rather than share it. Both doc comments name the other file; no import, generated code or parity test ties them together. A port MUST keep both sides in step when a source is added.
- **mirror-client-extras**: `isIssueSource` exists only on the client side. The server file has no equivalent guard.

### Purity and concurrency

- **pure-module**: The module MUST have no side effects on import and MUST perform no I/O.
- **single-threaded**: The module runs on the single JavaScript thread and never mutates its exports, so calls cannot interleave and it needs no ordering rule.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ISSUE_SOURCES` | `IssueSource[]` | `["dns", "http", "glitchtip", "vercel", "cloudflare-pages", "railway", "crunchy"]` | Compiled-in vocabulary and filter order. Changing it means editing this file and the server mirror. |
| `SOURCE_LABEL` | `Record<IssueSource, string>` | the seven labels listed under label-values | Compiled-in display labels. |
| `STUCK_DEPLOY_MS` | `number` | `1800000` | Compiled-in mirror of the server's stuck-build threshold. |
| `s` (argument to `isIssueSource`) | `string` | none (required) | The candidate source or platform string to test. |

The module reads no environment variables and no settings keys, imports nothing, and takes no injected dependencies.

## Localization

The labels are hardcoded English (brand and protocol names) with no localization keys. They are shown in the source filter and on badges.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `SOURCE_LABEL.dns` | DNS | Source filter checkbox and badge for DNS-resolution rows |
| `SOURCE_LABEL.http` | HTTP | Source filter checkbox and badge for HTTP-probe rows |
| `SOURCE_LABEL.glitchtip` | GlitchTip | Source filter checkbox and badge for error-tracker rows |
| `SOURCE_LABEL.vercel` | Vercel | Source filter checkbox and badge for Vercel deploy rows |
| `SOURCE_LABEL.cloudflare-pages` | Cloudflare | Source filter checkbox and badge for Cloudflare Pages deploy rows |
| `SOURCE_LABEL.railway` | Railway | Source filter checkbox and badge for Railway deploy rows |
| `SOURCE_LABEL.crunchy` | Crunchy Bridge | Source filter checkbox and badge for Crunchy Bridge database rows |

