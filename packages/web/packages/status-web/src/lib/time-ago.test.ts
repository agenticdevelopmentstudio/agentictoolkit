import { describe, it, expect } from "vitest";
import { timeAgo } from "./time-ago";

const BASE = new Date("2024-06-01T12:00:00Z").getTime();

describe("timeAgo", () => {
  it('returns "just now" for less than 60 seconds', () => {
    const iso = new Date(BASE - 30_000).toISOString();
    expect(timeAgo(iso, BASE)).toBe("just now");
  });

  it('returns "just now" for exactly 0 seconds', () => {
    const iso = new Date(BASE).toISOString();
    expect(timeAgo(iso, BASE)).toBe("just now");
  });

  it("returns minutes for less than 1 hour", () => {
    const iso = new Date(BASE - 12 * 60_000).toISOString();
    expect(timeAgo(iso, BASE)).toBe("12m");
  });

  it("returns hours for less than 1 day", () => {
    const iso = new Date(BASE - 3 * 3_600_000).toISOString();
    expect(timeAgo(iso, BASE)).toBe("3h");
  });

  it("returns days for 1 day or more", () => {
    const iso = new Date(BASE - 2 * 86_400_000).toISOString();
    expect(timeAgo(iso, BASE)).toBe("2d");
  });

  it("returns minutes at boundary: exactly 60s", () => {
    const iso = new Date(BASE - 60_000).toISOString();
    expect(timeAgo(iso, BASE)).toBe("1m");
  });

  it("returns hours at boundary: exactly 60 minutes", () => {
    const iso = new Date(BASE - 60 * 60_000).toISOString();
    expect(timeAgo(iso, BASE)).toBe("1h");
  });

  it("returns days at boundary: exactly 24 hours", () => {
    const iso = new Date(BASE - 24 * 3_600_000).toISOString();
    expect(timeAgo(iso, BASE)).toBe("1d");
  });
});
