import { describe, it, expect } from "vitest";
import { classify, DEGRADED_THRESHOLD_MS, HEALTH_CHECK_TIMEOUT_MS } from "./health";

describe("classify", () => {
  it("exposes the documented threshold constants", () => {
    expect(DEGRADED_THRESHOLD_MS).toBe(2_000);
    expect(HEALTH_CHECK_TIMEOUT_MS).toBe(10_000);
  });
  it("2xx under threshold is healthy", () => {
    expect(classify({ statusCode: 200, responseTimeMs: 100, expectedStatus: 200 })).toBe("healthy");
  });
  it("2xx over threshold is degraded", () => {
    expect(classify({ statusCode: 200, responseTimeMs: DEGRADED_THRESHOLD_MS + 1, expectedStatus: 200 })).toBe("degraded");
  });
  it("non-2xx not matching expected is down", () => {
    expect(classify({ statusCode: 500, responseTimeMs: 50, expectedStatus: 200 })).toBe("down");
  });
  it("non-2xx matching expectedStatus is healthy", () => {
    expect(classify({ statusCode: 403, responseTimeMs: 50, expectedStatus: 403 })).toBe("healthy");
  });
  it("health-kind requires ok body", () => {
    expect(classify({ statusCode: 200, responseTimeMs: 50, expectedStatus: 200, isHealthKind: true, bodyText: '{"status":"degraded"}' })).toBe("down");
    expect(classify({ statusCode: 200, responseTimeMs: 50, expectedStatus: 200, isHealthKind: true, bodyText: '{"status":"ok"}' })).toBe("healthy");
  });
  it("health-kind ok body but slow is degraded", () => {
    expect(classify({ statusCode: 200, responseTimeMs: DEGRADED_THRESHOLD_MS + 1, expectedStatus: 200, isHealthKind: true, bodyText: '{"status":"ok"}' })).toBe("degraded");
  });
  it('health-kind: {"status":"down","ok":false} (200) is down — not tripped by the "ok" token', () => {
    expect(classify({ statusCode: 200, responseTimeMs: 50, expectedStatus: 200, isHealthKind: true, bodyText: '{"status":"down","ok":false}' })).toBe("down");
  });
  it('health-kind: {"status":"degraded"} (200) is down', () => {
    expect(classify({ statusCode: 200, responseTimeMs: 50, expectedStatus: 200, isHealthKind: true, bodyText: '{"status":"degraded"}' })).toBe("down");
  });
  it("health-kind: non-JSON body (HTML) with 200 is healthy — parse failure falls through", () => {
    expect(classify({ statusCode: 200, responseTimeMs: 50, expectedStatus: 200, isHealthKind: true, bodyText: "<html><body>OK</body></html>" })).toBe("healthy");
  });
  it("health-kind: JSON body with no status field with 200 is healthy — unknown shape falls through", () => {
    expect(classify({ statusCode: 200, responseTimeMs: 50, expectedStatus: 200, isHealthKind: true, bodyText: '{"result":"ok"}' })).toBe("healthy");
  });
  it("non-2xx matching expectedStatus but slow is degraded", () => {
    expect(classify({ statusCode: 403, responseTimeMs: DEGRADED_THRESHOLD_MS + 1, expectedStatus: 403 })).toBe("degraded");
  });
});

describe("classify: expectBody marker", () => {
  const base = { responseTimeMs: 100, expectedStatus: 200 };

  it("a 2xx whose body is missing the marker is DOWN (broken/wrong page behind a 200)", () => {
    expect(classify({ ...base, statusCode: 200, bodyMarkerMissing: true })).toBe("down");
  });

  it("a 2xx with the marker present classifies normally (healthy / degraded by latency)", () => {
    expect(classify({ ...base, statusCode: 200, bodyMarkerMissing: false })).toBe("healthy");
    expect(classify({ ...base, statusCode: 200, responseTimeMs: 5000, bodyMarkerMissing: false })).toBe("degraded");
  });

  it("a custom expectedStatus match is also subject to the marker", () => {
    expect(classify({ ...base, statusCode: 401, expectedStatus: 401, bodyMarkerMissing: true })).toBe("down");
    expect(classify({ ...base, statusCode: 401, expectedStatus: 401, bodyMarkerMissing: false })).toBe("healthy");
  });

  it("no marker configured (undefined) changes nothing", () => {
    expect(classify({ ...base, statusCode: 200 })).toBe("healthy");
  });
});
