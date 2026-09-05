// The seed-roster port. `POST /config/seed` fills an empty configuration with a
// host-supplied list of sites to monitor — the roster is the host's data (which
// products it watches, on which hosts), so it arrives through `AppDeps.seed`
// (./app.ts) and nothing in this package names a site of its own.
//
// Plain data, like StatusConfig: no functions, so a host can keep it in JSON.

/** The environments a seeded site may carry; each becomes one endpoint. */
export type SeedEnvironment = 'production' | 'staging' | 'testing';

/** One monitored site as the host declares it — one row here fans out into a
 *  site-group (by `group`), a site (by `name` + `baseSlug`) and one endpoint per
 *  entry in `envs`, at `https://<env-qualified host><path>`. The non-production
 *  hosts follow the `staging.<host>` / `testing.<host>` convention. */
export interface SeedEndpoint {
  /** Section the site is listed under; becomes a site-group (slug = lower-cased, dashes). */
  group: string;
  /** The site's display name, unique within its group. */
  name: string;
  /** Slug for the site row; the endpoint kind + environment hang off it. */
  baseSlug: string;
  /** Production host, no scheme. */
  host: string;
  /** Which environments to create endpoints for. */
  envs: readonly SeedEnvironment[];
  /** Endpoint kind (`frontend`, `admin`, `health`, `custom`, …) — see the endpoints schema. */
  kind: string;
  /** Path appended to every environment's URL, e.g. `/health`. */
  path?: string;
  /** Expected HTTP status; 200 when omitted. */
  expectedStatus?: number;
}

/** What a host hands `createApp` as `seed`. Empty means the seed route creates
 *  only the provider connections whose credentials are present. */
export type SeedRoster = readonly SeedEndpoint[];
