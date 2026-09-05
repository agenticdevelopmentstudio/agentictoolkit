import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { z } from 'zod';
import type { Db } from '../libsql/client';
import { requireAdmin, type AuthVars } from '../middleware/auth';
import { listUsers, setUserRoleGuarded, deleteUserGuarded } from '../storage/auth-store';

export const roleBody = z.object({ role: z.enum(['pending', 'viewer', 'admin']) });

/**
 * Admin user-management — the "Users" config topic. Mounted AFTER the requireAuth
 * seam and gated to admins. The last-admin guard makes it impossible to lock the
 * instance out of administration (you can't demote or delete the only admin).
 */
export function usersRoutes(db: Db): Hono<{ Variables: AuthVars }> {
  const app = new Hono<{ Variables: AuthVars }>();
  app.use('*', requireAdmin);

  app.get('/users', async (c) => c.json(await listUsers(db)));

  app.patch('/users/:id', async (c) => {
    const id = c.req.param('id');
    const body = await c.req.json().catch(() => {
      throw new HTTPException(400, { message: 'Invalid JSON' });
    });
    const parsed = roleBody.safeParse(body);
    if (!parsed.success) throw new HTTPException(400, { message: 'Invalid role' });
    const { role } = parsed.data;

    // The guard is INSIDE the write statement (see setUserRoleGuarded): a
    // read-then-write pair here let two concurrent demotes of two different
    // admins both pass and leave zero admins — a permanent lockout.
    const updated = await setUserRoleGuarded(db, id, role);
    if (updated === undefined) throw new HTTPException(404, { message: 'User not found' });
    if (updated === 'blocked') throw new HTTPException(409, { message: 'Cannot demote the last admin' });
    return c.json(updated);
  });

  app.delete('/users/:id', async (c) => {
    const id = c.req.param('id');
    const deleted = await deleteUserGuarded(db, id);
    if (deleted === false) throw new HTTPException(404, { message: 'User not found' });
    if (deleted === 'blocked') throw new HTTPException(409, { message: 'Cannot delete the last admin' });
    return c.json({ ok: true });
  });

  return app;
}
