import type { Fetcher, FetchResult } from "../ports";
import type { ErrorDTO } from "../types";

// GlitchTip adapter for the Fetcher port. GlitchTip is Sentry-API-compatible: we
// poll the org-level issues endpoint and map each grouped issue to an ErrorDTO.
// GlitchTip owns the hard parts (source-maps + grouping); we summarize and
// deep-link via `permalink`. PURE w.r.t. storage — returns items, persists
// nothing. No-ops (ok, []) until GLITCHTIP_URL/_API_TOKEN/_ORG are configured.
//
// NOTE: verify the exact response shape against your GlitchTip instance when the
// project is live; the fields below follow the Sentry/GlitchTip issues schema.

export interface GlitchtipEnv {
  GLITCHTIP_URL?: string;
  GLITCHTIP_API_TOKEN?: string;
  GLITCHTIP_ORG?: string;
}

interface GlitchtipIssue {
  id: string;
  title: string;
  culprit?: string | null;
  level?: string | null;
  count?: string | number | null;
  userCount?: number | null;
  firstSeen?: string | null;
  lastSeen?: string | null;
  permalink?: string | null;
  project?: { slug?: string; name?: string } | string | null;
}

function projectSlug(p: GlitchtipIssue["project"]): string {
  if (!p) return "unknown";
  if (typeof p === "string") return p;
  return p.slug ?? p.name ?? "unknown";
}

function normalizeIso(s: string | null | undefined): string | null {
  if (!s) return null;
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

function toCount(c: string | number | null | undefined): number {
  if (typeof c === "number") return c;
  if (typeof c === "string") return Number.parseInt(c, 10) || 0;
  return 0;
}

/** Pure mapping issues → ErrorDTO[] — the testable core, no network. */
export function mapIssues(issues: GlitchtipIssue[]): ErrorDTO[] {
  return issues.map((i) => ({
    id: i.id,
    issueKey: i.id,
    project: projectSlug(i.project),
    title: i.title,
    culprit: i.culprit ?? null,
    level: i.level ?? null,
    count: toCount(i.count),
    userCount: i.userCount ?? 0,
    firstSeen: normalizeIso(i.firstSeen),
    lastSeen: normalizeIso(i.lastSeen),
    permalink: i.permalink ?? null,
  }));
}

// The issue query fans out over source-maps + grouping, so it's usually fast but
// can occasionally stall — give it a generous but BOUNDED budget (no retry: a retry
// just doubles a stalled cycle's wait, which stacked up to wedge the scheduler).
const TIMEOUT_MS = 12_000;

/**
 * One page. GlitchTip's issues endpoint is cursor-paginated and caps a page at 100, so a
 * poll that comes back FULL has almost certainly been truncated — and the truncation is
 * not cosmetic downstream: `errorsStore` reconciles, reading "absent" as "resolved
 * upstream". Reported as `complete` on the result rather than papered over here, because
 * only the store knows what a partial answer costs it.
 */
export const PAGE_LIMIT = 100;

function isTransient(err: unknown): boolean {
  const name = (err as { name?: string })?.name;
  return name === "AbortError" || name === "TimeoutError";
}

export function glitchtipFetcher(env: GlitchtipEnv): Fetcher<ErrorDTO> {
  return {
    async fetch(): Promise<FetchResult<ErrorDTO>> {
      const { GLITCHTIP_URL, GLITCHTIP_API_TOKEN, GLITCHTIP_ORG } = env;
      if (!GLITCHTIP_URL || !GLITCHTIP_API_TOKEN || !GLITCHTIP_ORG) return { ok: true, items: [] };

      const base = GLITCHTIP_URL.replace(/\/+$/, "");
      const url = `${base}/api/0/organizations/${GLITCHTIP_ORG}/issues/?query=is:unresolved&limit=${PAGE_LIMIT}`;
      // A SINGLE bounded attempt — no retry. Retrying a stalled provider just doubles
      // the time this cycle waits, and under sustained degradation that stacked up to
      // blow the scheduler's cycle budget (→ container restarts). A stall/HTTP error
      // blanks the errors band for THIS cycle; the next cycle refills it and the
      // GlitchTip self-check surfaces a genuine outage. Logged CONCISELY (no stack).
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
      try {
        const res = await fetch(url, {
          headers: { Authorization: `Bearer ${GLITCHTIP_API_TOKEN}` },
          signal: controller.signal,
        });
        if (!res.ok) {
          console.warn(`[telemetry] GlitchTip issues HTTP ${res.status}`);
          return { ok: false, items: [] };
        }
        const issues = (await res.json()) as GlitchtipIssue[];
        if (!Array.isArray(issues)) {
          // A 200 that isn't a list is a FAILED poll, not an empty one. This used to
          // return `ok: true, items: []` and was inert only because the store early-returned
          // on an empty set; against a reconciling store the same value resolves the entire
          // errors table and pages on-call an all-clear during a live incident. Every shape
          // that lands here — an error envelope, a maintenance page, an auth-proxy
          // interstitial, a paginated `{results:[…]}` wrapper — means we did not get the
          // answer we asked for, which is exactly what `ok: false` is for.
          console.warn("[telemetry] GlitchTip issues returned a non-array body — treating as a failed poll");
          return { ok: false, items: [] };
        }
        // A FULL page is presumed truncated: see PAGE_LIMIT. Errs toward "we may not have
        // seen everything", which costs a delayed resolve; the other way costs a flap.
        return { ok: true, items: mapIssues(issues), complete: issues.length < PAGE_LIMIT };
      } catch (err) {
        console.warn(
          isTransient(err)
            ? `[telemetry] GlitchTip issues fetch timed out after ${TIMEOUT_MS}ms`
            : `[telemetry] GlitchTip issues fetch failed: ${(err as Error)?.message ?? String(err)}`,
        );
        return { ok: false, items: [] };
      } finally {
        clearTimeout(timer);
      }
    },
  };
}
