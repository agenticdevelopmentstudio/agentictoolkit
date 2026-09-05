import { describe, it, expect } from "vitest";
import { isSameSnapshot } from "./use-live-snapshot";
import { liveSnapshot } from "../lib/live-snapshot.fixture";

const snap = (generatedAt: string) => liveSnapshot({ generatedAt });

describe("isSameSnapshot (cheap re-delivery skip)", () => {
  it("never matches when there is no previous snapshot", () => {
    expect(isSameSnapshot(null, snap("2026-06-30T00:00:00.000Z"))).toBe(false);
  });

  it("matches the identical object", () => {
    const s = snap("2026-06-30T00:00:00.000Z");
    expect(isSameSnapshot(s, s)).toBe(true);
  });

  it("matches a different object with the same build clock (one frame re-delivered)", () => {
    const a = snap("2026-06-30T00:00:00.000Z");
    const b = snap("2026-06-30T00:00:00.000Z");
    expect(a).not.toBe(b);
    expect(isSameSnapshot(a, b)).toBe(true);
  });

  it("does NOT match distinct build clocks (a new build)", () => {
    expect(isSameSnapshot(snap("2026-06-30T00:00:00.000Z"), snap("2026-06-30T00:01:00.000Z"))).toBe(false);
  });
});
