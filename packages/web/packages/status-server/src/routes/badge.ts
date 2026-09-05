import { Hono } from 'hono';
import type { Db } from '../libsql/client';
import type { StatusConfig } from '../config/port';
import type { Tier } from '../middleware/auth';
import type { OverallStatus } from '../monitor/overall';
import { buildSnapshot } from './reads';

// Shields-style color palette — mirrors websites/main/status/src/lib/colors.ts OVERALL_COLORS.
const OVERALL_COLORS: Record<OverallStatus, string> = {
  operational: '#5cb270',
  degraded: '#d4a754',
  major_outage: '#d45454',
  unknown: '#d4a754',
};

// The right-hand label on the badge, per status.
const LABEL: Record<OverallStatus, string> = {
  operational: 'operational',
  degraded: 'degraded',
  major_outage: 'outage',
  unknown: 'unknown',
};

/** Build a shields-style SVG badge showing "status | <overall>" */
function buildSvg(overall: OverallStatus): string {
  const label = LABEL[overall];
  const color = OVERALL_COLORS[overall];

  const left = 'status';
  const cw = 6.5;
  const lw = Math.ceil(left.length * cw) + 12;
  const rw = Math.ceil(label.length * cw) + 12;
  const w = lw + rw;

  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="20" role="img" aria-label="status: ${label}">` +
    `<clipPath id="r"><rect width="${w}" height="20" rx="3" fill="#fff"/></clipPath>` +
    `<g clip-path="url(#r)">` +
    `<rect width="${lw}" height="20" fill="#555"/>` +
    `<rect x="${lw}" width="${rw}" height="20" fill="${color}"/>` +
    `</g>` +
    `<g fill="#fff" text-anchor="middle" font-family="Verdana,sans-serif" font-size="11">` +
    `<text x="${lw / 2}" y="14">${left}</text>` +
    `<text x="${lw + rw / 2}" y="14">${label}</text>` +
    `</g>` +
    `</svg>`
  );
}

/** Compute the 4-state OverallStatus from the compact snapshot, which collapses
 *  major_outage to 'down' — so we re-expand 'down' back to 'major_outage' for
 *  the badge label, and map 'healthy' back to 'operational'. */
function overallFromSnapshot(snap: Awaited<ReturnType<typeof buildSnapshot>>): OverallStatus {
  switch (snap.overall) {
    case 'healthy':
      return 'operational';
    case 'degraded':
      return 'degraded';
    case 'down':
      return 'major_outage';
  }
}

export function badgeRoutes(db: Db, config: StatusConfig): Hono<{ Variables: { tier: Tier } }> {
  const app = new Hono<{ Variables: { tier: Tier } }>();

  app.get('/status/badge.svg', async (c) => {
    let overall: OverallStatus;
    try {
      const snap = await buildSnapshot(db, config);
      overall = overallFromSnapshot(snap);
    } catch {
      overall = 'unknown';
    }
    const svg = buildSvg(overall);
    return c.newResponse(svg, 200, {
      'Content-Type': 'image/svg+xml',
      'Cache-Control': 'public, max-age=60',
    });
  });

  return app;
}
