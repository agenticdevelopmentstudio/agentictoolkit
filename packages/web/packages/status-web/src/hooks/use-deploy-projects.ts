"use client";
import { useQuery, type UseQueryResult } from "@tanstack/react-query";

export interface DeployProject {
  platform: string; // as recorded on deploys: vercel | railway | cloudflare-pages
  projectName: string;
  /** The deploy ENVIRONMENT this entry represents. Railway serves every environment from
   *  ONE project, so it's enumerated once PER environment (production/staging/testing),
   *  each with its own domain; null for Vercel/Cloudflare (env is in the project name).
   *  Threaded into the created endpoint so its per-environment deploy status correlates. */
  environment: string | null;
  environments: string[];
  latestAt: string | null;
  deployCount: number;
  latestStatus: string | null; // success | failed | building | queued | canceled
  wired: boolean; // already referenced by a monitored endpoint
  ignored: boolean; // operator-exempted from the "unconfigured" warning
  // Config info shown in the browser's detail pane.
  domain: string | null;
  /** Every domain the project serves (canonical + redirect aliases). Auto Configure
   *  matches an unconfigured endpoint to a project by ANY of these, so e.g. the
   *  `olylo.ai` apex endpoint wires to the project whose canonical domain is
   *  `ia.olylo.ai`. CF/Railway have one host, so `[domain]`. */
  domains: string[];
  gitRepo: string | null;
  gitBranch: string | null;
  rootDirectory: string | null;
  framework: string | null;
}

/**
 * Fetch the deploy-projects snapshot. `no-store` so a refetch right after Add/Ignore
 * (or on picker open) reaches the server for a fresh provider scan, never the browser's
 * HTTP cache — the body would otherwise show stale wired/ignored/project data. Shared by
 * the hook and the imperative Auto Configure run so they never drift on URL / flag / shape.
 */
export interface DeployProjectsResponse {
  projects: DeployProject[];
  /** The platforms this enumeration listed LIVE and completely — the only ones whose
   *  ABSENCE from `projects` proves a project is gone. A provider that errored, timed out,
   *  or fell back to its configured list is deliberately missing, so a client can tell
   *  "deleted upstream" from "we couldn't look". Optional: a backend that predates the
   *  field sends nothing, and a client must then treat every wiring as live. */
  verifiedPlatforms?: string[];
}

export async function fetchDeployProjects(opts: { fresh?: boolean } = {}): Promise<DeployProjectsResponse> {
  const url = opts.fresh ? "/api/deploy-projects?fresh=1" : "/api/deploy-projects";
  const r = await fetch(url, { cache: "no-store" });
  if (!r.ok) throw new Error(`deploy-projects ${r.status}`);
  return r.json() as Promise<DeployProjectsResponse>;
}

/** The server's `GET /deploy-projects/unconfigured` partition — a FRESH enumeration
 *  classified server-side (the SoT). `pending`/`addable`/`noDomain` are the project axis
 *  (what the config badges and the Auto Configure review consume); `unconfiguredSites` is
 *  the endpoint axis (Spec C's "is anything unconfigured?" probe, minimal `{id,name}`). */
export interface UnconfiguredResponse {
  pending: DeployProject[];
  addable: DeployProject[];
  noDomain: DeployProject[];
  unconfiguredSites: { id: string; name: string }[];
}

/** Fetch the server's unconfigured partition. The route now shares the sibling
 *  /deploy-projects 30s provider cache, so the default (no `fresh`) call is cache-served —
 *  the config-status badges' 60s loop coalesces on it instead of fanning out a provider scan
 *  per tab per minute. `fresh: true` (sent when a user opens the Auto Configure modal) appends
 *  `?fresh=1` to bypass the TTL. `no-store` keeps the browser HTTP cache from masking either.
 *  Shared by the review and the badges so they can't drift on URL / shape. */
export async function fetchUnconfigured(opts: { fresh?: boolean } = {}): Promise<UnconfiguredResponse> {
  const url = opts.fresh ? "/api/deploy-projects/unconfigured?fresh=1" : "/api/deploy-projects/unconfigured";
  const r = await fetch(url, { cache: "no-store" });
  if (!r.ok) throw new Error(`deploy-projects/unconfigured ${r.status}`);
  return r.json() as Promise<UnconfiguredResponse>;
}

// The first fetch of a page load — and any fetch after `armFreshDeployProjectsFetch()` —
// requests `?fresh=1`, bypassing the server's 30s provider cache, so a reload (and the
// explicit Refresh) always shows (and auto-configure always plans against) the live project
// list. The latch disarms only when a fetch SUCCEEDS, so retries of a failed fetch stay
// fresh; once a fresh fetch succeeds, refetches within the same page load use normal caching.
let nextFetchIsFresh = true;

/** Arm the latch so the next deploy-projects fetch bypasses the server's 30s provider cache. */
export function armFreshDeployProjectsFetch(): void {
  nextFetchIsFresh = true;
}

/** All deploy projects seen in the deployments table — to browse when wiring an endpoint. */
export function useDeployProjects({ enabled = true }: { enabled?: boolean } = {}): UseQueryResult<DeployProjectsResponse> {
  return useQuery<DeployProjectsResponse>({
    queryKey: ["deploy-projects"],
    enabled,
    queryFn: async () => {
      const fresh = nextFetchIsFresh;
      const result = await fetchDeployProjects({ fresh });
      nextFetchIsFresh = false;
      return result;
    },
    staleTime: 60_000,
  });
}
