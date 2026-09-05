import type { Row } from "./row-model";
import { hostOf } from "./url";
import { platformLabel } from "./deploy-display";

/** The fields the details pane renders for a selected row. */
/**
 * Sources that render as deploy rows but deploy NOTHING — see `deployOutcome` below.
 * Keyed by the row's `platform`, which is the `IssueSource` string.
 */
const NON_DEPLOY_PLATFORMS = new Set(["crunchy", "glitchtip"]);

export interface RowDetail {
  title: string;
  titleUrl: string | null;
  environment: string | null;
  /** "built on vercel"-style phrase, or null when the row has no deploy platform. */
  platformText: string | null;
  platformLink: string | null;
  problem: string | null;
  problemLink: string | null;
  /** HTTP status of the last probe (endpoint problems). */
  statusCode: number | null;
  /** Last-probe latency, preformatted (e.g. "1200ms"). */
  responseTime: string | null;
  /** Deploy branch (deployment rows). */
  branch: string | null;
  /** ISO onset time — "down since" for endpoints, event time otherwise. */
  since: string | null;
  /** ISO time of the last health probe (endpoint problems). */
  lastChecked: string | null;
  sha: string | null;
  commitSubject: string | null;
  commitUrl: string | null;
  commitBody: string | null;
  /** Provider failure reason for a failed deploy — the actual build error
   *  (Vercel errorMessage / Railway build-log tail), possibly multi-line. */
  errorText: string | null;
  /** Settled build/deploy outcome for the Overview headline — null for endpoint
   *  rows, resolved issues, and in-flight (building/canceled) deploys. */
  deployOutcome: "success" | "failed" | null;
}

/** Serialize a RowDetail to a clean, labeled plaintext block — for the details
 *  pane's "copy" button, so the whole problem (endpoint, reason, platform, branch,
 *  timings, commit + message, and the inspector/dashboard link where the logs live)
 *  can be pasted straight into an LLM without opening the provider dashboard. Only
 *  populated fields are emitted; blank lines separate the commit body. */
export function rowDetailToText(d: RowDetail): string {
  const lines: string[] = [];
  const add = (label: string, val: string | number | null | undefined): void => {
    if (val != null && val !== "") lines.push(`${label}: ${val}`);
  };
  add("endpoint", d.title);
  if (d.titleUrl && d.titleUrl !== d.title) add("url", d.titleUrl);
  add("environment", d.environment);
  add("platform", d.platformText);
  add("problem", d.problem);
  add("http status", d.statusCode);
  add("response", d.responseTime);
  add("branch", d.branch);
  add("since", d.since);
  add("last check", d.lastChecked);
  if (d.sha || d.commitSubject) add("commit", [d.sha, d.commitSubject].filter(Boolean).join(" "));
  add("commit url", d.commitUrl);
  // The provider inspector / dashboard page — where the actual build logs live.
  add("link", d.platformLink ?? d.problemLink ?? d.titleUrl);
  // The actual build-failure reason/log — its own labeled block since it's the
  // whole point of the copy (paste straight into an LLM) and may be multi-line.
  if (d.errorText) {
    lines.push("", "error:", d.errorText);
  }
  if (d.commitBody && d.commitBody !== d.commitSubject) {
    lines.push("", d.commitBody);
  }
  return lines.join("\n");
}

/** Map a Row to the labeled details summary. Mirrors StatusRow's link derivations
 *  so the row and the details pane always agree on titles/links — including the status
 *  word, which both now render exactly as the server sent it (see rowToStatusRowProps:
 *  the client-side freshness demotion this used to re-apply is gone, and with it this
 *  function's `nowMs`). */
export function rowToDetailProps(row: Row): RowDetail {
  const isEndpoint = row.platform === "http" || row.platform === "dns";
  // Match StatusRow's title-link precedence exactly so the row title and the details
  // "endpoint" link agree: an endpoint IS its checked url (liveUrl first); a deploy's
  // title links to its deployment page (sourceUrl first).
  const titleUrl = isEndpoint ? (row.liveUrl ?? row.sourceUrl ?? null) : (row.sourceUrl ?? row.liveUrl ?? null);
  const title = isEndpoint && titleUrl ? hostOf(titleUrl) : row.name;
  const isResolved = row.statusWord.startsWith("[");
  const platformName = !isEndpoint && row.platform && !isResolved ? platformLabel(row.platform).toLowerCase() : null;
  // Deploy-status issues set `detail` to the commit's first line; when the problem text
  // is just the commit subject, drop it — the "git commit" field already shows it.
  const problem = row.detail && row.detail !== row.message ? row.detail : null;
  return {
    title,
    titleUrl,
    environment: row.environment,
    platformText: platformName ? `${row.statusWord} on ${platformName}` : null,
    // Only the specific deployment URL is stored — no project-level dashboard URL
    // is derivable from the provider metadata — so "platform" links to the
    // deployment page (the closest available deployments context).
    platformLink: platformName ? row.sourceUrl : null,
    problem,
    problemLink: problem ? row.sourceUrl : null,
    statusCode: row.statusCode ?? null,
    responseTime: row.responseTimeMs != null ? `${row.responseTimeMs}ms` : null,
    branch: row.branch ?? null,
    // Prefer the server-truth down-since; fall back to the row's event time so the
    // pane always shows WHEN, absolute — the list only carries a relative label.
    since: row.downSince ?? row.at ?? null,
    lastChecked: row.lastCheckedAt ?? null,
    sha: row.sha,
    commitSubject: row.message,
    commitUrl: row.commitUrl,
    commitBody: row.commitBody ?? null,
    errorText: row.errorText ?? null,
    // Only a live (non-resolved) deploy row with a settled tone gets a headline;
    // in-flight (progress) and canceled (neutral) stay null.
    //
    // NON_DEPLOY_PLATFORMS is the carve-out, and it is about what the row actually
    // reports. Crunchy rows are DB-CLUSTER HEALTH mapped onto deploy phases
    // (fetch-crunchy) and GlitchTip rows are APPLICATION ERRORS — in neither case was
    // anything built or deployed, so the "✕ build / deploy FAILED" headline names an
    // event that did not happen, and the pane's `logs` label would present an exception
    // list as a build log. `platformName` alone can't tell them apart: it is truthy for
    // every registered source, which is exactly why this list has to be explicit.
    deployOutcome:
      platformName && !NON_DEPLOY_PLATFORMS.has(row.platform ?? "")
        ? (row.tone === "bad" ? "failed" : row.tone === "good" ? "success" : null)
        : null,
  };
}
