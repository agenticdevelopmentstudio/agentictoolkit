import type { HealthStatus } from "./health";

export type OverallStatus = "operational" | "degraded" | "major_outage" | "unknown";

export function computeOverall(statuses: HealthStatus[]): OverallStatus {
  if (statuses.length === 0) return "unknown";
  if (statuses.every((s) => s === "down")) return "major_outage";
  if (statuses.some((s) => s === "down" || s === "degraded")) return "degraded";
  return "operational";
}
