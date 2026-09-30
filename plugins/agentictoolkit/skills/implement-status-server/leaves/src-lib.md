<!-- leaf: implement-status-server/src-lib · source: status-server-src-lib.md -->

**Rules** (cite as `implement-status-server/src-lib#<slug>`):

- `live-url-normalization` MUST
- `live-url-idempotent` MUST
- `dashboard-url-vercel` MUST
- `dashboard-url-railway` MUST
- `dashboard-url-cloudflare` MUST
- `dashboard-url-platform-canonicalization` MUST
- `dashboard-url-unknown-platform` MUST
- `dashboard-url-project-name-required` MUST
- `project-name-url-encoding` MUST
- `site-links-production-endpoint` MUST
- `site-links-live-url` MUST
- `site-links-platform-dashboard` MUST
- `default-meta-parameter` MUST

# status-server-src-lib

## Overview

Generates canonical deep links for monitored sites and deploy projects. The module derives two classes of links: the production live URL (for accessing the running site) and the platform-specific hosting dashboard URL (for administrative access). Links are derived from real configuration only — the module never constructs plausible-looking but unverified URLs.

## Behavioral Requirements

- **platform-meta-interface**: The module exports `PlatformMeta` interface carrying optional platform-specific identifiers (`railwayProjectId`, `vercelTeamId`, `cloudflareAccountId`) needed to construct dashboard URLs; all fields are nullable.
- **site-links-interface**: The module exports `SiteLinks` interface with `live` and `platform` fields, both nullable strings representing absolute URLs.
- **live-url-normalization**: `liveUrl()` MUST accept a string parameter representing either an absolute URL with scheme or a bare host. MUST prepend `https://` when the input lacks a URL scheme (detected by RFC 3986 scheme pattern `^[a-z][a-z0-9+.-]*://`); MUST return the input unchanged if a scheme is present.
- **live-url-idempotent**: `liveUrl()` MUST be idempotent: calling it twice on its own output MUST return the same result.
- **dashboard-url-vercel**: When platform is canonicalized to `vercel`, `platformDashboardUrl()` MUST return `https://vercel.com/{vercelTeamId}/{projectName}` if `meta.vercelTeamId` is present; MUST return `null` if `vercelTeamId` is missing or falsy.
- **dashboard-url-railway**: When platform is canonicalized to `railway`, `platformDashboardUrl()` MUST return `https://railway.app/project/{railwayProjectId}` if `meta.railwayProjectId` is present; MUST return `null` if `railwayProjectId` is missing or falsy.
- **dashboard-url-cloudflare**: When platform is canonicalized to `cloudflare`, `platformDashboardUrl()` MUST return `https://dash.cloudflare.com/{cloudflareAccountId}/workers/services/view/{projectName}` if `meta.cloudflareAccountId` is present; MUST return `null` if `cloudflareAccountId` is missing or falsy.
- **dashboard-url-platform-canonicalization**: `platformDashboardUrl()` MUST canonicalize the platform parameter using `platformCanon()` from the monitor submodule before evaluating the switch; `cloudflare-pages` and `cloudflare` MUST be treated as equivalent.
- **dashboard-url-unknown-platform**: When the canonicalized platform does not match `vercel`, `railway`, or `cloudflare`, `platformDashboardUrl()` MUST return `null`.
- **dashboard-url-project-name-required**: `platformDashboardUrl()` MUST return `null` when `projectName` is not provided (null or falsy), regardless of platform or credentials.
- **project-name-url-encoding**: In `platformDashboardUrl()`, `projectName` MUST be URL-encoded with `encodeURIComponent()` in the Vercel and Cloudflare URLs; the Railway URL does not contain the project name (it uses `meta.railwayProjectId`, inserted unencoded), though a falsy `projectName` still yields `null` for Railway too.
- **site-links-production-endpoint**: `siteLinks()` MUST select the production endpoint by matching `environment === 'production'` in the endpoints array; MUST fall back to the first endpoint (`endpoints[0]`) if no production endpoint is found.
- **site-links-live-url**: In `siteLinks()`, the `live` field MUST be `liveUrl(prod.url)` for the selected endpoint (production, else first); MUST be `null` only when the endpoints array is empty. `url` is a required string on the endpoint type, so there is no null-url branch — an empty `url` yields `"https://"`.
- **site-links-platform-dashboard**: In `siteLinks()`, the `platform` field MUST be the result of `platformDashboardUrl(site.platform, site.projectName, meta)`.
- **default-meta-parameter**: `platformDashboardUrl()` and `siteLinks()` MUST accept an optional `meta` parameter; when not provided, both functions MUST treat it as an empty object `{}`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `platform` | `string \| null \| undefined` | `null` | The hosting platform identifier (e.g., `vercel`, `railway`, `cloudflare`). Passed to `platformCanon()` for normalization. |
| `projectName` | `string \| null \| undefined` | `null` | The project or site name on the platform. Used in URL construction; `null` yields `null` for platform dashboard. |
| `meta` | `PlatformMeta` | `{}` | Optional platform-specific identifiers: `vercelTeamId`, `railwayProjectId`, `cloudflareAccountId`. Omitted fields are `undefined` and treated as absent (falsy). |
| `endpoints` | `Array<{ url: string; environment?: string \| null }>` | N/A | Array of deployment endpoints. The production endpoint (matched by `environment === 'production'`) is preferred; otherwise the first endpoint is used. Empty array yields `null` for `live`. |

## Platform Notes

- **Web / TypeScript**: The module is implemented in TypeScript (`links.ts`) with ES6 module syntax. Functions are pure and side-effect-free. URL scheme detection uses a regex (`/^[a-z][a-z0-9+.-]*:\/\//i`) compliant with RFC 3986. Platform canonicalization is delegated to `platformCanon()` from the monitor submodule (re-exported by `../monitor/overview` from `@agentic-toolkit/deploy-platform/canon`, where it maps platform aliases such as `cloudflare-pages` to one canonical name). URL encoding is handled by the native `encodeURIComponent()` function.
- **WinUI 3**: Port `links.ts` to a static C# class (e.g. `SiteLinkBuilder`) in a plain .NET class library the WinUI 3 app and any ASP.NET Core backend both reference; it is pure, synchronous, and touches no UI, so it needs no `DispatcherQueue` marshalling or `async` and can be called from any thread. `PlatformMeta` becomes `public sealed record PlatformMeta(string? RailwayProjectId = null, string? VercelTeamId = null, string? CloudflareAccountId = null)` and `SiteLinks` becomes `public sealed record SiteLinks(string? Live, string? Platform)`, with nullable reference types enabled. `liveUrl()` keeps the exact regex as `new Regex(@"^[a-z][a-z0-9+.-]*://", RegexOptions.IgnoreCase)` (or a `[GeneratedRegex]`) rather than `Uri.TryCreate`, which would accept scheme-less or `file:` forms differently and break idempotence. `platformDashboardUrl()` takes `string? platform, string? projectName, PlatformMeta? meta = null`, treats a null `meta` as `new PlatformMeta()`, returns null first when `string.IsNullOrEmpty(projectName)`, and switches on the result of a ported `PlatformCanon(platform)` (a dictionary or switch mapping aliases such as `cloudflare-pages` to `cloudflare`, shared with the monitor port rather than duplicated); each falsy-id check becomes `string.IsNullOrEmpty`, and `encodeURIComponent()` becomes `Uri.EscapeDataString()` applied to `projectName` in the Vercel and Cloudflare URLs only, with the Railway id inserted unencoded exactly as the source does. `siteLinks()` takes the site's `Platform`/`ProjectName` and an `IReadOnlyList` of endpoints with `Url` and `string? Environment`, selects `endpoints.FirstOrDefault(e => e.Environment == "production") ?? endpoints.FirstOrDefault()`, and keeps every URL template, the null-never-guess rule, and the empty-`url`-yields-`https://` behavior identical. In the WinUI 3 client, bind `SiteLinks.Live`/`Platform` to `HyperlinkButton.NavigateUri` (hidden when null) or open them with `Windows.System.Launcher.LaunchUriAsync(new Uri(...))`.
- **iOS / Swift**: Implement as a Swift module with structs for `PlatformMeta` and `SiteLinks`. Use `URL(string:)` for scheme detection or `URL.scheme` property check. Encode URL components with `URLComponents` and `URLQueryItem` where applicable, or `addingPercentEncoding(withAllowedCharacters:)` for manual encoding. Delegate platform canonicalization to a separate `platformCanon()` function; isolate it to support mocking in unit tests.
- **macOS / Swift AppKit**: Same as iOS; no platform-specific differences in link generation.
- **Android / Kotlin**: Implement as a Kotlin object or top-level functions in a module. Use `Uri.Builder` for URL construction or `URLEncoder.encode()` for encoding (specify UTF-8). Platform canonicalization can be a sealed class or when expression. Implement nullability using Kotlin's nullable types (`String?`).

## Design Decisions

**Decision**: Links are derived from real configuration only; no guessing.

**Rationale**: When a monitored site lacks a platform identifier or team ID, the module returns `null` rather than constructing a plausible-looking but unverified URL. This prevents users from being directed to incorrect dashboards and makes it clear to calling code when a link cannot be built. The pattern forces upstream code to handle the `null` case explicitly, avoiding silent failures.

**Approved**: pending

**Decision**: Production endpoint is preferred; fallback to first endpoint.

**Rationale**: Many monitoring scenarios have multiple endpoints (staging, canary, production). The production environment is the canonical live site; preferring it by environment tag ensures the most commonly used URL is returned. Falling back to the first endpoint when no production tag exists handles the common case of single-endpoint deployments without requiring the caller to specify a default.

**Approved**: pending

**Decision**: Platform canonicalization is delegated to `platformCanon()`.

**Rationale**: Platforms are sometimes aliased (e.g., `cloudflare-pages` vs. `cloudflare`). Centralizing canonicalization in a single function (defined in the monitor submodule) ensures consistency across the codebase and allows the canonicalization rules to be updated in one place.

**Approved**: pending
