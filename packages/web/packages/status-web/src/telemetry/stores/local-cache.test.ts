import { describe, it, expect } from "vitest";
import { parseSnapshot } from "./local-cache";
import type { TelemetrySnapshot } from "../types";

const snap: TelemetrySnapshot = {
  generatedAt: "2026-06-13T12:00:00.000Z",
  errors: [
    {
      id: "1",
      issueKey: "1",
      project: "hub",
      title: "boom",
      culprit: null,
      level: "error",
      count: 3,
      userCount: 1,
      firstSeen: null,
      lastSeen: null,
      permalink: null,
    },
  ],
  analytics: [{ metric: "pageviews", window: "24h", scope: "all", value: 10, capturedAt: "2026-06-13T12:00:00.000Z" }],
};

describe("parseSnapshot", () => {
  it("round-trips a stored snapshot", () => {
    expect(parseSnapshot(JSON.stringify(snap))).toEqual(snap);
  });

  it("returns null for null / empty input", () => {
    expect(parseSnapshot(null)).toBeNull();
    expect(parseSnapshot("")).toBeNull();
  });

  it("returns null for malformed JSON", () => {
    expect(parseSnapshot("{not json")).toBeNull();
  });

  it("rejects wrong-shape objects (bad types / missing arrays / null)", () => {
    expect(parseSnapshot(JSON.stringify(null))).toBeNull();
    expect(parseSnapshot(JSON.stringify({ generatedAt: "x" }))).toBeNull();
    expect(parseSnapshot(JSON.stringify({ generatedAt: 1, errors: [], analytics: [] }))).toBeNull();
    expect(parseSnapshot(JSON.stringify({ generatedAt: "x", errors: "nope", analytics: [] }))).toBeNull();
  });
});
