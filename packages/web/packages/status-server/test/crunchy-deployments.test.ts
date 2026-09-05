import { describe, it, expect, vi, afterEach } from "vitest";
import { fetchCrunchyClusters } from "../src/monitor/fetch-crunchy";

// A trimmed real GET /clusters response (secrets removed). Shape is authoritative —
// captured from api.crunchybridge.com on 2026-07-04.
const CLUSTERS = {
  clusters: [
    { id: "fq2z", name: "adh-production", state: "ready", is_suspended: false, environment: "production", created_at: "2026-07-04T00:00:00Z" },
    { id: "qki2", name: "adh-staging", state: "ready", is_suspended: false, environment: "staging", created_at: "2026-07-03T00:00:00Z" },
    { id: "72o5", name: "adh-testing", state: "suspended", is_suspended: true, environment: "testing", created_at: "2026-07-03T00:00:00Z" },
  ],
};

function okFetch(body: unknown) {
  return vi.fn((..._args: Parameters<typeof fetch>) =>
    Promise.resolve({ ok: true, status: 200, json: async () => body } as unknown as Response),
  );
}

afterEach(() => vi.unstubAllGlobals());

describe("fetchCrunchyClusters", () => {
  it("is a no-op (ok) when no token is configured", async () => {
    const out = await fetchCrunchyClusters({});
    expect(out).toEqual({ ok: true, deploys: [] });
  });

  it("maps each cluster to a deploy row; ready→deployed, suspended→failed", async () => {
    vi.stubGlobal("fetch", okFetch(CLUSTERS));
    const out = await fetchCrunchyClusters({ CRUNCHY_API_TOKEN: "cbkey_x" });
    expect(out.ok).toBe(true);
    expect(out.deploys.map((d) => [d.projectName, d.deployPhase])).toEqual([
      ["adh-production", "deployed"],
      ["adh-staging", "deployed"],
      ["adh-testing", "failed"],
    ]);
    expect(out.deploys[0]).toMatchObject({ id: "cr_fq2z", platform: "crunchy", buildPhase: null, environment: "production" });
  });

  it("sends the token as a Bearer header to /clusters", async () => {
    const spy = okFetch(CLUSTERS);
    vi.stubGlobal("fetch", spy);
    await fetchCrunchyClusters({ CRUNCHY_API_TOKEN: "cbkey_x" });
    const [url, init] = spy.mock.calls[0]!;
    expect(String(url)).toContain("api.crunchybridge.com/clusters");
    expect((init as RequestInit).headers).toMatchObject({ Authorization: "Bearer cbkey_x" });
  });

  it("returns ok:false with no deploys when the API errors", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 500, json: async () => ({}) }) as unknown as Response));
    const out = await fetchCrunchyClusters({ CRUNCHY_API_TOKEN: "cbkey_x" });
    expect(out).toEqual({ ok: false, deploys: [] });
  });

  it("returns ok:false when fetch throws", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("network"); }));
    const out = await fetchCrunchyClusters({ CRUNCHY_API_TOKEN: "cbkey_x" });
    expect(out).toEqual({ ok: false, deploys: [] });
  });

  it("defaults a cluster with no environment to production", async () => {
    vi.stubGlobal("fetch", okFetch({ clusters: [
      { id: "z1", name: "no-env", state: "ready", is_suspended: false, created_at: "2026-07-04T00:00:00Z" },
    ] }));
    const out = await fetchCrunchyClusters({ CRUNCHY_API_TOKEN: "cbkey_x" });
    expect(out.deploys[0]).toMatchObject({ environment: "production", deployPhase: "deployed" });
  });

  it("returns no deploys (ok) when the body has no clusters array", async () => {
    vi.stubGlobal("fetch", okFetch({}));
    const out = await fetchCrunchyClusters({ CRUNCHY_API_TOKEN: "cbkey_x" });
    expect(out).toEqual({ ok: true, deploys: [] });
  });

  it("treats a cluster missing its state as healthy (quieter: unknown is not a problem)", async () => {
    vi.stubGlobal("fetch", okFetch({ clusters: [
      { id: "z2", name: "no-state", is_suspended: false, environment: "staging", created_at: "2026-07-04T00:00:00Z" },
    ] }));
    const out = await fetchCrunchyClusters({ CRUNCHY_API_TOKEN: "cbkey_x" });
    expect(out.deploys[0]).toMatchObject({ deployPhase: "deployed" });
  });
});
