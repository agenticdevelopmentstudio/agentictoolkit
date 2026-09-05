import { and, desc, eq, notInArray, sql } from "drizzle-orm";
import type { Db } from "../../libsql/client";
import { errors } from "../../libsql/schema";
import type { Store } from "../ports";
import type { ErrorDTO } from "../types";

// SQLite/libSQL adapter of Store<ErrorDTO> over the `errors` table. The ONLY
// place that knows the errors data lives in a database — it adapts DTOs (ISO
// strings) to/from the DB row types (timestamps). Upserts by issueKey so a
// re-poll updates the summary in place. Takes the db handle explicitly (this
// backend has no db singleton), so the same store serves any DB (memory/file).
//
// `save` is a RECONCILIATION, not an append. The fetcher asks GlitchTip for
// `is:unresolved`, so each poll delivers the COMPLETE current set — an issue that
// is absent has been resolved (or deleted) upstream, and the only way to learn that
// is its absence. Until the sweep below existed nothing in the codebase ever wrote
// `resolved = true`: one insert, one select, no update, no delete. Every error ever
// fetched stayed unresolved forever, `load()` returned a list that only grew, and a
// Problem derived from it could go red and never go green. That was invisible for as
// long as it was, because `/telemetry` polls the provider live and bypasses this
// table entirely — only `/errors` and the board read what is stored here.
//
// THE SWEEP IS SAFE ONLY UNDER TWO PRECONDITIONS, and both are somebody else's to
// keep — which is why they are written down here rather than assumed.
//
//   1. THE POLL SUCCEEDED. `collect` persists nothing unless the fetcher returned `ok`
//      (`collect.ts`), and `collectTelemetry` skips the collection entirely when
//      GlitchTip is unconfigured (`server.ts`). So an empty `items` means "GlitchTip is
//      configured, answered, and has nothing unresolved" — which must clear the table —
//      and never "we could not ask". The fetcher earns that by reporting a malformed
//      200 as `ok: false` rather than as an empty success.
//   2. THE ANSWER IS WHOLE. The issues endpoint is paginated and the fetcher asks for one
//      page, so `opts.complete` says whether that page WAS the set. Sweeping a page
//      resolves everything past its edge and reopens it on the next poll — a project
//      whose issues straddle the boundary would flap `errors|<project>` open/closed every
//      cycle, paging a recovery and then an outage, forever. A partial answer therefore
//      upserts what it saw and sweeps nothing.
//
// Widen either precondition and this becomes a mass-resolve on a provider outage.

function toDate(s: string | null): Date | null {
  if (!s) return null;
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? null : d;
}

function rowToDTO(r: typeof errors.$inferSelect): ErrorDTO {
  return {
    id: r.id,
    issueKey: r.issueKey,
    project: r.project,
    title: r.title,
    culprit: r.culprit,
    level: r.level,
    count: r.count,
    userCount: r.userCount,
    firstSeen: r.firstSeen?.toISOString() ?? null,
    lastSeen: r.lastSeen?.toISOString() ?? null,
    permalink: r.permalink,
  };
}

export const errorsStore: Store<ErrorDTO> = {
  async save(db: Db, items: ErrorDTO[], opts?: { complete?: boolean }): Promise<void> {
    // NOT an early return on an empty set — "GlitchTip has nothing unresolved" is
    // exactly the state that must resolve every row we are still holding, and
    // returning here is what made a cleared error board permanent.
    if (items.length > 0) await upsert(db, items);
    // Default TRUE: a caller that says nothing is a whole-answer fetcher (the only other
    // shape in this codebase), and defaulting the other way would silently disable the
    // sweep for every one of them.
    if (opts?.complete ?? true) {
      await resolveVanished(db, items.map((i) => i.issueKey));
    } else {
      // Deliberately loud and deliberately per-poll: this is the state in which the store
      // stops closing rows, and a board that quietly stopped resolving would look exactly
      // like a board with nothing to resolve. Nothing goes stale-red as a result — the
      // fold's own recency window drops any row whose `lastSeen` stops advancing.
      console.warn(
        `[telemetry] GlitchTip returned a full page (${items.length}); the unresolved set is truncated, so no rows were swept this poll`,
      );
    }
  },

  async load(db: Db): Promise<ErrorDTO[]> {
    const rows = await db
      .select()
      .from(errors)
      .where(eq(errors.resolved, false))
      .orderBy(desc(errors.lastSeen))
      .limit(100);
    return rows.map(rowToDTO);
  },
};

async function upsert(db: Db, items: ErrorDTO[]): Promise<void> {
  await db
    .insert(errors)
    .values(
      items.map((i) => ({
        issueKey: i.issueKey,
        project: i.project,
        title: i.title,
        culprit: i.culprit,
        level: i.level,
        count: i.count,
        userCount: i.userCount,
        firstSeen: toDate(i.firstSeen),
        lastSeen: toDate(i.lastSeen),
        permalink: i.permalink,
        resolved: false,
      })),
    )
    .onConflictDoUpdate({
      target: errors.issueKey,
      set: {
        title: sql`excluded.title`,
        culprit: sql`excluded.culprit`,
        level: sql`excluded.level`,
        count: sql`excluded.count`,
        userCount: sql`excluded.user_count`,
        lastSeen: sql`excluded.last_seen`,
        permalink: sql`excluded.permalink`,
        // `project` is REFRESHED, unlike `firstSeen` below it, because this branch
        // promoted it from a display field into an IDENTITY: the board mints
        // `errors|<project>` from it. The conflict target is `issueKey`, so a stored slug
        // that stopped tracking the provider's would keep deriving a target no fact
        // mentions — its ledger row unclosable — while issues under the new slug opened a
        // second, simultaneous problem for the same app. Renames, an issue moved between
        // projects, and a payload that starts supplying `slug` where it used to fall back
        // to `name` all produce exactly that.
        project: sql`excluded.project`,
        // REOPENS a row that had been swept: `excluded.resolved` is the `false` the
        // values list above always carries, so an issue that comes back in a later
        // poll returns to the board instead of staying invisible behind its old
        // resolution. Spelled through `excluded` rather than a literal so it keeps
        // tracking the inserted value if that ever stops being a constant.
        resolved: sql`excluded.resolved`,
        fetchedAt: sql`(unixepoch())`,
      },
    });
}

/**
 * Mark every unresolved row NOT in this poll as resolved — the other half of the
 * reconciliation, and the only writer of `resolved = true` in the system.
 *
 * `notInArray` is given a non-empty list or skipped entirely: drizzle compiles an
 * empty one to `not in ()`, which SQLite rejects. The empty case is not an edge to
 * tolerate but the most important one to get right — it is a GlitchTip with a clean
 * board, and it must resolve everything.
 */
async function resolveVanished(db: Db, seen: string[]): Promise<void> {
  const stillOpen = eq(errors.resolved, false);
  await db
    .update(errors)
    .set({ resolved: true })
    // `fetchedAt` is deliberately NOT restamped: it records when a row was last SEEN
    // in a poll, and this row's defining property is that it wasn't.
    .where(seen.length === 0 ? stillOpen : and(stillOpen, notInArray(errors.issueKey, seen)));
}
