import { describe, it, expect } from "vitest";
import {
  BOARD_STALE_MS,
  BOARD_DATA_STALE_CYCLES,
  boardDataStaleMs,
  isBoardStale,
  boardDataFreshness,
} from "./board-staleness";
import { SNAPSHOT_STALE_FLOOR_MS } from "./snapshot-staleness";

describe("isBoardStale", () => {
  const now = Date.parse("2026-08-02T12:00:00.000Z");

  it("a board generated well within the window is fresh", () => {
    const generatedAt = new Date(now - 1000).toISOString();
    expect(isBoardStale(generatedAt, now)).toBe(false);
  });

  it("a board generated exactly at the threshold is not yet stale", () => {
    const generatedAt = new Date(now - BOARD_STALE_MS).toISOString();
    expect(isBoardStale(generatedAt, now)).toBe(false);
  });

  it("a board generated past the threshold is stale", () => {
    const generatedAt = new Date(now - BOARD_STALE_MS - 1).toISOString();
    expect(isBoardStale(generatedAt, now)).toBe(true);
  });

  it("an unparseable generatedAt fails CLOSED — stale, not fresh, because we cannot tell", () => {
    expect(isBoardStale("not-a-date", now)).toBe(true);
  });
});

// Fix Round 4 group 6. A wedged monitor keeps re-stamping `generatedAt`, so every case
// below pairs a PERFECTLY FRESH derivation clock with a data clock that isn't — which
// is precisely the state `isBoardStale` cannot see.
describe("boardDataFreshness", () => {
  const generatedAt = "2026-08-02T12:00:00.000Z";
  const genMs = Date.parse(generatedAt);
  const windowMs = boardDataStaleMs();

  it("a board derived from observations it just made is current", () => {
    expect(boardDataFreshness(genMs - 1000, generatedAt)).toBe("current");
    // …and `isBoardStale` agrees the read itself is fine, so nothing folds to null.
    expect(isBoardStale(generatedAt, genMs)).toBe(false);
  });

  it("data exactly at the threshold is not yet stale", () => {
    expect(boardDataFreshness(genMs - windowMs, generatedAt)).toBe("current");
  });

  it("data past the threshold is frozen even though the board itself is brand new", () => {
    expect(boardDataFreshness(genMs - windowMs - 1, generatedAt)).toBe("frozen");
    // The point of the whole fix: the OTHER rule reads this same board as perfectly
    // fresh, because it is. Neither check can stand in for the other.
    expect(isBoardStale(generatedAt, genMs)).toBe(false);
  });

  it("an unparseable generatedAt fails CLOSED, matching isBoardStale", () => {
    expect(boardDataFreshness(genMs, "not-a-date")).toBe("frozen");
  });

  it("a data clock slightly AHEAD of the derivation clock is not stale — clock jitter, not a wedge", () => {
    expect(boardDataFreshness(genMs + 500, generatedAt)).toBe("current");
  });

  // Fix Round 2 item C3. A board resting on NO observations is still not health — the
  // caller keeps folding it to a null board — but it is NOT the wedged-monitor verdict
  // either, and the two must be distinguishable: "nothing to observe" is the normal state
  // of a roster with no endpoints, and reporting it as a broken monitor sent a fresh
  // install to debug a monitor that was working perfectly.
  it("a board resting on NO observations reads no-data, NOT frozen", () => {
    expect(boardDataFreshness(null, generatedAt)).toBe("no-data");
  });

  it("no-data does not depend on the cadence — there is no age to scale", () => {
    expect(boardDataFreshness(null, generatedAt, 3600_000)).toBe("no-data");
    expect(boardDataFreshness(null, "not-a-date")).toBe("no-data");
  });
});

// Fix Round 2 item C2. The window used to be the bare 5-minute SNAPSHOT floor under a
// comment claiming it tracked the backend scheduler's cadence-scaled `staleAfterMs`.
describe("boardDataStaleMs", () => {
  const generatedAt = "2026-08-02T12:00:00.000Z";
  const genMs = Date.parse(generatedAt);

  /** The backend's own full-sync cadence — `config.deploySyncIntervalMs`, which is what
   *  rewrites the platform-sample heartbeat and is therefore the slowest fact the data
   *  clock can rest on. Spelled out here rather than imported because it lives in the
   *  backend's `src/config.ts`, on the other side of the wire from this client. */
  const platformSampleCadenceMs = (probeIntervalMs: number): number =>
    Math.max(300_000, probeIntervalMs * 5);

  it("scales with the probe interval instead of pinning a fixed 5 minutes", () => {
    // `PROBE_INTERVAL_SECONDS=3600` is the value this repo itself runs under
    // (`playwright.auth.config.ts`, and the verify-status-backend skill). Under the fixed
    // window every fact was older than 300s five minutes after boot, so `board === null`
    // and the entire board was replaced by UnknownBoardPanel — permanently.
    const hourly = 3600_000;
    expect(boardDataStaleMs(hourly)).toBeGreaterThan(10 * 60_000);
    expect(boardDataFreshness(genMs - 10 * 60_000, generatedAt, hourly)).toBe("current");
    // …and the same 10-minute-old fact IS frozen at the default cadence, so the scaling
    // is doing the work rather than the window simply having been widened for everyone.
    expect(boardDataFreshness(genMs - 10 * 60_000 - 1, generatedAt, 60_000)).toBe("frozen");
  });

  it("is STRICTLY greater than the platform-sample cadence at every probe interval", () => {
    // A window that merely EQUALS the write cadence is crossed at the tail of every
    // cycle by construction — the fact is written at the end of a cycle, so its age
    // reaches a full cadence just before the next write. That is what made the board
    // flap to unknown once per cycle on a fleet with no HTTP endpoints, where the
    // platform sample IS the heartbeat.
    for (const probeIntervalMs of [1_000, 15_000, 60_000, 300_000, 3600_000]) {
      expect(boardDataStaleMs(probeIntervalMs)).toBeGreaterThan(platformSampleCadenceMs(probeIntervalMs));
    }
    // The tail-of-cycle lag itself — one whole cadence — must read current, not frozen.
    const cadence = platformSampleCadenceMs(60_000);
    expect(boardDataFreshness(genMs - cadence, generatedAt, 60_000)).toBe("current");
  });

  it("an unknown cadence falls back to the widest window, never a narrower one", () => {
    // No `probeIntervalMs` at all (an older backend, or the live snapshot not landed
    // yet) must not tighten the rule — an unknown cadence can only delay the verdict.
    expect(boardDataStaleMs()).toBe(SNAPSHOT_STALE_FLOOR_MS * BOARD_DATA_STALE_CYCLES);
    expect(boardDataStaleMs(null)).toBe(boardDataStaleMs());
    expect(boardDataStaleMs(0)).toBe(boardDataStaleMs());
    expect(boardDataStaleMs()).toBeGreaterThanOrEqual(SNAPSHOT_STALE_FLOOR_MS);
  });

  it("needs at least two cycles of headroom for the tail-of-cycle rule to hold", () => {
    expect(BOARD_DATA_STALE_CYCLES).toBeGreaterThanOrEqual(2);
  });
});
