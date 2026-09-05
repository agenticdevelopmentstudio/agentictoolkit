// Monitoring-config client. Talks to the standalone status BACKEND via the
// frontend's `/api/[...path]` proxy: `/api/config/*` → `BACKEND_URL/config/*`
// (the backend renamed this admin surface from `/monitored-sites/*` to
// `/config/*`). Mirrors the hub's client shape so the editor UI ports cleanly;
// maps siteGroupId↔groupId. Updates are PATCH (the backend + the proxy expose
// PATCH, not PUT). The JSON fetch helper lives in ./req — peers share it.

import { req } from "./req";

// Row types mirror what the STATUS backend's /config/* routes return.
// Typed locally — not against @agentic-toolkit/adh-api-types (that describes the hub's
// OpenAPI surface, which is a different contract). The status backend's schema
// is the source of truth; these shapes are derived from the view interfaces below.
type GroupRow = { id: string; slug: string; name: string; retentionDays: number };
type SiteRow = { id: string; slug: string; name: string; siteGroupId: string };
// EndpointRow: what the backend actually returns (environment/platform/deployProject
// may be absent on older rows; the UI defaults them to null).
type EndpointRow = {
  id: string;
  siteId: string;
  url: string;
  kind: string;
  environment?: string | null;
  platform?: string | null;
  deployProject?: string | null;
  ignoreProjectWarning?: boolean;
  expectedStatus: number;
  expectBody?: string | null;
  dnsCheckA?: boolean;
  dnsCheckAaaa?: boolean;
  dnsCheckCname?: boolean;
  checkIntervalSeconds: number;
  isActive: boolean;
};

export interface SiteGroupView {
  id: string;
  slug: string;
  name: string;
  retentionDays: number;
}

export interface SiteView {
  id: string;
  slug: string;
  name: string;
  groupId: string;
}

export interface EndpointView {
  id: string;
  siteId: string;
  url: string;
  kind: string;
  environment: string | null;
  platform: string | null; // vercel | railway | cloudflare | null (the hosting platform)
  deployProject: string | null; // the project/worker name on that platform
  ignoreProjectWarning: boolean; // operator opt-out: suppress the "no deploy project" warning
  expectedStatus: number;
  /** Optional content check: body must contain this string, else the endpoint is down. */
  expectBody: string | null;
  // DNS-resolution check toggles: which record types the probe queries to confirm
  // the host resolves (A / AAAA / CNAME). All off → the DNS check is skipped.
  dnsCheckA: boolean;
  dnsCheckAaaa: boolean;
  dnsCheckCname: boolean;
  checkIntervalSeconds: number;
  // The site's MASTER monitoring switch (the editor's "Monitoring enabled" checkbox).
  // Off = paused: no probe, no DNS check, nothing on the board, and out of the
  // auto-configure conversation (`endpointConfigStatus` reads it) — but the row is still
  // CONFIGURED, so the deploy project it names stays claimed and gains no second monitor.
  isActive: boolean;
}

export interface IntegrationView {
  id: string;
  platform: string;
  label: string;
  config: Record<string, unknown>;
  tokenEnvVar: string | null;
  isActive: boolean;
}

// The canonical kind list lives in @/lib/endpoint-kinds (shared with the warning
// logic); re-export so existing `from "./monitored-sites"` imports keep working.
export { ENDPOINT_KINDS } from "../lib/endpoint-kinds";
export const ENVIRONMENTS = ["production", "staging", "testing"] as const;
export const PLATFORMS = ["vercel", "railway", "cloudflare", "crunchy"] as const;

const GROUPS = "/api/config/site-groups";
const SITES = "/api/config/sites";
const ENDPOINTS = "/api/config/endpoints";
const INTEGRATIONS = "/api/config/integrations";



export const toGroup = (r: GroupRow): SiteGroupView => ({ id: r.id, slug: r.slug, name: r.name, retentionDays: r.retentionDays });
export const toSite = (r: SiteRow): SiteView => ({ id: r.id, slug: r.slug, name: r.name, groupId: r.siteGroupId });
export const toEndpoint = (r: EndpointRow): EndpointView => ({
  ...r,
  environment: r.environment ?? null,
  platform: r.platform ?? null,
  deployProject: r.deployProject ?? null,
  ignoreProjectWarning: r.ignoreProjectWarning ?? false,
  expectBody: r.expectBody ?? null,
  // Rows created before the toggles existed default every record type on.
  dnsCheckA: r.dnsCheckA ?? true,
  dnsCheckAaaa: r.dnsCheckAaaa ?? true,
  dnsCheckCname: r.dnsCheckCname ?? true,
});

// --- groups -----------------------------------------------------------------
export async function listGroups(): Promise<SiteGroupView[]> {
  return (await req<GroupRow[]>(GROUPS)).map(toGroup);
}
export async function createGroup(body: { name: string; slug: string; retentionDays?: number }): Promise<SiteGroupView> {
  const fields: { name: string; slug: string; retentionDays?: number } = {
    name: body.name,
    slug: body.slug,
    retentionDays: body.retentionDays,
  };
  return toGroup(await req<GroupRow>(GROUPS, { method: "POST", body: JSON.stringify(fields) }));
}
export async function updateGroup(id: string, body: { name?: string; slug?: string; retentionDays?: number }): Promise<SiteGroupView> {
  const fields: { name?: string; slug?: string; retentionDays?: number } = {
    name: body.name,
    slug: body.slug,
    retentionDays: body.retentionDays,
  };
  return toGroup(await req<GroupRow>(`${GROUPS}/${id}`, { method: "PATCH", body: JSON.stringify(fields) }));
}
export function deleteGroup(id: string): Promise<void> {
  return req<void>(`${GROUPS}/${id}`, { method: "DELETE" });
}

// --- sites ------------------------------------------------------------------
export async function listSites(): Promise<SiteView[]> {
  return (await req<SiteRow[]>(SITES)).map(toSite);
}
export async function createSite(body: { name: string; slug: string; groupId: string }): Promise<SiteView> {
  const fields: { name: string; slug: string; siteGroupId: string } = {
    name: body.name,
    slug: body.slug,
    siteGroupId: body.groupId,
  };
  return toSite(await req<SiteRow>(SITES, { method: "POST", body: JSON.stringify(fields) }));
}
export async function updateSite(id: string, body: { name?: string; slug?: string; groupId?: string }): Promise<SiteView> {
  const fields: { name?: string; slug?: string; siteGroupId?: string } = {
    name: body.name,
    slug: body.slug,
    siteGroupId: body.groupId,
  };
  return toSite(await req<SiteRow>(`${SITES}/${id}`, { method: "PATCH", body: JSON.stringify(fields) }));
}
// The ONLY UI caller is the Auto Configure rollback path (lib/auto-configure.ts) — the
// dashboard deletes a site by retiring its endpoint (deleteEndpoint → the retire route),
// not through here, so don't assume this is how the editor removes a site.
export function deleteSite(id: string): Promise<void> {
  return req<void>(`${SITES}/${id}`, { method: "DELETE" });
}

// --- endpoints --------------------------------------------------------------
export async function listEndpoints(siteId: string): Promise<EndpointView[]> {
  return (await req<EndpointRow[]>(`${ENDPOINTS}?siteId=${encodeURIComponent(siteId)}`)).map(toEndpoint);
}
/** Every endpoint across all sites (the route returns all when no siteId is given). */
export async function listAllEndpoints(): Promise<EndpointView[]> {
  return (await req<EndpointRow[]>(ENDPOINTS)).map(toEndpoint);
}
// These bodies are typed LOCALLY, not against @agentic-toolkit/adh-api-types: that
// spec describes the HUB backend, whose monitored_sites table lacks
// environment/platform/deployProject — but THESE requests hit the STATUS
// backend's /config/endpoints surface, whose monitored_endpoints table DOES carry
// all three (+ ignoreProjectWarning / expectBody). Typing them off the hub spec
// gave false safety (and dropped the wiring fields, so the Configure UI never
// saved). The status backend's schema is the contract; mirror its accepted body here.
// Exactly EndpointView's writable fields (derived — adding a column to EndpointView
// can't silently drop it from create/update).
type EndpointWriteFields = Partial<Omit<EndpointView, "id" | "siteId">>;
type EndpointCreateBody = EndpointWriteFields & { siteId: string; url: string };
type EndpointUpdateBody = EndpointWriteFields;
export async function createEndpoint(siteId: string, body: Partial<Omit<EndpointView, "id" | "siteId">> & { url: string }): Promise<EndpointView> {
  const fields: EndpointCreateBody = {
    siteId,
    url: body.url,
    kind: body.kind,
    environment: body.environment ?? null,
    platform: body.platform ?? null,
    deployProject: body.deployProject ?? null,
    ignoreProjectWarning: body.ignoreProjectWarning,
    expectedStatus: body.expectedStatus,
    expectBody: body.expectBody ?? null,
    dnsCheckA: body.dnsCheckA,
    dnsCheckAaaa: body.dnsCheckAaaa,
    dnsCheckCname: body.dnsCheckCname,
    checkIntervalSeconds: body.checkIntervalSeconds,
    isActive: body.isActive,
  };
  return toEndpoint(await req<EndpointRow>(ENDPOINTS, { method: "POST", body: JSON.stringify(fields) }));
}
export async function updateEndpoint(id: string, body: Partial<Omit<EndpointView, "id" | "siteId">>): Promise<EndpointView> {
  const fields: EndpointUpdateBody = {
    url: body.url,
    kind: body.kind,
    environment: body.environment,
    platform: body.platform,
    deployProject: body.deployProject,
    ignoreProjectWarning: body.ignoreProjectWarning,
    expectedStatus: body.expectedStatus,
    expectBody: body.expectBody,
    dnsCheckA: body.dnsCheckA,
    dnsCheckAaaa: body.dnsCheckAaaa,
    dnsCheckCname: body.dnsCheckCname,
    checkIntervalSeconds: body.checkIntervalSeconds,
    isActive: body.isActive,
  };
  return toEndpoint(await req<EndpointRow>(`${ENDPOINTS}/${id}`, { method: "PATCH", body: JSON.stringify(fields) }));
}
export function deleteEndpoint(id: string): Promise<void> {
  return req<void>(`${ENDPOINTS}/${id}`, { method: "DELETE" });
}

// --- integrations -----------------------------------------------------------
// Hand-typed, not against @agentic-toolkit/adh-api-types: this is the STATUS backend's
// /config/integrations surface (deploy_integrations table) — not part of the HUB
// openapi spec. Mirror the backend's deployIntegrations insert/patch shape here.
export function listIntegrations(): Promise<IntegrationView[]> {
  return req<IntegrationView[]>(INTEGRATIONS);
}
export function createIntegration(body: { platform: string; label: string; config?: Record<string, unknown>; tokenEnvVar?: string | null; isActive?: boolean }): Promise<IntegrationView> {
  return req<IntegrationView>(INTEGRATIONS, { method: "POST", body: JSON.stringify(body) });
}
export function updateIntegration(id: string, body: { platform?: string; label?: string; config?: Record<string, unknown>; tokenEnvVar?: string | null; isActive?: boolean }): Promise<IntegrationView> {
  return req<IntegrationView>(`${INTEGRATIONS}/${id}`, { method: "PATCH", body: JSON.stringify(body) });
}
export function deleteIntegration(id: string): Promise<void> {
  return req<void>(`${INTEGRATIONS}/${id}`, { method: "DELETE" });
}

// --- ignored deploy projects ------------------------------------------------
const IGNORED = "/api/config/ignored-projects";

export interface IgnoredProjectView {
  platform: string;
  projectName: string;
}
export function listIgnoredProjects(): Promise<IgnoredProjectView[]> {
  return req<IgnoredProjectView[]>(IGNORED);
}
export function ignoreProject(platform: string, projectName: string): Promise<void> {
  return req<void>(IGNORED, { method: "POST", body: JSON.stringify({ platform, projectName }) });
}
/**
 * Bulk-ignore many projects (the "Ignore all" / review-modal batch action). The
 * backend's POST /config/ignored-projects takes ONE { platform, projectName } per
 * call, so this fans out one request per project (the unique (platform, projectName)
 * index makes a re-ignore idempotent). Issued in parallel — the rows are independent
 * — so ignoring a large Railway batch is one round-trip's latency, not N. A single
 * failure still surfaces (Promise.all rejects on the first rejection).
 */
export async function ignoreProjects(projects: { platform: string; projectName: string }[]): Promise<void> {
  await Promise.all(projects.map((p) => ignoreProject(p.platform, p.projectName)));
}
export function unignoreProject(platform: string, projectName: string): Promise<void> {
  // Backend DELETE keys off a compound id: `${platform}|${projectName}` (URL-encoded).
  const id = encodeURIComponent(`${platform}|${projectName}`);
  return req<void>(`${IGNORED}/${id}`, { method: "DELETE" });
}
