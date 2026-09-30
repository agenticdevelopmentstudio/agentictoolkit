<!-- leaf: implement-status-server/src-lib--edge-cases · source: status-server-src-lib.md -->

# status-server-src-lib

**Rules** (cite as `implement-status-server/src-lib--edge-cases#<slug>`):

- `empty-endpoints-array` MUST — When siteLinks() receives an empty endpoints array, live MUST be null (no endpoint to select). The platform field MUST …
- `undefined-environment-property` MUST — When an endpoint object in the array lacks an environment property, it MUST be treated as a non-production endpoint and …
- `null-platform-parameter` MUST — When siteLinks() is called with site.platform === null or undefined, platformDashboardUrl() MUST canonicalize it and …
- `empty-projectname` MUST — When platformDashboardUrl() receives an empty string as projectName, it MUST return null (falsy check applies).
- `url-scheme-detection-case-insensitive` MUST — The scheme pattern in liveUrl() uses the i flag; HTTP:// and Https:// MUST be recognized as having a scheme.
- `project-name-with-special-characters` MUST — When a projectName contains characters requiring URL encoding (spaces, slashes, ampersands), encodeURIComponent() MUST …

## Edge Cases

- **Empty endpoints array**: When `siteLinks()` receives an empty endpoints array, `live` MUST be `null` (no endpoint to select). The `platform` field MUST still be computed correctly.
- **Undefined environment property**: When an endpoint object in the array lacks an `environment` property, it MUST be treated as a non-production endpoint and available as a fallback only if no production endpoint exists.
- **Empty url string**: `url` is typed as a required `string`; an endpoint whose `url` is `""` produces `live: "https://"` because `liveUrl` prepends the scheme without checking for an empty host.
- **Null platform parameter**: When `siteLinks()` is called with `site.platform === null` or `undefined`, `platformDashboardUrl()` MUST canonicalize it and return `null` (no recognized platform).
- **Empty projectName**: When `platformDashboardUrl()` receives an empty string as projectName, it MUST return `null` (falsy check applies).
- **URL scheme detection case-insensitive**: The scheme pattern in `liveUrl()` uses the `i` flag; `HTTP://` and `Https://` MUST be recognized as having a scheme.
- **Project name with special characters**: When a projectName contains characters requiring URL encoding (spaces, slashes, ampersands), `encodeURIComponent()` MUST encode them in the Vercel and Cloudflare dashboard paths; the Railway path does not include the project name.
