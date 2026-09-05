import type { DeploymentDTO } from "../types";
import type { StatusRowProps } from "../components/StatusRow";
import { deployStatusInFlight } from "./deploy-status";
import { shortSha, commitFirstLine } from "./format";
import { timeAgo } from "./time-ago";
import { envBadgeLabel } from "./colors";
import { SOURCE_LABEL, isIssueSource, type IssueSource } from "./issue-sources";
import type { ActivityRow, Problem } from "./board-types";

// ---------------------------------------------------------------------------
// The ONE row model. Active problems, recently-resolved, and the activity feed
// are all built into this single shape, then rendered by the one <StatusRow>
// via rowToStatusRowProps — so every pane has identical row capabilities
// (clickable commits, consistent links) and a new field is added in one place.
// ---------------------------------------------------------------------------

/**
 * Color + weight class for a row. Collapses the three former per-pane color
 * systems (issue severity, resolved=green, activity tone) into one axis:
 * the row's tone fully determines its dot/word color and bold weight.
 * `stale` = the row's claim could not be (re)confirmed — muted, neither the
 * amber of live progress nor the colors of a verdict.
 */
export type RowTone = "good" | "bad" | "progress" | "neutral" | "stale";

export interface Row {
  key: string;
  /** Issue source / deploy platform — drives the badge + the source filter. */
  source: string;
  /** Badge glyph platform (=== source for issue rows). */
  platform: string | null;
  name: string;
  environment: string | null;
  /** Line-1 status word ("deploy failed", "deployed", "[down] resolved"). */
  statusWord: string;
  tone: RowTone;
  sha: string | null;
  commitUrl: string | null;
  message: string | null;
  /** Full commit message (subject + body) for the details pane; `message` stays the subject. */
  commitBody?: string | null;
  detail: string | null;
  /** ISO timestamp shown as a relative time and used for window filtering. */
  at: string;
  sourceUrl: string | null;
  liveUrl: string | null;
  // --- optional diagnostics surfaced ONLY in the details pane (present where the
  // source carries them; undefined elsewhere so existing builders stay unchanged). ---
  /** HTTP status of the last probe (endpoint) / deploy check. */
  statusCode?: number | null;
  /** Last-probe latency in ms (endpoint problems). */
  responseTimeMs?: number | null;
  /** ISO time of the last health probe (endpoint problems). */
  lastCheckedAt?: string | null;
  /** Server-truth "down since" — the endpoint's open issue openedAt, durable across
   *  browsers (unlike the client-onset `at`). null/undefined = not a live endpoint down. */
  downSince?: string | null;
  /** Deploy branch (deployment rows). */
  branch?: string | null;
  /** Provider failure reason for a failed deploy (Vercel errorMessage / Railway
   *  build-log tail) — shown verbatim in the details pane. */
  errorText?: string | null;
}

const TONE_COLOR: Record<RowTone, string> = {
  good: "var(--color-apt-green)",
  bad: "var(--color-apt-red)",
  progress: "var(--color-apt-gold)", // in-progress / warn → amber
  neutral: "var(--color-apt-gold)", // canceled → amber
  stale: "var(--color-apt-text-muted)", // unconfirmed claim / expired outcome → muted
};

/** FLOOR for how long an IN-FLIGHT deploy may go without backend confirmation before the
 *  UI stops asserting it as live progress. At the default 60s probe cadence the
 *  backend re-confirms in-flight rows every ~2 min (by-id reconcile) and every 5 min
 *  (provider poll), so 10 minutes unconfirmed means several consecutive confirmation
 *  failures — not jitter. This is the render-time half of the freshness contract: even
 *  when every server-side healer is dead, the display degrades to honesty by
 *  construction.
 *
 *  It judges DeploymentDTOs ONLY, via {@link deployDtoUnconfirmed} — the raw-deploy
 *  panels are the last place the client still holds a phase the server has not already
 *  ruled on. A `Row` never passes through here: an activity/problem row arrives with the
 *  server's own verdict (`derive-activity.ts` expires an unconfirmed phase to tone
 *  "stale" itself), so a second client-side clock over the same fact could only
 *  disagree with it. */
export const UNCONFIRMED_AFTER_MS = 10 * 60_000;

/** The unconfirmed window for a given backend probe cadence: 5× the probe interval,
 *  floored at {@link UNCONFIRMED_AFTER_MS}. Mirrors snapshot-staleness' `snapshotStaleMs`
 *  (and the scheduler's own `staleAfterMs`) so a SLOWER-configured poller doesn't make
 *  a normally-confirmed row false-demote — the render threshold tracks the real cadence,
 *  never a hardcoded 10 min that assumes a 60s probe. Undefined interval (older backend)
 *  → the floor. */
export function unconfirmedWindowMs(probeIntervalMs?: number): number {
  return Math.max(UNCONFIRMED_AFTER_MS, (probeIntervalMs ?? 0) * 5);
}

/** Whether an in-flight deploy's phase has outlived its confirmation, for the panels
 *  (DeployList, and summarizeByPlatform's "Build pipeline" counts) that render a
 *  DeploymentDTO directly instead of a Row — so they demote a wedged build in lockstep
 *  with the activity list, whose equivalent demotion the SERVER applies before the row
 *  ever reaches the browser. Fails CLOSED: an in-flight deploy whose clock is
 *  unparseable demotes, rather than asserting live progress on a date we can't read. */
export function deployDtoUnconfirmed(
  d: Pick<DeploymentDTO, "status" | "phaseConfirmedAt" | "createdAt">,
  nowMs: number,
  probeIntervalMs?: number,
): boolean {
  if (!deployStatusInFlight(d.status)) return false;
  const confirmed = Date.parse(d.phaseConfirmedAt ?? d.createdAt);
  if (!Number.isFinite(confirmed)) return true;
  return nowMs - confirmed > unconfirmedWindowMs(probeIntervalMs);
}

/** Adapt a Row to the one <StatusRow>'s props. Every pane goes through here.
 *
 *  The word and tone are rendered AS GIVEN. There used to be a `displayStatus` step here
 *  that re-judged an in-flight row's freshness and demoted it to "last seen building" —
 *  unreachable code, because both producers state `inFlight: false` and the server has
 *  already applied that very demotion (an unconfirmed phase reaches the client as verb
 *  "unknown", tone "stale"). `nowMs` survives for the timestamp alone. */
export function rowToStatusRowProps(row: Row, nowMs: number): StatusRowProps {
  return {
    platform: row.platform ?? undefined,
    environment: row.environment,
    name: row.name,
    statusWord: row.statusWord,
    statusColor: TONE_COLOR[row.tone],
    statusBold: row.tone === "bad",
    timeLabel: timeAgo(row.at, nowMs),
    sourceUrl: row.sourceUrl,
    liveUrl: row.liveUrl,
  };
}

/** Free-text the filter boxes search against — one definition for all panes. The status
 *  word is the row's own, which is exactly what the row renders (rowToStatusRowProps),
 *  so a filter always matches the on-screen text. */
export function rowSearchText(row: Row): string {
  // Search the FULL commit body (which the details pane now shows). commitBody ⊇ the
  // subject line (`message`), so it already covers the compact "git commit" text.
  return `${row.name} ${row.environment ?? ""} ${row.statusWord} ${row.detail ?? ""} ${row.commitBody ?? ""}`;
}

// ---------------------------------------------------------------------------
// Clipboard serialization. One row → one tab-separated line so a copied pane
// pastes cleanly into a doc or spreadsheet (columns stay aligned) while still
// reading sensibly as plain text. Same Row shape every pane uses, so all three
// copy buttons share one format.
// ---------------------------------------------------------------------------

/** A single row as one tab-separated line: time · env · source · name · status · commit/detail · url. */
export function rowToText(row: Row, nowMs: number): string {
  // commit (sha + message) takes precedence over the generic detail line, mirroring
  // what the row renders on line 2.
  const commit = [row.sha, row.message].filter(Boolean).join(" ");
  // The source column uses the same friendly label the badge/source-filter show
  // ("Cloudflare", not the internal "cloudflare-pages"), so copied text matches
  // the screen. The url column is ALWAYS present (empty when there's no url) so
  // every row has the same number of tab-separated fields and pastes as aligned
  // columns into a spreadsheet.
  const cols = [
    timeAgo(row.at, nowMs),
    row.environment ? envBadgeLabel(row.environment) : "",
    // `Row.source` is a plain string (an activity row falls back to its `kind` when the
    // server couldn't attribute a source), so NARROW it — `SOURCE_LABEL[x as IssueSource]`
    // was an unchecked cast that told the type system a lie and then leaned on `??` to
    // survive it. `isIssueSource` makes the fallback a real branch instead of a rescue.
    isIssueSource(row.source) ? SOURCE_LABEL[row.source] : row.source,
    row.name,
    // Copied text matches the screen — same word the row renders, verbatim.
    row.statusWord,
    commit || row.detail || "",
    row.liveUrl ?? row.sourceUrl ?? "",
  ];
  return cols.join("\t");
}

/** Every row as newline-separated text — what a pane's copy button writes to the clipboard. */
export function rowsToText(rows: Row[], nowMs: number): string {
  return rows.map((r) => rowToText(r, nowMs)).join("\n");
}

/** GitHub commit url from a stored "owner/name" repo + sha, else null. */
export function commitUrlOf(repo: string | null, hash: string | null): string | null {
  return repo && hash ? `https://github.com/${repo}/commit/${hash}` : null;
}

// ---------------------------------------------------------------------------
// Board (Problem / ActivityRow) → Row. The server has already decided what is a
// problem, what happened, and when — these builders only spell the row.
// ---------------------------------------------------------------------------

/** The observed bad state → its line-1 status word. Exported for `problemToRow`. */
export const STATE_LABEL: Record<string, string> = {
  down: "down",
  degraded: "degraded",
  failed: "deploy failed",
  stuck: "deploy stuck",
  // "stale" = the live production deployment is behind/errored while newer builds
  // sit ahead of it unpromoted — i.e. the deployment itself has failed.
  stale: "deployment failed",
  // "unreachable" = the deploy provider's own API couldn't be polled, so we're
  // blind to that platform's deploys (a monitor-side problem, not a deploy's).
  unreachable: "platform unreachable",
  // "erroring" = the app is THROWING while its host answers normally. Deliberately not
  // "errors": every other word here is a state the thing is IN, and the distinction this
  // row exists to make is that a reachable site can still be broken.
  erroring: "app errors",
};

/**
 * A server-derived Problem → a Row. No decisions here: whether this is a problem, what
 * it is called, and when it started were all settled by `deriveBoard`. This function
 * only spells the row.
 */
export function problemToRow(p: Problem): Row {
  const failureLabel = STATE_LABEL[p.state] ?? p.state;
  const commitUrl = commitUrlOf(p.commitRepo, p.commitHash);
  return {
    key: `problem:${p.target}`,
    source: p.source,
    platform: p.source,
    name: p.name,
    environment: p.environment,
    statusWord: failureLabel,
    // Open minor (degraded) → amber/not-bold; else red/bold. Problems are never green:
    // a resolved thing is not a problem, it is an activity row.
    tone: p.severity === "minor" ? "progress" : "bad",
    // Show the sha only when it links somewhere — a bare, non-clickable hash is noise.
    sha: commitUrl ? shortSha(p.commitHash) : null,
    commitUrl,
    message: commitFirstLine(p.commitMessage),
    commitBody: p.commitMessage,
    detail: p.detail,
    at: p.since,
    sourceUrl: p.sourceUrl,
    liveUrl: p.liveUrl,
    statusCode: p.statusCode,
    downSince: p.since,
    // The details pane's Git tab and error block, both straight off the wire — see
    // `Problem.branch`/`.errorText`.
    branch: p.branch,
    errorText: p.errorText,
  };
}

/**
 * A server-derived ActivityRow → a Row. The verb and tone arrive on the wire, so there
 * is deliberately NO phase table here: the pane renders what the server said happened.
 */
export function activityToRow(a: ActivityRow): Row {
  const commitUrl = commitUrlOf(a.commitRepo, a.commitHash);
  // The row's platform/source arrives on the wire directly (`ActivityRow.source`) in
  // the SAME `IssueSource` spelling `Problem.source` uses ("cloudflare-pages", never
  // `boardTargetKey`'s canonical "cloudflare") — no parsing of `a.target` or
  // reconciliation needed here. Falls back to the row's `kind` only when the server
  // genuinely couldn't attribute a source (should not happen in practice), so the
  // clipboard/source columns always have SOMETHING rather than an empty string.
  const platform = a.source ?? null;
  return {
    key: a.id,
    source: platform ?? a.kind,
    platform,
    name: a.name,
    environment: a.environment,
    statusWord: a.verb,
    tone: a.tone,
    sha: commitUrl ? shortSha(a.commitHash) : null,
    commitUrl,
    message: commitFirstLine(a.commitMessage),
    commitBody: a.commitMessage,
    detail: a.detail,
    at: a.at,
    sourceUrl: a.sourceUrl,
    liveUrl: a.liveUrl,
    branch: a.branch,
    errorText: a.errorText,
  };
}

