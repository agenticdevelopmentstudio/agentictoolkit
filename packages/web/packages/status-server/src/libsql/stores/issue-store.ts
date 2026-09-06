import { and, eq, inArray, isNull } from "drizzle-orm";
import type { Db } from "../client";
import { issues } from "../schema";
import type { IssueInsert, IssuePatch, IssueRow, IssueStore } from "../../storage/ports";

// ---------------------------------------------------------------------------
// The libSQL implementation of `IssueStore` — the ledger's raw reads/writes.
// Bodies moved verbatim from `monitor/issues.ts`; the grouping-by-target, the
// canonical-vs-shadow rule and the alert notifications all stay there as
// business logic layered on top of these plain CRUD primitives.
// ---------------------------------------------------------------------------

/** Build the `IssueStore` port over one connection. */
export function createIssueStore(db: Db): IssueStore {
  return {
    /**
     * Every currently-open issue, OLDEST FIRST — so `[0]` per target is the CANONICAL
     * row (the one carrying the true onset) and anything after it is a shadow.
     *
     * The DB partial unique index (`uniq_open_issue_per_target`) is supposed to keep each
     * target to one row; this returns every row anyway because DROPPING the extras is what
     * let them rot — a shadow the writer never saw was never updated and never resolved.
     */
    async listOpen(): Promise<IssueRow[]> {
      return db
        .select()
        .from(issues)
        .where(isNull(issues.resolvedAt))
        // `id` breaks the tie so two rows opened in the same millisecond still pick the
        // same canonical row on every read — an arbitrary canonical row is an arbitrary onset.
        .orderBy(issues.openedAt, issues.id);
    },

    /** Insert an open issue unless one already exists for the target — the partial unique
     *  index guards the race. Never alerts; the caller decides that. */
    async insertIssue(input: IssueInsert): Promise<void> {
      await db.insert(issues).values(input).onConflictDoNothing();
    },

    /** Refresh an open issue's derived fields in place — the links AND the commit, so an
     *  open issue tracks the latest deploy rather than staying frozen at whatever it was
     *  first opened with. */
    async updateIssue(id: number, patch: IssuePatch): Promise<void> {
      await db
        .update(issues)
        .set({
          source: patch.source,
          name: patch.name,
          environment: patch.environment,
          severity: patch.severity,
          state: patch.state,
          statusCode: patch.statusCode,
          detail: patch.detail,
          sourceUrl: patch.sourceUrl,
          liveUrl: patch.liveUrl,
          commitHash: patch.commitHash ?? null,
          commitMessage: patch.commitMessage ?? null,
          commitRepo: patch.commitRepo ?? null,
          updatedAt: new Date(),
        })
        .where(eq(issues.id, id));
    },

    /** Close an issue with the given reason. Never alerts; the caller decides that. */
    async resolveIssue(id: number, reason: "recovered" | "unmonitored" | "duplicate"): Promise<void> {
      await db
        .update(issues)
        .set({ resolvedAt: new Date(), resolvedReason: reason, updatedAt: new Date() })
        .where(eq(issues.id, id));
    },

    /** Resolve every currently-open issue for the given targets as "unmonitored" —
     *  for endpoints that were just deleted. Targeted by id list, never a mass-resolve. */
    async resolveUnmonitoredTargets(targets: string[]): Promise<void> {
      if (targets.length === 0) return;
      await db
        .update(issues)
        .set({ resolvedAt: new Date(), resolvedReason: "unmonitored", updatedAt: new Date() })
        .where(and(isNull(issues.resolvedAt), inArray(issues.target, targets)));
    },
  };
}
