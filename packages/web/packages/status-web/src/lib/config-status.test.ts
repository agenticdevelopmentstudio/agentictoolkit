import { describe, expect, it } from "vitest";
import { endpointConfigStatus, endpointUnconfigured, type EndpointLike } from "./config-status";

// The classification RULES are the engine's and are tested there (engine/classify.test.ts).
// What is tested here is the one thing this module adds: the fold of this board's second
// opt-out — `isActive: false`, the site's master monitoring switch — onto the engine's
// single `ignoreProjectWarning`. Every case below turns on that field.
const ep = (over: Partial<EndpointLike> = {}): EndpointLike => ({
  kind: "frontend",
  platform: null,
  deployProject: null,
  ignoreProjectWarning: false,
  ...over,
});

describe("the monitoring switch folds into the engine's opt-out", () => {
  it("never flags a site whose monitoring is switched off — paused, not unconfigured", () => {
    expect(endpointUnconfigured(ep({ isActive: false }))).toBe(false);
  });

  it("an ABSENT isActive is not read as disabled (the field is optional)", () => {
    // A caller that doesn't carry the field — the engine's EndpointLite, an older
    // payload — must keep its warning rather than silently lose it.
    expect(endpointUnconfigured(ep({ isActive: undefined }))).toBe(true);
    expect(endpointUnconfigured(ep({ isActive: true }))).toBe(true);
  });

  it("monitoring switched off moves an unwired endpoint to ignored", () => {
    expect(endpointConfigStatus(ep({ isActive: false }))).toBe("ignored");
  });

  it("a WIRED endpoint stays configured when monitoring is off — paused is not a config gap", () => {
    // The switch is read only in the engine's unwired branch: pausing a fully-wired site
    // must not downgrade it to "ignored", or the Config badge would misreport a healthy
    // setup.
    expect(endpointConfigStatus(ep({ platform: "vercel", deployProject: "p", isActive: false }))).toBe("configured");
  });

  it("the two predicates agree about the SAME endpoint, paused or not", () => {
    // They must not diverge here: `endpointUnconfigured` delegates to this module's
    // wrapper, not to the engine's own predicate, which would classify the raw row and
    // miss the fold.
    const cases = [ep({ isActive: false }), ep({ isActive: true }), ep({ platform: "vercel", deployProject: "p", isActive: false })];
    for (const c of cases) expect(endpointUnconfigured(c)).toBe(endpointConfigStatus(c) === "unconfigured");
  });
});
