import { deriveActivity, indicatorFor } from "./derive-activity";
import {
  deployProblems,
  endpointProblems,
  errorProblems,
  monitoredTargets,
  platformProblems,
  staleProdProblems,
} from "./derive-problems";
import { rosterTargets } from "./ownership";
import { ACTIVITY_WINDOW_MS } from "./types";
import type { Board, BoardFacts, Problem } from "./types";

/** Oldest first — the pane renders this array top-to-bottom, and the newest row belongs at
 *  the BOTTOM, where a reader parked at the tail sees it arrive. Ties broken on target so
 *  the order is total and stable. */
function byRecency(a: Problem, b: Problem): number {
  if (a.since !== b.since) return a.since < b.since ? -1 : 1;
  return a.target < b.target ? -1 : a.target > b.target ? 1 : 0;
}

/**
 * THE DATA CLOCK: the newest observation that PROVES A MONITOR CYCLE RAN, or null when the
 * board rests on no such observation at all.
 *
 * `generatedAt` is the DERIVATION clock, and the two come apart in exactly the case that
 * matters. If the monitor process stops cycling, the facts freeze at last-known-healthy,
 * `problems` goes empty, and `indicatorFor` says "operational" over a freshly-stamped
 * `generatedAt` — forever. `isBoardStale(generatedAt)` cannot see it, because
 * `generatedAt` really is fresh. `/health` and `/public/status-summary` each honour "no
 * data is not a health claim" with their own guard; the board is now the client's only
 * read and had none. This is that guard (constraint 2).
 *
 * ONLY A FACT THE MONITOR ITSELF WRITES, ON ITS OWN CADENCE, MAY MOVE THIS CLOCK. Exactly
 * two families qualify, and the question each answers is "did a cycle run", never "did
 * something happen":
 *   - health checks (`checkedAtMs`) — the probe's own clock, stamped by the cycle that ran
 *     the probe, ticking every cycle,
 *   - platform samples (`sampledAtMs`) — `recordPlatformObservations` rewrites the row
 *     every cycle whether or not the verdict changed, which is what keeps the clock honest
 *     on a fleet with no HTTP endpoints.
 *
 * THE DEPLOY FAMILIES ARE DELIBERATELY ABSENT, and adding them back re-opens the exact
 * hole this field exists to close. `deployments.createdAt` is the PROVIDER'S clock, not
 * ours, and the row need not have come from a cycle at all: `routes/hooks.ts` writes
 * Vercel/Railway webhook rows on the API thread and reconciles the ledger itself. So with
 * the monitor wedged at T0 and Hono still serving, one webhook is enough to stamp the
 * clock `now` while every probe and platform sample has been frozen for hours — `problems`
 * frozen at last-known-healthy, the client's freshness guard never firing, the board
 * serving `operational` over dead data. A deploy row is evidence that a provider did
 * something; it is not evidence that we are still looking.
 *
 * The ledger (`ledger`, `issueEvents`) is out for a neighbouring reason: those rows are the
 * board's OWN output written back by `applyBoardToLedger`, so counting them would let the
 * board's writes refresh the clock that is supposed to be watching them. `staleProd`
 * carries no timestamp at all — `vercel_prod_state` has no observation column — so it
 * cannot contribute either. Every exclusion errs the same way: the clock can read older
 * than reality, never fresher, and only "fresher" is a health claim.
 */
function dataAsOf(facts: BoardFacts): number | null {
  const observed = [
    ...facts.endpoints.map((e) => e.checkedAtMs),
    ...facts.platforms.map((p) => p.sampledAtMs),
  ];
  return observed.length === 0 ? null : Math.max(...observed);
}

/**
 * THE fold. Every input the status site has — provider polls, webhooks, HTTP probes,
 * the roster, the ledger — reduces to one Board here, and nothing else in the system is
 * allowed to decide what a Problem is.
 *
 * Pure by construction: `nowMs` is a parameter, there is no IO, and calling it twice
 * with the same facts gives a deep-equal result. That is what makes the scenarios we
 * kept regressing on cheap to pin as unit tests.
 */
export function deriveBoard(facts: BoardFacts, nowMs: number): Board {
  // Built ONCE and threaded through, rather than left for each rule to rebuild off
  // `facts.roster`. Five call sites each re-indexed the roster and one of them
  // (`deriveActivity`) re-ran `monitoredTargets`, which re-indexed it a sixth time — the
  // whole roster walked six times per fold, and once more per SSE frame. The rules keep
  // their optional parameter so a unit test can still call any of them directly with just
  // facts; this is the one place that has more than one of them to feed.
  const index = rosterTargets(facts.roster, facts.liveVercelProjects);
  const monitored = monitoredTargets(facts, index);

  const deploy = deployProblems(facts, nowMs, index);
  const suppress = new Set(deploy.map((p) => p.target));
  const problems = [
    ...deploy,
    ...endpointProblems(facts, nowMs),
    // NOT passed `suppress`, unlike `staleProdProblems`. Suppression exists so two rules
    // don't both speak about the same target; error targets are namespaced `errors|<project>`
    // and can't collide with a deploy or endpoint target, so there is nothing to suppress.
    // An erroring app during a failed deploy is two facts, and the operator wants both.
    ...errorProblems(facts, nowMs),
    ...platformProblems(facts, nowMs),
    ...staleProdProblems(facts, nowMs, suppress, index),
  ].sort(byRecency);

  return {
    generatedAt: new Date(nowMs).toISOString(),
    dataAsOfMs: dataAsOf(facts),
    probeIntervalMs: facts.probeIntervalMs,
    // The SAME boundary `deriveActivity` cuts the feed at, published rather than left for
    // the client to reconstruct from a constant it would have to keep in step by hand.
    activityFromMs: nowMs - ACTIVITY_WINDOW_MS,
    problems,
    activity: deriveActivity(facts, nowMs, index, new Set(monitored)),
    indicator: indicatorFor(problems),
    monitoredTargets: monitored,
  };
}
