"use client";
import { useEffect, useState } from "react";
import type { ActivityRow } from "../lib/board-types";

export interface BuildProgress {
  /** Show the bar — there is an active build cohort (possibly in its 2s hold). */
  visible: boolean;
  /** Builds finished in the current cohort. */
  completed: number;
  /** Builds in the current cohort. */
  total: number;
  /** Percentage complete, 0–100. */
  pct: number;
  /** Every cohort build is done — the bar holds full for 2s, then hides. */
  complete: boolean;
}

const COMPLETE_HOLD_MS = 2000;

/**
 * Progress over the current build "cohort" — the set of builds that have been
 * in-flight since the last all-idle moment. A build joins the cohort while the
 * board reports it in flight (a deploy/build row toned "progress"); it counts as
 * completed once the board stops saying so — the row settles (built / deployed /
 * failed / canceled), the server expires it to "stale", or it drops out of the
 * feed entirely. Every one of those is the SERVER's call; this hook has no clock
 * of its own and never demotes a row the board is still asserting. When every
 * cohort build is done the bar holds at 100% for two seconds, then the cohort
 * resets and the bar hides until the next build begins.
 *
 * Takes whatever `ActivityRow[]` the caller passes — OverviewTab passes its
 * env-filtered activity, so a filtered-out env's build doesn't count (see
 * `envActivity` there); ttl/clear/search narrow only what's DISPLAYED, not
 * what's tracked here.
 */
export function useBuildProgress(activity: ActivityRow[]): BuildProgress {
  const [cohort, setCohort] = useState<ReadonlySet<string>>(() => new Set());

  // A build is in-flight exactly while the SERVER says it is: `tone === "progress"`
  // on a deploy/build row. The client does not get a vote.
  //
  // This used to AND in a second term — `nowMs - Date.parse(a.at) < UNCONFIRMED_AFTER_MS`
  // — a private 10-minute clock that re-judged a verdict the server had already made,
  // while the rendered ROW went on saying "building". The two surfaces therefore
  // disagreed: past ten minutes the progress bar dropped the build and read 100%/hidden
  // while the row two inches below it still said "building" — one fact, two derivations,
  // and the quieter of them won on the more prominent surface. (`row-model.ts` has since
  // deleted its own client-side demotion outright, for the same reason.)
  //
  // The server owns the demotion, and does it in the open: `reconcile-stuck-deploys`
  // expires an unconfirmed in-flight phase (tone → "stale", which is not "progress", so
  // the row leaves this cohort at that instant), and `deployIsStuck` raises a Problem.
  // Consequence, accepted deliberately: while a build really is wedged AND the server's
  // own expiry hasn't fired yet, the bar stays visible below 100% instead of quietly
  // completing. That is the honest render — the build has not finished — and it now
  // ends the moment the row beside it stops saying "building", which is the only
  // behaviour a viewer can reconcile.
  const isInFlightBuild = (a: ActivityRow): boolean =>
    a.kind === "deploy" && a.step === "build" && a.tone === "progress";
  const inFlight = new Set(activity.filter(isInFlightBuild).map((a) => a.id));
  const inFlightKey = [...inFlight].sort().join("|");

  // Accumulate every build seen in-flight into the current cohort. This is an
  // external-observation sync (snapshots arrive over time), not derived state —
  // mirrors useEnvFilter's localStorage hydration pattern.
  useEffect(() => {
    if (inFlight.size === 0) return;
    // External-observation sync (not derived state): accumulate in-flight builds
    // across snapshots, like useEnvFilter's storage hydration.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setCohort((prev) => {
      let changed = false;
      const next = new Set(prev);
      for (const k of inFlight) {
        if (!next.has(k)) {
          next.add(k);
          changed = true;
        }
      }
      return changed ? next : prev;
    });
  }, [inFlightKey]); // eslint-disable-line react-hooks/exhaustive-deps

  const ids = [...cohort];
  const total = ids.length;
  // Completed = cohort builds no longer in-flight (terminal, stuck, or gone).
  const completed = ids.filter((k) => !inFlight.has(k)).length;
  const allDone = total > 0 && completed === total;

  // Hold full for 2s after the last build finishes, then clear the cohort. A new
  // in-flight build before the timer fires flips allDone false and cancels it
  // (the cleanup clears the pending timer).
  useEffect(() => {
    if (!allDone) return;
    const t = setTimeout(() => setCohort(new Set()), COMPLETE_HOLD_MS);
    return () => clearTimeout(t);
  }, [allDone]);

  return {
    visible: total > 0,
    completed,
    total,
    pct: total === 0 ? 0 : Math.round((completed / total) * 100),
    complete: allDone,
  };
}
