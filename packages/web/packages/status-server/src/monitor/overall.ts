import type { HealthStatus } from "./health";

export type OverallStatus = "operational" | "degraded" | "major_outage" | "unknown";

export function computeOverall(statuses: HealthStatus[]): OverallStatus {
  if (statuses.length === 0) return "unknown";
  if (statuses.every((s) => s === "down")) return "major_outage";
  if (statuses.some((s) => s === "down" || s === "degraded")) return "degraded";
  return "operational";
}

/** The PUBLIC headline verdict. The same endpoint-health rollup as
 *  {@link computeOverall}, but a live site keeps serving HTTP 200 while its
 *  latest build/deploy fails or its platform API can't be polled — those
 *  problems never show up in `statuses`, so without folding them in the landing
 *  reads "All systems operational" while deploys are red. A non-endpoint problem
 *  lifts an otherwise-operational verdict to `degraded`; it never manufactures a
 *  full outage (the sites are up) and never overrides an all-endpoints-down
 *  `major_outage` or an `unknown` (no-signal) rollup. */
export function publicOverall(statuses: HealthStatus[], hasNonEndpointProblem: boolean): OverallStatus {
  const base = computeOverall(statuses);
  return base === "operational" && hasNonEndpointProblem ? "degraded" : base;
}
