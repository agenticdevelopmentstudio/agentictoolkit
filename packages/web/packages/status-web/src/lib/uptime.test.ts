import { describe, it, expect } from "vitest";
import { uptimePercent, dayStatus, overallUptimePercent } from "./uptime";

describe("uptime math", () => {
  it("counts healthy+degraded as up", () => {
    expect(uptimePercent({ total: 100, healthy: 90, degraded: 5, down: 5 })).toBe(95);
  });
  it("null when no checks", () => {
    expect(uptimePercent({ total: 0, healthy: 0, degraded: 0, down: 0 })).toBeNull();
  });
  it("day status: >50% down is down", () => {
    expect(dayStatus({ total: 10, healthy: 2, degraded: 0, down: 8 })).toBe("down");
  });
  it("day status: some down <=50% is degraded", () => {
    expect(dayStatus({ total: 10, healthy: 7, degraded: 0, down: 3 })).toBe("degraded");
  });
  it("day status: degraded only is degraded", () => {
    expect(dayStatus({ total: 10, healthy: 8, degraded: 2, down: 0 })).toBe("degraded");
  });
  it("day status: all healthy is healthy", () => {
    expect(dayStatus({ total: 10, healthy: 10, degraded: 0, down: 0 })).toBe("healthy");
  });
});

describe("overallUptimePercent", () => {
  it("is the simple mean of each service's uptime (every service counts equally)", () => {
    expect(overallUptimePercent([
      { uptimePercent: 100 },
      { uptimePercent: 90 },
    ])).toBe(95);
  });
  it("ignores services with null uptime (no data), averaging the rest equally", () => {
    expect(overallUptimePercent([
      { uptimePercent: 99 },
      { uptimePercent: null },
      { uptimePercent: 95 },
    ])).toBe(97);
  });
  it("is null when there's no data", () => {
    expect(overallUptimePercent([])).toBeNull();
    expect(overallUptimePercent([{ uptimePercent: null }])).toBeNull();
  });
});

