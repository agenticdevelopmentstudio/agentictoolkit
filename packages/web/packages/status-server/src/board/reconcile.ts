import type { Db } from "../libsql/client";
import { flushAlerts } from "../monitor/alerts";
import { applyBoardToLedger } from "../monitor/issues";
import type { StatusConfig } from "../config/port";
import { deriveBoard } from "./derive";
import { readBoardFacts } from "./facts";
import type { Board } from "./types";

/**
 * Read the facts, fold them, record the verdict. Every caller that wants the ledger to
 * agree with reality calls THIS — the monitor cycle, `POST /board/reconcile`, and each
 * config mutation that can strand an issue (site deleted, group deleted, endpoint
 * retired). One verb, so there is exactly one answer to "is this problem still real".
 *
 * This is what replaces `reconcileOrphanedIssues`. That function answered a NARROWER
 * question — "does some live endpoint still claim this target" — with its own second
 * spelling of a target key, and its six call sites each passed it a slightly different
 * slice of config. The board already knows which targets are monitored, so the sweep is
 * a consequence of the fold rather than a rule kept in step with it by hand.
 *
 * Safe to call on every mutation: it is idempotent and derives from the DB, so calling
 * it twice resolves nothing the second time.
 *
 * `skipOnEmptyRoster` decides what an empty roster MEANS, and only the caller knows.
 * `sync.ts` and `POST /board/reconcile` merely OBSERVE the world, so for them an empty
 * roster is a read that may have blipped, and sweeping on it retires every open row at
 * once. The five config mutations CAUSED the emptiness — deleting the last site really
 * should retire its issues — so they must sweep, and they leave the flag off. This is
 * the distinction `sync.ts` used to draw in prose above a guard; it moves here because
 * the flag is where it is now enforced. The flag is off by default so the sweeping case
 * stays the one you get without thinking about it.
 *
 * FLUSHES ITS OWN ALERTS, because "the cycle will flush" is false for most of its callers.
 * `openIssue`/`resolveIssue` queue into a module-global array (`alerts.ts:30`), and module
 * state is PER THREAD: the monitor's flush (`cycle-runner.ts:22`) runs inside a real
 * `Worker` (`worker-client.ts:70` — which ships cooldown state through a SharedArrayBuffer
 * precisely because nothing else crosses that boundary). Six of this function's call sites
 * are on the API thread — `POST /board/reconcile`, three config mutations and two MCP
 * tools — so an alert they queue would sit in the API thread's queue forever, and the next
 * worker cycle would never re-queue it: the row is already open, so `openIssue` does not
 * run again. Delete a site while its deploy is failing and on-call is never paged at all.
 *
 * Flushing here also delivers each cycle's alerts at reconcile time rather than batching
 * both of a full sync's reconciles into `cycle-runner`'s one POST; that `finally` flush
 * stays as the throw-path backstop, and `hooks.ts:57` stays because it still fires when
 * this function throws inside the hook's fail-soft catch. The skip path returns before
 * `applyBoardToLedger`, so nothing is queued and nothing needs flushing.
 */
export async function reconcileBoardLedger(
  db: Db,
  config: StatusConfig,
  opts: { nowMs?: number; skipOnEmptyRoster?: boolean } = {},
): Promise<{ board: Board; opened: number; updated: number; resolved: number; resolvedTargets: string[]; skipped: boolean }> {
  const nowMs = opts.nowMs ?? Date.now();
  const facts = await readBoardFacts(db, nowMs, config);
  const board = deriveBoard(facts, nowMs);
  if (opts.skipOnEmptyRoster && facts.roster.length === 0) {
    return { board, opened: 0, updated: 0, resolved: 0, resolvedTargets: [], skipped: true };
  }
  const counts = await applyBoardToLedger(db, board);
  await flushAlerts(config.alertWebhookUrl);
  return { board, ...counts, skipped: false };
}
