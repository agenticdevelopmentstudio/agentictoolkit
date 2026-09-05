import { describe, it, expect } from "vitest";
import { platformFilterOptions, allPlatformKeys, PLATFORM_NONE } from "./platform-filter";

describe("platformFilterOptions", () => {
  it("always offers the known platforms in canonical order, even when zero endpoints use one (railway regression)", () => {
    // Production steady state: vercel + cloudflare sites, NO railway site — railway
    // must still be a filter row.
    const opts = platformFilterOptions([{ platform: "vercel" }, { platform: "vercel" }, { platform: "cloudflare" }]);
    expect(opts.map((o) => o.key)).toEqual(["vercel", "railway", "cloudflare", "crunchy"]);
  });

  it("offers every known platform even when NONE are present", () => {
    expect(platformFilterOptions([]).map((o) => o.key)).toEqual(["vercel", "railway", "cloudflare", "crunchy"]);
  });

  it("appends a 'no platform' row only when some endpoint is unwired", () => {
    expect(platformFilterOptions([{ platform: "vercel" }]).some((o) => o.key === PLATFORM_NONE)).toBe(false);
    expect(platformFilterOptions([{ platform: "vercel" }, { platform: null }]).at(-1)).toEqual({
      key: PLATFORM_NONE,
      label: "no platform",
    });
  });

  it("appends any unknown platform value present, after the known ones and before 'no platform'", () => {
    const opts = platformFilterOptions([{ platform: "fly" }, { platform: null }]);
    expect(opts.map((o) => o.key)).toEqual(["vercel", "railway", "cloudflare", "crunchy", "fly", PLATFORM_NONE]);
  });

  it("does not duplicate a known platform that is also present", () => {
    const opts = platformFilterOptions([{ platform: "railway" }, { platform: "railway" }]);
    expect(opts.map((o) => o.key)).toEqual(["vercel", "railway", "cloudflare", "crunchy"]);
  });

  it("allPlatformKeys covers every known platform plus the none bucket", () => {
    expect(allPlatformKeys()).toEqual(new Set(["vercel", "railway", "cloudflare", "crunchy", PLATFORM_NONE]));
  });
});
