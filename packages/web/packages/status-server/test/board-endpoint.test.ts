import { describe, it, expect } from "vitest";
import { endpointProblems } from "../src/board/derive-problems";
import { DEGRADED_CONFIRM_MS } from "../src/board/types";
import type { BoardFacts, EndpointFact, RosterEntry } from "../src/board/types";

const NOW = Date.UTC(2026, 7, 2, 12, 0, 0);

function entry(over: Partial<RosterEntry> = {}): RosterEntry {
  return {
    endpointId: "ep-1",
    label: "Hub Help",
    platform: "vercel",
    providerProjectId: null,
    projectName: "hub-help-testing",
    environment: "production",
    isActive: true,
    monitorHttp: true,
    monitorDeploys: true,
    ignoreProjectWarning: false,
    url: "https://testing.help.example.com",
    ...over,
  };
}

function probe(over: Partial<EndpointFact> = {}): EndpointFact {
  return { endpointId: "ep-1", status: "healthy", statusCode: 200, dnsOk: true, checkedAtMs: NOW - 30_000, badSinceMs: null, ...over };
}

function facts(over: Partial<BoardFacts> = {}): BoardFacts {
  return {
    roster: [entry()],
    probeIntervalMs: 60_000,
    deploys: [],
    inFlightDeploys: [],
    deployEvents: [],
    endpoints: [],
    platforms: [],
    staleProd: [],
    ledger: [],
    issueEvents: [],
    liveVercelProjects: [],
    errors: [], errorsConfigured: true, errorProjectAllowlist: null,
    ...over,
  };
}

describe("endpointProblems", () => {
  it("a HEALTHY endpoint is not a problem", () => {
    expect(endpointProblems(facts({ endpoints: [probe()] }), NOW)).toEqual([]);
  });

  it("uses the endpoint's BARE id as the target — reads.ts and app.ts key on it", () => {
    const f = facts({ endpoints: [probe({ status: "down", badSinceMs: NOW - 1000 })] });
    expect(endpointProblems(f, NOW)[0].target).toBe("ep-1");
  });

  it("an endpoint problem carries neither a branch nor an errorText — an HTTP probe has no build", () => {
    const f = facts({ endpoints: [probe({ status: "down", badSinceMs: NOW - 1000 })] });
    expect(endpointProblems(f, NOW)[0]).toMatchObject({ branch: null, errorText: null });
  });

  it("a DOWN endpoint is a problem immediately — no debounce", () => {
    const f = facts({ endpoints: [probe({ status: "down", statusCode: 503, badSinceMs: NOW - 1000 })] });
    const p = endpointProblems(f, NOW);
    expect(p).toHaveLength(1);
    expect(p[0]).toMatchObject({ state: "down", severity: "critical", statusCode: 503, source: "http" });
  });

  it("a DEGRADED endpoint under the confirm window is NOT yet a problem", () => {
    const f = facts({ endpoints: [probe({ status: "degraded", badSinceMs: NOW - (DEGRADED_CONFIRM_MS - 1) })] });
    expect(endpointProblems(f, NOW)).toEqual([]);
  });

  it("a DEGRADED endpoint past the confirm window IS a problem", () => {
    const f = facts({ endpoints: [probe({ status: "degraded", badSinceMs: NOW - DEGRADED_CONFIRM_MS })] });
    const p = endpointProblems(f, NOW);
    expect(p).toHaveLength(1);
    expect(p[0]).toMatchObject({ state: "degraded", severity: "minor" });
  });

  it("a DNS failure is a `dns` problem, not an `http` one", () => {
    const f = facts({ endpoints: [probe({ status: "down", dnsOk: false, badSinceMs: NOW - 1000 })] });
    expect(endpointProblems(f, NOW)[0].source).toBe("dns");
  });

  it("REQUIREMENT A: monitorHttp=false removes the endpoint's problem", () => {
    const f = facts({
      roster: [entry({ monitorHttp: false })],
      endpoints: [probe({ status: "down", badSinceMs: NOW - 3600_000 })],
    });
    expect(endpointProblems(f, NOW)).toEqual([]);
  });

  it("REQUIREMENT A: isActive=false removes the endpoint's problem", () => {
    const f = facts({
      roster: [entry({ isActive: false })],
      endpoints: [probe({ status: "down", badSinceMs: NOW - 3600_000 })],
    });
    expect(endpointProblems(f, NOW)).toEqual([]);
  });

  it("a probe with no roster entry is invisible — a deleted site cannot be a problem", () => {
    const f = facts({ roster: [], endpoints: [probe({ status: "down", badSinceMs: NOW - 1000 })] });
    expect(endpointProblems(f, NOW)).toEqual([]);
  });

  it("`since` is the SERVER's badSince, not the read time", () => {
    const bad = NOW - 7 * 3600_000;
    const f = facts({ endpoints: [probe({ status: "down", badSinceMs: bad })] });
    expect(endpointProblems(f, NOW)[0].since).toBe(new Date(bad).toISOString());
  });
});
