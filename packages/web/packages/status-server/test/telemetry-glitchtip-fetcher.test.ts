import { describe, it, expect, vi, afterEach } from "vitest";
import { glitchtipFetcher, mapIssues, PAGE_LIMIT } from "../src/telemetry/fetchers/glitchtip";

// The fetcher's CONTRACT with `errorsStore`, which is the only thing that makes the store's
// sweep safe. The store reads "absent from this set" as "resolved upstream", so it depends
// on two claims this file makes and nothing else can check: `ok` means the poll really
// answered, and `complete` means the answer was the whole set. Both used to be wrong in the
// same direction — toward a confident empty answer — which is the direction that mass-
// resolves the errors table and pages an all-clear in the middle of a live incident.

const ENV = {
  GLITCHTIP_URL: "https://glitchtip.example/",
  GLITCHTIP_API_TOKEN: "tok",
  GLITCHTIP_ORG: "adh",
};

function issue(id: string) {
  return { id, title: `boom ${id}`, project: { slug: "adh" }, level: "error", count: 1 };
}

/** Stub `fetch` with one canned response. Returns the URL it was called with. */
function stubFetch(body: unknown, init: { ok?: boolean; status?: number } = {}) {
  const calls: string[] = [];
  vi.stubGlobal("fetch", async (url: string) => {
    calls.push(url);
    return { ok: init.ok ?? true, status: init.status ?? 200, json: async () => body };
  });
  return calls;
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("glitchtipFetcher — is this answer usable", () => {
  it("no-ops green when unconfigured, so nothing is ever polled or swept", async () => {
    const r = await glitchtipFetcher({}).fetch();
    expect(r).toMatchObject({ ok: true, items: [] });
  });

  it("reports a short page as COMPLETE", async () => {
    stubFetch([issue("a"), issue("b")]);
    const r = await glitchtipFetcher(ENV).fetch();
    expect(r.ok).toBe(true);
    expect(r.complete).toBe(true);
    expect(r.items.map((i) => i.issueKey)).toEqual(["a", "b"]);
  });

  // A FULL page is presumed truncated. Sweeping on it would resolve every issue past the
  // page edge and the next poll would reopen them — a project whose issues straddle the
  // boundary flapping open/closed every cycle, forever.
  it("reports a FULL page as incomplete", async () => {
    stubFetch(Array.from({ length: PAGE_LIMIT }, (_, i) => issue(`i${i}`)));
    const r = await glitchtipFetcher(ENV).fetch();
    expect(r.ok).toBe(true);
    expect(r.complete).toBe(false);
  });

  it("asks for exactly one page of PAGE_LIMIT unresolved issues", async () => {
    const calls = stubFetch([]);
    await glitchtipFetcher(ENV).fetch();
    expect(calls[0]).toBe(
      `https://glitchtip.example/api/0/organizations/adh/issues/?query=is:unresolved&limit=${PAGE_LIMIT}`,
    );
  });

  // THE one that matters. A 200 whose body is not a list — an error envelope, a
  // maintenance page, an auth-proxy interstitial, a `{results:[…]}` wrapper — is a FAILED
  // poll, not an empty one. It used to return `ok: true, items: []`, which is exactly the
  // value that tells a reconciling store "GlitchTip has nothing unresolved".
  it.each([
    [{ detail: "Authentication credentials were not provided." }],
    [{ results: [{ id: "a" }] }],
    ["<html>maintenance</html>"],
    [null],
  ])("treats a non-array 200 body as a failed poll: %s", async (body) => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    stubFetch(body);
    expect(await glitchtipFetcher(ENV).fetch()).toMatchObject({ ok: false, items: [] });
  });

  it("treats an HTTP error as a failed poll", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    stubFetch([], { ok: false, status: 502 });
    expect(await glitchtipFetcher(ENV).fetch()).toMatchObject({ ok: false, items: [] });
  });

  it("treats a thrown fetch as a failed poll", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    vi.stubGlobal("fetch", async () => {
      throw new Error("ECONNREFUSED");
    });
    expect(await glitchtipFetcher(ENV).fetch()).toMatchObject({ ok: false, items: [] });
  });
});

describe("mapIssues", () => {
  // `projectSlug` falls back slug → name → "unknown", so the project segment the board
  // keys `errors|<project>` off is NOT safe by construction — which is why
  // `errorsTarget` escapes it.
  it("falls back through slug, name, then unknown", () => {
    const [a, b, c] = mapIssues([
      { id: "1", title: "t", project: { slug: "adh", name: "ADH" } },
      { id: "2", title: "t", project: { name: "Some Team's App" } },
      { id: "3", title: "t", project: null },
    ]);
    expect([a!.project, b!.project, c!.project]).toEqual(["adh", "Some Team's App", "unknown"]);
  });

  it("parses GlitchTip's string counts and drops unparseable timestamps", () => {
    const [i] = mapIssues([
      { id: "1", title: "t", count: "42", firstSeen: "not-a-date", lastSeen: "2026-08-18T00:00:00Z" },
    ]);
    expect(i).toMatchObject({ count: 42, firstSeen: null, lastSeen: "2026-08-18T00:00:00.000Z" });
  });
});
