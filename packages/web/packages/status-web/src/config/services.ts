import type { HealthStatus } from "../lib/health";

export type EnvKey = "production" | "staging" | "testing";
export type ServiceKind = "frontend" | "admin" | "health" | "custom";

export interface ServiceEndpoint {
  slug: string;        // unique, stable
  group: string;       // section header
  name: string;        // product/service name
  environment: EnvKey;
  url: string;
  kind: ServiceKind;
  expectedStatus: number;
  // Optional seed-only hint for the explicit deploy-target wiring. Left unset here
  // so seeded endpoints start with no project; the real (platform, project) is set
  // per endpoint in the Configure UI (the source of truth), never guessed.
  platform?: "vercel" | "railway" | "cloudflare";
  deployProject?: string;
}

export const ENV_ORDER: EnvKey[] = ["production", "staging", "testing"];

// Helper: derive prod/staging/testing URLs from a production host using the
// repo convention (prepend `testing.` / `staging.` to the production host).
function envHost(host: string, env: EnvKey): string {
  if (env === "production") return host;
  return `${env === "staging" ? "staging" : "testing"}.${host}`;
}

function envUrls(
  opts: {
    group: string;
    name: string;
    baseSlug: string;
    host: string;          // production host, no scheme
    envs: EnvKey[];
    kind: ServiceKind;
    path?: string;         // appended (e.g. "/api/health")
    expectedStatus?: number;
  },
): ServiceEndpoint[] {
  const { group, name, baseSlug, host, envs, kind, path = "", expectedStatus = 200 } = opts;
  return envs.map((environment) => ({
    slug: `${baseSlug}-${environment}`,
    group,
    name,
    environment,
    url: `https://${envHost(host, environment)}${path}`,
    kind,
    expectedStatus,
  }));
}

const ALL: EnvKey[] = ["production", "staging", "testing"];
const PS: EnvKey[] = ["production", "staging"];
const P: EnvKey[] = ["production"];

const ADH = "Agentic Developer Hub";
const OTHER = "Other Products";
const TEMPORAL = "Temporal";
const OLYLO = "Olylo";

export const ACTIVE_SERVICES: ServiceEndpoint[] = [
  // --- Agentic Developer Hub ---
  ...envUrls({ group: ADH, name: "App", baseSlug: "adh-app", host: "agenticdeveloperhub.com", envs: ALL, kind: "frontend" }),
  ...envUrls({ group: ADH, name: "Admin", baseSlug: "adh-admin", host: "admin.agenticdeveloperhub.com", envs: ALL, kind: "admin" }),
  ...envUrls({ group: ADH, name: "API Docs", baseSlug: "adh-api", host: "api.agenticdeveloperhub.com", envs: ALL, kind: "frontend" }),
  ...envUrls({ group: ADH, name: "MCP", baseSlug: "adh-mcp", host: "mcp.agenticdeveloperhub.com", envs: ALL, kind: "custom" }),
  ...envUrls({ group: ADH, name: "Docs", baseSlug: "adh-docs", host: "docs.agenticdeveloperhub.com", envs: PS, kind: "frontend" }),
  ...envUrls({ group: ADH, name: "Status", baseSlug: "adh-status", host: "status.agenticdeveloperhub.com", envs: PS, kind: "frontend" }),
  ...envUrls({ group: ADH, name: "Backend", baseSlug: "adh-backend", host: "backend.agenticdeveloperhub.com", envs: ALL, kind: "health", path: "/health" }),

  // --- Supplementary ADH backend checks. The data + MCP API consolidated back
  //     onto the hub apex (api./mcp.agenticdeveloperhub.com); MCP is already
  //     covered by `adh-mcp` above, so only the data-API /health probe and the
  //     Scalar apidocs frontend remain here. Seeded production-only; the runtime
  //     config also tracks the staging/testing apidocs hosts. The API root
  //     redirects browsers to the docs site, so the data API is health-checked
  //     at /health (always JSON 200). ---
  ...envUrls({ group: ADH, name: "API Docs (Scalar)", baseSlug: "storage-apidocs", host: "apidocs.agenticdeveloperhub.com", envs: P, kind: "frontend" }),
  ...envUrls({ group: ADH, name: "Data API", baseSlug: "storage-api", host: "api.agenticdeveloperhub.com", envs: P, kind: "health", path: "/health" }),

  // --- Olylo --- (olylo.ai apex; staging.olylo.ai follows the convention)
  ...envUrls({ group: OLYLO, name: "Olylo", baseSlug: "olylo", host: "olylo.ai", envs: PS, kind: "frontend" }),

  // --- Temporal (Cloudflare) ---
  ...envUrls({ group: TEMPORAL, name: "Temporal", baseSlug: "temporal-today", host: "temporal.today", envs: P, kind: "frontend" }),
  ...envUrls({ group: TEMPORAL, name: "Temporal Landing", baseSlug: "temporal-company", host: "temporal.company", envs: P, kind: "frontend" }),
  ...envUrls({ group: TEMPORAL, name: "Temporal Admin", baseSlug: "temporal-admin", host: "admin.temporal.today", envs: P, kind: "admin" }),

  // --- Other Products (production only) ---
  ...envUrls({ group: OTHER, name: "Mike Fullerton", baseSlug: "mikefullerton", host: "mikefullerton.com", envs: P, kind: "frontend" }),
  ...envUrls({ group: OTHER, name: "Persona Registry", baseSlug: "persona-registry", host: "agenticpersonaregistry.com", envs: P, kind: "frontend" }),
  ...envUrls({ group: OTHER, name: "Developer Team", baseSlug: "dev-team", host: "agenticdeveloperteam.com", envs: P, kind: "frontend" }),
  ...envUrls({ group: OTHER, name: "Developer Projects", baseSlug: "dev-projects", host: "agenticdeveloperprojects.com", envs: P, kind: "frontend" }),
  ...envUrls({ group: OTHER, name: "Developer Cookbook", baseSlug: "cookbook", host: "agenticdevelopercookbook.com", envs: P, kind: "frontend" }),
  ...envUrls({ group: OTHER, name: "Developer Toolkit", baseSlug: "toolkit", host: "agenticdevelopertoolkit.com", envs: P, kind: "frontend" }),
];

// NOTE: this list is now ONLY a one-time SEED for the DB-backed monitoring config
// (see db/config.ts seedConfigFromActiveServices). The status site reads what to
// monitor from the config, and correlates deploys to endpoints by live host — so
// there is no hand-maintained service→project map here anymore.

export type { HealthStatus };
