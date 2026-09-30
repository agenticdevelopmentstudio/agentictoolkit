<!-- leaf: implement-status-web-src-lib-1/deploy-display · source: status-web-src-lib-deploy-display.md -->

**Rules** (cite as `implement-status-web-src-lib-1/deploy-display#<slug>`):

- `platform-key-vocabulary` MUST
- `platform-input-type` MUST
- `glyph-signature` MUST
- `glyph-vercel` MUST
- `glyph-cloudflare` MUST
- `glyph-railway` MUST
- `glyph-http` MUST
- `glyph-dns` MUST
- `glyph-crunchy` MUST
- `glyph-glitchtip-text-presentation` MUST
- `glyph-fallback` MUST
- `color-signature` MUST
- `color-vercel` MUST
- `color-cloudflare` MUST
- `color-railway` MUST
- `color-http` MUST
- `color-dns` MUST
- `color-crunchy-shares-http` MUST
- `color-glitchtip-shares-cloudflare` MUST
- `color-fallback` MUST
- `color-env-hue-exclusion` MUST
- `color-theme-tokens-only` MUST
- `label-signature` MUST
- `label-table` MUST
- `label-fallback-uppercase` MUST
- `short-label-signature` MUST
- `short-label-overrides` MUST
- `short-label-fallback` MUST
- `status-color-signature` MUST
- `status-color-lookup` MUST
- `status-color-unknown-muted` MUST
- `status-color-fallback` MUST
- `status-color-token-not-hex` MUST
- `status-label-signature` MUST
- `status-label-success` MUST
- `status-label-failed-uppercase` MUST
- `status-label-in-flight` MUST
- `status-label-canceled` MUST
- `status-label-unknown` MUST
- `status-label-passthrough` MUST
- `pure-functions` MUST
- `no-mutation` MUST
- `concurrency` MAY

# Deploy Display

## Overview

`deploy-display.ts` (`packages/web/packages/status-web/src/lib/deploy-display.ts`) is the status dashboard's platform taxonomy. Its header comment states its purpose: "glyph, brand color, and badge label for each deploy platform (plus the http/dns health checks). One module owns 'what a platform looks like', so adding a platform is a single edit here."

It exports six pure functions:

- `platformGlyph(platform)` returns a Unicode glyph.
- `platformColor(platform)` returns a CSS color expression that references a theme token.
- `platformLabel(platform)` returns an upper-case badge label.
- `platformLabelShort(platform)` returns a compact label for dense strips.
- `deployStatusColor(status)` returns the color for a deploy status dot or label.
- `deployStatusLabel(status)` returns a short text label for a deploy status.

The module has no state, no I/O and no side effects. It imports the `DeployStatus` type from `./deploy-status` and the `DEPLOY_COLORS` map from `./colors`. The callers are dashboard components (`DeployList`, `StatusMatrix`, `StatusRow`, `KpiStrip`, `GlobalPanel`, `UnconfiguredProjectsBanner`, `AutoConfigureReview`, `configure/ProjectBrowser`, `configure/PlatformProjects`) and `row-detail.ts`. They render the returned strings and never branch on them. The server-side status vocabulary is specified in Monitor Deploy Status.

## Behavioral Requirements

### Platform keys

- **platform-key-vocabulary**: The module MUST recognise these platform keys, compared by exact, case-sensitive string equality: `vercel`, `cloudflare-pages`, `railway`, `http`, `dns`, `crunchy`, `glitchtip`. `http` and `dns` are health checks, not hosting platforms. `crunchy` is a database, and `glitchtip` stands for thrown errors.
- **platform-input-type**: Every platform function MUST accept any `string` and MUST NOT throw for any string input.

### platformGlyph

- **glyph-signature**: `platformGlyph(platform: string)` MUST return a `string`.
- **glyph-vercel**: `platformGlyph` MUST return `▲` (U+25B2) for `vercel`.
- **glyph-cloudflare**: `platformGlyph` MUST return `☁` (U+2601) for `cloudflare-pages`.
- **glyph-railway**: `platformGlyph` MUST return `⬢` (U+2B22) for `railway`.
- **glyph-http**: `platformGlyph` MUST return `◉` (U+25C9) for `http`.
- **glyph-dns**: `platformGlyph` MUST return `⌖` (U+2316) for `dns`.
- **glyph-crunchy**: `platformGlyph` MUST return `⛁` (U+26C1) for `crunchy`.
- **glyph-glitchtip-text-presentation**: `platformGlyph` MUST return the two-code-point string U+26A0 U+FE0E for `glitchtip`. The source comment says the bare warning sign has an emoji presentation by default on macOS and iOS, so it would render full-colour and double-width beside six monochrome glyphs. VARIATION SELECTOR-15 forces the text form.
- **glyph-fallback**: `platformGlyph` MUST return `◆` (U+25C6) for every other string, including the empty string.

### platformColor

- **color-signature**: `platformColor(platform: string)` MUST return a `string` holding a CSS color expression.
- **color-vercel**: `platformColor` MUST return `var(--color-apt-text)` for `vercel`. The source comment calls this the brand near-white.
- **color-cloudflare**: `platformColor` MUST return `var(--color-apt-cat-orange)` for `cloudflare-pages`.
- **color-railway**: `platformColor` MUST return `var(--color-apt-cat-purple)` for `railway`.
- **color-http**: `platformColor` MUST return `var(--color-apt-cat-teal)` for `http`.
- **color-dns**: `platformColor` MUST return `var(--color-apt-cat-indigo)` for `dns`.
- **color-crunchy-shares-http**: `platformColor` MUST return `var(--color-apt-cat-teal)` for `crunchy`, the same value as `http`.
- **color-glitchtip-shares-cloudflare**: `platformColor` MUST return `var(--color-apt-cat-orange)` for `glitchtip`, the same value as `cloudflare-pages`.
- **color-fallback**: `platformColor` MUST return `var(--color-apt-text-muted)` for any platform with no own entry in the color map.
- **color-env-hue-exclusion**: A platform color MUST NOT equal an environment hue. The environment hues in `ENV_COLORS` are `var(--color-apt-cat-blue)`, `var(--color-apt-cat-violet)` and `var(--color-apt-cat-pink)`. The source comment gives the reason: a row that shows both an env badge and a platform badge must read unambiguously.
- **color-theme-tokens-only**: Every returned platform color MUST be a `var(--color-apt-*)` theme-token reference, never a literal hex value. The token values are owned by the shared theme package.

### platformLabel

- **label-signature**: `platformLabel(platform: string)` MUST return a `string`.
- **label-table**: `platformLabel` MUST return `VERCEL` for `vercel`, `CLOUDFLARE` for `cloudflare-pages`, `RAILWAY` for `railway`, `HTTP` for `http`, `DNS` for `dns` and `CRUNCHY` for `crunchy`.
- **label-fallback-uppercase**: `platformLabel` MUST return `platform.toUpperCase()` for any platform with no own entry in the label map. This includes `glitchtip`, which has no label entry and so yields `GLITCHTIP`.

### platformLabelShort

- **short-label-signature**: `platformLabelShort(platform: string)` MUST return a `string`.
- **short-label-overrides**: `platformLabelShort` MUST return `CF` for `cloudflare-pages` and `CB` for `crunchy`.
- **short-label-fallback**: `platformLabelShort` MUST return `platformLabel(platform)` for every platform with no short override. For example, it returns `VERCEL` for `vercel`.

### deployStatusColor

- **status-color-signature**: `deployStatusColor(status: DeployStatus | string)` MUST return a `string`. `DeployStatus` is `"success" | "failed" | "building" | "queued" | "canceled" | "unknown"`.
- **status-color-lookup**: `deployStatusColor` MUST return `DEPLOY_COLORS[status]` when that entry exists. The values are `success` → `var(--color-apt-green)`, `failed` → `var(--color-apt-red)`, `building`/`queued`/`canceled` → `var(--color-apt-gold)`, and `unknown` → `var(--color-apt-text-muted)`.
- **status-color-unknown-muted**: `deployStatusColor("unknown")` MUST return the muted token, not the amber used for live progress. The `DEPLOY_COLORS` comment says `unknown` is "an ABSENCE of a verdict".
- **status-color-fallback**: `deployStatusColor` MUST return `DEPLOY_COLORS["canceled"]` (`var(--color-apt-gold)`) for any status string that is not a key of `DEPLOY_COLORS`. An unrecognised status therefore renders amber, not muted.
- **status-color-token-not-hex**: `deployStatusColor` MUST return a theme-token expression. Its doc comment says "CSS hex color", but `DEPLOY_COLORS` holds only `var(--color-apt-*)` references, so the doc comment is stale.

### deployStatusLabel

- **status-label-signature**: `deployStatusLabel(status: DeployStatus | string)` MUST return a `string`.
- **status-label-success**: `deployStatusLabel` MUST return `ready` for `success`.
- **status-label-failed-uppercase**: `deployStatusLabel` MUST return `FAILED`, in upper case, for `failed`. It is the only upper-case status label.
- **status-label-in-flight**: `deployStatusLabel` MUST return `building` for `building` and `queued` for `queued`.
- **status-label-canceled**: `deployStatusLabel` MUST return `canceled` for `canceled`.
- **status-label-unknown**: `deployStatusLabel` MUST return `outcome unknown` for `unknown`. The source comment says `unknown` is an in-flight phase the backend expired without confirmation, and the label must say so rather than echo the raw enum.
- **status-label-passthrough**: `deployStatusLabel` MUST return the input string unchanged for any other status.

### Contract-wide

- **pure-functions**: Every export MUST be a synchronous, side-effect-free function whose result depends only on its argument and the module's constant maps.
- **no-mutation**: The module MUST NOT expose its lookup maps (`PLATFORM_COLOR`, `PLATFORM_LABEL`, `PLATFORM_LABEL_SHORT`). They are module-private constants, and no function mutates them.
- **concurrency**: The functions MAY be called from any context. They run on the single JavaScript thread, hold no state and cannot interleave.
- **prototype-key-lookup**: `platformColor`, `platformLabel`, `platformLabelShort` and `deployStatusColor` index plain object literals and fall back only on `null`/`undefined` (`??`), so an inherited key such as `constructor` or `toString` returns the inherited value (a function) instead of a string. The parameters are typed `string`, and nothing in the package passes such a key or tests one. A port using a real dictionary or an own-property check returns the fallback instead, which is the intended behavior.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `platform` | `string` | none (required) | Platform or check key passed to the four platform functions. Unknown keys fall back as described above. |
| `status` | `DeployStatus \| string` | none (required) | Deploy status passed to `deployStatusColor` and `deployStatusLabel`. |
| `DEPLOY_COLORS` | `Record<string, string>` (imported from `./colors`) | theme-token map | Supplies the status colors. The fallback for unrecognised statuses is its `canceled` entry. |
| `--color-apt-*` CSS custom properties | theme tokens | owned by the shared theme package | The returned strings resolve only where the theme stylesheet defines these properties. |

The module reads no environment variables and no settings keys, and takes no injected dependencies.

## Localization

The module returns hardcoded English strings and has no localization layer. These are facts of the source, not gaps.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `deployStatusLabel.success` | `ready` | Status label for a successful deploy |
| `deployStatusLabel.failed` | `FAILED` | Status label for a failed deploy (upper case for emphasis) |
| `deployStatusLabel.building` | `building` | Status label while building or deploying |
| `deployStatusLabel.queued` | `queued` | Status label for a queued build |
| `deployStatusLabel.canceled` | `canceled` | Status label for a canceled build |
| `deployStatusLabel.unknown` | `outcome unknown` | Status label for an in-flight phase the backend expired without confirmation |
| `platformLabel.*` | `VERCEL`, `CLOUDFLARE`, `RAILWAY`, `HTTP`, `DNS`, `CRUNCHY` | Brand and check names. These are proper nouns and are not translated. |
| `platformLabelShort.*` | `CF`, `CB` | Compact brand abbreviations for dense strips |

The upper-case fallback uses `String.prototype.toUpperCase()`, which is locale-independent.

