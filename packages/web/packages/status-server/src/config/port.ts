// The configuration port. Everything the shared server needs to know about the
// host it runs in arrives through one StatusConfig value that the HOST builds —
// nothing under src/ reads the environment directly. Plain data on purpose: a StatusConfig
// crosses the worker_threads boundary as workerData, so it holds no functions.
//
// `envConfig(env)` (./env.ts) is the adapter for a host that configures itself
// through environment variables, using the same variable names websites/main's
// .env.example documents. A host that keeps its settings elsewhere (a hub's
// tenant record, a secrets manager) builds a StatusConfig by hand.

/**
 * Provider credentials and settings the monitor looks up BY NAME — the platform
 * registry (`routes/config.ts`) and the telemetry self-check (`monitor/integrations.ts`)
 * both report "which setting is missing" to the operator, so the names are part
 * of the contract, not an env-var leak. A host maps its own secret store onto
 * these names; unset entries are `undefined`.
 */
export const STATUS_CREDENTIAL_NAMES = [
  "VERCEL_API_TOKEN",
  "VERCEL_TEAM_ID",
  "CLOUDFLARE_API_TOKEN",
  "CLOUDFLARE_ACCOUNT_ID",
  "RAILWAY_API_TOKEN",
  "CRUNCHY_API_TOKEN",
  "GLITCHTIP_URL",
  "GLITCHTIP_API_TOKEN",
  "GLITCHTIP_ORG",
  "POSTHOG_HOST",
  "POSTHOG_API_KEY",
  "POSTHOG_PROJECT_ID",
] as const;

export type StatusCredentialName = (typeof STATUS_CREDENTIAL_NAMES)[number];

export interface StatusConfig {
  /** TCP port the host serves the API on. */
  readonly port: number;
  /** Reported in /health and the OpenAPI document. */
  readonly appVersion: string;
  /** Git commit the running build was cut from, when the platform tells us. */
  readonly gitCommitSha: string | null;
  /** Endpoint-probe cadence, seconds. */
  readonly probeIntervalSeconds: number;
  /** Explicit override of the heavy deploy-sync cadence, seconds; null derives it — see deploySyncIntervalMs. */
  readonly deploySyncSeconds: number | null;
  /** Origins allowed by the CORS middleware (host names, no scheme). */
  readonly corsAllowedHosts: readonly string[];
  /** Host names the MCP endpoint accepts (DNS-rebinding guard). */
  readonly mcpAllowedHosts: readonly string[];
  /** Shared secret a peer monitor presents to read /snapshot. Empty disables peer reads. */
  readonly peerToken: string;
  /** How this monitor names ITSELF on the fleet board (already environment-qualified). */
  readonly monitorLabel: string;
  /** Dev/e2e escape hatch: every request runs as admin. Never true in production. */
  readonly authDisabled: boolean;
  /** Whether the session cookie carries `Secure`. */
  readonly cookieSecure: boolean;
  /** Emails auto-promoted to admin on first signup/login, lower-cased. */
  readonly adminEmails: readonly string[];
  /** Browser-facing origin (no trailing slash) for OAuth callbacks; empty when unknown. */
  readonly publicBaseUrl: string;
  /** GitHub OAuth app. Empty strings when GitHub login is not configured. */
  readonly github: {
    readonly clientId: string;
    readonly clientSecret: string;
    /** Timeout for GitHub API calls during login, ms; null keeps the code default. */
    readonly fetchTimeoutMs: number | null;
  };
  /** Inbound deploy-webhook secrets; null when that platform's webhook is not wired. */
  readonly webhooks: {
    readonly vercel: string | null;
    readonly railway: string | null;
  };
  /** Outbound heartbeat ping URL (Better Stack style); null disables it. */
  readonly heartbeatUrl: string | null;
  /** Outbound alert webhook URL; null disables alert posting. */
  readonly alertWebhookUrl: string | null;
  /** GLITCHTIP_PROJECTS allowlist; null means every project the org returns. */
  readonly glitchtipProjects: readonly string[] | null;
  /** Provider credentials and settings, by name. See STATUS_CREDENTIAL_NAMES. */
  readonly credentials: Readonly<Record<StatusCredentialName, string | undefined>>;
}

/** How often (ms) the EXPENSIVE deploy-provider poll + peer/telemetry fetch runs,
 *  decoupled from the fast endpoint-probe tick so those provider APIs (each up to the
 *  20s guard) don't starve the HTTP event loop every probe interval. Given the probe
 *  interval (ms) so it can scale with it: defaults to max(5min, 5× the probe interval),
 *  always a multiple of several probe ticks. `deploySyncSeconds` overrides. */
export function deploySyncIntervalMs(config: StatusConfig, probeIntervalMs: number): number {
  const override = config.deploySyncSeconds;
  if (override !== null && Number.isFinite(override) && override > 0) return override * 1000;
  return Math.max(300_000, probeIntervalMs * 5);
}

/**
 * Is GlitchTip wired up — URL, token AND org? All three or nothing: the fetcher needs
 * every one to build a request, so two-of-three is unconfigured, not partly configured.
 *
 * Lives here rather than beside its first caller because it has TWO and they must
 * not drift: `collectTelemetry` uses it to decide whether to poll at all, and
 * `readBoardFacts` to decide whether error Problems may be judged. If those two ever
 * disagreed, the board would judge frozen rows nothing was refreshing.
 */
export function glitchtipConfigured(config: StatusConfig): boolean {
  const c = config.credentials;
  return !!(c.GLITCHTIP_URL && c.GLITCHTIP_API_TOKEN && c.GLITCHTIP_ORG);
}

export function posthogConfigured(config: StatusConfig): boolean {
  const c = config.credentials;
  return !!(c.POSTHOG_HOST && c.POSTHOG_API_KEY && c.POSTHOG_PROJECT_ID);
}

