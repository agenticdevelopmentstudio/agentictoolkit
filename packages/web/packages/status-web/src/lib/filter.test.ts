import { describe, it, expect } from "vitest";
import { matchesQuery } from "./filter";

describe("matchesQuery", () => {
  it("matches everything on an empty/blank query", () => {
    expect(matchesQuery("anything", "")).toBe(true);
    expect(matchesQuery("anything", "   ")).toBe(true);
  });

  it("is case-insensitive substring", () => {
    expect(matchesQuery("staging.adh deploy failed", "ADH")).toBe(true);
    expect(matchesQuery("staging.adh", "prod")).toBe(false);
  });

  it("requires all tokens (AND)", () => {
    expect(matchesQuery("testing.admin.adh deploy failed", "testing failed")).toBe(true);
    expect(matchesQuery("testing.admin.adh deploy failed", "testing deployed")).toBe(false);
  });
});
