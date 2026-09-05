import { sqliteTable, integer, text, real, index, uniqueIndex } from "drizzle-orm/sqlite-core";
import { sql } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { inFlightSql } from "../monitor/deploy-status";

// Timestamps are stored as INTEGER unix-seconds (`integer({ mode: "timestamp" })`),
// so Drizzle-typed reads/writes still see JS `Date`s while raw SQL does plain
// integer math (`unixepoch()`, `checked_at / 3600 * 3600`, …). UUID primary keys
// are app-generated (`randomUUID()`) since SQLite has no uuid/gen function.
const now = sql`(unixepoch())`;
const uuid = () => randomUUID();

export const healthChecks = sqliteTable(
  "health_checks",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    serviceSlug: text("service_slug").notNull(),
    status: text("status").notNull(), // 'healthy' | 'degraded' | 'down'
    responseTimeMs: integer("response_time_ms"),
    statusCode: integer("status_code"),
    error: text("error"),
    /**
     * Did the hostname resolve? A false here makes the problem a `dns` one rather than
     * an `http` one. Persisted because the board derives the issue FROM this row; the
     * old reads.ts derivation ran the other way (issue → dnsOk) and cannot survive the
     * ledger becoming an output. Default true is an assumption about pre-existing rows,
     * not a fact — some of them recorded a DNS failure, and which ones is unknowable now
     * (that is the whole reason for the column). Left alone rather than backfilled: these
     * are historical probe rows, and only the newest one per endpoint feeds the fold, so
     * the guess is overwritten by the next poll.
     */
    dnsOk: integer("dns_ok", { mode: "boolean" }).notNull().default(true),
    checkedAt: integer("checked_at", { mode: "timestamp" }).notNull().default(now),
  },
  (t) => [
    index("idx_health_service_checked").on(t.serviceSlug, t.checkedAt),
    // The retention prune seeks by AGE ALONE (`where checked_at < cutoff`), which the
    // composite above cannot serve — its leading column is service_slug. Without this the
    // prune full-scans the table it is trying to bound.
    index("idx_health_checked").on(t.checkedAt),
  ],
);

export const metricsHourly = sqliteTable(
  "metrics_hourly",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    serviceSlug: text("service_slug").notNull(),
    hour: integer("hour", { mode: "timestamp" }).notNull(),
    totalChecks: integer("total_checks").notNull(),
    healthyChecks: integer("healthy_checks").notNull(),
    degradedChecks: integer("degraded_checks").notNull(),
    downChecks: integer("down_checks").notNull(),
    avgResponseTimeMs: real("avg_response_time_ms"),
    minResponseTimeMs: integer("min_response_time_ms"),
    maxResponseTimeMs: integer("max_response_time_ms"),
  },
  (t) => [
    uniqueIndex("uniq_metrics_service_hour").on(t.serviceSlug, t.hour),
    // The retention prune seeks by AGE ALONE (`where hour < cutoff`); the unique
    // index leads with service_slug and cannot serve that, so without this the
    // prune's subselect scans the table it is trying to bound (same rationale as
    // idx_health_checked).
    index("idx_metrics_hour").on(t.hour),
  ],
);

export const deployments = sqliteTable(
  "deployments",
  {
    id: text("id").primaryKey(), // 'vc_<uid>' | 'cf_<id>' | 'ry_<id>'
    platform: text("platform").notNull(), // 'vercel' | 'cloudflare-pages' | 'railway'
    projectName: text("project_name").notNull(),
    // The provider's immutable project id (Railway's project.id, Vercel's project id),
    // when the source that produced this row carried one. Nullable: a platform we have
    // not adopted ids for (or a source that never sees the id, e.g. a backfill keyed on
    // name alone) leaves it null, and identity falls back to `project_name`.
    providerProjectId: text("provider_project_id"),
    // Vestigial: the old single DeployStatus. Kept (nullable) so a rolling deploy
    // doesn't break the still-live old code while migrations auto-apply. New code
    // ignores it (status is derived from the phases). Drop in a later migration
    // once every environment is fully cut over to the phase columns.
    status: text("status"),
    buildPhase: text("build_phase"),                             // BuildPhase | null
    deployPhase: text("deploy_phase").notNull().default("none"), // DeployPhase
    environment: text("environment"),
    commitHash: text("commit_hash"),
    commitMessage: text("commit_message"),
    branch: text("branch"),
    commitRepo: text("commit_repo"), // "owner/name" — to build a GitHub commit link
    url: text("url"),
    // The provider's failure reason for a FAILED build/deploy — Vercel's
    // `errorMessage` (prefixed with the failing build step) or a tail of Railway's
    // build logs — fetched ONCE per failed deploy by enrich-deploy-errors and shown
    // verbatim in the details pane so the reason is readable (and copyable) without
    // opening the provider dashboard. Null for healthy/in-progress deploys and for
    // platforms with no build-error concept (Cloudflare Workers, Crunchy).
    errorText: text("error_text"),
    // The project's live custom domain host (e.g. "docs.example.com"),
    // resolved at fetch time from the platform's attached domains. The single key
    // for correlating a deploy to a monitored endpoint (host match) and for the
    // live-url link — replaces the dead DEPLOY_MAP name matching.
    liveHost: text("live_host"),
    createdAt: integer("created_at", { mode: "timestamp" }).notNull(),
    fetchedAt: integer("fetched_at", { mode: "timestamp" }).notNull().default(now),
  },
  (t) => [
    index("idx_deploy_created").on(t.createdAt),
    // The reconcile candidate query runs EVERY fast tick and the expiry sweep every full
    // sync; both filter to in-flight rows by `fetched_at`. Without a partial index that
    // predicate full-scans the (90-day) deployments table on every tick — the same
    // per-tick-cost-grows-with-history trap that took the container down via health_checks.
    // This index holds ONLY in-flight rows (normally near-zero), keyed by fetched_at, so
    // both queries seek a tiny index instead of scanning. Its WHERE is built from the SAME
    // inFlightSql the queries use (literal phase values, no bound params), so it matches
    // textually and SQLite actually picks it up for that OR-predicate.
    index("idx_deploy_inflight").on(t.fetchedAt).where(sql.raw(inFlightSql(""))),
  ],
);

export const issues = sqliteTable(
  "issues",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    target: text("target").notNull(),          // service slug, or "<platform>|<project>|<env>"
    source: text("source").notNull(),          // 'http' | 'vercel' | 'cloudflare-pages' | 'railway'
    name: text("name").notNull(),
    environment: text("environment"),
    severity: text("severity").notNull(),       // critical | major | minor
    state: text("state").notNull(),             // down | degraded | failed
    openedAt: integer("opened_at", { mode: "timestamp" }).notNull().default(now),
    resolvedAt: integer("resolved_at", { mode: "timestamp" }),
    /**
     * WHY this issue closed: `recovered` (observed working again) or `unmonitored` (it
     * stopped being watched — nothing recovered). Only a `recovered` close may become a
     * "[state] resolved" Activity row. NULL for rows resolved before this column existed,
     * and for rows still open: unknown, so the fold claims nothing.
     */
    resolvedReason: text("resolved_reason"),
    statusCode: integer("status_code"),
    detail: text("detail"),
    sourceUrl: text("source_url"),
    liveUrl: text("live_url"),
    // Commit that produced the observed deploy failure — mirrors `deployments`, so
    // an issue row can render the same clickable GitHub commit link the activity
    // feed does. Null for http/dns/stale issues (no associated commit).
    commitHash: text("commit_hash"),
    commitMessage: text("commit_message"),
    commitRepo: text("commit_repo"), // "owner/name" — to build a GitHub commit link
    updatedAt: integer("updated_at", { mode: "timestamp" }).notNull().default(now),
  },
  (t) => [
    uniqueIndex("uniq_open_issue_per_target").on(t.target).where(sql`resolved_at is null`),
    index("idx_issue_resolved").on(t.resolvedAt),
    index("idx_issue_source").on(t.source),
    // The activity HISTORY read pages back across the full 90-day retention, ordered by
    // opened_at. Without this it is a full scan of a table that grows with every incident
    // — the per-request-cost-grows-with-history trap that took the container down via
    // health_checks, and the same reason idx_deploy_inflight exists on deployments.
    index("idx_issue_opened").on(t.openedAt),
  ],
);

// ---------------------------------------------------------------------------
// Monitoring config (status-local; replaces the hard-coded ACTIVE_SERVICES list).
// Group → Site → Endpoint, mirroring the backend `monitored_sites` model (so the
// hub's editor UI can be reused), plus `environment` on the endpoint which the
// status badges need. Editable via the in-app "Configure" dialog. Unauthenticated
// for now — gate later. `ACTIVE_SERVICES` is the one-time seed.
//
// FK cascades are declared for documentation/intent, but libSQL over HTTP does
// not enforce foreign keys, so deleteGroup/deleteSite cascade in application code
// (see db/config.ts) — don't rely on ON DELETE CASCADE firing here.
// ---------------------------------------------------------------------------

export const siteGroups = sqliteTable(
  "site_groups",
  {
    id: text("id").primaryKey().$defaultFn(uuid),
    slug: text("slug").notNull(),
    name: text("name").notNull(),
    retentionDays: integer("retention_days").notNull().default(14),
    createdAt: integer("created_at", { mode: "timestamp" }).notNull().default(now),
    updatedAt: integer("updated_at", { mode: "timestamp" }).notNull().default(now),
  },
  (t) => [uniqueIndex("uniq_site_group_slug").on(t.slug)],
);

export const monitoredSites = sqliteTable(
  "monitored_sites",
  {
    id: text("id").primaryKey().$defaultFn(uuid),
    siteGroupId: text("site_group_id")
      .notNull()
      .references(() => siteGroups.id, { onDelete: "cascade" }),
    slug: text("slug").notNull(),
    name: text("name").notNull(),
    createdAt: integer("created_at", { mode: "timestamp" }).notNull().default(now),
    updatedAt: integer("updated_at", { mode: "timestamp" }).notNull().default(now),
  },
  (t) => [uniqueIndex("uniq_site_group_site_slug").on(t.siteGroupId, t.slug)],
);

export const monitoredEndpoints = sqliteTable(
  "monitored_endpoints",
  {
    id: text("id").primaryKey().$defaultFn(uuid),
    siteId: text("site_id")
      .notNull()
      .references(() => monitoredSites.id, { onDelete: "cascade" }),
    url: text("url").notNull(),
    kind: text("kind").notNull().default("http"),
    environment: text("environment"), // production | staging | testing | null
    // Explicit deploy-target wiring: which hosting platform + project deploys the
    // URL this endpoint monitors. The correlation key (deploy <-> endpoint) — null
    // = a health-only endpoint not tied to any deploy project.
    platform: text("platform"), // vercel | railway | cloudflare | null
    deployProject: text("deploy_project"), // the project/worker name on that platform
    // The provider's immutable project id, learned from a deploy whose NAME already
    // matched this endpoint (see `learnDeployProjectIds`) — never entered directly by
    // an operator's own click except via a hand-authored config write. Null until
    // learned; once set it is never overwritten automatically, so an operator's own
    // value always wins.
    deployProjectId: text("deploy_project_id"),
    // Operator opt-out, surfaced as the editor's "Automatically Configure" checkbox
    // (checked = this flag OFF): suppresses the "no deploy project configured" warning
    // for a deploy-backed endpoint the operator has decided needs no project wiring, AND
    // keeps Auto Configure's endpoint axis from wiring it behind their back.
    ignoreProjectWarning: integer("ignore_project_warning", { mode: "boolean" }).notNull().default(false),
    expectedStatus: integer("expected_status").notNull().default(200),
    // Optional content check: the response body must contain this string, else
    // the endpoint is down (see ConfiguredEndpoint.expectBody).
    expectBody: text("expect_body"),
    // DNS-resolution check toggles — which record types the probe queries when
    // verifying the host resolves (A / AAAA / CNAME). Default ON to preserve the
    // historic "resolves via any of A/AAAA/CNAME" behaviour; all three off skips
    // the DNS check entirely (see monitor/probe.ts resolveDns).
    dnsCheckA: integer("dns_check_a", { mode: "boolean" }).notNull().default(true),
    dnsCheckAaaa: integer("dns_check_aaaa", { mode: "boolean" }).notNull().default(true),
    dnsCheckCname: integer("dns_check_cname", { mode: "boolean" }).notNull().default(true),
    // NOTE: there is deliberately no "how long has this host been unresolvable" clock here
    // (a `dns_failing_since` column existed in 0010 and is dropped in 0011). DNS decides
    // nothing about removal: an unresolvable name explains why an endpoint is DOWN, and a
    // broken site's monitor is the alarm, not the mess. What gets removed is decided from
    // the platform inventory alone — see `endpointsClaimedByNothing`.
    checkIntervalSeconds: integer("check_interval_seconds").notNull().default(60),
    // The site's MASTER monitoring switch (the editor's "Monitoring enabled" checkbox).
    // Off = paused: no HTTP probe, no DNS check, nothing on the board, and no
    // auto-configure nagging — but the row is still CONFIGURED, so the deploy project it
    // names stays claimed (see `listEndpointsForWiring`) and no second monitor is added.
    isActive: integer("is_active", { mode: "boolean" }).notNull().default(true),
    /**
     * Per-signal monitoring switches, independent of the `isActive` master switch.
     * Turning one off removes exactly that signal's problems from the board (Requirement
     * A) while leaving the other standing. Default true so every existing row keeps the
     * behaviour it had before the columns existed.
     */
    monitorHttp: integer("monitor_http", { mode: "boolean" }).notNull().default(true),
    monitorDeploys: integer("monitor_deploys", { mode: "boolean" }).notNull().default(true),
    createdAt: integer("created_at", { mode: "timestamp" }).notNull().default(now),
    updatedAt: integer("updated_at", { mode: "timestamp" }).notNull().default(now),
  },
  (t) => [index("idx_endpoint_site").on(t.siteId)],
);

// Deploy-platform tables (deployIntegrations, deployProjectMeta,
// ignoredDeployProjects) now live in the shared @agentic-toolkit/deploy-platform
// core. Re-exported here so drizzle-kit + the relational query builder still see
// them via db/schema, and every existing importer keeps its `../db/schema` path.
export {
  deployIntegrations,
  deployProjectMeta,
  ignoredDeployProjects,
  type DeployIntegrationRow,
  type DeployProjectMetaRow,
  type IgnoredDeployProjectRow,
} from "@agentic-toolkit/deploy-platform/schema";

// Per-platform poll health — the persisted streak that DEBOUNCES the
// `platform-health|<source>` issue. A single transient failed poll (a one-off
// 429/timeout from a provider API) shouldn't open + auto-resolve an "unreachable"
// issue within one cycle, so we only open after the failure persists
// PLATFORM_UNREACHABLE_POLLS consecutive polls. One row per source;
// `consecutiveFailures` resets to 0 on any reachable poll. Serverless crons are a
// fresh process each tick, so this streak can't live in memory — it's persisted
// here. (If this table hasn't been migrated onto a DB yet, recordPlatformObservations
// leaves the column unwritten and the fold sees no streak — no debounce.)
export const platformHealthState = sqliteTable("platform_health_state", {
  source: text("source").primaryKey(), // 'vercel' | 'cloudflare-pages' | 'railway'
  consecutiveFailures: integer("consecutive_failures").notNull().default(0),
  /**
   * Do we poll this platform at all — an active integration with a token? An
   * unconfigured platform is never "unreachable"; "not configured" is not "broken".
   * Default true is a GUESS about pre-existing rows, not a fact: `setPlatformFailureCount`
   * wrote a row for every observation regardless of `configured`, so an unconfigured
   * platform may well have one. The guess is benign — one poll overwrites it, and until
   * then it can only make the fold judge a platform it should have skipped, which the
   * streak (0 for anything never failing) already keeps quiet.
   */
  configured: integer("configured", { mode: "boolean" }).notNull().default(true),
  /**
   * Did the most recent poll reach the provider's API? Default true is wrong for exactly
   * one pre-existing row: a platform mid-outage. The migration therefore backfills
   * `reachable = false WHERE consecutive_failures > 0` — otherwise the board would suppress
   * a live platform-health problem until the next poll.
   */
  reachable: integer("reachable", { mode: "boolean" }).notNull().default(true),
  updatedAt: integer("updated_at", { mode: "timestamp" }).notNull().default(now),
});

/**
 * The newest production-promotion verdict per Vercel project, as OBSERVED by the poll.
 * `stale` = the live production deployment errored, or a newer READY production build
 * was never promoted (see evaluateProdStaleness). One row per project, replaced whole on
 * every complete read; the fold decides whether a stale project is a Problem (it is not,
 * unless a live roster entry owns it and no failed-deploy problem already covers it).
 */
export const vercelProdState = sqliteTable("vercel_prod_state", {
  projectName: text("project_name").primaryKey(),
  stale: integer("stale", { mode: "boolean" }).notNull().default(false),
  detail: text("detail"),
  sourceUrl: text("source_url"),
  liveUrl: text("live_url"),
  updatedAt: integer("updated_at", { mode: "timestamp" }).notNull().default(now),
});

// --- appended: peer configuration + cached peer snapshots (fleet view) ---

// Peer monitors this instance aggregates into its fleet view. Because auth is
// per-instance, each row carries the token to present to THAT peer (its PEER_TOKEN).
export const peers = sqliteTable(
  'peers',
  {
    id: text('id').primaryKey().$defaultFn(uuid),
    label: text('label').notNull(),
    baseUrl: text('base_url').notNull(), // e.g. https://status-b.example.com (no trailing slash)
    token: text('token'), // PEER_TOKEN to present to this peer; null = peer's reads are public
    isActive: integer('is_active', { mode: 'boolean' }).notNull().default(true),
    createdAt: integer('created_at', { mode: 'timestamp' }).notNull().default(now),
    updatedAt: integer('updated_at', { mode: 'timestamp' }).notNull().default(now),
  },
  (t) => [uniqueIndex('uniq_peer_base_url').on(t.baseUrl)],
);

// Latest snapshot fetched from each peer (one row per peer). Survives restarts so
// the fleet view is populated before the first post-boot cycle completes.
export const peerSnapshots = sqliteTable('peer_snapshots', {
  peerId: text('peer_id')
    .primaryKey()
    .references(() => peers.id, { onDelete: 'cascade' }),
  payload: text('payload', { mode: 'json' }), // the peer's /snapshot body, or null when unreachable
  overall: text('overall'), // 'healthy' | 'degraded' | 'down' | null
  reachable: integer('reachable', { mode: 'boolean' }).notNull().default(false),
  error: text('error'),
  fetchedAt: integer('fetched_at', { mode: 'timestamp' }).notNull().default(now),
});

// ---------------------------------------------------------------------------
// Production runtime visibility (Layer 4): errors + analytics, pulled into the
// single dashboard. The status backend is the one pane; the heavy processing
// lives in the engines (GlitchTip for errors, PostHog for analytics) and these
// tables hold the polled summaries — deep-dive clicks through via `permalink`.
// On THIS backend they live in the same embedded SQLite/libSQL DB as everything
// else (no separate Turso cloud connection); the scheduler cycle accrues them.
// ---------------------------------------------------------------------------

// One row per GlitchTip issue (a grouped error), upserted by its stable issue id.
// GlitchTip does the source-maps + grouping; we store the summary it returns.
export const errors = sqliteTable(
  "errors",
  {
    id: text("id").primaryKey().$defaultFn(uuid),
    issueKey: text("issue_key").notNull(), // GlitchTip issue id — stable across polls
    project: text("project").notNull(), // GlitchTip project slug (≈ site)
    title: text("title").notNull(),
    culprit: text("culprit"),
    level: text("level"), // error | warning | info | fatal
    count: integer("count").notNull().default(0), // total occurrences
    userCount: integer("user_count").notNull().default(0), // distinct users affected
    firstSeen: integer("first_seen", { mode: "timestamp" }),
    lastSeen: integer("last_seen", { mode: "timestamp" }),
    permalink: text("permalink"), // deep-dive link into GlitchTip
    resolved: integer("resolved", { mode: "boolean" }).notNull().default(false),
    fetchedAt: integer("fetched_at", { mode: "timestamp" }).notNull().default(now),
  },
  (t) => [uniqueIndex("uniq_error_issue").on(t.issueKey), index("idx_error_last_seen").on(t.lastSeen)],
);

// Periodic snapshots of headline analytics KPIs (anonymous, aggregate) pulled
// from PostHog — one row per (metric, window, scope) per poll, so the dashboard
// shows the latest value AND its trend over time (the status DB is the trend store).
export const analyticsMetrics = sqliteTable(
  "analytics_metrics",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    metric: text("metric").notNull(), // 'pageviews' | 'visitors'
    window: text("window").notNull(), // '24h' | '7d'
    scope: text("scope").notNull().default("all"), // 'all' or a site slug
    value: integer("value").notNull(),
    capturedAt: integer("captured_at", { mode: "timestamp" }).notNull().default(now),
  },
  (t) => [
    index("idx_analytics_metric_time").on(t.metric, t.window, t.scope, t.capturedAt),
    // Age-only seek for the retention prune (capturedAt is LAST in the composite
    // above, which cannot serve `where captured_at < cutoff`).
    index("idx_analytics_captured").on(t.capturedAt),
  ],
);

// --- User auth (self-enclosed; no central auth server) -----------------------
// A real user-account system replaces the old shared-secret VIEW/ADMIN tokens.
// `passwordHash` is null for OAuth-only accounts; `githubId` is null for
// password-only ones. New accounts start `pending` (no dashboard access) until
// an admin promotes them — except emails in ADMIN_EMAILS, auto-promoted on
// first signup/login so there is always an approver.
export const users = sqliteTable(
  "users",
  {
    id: text("id").primaryKey().$defaultFn(uuid),
    email: text("email").notNull(), // stored lower-cased by callers
    passwordHash: text("password_hash"), // null for OAuth-only accounts
    githubId: text("github_id"), // null for password-only accounts
    displayName: text("display_name").notNull(),
    role: text("role").notNull().default("pending"), // 'pending' | 'viewer' | 'admin'
    createdAt: integer("created_at", { mode: "timestamp" }).notNull().default(now),
  },
  (t) => [uniqueIndex("uniq_user_email").on(t.email), uniqueIndex("uniq_user_github").on(t.githubId)],
);

// Opaque server sessions: the `status_auth` cookie holds a random token; only its
// sha256 is persisted here, so a DB leak can't reconstruct live cookies.
export const sessions = sqliteTable(
  "sessions",
  {
    id: text("id").primaryKey().$defaultFn(uuid),
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    tokenHash: text("token_hash").notNull(),
    expiresAt: integer("expires_at", { mode: "timestamp" }).notNull(),
    createdAt: integer("created_at", { mode: "timestamp" }).notNull().default(now),
  },
  (t) => [uniqueIndex("uniq_session_token").on(t.tokenHash), index("idx_session_user").on(t.userId)],
);

// Opaque API bearer tokens (`sts_<64 hex>`) for CLI / MCP / machine callers — the
// non-cookie auth channel. The raw value is shown exactly once at mint; only its
// sha256 is persisted (token_hash), so a DB leak can't reconstruct a live token.
// `prefix` keeps the first chars for human-readable listing. `role` sets the
// token's tier (admin | user → admin | view); `kind` distinguishes an explicitly
// minted token from a later device-flow token. `created_by` is the SESSION user
// who minted it (tokens cannot mint tokens). Soft-revoked via `revoked_at`.
export const apiTokens = sqliteTable(
  "api_tokens",
  {
    id: text("id").primaryKey().$defaultFn(() => crypto.randomUUID()),
    name: text("name").notNull(),
    role: text("role").$type<"admin" | "user">().notNull(),
    kind: text("kind").$type<"minted" | "device">().notNull().default("minted"),
    prefix: text("prefix").notNull(), // raw.slice(0, 12), display only
    tokenHash: text("token_hash").notNull(),
    createdBy: text("created_by")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    createdAt: integer("created_at", { mode: "timestamp" }).notNull().$defaultFn(() => new Date()),
    lastUsedAt: integer("last_used_at", { mode: "timestamp" }),
    expiresAt: integer("expires_at", { mode: "timestamp" }),
    revokedAt: integer("revoked_at", { mode: "timestamp" }),
  },
  (t) => [uniqueIndex("uniq_api_token_hash").on(t.tokenHash)],
);

// Device authorization grants (RFC 8628-shaped CLI/device flow). A CLI POSTs
// /auth/device to get a short `user_code` + long `device_code`; the human opens
// the `verification_uri` in a browser, an approver (any signed-in viewer/admin)
// approves it, and the CLI polling /auth/device/token gets the minted bearer
// exactly once. Only the sha256 of each code is stored (device_code_hash /
// user_code_hash), never the plaintext. `token_raw` is the SOLE deliberate
// exception to hash-only-at-rest: it holds the minted secret ONLY between
// approval and the single successful poll, then the row is deleted (single-use)
// — it is never selected in any list path. Rows are opportunistically reaped on
// TTL (`expires_at`).
export const deviceAuthorizations = sqliteTable(
  "device_authorizations",
  {
    id: text("id").primaryKey().$defaultFn(() => crypto.randomUUID()),
    deviceCodeHash: text("device_code_hash").notNull(),
    userCodeHash: text("user_code_hash").notNull(),
    cliLabel: text("cli_label").notNull().default(""),
    status: text("status").$type<"pending" | "approved" | "denied">().notNull().default("pending"),
    tokenId: text("token_id").references(() => apiTokens.id, { onDelete: "set null" }),
    tokenRaw: text("token_raw"), // held ONLY between approval and the single successful poll, then nulled
    approvedBy: text("approved_by").references(() => users.id, { onDelete: "set null" }),
    createdAt: integer("created_at", { mode: "timestamp" }).notNull().$defaultFn(() => new Date()),
    expiresAt: integer("expires_at", { mode: "timestamp" }).notNull(),
    lastPollAt: integer("last_poll_at", { mode: "timestamp" }),
  },
  (t) => [uniqueIndex("uniq_device_code").on(t.deviceCodeHash), uniqueIndex("uniq_user_code").on(t.userCodeHash)],
);

export type User = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;
export type Session = typeof sessions.$inferSelect;
