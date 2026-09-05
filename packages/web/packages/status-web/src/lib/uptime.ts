import type { HealthStatus } from "./health";

export interface Counts {
  total: number;
  healthy: number;
  degraded: number;
  down: number;
}

export function uptimePercent(c: Counts): number | null {
  if (c.total <= 0) return null;
  return Math.round(((c.healthy + c.degraded) / c.total) * 10000) / 100;
}

export function dayStatus(c: Counts): HealthStatus {
  if (c.down > 0) return c.down / c.total > 0.5 ? "down" : "degraded";
  if (c.degraded > 0) return "degraded";
  return "healthy";
}

/**
 * Portfolio-wide uptime % — the simple mean of each service's own uptime %, so
 * every service counts equally. (Volume-weighting was misleading: a service
 * checked more often, or simply monitored for longer, would dominate the number
 * even though it's just one of the things we watch.) Null when there's no data.
 */
export function overallUptimePercent(
  services: { uptimePercent: number | null }[],
): number | null {
  const vals = services.map((s) => s.uptimePercent).filter((p): p is number => p != null);
  if (vals.length === 0) return null;
  const mean = vals.reduce((a, b) => a + b, 0) / vals.length;
  return Math.round(mean * 100) / 100;
}
