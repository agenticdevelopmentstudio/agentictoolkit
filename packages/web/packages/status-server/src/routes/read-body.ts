import type { Context } from 'hono';
import { HTTPException } from 'hono/http-exception';

/** The minimal safeParse surface every route's zod schema satisfies. */
interface SafeParser<T> {
  safeParse(value: unknown): { success: true; data: T } | { success: false; error: unknown };
}

/**
 * Read + validate a JSON request body against `schema`. One place so every route
 * reports body errors the same way: 400 'invalid JSON' when the body isn't JSON,
 * 400 with the zod issue detail when it doesn't match the schema. Replaces the three
 * near-identical parse/parseBody/readJson variants that had drifted across routes.
 */
export async function readValidatedBody<T>(c: Context, schema: SafeParser<T>): Promise<T> {
  let raw: unknown;
  try {
    raw = await c.req.json();
  } catch {
    throw new HTTPException(400, { message: 'invalid JSON' });
  }
  const parsed = schema.safeParse(raw);
  if (!parsed.success) throw new HTTPException(400, { message: `Invalid request body: ${String(parsed.error)}` });
  return parsed.data;
}
