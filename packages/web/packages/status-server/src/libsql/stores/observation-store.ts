import { notInArray, sql } from "drizzle-orm";
import type { Db } from "../client";
import { platformHealthState, vercelProdState } from "../schema";
import { nextPlatformStreak } from "../../monitor/issue-sources";
import type { ObservationStore, PlatformObservationInput, VercelProdStateInput } from "../../storage/ports";

// ---------------------------------------------------------------------------
// The libSQL implementation of `ObservationStore`. Bodies moved verbatim from
// `monitor/observations.ts` — see that file's doc comments for the read-then-write
// streak rationale and the fail-closed staleness rule.
// ---------------------------------------------------------------------------

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

/** Build the `ObservationStore` port over one connection. */
export function createObservationStore(db: Db): ObservationStore {
  return {
    /**
     * Persist what this poll SAW of each platform: was it configured, did we reach it, and
     * how many consecutive polls it has now failed. The streak lives here because this is
     * the ONLY writer — see `monitor/observations.ts` for the double-advance regression
     * this single-writer rule fixed.
     */
    async recordObservations(observations: PlatformObservationInput[]): Promise<void> {
      if (observations.length === 0) return;
      // ONE read of the prior streaks for the whole batch, before any write.
      const counts = await platformFailureCounts(db);
      for (const o of observations) {
        const failing = o.configured && !o.reachable;
        // `nextPlatformStreak`'s `bad` half is deliberately ignored: the threshold decision
        // belongs to `platformProblems`, and the recorder's job is the count.
        const { streak } = nextPlatformStreak(counts?.get(o.source) ?? 0, failing);
        // `counts === null` means the debounce table is not migrated onto this DB; leave
        // the column out entirely rather than writing a streak the schema cannot hold.
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
    },

    /**
     * Replace the production-staleness mirror with what this read saw. An EMPTY list
     * deletes nothing — the caller must only pass a COMPLETE read; a partial one must
     * not reach here (see `monitor/observations.ts`).
     */
    async recordVercelProdStates(states: VercelProdStateInput[]): Promise<void> {
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
            // A read that resolved null did not resolve the link — it did not learn the
            // link is gone. `detail` and `stale` are deliberately NOT coalesced: those are
            // the read's actual verdict.
            set: {
              ...row,
              sourceUrl: sql`coalesce(excluded.source_url, ${vercelProdState.sourceUrl})`,
              liveUrl: sql`coalesce(excluded.live_url, ${vercelProdState.liveUrl})`,
            },
          });
      }
      // A project that left the account entirely must not linger as permanently stale.
      await db.delete(vercelProdState).where(notInArray(vercelProdState.projectName, states.map((s) => s.projectName)));
    },
  };
}
