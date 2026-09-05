// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from "vitest";
import { renderHook, act, cleanup } from "@testing-library/react";
import { useBuildProgress } from "./use-build-progress";
import type { ActivityRow } from "../lib/board-types";

// Fix Round 4 item 5.7. The cohort predicate used to AND in a private 10-minute clock
// (`nowMs - Date.parse(a.at) < UNCONFIRMED_AFTER_MS`) that re-judged a verdict the
// server had already made — while the RENDERED row went on saying "building". So past
// ten minutes the bar dropped a build and read complete while the row beside it still
// said "building". The rule is now: in-flight ⇔ the board says `tone === "progress"` on
// a deploy/build row — the same single source `row-model.ts` renders, its own
// client-side freshness clock having since been deleted for the identical reason.

const T0 = Date.parse("2026-06-04T19:30:00.000Z");

function buildRow(name: string, tone: ActivityRow["tone"], atMs: number): ActivityRow {
  return {
    id: `deploy:vc_${name}:build`,
    kind: "deploy",
    step: "build",
    source: "vercel",
    target: `vercel|${name}|production`,
    name,
    environment: "production",
    verb: tone === "progress" ? "building" : "built",
    tone,
    detail: null,
    sourceUrl: null,
    liveUrl: null,
    commitHash: null,
    commitMessage: null,
    commitRepo: null,
    branch: null,
    errorText: null,
    at: new Date(atMs).toISOString(),
  };
}

afterEach(() => {
  cleanup();
  vi.useRealTimers();
});

describe("useBuildProgress", () => {
  it("counts a build as in-flight while the board tones it progress", () => {
    const { result } = renderHook(({ a }: { a: ActivityRow[] }) => useBuildProgress(a), {
      initialProps: { a: [buildRow("app", "progress", T0)] },
    });
    expect(result.current.visible).toBe(true);
    expect(result.current.total).toBe(1);
    expect(result.current.completed).toBe(0);
    expect(result.current.pct).toBe(0);
  });

  it("completes a build when the board settles its row", () => {
    const { result, rerender } = renderHook(({ a }: { a: ActivityRow[] }) => useBuildProgress(a), {
      initialProps: { a: [buildRow("app", "progress", T0)] },
    });
    rerender({ a: [buildRow("app", "good", T0)] });
    expect(result.current.total).toBe(1);
    expect(result.current.completed).toBe(1);
    expect(result.current.pct).toBe(100);
    expect(result.current.complete).toBe(true);
  });

  it("completes a build when the SERVER expires it to `stale` — the server's demotion, not a client clock", () => {
    const { result, rerender } = renderHook(({ a }: { a: ActivityRow[] }) => useBuildProgress(a), {
      initialProps: { a: [buildRow("app", "progress", T0)] },
    });
    // reconcile-stuck-deploys expires an unconfirmed in-flight phase; the tone stops
    // being "progress", so the row leaves the cohort at exactly that instant.
    rerender({ a: [buildRow("app", "stale", T0)] });
    expect(result.current.completed).toBe(1);
    expect(result.current.complete).toBe(true);
  });

  it("keeps an OLD in-flight build in the cohort — the client no longer runs a 10-minute demotion clock", () => {
    // The row's `at` is a full hour in the past and the board is STILL toning it
    // progress. Under the removed clock this read 1/1, 100%, complete — a green bar
    // over a row that still said "building". It must read 0/1 now.
    const anHourOld = T0 - 60 * 60_000;
    const { result } = renderHook(() => useBuildProgress([buildRow("wedged", "progress", anHourOld)]));
    expect(result.current.visible).toBe(true);
    expect(result.current.total).toBe(1);
    expect(result.current.completed).toBe(0);
    expect(result.current.pct).toBe(0);
    expect(result.current.complete).toBe(false);
  });

  it("tracks a mixed cohort and hides two seconds after the last build settles", () => {
    vi.useFakeTimers();
    const { result, rerender } = renderHook(({ a }: { a: ActivityRow[] }) => useBuildProgress(a), {
      initialProps: { a: [buildRow("one", "progress", T0), buildRow("two", "progress", T0 + 1)] },
    });
    expect(result.current.total).toBe(2);

    rerender({ a: [buildRow("one", "good", T0), buildRow("two", "progress", T0 + 1)] });
    expect(result.current.pct).toBe(50);
    expect(result.current.visible).toBe(true);

    rerender({ a: [buildRow("one", "good", T0), buildRow("two", "good", T0 + 1)] });
    expect(result.current.pct).toBe(100);
    expect(result.current.visible).toBe(true); // holds full…

    act(() => void vi.advanceTimersByTime(2100));
    expect(result.current.visible).toBe(false); // …then the cohort resets and it hides
  });

  it("ignores rows that are not deploy BUILD steps", () => {
    // The DEPLOY step of a deployment has its own progress semantics and is not part of
    // the build cohort; a probe row isn't a deployment at all. The probe row wears the
    // shape `deriveActivity` actually emits for one — an ISSUE event, `kind: "probe"` with
    // a null step and an `issue:<target>:<step>:<atMs>:<issueId>` id — because a fixture
    // that invents a third id grammar would keep passing a cohort predicate that had
    // started keying off the id.
    const deployStep: ActivityRow = { ...buildRow("app", "progress", T0), id: "deploy:vc_app:deploy", step: "deploy" };
    const probe: ActivityRow = { ...buildRow("app", "progress", T0), id: `issue:ep-app:opened:${T0}:41`, kind: "probe", step: null };
    const { result } = renderHook(() => useBuildProgress([deployStep, probe]));
    expect(result.current.visible).toBe(false);
    expect(result.current.total).toBe(0);
  });
});
