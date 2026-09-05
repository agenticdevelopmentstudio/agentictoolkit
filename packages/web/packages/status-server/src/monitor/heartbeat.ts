// The dead-man's switch. Every layer of the self-healing chain — cycle
// watchdog, worker terminate/respawn, supervisor health-watch, Railway restart
// policy — lives INSIDE the container. When the container itself dies (volume
// failure, platform outage, restartPolicyMaxRetries exhausted) nothing tells
// anyone: the monitor that watches everything has no watcher.
//
// The fix is push-based: each successful FULL sync pings HEARTBEAT_URL (a
// healthchecks.io-style check-in endpoint). The external service alerts on a
// MISSED ping, which covers every way the monitor can die — including the ways
// no in-container code could ever report. Full syncs run every ~5min, so set
// the external grace period to ~2-3 intervals.
//
// Unset HEARTBEAT_URL = feature off (local dev, tests).

const HEARTBEAT_TIMEOUT_MS = 5_000;

/** Check in with the external dead-man monitor. Fail-soft and bounded: a slow
 *  or failing heartbeat endpoint must never fail (or stall) the cycle that is
 *  trying to report its own success. `url` is `config.heartbeatUrl` — this
 *  module takes no default and never reads env itself. */
export async function pingHeartbeat(url: string | null): Promise<void> {
  if (!url) return;
  try {
    const res = await fetch(url, {
      method: 'GET',
      signal: AbortSignal.timeout(HEARTBEAT_TIMEOUT_MS),
      headers: { 'User-Agent': 'AgenticDeveloperHubStatus/1.0' },
    });
    // fetch() only REJECTS on a network-level failure: a 404 from a typo'd or
    // deleted check-in URL resolves happily. Without this check every cycle
    // would believe it checked in while the external dead-man service never saw
    // a valid ping — the watchdog silently never arms, which is precisely the
    // blind spot this file exists to remove.
    if (!res.ok) {
      console.error(`[heartbeat] check-in URL answered ${res.status} — the dead-man ping is NOT registering; verify HEARTBEAT_URL`);
    }
  } catch (err) {
    console.error(`[heartbeat] ping failed: ${err instanceof Error ? err.message : String(err)}`);
  }
}
