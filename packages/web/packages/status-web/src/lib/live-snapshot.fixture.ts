import type { LiveSnapshot } from "./live-types";

/** A minimal, override-able LiveSnapshot for tests — the single source of the
 *  default shape so adding a required field touches one place, not every test. */
export function liveSnapshot(over: Partial<LiveSnapshot> = {}): LiveSnapshot {
  return {
    generatedAt: "2026-06-30T00:00:00.000Z",
    services: [],
    deployments: [],
    staleProd: [],
    providers: {
      vercel: { configured: true, ok: true },
      "cloudflare-pages": { configured: true, ok: true },
      railway: { configured: true, ok: true },
      crunchy: { configured: true, ok: true },
    },
    configDegraded: false,
    configReason: null,
    ...over,
  };
}
