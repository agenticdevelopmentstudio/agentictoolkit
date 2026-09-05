import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { requireAdmin, type Tier } from '../middleware/auth';
import type { Scheduler } from '../scheduler';
import type { Db } from '../libsql/client';
import { runMaintenance } from '../monitor/sync';

export function cronRoutes(db: Db, scheduler: Scheduler): OpenAPIHono<{ Variables: { tier: Tier } }> {
  const app = new OpenAPIHono<{ Variables: { tier: Tier } }>();
  const ok = {
    200: { description: 'ok', content: { 'application/json': { schema: z.object({ ok: z.boolean() }) } } },
  };
  const pruned = {
    200: {
      description: 'ok',
      content: {
        'application/json': {
          schema: z.object({ ok: z.boolean(), deleted: z.number(), done: z.boolean() }),
        },
      },
    },
  };
  app.use('/cron/*', requireAdmin);
  app.openapi(
    createRoute({ method: 'post', path: '/cron/refresh', tags: ['cron'], responses: ok }),
    async (c) => {
      await scheduler.runNow();
      return c.json({ ok: true });
    },
  );
  // The scheduler prunes on every full sync (index.ts); this route stays as the manual
  // lever. Both are bounded per call, so a long backlog drains over successive runs —
  // `done:false` means there is more to clear.
  app.openapi(
    createRoute({ method: 'post', path: '/cron/maintenance', tags: ['cron'], responses: pruned }),
    async (c) => {
      const { deleted, done } = await runMaintenance(db);
      return c.json({ ok: true, deleted, done });
    },
  );
  return app;
}
