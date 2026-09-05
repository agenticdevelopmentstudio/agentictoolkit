import { platformCanon } from '../monitor/overview';

// ---------------------------------------------------------------------------
// Canonical deep links for a monitored site / deploy project.
//
// A read entry (a /status site, a /deploy-projects project) carries WHERE to go
// next: its live URL and, when we can build one, its hosting-platform dashboard.
// Every link is nullable — we NEVER guess a URL we can't derive from real state
// (a missing team/account/project id yields null, not a plausible-looking guess).
// ---------------------------------------------------------------------------

/** Optional enumeration-derived identifiers a platform link needs but the read
 *  DTOs don't already carry (only Railway's project id today; null everywhere the
 *  enumeration doesn't surface it, which is currently all callers). Also carries
 *  the two credentials `platformDashboardUrl` needs (`config.credentials.VERCEL_TEAM_ID` /
 *  `CLOUDFLARE_ACCOUNT_ID`) — this module never reads env or config itself. */
export interface PlatformMeta {
  railwayProjectId?: string | null;
  vercelTeamId?: string | null;
  cloudflareAccountId?: string | null;
}

/** The canonical links attached to a site / project read entry. Both nullable:
 *  `live` is null for a project with no domain; `platform` is null whenever the
 *  dashboard URL can't be built from real config (no team/account/project id). */
export interface SiteLinks {
  live: string | null;
  platform: string | null;
}

/** Normalize an endpoint URL / bare host to a browsable absolute URL. A stored
 *  endpoint may be a full `https://host/path` or a bare `host`; the deploy-project
 *  `domain` is always a bare host. Prepend `https://` only when no scheme is present. */
export function liveUrl(url: string): string {
  return /^[a-z][a-z0-9+.-]*:\/\//i.test(url) ? url : `https://${url}`;
}

/**
 * The hosting-platform dashboard URL for a deploy project, or null when it can't
 * be built from real configuration (never a guess):
 *   - vercel     → https://vercel.com/<VERCEL_TEAM_ID>/<project>   (null without the team)
 *   - railway    → https://railway.app/project/<id>                 (null without meta.railwayProjectId)
 *   - cloudflare → https://dash.cloudflare.com/<CLOUDFLARE_ACCOUNT_ID>/workers/services/view/<name>
 *                                                                    (null without the account id)
 * Platform is canonicalized first, so `cloudflare-pages` and `cloudflare` agree.
 */
export function platformDashboardUrl(
  platform: string | null | undefined,
  projectName: string | null | undefined,
  meta: PlatformMeta = {},
): string | null {
  if (!projectName) return null;
  switch (platformCanon(platform)) {
    case 'vercel': {
      const team = meta.vercelTeamId;
      return team ? `https://vercel.com/${team}/${encodeURIComponent(projectName)}` : null;
    }
    case 'railway': {
      // EnumeratedProject carries no Railway project id, so this is null in
      // practice today — the honest answer until enumeration surfaces the id.
      const id = meta.railwayProjectId;
      return id ? `https://railway.app/project/${id}` : null;
    }
    case 'cloudflare': {
      const account = meta.cloudflareAccountId;
      return account
        ? `https://dash.cloudflare.com/${account}/workers/services/view/${encodeURIComponent(projectName)}`
        : null;
    }
    default:
      return null;
  }
}

/**
 * The canonical links for a site / project: its live production URL and its
 * platform dashboard. `live` is the PRODUCTION endpoint's URL (falling back to the
 * first endpoint), normalized to an absolute URL; null when the site has no
 * endpoint/domain. `platform` is the deploy-platform dashboard (nullable).
 */
export function siteLinks(
  site: { platform: string | null; projectName: string | null },
  endpoints: { url: string; environment?: string | null }[],
  meta?: PlatformMeta,
): SiteLinks {
  const prod = endpoints.find((e) => e.environment === 'production') ?? endpoints[0];
  return {
    live: prod ? liveUrl(prod.url) : null,
    platform: platformDashboardUrl(site.platform, site.projectName, meta),
  };
}
