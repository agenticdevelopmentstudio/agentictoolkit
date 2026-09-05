import { notInArray, sql } from "drizzle-orm";
import type { Db } from "../libsql/client";
import { platformHealthState, vercelProdState } from "../libsql/schema";
import { nextPlatformStreak, type IssueSource } from "./issue-sources";
import type { VercelProdState } from "./fetch-vercel-projects";

/**
 * Moved here from `issues.ts:562` — one definition, and it now lives with the code that
 * records it rather than with the code Task 12 deleted.
 *
 * `source` must stay `IssueSource`, not `string`: the fold indexes `SOURCE_LABEL[…]`
 * (`Record<IssueSource, string>`) off the value this observation persists, which is
 * TS7053 under this project's strict config the moment the type is widened.
 */
export interface PlatformObservation {
  source: IssueSource;
  /** An active integration with a token — i.e. a platform we actually poll. */
  configured: boolean;
  /** Did this poll reach the API? */
  reachable: boolean;
}

/** Prior consecutive-failure streak per source, or null when the debounce table
 *  hasn't been migrated onto this DB yet (→ caller falls back to no debounce). */
async function platformFailureCounts(db: Db): Promise<Map<string, number> | null> {
  try {
    const rows = await db.select().from(platformHealthState);
    return new Map(rows.map((r) => [r.source, r.consecutiveFailures]));
  } catch (err) {
    // Tolerate "table not migrated yet" (libSQL/SQLite phrasings vary); rethrow
    // real errors. Null signals "no persisted streak available" to the caller.
    if (/no such table|does not exist|not found/i.test(String(err))) return null;
    throw err;
  }
}

/**
 * Persist what this poll SAW of each platform: was it configured, did we reach it, and
 * how many consecutive polls it has now failed.
 *
 * The streak (`consecutiveFailures`) lives here because this is the ONLY writer. It used
 * to belong to `applyPlatformIssues`, which owned it by READ-THEN-WRITE
 * (`platformFailureCounts` → `nextPlatformStreak` → `setPlatformFailureCount`); while both
 * functions existed, a streak written here landed BEFORE that read, so one failed poll
 * advanced the counter twice and `PLATFORM_UNREACHABLE_POLLS = 2` was satisfied by a SINGLE
 * failure — the debounce deleted, and every transient 429 opening then resolving an issue.
 * That is regression `f21284e26` / `9fe25b304`. Task 12 deleted `applyPlatformIssues` in the
 * same commit that moved the streak here, so there is exactly one writer and the
 * double-advance cannot recur. `test/observations.test.ts` pins the count.
 *
 * Recording the observation separately from judging it is what lets `GET /board` judge
 * platform health on a request with no poll in flight: the fold reads `configured`,
 * `reachable` AND the streak from this table, and `platformProblems` applies the threshold.
 */
export async function recordPlatformObservations(db: Db, observations: PlatformObservation[]): Promise<void> {
  if (observations.length === 0) return;
  // ONE read of the prior streaks for the whole batch, before any write — the same
  // read-then-write applyPlatformIssues did, now with nothing else advancing the counter
  // between the read and the write.
  const counts = await platformFailureCounts(db);
  for (const o of observations) {
    const failing = o.configured && !o.reachable;
    // `nextPlatformStreak`'s `bad` half is deliberately ignored: the threshold decision
    // belongs to `platformProblems` now, and the recorder's job is the count. That is also
    // why the threshold argument is left at its default — `bad` is all it affects.
    const { streak } = nextPlatformStreak(counts?.get(o.source) ?? 0, failing);
    // `counts === null` means the debounce table is not migrated onto this DB; leave the
    // column out entirely rather than writing a streak the schema cannot hold.
    const row = {
      configured: o.configured,
      reachable: o.reachable,
      ...(counts === null ? {} : { consecutiveFailures: streak }),
      updatedAt: new Date(),
    };
    await db
      .insert(platformHealthState)
      .values({ source: o.source, ...row })
      .onConflictDoUpdate({ target: platformHealthState.source, set: row });
  }
}

/**
 * Replace the production-staleness mirror with what this read saw.
 *
 * An EMPTY list deletes nothing. A failed or rate-limited Vercel read returns no states,
 * and treating that as "every project recovered" would mass-resolve the whole fleet's
 * stale problems on one transient 429 — the same fail-closed rule `dropVanishedVercelProjects`
 * and the `if (prod.ok)` gate at `sync.ts:520` already apply. The caller must only pass a
 * COMPLETE read; a partial one must not reach here.
 */
export async function recordVercelProdStates(db: Db, states: VercelProdState[]): Promise<void> {
  if (states.length === 0) return;
  for (const s of states) {
    const row = {
      projectName: s.projectName, stale: s.stale, detail: s.detail,
      sourceUrl: s.sourceUrl, liveUrl: s.liveUrl, updatedAt: new Date(),
    };
    await db
      .insert(vercelProdState)
      .values(row)
      .onConflictDoUpdate({
        target: vercelProdState.projectName,
        // A read that resolved null did not resolve the link — it did not learn the link is
        // gone. Both are best-effort decoration on a budget (`fetchTeamSlug` returns null
        // when the poll ran out of time; `liveUrl` lands only once an endpoint matches), so
        // writing the null through blanks the operator's only route to the failing build's
        // log on exactly the problem telling them to go look at it. Keep what we last knew.
        // `excluded` is the proposed row; the bare column is the stored one.
        //
        // `detail` and `stale` are deliberately NOT coalesced: those are the read's actual
        // verdict, and a null detail on a non-stale project is the truth. And the coalesce
        // lives HERE, in the mirror the board reads — never also in the ledger writer, which
        // only records what the fold already decided.
        set: {
          ...row,
          sourceUrl: sql`coalesce(excluded.source_url, ${vercelProdState.sourceUrl})`,
          liveUrl: sql`coalesce(excluded.live_url, ${vercelProdState.liveUrl})`,
        },
      });
  }
  // A project that left the account entirely must not linger as permanently stale.
  await db.delete(vercelProdState).where(notInArray(vercelProdState.projectName, states.map((s) => s.projectName)));
}
