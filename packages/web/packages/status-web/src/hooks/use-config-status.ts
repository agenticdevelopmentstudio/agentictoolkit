"use client";
import { useCallback, useMemo } from "react";
import { useQuery, type QueryClient, type UseQueryResult } from "@tanstack/react-query";
import * as api from "../api/monitored-sites";
import type { SiteGroupView, SiteView, IntegrationView, EndpointView } from "../api/monitored-sites";
import { fetchUnconfigured, type DeployProject, type UnconfiguredResponse } from "./use-deploy-projects";
import type { ConfigStatus } from "@agentic-toolkit/deploy-platform/engine";
// The PREDICATE is this app's (it folds in the paused-monitor opt-out); the SHAPE it
// fills is the engine's.
import { endpointUnconfigured } from "../lib/config-status";
import { platformCanon } from "../lib/deploy-view";

/** The raw config rosters (local DB only). */
export const CONFIGURE_DATA_KEY = ["configure-data"] as const;
/** The server's deploy-project classification (a live provider scan). */
export const CONFIGURE_CLASSIFICATION_KEY = ["configure-classification"] as const;

/** Invalidate BOTH halves of the config model. The two keys are refetched together
 *  everywhere they were one key before the split, so a caller can't refresh the rosters
 *  and leave the badges stale (or the reverse). */
export function invalidateConfigQueries(qc: QueryClient): Promise<void> {
  return Promise.all([
    qc.invalidateQueries({ queryKey: CONFIGURE_DATA_KEY }),
    qc.invalidateQueries({ queryKey: CONFIGURE_CLASSIFICATION_KEY }),
  ]).then(() => undefined);
}

/** The raw monitoring config — one query, shared by the Config editor AND the
 *  status model so the front page and the Config page read identical data. */
export interface ConfigureData {
  groups: SiteGroupView[];
  sites: SiteView[];
  integrations: IntegrationView[];
  endpoints: EndpointView[];
}

/** The single `["configure-data"]` query. Defined ONCE here (was inline in
 *  ConfigPanel) so every consumer hits the same key, queryFn, and cache.
 *  Intentionally NOT exported: `useConfigStatus` is the one access point, and it
 *  already returns the raw `configure` data — keeping this private stops a
 *  component from reading endpoints without the shared status model.
 *
 *  Four LOCAL-DB reads and nothing else. The deploy-project classification used to be a
 *  fifth leg of this same `Promise.all` — but that leg is a live enumeration of Vercel,
 *  Railway and Cloudflare, and `Promise.all` rejects whole: one flaky provider took the
 *  ENTIRE config editor down with it, so Settings ▸ Sites and Settings ▸ Platforms both
 *  rendered empty while the rows sat perfectly readable in SQLite. The rosters must not be
 *  hostage to a third party being up; the classification is its own query below, and
 *  `useConfigStatus` still reports ITS failure so a dead scan is never read as "all clear". */
function useConfigureData(enabled: boolean): UseQueryResult<ConfigureData> {
  return useQuery<ConfigureData>({
    queryKey: CONFIGURE_DATA_KEY,
    enabled,
    queryFn: async () => {
      const [groups, sites, integrations, endpoints] = await Promise.all([
        api.listGroups(),
        api.listSites(),
        api.listIntegrations(),
        api.listAllEndpoints(),
      ]);
      return { groups, sites, integrations, endpoints };
    },
  });
}

/** The server's classified deploy-project partition — the SoT for the "not monitored"
 *  (project-axis) badges. Its OWN key, because it is the only leg that leaves the box: a
 *  full provider scan behind the route's shared 30s single-flight cache (the Auto Configure
 *  modal is what forces a fresh one, via `fetchUnconfigured({ fresh: true })`). Carries no
 *  `refetchInterval`, and the app QueryClient sets no default one, so it runs on mount +
 *  the shared 60s refresh + explicit invalidation. */
function useUnconfigured(enabled: boolean): UseQueryResult<UnconfiguredResponse> {
  return useQuery<UnconfiguredResponse>({
    queryKey: CONFIGURE_CLASSIFICATION_KEY,
    enabled,
    queryFn: () => fetchUnconfigured(),
  });
}

export interface UseConfigStatus {
  /** The one configuration-status model — what every "configured?" surface renders. */
  status: ConfigStatus<EndpointView, DeployProject>;
  /** The raw config (for the editor); undefined until the first load resolves. */
  configure: ConfigureData | undefined;
  isLoading: boolean;
  /** Load error from the shared config query — which now ALSO covers the server
   *  classification fetch, so a failed `/deploy-projects/unconfigured` isn't silently
   *  read as "zero gaps / all clear". */
  error: unknown;
  /** Refetch the raw config — so a consumer needn't reach past this hook to the query. */
  refetch: () => Promise<unknown>;
}

const EMPTY_STATUS: ConfigStatus<EndpointView, DeployProject> = {
  unconfiguredSites: [],
  unmonitoredProjects: [],
  addableProjects: [],
  noDomainProjects: 0,
  unmonitoredByPlatform: new Map(),
  counts: { sites: 0, projects: 0, total: 0 },
};

/**
 * Assemble the configuration-status model from the shared query data. The PROJECT axis
 * (`unmonitoredProjects` / `addableProjects` / `noDomainProjects` / `unmonitoredByPlatform`)
 * is taken WHOLE from the server's `unconfigured` partition — no client re-classification,
 * so the server is the single source of truth for "which projects need monitoring".
 *
 * The ENDPOINT axis (`unconfiguredSites`) is derived from the raw endpoints via the SAME
 * `endpointUnconfigured` predicate the server applies. It stays client-side deliberately:
 * the banner popover renders each endpoint's url / site / environment, which the server's
 * intentionally-minimal `{id,name}` shape omits — and the raw endpoints are already in this
 * query (the editor needs them), so the values are identical to the prior behavior.
 * `unmonitoredByPlatform` re-tallies by CANONICAL platform, a pure key normalization (not
 * classification), matching the badges' prior per-platform counts.
 */
function buildStatus(
  data: ConfigureData | undefined,
  unconfigured: UnconfiguredResponse | undefined,
): ConfigStatus<EndpointView, DeployProject> {
  if (!data || !unconfigured) return EMPTY_STATUS;
  const { endpoints } = data;
  const unconfiguredSites = endpoints.filter(endpointUnconfigured);
  const unmonitoredProjects = unconfigured.pending;
  const unmonitoredByPlatform = new Map<string, number>();
  for (const p of unmonitoredProjects) {
    const key = platformCanon(p.platform);
    unmonitoredByPlatform.set(key, (unmonitoredByPlatform.get(key) ?? 0) + 1);
  }
  const sites = unconfiguredSites.length;
  const projects = unmonitoredProjects.length;
  return {
    unconfiguredSites,
    unmonitoredProjects,
    addableProjects: unconfigured.addable,
    noDomainProjects: unconfigured.noDomain.length,
    unmonitoredByPlatform,
    counts: { sites, projects, total: sites + projects },
  };
}

/**
 * THE access point for configuration health. Reads the shared `configure-data` query
 * (raw config + the server's classified partition) and assembles the model. The query is
 * react-query-cached, so calling this from several components fetches nothing extra — they
 * read the same cached data and derive the same model, which is the whole point: the
 * Overview banner and the Config page can't diverge.
 *
 * `enabled: false` parks THIS consumer's observer without fetching (a caller that
 * only sometimes needs the model, e.g. the board rail off the Settings topic);
 * any enabled consumer elsewhere still drives the shared query.
 */
export function useConfigStatus({ enabled = true }: { enabled?: boolean } = {}): UseConfigStatus {
  const configure = useConfigureData(enabled);
  const unconfigured = useUnconfigured(enabled);
  const status = useMemo(() => buildStatus(configure.data, unconfigured.data), [configure.data, unconfigured.data]);
  const refetch = useCallback(
    () => Promise.all([configure.refetch(), unconfigured.refetch()]),
    [configure.refetch, unconfigured.refetch],
  );
  return {
    status,
    configure: configure.data,
    // The ROSTERS' own load — what the config editor renders. A failed provider scan no
    // longer parks the editor in a permanent skeleton.
    isLoading: configure.isLoading,
    // Still BOTH, in roster-first order: a dead classification must never be read as "zero
    // gaps / all clear" (the reason it was folded in), but it no longer blanks the rosters.
    error: configure.error ?? unconfigured.error,
    refetch,
  };
}
