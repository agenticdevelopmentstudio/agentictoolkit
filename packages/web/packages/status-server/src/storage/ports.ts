import type { StatusConfig } from '../config/port';
import type { Store } from '../telemetry/ports';
import type { AnalyticsMetricDTO, ErrorDTO } from '../telemetry/types';
import type {
  DeployFact,
  ErrorFact,
  IssueEvent,
  LedgerEntry,
  PlatformFact,
  RosterEntry,
  StaleProdFact,
} from '../board/types';

// ---------------------------------------------------------------------------
// The storage boundary: plain-domain-type interfaces every consumer (routes,
// monitor, board, MCP tools, peers, telemetry) reads and writes through.
//
// NOTHING here imports a query-builder, driver client, or a schema/table module —
// every method signature takes and returns the plain types below, never a
// generated row-inference alias, a connection handle, or a raw query fragment.
// The libSQL implementation of these interfaces (`createLibsqlStorage`) lives
// under `../libsql/stores/` and is the only place permitted to speak to the driver.
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

/** A `site_groups` row, as a plain domain type. */
export interface GroupRow {
  id: string;
  slug: string;
  name: string;
  retentionDays: number;
  createdAt: Date;
  updatedAt: Date;
}

/** A `monitored_sites` row, as a plain domain type. */
export interface SiteRow {
  id: string;
  siteGroupId: string;
  slug: string;
  name: string;
  createdAt: Date;
  updatedAt: Date;
}

/** A `monitored_endpoints` row, as a plain domain type. */
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

/** A `deploy_integrations` row, as a plain domain type. */
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

/** A `peers` row, as a plain domain type. */
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
    secretRef?: string | null;
    isActive?: boolean;
  }): Promise<IntegrationRow>;
  updateIntegration(
    id: string,
    patch: {
      platform?: string;
      label?: string;
      config?: unknown;
      tokenEnvVar?: string | null;
      secretRef?: string | null;
      isActive?: boolean;
    },
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

/** A `users` row, as a plain domain type. Internal to the auth flows
 *  (signup/login/OAuth) that need the password hash or GitHub id;
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

/** One probe result, as `HealthStore.recordChecks` persists it. */
export interface HealthCheckInput {
  serviceSlug: string;
  status: string;
  responseTimeMs: number | null;
  statusCode: number | null;
  error: string | null;
  dnsOk: boolean;
}

export interface HealthStore {
  /** The latest health_checks row per given slug — THE ONLY WAY anything reads
   *  "the current health of these endpoints" (see the libsql implementation for
   *  the sargable-seek + tiebreak rationale). */
  latestChecks(slugs: string[]): Promise<LatestCheckRow[]>;
  /** The onset of each slug's current unbroken bad run, for every slug given. */
  badRunOnsets(slugs: string[]): Promise<BadRunOnsetRow[]>;

  /** Persist one health_checks row per probe result. */
  recordChecks(checks: HealthCheckInput[]): Promise<void>;
  /** Aggregate stats over every persisted check: total samples + distinct services. */
  checksSummary(): Promise<{ samples: number; services: number }>;
  /** The most recent check's epoch-ms timestamp, or null when none have run yet. */
  lastCheckedAtMs(): Promise<number | null>;
}

// --- deploy: deployments, deploy targets, project meta, deploy errors -------

/** One deploy as fetched by a provider poll or pushed by a webhook — the plain
 *  shape `DeployStore.upsertDeployments` persists. Structurally mirrors
 *  `ProviderDeploy` (monitor/provider-deploy.ts) at the storage boundary, kept as
 *  its own type here rather than imported so the port never depends on a
 *  consumer's module. */
export interface DeployUpsertInput {
  id: string;
  platform: string;
  projectName: string;
  providerProjectId?: string | null;
  buildPhase: string | null;
  deployPhase: string;
  environment: string | null;
  commitHash: string | null;
  commitMessage: string | null;
  branch: string | null;
  commitRepo: string | null;
  url: string | null;
  createdAt: Date;
}

/** A deploy's correlation fields, for the live-host reconcile. */
export interface DeployHostRow {
  id: string;
  platform: string;
  providerProjectId: string | null;
  projectName: string;
  environment: string | null;
  liveHost: string | null;
}

/** Fresh by-id provider phases for one deploy. */
export interface DeployPhases {
  /** null = the provider has no build phase for this deploy (the column is nullable). */
  buildPhase: string | null;
  deployPhase: string;
}

/** A deploy candidate row — just enough to dispatch a by-id provider re-fetch. */
export interface DeployIdPlatformRow {
  id: string;
  platform: string;
}

/** One project's descriptive metadata, as `DeployStore.upsertProjectMeta` mirrors it. */
export interface ProjectMetaInput {
  platform: string;
  projectName: string;
  domain: string | null;
  gitRepo: string | null;
  gitBranch: string | null;
  rootDirectory: string | null;
  framework: string | null;
}

/** One project's descriptive metadata as read back — the shape `ProjectMetaLike`
 *  (`@agentic-toolkit/deploy-platform/enumerate`) expects. */
export type ProjectMetaRow = ProjectMetaInput;

/** Which deploy projects a live site monitors, keyed by canonical platform — the input
 *  `ownsDeployProject`/`ownedDeploysWhere` narrow a deployments read against. Built by
 *  `rosterDeployProjects` (`src/board/ownership.ts`) from the roster; a storage-boundary
 *  type because both `DeployStore.listRecentOwned` and `BoardStore`'s event/activity reads
 *  take it. */
export type OwnedProjects = Map<string, { ids: Set<string>; names: Set<string> }>;

/** A full `deployments` row, as a plain domain type — the shape
 *  `rowToProviderDeploy`/`deploymentDtos` map into `DeploymentDTO`. */
export interface DeploymentRow {
  id: string;
  platform: string;
  projectName: string;
  providerProjectId: string | null;
  buildPhase: string | null;
  deployPhase: string;
  environment: string | null;
  commitHash: string | null;
  commitMessage: string | null;
  branch: string | null;
  commitRepo: string | null;
  url: string | null;
  errorText: string | null;
  createdAt: Date;
  fetchedAt: Date;
  liveHost: string | null;
}

export interface DeployStore {
  /** Upsert fetched/webhook deploys by id (phases win the update so a re-fetched
   *  build moves to its latest state) — see the libsql implementation for the
   *  webhook-regression guard and the per-column COALESCE rationale. */
  upsertDeployments(deploys: DeployUpsertInput[], opts?: { source?: 'poll' | 'webhook' }): Promise<void>;
  /** Backfill each wired endpoint's provider project id from a batch of deploys,
   *  keyed by the name that already matches; never overwrites an existing id. */
  learnProjectIds(
    deploys: { platform: string; projectName: string; providerProjectId?: string | null }[],
  ): Promise<void>;
  /** Delete deploy rows older than `days`. */
  pruneOlderThanDays(days: number): Promise<void>;
  /** Every deploy row's correlation fields, for the live-host reconcile. */
  listForLiveHostStamp(): Promise<DeployHostRow[]>;
  /** Persist one deploy's reconciled live host. */
  setLiveHost(id: string, host: string | null): Promise<void>;

  /** Recent in-flight deploys on the given platforms, created after `createdAfterMs`
   *  and unconfirmed since before `fetchedBeforeMs`, excluding `excludeIds` (parked
   *  backoff), newest-created first, capped at `limit`. */
  listInFlightCandidates(input: {
    platforms: string[];
    excludeIds: string[];
    createdAfterMs: number;
    fetchedBeforeMs: number;
    limit: number;
  }): Promise<DeployIdPlatformRow[]>;
  /** The provider says this deployment no longer exists — collapse its in-flight
   *  lifecycle(s) to canceled/none. */
  markDeployGone(id: string): Promise<void>;
  /** Fresh by-id provider phases — authoritative, overwrites both phases. */
  markDeployPhases(id: string, phases: DeployPhases): Promise<void>;
  /** Collapse every in-flight deploy unconfirmed for at least `olderThanMs` to
   *  unknown/unknown. Returns the row count affected. */
  expireStaleInFlight(olderThanMs: number): Promise<number>;

  /** Failed deploys on the given platforms with no error_text yet, created after
   *  `createdAfterMs`, newest-created first, capped at `limit`. */
  listFailedWithoutError(input: {
    platforms: string[];
    createdAfterMs: number;
    limit: number;
  }): Promise<DeployIdPlatformRow[]>;
  /** Persist a failed deploy's provider failure reason. */
  setErrorText(id: string, text: string): Promise<void>;

  /** Upsert Vercel project metadata (chunked internally). */
  upsertProjectMeta(rows: ProjectMetaInput[]): Promise<void>;
  /** Every stored project name for a platform. */
  listProjectMetaNames(platform: string): Promise<string[]>;
  /** Every stored project-meta row, across all platforms — the input
   *  `enumerateDeployProjectsFrom` correlates live provider reads against. */
  listProjectMeta(): Promise<ProjectMetaRow[]>;
  /** Delete stored project-meta rows for a platform, by name (chunked internally). */
  deleteProjectMeta(platform: string, names: string[]): Promise<void>;

  /** The most recent `limit` deploys some live site monitors (see `OwnedProjects`),
   *  newest-created first — the Deployments-tab feed. Crunchy clusters (not
   *  site-bound) are always included. */
  listRecentOwned(owned: OwnedProjects, limit: number): Promise<DeploymentRow[]>;

  /** One deployment's identity + persisted failure summary, for `GET /deployments/:id/log` —
   *  null when no such row exists. */
  findById(id: string): Promise<DeployLogRow | null>;
}

/** The fields `GET /deployments/:id/log` needs off one `deployments` row — its identity for
 *  dispatching the provider log fetch, plus the summary already persisted so the response
 *  answers both the summary and (best-effort) the full log in one call. */
export interface DeployLogRow {
  id: string;
  platform: string;
  projectName: string;
  environment: string | null;
  errorText: string | null;
}

// --- issues: the deploy/HTTP issue ledger ------------------------------------

/** An `issues` row, as a plain domain type. */
export interface IssueRow {
  id: number;
  target: string;
  source: string;
  name: string;
  environment: string | null;
  severity: string;
  state: string;
  statusCode: number | null;
  detail: string | null;
  sourceUrl: string | null;
  liveUrl: string | null;
  commitHash: string | null;
  commitMessage: string | null;
  commitRepo: string | null;
  openedAt: Date;
}

export interface IssueInsert {
  target: string;
  source: string;
  name: string;
  environment: string | null;
  severity: string;
  state: string;
  statusCode: number | null;
  detail: string | null;
  sourceUrl: string | null;
  liveUrl: string | null;
  commitHash?: string | null;
  commitMessage?: string | null;
  commitRepo?: string | null;
}

export type IssuePatch = Pick<
  IssueInsert,
  | 'source'
  | 'name'
  | 'environment'
  | 'severity'
  | 'state'
  | 'statusCode'
  | 'detail'
  | 'sourceUrl'
  | 'liveUrl'
  | 'commitHash'
  | 'commitMessage'
  | 'commitRepo'
>;

export interface IssueStore {
  /** Every currently-open issue, oldest-first (openedAt, then id) — so `[0]` per
   *  target is the canonical row and anything after it is a shadow. */
  listOpen(): Promise<IssueRow[]>;
  /** Insert an open issue for a target unless one already exists (the partial
   *  unique index guards the race) — never alerts; the caller decides that. */
  insertIssue(input: IssueInsert): Promise<void>;
  /** Refresh an open issue's derived fields in place. */
  updateIssue(id: number, patch: IssuePatch): Promise<void>;
  /** Close an issue with the given reason. */
  resolveIssue(id: number, reason: 'recovered' | 'unmonitored' | 'duplicate'): Promise<void>;
  /** Resolve every currently-open issue for the given targets as "unmonitored" — for
   *  endpoints that were just deleted, so nothing will ever probe them again to
   *  naturally resolve their issue. A no-op on an empty list. */
  resolveUnmonitoredTargets(targets: string[]): Promise<void>;
}

// --- observations: platform reachability + Vercel prod staleness -----------

/** What one poll saw of a platform — the plain input `ObservationStore.recordObservations`
 *  persists. `source` is a plain string here (the port owns no monitor-domain union);
 *  callers pass their own `IssueSource`-typed values, which are structurally assignable. */
export interface PlatformObservationInput {
  source: string;
  /** An active integration with a token — i.e. a platform we actually poll. */
  configured: boolean;
  /** Did this poll reach the API? */
  reachable: boolean;
}

/** One project's Vercel production-staleness verdict, as the mirror stores it. */
export interface VercelProdStateInput {
  projectName: string;
  stale: boolean;
  detail: string | null;
  sourceUrl: string | null;
  liveUrl: string | null;
}

export interface ObservationStore {
  /** Persist what this poll saw of each platform (configured/reachable) plus the
   *  rolling consecutive-failure streak. */
  recordObservations(observations: PlatformObservationInput[]): Promise<void>;
  /** Replace the Vercel production-staleness mirror with what this read saw; a
   *  project absent from `states` is deleted from the mirror. A no-op on an empty
   *  list — the caller must pass only a COMPLETE read. */
  recordVercelProdStates(states: VercelProdStateInput[]): Promise<void>;
}

// --- maintenance: rollup, retention prune, WAL checkpoint, file snapshot ---

export interface SnapshotOptions {
  /** Overrides the adapter's own connection url; only tests need this. Omit it in
   *  production code — the adapter already knows which file it opened. */
  dbUrl?: string;
  intervalMs?: number;
  keep?: number;
  now?: () => number;
}

export interface MaintenanceStore {
  /** Roll up `metrics_hourly` for the given services' current hour bucket. */
  rollupMetrics(serviceSlugs: string[]): Promise<void>;
  /** Retention prune across every accruing table, WAL-checkpointing when the
   *  adapter has a live connection — see the libsql implementation. */
  runMaintenance(opts?: { maxRows?: number; chunkRows?: number }): Promise<{ deleted: number; done: boolean }>;
  /** VACUUM INTO a rotated on-volume snapshot if the configured interval lapsed.
   *  Uses the adapter's own connection url unless `opts.dbUrl` overrides it. */
  snapshotIfDue(opts?: SnapshotOptions): Promise<{ created: boolean; path?: string }>;
}

// --- device: RFC 8628 device-authorization grants ---------------------------

export type DeviceGrantStatus = 'pending' | 'approved' | 'denied';

/** A `device_authorizations` row, minus the secret columns (`deviceCodeHash`,
 *  `userCodeHash`, `tokenRaw`) — those are write-only/consume-only and never
 *  read back through this shape. */
export interface DeviceGrantRow {
  id: string;
  cliLabel: string;
  status: DeviceGrantStatus;
  createdAt: Date;
  expiresAt: Date;
  lastPollAt: Date | null;
}

export interface DeviceStore {
  /** Delete every grant past its expiry — run opportunistically before minting a
   *  new one so the table never accumulates dead rows. */
  purgeExpired(): Promise<void>;
  /** Insert a freshly-requested grant. */
  create(input: { deviceCodeHash: string; userCodeHash: string; cliLabel: string; expiresAt: Date }): Promise<void>;
  findByDeviceCodeHash(hash: string): Promise<DeviceGrantRow | null>;
  findByUserCodeHash(hash: string): Promise<DeviceGrantRow | null>;
  deleteById(id: string): Promise<void>;
  /** Stamp `lastPollAt` on a still-pending grant. */
  markPolled(id: string): Promise<void>;
  /** Atomically delete an approved grant and hand back its stashed secret — the
   *  single-use consume. Null when the row is gone or was never approved. */
  consumeApproved(id: string): Promise<{ tokenRaw: string; tokenId: string } | null>;
  /** Mark a still-pending grant approved with its minted token, guarded on status
   *  so two racing approvers can't both win. False when the guard didn't match. */
  approve(id: string, patch: { tokenId: string; tokenRaw: string; approvedBy: string }): Promise<boolean>;
  /** Mark a still-pending grant denied, guarded on status. False when it didn't match. */
  deny(id: string): Promise<boolean>;
  /** The role + expiry of a minted token, for the poll response. */
  tokenRoleAndExpiry(tokenId: string): Promise<{ role: 'admin' | 'user'; expiresAt: Date | null } | null>;
}

// --- board: the raw reads behind the deploy/issue fold ----------------------

/** One page of a time-descending source read, with the tie group its LIMIT cut
 *  through re-read in full — see the libsql implementation (`readSourcePage`) for
 *  why a partial instant can never be returned. `floorMs` is null when the page
 *  exhausted the source (nothing older exists). */
export interface SourcePage<T> {
  rows: T[];
  floorMs: number | null;
}

/** One page-query's cursor: read strictly before `atMs` (a stalled page's empty-id
 *  sentinel) or at-or-before it (an ordinary cursor) — null `beforeMs` means "from
 *  the newest row", the first page. */
export interface PageCursor {
  beforeMs: number | null;
  strict: boolean;
  limit: number;
}

export interface BoardStore {
  /** Every monitored endpoint with the columns ownership is resolved from. */
  readRoster(): Promise<RosterEntry[]>;
  /** Every deploy row that has CONCLUDED or is still IN-FLIGHT, one per (platform,
   *  projectName, environment) group — the state projection `binByOutcome` (pure,
   *  stays in board/facts.ts) partitions into verdicts vs. still-changing rows. */
  readDeployOutcomeCandidates(): Promise<DeployFact[]>;
  /** Every deploy inside the activity window owned by `owned`, ungrouped, newest
   *  first, capped at `MAX_ACTIVITY_ROWS` — the Activity feed's deploy log. */
  readDeployEvents(sinceMs: number, owned: OwnedProjects): Promise<DeployFact[]>;
  /** Issues that opened OR closed inside the window, newest-event-first, capped. */
  readIssueEvents(sinceMs: number): Promise<IssueEvent[]>;
  /** Every currently-open issue's target + onset — the ledger continuity floor. */
  readOpenIssueTargets(): Promise<LedgerEntry[]>;
  /** The platform-health mirror, one row per polled platform. */
  readPlatformFacts(): Promise<PlatformFact[]>;
  /** Vercel projects whose live production deploy is stale. */
  readStaleProdFacts(): Promise<StaleProdFact[]>;
  /** Unresolved GlitchTip error groups, newest activity first, capped at `MAX_ERROR_FACTS`. */
  readErrorFacts(): Promise<ErrorFact[]>;

  /** One page of the deploy-activity feed, owned-narrowed. */
  readDeployActivityPage(cursor: PageCursor, owned: OwnedProjects): Promise<SourcePage<DeployFact>>;
  /** One page of issues by `openedAt`, narrowed to `targets`. */
  readIssueOpenedPage(cursor: PageCursor, targets: string[]): Promise<SourcePage<IssueEvent>>;
  /** One page of issues by `resolvedAt`, narrowed to `targets`. */
  readIssueResolvedPage(cursor: PageCursor, targets: string[]): Promise<SourcePage<IssueEvent>>;
}

// --- history: health-check aggregations for /history, /uptime, /response-history --

/** One health-check sample, for the `/history` payload. */
export interface HistoryCheckRow {
  status: string;
  responseTimeMs: number | null;
  statusCode: number | null;
  error: string | null;
  checkedAt: Date;
}

/** One UTC day's check counts, for `/uptime`. */
export interface DailyCountsRow {
  day: string;
  total: number;
  healthy: number;
  degraded: number;
  down: number;
}

export interface HistoryStore {
  /** The newest `checked_at` across ALL history, or null when nothing has ever
   *  been probed — the poller's "last ran" clock. */
  newestCheckAt(): Promise<Date | null>;
  /** One endpoint's samples within the last `hours`, ascending. */
  checksFor(slug: string, hours: number): Promise<HistoryCheckRow[]>;
  /** One endpoint's per-UTC-day counts over the last `days`, ascending. */
  dailyCounts(slug: string, days: number): Promise<DailyCountsRow[]>;
  /** Portfolio-wide response-time sparkline: `buckets` buckets over the last
   *  `hours` (oldest → newest), each the avg response of UP checks, null where no
   *  data — see the libsql implementation for the fine-window/rollup split. */
  responseBuckets(hours: number, buckets: number): Promise<(number | null)[]>;
}

// --- peers: fleet peer polling + snapshot mirror ----------------------------

/** The freshly-polled (or failed) state of one peer, as `PeerStore.upsertSnapshot`
 *  persists it. */
export interface PeerSnapshotUpsert {
  peerId: string;
  fetchedAt: Date;
  payload: unknown;
  overall: string | null;
  reachable: boolean;
  error: string | null;
}

/** A `peer_snapshots` row, as a plain domain type. */
export interface PeerSnapshotRow {
  peerId: string;
  overall: string | null;
  reachable: boolean;
  fetchedAt: Date;
  payload: unknown;
}

export interface PeerStore {
  /** Active peers only — the same roster both the poller and the fleet reader use. */
  listActive(): Promise<PeerRow[]>;
  /** Upsert one peer's freshly-polled (or failed) snapshot, keyed by peerId. */
  upsertSnapshot(row: PeerSnapshotUpsert): Promise<void>;
  /** Every stored peer snapshot, one row per peer. */
  listSnapshots(): Promise<PeerSnapshotRow[]>;
}

// --- telemetry: GlitchTip errors + PostHog analytics trend stores -----------

/** The persisted telemetry streams — one `Store<T>` per stream, named for what
 *  it holds rather than the provider that feeds it (a store outlives its
 *  fetcher). */
export interface TelemetryStore {
  errors: Store<ErrorDTO>;
  analytics: Store<AnalyticsMetricDTO>;
}

// --- composed storage ---------------------------------------------------------

/** Everything a host builds once and threads through `createApp`. Composed from
 *  the concerns above by name — never a grab-bag `db`/`conn` escape hatch. */
export interface Storage {
  config: ConfigStore;
  auth: AuthStore;
  tokens: TokenStore;
  health: HealthStore;
  deploy: DeployStore;
  issues: IssueStore;
  observations: ObservationStore;
  maintenance: MaintenanceStore;
  board: BoardStore;
  history: HistoryStore;
  device: DeviceStore;
  peers: PeerStore;
  telemetry: TelemetryStore;
}
