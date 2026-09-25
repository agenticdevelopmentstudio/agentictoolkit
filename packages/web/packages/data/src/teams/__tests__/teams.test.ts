import { describe, expect, it } from "vitest";
import { toTeam, validateTeamIdentifier } from "../teams";

describe("toTeam", () => {
  it("renames name→displayName and slug→identifier", () => {
    const t = toTeam({
      id: "1",
      name: "Platform",
      slug: "com.acme.platform",
      createdAt: "c",
      updatedAt: "u",
    });
    expect(t.displayName).toBe("Platform");
    expect(t.identifier).toBe("com.acme.platform");
  });
});

describe("validateTeamIdentifier", () => {
  it("accepts reverse-domain identifiers", () => {
    expect(validateTeamIdentifier("com.acme.platform")).toBeNull();
  });

  it("rejects an empty identifier", () => {
    expect(validateTeamIdentifier("")).toMatch(/required/i);
  });

  // The backend's own teams are plain slugs (`participants`, `admins`), so a single label is the
  // COMMON shape, not an error.
  it("accepts a plain slug, hyphenated or not", () => {
    expect(validateTeamIdentifier("members")).toBeNull();
    expect(validateTeamIdentifier("platform-team")).toBeNull();
  });

  // `com.acme-` passed the old reverse-domain rule, which let a hyphen sit anywhere in a later
  // segment; it is a dangling separator all the same, and the doc says so.
  it("rejects spaces, capitals and dangling separators", () => {
    for (const bad of ["core team", "Members", "members.", "-members", "a..b", "com.acme-"]) {
      expect(validateTeamIdentifier(bad), bad).toMatch(/lowercase/i);
    }
  });
});
