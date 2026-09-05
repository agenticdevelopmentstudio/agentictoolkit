import type { StatusConfig } from '../config/port';

// ---------------------------------------------------------------------------
// The storage boundary: plain-domain-type interfaces every consumer (routes,
// monitor, board, MCP tools, peers, telemetry) reads and writes through.
//
// NOTHING here imports drizzle-orm, @libsql/*, or a schema/table module — every
// method signature takes and returns the plain types below, never a `$inferSelect`
// row alias, a `Db`, or a raw `SQL` fragment. The libSQL implementation of these
// interfaces (`createLibsqlStorage`) lives under `../libsql/stores/` and is the
// only place permitted to speak drizzle.
//
// Each store is named for the concern the existing code already expresses
// (Config, Auth, Token, Health, …) rather than an invented grouping. `Storage`
// is composed from them so a host builds exactly one object and threads it
// through `createApp`.
// ---------------------------------------------------------------------------

// --- config: groups / sites / endpoints / integrations / ignored projects / peers ---

/** One ACTIVE endpoint flattened with its site + group names — the list the
 *  probes (and /api/live) run against. */
export interface ConfiguredEndpoint {
  slug: string; // stable per endpoint — the problem target key
  group: string;
  name: string;
  environment: string | null;
  url: string;
  kind: string;
  platform: string | null; // explicit deploy-target wiring (correlation key)
  deployProject: string | null;
  /** Operator opt-out: when true, this endpoint is intentionally NOT tied to a deploy
   *  project (auto-wire must skip it, the "unconfigured" warning is suppressed). */
  ignoreProjectWarning?: boolean;
  expectedStatus: number;
  /** Optional body-content marker (see EndpointRow.expectBody). */
  expectBody?: string | null;
  /** DNS-resolution check toggles (A/AAAA/CNAME). Undefined → every type on, the
   *  pre-toggle default (see monitor/probe.ts dnsChecksOf). */
  dnsCheckA?: boolean;
  dnsCheckAaaa?: boolean;
  dnsCheckCname?: boolean;
}

/** A `site_groups` row, as a plain type (was `typeof siteGroups.$inferSelect`). */
export interface GroupRow {
  id: string;
  slug: string;
  name: string;
  retentionDays: number;
  createdAt: Date;
  updatedAt: Date;
}

/** A `monitored_sites` row, as a plain type (was `typeof monitoredSites.$inferSelect`). */
export interface SiteRow {
  id: string;
  siteGroupId: string;
  slug: string;
  name: string;
  createdAt: Date;
  updatedAt: Date;
}

/** A `monitored_endpoints` row, as a plain type (was `typeof monitoredEndpoints.$inferSelect`). */
export interface EndpointRow {
  id: string;
  siteId: string;
  url: string;
  kind: string;
  environment: string | null;
  platform: string | null;
  deployProject: string | null;
  deployProjectId: string | null;
  ignoreProjectWarning: boolean;
  expectedStatus: number;
  expectBody: string | null;
  dnsCheckA: boolean;
  dnsCheckAaaa: boolean;
  dnsCheckCname: boolean;
  checkIntervalSeconds: number;
  isActive: boolean;
  monitorHttp: boolean;
  monitorDeploys: boolean;
  createdAt: Date;
  updatedAt: Date;
}

/** A `deploy_integrations` row, as a plain type (was `typeof deployIntegrations.$inferSelect`). */
export interface IntegrationRow {
  id: string;
  platform: string;
  label: string;
  config: Record<string, unknown>;
  tokenEnvVar: string | null;
  secretRef: string | null;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
}

/** A `peers` row, as a plain type (was `typeof peers.$inferSelect`). */
export interface PeerRow {
  id: string;
  label: string;
  baseUrl: string;
  token: string | null;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface IgnoredProject {
  platform: string;
  projectName: string;
}

export interface ConfigStore {
  listSiteGroups(): Promise<GroupRow[]>;
  createGroup(input: { name: string; slug: string; retentionDays?: number }): Promise<GroupRow>;
  updateGroup(id: string, patch: { name?: string; slug?: string; retentionDays?: number }): Promise<GroupRow | null>;
  deleteGroup(id: string): Promise<void>;

  listSites(): Promise<SiteRow[]>;
  createSite(input: { name: string; slug: string; siteGroupId: string }): Promise<SiteRow>;
  updateSite(id: string, patch: { name?: string; slug?: string; siteGroupId?: string }): Promise<SiteRow | null>;
  deleteSite(id: string): Promise<void>;

  listEndpoints(siteId?: string): Promise<EndpointRow[]>;
  createEndpoint(input: {
    siteId: string;
    url: string;
    kind?: string;
    environment?: string | null;
    platform?: string | null;
    deployProject?: string | null;
    deployProjectId?: string | null;
    ignoreProjectWarning?: boolean;
    expectedStatus?: number;
    expectBody?: string | null;
    dnsCheckA?: boolean;
    dnsCheckAaaa?: boolean;
    dnsCheckCname?: boolean;
    checkIntervalSeconds?: number;
    isActive?: boolean;
    monitorHttp?: boolean;
    monitorDeploys?: boolean;
  }): Promise<EndpointRow>;
  updateEndpoint(
    id: string,
    patch: {
      url?: string;
      kind?: string;
      environment?: string | null;
      platform?: string | null;
      deployProject?: string | null;
      deployProjectId?: string | null;
      ignoreProjectWarning?: boolean;
      expectedStatus?: number;
      expectBody?: string | null;
      dnsCheckA?: boolean;
      dnsCheckAaaa?: boolean;
      dnsCheckCname?: boolean;
      checkIntervalSeconds?: number;
      isActive?: boolean;
      monitorHttp?: boolean;
      monitorDeploys?: boolean;
    },
  ): Promise<EndpointRow | null>;
  deleteEndpoint(id: string): Promise<void>;

  /** Purge an endpoint's monitoring history (health_checks + metrics_hourly) and
   *  resolve its open issues. See the libsql implementation for the full rationale. */
  purgeEndpointHistory(epIds: string[]): Promise<void>;

  listActiveEndpoints(): Promise<ConfiguredEndpoint[]>;

  reconcileOrphanedEndpoints(): Promise<{ endpoints: number; sites: number; prunedEndpointIds: string[] }>;

  retireEndpoint(id: string): Promise<{ endpointDeleted: boolean; siteDeleted: boolean }>;

  listIntegrations(): Promise<IntegrationRow[]>;
  createIntegration(input: {
    platform: string;
    label: string;
    config?: unknown;
    tokenEnvVar?: string | null;
    isActive?: boolean;
  }): Promise<IntegrationRow>;
  updateIntegration(
    id: string,
    patch: { platform?: string; label?: string; config?: unknown; tokenEnvVar?: string | null; isActive?: boolean },
  ): Promise<IntegrationRow | null>;
  deleteIntegration(id: string): Promise<void>;

  listIgnoredProjects(): Promise<IgnoredProject[]>;
  addIgnoredProject(platform: string, projectName: string): Promise<void>;
  addIgnoredProjects(rows: IgnoredProject[]): Promise<void>;
  removeIgnoredProject(platform: string, projectName: string): Promise<void>;

  listPeers(): Promise<PeerRow[]>;
  createPeer(input: { label: string; baseUrl: string; token?: string | null; isActive?: boolean }): Promise<PeerRow>;
  updatePeer(
    id: string,
    patch: { label?: string; baseUrl?: string; token?: string | null; isActive?: boolean },
  ): Promise<PeerRow | null>;
  deletePeer(id: string): Promise<void>;
}

/** Drop the secret `token` column before a peer row leaves the process, replacing it
 *  with `hasToken` — WHETHER one is set, which is all any read surface (REST
 *  GET/POST/PATCH or the MCP `list_peers`/`add_peer` tools) may know. Pure — has
 *  no store dependency, so it stays beside the type it projects rather than
 *  moving into the libsql adapter. */
export function redactPeer<T extends { token?: unknown }>(peer: T): Omit<T, 'token'> & { hasToken: boolean } {
  const { token, ...rest } = peer;
  return { ...rest, hasToken: typeof token === 'string' && token !== '' };
}

// --- auth: users + sessions --------------------------------------------------

export type UserRole = 'pending' | 'viewer' | 'admin';

/** The request principal carried on the Hono context — never the password hash. */
export interface AuthUser {
  id: string;
  email: string;
  displayName: string;
  role: UserRole;
}

/** A `users` row, as a plain type (was `typeof users.$inferSelect`). Internal to
 *  the auth flows (signup/login/OAuth) that need the password hash or GitHub id;
 *  everything else reads the narrower `AuthUser`. */
export interface UserRecord {
  id: string;
  email: string;
  passwordHash: string | null;
  githubId: string | null;
  displayName: string;
  role: string;
  createdAt: Date;
}

export interface AuthStore {
  findUserByEmail(email: string): Promise<UserRecord | undefined>;
  findUserByGithubId(githubId: string): Promise<UserRecord | undefined>;
  getUserById(id: string): Promise<UserRecord | undefined>;
  createUser(input: {
    email: string;
    displayName: string;
    role: UserRole;
    passwordHash?: string | null;
    githubId?: string | null;
  }): Promise<UserRecord>;
  /** Link a GitHub identity onto an existing account. */
  attachGithubId(userId: string, githubId: string): Promise<UserRecord | undefined>;
  listUsers(): Promise<AuthUser[]>;
  /** Change a user's role; demoting the LAST admin is atomically blocked. */
  setUserRoleGuarded(id: string, role: UserRole): Promise<AuthUser | 'blocked' | undefined>;
  /** Delete a user (and their sessions); deleting the LAST admin is atomically blocked. */
  deleteUserGuarded(id: string): Promise<boolean | 'blocked'>;
  countAdmins(): Promise<number>;

  /** Mint a session: returns the raw opaque cookie token; only its sha256 is persisted. */
  createSession(userId: string, ttlMs?: number): Promise<string>;
  /** Resolve a cookie token → the live user, or null (unknown/expired). */
  resolveSession(token: string | undefined): Promise<AuthUser | null>;
  revokeSession(token: string | undefined): Promise<void>;
}

/** SQLite/libSQL unique-index violation — the email/githubId already exists. Pure
 *  (walks an Error's `.cause` chain), so it stays here rather than in the adapter. */
export function isUniqueViolation(err: unknown): boolean {
  for (let e: unknown = err; e instanceof Error; e = e.cause) {
    if (/UNIQUE constraint failed/i.test(e.message)) return true;
  }
  return false;
}

const ROLES = new Set<UserRole>(['pending', 'viewer', 'admin']);

/** Coerce a raw text role to the union, defaulting an UNKNOWN value to the
 *  least-privileged `pending` (fail safe, not fail open) rather than casting blind. */
function asRole(role: string): UserRole {
  return ROLES.has(role as UserRole) ? (role as UserRole) : 'pending';
}

/** Project a `UserRecord` down to the public principal (drops the password hash). */
export function toAuthUser(u: UserRecord): AuthUser {
  return { id: u.id, email: u.email, displayName: u.displayName, role: asRole(u.role) };
}

/** Bootstrap rule: emails in ADMIN_EMAILS are admins from their first account;
 *  everyone else starts pending. Pure (config-only), so it stays here rather than
 *  in the adapter. */
export function roleForEmail(email: string, config: Pick<StatusConfig, 'adminEmails'>): UserRole {
  return config.adminEmails.includes(email.toLowerCase()) ? 'admin' : 'pending';
}

// --- tokens: opaque API bearer tokens ----------------------------------------

/** Every raw status token starts with this; the bearer seam only attempts a
 *  token lookup when the Authorization bearer begins with it. */
export const TOKEN_PREFIX = 'sts_';
/** How many leading chars of the raw value are stored as the display prefix. */
export const PREFIX_LEN = 12; // 'sts_' + 8 hex

/** The token principal recorded on the context (never the hash or raw value). */
export interface TokenPrincipal {
  id: string;
  name: string;
  role: 'admin' | 'user';
  expiresAt: Date | null;
}

/** Token metadata for listing — never the hash or the raw secret. */
export interface ApiTokenMeta {
  id: string;
  name: string;
  role: 'admin' | 'user';
  kind: 'minted' | 'device';
  prefix: string;
  createdBy: string;
  createdAt: Date;
  lastUsedAt: Date | null;
  expiresAt: Date | null;
  revokedAt: Date | null;
}

export interface TokenStore {
  /** Mint a token; returns its metadata plus the raw value, shown to the caller
   *  EXACTLY ONCE — only the hash is stored. */
  mintApiToken(input: {
    name: string;
    role: 'admin' | 'user';
    kind?: 'minted' | 'device';
    createdBy: string;
    expiresAt?: Date | null;
  }): Promise<{ meta: ApiTokenMeta; raw: string }>;
  /** Validate a raw bearer token → its principal, or null. Bumps last_used_at on success. */
  validateApiToken(raw: string): Promise<TokenPrincipal | null>;
  listApiTokens(): Promise<ApiTokenMeta[]>;
  /** Soft-revoke a token by id. Returns false when no such token exists. */
  revokeApiToken(id: string): Promise<boolean>;
  /** Hard-delete a token row by id. Returns false when no such token exists. */
  deleteApiToken(id: string): Promise<boolean>;
}

// --- health: latest-check and bad-run-onset reads ----------------------------

/** One row per slug that has a current bad run, `since` in epoch SECONDS. */
export interface BadRunOnsetRow {
  service_slug: string;
  since: number | null;
}

/** The shape of one "latest check" read — snake_case columns straight from SQLite,
 *  with `checked_at` in epoch SECONDS and `dns_ok` as 0/1. Callers map it into
 *  their own richer type. */
export interface LatestCheckRow {
  service_slug: string;
  status: string;
  response_time_ms: number | null;
  status_code: number | null;
  error: string | null;
  checked_at: number;
  dns_ok: number;
}

export interface HealthStore {
  /** The latest health_checks row per given slug — THE ONLY WAY anything reads
   *  "the current health of these endpoints" (see the libsql implementation for
   *  the sargable-seek + tiebreak rationale). */
  latestChecks(slugs: string[]): Promise<LatestCheckRow[]>;
  /** The onset of each slug's current unbroken bad run, for every slug given. */
  badRunOnsets(slugs: string[]): Promise<BadRunOnsetRow[]>;
}

// --- composed storage ---------------------------------------------------------

/** Everything a host builds once and threads through `createApp`. Composed from
 *  the concerns above by name — never a grab-bag `db`/`conn` escape hatch. */
export interface Storage {
  config: ConfigStore;
  auth: AuthStore;
  tokens: TokenStore;
  health: HealthStore;
}
