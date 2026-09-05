import type { HealthStatus } from "./health";
import type { OverallStatus } from "./overall";
import type { DeployStatus, BuildPhase, DeployPhase } from "./deploy-status";

export type { HealthStatus, OverallStatus, DeployStatus };

export interface ServiceStatusDTO {
  slug: string;
  group: string;
  name: string;
  url: string;
  environment: string;
  platform: string | null;      // explicit deploy target (correlation key)
  deployProject: string | null;
  status: HealthStatus | "unknown";
  responseTimeMs: number | null;
  statusCode: number | null;
  error: string | null;
  lastCheckedAt: string | null;
}

export interface UptimeDay {
  day: string;
  status: HealthStatus;
  uptimePercent: number | null;
}
export interface UptimeService {
  slug: string;
  name: string;
  uptimePercent: number | null;
  totalChecks: number;
  daily: UptimeDay[];
}
export interface UptimeResponse {
  services: UptimeService[];
  days: number;
}

export interface DeploymentDTO {
  id: string;
  platform: string;
  projectName: string;
  /**
   * The provider's immutable project id, when the row has one. ON THE WIRE because a
   * board target's identity segment is `providerProjectId ?? projectName`
   * (`entryIdentity`), so a consumer holding a target cannot correlate it to a deployment
   * by name alone — after an upstream rename, or simply after id adoption, the name in
   * the target and the name on the row are different strings. The `adh-status` CLI's
   * "show me the failing build's log" path matched on `projectName` and silently found
   * nothing for every Vercel and Railway target once ids were adopted.
   */
  providerProjectId: string | null;
  status: DeployStatus;          // derived (combinedStatus) — for the Details/KPI views
  buildPhase: BuildPhase | null; // for the activity transcript
  deployPhase: DeployPhase;
  environment: string | null;
  /**
   * The LOGICAL TIER this build belongs to — `deployEnv` of the branch, then the project
   * name — or null when the row is not a deployment of any tier (a Vercel preview).
   *
   * Beside `environment` rather than replacing it, because they answer different
   * questions: `environment` is the PROVIDER'S promotion target, "production" for every
   * Vercel project, and the preview gate, `boardTargetKey` and the SQL grouping all need it
   * raw. Derived HERE so no client has to: the panel that rendered `environment` straight
   * badged the whole testing fleet PROD, and the only client-side fix is a second copy of
   * `deployEnv` — the duplicate whose drift caused that divergence in the first place.
   */
  tier: string | null;
  commitHash: string | null;
  commitMessage: string | null;
  branch: string | null;
  commitRepo: string | null; // "owner/name" — to build a GitHub commit link
  url: string | null;
  // Provider failure reason for a FAILED deploy (Vercel errorMessage / Railway
  // build-log tail); null otherwise. Rendered verbatim in the details pane.
  errorText: string | null;
  liveHost: string | null; // resolved live custom domain host (correlation key + live url)
  createdAt: string;
  /** ISO time the PHASES were last confirmed against provider truth (the row's
   *  fetched_at / a webhook's receipt). An IN-FLIGHT phase is a claim with a
   *  freshness deadline, not a fact — the client demotes one whose confirmation
   *  is old instead of asserting "building" on nothing (see row-model). */
  phaseConfirmedAt: string;
}

export interface HistoryCheck {
  status: HealthStatus | "unknown";
  responseTimeMs: number | null;
  statusCode: number | null;
  error: string | null;
  checkedAt: string;
}

export interface HistoryResponse {
  service: string;
  hours: number;
  checks: HistoryCheck[];
}

export type CheckState = "ok" | "warn" | "error";

export interface IntegrationCheck {
  id: string;
  label: string;
  configured: boolean;
  ok: boolean;
  state: CheckState;
  detail: string;
  /** Expected env vars this check found UNSET (named exactly, e.g. CLOUDFLARE_ACCOUNT_ID).
   *  Drives the "missing env" error bar so a blank var can't fail silently. Omitted/empty
   *  when nothing is missing. */
  missingEnv?: string[];
  /** The probe got NO HTTP response at all (timeout/abort/connection failure). Such a
   *  failure may be monitor-side, so it is debounced across runs before surfacing as an
   *  error (see self-check-stability). A real HTTP error (401/5xx) is never tagged. */
  unreachable?: boolean;
  /** Confirmed-unreachable together with other providers in the same run — treated as
   *  monitor-side connectivity; the banner collapses these into one Connectivity chip. */
  correlated?: boolean;
}

export interface IntegrationsResponse {
  generatedAt: string;
  overall: CheckState;
  checks: IntegrationCheck[];
}

