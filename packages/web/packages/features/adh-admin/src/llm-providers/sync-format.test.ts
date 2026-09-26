import { describe, expect, it, vi, afterEach, afterAll } from "vitest";
import { formatRelativeTime, finiteCount, normalizeNaiveUtc } from "./sync-format";

// Prove TZ-independence: run the naive-timestamp cases under a decidedly non-UTC
// zone. Node re-reads process.env.TZ via tzset() on assignment, so subsequent
// naive `Date` parsing uses this offset (the very thing the fix must cancel out).
const ORIGINAL_TZ = process.env.TZ;
process.env.TZ = "America/Los_Angeles";
afterAll(() => {
  process.env.TZ = ORIGINAL_TZ;
});

// Compare against the same Intl formatter the helper uses so the assertions
// validate the unit/rounding choice without hardcoding an English string (CI
// locale-independent).
const rel = (value: number, unit: Intl.RelativeTimeFormatUnit) =>
  new Intl.RelativeTimeFormat(undefined, { numeric: "auto" }).format(value, unit);

describe("formatRelativeTime", () => {
  afterEach(() => vi.useRealTimers());

  it("returns 'never' for null, undefined, empty, or unparseable input", () => {
    expect(formatRelativeTime(null)).toBe("never");
    expect(formatRelativeTime(undefined)).toBe("never");
    expect(formatRelativeTime("")).toBe("never");
    expect(formatRelativeTime("not-a-date")).toBe("never");
  });

  it("picks minutes for a few-minutes-old timestamp", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-07-22T12:00:00Z"));
    expect(formatRelativeTime("2026-07-22T11:57:00Z")).toBe(rel(-3, "minute"));
  });

  it("escalates the unit for hours and days", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-07-22T12:00:00Z"));
    expect(formatRelativeTime("2026-07-22T09:00:00Z")).toBe(rel(-3, "hour"));
    expect(formatRelativeTime("2026-07-20T12:00:00Z")).toBe(rel(-2, "day"));
  });

  it("reads a naive PG-text timestamp as UTC, not local time (TZ-independent)", () => {
    // Sanity: we really are running under a non-UTC zone, so a bug that parsed the
    // naive string as local would produce the WRONG offset and fail this test.
    expect(new Date("2026-07-22 07:55:00").getTimezoneOffset()).not.toBe(0);

    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-07-22T12:00:00Z"));
    // Exactly the shape `catalog_sync_runs.last_run_at` arrives as (naive UTC, space
    // separator, fractional seconds) — 5 minutes before "now" ⇒ "5 minutes ago".
    expect(formatRelativeTime("2026-07-22 11:55:00.123")).toBe(rel(-5, "minute"));
    // Second-precision naive shape (no fraction) resolves the same instant.
    expect(formatRelativeTime("2026-07-22 11:55:00")).toBe(rel(-5, "minute"));
  });
});

describe("normalizeNaiveUtc", () => {
  it("Z-suffixes a naive PG-text timestamp, leaving zoned/ISO strings alone", () => {
    expect(normalizeNaiveUtc("2026-07-22 03:15:00.123")).toBe("2026-07-22T03:15:00.123Z");
    expect(normalizeNaiveUtc("2026-07-22 03:15:00")).toBe("2026-07-22T03:15:00Z");
    // Already-zoned / ISO inputs pass through unchanged.
    expect(normalizeNaiveUtc("2026-07-22T03:15:00Z")).toBe("2026-07-22T03:15:00Z");
    expect(normalizeNaiveUtc("2026-07-22T03:15:00+00:00")).toBe("2026-07-22T03:15:00+00:00");
  });
});

describe("finiteCount", () => {
  it("returns the number for finite numeric input", () => {
    expect(finiteCount(0)).toBe(0);
    expect(finiteCount(42)).toBe(42);
    expect(finiteCount("7")).toBe(7);
  });

  it("falls back to 0 for null, undefined, non-numeric, or non-finite input", () => {
    expect(finiteCount(null)).toBe(0);
    expect(finiteCount(undefined)).toBe(0);
    expect(finiteCount("nope")).toBe(0);
    expect(finiteCount({})).toBe(0);
    expect(finiteCount(Number.POSITIVE_INFINITY)).toBe(0);
    expect(finiteCount(Number.NaN)).toBe(0);
  });
});
