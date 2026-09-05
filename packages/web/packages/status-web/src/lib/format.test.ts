import { describe, it, expect } from "vitest";
import { shortSha, commitFirstLine } from "./format";

describe("shortSha", () => {
  it("returns the first 7 chars of a hash, or null", () => {
    expect(shortSha("abcdef1234567")).toBe("abcdef1");
    expect(shortSha("abc")).toBe("abc"); // shorter than 7 → unchanged
    expect(shortSha(null)).toBeNull();
    expect(shortSha(undefined)).toBeNull();
    expect(shortSha("")).toBeNull(); // empty → no commit
  });
});

describe("commitFirstLine", () => {
  it("returns the subject line (first line), or null", () => {
    expect(commitFirstLine("subject\n\nbody text")).toBe("subject");
    expect(commitFirstLine("just one line")).toBe("just one line");
    expect(commitFirstLine(null)).toBeNull();
    expect(commitFirstLine(undefined)).toBeNull();
    expect(commitFirstLine("")).toBeNull();
  });

  it("caps the subject at `max` chars (default 200)", () => {
    const long = "x".repeat(250);
    expect(commitFirstLine(long)).toHaveLength(200);
    expect(commitFirstLine(long, 10)).toHaveLength(10);
    expect(commitFirstLine("short", 200)).toBe("short");
  });
});
