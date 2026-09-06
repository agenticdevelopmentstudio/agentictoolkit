import { Hono } from 'hono';
import type { StatusConfig } from '../config/port';
import type { Storage } from '../storage/ports';
import type { Tier } from '../middleware/auth';
import { buildSnapshot } from './reads';
import { assembleFleet } from '../peers/fleet';

export function fleetRoutes(storage: Storage, config: StatusConfig): Hono<{ Variables: { tier: Tier } }> {
  const app = new Hono<{ Variables: { tier: Tier } }>();

  app.get('/fleet', async (c) => {
    const snap = await buildSnapshot(storage, config);
    const members = await assembleFleet(storage, {
      label: config.monitorLabel,
      snapshot: snap,
      overall: snap.overall,
    });
    return c.json(members);
  });

  return app;
}
