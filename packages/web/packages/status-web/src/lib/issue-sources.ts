/**
 * Where a row/problem came from — DNS resolution, the HTTP probe, the error tracker, or a deploy
 * provider.
 *
 * `glitchtip` is the odd one out and deliberately so: the other sources answer "is the thing
 * reachable", it answers "is the thing THROWING". A site can be up on every probe and still
 * have an error Problem open, which is the whole point of carrying it here rather than
 * folding it into `http`.
 *
 * MIRROR of `src/monitor/issue-sources.ts` — same union, same labels, same
 * order. This side indexes `SOURCE_LABEL[row.source]`, so a source the server can emit and
 * the client has never heard of renders `undefined` in the filter and the badge.
 */
export type IssueSource = "dns" | "http" | "glitchtip" | "vercel" | "cloudflare-pages" | "railway" | "crunchy";

/** Display labels for the source filter + badges. */
export const SOURCE_LABEL: Record<IssueSource, string> = {
  dns: "DNS",
  http: "HTTP",
  glitchtip: "GlitchTip",
  vercel: "Vercel",
  "cloudflare-pages": "Cloudflare",
  railway: "Railway",
  crunchy: "Crunchy Bridge",
};

/** Canonical order for the source filter UI. */
export const ISSUE_SOURCES: IssueSource[] = ["dns", "http", "glitchtip", "vercel", "cloudflare-pages", "railway", "crunchy"];

/** Narrows a raw platform/source string to a known `IssueSource`, so a caller can
 *  filter/index by it without an unchecked `as IssueSource` cast. */
export function isIssueSource(s: string): s is IssueSource {
  return (ISSUE_SOURCES as readonly string[]).includes(s);
}

/**
 * How long a build may sit BUILDING before the BACKEND counts it as stuck
 * (mirror of the server threshold; drives its stuck issues + alerts). The
 * client deliberately does NOT derive stuck problems from this anymore — an
 * in-flight `building` row is activity, never a Problem (owner call,
 * 2026-07-10). `queued` is likewise never stuck: a long queue is almost always
 * an INTENTIONAL hold, not a wedge.
 */
export const STUCK_DEPLOY_MS = 30 * 60 * 1000; // 30 minutes

// NOTE: the platform-unreachable debounce lives SERVER-side (applyPlatformIssues +
// the platform_health_state table) and is folded into the board as a
// `platform-health|<source>` Problem (src/board/derive-problems.ts) — the client
// renders that verdict directly, so there is no client-side streak/threshold here.
