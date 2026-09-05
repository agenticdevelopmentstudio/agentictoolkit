import { promises as dnsp } from "node:dns";
import { classify, HEALTH_CHECK_TIMEOUT_MS, type HealthStatus } from "./health";
import { mapLimit } from "@agentic-toolkit/deploy-platform/util";
import type { ConfiguredEndpoint } from "../storage/config-store";

// The live HTTP/DNS probe — the single source of truth for "is this endpoint up
// right now". Used by the health sync (which persists the results, see sync.ts)
// AND by the /api/status route's no-DB fallback (which returns them straight to
// the wallboard when the database is unreadable). Kept free of any DB import so
// the status route can fall back to a live probe without pulling in the writer
// graph — `ConfiguredEndpoint` is a type-only import.

const USER_AGENT = "AgenticDeveloperHubStatus/1.0";

// Probe endpoints in bounded batches rather than all at once. A single serverless
// invocation fanning ~90 simultaneous fetch()+DNS calls saturates Node's getaddrinfo
// threadpool (4 threads) and socket pool, so each probe's wall-clock timer ends up
// counting time spent *queued behind the other probes* — which inflated every site's
// "response time" into a uniform ~2s band and tripped the degraded threshold for sites
// that actually answer in <300ms. Bounding in-flight work keeps each measurement about
// the site, not the checker.
//
// 24 is chosen against two limits: low enough that DNS queue depth (~24/4 = 6) stays
// well under the saturation that caused the inflation, yet high enough that a wide
// outage — where many endpoints hang to the full HEALTH_CHECK_TIMEOUT_MS — still
// finishes inside the route's maxDuration (60s): ~134 endpoints × 10s / 24 ≈ 56s.
// (At the old 20, a total outage of today's 134-endpoint fleet would take ~67s and
// be killed by the platform before results could be served.)
export const HEALTH_PROBE_CONCURRENCY = 24;

// Cap on how much of a probed body is read (health JSON and expectBody markers
// live in the first bytes). Without a cap, classifying "read the whole body"
// lets one endless/huge response drain forever inside the cycle.
export const PROBE_BODY_MAX_BYTES = 256 * 1024;

// DNS resolution deadline. c-ares has its own retry budget, but a black-holed
// resolver can exceed it; an un-deadlined lookup holds a probe slot hostage.
const DNS_TIMEOUT_MS = 5_000;

/** Injectable deadlines — production callers use the defaults; tests shrink them. */
export interface ProbeOptions {
  /** Deadline for the whole HTTP leg — headers AND body read. */
  timeoutMs?: number;
  dnsTimeoutMs?: number;
}

export interface Probe {
  slug: string;
  status: HealthStatus;
  responseTimeMs: number | null;
  statusCode: number | null;
  error: string | null;
  /** Whether the site's hostname resolved in DNS. false → a DNS-resolution problem. */
  dnsOk: boolean;
}

/** Which DNS record types the resolution check queries (per-endpoint, A/AAAA/CNAME). */
interface DnsChecks {
  a: boolean;
  aaaa: boolean;
  cname: boolean;
}

/** Resolve an endpoint's DNS-check toggles, defaulting every record type ON so an
 *  endpoint configured before the toggles existed keeps the original behaviour. */
function dnsChecksOf(svc: ConfiguredEndpoint): DnsChecks {
  return {
    a: svc.dnsCheckA ?? true,
    aaaa: svc.dnsCheckAaaa ?? true,
    cname: svc.dnsCheckCname ?? true,
  };
}

/**
 * Independently resolve a hostname across the ENABLED record types — A, AAAA,
 * and/or CNAME. Subdomains usually point at their host via a CNAME (e.g.
 * `staging.olylo.ai` → `cname.vercel-dns.com`) rather than carrying A/AAAA
 * directly, so a CNAME counts as resolvable. This is the "actual DNS name
 * resolution" check, catching a name that no longer resolves before it manifests
 * as a fetch error (a host that resolves but doesn't serve is caught by the HTTP
 * probe instead). With every record type disabled the check is skipped entirely
 * — DNS no longer gates the HTTP probe — and only the enabled types are queried.
 */
async function resolveDns(
  hostname: string,
  checks: DnsChecks,
  timeoutMs: number,
): Promise<{ ok: boolean; error: string | null }> {
  if (!checks.a && !checks.aaaa && !checks.cname) return { ok: true, error: null };
  const lookup = async (): Promise<{ ok: boolean; error: string | null }> => {
    try {
      if (checks.a) {
        const v4 = await dnsp.resolve4(hostname).catch(() => [] as string[]);
        if (v4.length > 0) return { ok: true, error: null };
      }
      if (checks.aaaa) {
        const v6 = await dnsp.resolve6(hostname).catch(() => [] as string[]);
        if (v6.length > 0) return { ok: true, error: null };
      }
      if (checks.cname) {
        const cname = await dnsp.resolveCname(hostname).catch(() => [] as string[]);
        if (cname.length > 0) return { ok: true, error: null };
      }
      return { ok: false, error: "does not resolve" };
    } catch (err) {
      return { ok: false, error: err instanceof Error ? err.message : "DNS error" };
    }
  };
  // Race the lookups against a hard deadline: a resolver that never answers must
  // fail THIS probe (fail-fast), not stall its concurrency slot. The abandoned
  // lookups settle on their own — c-ares cleans up after itself.
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<{ ok: false; error: string }>((resolve) => {
    timer = setTimeout(() => resolve({ ok: false, error: "resolution timed out" }), timeoutMs);
  });
  try {
    return await Promise.race([lookup(), deadline]);
  } finally {
    clearTimeout(timer);
  }
}

/** What a capped body read yielded: the text, whether the CAP cut it short (so a
 *  missing marker can be explained rather than reported as a broken page), and
 *  whether the read FAILED mid-stream. */
interface CappedBody {
  text: string;
  truncated: boolean;
  failed: boolean;
}

/** Read at most `maxBytes` of the body, then release the connection. Runs under
 *  the probe's abort signal (the fetch's), so a trickling body hits the same
 *  deadline as slow headers instead of hanging the probe — and the cycle —
 *  forever. Always cancels the rest of the stream, hit cap or not, so the
 *  socket returns to the pool.
 *
 *  A mid-stream read error is REPORTED, not thrown: the server already answered
 *  with headers, so a broken body is not evidence the site is down — and since
 *  HTTP issues carry no debounce, letting it hard-fail would open an issue (and
 *  page on-call) off one connection blip. The abort/deadline case still throws,
 *  because a body that never arrives IS an outage. */
async function readBodyCapped(res: Response, maxBytes: number, signal: AbortSignal): Promise<CappedBody> {
  if (!res.body) return { text: "", truncated: false, failed: false };
  const reader = res.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  let failed = false;
  let truncated = false;
  try {
    while (total < maxBytes) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
      total += value.byteLength;
    }
    // Loop left with budget spent rather than `done` — more body was coming.
    truncated = total >= maxBytes;
  } catch (err) {
    // The deadline fired: this IS the outage signal — let probe() classify it.
    if (signal.aborted) throw err;
    failed = true;
    console.error(`[probe] body read failed after headers: ${err instanceof Error ? err.message : String(err)}`);
  } finally {
    await reader.cancel().catch(() => {});
  }
  return { text: Buffer.concat(chunks).toString("utf8"), truncated, failed };
}

export async function probe(svc: ConfiguredEndpoint, opts: ProbeOptions = {}): Promise<Probe> {
  const timeoutMs = opts.timeoutMs ?? HEALTH_CHECK_TIMEOUT_MS;
  const dnsTimeoutMs = opts.dnsTimeoutMs ?? DNS_TIMEOUT_MS;
  const start = Date.now();

  // 1) DNS resolution — a name that doesn't resolve is a DNS problem, distinct
  //    from a server that resolves but returns an error. Short-circuit: if it
  //    can't resolve, the HTTP fetch can't reach it either.
  let hostname = "";
  try {
    hostname = new URL(svc.url).hostname;
  } catch {
    hostname = "";
  }
  if (hostname) {
    const dns = await resolveDns(hostname, dnsChecksOf(svc), dnsTimeoutMs);
    if (!dns.ok) {
      return {
        slug: svc.slug,
        status: "down",
        responseTimeMs: Date.now() - start,
        statusCode: null,
        error: `DNS: ${dns.error}`,
        dnsOk: false,
      };
    }
  }

  // 2) HTTP probe — DNS resolved, so any failure here is a server/HTTP problem.
  //    Time only the HTTP request itself (from just before fetch), NOT the DNS
  //    work above: "response time" should mean how long the *site* took to answer,
  //    not how long our checker spent resolving the name. `start` still covers the
  //    DNS-failure branch's time-to-failure.
  const controller = new AbortController();
  // The deadline covers the WHOLE HTTP leg — headers AND body. Clearing it at
  // headers (as this once did) let a server that answers instantly and then
  // trickles its body forever hang the probe past every cycle budget: the worker
  // got terminated every tick, /health went stale, and the supervisor
  // restart-looped the container — one bad endpoint taking down the monitor.
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  const fetchStart = Date.now();
  try {
    const res = await fetch(svc.url, {
      method: "GET",
      signal: controller.signal,
      headers: { "User-Agent": USER_AGENT },
      redirect: "follow",
    });
    const responseTimeMs = Date.now() - fetchStart;
    const isHealthKind = svc.kind === "health";
    // The body is only read when something checks it (health JSON / the marker)
    // — the response-time measurement above is to HEADERS either way. An unread
    // body is CANCELLED so its socket returns to the pool instead of idling
    // half-open. The capped read runs under the same abort signal, so a body
    // failure or timeout lands in the catch below.
    const expectBody = svc.expectBody ?? null;
    let body: CappedBody | undefined;
    if (isHealthKind || expectBody) {
      body = await readBodyCapped(res, PROBE_BODY_MAX_BYTES, controller.signal);
    } else {
      await res.body?.cancel().catch(() => {});
    }
    // A body we could not READ tells us nothing about the content — fall back to
    // status-code classification (the pre-cap behaviour) rather than inventing an
    // outage from a broken stream on an otherwise-good 200.
    const bodyReadable = body != null && !body.failed;
    const bodyText = bodyReadable ? body!.text : undefined;
    const bodyMarkerMissing = bodyReadable && expectBody != null && !body!.text.includes(expectBody);
    const status = classify({
      statusCode: res.status,
      responseTimeMs,
      expectedStatus: svc.expectedStatus,
      isHealthKind,
      bodyText,
      bodyMarkerMissing,
    });
    // When the CAP is what hid the marker, say so: a bare "expected content not
    // found" is indistinguishable from a genuinely broken page, and an operator
    // has no other signal that PROBE_BODY_MAX_BYTES cut the search short.
    const markerError =
      bodyMarkerMissing && body!.truncated
        ? `expected content "${expectBody}" not found in the first ${Math.round(PROBE_BODY_MAX_BYTES / 1024)}KB (body truncated — marker may lie beyond the cap)`
        : `expected content "${expectBody}" not found in response`;
    return {
      slug: svc.slug,
      status,
      responseTimeMs,
      statusCode: res.status,
      error:
        status !== "down" ? null
        : bodyMarkerMissing && (res.status < 300 || res.status === svc.expectedStatus)
          ? markerError
          : `Unexpected status ${res.status}`,
      dnsOk: true,
    };
  } catch (err) {
    const responseTimeMs = Date.now() - fetchStart;
    const message = err instanceof Error ? err.message : "Unknown error";
    // The signal is the authoritative timeout marker (a body-read abort surfaces
    // as a stream error whose message doesn't say "abort"); the message/elapsed
    // checks stay as fallbacks for runtimes that word it differently.
    const isTimeout = controller.signal.aborted || message.includes("abort") || responseTimeMs >= timeoutMs;
    return {
      slug: svc.slug,
      status: "down",
      responseTimeMs: isTimeout ? timeoutMs : responseTimeMs,
      statusCode: null,
      error: isTimeout ? `Timeout after ${timeoutMs}ms` : message,
      dnsOk: true,
    };
  } finally {
    clearTimeout(timeout);
  }
}

/** Probe every endpoint in bounded-concurrency batches and return the raw results. */
export async function probeEndpoints(endpoints: ConfiguredEndpoint[]): Promise<Probe[]> {
  return mapLimit(endpoints, HEALTH_PROBE_CONCURRENCY, probe);
}
