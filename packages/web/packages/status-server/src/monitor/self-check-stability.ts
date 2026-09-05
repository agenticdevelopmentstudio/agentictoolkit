import type { IntegrationCheck } from "./types";

/** Consecutive failing runs before an unreachable-kind failure is confirmed. */
export const CONFIRM_RUNS = 2;
/** Minimum wall-clock persistence before confirmation. The check runs on demand
 *  (every /integrations request), so a run count alone could be satisfied by two
 *  polls seconds apart inside one blip — the failure must also span real time. */
export const CONFIRM_WINDOW_MS = 90_000;
/** Confirmed-unreachable providers in ONE run at/above which the failure is treated
 *  as monitor-side connectivity rather than independent provider outages. */
export const CORRELATED_MIN = 2;

interface FailTrack {
  runs: number;
  firstFailedAtMs: number;
}

export interface SelfCheckStabilizer {
  stabilize(checks: IntegrationCheck[], nowMs?: number): IntegrationCheck[];
  reset(): void;
}

/**
 * Cross-run smoothing for the self-check, mirroring nextPlatformStreak's debounce for
 * platform-health issues: an `unreachable` failure (the probe got NO HTTP response)
 * is reported as healthy-with-a-note until it has persisted CONFIRM_RUNS consecutive
 * runs spanning CONFIRM_WINDOW_MS, so a momentary egress blip on the monitor's own
 * side never reaches the error bar. Failures that DID get an HTTP response (401/5xx —
 * token invalid and the like) pass through untouched: those are real, actionable
 * states. Recovery is not debounced — one good run clears the streak.
 *
 * When several providers are confirmed-unreachable in the SAME run, the outage is
 * almost certainly ours, not theirs: each is downgraded to a `correlated` warn and a
 * single synthetic Connectivity check names the real suspect, so the banner shows one
 * amber chip instead of a wall of red provider errors.
 */
export function createSelfCheckStabilizer(): SelfCheckStabilizer {
  const failing = new Map<string, FailTrack>();

  return {
    reset(): void {
      failing.clear();
    },

    stabilize(checks: IntegrationCheck[], nowMs: number = Date.now()): IntegrationCheck[] {
      const confirmed = new Set<string>();
      const out = checks.map((check) => {
        if (!(check.unreachable && check.state === "error")) {
          failing.delete(check.id);
          return check;
        }
        const prev = failing.get(check.id);
        const track: FailTrack = prev
          ? { runs: prev.runs + 1, firstFailedAtMs: prev.firstFailedAtMs }
          : { runs: 1, firstFailedAtMs: nowMs };
        failing.set(check.id, track);
        if (track.runs >= CONFIRM_RUNS && nowMs - track.firstFailedAtMs >= CONFIRM_WINDOW_MS) {
          confirmed.add(check.id);
          return check;
        }
        // Not yet confirmed — report healthy so the bar stays quiet, but keep the
        // failure text (and the unreachable tag) visible on the integrations panel.
        return { ...check, ok: true, state: "ok" as const, detail: `recheck pending — ${check.detail}` };
      });

      if (confirmed.size < CORRELATED_MIN) return out;

      const downgraded: IntegrationCheck[] = out.map((check) =>
        confirmed.has(check.id) ? { ...check, state: "warn" as const, correlated: true } : check,
      );
      downgraded.push({
        id: "connectivity",
        label: "Connectivity",
        configured: true,
        ok: false,
        state: "warn",
        detail: `${confirmed.size} providers unreachable at once — likely monitor-side connectivity, not provider outages`,
      });
      return downgraded;
    },
  };
}
