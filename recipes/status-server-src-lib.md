---
id: 1c017caa-0dcc-4278-9b82-af4fa935a3d9
title: status-server-src-lib
domain: agentictoolkit://recipes/status-server-src-lib
type: ingredient
version: 1.0.0
status: review
language: en
created: 2026-09-24
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Link generation for monitored sites and deploy projects, deriving live URLs
  and platform dashboards from configuration and metadata.
platforms:
- web
tags:
- link-generation
- configuration
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a link-generation utility, not a visual component.

## States

Not applicable — this is a link-generation utility, not a visual component.

## Accessibility

Not applicable — this is a link-generation utility, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| links-001 | live-url-normalization | `liveUrl("example.com")` | `"https://example.com"` |
| links-002 | live-url-normalization | `liveUrl("https://example.com/path")` | `"https://example.com/path"` |
| links-003 | live-url-idempotent | `liveUrl(liveUrl("example.com"))` | `"https://example.com"` |
| links-004 | dashboard-url-vercel | `platformDashboardUrl("vercel", "my-app", { vercelTeamId: "acme" })` | `"https://vercel.com/acme/my-app"` |
| links-005 | dashboard-url-vercel | `platformDashboardUrl("vercel", "my-app", { vercelTeamId: null })` | `null` |
| links-006 | dashboard-url-railway | `platformDashboardUrl("railway", "my-app", { railwayProjectId: "xyz123" })` | `"https://railway.app/project/xyz123"` |
| links-007 | dashboard-url-railway | `platformDashboardUrl("railway", "my-app", {})` | `null` |
| links-008 | dashboard-url-cloudflare | `platformDashboardUrl("cloudflare", "worker-name", { cloudflareAccountId: "abc123" })` | `"https://dash.cloudflare.com/abc123/workers/services/view/worker-name"` |
| links-009 | dashboard-url-cloudflare | `platformDashboardUrl("cloudflare-pages", "worker-name", { cloudflareAccountId: "abc123" })` | `"https://dash.cloudflare.com/abc123/workers/services/view/worker-name"` |
| links-010 | dashboard-url-unknown-platform | `platformDashboardUrl("heroku", "my-app", {})` | `null` |
| links-011 | dashboard-url-project-name-required | `platformDashboardUrl("vercel", null, { vercelTeamId: "acme" })` | `null` |
| links-012 | project-name-url-encoding | `platformDashboardUrl("vercel", "my app", { vercelTeamId: "acme" })` | `"https://vercel.com/acme/my%20app"` |
| links-013 | site-links-production-endpoint | `siteLinks({ platform: "vercel", projectName: "app" }, [{ url: "dev.example.com", environment: "dev" }, { url: "prod.example.com", environment: "production" }], { vercelTeamId: "acme" })` | `{ live: "https://prod.example.com", platform: "https://vercel.com/acme/app" }` |
| links-014 | site-links-production-endpoint | `siteLinks({ platform: "vercel", projectName: "app" }, [{ url: "staging.example.com" }], { vercelTeamId: "acme" })` | `{ live: "https://staging.example.com", platform: "https://vercel.com/acme/app" }` |
| links-015 | site-links-live-url | `siteLinks({ platform: "vercel", projectName: "app" }, [], { vercelTeamId: "acme" })` | `{ live: null, platform: "https://vercel.com/acme/app" }` |

## Edge Cases

- **Empty endpoints array**: When `siteLinks()` receives an empty endpoints array, `live` MUST be `null` (no endpoint to select). The `platform` field MUST still be computed correctly.
- **Undefined environment property**: When an endpoint object in the array lacks an `environment` property, it MUST be treated as a non-production endpoint and available as a fallback only if no production endpoint exists.
- **Empty url string**: `url` is typed as a required `string`; an endpoint whose `url` is `""` produces `live: "https://"` because `liveUrl` prepends the scheme without checking for an empty host.
- **Null platform parameter**: When `siteLinks()` is called with `site.platform === null` or `undefined`, `platformDashboardUrl()` MUST canonicalize it and return `null` (no recognized platform).
- **Empty projectName**: When `platformDashboardUrl()` receives an empty string as projectName, it MUST return `null` (falsy check applies).
- **URL scheme detection case-insensitive**: The scheme pattern in `liveUrl()` uses the `i` flag; `HTTP://` and `Https://` MUST be recognized as having a scheme.
- **Project name with special characters**: When a projectName contains characters requiring URL encoding (spaces, slashes, ampersands), `encodeURIComponent()` MUST encode them in the Vercel and Cloudflare dashboard paths; the Railway path does not include the project name.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `platform` | `string \| null \| undefined` | `null` | The hosting platform identifier (e.g., `vercel`, `railway`, `cloudflare`). Passed to `platformCanon()` for normalization. |
| `projectName` | `string \| null \| undefined` | `null` | The project or site name on the platform. Used in URL construction; `null` yields `null` for platform dashboard. |
| `meta` | `PlatformMeta` | `{}` | Optional platform-specific identifiers: `vercelTeamId`, `railwayProjectId`, `cloudflareAccountId`. Omitted fields are `undefined` and treated as absent (falsy). |
| `endpoints` | `Array<{ url: string; environment?: string \| null }>` | N/A | Array of deployment endpoints. The production endpoint (matched by `environment === 'production'`) is preferred; otherwise the first endpoint is used. Empty array yields `null` for `live`. |

## Deep Linking

Not applicable: this module generates URLs for external consumption (rendered in a status dashboard or sent to monitoring logs), not a deep-linking scheme internal to an application.

## Localization

Not applicable: the module contains no user-facing strings. Dashboard URLs are hardcoded absolute URLs to third-party platforms; they are not localized.

## Accessibility Options

Not applicable: the module generates data structures (URL strings), not UI components that respond to accessibility display settings.

## Feature Flags

Not applicable: the module contains no conditional logic gated by feature flags. Link generation is unconditional.

## Analytics

Not applicable: the module generates URLs but does not emit analytics events. Logging or event emission would occur in calling code.

## Privacy

Not applicable: the module does not collect, store, or transmit data. It derives URLs from caller-supplied configuration. The credentials passed in `meta` (e.g., `vercelTeamId`) are used only to construct URLs; they are not persisted or logged by this module.

## Logging

Not applicable: the module contains no logging calls. All errors (e.g., missing credentials) are communicated via `null` return values.

## Platform Notes

- **Web / TypeScript**: The module is implemented in TypeScript (`links.ts`) with ES6 module syntax. Functions are pure and side-effect-free. URL scheme detection uses a regex (`/^[a-z][a-z0-9+.-]*:\/\//i`) compliant with RFC 3986. Platform canonicalization is delegated to `platformCanon()` from the monitor submodule (re-exported by `../monitor/overview` from `@agentic-toolkit/deploy-platform/canon`, where it maps platform aliases such as `cloudflare-pages` to one canonical name). URL encoding is handled by the native `encodeURIComponent()` function.
- **Windows (.NET / C#)**: Derive URLs using `System.Uri` for scheme detection and `Uri.EscapeDataString()` for URL encoding. Canonicalize platform names using a switch statement or a dictionary mapping aliases like `cloudflare-pages` to `cloudflare`. Implement `PlatformMeta` as a nullable record type or class with optional properties. The `null`-checking patterns in the source translate directly to C# null-coalescing operators (`??`) and ternary expressions.
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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |

**Separation of Concerns**: The module has a single responsibility — generating canonical links from configuration. Public functions are pure (no side effects), take only what they need as parameters, and return simple data structures. Concerns like platform canonicalization are delegated to the monitor submodule.

**Unit Test Coverage**: The module's core logic (URL normalization, dashboard URL construction, endpoint selection) is amenable to unit testing and should be covered by test vectors. However, the source file provided does not include unit test assertions; these must be verified in the test suite alongside this recipe.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | | Initial creation |
