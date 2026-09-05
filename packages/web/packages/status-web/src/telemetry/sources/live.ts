import type { StatusApiClient } from "../../api/client";
import type { TelemetrySource } from "../ports";
import type { TelemetrySnapshot } from "../types";

// The LIVE source — reads /telemetry, where the server polls GlitchTip and
// PostHog and returns DTOs directly. No database anywhere on this path: a Turso
// outage cannot affect the dashboard's errors/analytics. This is the source
// wired today (see telemetry/client.ts).
export const liveSource: TelemetrySource = {
  async get(api: StatusApiClient): Promise<TelemetrySnapshot> {
    const r = await api.fetch("/telemetry");
    if (!r.ok) throw new Error(`telemetry ${r.status}`);
    return (await r.json()) as TelemetrySnapshot;
  },
};
