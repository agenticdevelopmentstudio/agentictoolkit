import { describe, it, expect } from "vitest";
import { parsePlatformHealthTarget, platformHealthTarget } from "../src/board/derive-problems";
import { boardTargetKey, parseBoardTarget } from "../src/board/target-key";

describe("boardTargetKey", () => {
  it("blanks the env segment off Railway — one Vercel project IS one env", () => {
    expect(boardTargetKey("vercel", "hub-help-testing", "production")).toBe("vercel|hub-help-testing|");
  });

  it("keeps the env segment for Railway — one project serves many envs", () => {
    expect(boardTargetKey("railway", "adh-backend", "scratch1")).toBe("railway|adh-backend|scratch1");
  });

  it("lowercases the Railway env so 'Scratch1' and 'scratch1' are one target", () => {
    expect(boardTargetKey("railway", "adh-backend", "Scratch1")).toBe("railway|adh-backend|scratch1");
  });

  it("canonicalises cloudflare-pages to cloudflare", () => {
    expect(boardTargetKey("cloudflare-pages", "docs", "production")).toBe("cloudflare|docs|");
  });

  it("agrees with the vendored deployTargetKey when the id is the project name", async () => {
    const { deployTargetKey } = await import("@agentic-toolkit/deploy-platform");
    for (const [p, proj, env] of [
      ["vercel", "hub-help-testing", "production"],
      ["railway", "adh-backend", "scratch1"],
      ["cloudflare-pages", "docs", "production"],
    ] as const) {
      expect(boardTargetKey(p, proj, env)).toBe(deployTargetKey(p, proj, env));
    }
  });

  it("returns null when the platform or id is missing — never a half key", () => {
    expect(boardTargetKey(null, "x", "production")).toBeNull();
    expect(boardTargetKey("vercel", null, "production")).toBeNull();
    expect(boardTargetKey("vercel", "", "production")).toBeNull();
  });

  it("round-trips through parseBoardTarget", () => {
    expect(parseBoardTarget("railway|adh-backend|scratch1")).toEqual({
      platform: "railway",
      id: "adh-backend",
      environment: "scratch1",
    });
    expect(parseBoardTarget("vercel|hub-help-testing|")).toEqual({
      platform: "vercel",
      id: "hub-help-testing",
      environment: "",
    });
  });

  it("rejects a target that is not three segments", () => {
    expect(parseBoardTarget("vercel|hub-help-testing")).toBeNull();
    expect(parseBoardTarget("")).toBeNull();
  });

  // `|` is the separator, so a segment holding one is ESCAPED. Refusing to mint instead
  // (round 1) meant a Railway environment named `prod|eu` — free-form, on the only platform
  // that populates that segment — produced NO key, so nothing indexed it, nothing owned it,
  // and a failed build raised no Problem at all while its open ledger row closed silently as
  // `unmonitored`. Railway is the reachable case: project and environment names are both
  // free-form there.
  it("escapes the separator instead of refusing to mint", () => {
    expect(boardTargetKey("railway", "adh-backend", "prod|eu")).toBe("railway|adh-backend|prod%7Ceu");
    expect(boardTargetKey("railway", "adh|backend", "scratch1")).toBe("railway|adh%7Cbackend|scratch1");
    // Still exactly three segments — the invariant every consumer reads by.
    expect(boardTargetKey("railway", "adh|backend", "prod|eu")!.split("|")).toHaveLength(3);
  });

  it("escapes the escape character too, so the mapping stays injective", () => {
    // Without `%` → `%25`, an id of `adh%7Cbackend` and one of `adh|backend` would mint the
    // SAME target — two projects sharing one Problem row.
    expect(boardTargetKey("railway", "adh%7Cbackend", "scratch1")).toBe("railway|adh%257Cbackend|scratch1");
    expect(boardTargetKey("railway", "adh%7Cbackend", "scratch1")).not.toBe(
      boardTargetKey("railway", "adh|backend", "scratch1"),
    );
  });

  it("round-trips every segment a provider can name, separators and all", () => {
    for (const [p, id, env] of [
      ["railway", "adh-backend", "prod|eu"],
      ["railway", "adh%backend", "scratch1"],
      ["railway", "adh%7Cbackend", "prod|eu"],
      ["railway", "adh|backend", "100%|prod"],
      ["railway", "adh-backend", "scratch1"],
    ] as const) {
      const target = boardTargetKey(p, id, env);
      expect(target).not.toBeNull();
      // The env comes back LOWERCASED — that is the domain rule, not a round-trip loss.
      expect(parseBoardTarget(target!)).toEqual({ platform: p, id, environment: env.toLowerCase() });
    }
  });

  it("mints only targets its own parser can read — the round-trip is total", () => {
    for (const [p, id, env] of [
      ["railway", "adh|backend", "scratch1"],
      ["railway", "adh-backend", "scratch|1"],
      ["railway", "adh-backend", "Scratch1"],
      ["vercel", "hub-help-testing", "production"],
      ["vercel", "hub|help", "prod|uction"],
      ["cloudflare-pages", "docs", null],
    ] as const) {
      const target = boardTargetKey(p, id, env);
      expect(target).not.toBeNull();
      expect(parseBoardTarget(target!)).not.toBeNull();
    }
  });
});

// A platform-health target is TWO segments and deliberately NOT minted by boardTargetKey
// (a provider is not a deploy target, and a third segment would orphan every live row).
// It has a minter and, since item 4.2, an inverse — because three readers had each spelled
// the prefix themselves, which is the same two-producers shape the minter exists to avoid.
describe("platformHealthTarget", () => {
  it("is two segments with no trailing pipe — the spelling already in the issues table", () => {
    expect(platformHealthTarget("vercel")).toBe("platform-health|vercel");
    expect(platformHealthTarget("cloudflare-pages")).toBe("platform-health|cloudflare-pages");
  });

  it("round-trips, including the raw platform spelling boardTargetKey would canonicalise", () => {
    for (const source of ["vercel", "railway", "cloudflare-pages", "crunchy"] as const) {
      expect(parsePlatformHealthTarget(platformHealthTarget(source))).toBe(source);
    }
  });

  it("answers null for every target that is not one — the 'is it?' and 'which?' are one call", () => {
    expect(parsePlatformHealthTarget("vercel|hub-help-testing|")).toBeNull();
    expect(parsePlatformHealthTarget("railway|adh-backend|scratch1")).toBeNull();
    // A bare endpoint id: an HTTP target, and the shape most likely to be mis-sniffed.
    expect(parsePlatformHealthTarget("ep-1")).toBeNull();
    expect(parsePlatformHealthTarget("")).toBeNull();
  });
});
