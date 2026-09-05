import { describe, it, expect } from "vitest";
import { snapshotFreshness, snapshotStaleMs, SNAPSHOT_STALE_FLOOR_MS } from "./snapshot-staleness";

const GEN = "2024-06-01T12:00:00.000Z";
const gen = Date.parse(GEN);
/** An ISO `ms` before `generatedAt`. */
const lag = (ms: number): string => new Date(gen - ms).toISOString();

describe("snapshotStaleMs", () => {
  it("floors at 5min when interval is small/absent", () => {
    expect(snapshotStaleMs(undefined)).toBe(SNAPSHOT_STALE_FLOOR_MS);
    expect(snapshotStaleMs(null)).toBe(SNAPSHOT_STALE_FLOOR_MS);
    expect(snapshotStaleMs(60_000)).toBe(SNAPSHOT_STALE_FLOOR_MS); // 60s×5 = 5min = floor
  });

  it("scales to 5× the interval once past the floor", () => {
    expect(snapshotStaleMs(120_000)).toBe(600_000); // 120s×5 = 10min
  });
});

describe("snapshotFreshness", () => {
  it("is fresh when there is no probe yet (null lastCycleAt)", () => {
    expect(snapshotFreshness(null, GEN, 60_000)).toBe("fresh");
    expect(snapshotFreshness(undefined, GEN)).toBe("fresh");
  });

  it("is fresh when generatedAt is missing", () => {
    expect(snapshotFreshness(lag(10 * 60_000), null)).toBe("fresh");
  });

  it("is fresh within the stale window", () => {
    expect(snapshotFreshness(lag(4 * 60_000), GEN, 60_000)).toBe("fresh"); // 4min < 5min
  });

  it("is stale just past the window, before very-stale", () => {
    expect(snapshotFreshness(lag(6 * 60_000), GEN, 60_000)).toBe("stale"); // 6min > 5min, < 15min
  });

  it("is very-stale past 3× the window", () => {
    expect(snapshotFreshness(lag(16 * 60_000), GEN, 60_000)).toBe("very-stale"); // 16min > 15min
  });

  it("scales the window with the probe interval (no false trip when interval is raised)", () => {
    // interval 120s → window 10min; a 6min lag that trips at the default interval is fresh here.
    expect(snapshotFreshness(lag(6 * 60_000), GEN, 120_000)).toBe("fresh");
    expect(snapshotFreshness(lag(11 * 60_000), GEN, 120_000)).toBe("stale");
  });

  it("is NaN-safe: an unparseable date never shows a banner", () => {
    expect(snapshotFreshness("not-a-date", GEN, 60_000)).toBe("fresh");
    expect(snapshotFreshness(lag(20 * 60_000), "not-a-date", 60_000)).toBe("fresh");
  });

  it("does not trip on a negative lag (probe newer than the read clock)", () => {
    expect(snapshotFreshness(new Date(gen + 30_000).toISOString(), GEN, 60_000)).toBe("fresh");
  });
});
