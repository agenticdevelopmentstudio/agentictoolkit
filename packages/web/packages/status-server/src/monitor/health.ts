export type HealthStatus = "healthy" | "degraded" | "down";

export const HEALTH_CHECK_TIMEOUT_MS = 10_000;
export const DEGRADED_THRESHOLD_MS = 2_000;

export interface ClassifyInput {
  statusCode: number;
  responseTimeMs: number;
  expectedStatus: number;
  isHealthKind?: boolean;
  bodyText?: string;
  /** True when the endpoint's configured `expectBody` marker was NOT found in
   *  the response body — a 200 serving the wrong/broken page is DOWN. */
  bodyMarkerMissing?: boolean;
}

export function classify(input: ClassifyInput): HealthStatus {
  const { statusCode, responseTimeMs, expectedStatus, isHealthKind, bodyText, bodyMarkerMissing } = input;
  const is2xx = statusCode >= 200 && statusCode < 300;

  if (is2xx || statusCode === expectedStatus) {
    if (is2xx && isHealthKind && bodyText) {
      try {
        const parsed: unknown = JSON.parse(bodyText);
        if (parsed !== null && typeof parsed === "object" && "status" in parsed) {
          if (String((parsed as Record<string, unknown>).status).toLowerCase() !== "ok") {
            return "down";
          }
        }
      } catch {
        // Non-JSON body (e.g. HTML page) — fall through to the marker/latency checks.
      }
    }
    // A success status serving the WRONG content (broken shell, takeover page,
    // empty app) is an outage the status code can't see — the marker can.
    if (bodyMarkerMissing) return "down";
    return responseTimeMs > DEGRADED_THRESHOLD_MS ? "degraded" : "healthy";
  }
  return "down";
}
