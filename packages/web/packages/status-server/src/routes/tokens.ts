import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { z } from 'zod';
import type { Db } from '../libsql/client';
import { requireAdmin, type AuthVars } from '../middleware/auth';
import { mintApiToken, listApiTokens, revokeApiToken } from '../storage/token-store';
import { readValidatedBody } from './read-body';

export const createSchema = z.object({
  name: z.string().min(1).max(100),
  role: z.enum(['admin', 'user']),
  expiresAt: z.iso.datetime().nullish(),
});

/**
 * API-token management (mint / list / revoke). Mounted AFTER the requireAuth
 * seam. The raw token value is returned exactly once, on creation. Minting
 * requires a SESSION admin — a token cannot mint another token (the simplest
 * honest `created_by`), so under AUTH_DISABLED (no session user) and for a token
 * principal alike, POST is 403. A token may, however, revoke ITSELF.
 */
export function tokensRoutes(db: Db): Hono<{ Variables: AuthVars }> {
  const app = new Hono<{ Variables: AuthVars }>();

  app.post('/tokens', requireAdmin, async (c) => {
    const user = c.get('user');
    // requireAdmin admits a session admin, an admin token, and (under
    // AUTH_DISABLED) an anonymous admin. Only a SESSION user may mint — tokens
    // cannot mint tokens, and AUTH_DISABLED has no honest `created_by`.
    if (!user) {
      throw new HTTPException(403, { message: 'Minting a token requires a signed-in admin user' });
    }
    const { name, role, expiresAt } = await readValidatedBody(c, createSchema);
    const { meta, raw } = await mintApiToken(db, {
      name,
      role,
      createdBy: user.id,
      expiresAt: expiresAt ? new Date(expiresAt) : null,
    });
    // The raw token is returned exactly once here; never let a cache retain it.
    c.header('Cache-Control', 'no-store');
    return c.json({ ...meta, token: raw }, 201);
  });

  app.get('/tokens', requireAdmin, async (c) => {
    const tokens = await listApiTokens(db);
    // Credential metadata (ids, prefixes) — keep it out of shared caches.
    c.header('Cache-Control', 'no-store');
    return c.json(tokens);
  });

  app.delete('/tokens/:id', async (c) => {
    const id = c.req.param('id');
    // Admins revoke any token; a token bearer may always revoke ITSELF (its own
    // id), regardless of its role — the CLI/device kill switch.
    const isAdmin = c.get('tier') === 'admin';
    const isSelf = c.get('token')?.id === id;
    if (!isAdmin && !isSelf) throw new HTTPException(403, { message: 'Admin required' });
    const ok = await revokeApiToken(db, id);
    if (!ok) throw new HTTPException(404, { message: 'token not found' });
    return c.body(null, 204);
  });

  return app;
}
