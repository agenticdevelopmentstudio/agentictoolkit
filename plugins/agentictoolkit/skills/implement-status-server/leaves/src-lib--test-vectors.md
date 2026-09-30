<!-- leaf: implement-status-server/src-lib--test-vectors · source: status-server-src-lib.md -->

# status-server-src-lib

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
