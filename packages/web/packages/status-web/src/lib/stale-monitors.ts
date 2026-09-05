import type { LiveServiceDTO } from "./live-types";

// ---------------------------------------------------------------------------
// Stale-monitor selection — the AMBIGUOUS half of ghost cleanup, and only that half.
// A monitor whose thing provably stopped existing is not offered here at all: the backend
// cycle deletes it outright, because no platform lists the project it names or serves the
// host it watches (`endpointsClaimedByNothing`, applied by `retireUnclaimedMonitors` in
// src/monitor/sync). What's left is the case no inventory settles — a monitor that is still
// claimed by a live deploy project but has been DOWN for a week. That may be a site nobody
// turned off, or an outage nobody fixed, and only its operator knows which, so it's
// surfaced for a one-click retire rather than removed.
//
// DNS is not part of that split, in either direction. A name that stopped resolving is not
// evidence the deployment was deleted (nor is resolving evidence it exists), so it neither
// triggers the automatic removal nor withholds this offer — it is one more way a monitor
// can be down, and it shows up in the row's `detail` like any other.
// Pure function of (services, now) so the rule is unit-testable.
// ---------------------------------------------------------------------------

/** How long a monitor must be continuously DOWN before it's offered for retirement.
 *  7 days: a genuine outage lasting this long is essentially unheard of, so an endpoint
 *  still failing at this age is almost always something nobody is coming back to. Purely a
 *  VIEW threshold: it decides what to OFFER, and the operator decides each row. Nothing the
 *  backend deletes is on any clock — a project is either in the inventory or it isn't. */
export const STALE_MONITOR_MS = 7 * 24 * 60 * 60 * 1000;

export interface StaleMonitor {
  /** Endpoint id — the delete target (the live service `slug`). */
  slug: string;
  name: string;
  url: string;
  environment: string | null;
  /** Why it's down — e.g. "HTTP 500". */
  detail: string;
  /** Whether the host still resolves. Explanatory only — it selects nothing (see the header:
   *  DNS decides no removal, automatic or offered). The banner reads it to word the confirm,
   *  so a prompt never claims a host "still resolves" when its own row says it doesn't. */
  dnsOk: boolean;
  downSince: string; // ISO (server-truth)
  ageMs: number;
}

/**
 * Endpoints down for at least `thresholdMs` — the retire candidates, longest-down first.
 * Pure. Retiring is a single `deleteEndpoint(slug)` call (the backend drops the now-empty
 * site atomically), so no site/ownership data is needed here. A non-finite age (a
 * malformed/absent `downSince`) is treated as "can't judge" and skipped, so a bad timestamp
 * can never surface a live monitor as a retire candidate.
 *
 * Every down-for-a-week endpoint on the board is offered, whether or not its host resolves.
 * Anything the platform inventory condemns has already been deleted by the cycle without a
 * banner; what remains is by definition still claimed by something, so no row here is
 * "about to vanish on its own" and withholding one would just leave it unremovable.
 */
export function selectStaleMonitors(
  services: readonly LiveServiceDTO[],
  nowMs: number,
  thresholdMs: number = STALE_MONITOR_MS,
): StaleMonitor[] {
  const out: StaleMonitor[] = [];
  for (const s of services) {
    if (s.status !== "down" || !s.downSince) continue;
    const ageMs = nowMs - Date.parse(s.downSince);
    if (!Number.isFinite(ageMs) || ageMs < thresholdMs) continue;
    out.push({
      slug: s.slug,
      name: s.name,
      url: s.url,
      environment: s.environment || null,
      detail: s.error ?? (s.statusCode != null ? `HTTP ${s.statusCode}` : "down"),
      dnsOk: s.dnsOk,
      downSince: s.downSince,
      ageMs,
    });
  }
  out.sort((a, b) => b.ageMs - a.ageMs);
  return out;
}
