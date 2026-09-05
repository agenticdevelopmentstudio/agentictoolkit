import type { IssueSource } from "./issue-sources";

// The wire contract for GET /api/board — hand-mirrored from src/board/types.ts (the
// server tree, which the web app cannot import at runtime). Pinned by
// board-types-parity.test.ts's mutual-assignability check; keep the two in lockstep.

export type ActivityKind = "deploy" | "probe" | "platform";

/**
 * The row's colour/weight axis, matching the client's `RowTone` one-for-one so the
 * pane renders the wire value directly instead of re-deriving it. `stale` = the row's
 * claim could not be re-confirmed (an `unknown` phase) — muted, neither progress amber
 * nor a verdict's colour.
 */
export type ActivityTone = "good" | "bad" | "progress" | "neutral" | "stale";

export type Indicator = "operational" | "degraded" | "outage";

/** One row of the Problems list. This is the wire shape the client renders. */
export interface Problem {
  /**
   * For a deploy target, `boardTargetKey()` output. For an endpoint, the endpoint's
   * BARE id — `reads.ts:437` and `app.ts:91` both tell endpoint problems from the rest
   * by testing `serviceSlugs.has(target)`, so wrapping it would break both. For platform
   * health, `platform-health|<source>` — TWO segments, no trailing pipe. That is the
   * spelling already in the `issues` table (`issues.ts:611`), and it is deliberately not
   * minted by `boardTargetKey()`: a provider is not a deploy target, and giving it a
   * third segment would orphan every live platform-health row for no gain.
   */
  target: string;
  source: IssueSource;
  /** Human name — the project or site name, never the id. */
  name: string;
  environment: string | null;
  severity: "critical" | "major" | "minor";
  /** What kind of problem: `failed`, `stuck`, `down`, `degraded`, `stale`, `unreachable`. */
  state: string;
  statusCode: number | null;
  detail: string | null;
  sourceUrl: string | null;
  liveUrl: string | null;
  commitHash: string | null;
  commitMessage: string | null;
  commitRepo: string | null;
  /**
   * The git ref the deploy was built from, RAW — the same field the tier in `environment`
   * was derived from, carried on as well because the details pane's Git tab shows the
   * branch itself. A stale-production problem carries the project's CONFIGURED production
   * branch. Null on every problem that is not about a deploy.
   */
  branch: string | null;
  /**
   * The provider's own words about the failure, which the details pane renders as its
   * error block. Null wherever there is no provider text.
   */
  errorText: string | null;
  /** ISO time the problem began — from the ledger when known, else first observation. */
  since: string;
}

/** One row of the Activity feed — a RECORD of something that happened. */
export interface ActivityRow {
  /**
   * Stable identity for React keys, dedup, and the `(at, id)` paging cursor.
   *
   * `deploy:<deploymentId>:<step>` for a deployment's build/deploy rows;
   * `issue:<target>:opened|resolved:<atMs>:<issueId>` for issue rows.
   *
   * STABLE is the load-bearing word, not merely unique. Every component must be immutable
   * for the life of the fact: the client keys history by this string and cannot tell a row
   * that was renamed from a row that was withdrawn and replaced. Deploy rows carry no
   * target and no timestamp precisely because `deployments.created_at`, `project_name` and
   * `branch` are all corrected after the row first renders — see `deriveActivity`'s
   * `deployRowId`, and `docs/status-site/status-activity-row-ids-must-not-move.md`.
   */
  id: string;
  kind: ActivityKind;
  /**
   * Which lifecycle step this row records. A deployment emits a build row and, when it
   * got that far, a deploy row — the two are distinct events and the pane has always
   * shown them as separate lines. Null for probe/platform rows.
   */
  step: "build" | "deploy" | null;
  /**
   * The provider/probe this row came from, in the SAME `IssueSource` spelling
   * `Problem.source` uses (`"cloudflare-pages"`, never the canonical `"cloudflare"`) — a
   * deploy row's platform, or an issue row's source. Null only if genuinely unknown.
   */
  source: IssueSource | null;
  /**
   * Tone is DERIVED FROM the event, and `kind` is never recomputed from tone.
   * (activity-store.ts:322 did exactly that, which is defect #1 in the spec.)
   */
  tone: ActivityTone;
  /**
   * The rendered status word — "building", "build failed", "deployed", "[down] resolved".
   * On the wire because the server owns what a row SAYS, exactly as it owns whether the
   * row exists. The client copies it into `Row.statusWord` and renders it; it does not
   * own a second verb table for this pane.
   */
  verb: string;
  target: string;
  name: string;
  environment: string | null;
  detail: string | null;
  sourceUrl: string | null;
  liveUrl: string | null;
  commitHash: string | null;
  commitMessage: string | null;
  commitRepo: string | null;
  /** The deploy's git ref, raw — see `Problem.branch`. Null on an issue row. */
  branch: string | null;
  /** The provider's failure text — see `Problem.errorText`. Null on an issue row. */
  errorText: string | null;
  /** ISO time the event happened. */
  at: string;
}

/** The whole board. One read, one clock, one truth. */
export interface Board {
  /** ISO server clock at derivation — the client's only time reference. */
  generatedAt: string;
  /** Epoch ms of the newest observation the board was derived from — null when the
   *  board rests on no observations at all. NOT `generatedAt`: a wedged monitor keeps
   *  minting a fresh generatedAt over frozen data. */
  dataAsOfMs: number | null;
  /** The monitor's probe cadence in ms. The freshness windows this client scales by it are
   *  judging THIS board, so the cadence travels with it rather than arriving separately on
   *  the SSE stream — which left it null for every consumer that never opens a stream. */
  probeIntervalMs: number;
  /** Epoch ms of the OLDEST event `activity` can contain. Anything counting or captioning
   *  those rows reads the boundary from here instead of re-deriving a window of its own. */
  activityFromMs: number;
  problems: Problem[];
  activity: ActivityRow[];
  indicator: Indicator;
  /**
   * Every target the board is CURRENTLY WATCHING — the roster's own targets, whether or
   * not they have a problem. This is what separates "this target recovered" from "this
   * target is no longer monitored" when closing a ledger row, and those two must not be
   * confused: `resolveIssue` alerts on the first and stays silent on the second, so
   * closing a de-configured target as "recovered" pages on-call that an outage cleared
   * when it may still be burning.
   *
   * Replaces `/live`'s `deployTargets?: string[]`, which existed so the CLIENT could run
   * its own orphan sweep. The sweep is the server's now; the list stays because the
   * ledger writer needs it.
   */
  monitoredTargets: string[];
}

/**
 * A position in the activity feed. The PAIR, not the timestamp alone: a deployment's
 * build and deploy rows share one `createdAtMs`, so a time-only cursor would either
 * re-serve one of them every page or skip it entirely.
 */
export interface ActivityCursor {
  atMs: number;
  id: string;
}

/** One page of activity, oldest-first like the feed itself. */
export interface ActivityPage {
  rows: ActivityRow[];
  /** Where the NEXT (older) page starts, or null when the facts are exhausted. */
  nextCursor: ActivityCursor | null;
}
