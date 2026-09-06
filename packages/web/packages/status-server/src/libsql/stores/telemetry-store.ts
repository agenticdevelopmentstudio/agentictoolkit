import { and, desc, eq, notInArray, sql } from "drizzle-orm";
import type { Db } from "../client";
import { analyticsMetrics, errors } from "../schema";
import type { Store } from "../../telemetry/ports";
import type { AnalyticsMetricDTO, ErrorDTO } from "../../telemetry/types";
import type { TelemetryStore } from "../../storage/ports";

// SQLite/libSQL adapter of TelemetryStore — the ONLY place that knows the
// errors/analytics streams live in a database. Each closes over `db` so nothing
// above this module ever sees a connection.

function toDate(s: string | null): Date | null {
  if (!s) return null;
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? null : d;
}

function rowToErrorDTO(r: typeof errors.$inferSelect): ErrorDTO {
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

async function upsertErrors(db: Db, items: ErrorDTO[]): Promise<void> {
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

function createErrorsStore(db: Db): Store<ErrorDTO> {
  return {
    // `save` is a RECONCILIATION, not an append. The fetcher asks GlitchTip for
    // `is:unresolved`, so each poll delivers the COMPLETE current set — an issue
    // that is absent has been resolved (or deleted) upstream, and the only way to
    // learn that is its absence. See git history for the two preconditions
    // (poll succeeded, answer whole) that make the sweep below safe.
    async save(items: ErrorDTO[], opts?: { complete?: boolean }): Promise<void> {
      // NOT an early return on an empty set — "GlitchTip has nothing unresolved" is
      // exactly the state that must resolve every row we are still holding, and
      // returning here is what made a cleared error board permanent.
      if (items.length > 0) await upsertErrors(db, items);
      // Default TRUE: a caller that says nothing is a whole-answer fetcher (the only
      // other shape in this codebase), and defaulting the other way would silently
      // disable the sweep for every one of them.
      if (opts?.complete ?? true) {
        await resolveVanished(
          db,
          items.map((i) => i.issueKey),
        );
      } else {
        // Deliberately loud and deliberately per-poll: this is the state in which the
        // store stops closing rows, and a board that quietly stopped resolving would
        // look exactly like a board with nothing to resolve. Nothing goes stale-red as
        // a result — the fold's own recency window drops any row whose `lastSeen` stops
        // advancing.
        console.warn(
          `[telemetry] GlitchTip returned a full page (${items.length}); the unresolved set is truncated, so no rows were swept this poll`,
        );
      }
    },

    async load(): Promise<ErrorDTO[]> {
      const rows = await db
        .select()
        .from(errors)
        .where(eq(errors.resolved, false))
        .orderBy(desc(errors.lastSeen))
        .limit(100);
      return rows.map(rowToErrorDTO);
    },
  };
}

function createAnalyticsStore(db: Db): Store<AnalyticsMetricDTO> {
  return {
    async save(items: AnalyticsMetricDTO[]): Promise<void> {
      if (items.length === 0) return;
      await db.insert(analyticsMetrics).values(
        items.map((i) => ({
          metric: i.metric,
          window: i.window,
          scope: i.scope,
          value: i.value,
          capturedAt: new Date(i.capturedAt),
        })),
      );
    },

    async load(): Promise<AnalyticsMetricDTO[]> {
      const rows = await db
        .select()
        .from(analyticsMetrics)
        .orderBy(desc(analyticsMetrics.capturedAt))
        .limit(100);

      // Reduce to the latest snapshot per (metric, window, scope).
      const latest = new Map<string, typeof analyticsMetrics.$inferSelect>();
      for (const r of rows) {
        const key = `${r.metric}|${r.window}|${r.scope}`;
        if (!latest.has(key)) latest.set(key, r);
      }
      return Array.from(latest.values()).map((r) => ({
        metric: r.metric,
        window: r.window,
        scope: r.scope,
        value: r.value,
        capturedAt: r.capturedAt.toISOString(),
      }));
    },
  };
}

export function createTelemetryStore(db: Db): TelemetryStore {
  return {
    errors: createErrorsStore(db),
    analytics: createAnalyticsStore(db),
  };
}
