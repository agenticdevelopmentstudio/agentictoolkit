import type { StatusApiClient } from "../../api/client";
import type { TelemetrySource } from "../ports";
import type { TelemetrySnapshot, ErrorDTO, AnalyticsMetricDTO } from "../types";

// The TURSO-backed source — reads the persisted store via /errors +
// /analytics (which read the database). This is the "reconnect the Turso
// backend later" target: flip telemetry/client.ts's `source` to this and the
// dashboard serves from the DB instead of the live poll, with NOTHING else
// changing (same TelemetrySnapshot contract). Preserves the original
// useErrors/useAnalytics read logic as a single composable source.
export const tursoSource: TelemetrySource = {
  async get(api: StatusApiClient): Promise<TelemetrySnapshot> {
    const [er, ar] = await Promise.all([api.fetch("/errors"), api.fetch("/analytics")]);
    if (!er.ok) throw new Error(`errors ${er.status}`);
    if (!ar.ok) throw new Error(`analytics ${ar.status}`);
    const errors = ((await er.json()) as { errors: ErrorDTO[] }).errors;
    const analytics = ((await ar.json()) as { metrics: AnalyticsMetricDTO[] }).metrics;
    return { generatedAt: new Date().toISOString(), errors, analytics };
  },
};
