import { Hono } from 'hono';
import type { Db } from '../libsql/client';
import type { StatusConfig } from '../config/port';
import type { Tier } from '../middleware/auth';
import { buildSnapshot } from './reads';
import { assembleFleet } from '../peers/fleet';

export function fleetRoutes(db: Db, config: StatusConfig): Hono<{ Variables: { tier: Tier } }> {
  const app = new Hono<{ Variables: { tier: Tier } }>();

  app.get('/fleet', async (c) => {
    const snap = await buildSnapshot(db, config);
    const members = await assembleFleet(db, {
      label: config.monitorLabel,
      snapshot: snap,
      overall: snap.overall,
    });
    return c.json(members);
  });

  return app;
}
