import { describe, expect, it, vi } from "vitest";
import { noteDetail, runMatch, skipDetail, statusApi, SKIP_DETAIL_LINES } from "./auto-configure";
import type { EndpointView, SiteView } from "../api/monitored-sites";

// The MATCHING is the engine's and is tested there (engine/run.test.ts). What is tested
// here is this module's whole job: the adapter that maps this app's client onto the
// engine's port, the flattening of its result to the shape the dialogs render, and the
// two detail blocks.

const epView = (o: Partial<EndpointView> & { id: string; siteId: string; url: string }): EndpointView => ({
  kind: "http",
  environment: null,
  platform: null,
  deployProject: null,
  ignoreProjectWarning: false,
  expectedStatus: 200,
  expectBody: null,
  dnsCheckA: true,
  dnsCheckAaaa: true,
  dnsCheckCname: true,
  checkIntervalSeconds: 60,
  isActive: true,
  ...o,
});

describe("statusApi — the monitored-sites client as the engine's port", () => {
  it("maps an EndpointView down to the lite view the engine plans against", async () => {
    const view = epView({ id: "e1", siteId: "s1", url: "https://a.com", kind: "frontend", environment: "production", platform: "vercel", deployProject: "p" });
    const api = statusApi({ listAllEndpoints: async () => [view] } as unknown as typeof import("../api/monitored-sites"));

    // Exactly the engine's EndpointLite — the probe/monitoring fields are this board's and
    // mean nothing to the planner, so they must not ride along into it.
    expect(await api.listAllEndpoints()).toEqual([
      { id: "e1", siteId: "s1", url: "https://a.com", kind: "frontend", environment: "production", platform: "vercel", deployProject: "p", ignoreProjectWarning: false },
    ]);
  });

  it("carries the opt-out as the FOLD of both of this board's ways to say it", async () => {
    // The engine's endpoint axis filters on `endpointUnconfigured`, which reads this one
    // flag; a port that dropped it read every opted-out monitor as undecided and wired it
    // anyway. Both of this board's opt-outs have to arrive as that flag, or pausing a site
    // means something different depending on which side of the wire you ask.
    const api = statusApi({
      listAllEndpoints: async () => [
        epView({ id: "ignored", siteId: "s1", url: "https://a.com", ignoreProjectWarning: true }),
        epView({ id: "paused", siteId: "s1", url: "https://b.com", isActive: false }),
        epView({ id: "live", siteId: "s1", url: "https://c.com" }),
      ],
    } as unknown as typeof import("../api/monitored-sites"));

    expect((await api.listAllEndpoints()).map((e) => [e.id, e.ignoreProjectWarning])).toEqual([
      ["ignored", true],
      ["paused", true],
      ["live", false],
    ]);
  });

  it("maps a SiteView down to {id, slug, groupId} — the three fields the create path reads", async () => {
    const site = { id: "s1", slug: "alpha", groupId: "g1", name: "Alpha", extra: "ignored" } as unknown as SiteView;
    const api = statusApi({ listSites: async () => [site] } as unknown as typeof import("../api/monitored-sites"));

    expect(await api.listSites()).toEqual([{ id: "s1", slug: "alpha", groupId: "g1" }]);
  });
});

describe("runMatch", () => {
  it("never passes `create` — an unmonitored project is left for the operator", async () => {
    // The guarantee is a property of THIS call, not of the engine: `runAutoConfigure` will
    // create sites when handed a group, and a browser can't answer which group is right.
    const listAllEndpoints = vi.fn(async () => []);
    const createSite = vi.fn(async () => ({ id: "s1" }));
    const createEndpoint = vi.fn(async () => {
      throw new Error("createEndpoint must not be reached");
    });
    const api = statusApi({ listAllEndpoints, listSites: async () => [], createSite, createEndpoint } as unknown as typeof import("../api/monitored-sites"));

    const res = await runMatch([{ platform: "vercel", projectName: "help-production", domain: "agenticdeveloperhelp.com" }], { api });

    expect(createSite).not.toHaveBeenCalled();
    expect(createEndpoint).not.toHaveBeenCalled();
    expect(res.added).toBe(0);
    expect(res.skipped[0]).toEqual({ project: "help-production", reason: expect.stringContaining("no site monitors this domain") });
  });

  it("flattens the engine's per-project result to the counts and names the UI renders", async () => {
    // The engine hands back the PROJECT objects (it is generic over them); the dialogs and
    // the inline error line render a count and a name.
    const view = epView({ id: "e1", siteId: "s1", url: "https://a.com", kind: "frontend", environment: "production" });
    const api = statusApi({
      listAllEndpoints: async () => [view],
      listSites: async () => [{ id: "s1", slug: "a", groupId: "g1" } as unknown as SiteView],
      updateEndpoint: async () => view,
    } as unknown as typeof import("../api/monitored-sites"));

    const res = await runMatch(
      [
        { platform: "vercel", projectName: "a-production", domain: "a.com" },
        { platform: "vercel", projectName: "b-production", domain: "b.com" },
      ],
      { api },
    );

    expect(res.added).toBe(1);
    expect(res.skipped).toEqual([{ project: "b-production", reason: expect.any(String) }]);
  });
});

describe("skipDetail", () => {
  const rows = (n: number) => Array.from({ length: n }, (_, i) => ({ project: `p${i + 1}`, reason: `r${i + 1}` }));

  it("says nothing when there is nothing left alone", () => {
    // The empty case must contribute NO text — otherwise a clean run's message ends in a
    // dangling "Left alone:" header with no rows under it.
    expect(skipDetail(undefined)).toBe("");
    expect(skipDetail([])).toBe("");
  });

  it("names every project when they fit under the line limit", () => {
    expect(skipDetail(rows(2))).toBe("\n\nLeft alone:\n• p1: r1\n• p2: r2");
  });

  it("names exactly the limit with no '…and more' when the count is the limit", () => {
    const out = skipDetail(rows(SKIP_DETAIL_LINES));
    expect(out.split("\n• ")).toHaveLength(SKIP_DETAIL_LINES + 1);
    expect(out).not.toContain("more");
  });

  it("truncates past the limit and counts the REST, not the total", () => {
    // The off-by-one to guard: `…and 7 more` beside 5 shown rows would over-count by the
    // 5 already named, and the operator would go looking for projects that aren't missing.
    const out = skipDetail(rows(7));
    expect(out).toContain("• p5: r5");
    expect(out).not.toContain("• p6: r6");
    expect(out).toContain("…and 2 more");
  });
});

describe("noteDetail", () => {
  const rows = (n: number) => Array.from({ length: n }, (_, i) => ({ project: `p${i + 1}`, note: `n${i + 1}` }));

  it("says nothing when there was nothing to report", () => {
    expect(noteDetail(undefined)).toBe("");
    expect(noteDetail([])).toBe("");
  });

  it("names each project under a header that doesn't presume WHICH caveat it is", () => {
    // The whole point: a decision made for the operator must SAY so. Silence reads as "it
    // went exactly as you asked", and they can only correct what they can see. The header
    // stays neutral because two different caveats (a site filed with its domain family's
    // group, a monitor taken over from a retired project) share this one block — naming
    // only one of them would mislabel the other.
    expect(noteDetail(rows(2))).toBe("\n\nAlso:\n• p1: n1\n• p2: n2");
  });

  it("truncates on the SAME line budget as the skip block", () => {
    const out = noteDetail(rows(SKIP_DETAIL_LINES + 2));
    expect(out.split("\n• ")).toHaveLength(SKIP_DETAIL_LINES + 1);
    expect(out).toContain("…and 2 more");
  });
});
