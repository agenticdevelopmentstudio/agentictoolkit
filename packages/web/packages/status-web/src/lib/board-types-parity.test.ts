import { describe, it, expect } from "vitest";
// The SERVER's board types, imported by relative path (there is no shared build between the
// backend and its embedded web app — see deploy-status-parity.test.ts for the precedent).
import type * as server from "@agentic-toolkit/status-server/board";
import type * as web from "./board-types";
// RUNTIME import from the pure ./activity subpath (derive-activity.ts and what it
// reaches import no drizzle/libsql), so this browser-side package's tests never
// load the ORM — ./board also re-exports the drizzle-backed facts reader.
import { indicatorFor } from "@agentic-toolkit/status-server/activity";
import { INDICATOR_STATE, indicatorFromProblems } from "./overview";
import type { Problem } from "./board-types";

// DRIFT GUARD. web/src/lib/board-types.ts is a HAND MIRROR of src/board/types.ts (there is no
// shared package between the backend and its embedded web app). If the two drift — a renamed
// field, a widened nullability, a union member added on one side only — the board silently
// mis-renders with no compile error to catch it, because `pnpm test` transpiles without
// typechecking. So the type half below is what makes the drift visible: it is real code that
// only compiles when both sides still agree, checked by `pnpm typecheck` (Step 11).

/** Mutual assignability. Drift a field name, a nullability, or a union member on either
 *  side and this stops resolving to `true`. */
type Exact<A, B> = [A] extends [B] ? ([B] extends [A] ? true : never) : never;

const _board: Exact<server.Board, web.Board> = true;
const _problem: Exact<server.Problem, web.Problem> = true;
const _activityRow: Exact<server.ActivityRow, web.ActivityRow> = true;
const _activityTone: Exact<server.ActivityTone, web.ActivityTone> = true;
const _activityKind: Exact<server.ActivityKind, web.ActivityKind> = true;
const _indicator: Exact<server.Indicator, web.Indicator> = true;
// The pagination protocol itself: `useActivityHistory` reads `/api/activity`'s response as
// `web.ActivityPage` and mints its query string from `web.ActivityCursor`, so a field the
// server renamed on one side only would page silently wrong rather than fail to compile.
const _activityCursor: Exact<server.ActivityCursor, web.ActivityCursor> = true;
const _activityPage: Exact<server.ActivityPage, web.ActivityPage> = true;
void [
  _board, _problem, _activityRow, _activityTone, _activityKind, _indicator,
  _activityCursor, _activityPage,
];

/** A minimal, override-able Problem fixture — only `severity` varies across the cases below. */
function problem(severity: Problem["severity"], overrides: Partial<Problem> = {}): Problem {
  return {
    target: "vercel|example",
    source: "vercel",
    name: "example",
    environment: null,
    severity,
    state: "failed",
    statusCode: null,
    detail: null,
    sourceUrl: null,
    liveUrl: null,
    commitHash: null,
    commitMessage: null,
    commitRepo: null,
    branch: null,
    errorText: null,
    since: "2026-06-30T00:00:00.000Z",
    ...overrides,
  };
}

describe("board-types parity (web mirrors server)", () => {
  it("INDICATOR_STATE covers every member of the server's Indicator union, with no extras", () => {
    // A Record<BoardIndicator, …> is exhaustive by construction at compile time — but only
    // this key check catches a member removed from both the union and the map together.
    expect(Object.keys(INDICATOR_STATE).sort()).toEqual(["degraded", "operational", "outage"]);
  });

  // The client's indicatorFromProblems is a rendering projection of the server's indicatorFor
  // (src/board/derive-activity.ts:220) — these cases pin the two together on the unfiltered
  // set, so the client rule can't drift from the server's the way it did before this task.
  it("agrees with the server's indicatorFor on an empty problem set", () => {
    const problems: Problem[] = [];
    expect(indicatorFromProblems(problems)).toEqual({
      state: INDICATOR_STATE[indicatorFor(problems)],
      count: problems.length,
    });
  });

  it("agrees with the server's indicatorFor on a minor-only problem set", () => {
    const problems: Problem[] = [problem("minor"), problem("minor")];
    expect(indicatorFromProblems(problems)).toEqual({
      state: INDICATOR_STATE[indicatorFor(problems)],
      count: problems.length,
    });
  });

  it("agrees with the server's indicatorFor on a major-only problem set", () => {
    const problems: Problem[] = [problem("major"), problem("minor")];
    expect(indicatorFromProblems(problems)).toEqual({
      state: INDICATOR_STATE[indicatorFor(problems)],
      count: problems.length,
    });
  });

  it("agrees with the server's indicatorFor on a critical-bearing problem set", () => {
    const problems: Problem[] = [problem("minor"), problem("major"), problem("critical")];
    expect(indicatorFromProblems(problems)).toEqual({
      state: INDICATOR_STATE[indicatorFor(problems)],
      count: problems.length,
    });
  });
});
