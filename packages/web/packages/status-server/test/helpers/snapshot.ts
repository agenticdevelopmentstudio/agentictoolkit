import type { LiveSnapshot } from '../../src/monitor/live-types';

/** A minimal, override-able LiveSnapshot for tests — the single source of the
 *  default shape so adding a required field touches one place, not every test. */
export function liveSnapshot(over: Partial<LiveSnapshot> = {}): LiveSnapshot {
  return {
    generatedAt: new Date().toISOString(),
    lastCycleAt: null,
    probeIntervalMs: 60_000,
    monitorVersion: null,
    services: [],
    deployments: [],
    staleProd: [],
    providers: {
      vercel: { configured: false, ok: true },
      'cloudflare-pages': { configured: false, ok: true },
      railway: { configured: false, ok: true },
      crunchy: { configured: false, ok: true },
    },
    configDegraded: false,
    configReason: null,
    ...over,
  };
}
