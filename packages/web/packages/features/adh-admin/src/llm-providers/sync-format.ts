// Pure presentation helper for the catalog SyncPanel, kept separate from the
// component so the (edge-case-laden) relative-time formatting is unit-testable
// without a DOM — mirrors connection-spec-draft.ts's pure-conversion split.
//
// Near-copies of `formatRelativeTime` live in `@agentic-toolkit/messaging`
// (src/components/util.ts, also in the toolkit's ActivityFeed) and in the
// community app (app/discussions/discussion-api.ts, alongside its own naive-date
// coercion). Neither is importable here: messaging isn't a dependency of this app
// and doesn't export util.ts from its barrel or its `./components/*` (.tsx-only)
// subpath, and the community copy is app-private in another Next app. Both also
// lack what the SyncPanel needs — the naive-UTC coercion and the "never" fallback.
// Adding a dependency (or a new shared package) for ~15 lines isn't worth it.

const RELATIVE_DIVISIONS: Array<{ amount: number; unit: Intl.RelativeTimeFormatUnit }> = [
  { amount: 60, unit: "second" },
  { amount: 60, unit: "minute" },
  { amount: 24, unit: "hour" },
  { amount: 7, unit: "day" },
  { amount: 4.34524, unit: "week" },
  { amount: 12, unit: "month" },
  { amount: Number.POSITIVE_INFINITY, unit: "year" },
];

/**
 * Postgres serializes a naive `timestamp` column (our `last_run_at` /
 * `last_synced_at`, written as UTC wall-clock via `now() at time zone 'utc'` and
 * `Date.toISOString()` sans the `Z`) as space-separated text with NO zone, e.g.
 * `2026-07-22 03:15:00.123`. `new Date("2026-07-22 03:15:00.123")` parses that as
 * the viewer's LOCAL time, skewing every relative label by the operator's UTC
 * offset. Coerce the naive `YYYY-MM-DD HH:MM:SS(.fff)` shape to ISO-8601 UTC
 * (`T`-separated, `Z`-suffixed) before parsing; a string already carrying a zone
 * or `T` separator falls through untouched.
 */
export function normalizeNaiveUtc(iso: string): string {
  return /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(\.\d+)?$/.test(iso)
    ? `${iso.replace(" ", "T")}Z`
    : iso;
}

/**
 * ISO timestamp → a short relative label ("3 minutes ago"), via native Intl.
 * An unparseable/empty input yields "never" so a source that has not run yet
 * reads sensibly instead of showing "Invalid Date".
 */
export function formatRelativeTime(iso: string | null | undefined): string {
  if (!iso) return "never";
  const ms = new Date(normalizeNaiveUtc(iso)).getTime();
  if (Number.isNaN(ms)) return "never";
  const rtf = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });
  let duration = (ms - Date.now()) / 1000;
  for (const division of RELATIVE_DIVISIONS) {
    if (Math.abs(duration) < division.amount) {
      return rtf.format(Math.round(duration), division.unit);
    }
    duration /= division.amount;
  }
  return "never";
}

/**
 * Coerce a loosely-typed sync-`detail` field to a display count, falling back to
 * 0 for null/undefined/NaN/±Infinity (the `detail` blob is `unknown`-typed, so a
 * bad value must not render "NaN upserted").
 */
export function finiteCount(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}
