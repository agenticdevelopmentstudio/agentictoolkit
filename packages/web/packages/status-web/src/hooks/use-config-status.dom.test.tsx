// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactElement } from "react";

// The five reads behind the config model. Mocked at the module boundary so the test
// exercises the REAL query wiring (keys, enabled, Promise.all shape) and only the
// network is faked.
vi.mock("../api/monitored-sites", () => ({
  listGroups: vi.fn(async () => [{ id: "g1", slug: "g", name: "G", retentionDays: 30 }]),
  listSites: vi.fn(async () => [{ id: "s1", slug: "s", name: "S", groupId: "g1" }]),
  listIntegrations: vi.fn(async () => [{ id: "i1", platform: "vercel", label: "Vercel", config: {}, tokenEnvVar: null, isActive: true }]),
  listAllEndpoints: vi.fn(async () => [{ id: "e1", siteId: "s1", url: "https://x.test", kind: "http", environment: null, platform: null, deployProject: null, ignoreProjectWarning: false, expectedStatus: 200, expectBody: null, dnsCheckA: true, dnsCheckAaaa: true, dnsCheckCname: true, checkIntervalSeconds: 60, isActive: true }]),
}));
const fetchUnconfigured = vi.fn();
vi.mock("./use-deploy-projects", () => ({ fetchUnconfigured: (...a: unknown[]) => fetchUnconfigured(...a) }));

import { useConfigStatus } from "./use-config-status";

function harness() {
  const out: { configure?: unknown; error?: unknown; counts?: number } = {};
  function Probe(): ReactElement | null {
    const r = useConfigStatus();
    out.configure = r.configure;
    out.error = r.error;
    out.counts = r.status.counts.total;
    return null;
  }
  // retry:0 so a rejected leg settles in one tick, like the app's `retry: 1` eventually does.
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return {
    out,
    view: render(
      <QueryClientProvider client={client}>
        <Probe />
      </QueryClientProvider>,
    ),
  };
}

describe("useConfigStatus", () => {
  beforeEach(() => {
    fetchUnconfigured.mockReset();
    vi.spyOn(console, "error").mockImplementation(() => {});
  });
  afterEach(() => vi.restoreAllMocks());

  it("still serves the rosters when the deploy-project scan fails", async () => {
    // The regression this guards: the provider scan used to be a fifth leg of the SAME
    // Promise.all as the four DB reads, so one flaky platform emptied Settings ▸ Sites and
    // Settings ▸ Platforms while the rows sat readable in SQLite.
    fetchUnconfigured.mockRejectedValue(new Error("deploy-projects/unconfigured 502"));
    const { out } = harness();
    await waitFor(() => expect(out.error).toBeInstanceOf(Error));
    const configure = out.configure as { sites: unknown[]; endpoints: unknown[]; integrations: unknown[] };
    expect(configure.sites).toHaveLength(1);
    expect(configure.endpoints).toHaveLength(1);
    expect(configure.integrations).toHaveLength(1);
    // …and the failure is still REPORTED, so a dead scan is never read as "all clear".
    expect((out.error as Error).message).toContain("502");
  });

  it("reports both halves when everything loads", async () => {
    fetchUnconfigured.mockResolvedValue({ pending: [{ platform: "vercel", projectName: "p" }], addable: [], noDomain: [], unconfiguredSites: [] });
    const { out } = harness();
    // Both axes land: the endpoint names no deploy project (1 site) + 1 pending project.
    await waitFor(() => expect(out.counts).toBe(2));
    expect(out.error).toBeFalsy();
  });
});
