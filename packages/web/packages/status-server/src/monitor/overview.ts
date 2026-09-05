import type { DeploymentDTO } from "./types";
import { platformCanon, deployTargetKey } from "@agentic-toolkit/deploy-platform/canon";

export interface PlatformSummary {
  platform: string;
  ready: number;
  building: number;
  failed: number;
  total: number;
}

// Stable ordering for known platforms; unknowns go after.
const PLATFORM_ORDER = ["vercel", "cloudflare-pages", "railway", "crunchy"];

/**
 * Summarize deploys by platform.
 * status buckets: success→ready; building|queued→building; failed→failed; canceled→total only
 */
export function summarizeByPlatform(deploys: DeploymentDTO[]): PlatformSummary[] {
  const map = new Map<string, PlatformSummary>();

  for (const d of deploys) {
    let entry = map.get(d.platform);
    if (!entry) {
      entry = { platform: d.platform, ready: 0, building: 0, failed: 0, total: 0 };
      map.set(d.platform, entry);
    }
    entry.total++;
    if (d.status === "success") entry.ready++;
    else if (d.status === "building" || d.status === "queued") entry.building++;
    else if (d.status === "failed") entry.failed++;
    // canceled: counted in total only
  }

  // Sort: known platforms in stable order, then any others in insertion order
  const known = PLATFORM_ORDER.filter((p) => map.has(p)).map((p) => map.get(p)!);
  const unknown = [...map.values()].filter((s) => !PLATFORM_ORDER.includes(s.platform));
  return [...known, ...unknown];
}

// ---------------------------------------------------------------------------
// Endpoint-aware helpers — correlate a monitored endpoint to its deploys by the
// EXPLICIT (platform, project) wired on the endpoint in config. No host guessing.
// ---------------------------------------------------------------------------

/** The deploy-target fields an endpoint is correlated by (from its config). */
export interface EndpointLike {
  platform?: string | null;
  deployProject?: string | null;
  environment?: string | null;
}

// platformCanon + deployTargetKey now live in @agentic-toolkit/deploy-platform/canon.
// Imported above for use in this module; re-exported so existing `./overview`
// importers keep their path.
export { platformCanon, deployTargetKey };

/**
 * All deploys wired to this endpoint — matched by the endpoint's EXPLICIT
 * (platform, project), newest-first. Railway serves every env from ONE project, so
 * there we also match the environment; Vercel/Cloudflare projects are env-specific,
 * so the project alone identifies them. An endpoint with no platform/project (a
 * health-only check) correlates to nothing.
 */
export function deploysForEndpoint(deploys: DeploymentDTO[], ep: EndpointLike): DeploymentDTO[] {
  const key = deployTargetKey(ep.platform, ep.deployProject, ep.environment);
  if (!key) return [];
  return deploys
    .filter((d) => deployTargetKey(d.platform, d.projectName, d.environment) === key)
    .sort((a, b) => +new Date(b.createdAt) - +new Date(a.createdAt));
}

/**
 * The most recent *terminal* deploy for an endpoint — a definitive `success` or
 * `failed`, skipping `canceled`/`building`/`queued`. So the deploy status shown
 * reflects the last real outcome, not a canceled/in-flight build on top.
 */
export function latestTerminalForEndpoint(deploys: DeploymentDTO[], ep: EndpointLike): DeploymentDTO | null {
  return deploysForEndpoint(deploys, ep).find((d) => d.status === "success" || d.status === "failed") ?? null;
}

/** Returns the count of failed deploys for a specific endpoint. */
export function failuresForEndpoint(deploys: DeploymentDTO[], ep: EndpointLike): number {
  return deploysForEndpoint(deploys, ep).filter((d) => d.status === "failed").length;
}
