import type { ServiceStatusDTO, DeploymentDTO } from "../types";

// The /api/live contract — one self-contained snapshot of everything the client
// displays, pulled live from providers + HTTP probes. Type-only module (shared by
// the route and the client store); no DB imports.

export interface LiveServiceDTO extends ServiceStatusDTO {
  /** Whether the hostname resolved in DNS. false → a `dns`-source problem, not `http`. */
  dnsOk: boolean;
  /** ISO time the endpoint's current http/dns issue opened — SERVER-truth "down since",
   *  durable across browsers (unlike the client store's per-tab onset). null = not down. */
  downSince: string | null;
}

/** A Vercel project whose LIVE production deploy is errored/behind (already filtered to stale). */
export interface StaleProdDTO {
  projectName: string;
  environment: string;
  detail: string | null;
  sourceUrl: string | null;
  liveUrl: string | null;
}

export type ProviderKey = "vercel" | "cloudflare-pages" | "railway" | "crunchy";

export interface ProviderHealth {
  /** Whether we actually poll this platform (active integration WITH a token). */
  configured: boolean;
  /** Whether the latest poll reached the provider API. */
  ok: boolean;
}

export interface LiveSnapshot {
  generatedAt: string; // ISO, server clock — the client's event-time reference
  /** ISO time of the NEWEST PERSISTED PROBE — the data-freshness clock for what's on
   *  screen, null before the first probe. Distinct from the scheduler's cycle-
   *  COMPLETION clock at `/health` (that's the loop-health signal). The client warns
   *  when this lags `generatedAt` by more than a few probe intervals, so a wedged /
   *  never-redeployed poller can't masquerade as live data (`generatedAt` is read-time
   *  and always looks fresh). Optional so an older backend degrades to "no warning". */
  lastCycleAt?: string | null;
  /** The backend's probe interval (ms), so the client's staleness window can scale
   *  with it instead of hardcoding a threshold that false-trips when the operator
   *  raises `PROBE_INTERVAL_SECONDS`. Optional (older backend → the client's floor). */
  probeIntervalMs?: number;
  /** Git commit the MONITOR ITSELF is running (Railway build env; null locally).
   *  Shown on the board so "did my status-site deploy actually take?" is answerable
   *  from the board. Optional so an older backend degrades to "not shown". */
  monitorVersion?: string | null;
  services: LiveServiceDTO[];
  deployments: DeploymentDTO[];
  staleProd: StaleProdDTO[];
  providers: Record<ProviderKey, ProviderHealth>;
  /** True when the config read fell back to the static list (DB unreachable). */
  configDegraded: boolean;
  configReason: string | null;
}
