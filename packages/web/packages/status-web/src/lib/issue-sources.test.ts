import { describe, it, expect } from "vitest";
import { ISSUE_SOURCES, SOURCE_LABEL } from "./issue-sources";

describe("issue sources", () => {
  it("includes dns as a first-class source with a label", () => {
    expect(ISSUE_SOURCES).toContain("dns");
    expect(SOURCE_LABEL.dns).toBe("DNS");
    // Every source has a label.
    for (const s of ISSUE_SOURCES) expect(SOURCE_LABEL[s]).toBeTruthy();
  });
});
