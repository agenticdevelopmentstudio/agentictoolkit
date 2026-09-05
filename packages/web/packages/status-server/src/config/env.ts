import { STATUS_CREDENTIAL_NAMES, type StatusConfig, type StatusCredentialName } from "./port";

/** A read-only view of environment variables — `process.env` in a host, a plain
 *  object in tests. Only ever read through `env[name]`. */
export type EnvSource = Readonly<Record<string, string | undefined>>;

const list = (raw: string | undefined, lower = false): string[] =>
  (raw ?? "")
    .split(",")
    .map((s) => (lower ? s.trim().toLowerCase() : s.trim()))
    .filter(Boolean);

const optional = (raw: string | undefined): string | null => (raw ? raw : null);

const positiveNumber = (raw: string | undefined): number | null => {
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? n : null;
};

/**
 * Build a StatusConfig from environment variables — the adapter for hosts that are
 * configured the twelve-factor way. The variable names are the ones websites/main's
 * `.env.example` documents; nothing else in this package knows them.
 *
 * Every field is a getter over `env`, so the value is read when it is USED, not when
 * the config is built: a host constructs one config at module load, and tests that set
 * `process.env` afterwards still see their value. Structured clone (workerData) and
 * JSON both invoke getters, so a snapshot crosses to the monitor worker as plain data.
 *
 * SEC-M5: AUTH_DISABLED (bypasses auth → admin tier) and COOKIE_INSECURE (drops the Secure
 * cookie flag) are local-dev / e2e escape hatches ONLY. Refuse to boot with either set in
 * production, so an accidental prod env can't silently grant anonymous admin or ship an
 * insecure session cookie.
 */
export function envConfig(env: EnvSource): StatusConfig {
  if (env.NODE_ENV === "production" && (env.AUTH_DISABLED === "1" || env.COOKIE_INSECURE === "1")) {
    throw new Error("refusing to boot: AUTH_DISABLED / COOKIE_INSECURE must not be set when NODE_ENV=production");
  }
  return {
    get port() {
      return Number(env.PORT ?? 3000);
    },
    get appVersion() {
      return env.APP_VERSION ?? "0.0.0";
    },
    get gitCommitSha() {
      return optional(env.RAILWAY_GIT_COMMIT_SHA);
    },
    get probeIntervalSeconds() {
      return Number(env.PROBE_INTERVAL_SECONDS ?? 60);
    },
    get deploySyncSeconds() {
      return positiveNumber(env.DEPLOY_SYNC_SECONDS);
    },
    get corsAllowedHosts() {
      return list(env.CORS_ALLOWED_HOSTS);
    },
    get mcpAllowedHosts() {
      return list(env.MCP_ALLOWED_HOSTS);
    },
    get peerToken() {
      return env.PEER_TOKEN ?? "";
    },
    /**
     * Qualified with the platform's own environment name whenever that is not production.
     * MONITOR_LABEL is hand-set per environment and nothing stops two environments from
     * carrying the same one: prod and testing both said `adh-status-railway`, so the testing
     * board introduced itself as the production monitor, and any fleet listing both showed
     * two identically-named cards with no way to tell which was which. The platform already
     * knows which environment this is — requiring an operator to encode it a second time is
     * a duplication that only ever gets noticed once it is already wrong.
     *
     * A label that already names its environment is left alone, so an explicitly suffixed
     * MONITOR_LABEL never becomes `…-testing (testing)`.
     */
    get monitorLabel() {
      const label = env.MONITOR_LABEL?.trim() || "this monitor";
      const name = (env.RAILWAY_ENVIRONMENT_NAME ?? "").trim().toLowerCase();
      if (!name || name === "production") return label;
      return label.toLowerCase().includes(name) ? label : `${label} (${name})`;
    },
    get authDisabled() {
      return env.AUTH_DISABLED === "1";
    },
    get cookieSecure() {
      return env.COOKIE_INSECURE !== "1";
    },
    get adminEmails() {
      return list(env.ADMIN_EMAILS, true);
    },
    /** Prefers PUBLIC_BASE_URL; falls back to Railway's injected public domain. */
    get publicBaseUrl() {
      const explicit = env.PUBLIC_BASE_URL;
      const railway = env.RAILWAY_PUBLIC_DOMAIN;
      const raw = explicit || (railway ? `https://${railway}` : "");
      return raw.replace(/\/$/, "");
    },
    get github() {
      return {
        clientId: env.GITHUB_OAUTH_CLIENT_ID ?? "",
        clientSecret: env.GITHUB_OAUTH_CLIENT_SECRET ?? "",
        fetchTimeoutMs: positiveNumber(env.GITHUB_FETCH_TIMEOUT_MS),
      };
    },
    get webhooks() {
      return { vercel: optional(env.VERCEL_WEBHOOK_SECRET), railway: optional(env.RAILWAY_WEBHOOK_SECRET) };
    },
    get heartbeatUrl() {
      return optional(env.HEARTBEAT_URL);
    },
    get alertWebhookUrl() {
      return optional(env.ALERT_WEBHOOK_URL);
    },
    /**
     * Which GlitchTip projects may mint a board Problem — `GLITCHTIP_PROJECTS`, comma
     * separated. NULL when unset, meaning "every project the org returns".
     *
     * The lever exists because the poll is ORGANIZATION-wide
     * (`/api/0/organizations/<org>/issues/`) while every other Problem rule is gated by site
     * ownership: `issue-sources.ts` states it plainly — a project no site monitors is never
     * enumerated and never a Problem, so a non-site platform project cannot manufacture a
     * phantom. Errors have no site to hang that gate on, so this is the gate. Point a second
     * product, a scratch project, or GlitchTip's own internal project at the same org and,
     * unset, one `error`-level event opens a row on the board and pages on-call.
     *
     * Defaulting to "all" rather than "none" is deliberate: a fleet with one GlitchTip
     * project (today's) needs no configuration to work, and the allowlist is what a second
     * project makes necessary rather than what the first one waits for.
     * An env var set to `,,` is a mistake, not an instruction to silence the feature.
     */
    get glitchtipProjects() {
      const raw = env.GLITCHTIP_PROJECTS?.trim();
      if (!raw) return null;
      const projects = list(raw);
      return projects.length > 0 ? projects : null;
    },
    get credentials() {
      const out = {} as Record<StatusCredentialName, string | undefined>;
      for (const name of STATUS_CREDENTIAL_NAMES) out[name] = env[name];
      return out;
    },
  };
}
