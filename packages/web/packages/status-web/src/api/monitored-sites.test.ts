// Runtime unit tests for status's monitoring-config mappers. The important case is
// `toEndpoint`: the backend has no `environment` column, so the mapper must default
// the frontend-only field to null rather than leak `undefined` into the view.
import { describe, expect, it } from "vitest";
import { toGroup, toSite, toEndpoint } from "./monitored-sites";

const as = <F extends (arg: never) => unknown>(o: Record<string, unknown>): Parameters<F>[0] =>
  o as unknown as Parameters<F>[0];

describe("status monitored-sites mappers", () => {
  it("toGroup passes group fields through", () => {
    const g = toGroup(as<typeof toGroup>({ id: "g", slug: "s", name: "N", retentionDays: 14 }));
    expect(g).toEqual({ id: "g", slug: "s", name: "N", retentionDays: 14 });
  });

  it("toSite renames siteGroupId→groupId", () => {
    const s = toSite(as<typeof toSite>({ id: "s1", slug: "site", name: "Site", siteGroupId: "g1" }));
    expect(s.groupId).toBe("g1");
  });

  it("toEndpoint defaults the missing-from-backend `environment` to null", () => {
    // The backend never returns `environment` (no such column).
    const e = toEndpoint(
      as<typeof toEndpoint>({ id: "e", siteId: "s", url: "https://x", kind: "http", expectedStatus: 200, checkIntervalSeconds: 60, isActive: true }),
    );
    expect(e.environment).toBeNull();
  });

  it("toEndpoint keeps an explicitly-provided environment", () => {
    const e = toEndpoint(
      as<typeof toEndpoint>({ id: "e", siteId: "s", url: "https://x", kind: "http", environment: "production", expectedStatus: 200, checkIntervalSeconds: 60, isActive: true }),
    );
    expect(e.environment).toBe("production");
  });

  it("toEndpoint defaults DNS record checks to on when the backend omits them", () => {
    // A row created before the dns_check_* columns existed reads them as undefined;
    // the view must default each to true (the historic "resolve via any record" behavior).
    const e = toEndpoint(
      as<typeof toEndpoint>({ id: "e", siteId: "s", url: "https://x", kind: "http", expectedStatus: 200, checkIntervalSeconds: 60, isActive: true }),
    );
    expect(e.dnsCheckA).toBe(true);
    expect(e.dnsCheckAaaa).toBe(true);
    expect(e.dnsCheckCname).toBe(true);
  });

  it("toEndpoint preserves an explicit `false` DNS check (no `?? true` clobber)", () => {
    const e = toEndpoint(
      as<typeof toEndpoint>({ id: "e", siteId: "s", url: "https://x", kind: "http", dnsCheckCname: false, expectedStatus: 200, checkIntervalSeconds: 60, isActive: true }),
    );
    expect(e.dnsCheckCname).toBe(false);
    expect(e.dnsCheckA).toBe(true);
  });
});
