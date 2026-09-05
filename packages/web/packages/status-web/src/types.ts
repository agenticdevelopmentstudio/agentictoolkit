import type { HealthStatus } from "./lib/health";
import type { OverallStatus } from "./lib/overall";
import type { DeployStatus, BuildPhase, DeployPhase } from "./lib/deploy-status";

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

export interface StatusResponse {
  overall: OverallStatus;
  services: ServiceStatusDTO[];
  checkedAt: string;
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
  status: DeployStatus;          // derived (combinedStatus) — for the Details/KPI views
  buildPhase: BuildPhase | null; // for the activity transcript
  deployPhase: DeployPhase;
  environment: string | null;
  /** The LOGICAL TIER this build belongs to, derived server-side by `deployEnv` (branch
   *  first, then the project name); null when the row is not a deployment of any tier — a
   *  Vercel preview. Render THIS, never `environment`: that one is the provider's promotion
   *  target and reads "production" for every Vercel project, testing fleet included. The
   *  client deliberately owns no copy of the derivation (see board-types.ts). */
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
  /** ISO time the PHASES were last confirmed against provider truth. An in-flight
   *  phase is a claim with a freshness deadline, not a fact — row-model demotes one
   *  whose confirmation is old instead of asserting "building" on nothing. Optional
   *  (older backend / persisted pre-upgrade rows) → createdAt is the floor. */
  phaseConfirmedAt?: string;
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
   *  Drives the "missing env" error bar. Omitted/empty when nothing is missing. */
  missingEnv?: string[];
  /** The probe got NO HTTP response at all (timeout/abort/connection failure) —
   *  debounced backend-side before it may surface as an error. */
  unreachable?: boolean;
  /** Confirmed-unreachable together with other providers in the same run — the backend
   *  judged it monitor-side connectivity; the banner shows only the Connectivity chip. */
  correlated?: boolean;
}

export interface IntegrationsResponse {
  generatedAt: string;
  overall: CheckState;
  checks: IntegrationCheck[];
}
