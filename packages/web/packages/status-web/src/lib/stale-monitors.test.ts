import { describe, it, expect } from "vitest";
import { selectStaleMonitors, STALE_MONITOR_MS } from "./stale-monitors";
import type { LiveServiceDTO } from "./live-types";

const NOW = Date.parse("2026-06-26T00:00:00.000Z");
const daysAgo = (n: number): string => new Date(NOW - n * 86_400_000).toISOString();

function svc(over: Partial<LiveServiceDTO> = {}): LiveServiceDTO {
  return {
    slug: "ep1",
    group: "g",
    name: "Site",
    url: "https://site.example.com",
    environment: "production",
    platform: null,
    deployProject: null,
    status: "down",
    responseTimeMs: null,
    statusCode: null,
    error: "HTTP 500",
    lastCheckedAt: null,
    // Whether the host resolves is carried through for the confirm copy and selects
    // nothing — see the DNS test below.
    dnsOk: true,
    downSince: daysAgo(30),
    ...over,
  };
}

describe("selectStaleMonitors", () => {
  it("includes a down endpoint past the threshold", () => {
    const res = selectStaleMonitors([svc({ slug: "ep1" })], NOW);
    expect(res).toHaveLength(1);
    expect(res[0]).toMatchObject({ slug: "ep1", dnsOk: true, detail: "HTTP 500" });
    expect(res[0]!.ageMs).toBe(30 * 86_400_000);
  });

  it("selects the same rows whether or not the hosts RESOLVE — DNS decides nothing here", () => {
    // DNS used to gate this list in both directions: an un-resolving host was hidden
    // (the cycle was about to delete it on a 7-day DNS clock) unless NOTHING on the board
    // resolved (the cycle refused, so hiding it left it unremovable). Both are gone with
    // the clock. What the cycle deletes is decided by the platform inventory, silently and
    // with no banner, so every row that reaches here is still claimed by something —
    // resolving or not, it is a judgement call and it gets offered.
    const rows = (dnsOk: boolean): string[] =>
      selectStaleMonitors(
        [
          svc({ slug: "gone", dnsOk, error: "DNS: does not resolve", downSince: daysAgo(90) }),
          svc({ slug: "also-gone", dnsOk, downSince: daysAgo(9) }),
          svc({ slug: "alive", status: "healthy", downSince: null }),
        ],
        NOW,
      ).map((r) => r.slug);
    expect(rows(false)).toEqual(["gone", "also-gone"]);
    expect(rows(true)).toEqual(rows(false));
    // It is still REPORTED, because the confirm wording turns on it.
    expect(selectStaleMonitors([svc({ dnsOk: false })], NOW)[0]!.dnsOk).toBe(false);
  });

  it("excludes a down endpoint that hasn't been down long enough", () => {
    expect(selectStaleMonitors([svc({ downSince: daysAgo(2) })], NOW)).toEqual([]);
  });

  it("excludes healthy/degraded endpoints and down ones with no downSince", () => {
    const res = selectStaleMonitors(
      [
        svc({ slug: "h", status: "healthy", downSince: null }),
        svc({ slug: "d", status: "degraded", downSince: daysAgo(40) }),
        svc({ slug: "x", status: "down", downSince: null }), // down but unknown onset → can't judge
      ],
      NOW,
    );
    expect(res).toEqual([]);
  });

  it("skips a malformed downSince instead of surfacing it as 'NaN' old", () => {
    // A non-ISO downSince → Date.parse = NaN → ageMs = NaN. It must be SKIPPED (never
    // offered for retirement), not pass the threshold via the `NaN < x` quirk.
    const res = selectStaleMonitors([svc({ downSince: "not-a-date" })], NOW);
    expect(res).toEqual([]);
  });

  it("derives the detail from statusCode when there's no error string", () => {
    const res = selectStaleMonitors([svc({ error: null, statusCode: 503 })], NOW);
    expect(res[0]!.detail).toBe("HTTP 503");
  });

  it("sorts longest-down first", () => {
    const res = selectStaleMonitors(
      [svc({ slug: "newer", downSince: daysAgo(8) }), svc({ slug: "older", downSince: daysAgo(90) })],
      NOW,
    );
    expect(res.map((r) => r.slug)).toEqual(["older", "newer"]);
  });

  it("uses a 7-day default threshold (inclusive)", () => {
    expect(STALE_MONITOR_MS).toBe(7 * 24 * 60 * 60 * 1000);
    expect(selectStaleMonitors([svc({ downSince: daysAgo(7) })], NOW)).toHaveLength(1);
    expect(selectStaleMonitors([svc({ downSince: daysAgo(6) })], NOW)).toHaveLength(0);
  });
});
