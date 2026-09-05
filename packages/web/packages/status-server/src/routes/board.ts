import { Hono } from 'hono';
import type { Db } from '../libsql/client';
import type { StatusConfig } from '../config/port';
import { requireAdmin } from '../middleware/auth';
import { deriveBoard, readBoardFacts, reconcileBoardLedger } from '../board';

export function boardRoutes(db: Db, config: StatusConfig) {
  const app = new Hono();

  /**
   * The whole board in one read. This is the client's ONLY source for Problems,
   * Activity and the indicator — the View in a distributed MVC.
   */
  app.get('/board', async (c) => {
    const nowMs = Date.now();
    return c.json(deriveBoard(await readBoardFacts(db, nowMs, config), nowMs));
  });

  /**
   * REQUIREMENT B: make the LEDGER agree with the board. This runs the monitor cycle's own
   * verb (`reconcileBoardLedger`), so it is the FULL write, not a sweep: it OPENS a row for
   * every problem the fold derives that has none, UPDATES the rows of problems still live,
   * and RESOLVES the ones the fold no longer derives — the site was deleted, the project
   * was renamed, or its monitoring was switched off. The board itself is already correct
   * without this (it is derived, not stored); this keeps alert dedup, onset times and
   * resolved history honest.
   *
   * IT CAN ALERT. `openIssue` pages unconditionally and a `recovered` close pages too, and
   * this endpoint flushes the queue on the API thread — so an admin calling it can page
   * on-call. That is correct (an unpaged live outage is the bug it fixes) but it is not
   * what "reconcile" sounds like, so: the response reports `opened`/`updated` alongside
   * `resolved`, and a caller putting this on a tight loop should know a NEW problem
   * discovered here is announced here.
   *
   * Idempotent: a second run against unchanged state opens nothing, resolves nothing, and
   * re-queues no alert (the row already exists), so it is safe to run on a loop, from the
   * CLI, or twice by accident. `updated` is the exception and is expected to be non-zero
   * on every run — refreshing a live row's links and commit is the steady state.
   *
   * ADMIN-ONLY, applied per-route rather than as a blanket `use("*")`: this sub-app mounts
   * at the ROOT prefix beside `readsRoutes`, so a root-mounted guard would leak onto every
   * sibling registered after it. `auto-configure.ts:242` guards its one write exactly this
   * way and says so. `GET /board` stays view-tier — it is the client's only read.
   */
  app.post('/board/reconcile', requireAdmin, async (c) => {
    // `skipOnEmptyRoster` because this route only OBSERVES: it cannot tell "every site was
    // deleted" from "the read blipped", and its own docstring invites running it on a loop.
    // The five config mutations pass no flag — they caused the emptiness, so they sweep.
    const { board, opened, updated, resolved, resolvedTargets, skipped } = await reconcileBoardLedger(db, config, {
      skipOnEmptyRoster: true,
    });
    return c.json({ opened, updated, resolved, targets: resolvedTargets, checkedAt: board.generatedAt, skipped });
  });

  return app;
}
