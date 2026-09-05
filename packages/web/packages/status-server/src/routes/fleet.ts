import { Hono } from 'hono';
import type { Db } from '../libsql/client';
import type { StatusConfig } from '../config/port';
import type { Storage } from '../storage/ports';
import type { Tier } from '../middleware/auth';
import { buildSnapshot } from './reads';
import { assembleFleet } from '../peers/fleet';

export function fleetRoutes(db: Db, storage: Storage, config: StatusConfig): Hono<{ Variables: { tier: Tier } }> {
  const app = new Hono<{ Variables: { tier: Tier } }>();

  app.get('/fleet', async (c) => {
    const snap = await buildSnapshot(db, storage, config);
    const members = await assembleFleet(db, {
      label: config.monitorLabel,
      snapshot: snap,
      overall: snap.overall,
    });
    return c.json(members);
  });

  return app;
}
